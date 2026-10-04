using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

// Skin Studio per-texture op engine.
// All loads go through a fully-decoded MemoryStream copy so GDI+ never keeps a
// file lock or a lazy decoder alive (the bg2 clone-lock failure mode).
public static class SkinArt {

    // parallel fan-out cap for the pixel loops / thumb batches; 0 = let TPL
    // decide. Set from PowerShell (SS-SetArtWorkers) so it stays game-aware.
    public static int MaxWorkers = 0;

    static ParallelOptions POpts() {
        ParallelOptions po = new ParallelOptions();
        if (MaxWorkers > 0) po.MaxDegreeOfParallelism = MaxWorkers;
        return po;
    }

    public static Bitmap Load(string path) {
        byte[] bytes = File.ReadAllBytes(path);
        using (MemoryStream ms = new MemoryStream(bytes))
        using (Bitmap tmp = new Bitmap(ms)) {
            Bitmap copy = new Bitmap(tmp.Width, tmp.Height, PixelFormat.Format32bppArgb);
            using (Graphics gr = Graphics.FromImage(copy)) {
                gr.CompositingMode = CompositingMode.SourceCopy;
                gr.DrawImage(tmp, 0, 0, tmp.Width, tmp.Height);
            }
            return copy;
        }
    }

    public static void SavePng(Bitmap bmp, string path) {
        string dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        bmp.Save(path, ImageFormat.Png);
    }

    // ---- gamma-faithful PNG save --------------------------------------------
    // ddstools exports linear-flagged game textures as PNGs tagged gAMA=1.0 and
    // no sRGB chunk; GDI+ always writes gAMA=0.4545 + sRGB. texconv honors the
    // tags on inject and would bake an sRGB->linear conversion into the DDS
    // (the "Luna dark skin" bug). So every PNG destined for injection is saved
    // with its color chunks rewritten to MATCH the vanilla source PNG.
    static uint[] crcTable;
    static uint Crc32(byte[] data, int off, int len) {
        if (crcTable == null) {
            crcTable = new uint[256];
            for (uint i = 0; i < 256; i++) {
                uint c = i;
                for (int k = 0; k < 8; k++) c = ((c & 1) != 0) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                crcTable[i] = c;
            }
        }
        uint crc = 0xFFFFFFFFu;
        for (int i = off; i < off + len; i++) crc = crcTable[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
        return crc ^ 0xFFFFFFFFu;
    }

    static uint BE32(byte[] b, int off) {
        return ((uint)b[off] << 24) | ((uint)b[off + 1] << 16) | ((uint)b[off + 2] << 8) | b[off + 3];
    }

    // scan a PNG for its color-space tagging: gAMA value (0 = absent) and sRGB presence
    static void PngColorTags(byte[] png, out uint gama, out bool hasSrgb) {
        gama = 0; hasSrgb = false;
        int pos = 8;
        while (pos + 12 <= png.Length) {
            uint len = BE32(png, pos);
            string typ = System.Text.Encoding.ASCII.GetString(png, pos + 4, 4);
            if (typ == "gAMA" && len >= 4) gama = BE32(png, pos + 8);
            else if (typ == "sRGB") hasSrgb = true;
            else if (typ == "IEND") break;
            pos += 12 + (int)len;
        }
    }

    static void WriteChunk(MemoryStream outMs, string typ, byte[] data) {
        byte[] head = new byte[8 + data.Length];
        uint len = (uint)data.Length;
        head[0] = (byte)(len >> 24); head[1] = (byte)(len >> 16); head[2] = (byte)(len >> 8); head[3] = (byte)len;
        byte[] tb = System.Text.Encoding.ASCII.GetBytes(typ);
        Array.Copy(tb, 0, head, 4, 4);
        Array.Copy(data, 0, head, 8, data.Length);
        uint crc = Crc32(head, 4, 4 + data.Length);
        outMs.Write(head, 0, head.Length);
        outMs.WriteByte((byte)(crc >> 24)); outMs.WriteByte((byte)(crc >> 16));
        outMs.WriteByte((byte)(crc >> 8)); outMs.WriteByte((byte)crc);
    }

    public static void SavePngLike(Bitmap bmp, string path, string likePng) {
        string dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        uint wantGama = 0; bool wantSrgb = false;
        if (!string.IsNullOrEmpty(likePng) && File.Exists(likePng))
            PngColorTags(File.ReadAllBytes(likePng), out wantGama, out wantSrgb);

        byte[] enc;
        using (MemoryStream ms = new MemoryStream()) { bmp.Save(ms, ImageFormat.Png); enc = ms.ToArray(); }

        using (MemoryStream outMs = new MemoryStream()) {
            outMs.Write(enc, 0, 8);                       // signature
            bool gamaDone = false;
            int pos = 8;
            while (pos + 12 <= enc.Length) {
                uint len = BE32(enc, pos);
                string typ = System.Text.Encoding.ASCII.GetString(enc, pos + 4, 4);
                int tot = 12 + (int)len;
                bool copy = true;
                if (typ == "sRGB" && !wantSrgb) copy = false;
                else if (typ == "cHRM") copy = false;
                else if (typ == "gAMA") {
                    copy = false; gamaDone = true;
                    if (wantGama != 0)
                        WriteChunk(outMs, "gAMA", new byte[] {
                            (byte)(wantGama >> 24), (byte)(wantGama >> 16), (byte)(wantGama >> 8), (byte)wantGama });
                } else if (typ == "IDAT" && !gamaDone) {
                    gamaDone = true;
                    if (wantGama != 0)
                        WriteChunk(outMs, "gAMA", new byte[] {
                            (byte)(wantGama >> 24), (byte)(wantGama >> 16), (byte)(wantGama >> 8), (byte)wantGama });
                }
                if (copy) outMs.Write(enc, pos, tot);
                pos += tot;
                if (typ == "IEND") break;
            }
            File.WriteAllBytes(path, outMs.ToArray());
        }
    }

    // ---- live preview PNG ---------------------------------------------------
    // The in-game menu loads these through KismetRenderingLibrary.ImportFileAsTexture2D,
    // which hands back an sRGB-flagged transient texture. Character colour maps
    // are LINEAR-flagged, so the shader would apply an sRGB->linear read that the
    // vanilla texture never gets - the Luna darkening again, at preview time.
    // Writing lin->sRGB here cancels it exactly, so the preview matches the mod.
    //   "srgb"   encode lin->sRGB  (default: D/E maps are linear-flagged)
    //   "linear" decode sRGB->lin  (if a map turns out to be sRGB-flagged)
    //   "none"   pass the pixels through untouched
    // 8-bit in, 8-bit out, so a 256-entry LUT is exact and costs nothing.
    // Alpha is data, never gamma-mapped.
    public static void SaveLivePng(Bitmap bmp, string path, string gamma) {
        string dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        string g = (gamma == null ? "none" : gamma.ToLowerInvariant());
        if (g != "srgb" && g != "linear") { bmp.Save(path, ImageFormat.Png); return; }

        byte[] lut = new byte[256];
        for (int i = 0; i < 256; i++) {
            double v = i / 255.0;
            double o = (g == "srgb") ? LinearToSrgb(v) : SrgbToLinear(v);
            int b = (int)Math.Round(o * 255.0);
            lut[i] = (byte)(b < 0 ? 0 : (b > 255 ? 255 : b));
        }

        Rectangle rc = new Rectangle(0, 0, bmp.Width, bmp.Height);
        using (Bitmap outB = new Bitmap(bmp.Width, bmp.Height, PixelFormat.Format32bppArgb)) {
            BitmapData src = bmp.LockBits(rc, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            BitmapData dst = outB.LockBits(rc, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            try {
                int rowBytes = bmp.Width * 4;
                byte[] row = new byte[rowBytes];
                for (int y = 0; y < bmp.Height; y++) {
                    Marshal.Copy((IntPtr)(src.Scan0.ToInt64() + (long)y * src.Stride), row, 0, rowBytes);
                    for (int i = 0; i < rowBytes; i += 4) {      // BGRA
                        row[i]     = lut[row[i]];
                        row[i + 1] = lut[row[i + 1]];
                        row[i + 2] = lut[row[i + 2]];
                    }
                    Marshal.Copy(row, 0, (IntPtr)(dst.Scan0.ToInt64() + (long)y * dst.Stride), rowBytes);
                }
            } finally {
                bmp.UnlockBits(src);
                outB.UnlockBits(dst);
            }
            outB.Save(path, ImageFormat.Png);
        }
    }

    // sampled mean absolute luminance difference between two same-size images -
    // the post-build drift check (BC compression noise is ~1-2, a gamma bake ~60)
    public static double AvgLumDiff(string pathA, string pathB, int grid) {
        using (Bitmap a = Load(pathA))
        using (Bitmap b = Load(pathB)) {
            int w = Math.Min(a.Width, b.Width), h = Math.Min(a.Height, b.Height);
            int step = Math.Max(1, Math.Min(w, h) / Math.Max(8, grid));
            double sum = 0; int n = 0;
            for (int x = step / 2; x < w; x += step)
                for (int y = step / 2; y < h; y += step) {
                    Color pa = a.GetPixel(x, y), pb = b.GetPixel(x, y);
                    double la = 0.299 * pa.R + 0.587 * pa.G + 0.114 * pa.B;
                    double lb = 0.299 * pb.R + 0.587 * pb.G + 0.114 * pb.B;
                    sum += Math.Abs(la - lb); n++;
                }
            return (n > 0) ? sum / n : 0;
        }
    }

    // PNG dims straight from the IHDR header - no decode. Falls back to a full
    // load for anything that isn't a well-formed PNG.
    public static int[] Size(string path) {
        try {
            using (FileStream fs = File.OpenRead(path)) {
                byte[] head = new byte[24];
                if (fs.Read(head, 0, 24) == 24 &&
                    head[0] == 0x89 && head[1] == 0x50 && head[2] == 0x4E && head[3] == 0x47 &&
                    head[12] == (byte)'I' && head[13] == (byte)'H' && head[14] == (byte)'D' && head[15] == (byte)'R') {
                    int w = (head[16] << 24) | (head[17] << 16) | (head[18] << 8) | head[19];
                    int h = (head[20] << 24) | (head[21] << 16) | (head[22] << 8) | head[23];
                    if (w > 0 && h > 0) return new int[] { w, h };
                }
            }
        } catch {}
        using (Bitmap b = Load(path)) return new int[] { b.Width, b.Height };
    }

    // Fit-inside thumbnail (also used for the 512px preview bases).
    public static void Thumb(string src, string dst, int max) {
        using (Bitmap b = Load(src)) {
            double sc = Math.Min((double)max / b.Width, (double)max / b.Height);
            if (sc > 1.0) sc = 1.0;
            int w = Math.Max(1, (int)Math.Round(b.Width * sc));
            int h = Math.Max(1, (int)Math.Round(b.Height * sc));
            using (Bitmap outB = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
                using (Graphics gr = Graphics.FromImage(outB)) {
                    gr.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    gr.DrawImage(b, 0, 0, w, h);
                }
                SavePng(outB, dst);
            }
        }
    }

    // Thumb over many files at once, one worker per file (each thread owns its
    // own Bitmaps - GDI+ is safe per-object). Returns interleaved dims
    // [w0,h0,w1,h1,...] so the caller never has to decode again for sizes.
    public static int[] ThumbBatch(string[] srcs, string[] dsts, int max) {
        int[] dims = new int[srcs.Length * 2];
        Parallel.For(0, srcs.Length, POpts(), delegate(int k) {
            using (Bitmap b = Load(srcs[k])) {
                dims[k * 2] = b.Width; dims[k * 2 + 1] = b.Height;
                double sc = Math.Min((double)max / b.Width, (double)max / b.Height);
                if (sc > 1.0) sc = 1.0;
                int w = Math.Max(1, (int)Math.Round(b.Width * sc));
                int h = Math.Max(1, (int)Math.Round(b.Height * sc));
                using (Bitmap outB = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
                    using (Graphics gr = Graphics.FromImage(outB)) {
                        gr.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        gr.DrawImage(b, 0, 0, w, h);
                    }
                    SavePng(outB, dsts[k]);
                }
            }
        });
        return dims;
    }

    // ---- HSL helpers (0..1 rgb, h in degrees) --------------------------------
    static void RgbToHsl(double r, double g, double b, out double h, out double s, out double l) {
        double mx = Math.Max(r, Math.Max(g, b)), mn = Math.Min(r, Math.Min(g, b));
        l = (mx + mn) / 2.0; h = 0; s = 0;
        if (mx > mn) {
            double d = mx - mn;
            s = d / (1.0 - Math.Abs(2.0 * l - 1.0) + 1e-9);
            if (mx == r) h = 60.0 * (((g - b) / d) % 6.0);
            else if (mx == g) h = 60.0 * (((b - r) / d) + 2.0);
            else h = 60.0 * (((r - g) / d) + 4.0);
            if (h < 0) h += 360.0;
        }
    }

    static double HueChan(double p, double q, double t) {
        if (t < 0) t += 1; if (t > 1) t -= 1;
        if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
        if (t < 0.5) return q;
        if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
        return p;
    }

    static void HslToRgb(double h, double s, double l, out double r, out double g, out double b) {
        s = Math.Max(0, Math.Min(1, s)); l = Math.Max(0, Math.Min(1, l));
        h = h % 360.0; if (h < 0) h += 360.0;
        if (s <= 0.0001) { r = g = b = l; return; }
        double q = (l < 0.5) ? l * (1 + s) : l + s - l * s;
        double p = 2 * l - q;
        double hk = h / 360.0;
        r = HueChan(p, q, hk + 1.0 / 3.0);
        g = HueChan(p, q, hk);
        b = HueChan(p, q, hk - 1.0 / 3.0);
    }

    // Warm-hue guard ported from the Luna LOD2 grade: faces, lips, most skin
    // tones sit in the warm band with some saturation - leave them untouched.
    static bool IsSkinTone(double h, double s, double l) {
        return (h < 58.0 || h > 342.0) && s > 0.08 && l > 0.06 && l < 0.97;
    }

    // ---- the one entry point -------------------------------------------------
    // mode: tint | paint | hueshift | hsl | gray | invert | replace | gradtint | gradpaint
    // hex:  #RRGGBB target for tint/paint; gradient color A for grad modes
    // strength: 0..1 blend with the original (replace included)
    // hueShift degrees, satMul / lightMul multipliers for hueshift/hsl
    // file2: replacement image path for replace
    // hex2..hex4 + gradDir: gradient stops. gradDir: v | h | diag | radial | corners
    //   (corners = 4-color mesh: A top-left, B top-right, C bottom-left, D bottom-right)
    // ---- the hue-family band -------------------------------------------------
    // The dominant saturated, non-skin hue in an image - the colour family a
    // "recolor color family" op falls back to when nothing was picked by hand.
    // Factored out so the picker's preview and the real render can never
    // disagree about where the band sits.
    static double AutoBandCenter(byte[] px, int stride, int w, int h) {
        double[] hist = new double[36];
        int total = h * w;
        int sstep = Math.Max(1, total / 40000);
        int scount = 0;
        for (int p = 0; p < total; p += sstep) {
            int yy = p / w, xx = p % w; int ii = yy * stride + xx * 4;
            double bb = px[ii] / 255.0, gg = px[ii + 1] / 255.0, rr = px[ii + 2] / 255.0;
            double hh, ss2, ll2; RgbToHsl(rr, gg, bb, out hh, out ss2, out ll2);
            if (ss2 < 0.18) continue;                                                          // skip near-gray
            if ((hh < 58.0 || hh > 342.0) && ss2 > 0.08 && ll2 > 0.06 && ll2 < 0.97) continue;  // skip skin/gold
            hist[((int)(hh / 10.0)) % 36] += 1; scount++;
        }
        if (scount == 0) return -1.0;
        int best = 0; for (int bkt = 1; bkt < 36; bkt++) if (hist[bkt] > hist[best]) best = bkt;
        return best * 10.0 + 5.0;
    }
    public static double AutoBandCenter(Bitmap src) {
        Rectangle r = new Rectangle(0, 0, src.Width, src.Height);
        BitmapData bd = src.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try {
            int stride = Math.Abs(bd.Stride);
            byte[] px = new byte[stride * src.Height];
            Marshal.Copy(bd.Scan0, px, 0, px.Length);
            return AutoBandCenter(px, stride, src.Width, src.Height);
        } finally { src.UnlockBits(bd); }
    }

    // fraction of the opaque pixels the last BandPreview selected (0..1)
    public static double LastCoverage = 0.0;

    // A picture of what the band selects: pixels inside keep their colour,
    // everything else drops to dim grey, feathered exactly the way the real op
    // feathers - so what you see selected is what gets recoloured. Call it on a
    // downscaled copy; it is O(pixels).
    public static Bitmap BandPreview(Bitmap src, double center, double half) {
        double fea = Math.Max(4.0, half * 0.38);
        Bitmap outB = new Bitmap(src.Width, src.Height, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(outB)) {
            g.CompositingMode = CompositingMode.SourceCopy;
            g.DrawImageUnscaled(src, 0, 0);
        }
        Rectangle rct = new Rectangle(0, 0, outB.Width, outB.Height);
        BitmapData bd = outB.LockBits(rct, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int stride = Math.Abs(bd.Stride);
        byte[] px = new byte[stride * outB.Height];
        Marshal.Copy(bd.Scan0, px, 0, px.Length);
        double inb = 0, tot = 0;
        for (int y = 0; y < outB.Height; y++) {
            int off = y * stride;
            for (int x = 0; x < outB.Width; x++) {
                int i = off + x * 4;
                if (px[i + 3] < 8) continue;
                tot++;
                double b0 = px[i] / 255.0, g0 = px[i + 1] / 255.0, r0 = px[i + 2] / 255.0;
                double hh, ss, ll; RgbToHsl(r0, g0, b0, out hh, out ss, out ll);
                double diff = Math.Abs(hh - center) % 360.0; if (diff > 180.0) diff = 360.0 - diff;
                double wgt;
                if (diff <= half) wgt = 1.0;
                else if (diff <= half + fea) wgt = 0.5 - 0.5 * Math.Cos(Math.PI * ((half + fea) - diff) / fea);
                else wgt = 0.0;
                inb += wgt;
                if (wgt < 0.999) {
                    double lum = 0.299 * r0 + 0.587 * g0 + 0.114 * b0;
                    double d = lum * 0.35 + 0.06;
                    double nr = d + (r0 - d) * wgt, ng = d + (g0 - d) * wgt, nb = d + (b0 - d) * wgt;
                    px[i]     = (byte)Math.Max(0, Math.Min(255, (int)Math.Round(nb * 255.0)));
                    px[i + 1] = (byte)Math.Max(0, Math.Min(255, (int)Math.Round(ng * 255.0)));
                    px[i + 2] = (byte)Math.Max(0, Math.Min(255, (int)Math.Round(nr * 255.0)));
                }
            }
        }
        Marshal.Copy(px, 0, bd.Scan0, px.Length);
        outB.UnlockBits(bd);
        LastCoverage = (tot > 0) ? inb / tot : 0.0;
        return outB;
    }

    public static void Apply(string src, string dst, string mode, string hex,
                             double strength, double hueShift, double satMul, double lightMul,
                             string file2, bool protectSkin) {
        Apply(src, dst, mode, hex, strength, hueShift, satMul, lightMul, file2, protectSkin,
              "", "", "", "v");
    }

    public static void Apply(string src, string dst, string mode, string hex,
                             double strength, double hueShift, double satMul, double lightMul,
                             string file2, bool protectSkin,
                             string hex2, string hex3, string hex4, string gradDir) {
        Apply(src, dst, mode, hex, strength, hueShift, satMul, lightMul, file2, protectSkin,
              hex2, hex3, hex4, gradDir, -1.0, 0.0);
    }

    public static void Apply(string src, string dst, string mode, string hex,
                             double strength, double hueShift, double satMul, double lightMul,
                             string file2, bool protectSkin,
                             string hex2, string hex3, string hex4, string gradDir,
                             double bandCenterIn, double bandWidth) {
        using (Bitmap baseB = Load(src)) {
            Bitmap outB = ApplyBitmap(baseB, mode, hex, strength, hueShift, satMul, lightMul,
                                      file2, protectSkin, hex2, hex3, hex4, gradDir,
                                      bandCenterIn, bandWidth);
            try { SavePngLike(outB, dst, src); }
            finally { if (!object.ReferenceEquals(outB, baseB)) outB.Dispose(); }
        }
    }

    // In-memory core: mutates baseB in place and returns it - except "replace",
    // which builds and returns a NEW bitmap (caller disposes whichever it owns).
    // Layer stacks chain through this without any intermediate PNG encodes.
    public static Bitmap ApplyBitmap(Bitmap baseB, string mode, string hex,
                             double strength, double hueShift, double satMul, double lightMul,
                             string file2, bool protectSkin,
                             string hex2, string hex3, string hex4, string gradDir) {
        return ApplyBitmap(baseB, mode, hex, strength, hueShift, satMul, lightMul,
                           file2, protectSkin, hex2, hex3, hex4, gradDir, -1.0, 0.0);
    }

    // bandCenterIn: hue 0-360 for "huerange", or < 0 to auto-detect.
    // bandWidth:    half-width in degrees, or <= 0 for the 34 default.
    public static Bitmap ApplyBitmap(Bitmap baseB, string mode, string hex,
                             double strength, double hueShift, double satMul, double lightMul,
                             string file2, bool protectSkin,
                             string hex2, string hex3, string hex4, string gradDir,
                             double bandCenterIn, double bandWidth) {
        if (strength < 0) strength = 0; if (strength > 1) strength = 1;
        if (mode == "replace") {
            if (string.IsNullOrEmpty(file2) || !File.Exists(file2))
                throw new IOException("replacement image not found: " + file2);
            Bitmap repOut = new Bitmap(baseB.Width, baseB.Height, PixelFormat.Format32bppArgb);
            using (Bitmap rep = Load(file2))
            using (Graphics gr = Graphics.FromImage(repOut)) {
                gr.CompositingMode = CompositingMode.SourceCopy;
                gr.InterpolationMode = InterpolationMode.HighQualityBicubic;
                // stretch to the vanilla canvas - UVs map 1:1, aspect is the asset's problem
                gr.DrawImage(rep, 0, 0, baseB.Width, baseB.Height);
            }
            if (strength < 0.999) BlendInto(repOut, baseB, strength);
            return repOut;
        }

        Color target = Color.White;
        if (!string.IsNullOrEmpty(hex)) target = ColorTranslator.FromHtml(hex);
        double th0, ts0, tl0;
        RgbToHsl(target.R / 255.0, target.G / 255.0, target.B / 255.0, out th0, out ts0, out tl0);

        bool isGrad = (mode == "gradtint" || mode == "gradpaint");
        Color gB = target, gC = target, gD = target;
        if (!string.IsNullOrEmpty(hex2)) gB = ColorTranslator.FromHtml(hex2);
        if (!string.IsNullOrEmpty(hex3)) gC = ColorTranslator.FromHtml(hex3); else gC = target;
        if (!string.IsNullOrEmpty(hex4)) gD = ColorTranslator.FromHtml(hex4); else gD = gB;
        int imgW = baseB.Width, imgH = baseB.Height;

        Rectangle rect = new Rectangle(0, 0, imgW, imgH);
        BitmapData bd = baseB.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int stride = Math.Abs(bd.Stride);
        int nBytes = stride * imgH;
        byte[] px = new byte[nBytes];
        Marshal.Copy(bd.Scan0, px, 0, nBytes);

        // huerange: which hue family gets recolored. bandCenterIn < 0 means
        // "work it out" - the dominant saturated, non-skin hue, which is right
        // for a texture with one obvious colour family. It is NOT right for a
        // shared atlas (a cap, badges, a red top, a tie and headphones on one
        // sheet), so the studio can hand a centre in instead: see BandPreview
        // and the Colour-family picker.
        double bandCenter = (bandCenterIn >= 0) ? bandCenterIn : th0;
        if (mode == "huerange" && bandCenterIn < 0) {
            double auto = AutoBandCenter(px, stride, imgW, imgH);
            if (auto >= 0) bandCenter = auto;
        }
        double bandHalf = (bandWidth > 0) ? bandWidth : 34.0;
        // the feather stays proportional, so a narrow band still has a soft edge
        double bandFea = Math.Max(4.0, bandHalf * 0.38);

        // Rows fan out across cores (POpts caps it, game-aware). For the
        // spatially-uniform modes the output is a pure function of the input
        // RGB, and game textures repeat colors heavily - so each worker keeps
        // a private memo of colors it has already converted.
        bool useMemo = !isGrad;
        double sMode = strength; string m = mode; bool pSkin = protectSkin;
        double hShift = hueShift, sMul = satMul, lMul = lightMul;
        string gDir = gradDir;

        Parallel.For<Dictionary<int, int>>(0, imgH, POpts(),
            delegate { return new Dictionary<int, int>(); },
            delegate(int y, ParallelLoopState st, Dictionary<int, int> memo) {
                int rowOff = y * stride;
                for (int xI = 0; xI < imgW; xI++) {
                    int i = rowOff + xI * 4;
                    byte bIn = px[i], gIn = px[i + 1], rIn = px[i + 2];
                    int key = bIn | (gIn << 8) | (rIn << 16);
                    int packed;
                    if (useMemo && memo.TryGetValue(key, out packed)) {
                        px[i] = (byte)packed; px[i + 1] = (byte)(packed >> 8); px[i + 2] = (byte)(packed >> 16);
                        continue;
                    }
                    double b0 = bIn / 255.0, g0 = gIn / 255.0, r0 = rIn / 255.0;
                    double h, s, l;
                    RgbToHsl(r0, g0, b0, out h, out s, out l);
                    if (pSkin && IsSkinTone(h, s, l)) {
                        // byte-exact skip (matching the pre-parallel engine)
                        if (useMemo) memo[key] = key;
                        continue;
                    }
                    double r1 = r0, g1 = g0, b1 = b0;
                    {
                        double tH = th0, tS = ts0, tL = tl0;
                        if (isGrad) {
                            // spatially varying target color in UV space
                            double u = (imgW > 1) ? xI / (double)(imgW - 1) : 0;
                            double v = (imgH > 1) ? y / (double)(imgH - 1) : 0;
                            double gr, gg2, gb2;
                            if (gDir == "corners") {
                                // bilinear 4-color mesh: A(tl) B(tr) C(bl) D(br)
                                gr  = ((target.R * (1 - u) + gB.R * u) * (1 - v) + (gC.R * (1 - u) + gD.R * u) * v) / 255.0;
                                gg2 = ((target.G * (1 - u) + gB.G * u) * (1 - v) + (gC.G * (1 - u) + gD.G * u) * v) / 255.0;
                                gb2 = ((target.B * (1 - u) + gB.B * u) * (1 - v) + (gC.B * (1 - u) + gD.B * u) * v) / 255.0;
                            } else {
                                double t;
                                if (gDir == "h") t = u;
                                else if (gDir == "diag") t = (u + v) / 2.0;
                                else if (gDir == "radial") {
                                    double dx = u - 0.5, dy = v - 0.5;
                                    t = Math.Min(1.0, Math.Sqrt(dx * dx + dy * dy) / 0.7071);
                                } else t = v;   // "v": top -> bottom
                                gr  = (target.R * (1 - t) + gB.R * t) / 255.0;
                                gg2 = (target.G * (1 - t) + gB.G * t) / 255.0;
                                gb2 = (target.B * (1 - t) + gB.B * t) / 255.0;
                            }
                            RgbToHsl(gr, gg2, gb2, out tH, out tS, out tL);
                        }
                        if (m == "tint" || m == "gradtint") {
                            // hue-lock to the target, saturation follows the original's ramp so
                            // neutral leather/metal stays subdued instead of going neon
                            double ns = tS * (0.25 + 0.75 * Math.Min(1.0, s * 1.4));
                            ns *= (1.0 - Math.Abs(2.0 * l - 1.0) * 0.30);   // ease off in deep shadow/highlight
                            HslToRgb(tH, ns, l, out r1, out g1, out b1);
                        } else if (m == "paint" || m == "gradpaint") {
                            // flat paint: target hue AND saturation, original luminance ramp
                            double nl = l * (0.35 + tL * 1.3);
                            if (nl > 1) nl = 1;
                            double ns = tS * (1.0 - Math.Abs(2.0 * l - 1.0) * 0.25);
                            HslToRgb(tH, ns, nl, out r1, out g1, out b1);
                        } else if (m == "hueshift") {
                            HslToRgb(h + hShift, s, l, out r1, out g1, out b1);
                        } else if (m == "hsl") {
                            HslToRgb(h + hShift, s * sMul, l * lMul, out r1, out g1, out b1);
                        } else if (m == "huerange") {
                            // recolor only one hue family to the target hue (th0),
                            // preserving each pixel's offset from the band center so the
                            // family's internal variation carries over. The centre is
                            // either auto-detected or picked by hand; hShift nudges the
                            // target, satMul/lightMul tune it.
                            double diff = Math.Abs(h - bandCenter) % 360.0; if (diff > 180.0) diff = 360.0 - diff;
                            double HALF = bandHalf, FEA = bandFea; double wgt;
                            if (diff <= HALF) wgt = 1.0;
                            else if (diff <= HALF + FEA) wgt = 0.5 - 0.5 * Math.Cos(Math.PI * ((HALF + FEA) - diff) / FEA);
                            else wgt = 0.0;
                            if (wgt > 0.0) {
                                double rr, gg, bb;
                                HslToRgb(h + (th0 - bandCenter) + hShift, s * sMul, l * lMul, out rr, out gg, out bb);
                                r1 = r0 + (rr - r0) * wgt; g1 = g0 + (gg - g0) * wgt; b1 = b0 + (bb - b0) * wgt;
                            }
                        } else if (m == "gray") {
                            double lum = 0.299 * r0 + 0.587 * g0 + 0.114 * b0;
                            r1 = lum; g1 = lum; b1 = lum;
                        } else if (m == "invert") {
                            r1 = 1 - r0; g1 = 1 - g0; b1 = 1 - b0;
                        }
                    }
                    byte nb = (byte)Math.Max(0, Math.Min(255, (b0 + (b1 - b0) * sMode) * 255.0));
                    byte ng = (byte)Math.Max(0, Math.Min(255, (g0 + (g1 - g0) * sMode) * 255.0));
                    byte nr = (byte)Math.Max(0, Math.Min(255, (r0 + (r1 - r0) * sMode) * 255.0));
                    px[i] = nb; px[i + 1] = ng; px[i + 2] = nr;
                    // alpha untouched - D-map alpha channels carry masks
                    if (useMemo) memo[key] = nb | (ng << 8) | (nr << 16);
                }
                return memo;
            },
            delegate(Dictionary<int, int> memo) { });

        Marshal.Copy(px, 0, bd.Scan0, nBytes);
        baseB.UnlockBits(bd);
        return baseB;
    }

    // dst = dst*strength + orig*(1-strength), alpha included (replace op only)
    static void BlendInto(Bitmap dst, Bitmap orig, double strength) {
        Rectangle rect = new Rectangle(0, 0, dst.Width, dst.Height);
        BitmapData d1 = dst.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        BitmapData d0 = orig.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int nBytes = Math.Abs(d1.Stride) * dst.Height;
        byte[] a = new byte[nBytes]; byte[] b = new byte[nBytes];
        Marshal.Copy(d1.Scan0, a, 0, nBytes);
        Marshal.Copy(d0.Scan0, b, 0, nBytes);
        for (int i = 0; i < nBytes; i++)
            a[i] = (byte)(b[i] + (a[i] - b[i]) * strength);
        Marshal.Copy(a, 0, d1.Scan0, nBytes);
        dst.UnlockBits(d1); orig.UnlockBits(d0);
    }

    // ---- recolour dye calibration -------------------------------------------
    // A dyed zone renders ONE flat colour, and the colour sampled for it is an
    // average over the whole region in the ATLAS - which covers more than you
    // can see, so it comes out diluted (Jubilee's shorts landed about half as
    // warm as the costume's). That gap can only be measured in game, from three
    // shots of the same pose:
    //   meter   - a build whose every dye is 1,1,1, so it renders 1 x LIGHTING
    //   recolor - renders dye x lighting
    //   costume - renders the design's own art x lighting
    // Divide by the meter and the lighting cancels: recolor/meter is the dye
    // actually painting a pixel - which is how a pixel finds WHICH dye owns it,
    // with no region ids involved - and costume/meter is the albedo it should
    // carry. GetPixel is far too slow for a megapixel x 3, so this is LockBits.

    static double[] SrgbLut() {
        double[] lut = new double[256];
        for (int i = 0; i < 256; i++) lut[i] = SrgbToLinear(i / 255.0);
        return lut;
    }
    static byte[] Grab(string path, out int w, out int h, out int stride) {
        using (Bitmap b = Load(path)) {
            w = b.Width; h = b.Height;
            BitmapData d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            stride = d.Stride;
            byte[] buf = new byte[stride * h];
            Marshal.Copy(d.Scan0, buf, 0, buf.Length);
            b.UnlockBits(d);
            return buf;
        }
    }
    // Two shots of one scene are cropped differently, so a body point sits at a
    // different pixel in each. Find b's offset against a by matching a patch of
    // BACKGROUND - pass a rectangle away from the figure and the UI text.
    // Returns "dx<TAB>dy<TAB>mean abs diff".
    public static string AlignShots(string aPath, string bPath, int rx, int ry, int rw, int rh, int range) {
        int aw, ah, astr, bw, bh, bstr;
        byte[] A = Grab(aPath, out aw, out ah, out astr);
        byte[] B = Grab(bPath, out bw, out bh, out bstr);
        int bestDx = 0, bestDy = 0;
        double bestScore = double.MaxValue;
        int[] steps = new int[] { 4, 1 };
        int[] spans = new int[] { range, 5 };
        for (int pass = 0; pass < steps.Length; pass++) {
            int step = steps[pass], span = spans[pass];
            int cx = bestDx, cy = bestDy;
            bestScore = double.MaxValue;
            for (int dy = cy - span; dy <= cy + span; dy += step) {
                for (int dx = cx - span; dx <= cx + span; dx += step) {
                    double sum = 0; int n = 0;
                    for (int y = ry; y < ry + rh; y += 3) {
                        int by = y + dy;
                        if (y < 0 || y >= ah || by < 0 || by >= bh) continue;
                        for (int x = rx; x < rx + rw; x += 3) {
                            int bx = x + dx;
                            if (x < 0 || x >= aw || bx < 0 || bx >= bw) continue;
                            int ia = y * astr + x * 4, ib = by * bstr + bx * 4;
                            sum += Math.Abs(A[ia] - B[ib]) + Math.Abs(A[ia + 1] - B[ib + 1]) + Math.Abs(A[ia + 2] - B[ib + 2]);
                            n++;
                        }
                    }
                    if (n < 50) continue;
                    double score = sum / n;
                    if (score < bestScore) { bestScore = score; bestDx = dx; bestDy = dy; }
                }
            }
        }
        return bestDx + "\t" + bestDy + "\t" + bestScore.ToString("F2", System.Globalization.CultureInfo.InvariantCulture);
    }
    // For every pixel the recolor paints differently from the costume, work out
    // which of the design's dye values owns it and what the costume shows there.
    // dr/dg/db are the dye values the design wrote, one entry per group. One
    // line comes back per group that was seen:
    //   index<TAB>pixels<TAB>Ar<TAB>Ag<TAB>Ab<TAB>Dr<TAB>Dg<TAB>Db   (medians)
    // D is the MEASURED dye: it should land close to the value handed in, and
    // that agreement is the check that the whole measurement is sound.
    public static string SolveDyeCal(string costumePath, string recolorPath, string meterPath,
                                     int dxR, int dyR, int dxM, int dyM,
                                     double[] dr, double[] dg, double[] db,
                                     double tol, int minDiff) {
        int cw, ch, cs, rw2, rh2, rs, mw, mh, ms;
        byte[] C = Grab(costumePath, out cw, out ch, out cs);
        byte[] R = Grab(recolorPath, out rw2, out rh2, out rs);
        byte[] M = Grab(meterPath, out mw, out mh, out ms);
        double[] lut = SrgbLut();
        int G = dr.Length;
        List<float>[] ar = new List<float>[G], ag = new List<float>[G], ab = new List<float>[G];
        List<float>[] mr = new List<float>[G], mg = new List<float>[G], mb = new List<float>[G];
        for (int i = 0; i < G; i++) {
            ar[i] = new List<float>(); ag[i] = new List<float>(); ab[i] = new List<float>();
            mr[i] = new List<float>(); mg[i] = new List<float>(); mb[i] = new List<float>();
        }
        double tol2 = tol * tol;
        for (int y = 0; y < ch; y++) {
            int ry2 = y + dyR, my = y + dyM;
            if (ry2 < 0 || ry2 >= rh2 || my < 0 || my >= mh) continue;
            for (int x = 0; x < cw; x++) {
                int rx2 = x + dxR, mx = x + dxM;
                if (rx2 < 0 || rx2 >= rw2 || mx < 0 || mx >= mw) continue;
                int ic = y * cs + x * 4, ir = ry2 * rs + rx2 * 4, im = my * ms + mx * 4;
                int diff = Math.Abs(C[ic] - R[ir]) + Math.Abs(C[ic + 1] - R[ir + 1]) + Math.Abs(C[ic + 2] - R[ir + 2]);
                if (diff < minDiff) continue;                        // the dye paints nothing here
                double lb = lut[M[im]], lg = lut[M[im + 1]], lr = lut[M[im + 2]];
                if (lr < 0.02 || lg < 0.02 || lb < 0.02) continue;    // too dark to divide by
                double Dr = lut[R[ir + 2]] / lr, Dg = lut[R[ir + 1]] / lg, Db = lut[R[ir]] / lb;
                int best = -1; double bestD = tol2;
                for (int i = 0; i < G; i++) {
                    double er = Dr - dr[i], eg = Dg - dg[i], eb = Db - db[i];
                    double e = er * er + eg * eg + eb * eb;
                    if (e < bestD) { bestD = e; best = i; }
                }
                if (best < 0) continue;                               // no dye of ours explains this pixel
                ar[best].Add((float)(lut[C[ic + 2]] / lr));
                ag[best].Add((float)(lut[C[ic + 1]] / lg));
                ab[best].Add((float)(lut[C[ic]] / lb));
                mr[best].Add((float)Dr); mg[best].Add((float)Dg); mb[best].Add((float)Db);
            }
        }
        System.Text.StringBuilder sb = new System.Text.StringBuilder();
        for (int i = 0; i < G; i++) {
            if (ar[i].Count == 0) continue;
            sb.Append(i).Append('\t').Append(ar[i].Count).Append('\t')
              .Append(Med(ar[i])).Append('\t').Append(Med(ag[i])).Append('\t').Append(Med(ab[i])).Append('\t')
              .Append(Med(mr[i])).Append('\t').Append(Med(mg[i])).Append('\t').Append(Med(mb[i])).Append('\n');
        }
        return sb.ToString();
    }
    static string Med(List<float> v) {
        float[] a = v.ToArray();
        Array.Sort(a);
        return a[a.Length / 2].ToString("F4", System.Globalization.CultureInfo.InvariantCulture);
    }

    // ---- color-space + swatches (material / particle FLinearColor editing) ---
    // Material/Niagara colors are stored LINEAR (FLinearColor); the color picker
    // and swatches are sRGB, so convert on the boundary (mirrors patch_colors.py).
    public static double SrgbToLinear(double c) {
        return c <= 0.04045 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4);
    }
    public static double LinearToSrgb(double c) {
        return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.Pow(c, 1.0 / 2.4) - 0.055;
    }
    // linear channel (may be HDR >1 for glow/emissive params) -> displayable byte
    static int LinToByte(double lin) {
        double s = LinearToSrgb(Math.Max(0.0, Math.Min(1.0, lin)));
        return (int)Math.Round(Math.Max(0.0, Math.Min(1.0, s)) * 255.0);
    }
    // a flat color chip for the Colors list / preview, from a LINEAR rgb triple
    public static Bitmap Swatch(double r, double g, double b, int w, int h) {
        Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (Graphics gr = Graphics.FromImage(bmp))
        using (SolidBrush br = new SolidBrush(Color.FromArgb(255, LinToByte(r), LinToByte(g), LinToByte(b))))
            gr.FillRectangle(br, 0, 0, w, h);
        return bmp;
    }
    // sRGB #RRGGBB (picker) -> linear r,g,b floats packed as a 3-element array
    public static double[] HexToLinear(int R, int G, int B) {
        return new double[] { SrgbToLinear(R / 255.0), SrgbToLinear(G / 255.0), SrgbToLinear(B / 255.0) };
    }
    // linear rgb -> sRGB #RRGGBB bytes (for loading a saved color into the picker)
    public static int[] LinearToHex(double r, double g, double b) {
        return new int[] { LinToByte(r), LinToByte(g), LinToByte(b) };
    }
    // a material colour multiply (BaseTint) shown over a texture preview: each
    // pixel to linear, times the factors, back to sRGB - what the game's shader
    // does. The factors are edit / vanilla, since the plain texture view already
    // stands for "vanilla tint". Returns a new bitmap; alpha is kept.
    public static Bitmap MultiplyLinear(Bitmap src, double fr, double fg, double fb) {
        Bitmap dst = new Bitmap(src.Width, src.Height, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(dst)) g.DrawImage(src, 0, 0, src.Width, src.Height);
        byte[][] lut = new byte[3][];
        double[] fac = { fb, fg, fr };                      // BGRA order
        for (int c = 0; c < 3; c++) {
            lut[c] = new byte[256];
            for (int v = 0; v < 256; v++) {
                double lin = SrgbToLinear(v / 255.0) * fac[c];
                lut[c][v] = (byte)Math.Round(Math.Max(0.0, Math.Min(1.0, LinearToSrgb(Math.Max(0.0, Math.Min(1.0, lin))))) * 255.0);
            }
        }
        Rectangle rc = new Rectangle(0, 0, dst.Width, dst.Height);
        BitmapData bd = dst.LockBits(rc, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        byte[] px = new byte[bd.Stride * bd.Height];
        System.Runtime.InteropServices.Marshal.Copy(bd.Scan0, px, 0, px.Length);
        for (int y = 0; y < bd.Height; y++) {
            int row = y * bd.Stride;
            for (int x = 0; x < bd.Width; x++) {
                int i = row + x * 4;
                px[i] = lut[0][px[i]]; px[i + 1] = lut[1][px[i + 1]]; px[i + 2] = lut[2][px[i + 2]];
            }
        }
        System.Runtime.InteropServices.Marshal.Copy(px, 0, bd.Scan0, px.Length);
        dst.UnlockBits(bd);
        return dst;
    }
}

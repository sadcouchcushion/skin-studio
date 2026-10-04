// ViewArt.cs - pixel work for the 3D preview (viewer\). Kept apart from SkinArt.cs
// so the viewer can change without touching the builder's pixel engine.
//
// All texture bytes here are LINEAR data (character diffuse maps are
// linear-flagged; byte/255 IS the linear value - the gamma landmine), and the
// viewer uploads them as linear, so nothing in here converts colour spaces.
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class ViewArt
{
    static Bitmap LoadCopy(string path)
    {
        // full MemoryStream decode: GDI+ keeps a file lock (and a process-wide
        // clone lock) on anything loaded straight from a path
        byte[] b = File.ReadAllBytes(path);
        using (var ms = new MemoryStream(b))
        using (var img = Image.FromStream(ms))
        {
            var bmp = new Bitmap(img.Width, img.Height, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                g.CompositingMode = CompositingMode.SourceCopy;
                g.DrawImage(img, 0, 0, img.Width, img.Height);
            }
            return bmp;
        }
    }

    static Bitmap Fit(Bitmap src, int maxSize)
    {
        if (maxSize <= 0 || (src.Width <= maxSize && src.Height <= maxSize)) return src;
        double k = (double)maxSize / Math.Max(src.Width, src.Height);
        int w = Math.Max(1, (int)Math.Round(src.Width * k)), h = Math.Max(1, (int)Math.Round(src.Height * k));
        var dst = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(dst))
        {
            g.CompositingMode = CompositingMode.SourceCopy;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            using (var ia = new ImageAttributes())
            {
                ia.SetWrapMode(WrapMode.TileFlipXY);   // no dark fringe at the edges
                g.DrawImage(src, new Rectangle(0, 0, w, h), 0, 0, src.Width, src.Height, GraphicsUnit.Pixel, ia);
            }
        }
        src.Dispose();
        return dst;
    }

    static byte[] Pixels(Bitmap bmp)
    {
        var r = new Rectangle(0, 0, bmp.Width, bmp.Height);
        var d = bmp.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var px = new byte[d.Stride * d.Height];
        Marshal.Copy(d.Scan0, px, 0, px.Length);
        bmp.UnlockBits(d);
        return px;
    }

    static void Put(Bitmap bmp, byte[] px)
    {
        var r = new Rectangle(0, 0, bmp.Width, bmp.Height);
        var d = bmp.LockBits(r, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(px, 0, d.Scan0, px.Length);
        bmp.UnlockBits(d);
    }

    static void SavePng(Bitmap bmp, string dst)
    {
        string tmp = dst + ".tmp";
        bmp.Save(tmp, ImageFormat.Png);
        if (File.Exists(dst)) File.Delete(dst);
        File.Move(tmp, dst);
    }

    // copy a PNG down to at most maxSize on its long edge (GPU memory: a
    // costume is 30-60 maps and many are 4096)
    public static void Shrink(string src, string dst, int maxSize)
    {
        using (var bmp = Fit(LoadCopy(src), maxSize)) SavePng(bmp, dst);
    }

    // The dye, as settled in game (2026-09-18/20):
    //   region = round(mask.alpha / (255/7)); 0 = undyed -> the art shows
    //   colour = lerp(ColorA, ColorB, mask.R), then toward ColorGChannel by
    //            mask.G and toward ColorBChannel by mask.B
    //   and the dye REPLACES the art in its zone (a dyed zone renders flat).
    // regions: 8 x 4 x 4 floats, [region][A,B,G,Bch][r,g,b,present]; a region
    // whose A and B are both absent is left as the art (its values would come
    // from the parent material, which we cannot read).
    // Returns the number of dyed pixels written.
    public static int DyeComposite(string diffPng, string maskPng, string dstPng, float[] regions, int maxSize)
    {
        using (var diff0 = LoadCopy(diffPng))
        using (var diff = Fit(new Bitmap(diff0), maxSize))
        using (var mask = LoadCopy(maskPng))
        {
            byte[] dp = Pixels(diff), mp = Pixels(mask);
            int w = diff.Width, h = diff.Height, mw = mask.Width, mh = mask.Height;
            int dStride = w * 4, mStride = mw * 4;
            int n = 0;
            for (int y = 0; y < h; y++)
            {
                int my = (int)((y + 0.5) * mh / h); if (my >= mh) my = mh - 1;
                for (int x = 0; x < w; x++)
                {
                    int mx = (int)((x + 0.5) * mw / w); if (mx >= mw) mx = mw - 1;   // NEAREST - smoothing invents region ids
                    int mi = my * mStride + mx * 4;
                    int reg = (int)Math.Round(mp[mi + 3] / (255.0 / 7.0));
                    if (reg <= 0 || reg > 7) continue;
                    int o = reg * 16;
                    bool hasA = regions[o + 3] > 0, hasB = regions[o + 7] > 0;
                    if (!hasA && !hasB) continue;
                    double t = mp[mi + 2] / 255.0;                    // R (GDI+ order is B,G,R,A)
                    double cr, cg, cb;
                    if (hasA && hasB)
                    {
                        cr = regions[o + 0] + (regions[o + 4] - regions[o + 0]) * t;
                        cg = regions[o + 1] + (regions[o + 5] - regions[o + 1]) * t;
                        cb = regions[o + 2] + (regions[o + 6] - regions[o + 2]) * t;
                    }
                    else
                    {
                        int k = hasA ? 0 : 4;
                        cr = regions[o + k]; cg = regions[o + k + 1]; cb = regions[o + k + 2];
                    }
                    if (regions[o + 11] > 0)
                    {
                        double s = mp[mi + 1] / 255.0;               // G
                        cr += (regions[o + 8] - cr) * s; cg += (regions[o + 9] - cg) * s; cb += (regions[o + 10] - cb) * s;
                    }
                    if (regions[o + 15] > 0)
                    {
                        double s = mp[mi + 0] / 255.0;               // B
                        cr += (regions[o + 12] - cr) * s; cg += (regions[o + 13] - cg) * s; cb += (regions[o + 14] - cb) * s;
                    }
                    int di = y * dStride + x * 4;
                    dp[di + 2] = ToByte(cr); dp[di + 1] = ToByte(cg); dp[di + 0] = ToByte(cb);
                    n++;
                }
            }
            Put(diff, dp);
            SavePng(diff, dstPng);
            return n;
        }
    }

    // How different are two PNGs, byte for byte (GDI+ decodes raw bytes and
    // ignores gAMA, verified 2026-09-23)? Every byte is read - a small painted
    // logo on a big atlas vanishes into any MEAN, so the verdict uses the MAX.
    // Returns { mean, max, bytes over 3 }, or { -1, -1, -1 } when sizes differ.
    // Two decoders of one BC texture land within +-1 of each other.
    public static double[] DiffStats(string a, string b)
    {
        using (var ba = LoadCopy(a))
        using (var bb = LoadCopy(b))
        {
            if (ba.Width != bb.Width || ba.Height != bb.Height) return new double[] { -1, -1, -1 };
            byte[] pa = Pixels(ba), pb = Pixels(bb);
            long sum = 0, over = 0; int max = 0;
            for (int i = 0; i < pa.Length; i++)
            {
                int d = Math.Abs(pa[i] - pb[i]);
                sum += d;
                if (d > max) max = d;
                if (d > 3) over++;
            }
            return new double[] { pa.Length == 0 ? 0 : (double)sum / pa.Length, max, over };
        }
    }

    // PNG without colour-space chunks (gAMA / sRGB / cHRM / iCCP): Atelier's own
    // exports carry none, and the bytes are linear data either way. GDI+ adds
    // gAMA 0.45455 + sRGB on every save, which a converter that honours them
    // would "correct" (the Luna darkening).
    public static void StripColorChunks(string png)
    {
        byte[] b = File.ReadAllBytes(png);
        using (var ms = new MemoryStream(b.Length))
        {
            ms.Write(b, 0, 8);
            int i = 8;
            while (i + 12 <= b.Length)
            {
                int len = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
                string t = System.Text.Encoding.ASCII.GetString(b, i + 4, 4);
                int total = 12 + len;
                if (t != "gAMA" && t != "sRGB" && t != "cHRM" && t != "iCCP") ms.Write(b, i, total);
                i += total;
                if (t == "IEND") break;
            }
            File.WriteAllBytes(png, ms.ToArray());
        }
    }

    // HDR dyes (components above 1) clip - a texture cannot carry them
    static byte ToByte(double v)
    {
        if (v <= 0) return 0;
        if (v >= 1) return 255;
        return (byte)Math.Round(v * 255.0);
    }
}

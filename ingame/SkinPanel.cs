// SkinPanel.cs - the in-game editor's UI, drawn on the PC.
//
// The game side is deliberately dumb: one Image showing a PNG and a transparent
// Button that reports where the mouse went down, moved and came up. Everything
// the player sees in that panel is drawn HERE, by an immediate-mode UI over
// GDI+, and every click is resolved HERE by hit-testing the same rectangles we
// drew. So a new control, a new screen or a layout fix never needs Unreal, a
// cook or a repack - only this file and ingame_server.ps1.
//
// Immediate mode, one pass per input event:
//     p.Begin(input)         mouse position in frame pixels, edges, wheel
//     ...widgets...          each draws itself and answers "was I used?"
//     p.End()                the finished frame
//
// A click is resolved on RELEASE over the widget that took the PRESS, the same
// rule every desktop toolkit uses, so a press that slides off a button cancels.
// When a widget reports an action mid-frame the caller changes state and then
// renders once more, so the frame on screen always matches the state.

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;

public class SkinPanelInput {
    public float X = -1, Y = -1;      // frame pixels; negative = mouse not over the panel
    public bool Down;                 // button held after this event
    public bool Pressed;              // went down on this event
    public bool Released;             // came up on this event
    public int Wheel;                 // +1 = up / away, -1 = down / toward
}

public class SkinPanel : IDisposable {
    // ---- theme: vuistyle's sage-on-charcoal, so the panel reads as Skin Studio
    public static readonly Color Bg      = Color.FromArgb(246, 27, 27, 27);
    public static readonly Color Card    = Color.FromArgb(40, 40, 40);
    public static readonly Color Raised  = Color.FromArgb(52, 52, 52);
    public static readonly Color Hover   = Color.FromArgb(67, 67, 67);
    public static readonly Color Line    = Color.FromArgb(74, 74, 74);
    public static readonly Color Text    = Color.FromArgb(233, 233, 233);
    public static readonly Color Muted   = Color.FromArgb(155, 155, 155);
    public static readonly Color Faint   = Color.FromArgb(118, 118, 118);
    public static readonly Color Sage    = Color.FromArgb(158, 189, 148);
    public static readonly Color SageLt  = Color.FromArgb(190, 214, 182);
    public static readonly Color SageDk  = Color.FromArgb(116, 146, 107);
    public static readonly Color SageHi  = Color.FromArgb(176, 203, 167);
    public static readonly Color Amber   = Color.FromArgb(228, 172, 102);
    public static readonly Color Danger  = Color.FromArgb(214, 118, 108);
    public static readonly Color Sink    = Color.FromArgb(31, 31, 31);

    public readonly int W, H;
    // UI scale: 1.0 = the sizes written below, in real screen pixels. The
    // server derives it from the viewport's PIXEL height and her text-size
    // setting - never from the game's UMG DPI scale, which Rivals reports as
    // ~0.5 at 1080p and which halved the whole panel on the first in-game run.
    public readonly float S;
    Bitmap bmp;
    Graphics g;
    SkinPanelInput inp = new SkinPanelInput();

    // persistent across frames
    public string ActiveId;           // the widget that took the press
    public string LastCommitId;       // set when a drag widget is released this frame
    readonly Dictionary<string, float> scroll = new Dictionary<string, float>();
    readonly Dictionary<string, float> scrollMax = new Dictionary<string, float>();
    readonly Dictionary<string, Bitmap> imgCache = new Dictionary<string, Bitmap>(StringComparer.OrdinalIgnoreCase);
    float dragGrabDy;                 // scrollbar thumb grab offset

    // per-frame layout
    float x0, x1, y;                  // content column and cursor
    float clipTop, clipBot;           // visible band of the active scroll region
    string scrollId; float scrollTop; float scrollContentStart;
    public bool AnyHot;               // something under the mouse wants hover feedback
    public string HotId;

    // fonts
    Font fTitle, fSub, fBody, fBold, fSmall, fTiny, fMono;
    readonly StringFormat sfLeft, sfCenter, sfRight, sfWrap;

    public SkinPanel(int w, int h, float scale) {
        W = w; H = h; S = scale;
        string face = "Segoe UI";
        fTitle = new Font("Segoe UI Semibold", 16f * S, FontStyle.Regular, GraphicsUnit.Pixel);
        fSub   = new Font(face, 12f * S, FontStyle.Regular, GraphicsUnit.Pixel);
        fBody  = new Font(face, 14f * S, FontStyle.Regular, GraphicsUnit.Pixel);
        fBold  = new Font("Segoe UI Semibold", 14f * S, FontStyle.Regular, GraphicsUnit.Pixel);
        fSmall = new Font("Segoe UI Semibold", 11f * S, FontStyle.Regular, GraphicsUnit.Pixel);
        fTiny  = new Font(face, 12f * S, FontStyle.Regular, GraphicsUnit.Pixel);
        fMono  = new Font("Consolas", 13f * S, FontStyle.Regular, GraphicsUnit.Pixel);
        sfLeft = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter, FormatFlags = StringFormatFlags.NoWrap };
        sfCenter = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter, FormatFlags = StringFormatFlags.NoWrap };
        sfRight = new StringFormat { Alignment = StringAlignment.Far, LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter, FormatFlags = StringFormatFlags.NoWrap };
        sfWrap = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Near, Trimming = StringTrimming.Word };
    }

    public void Dispose() {
        if (g != null) g.Dispose();
        if (bmp != null) bmp.Dispose();
        foreach (var b in imgCache.Values) b.Dispose();
        imgCache.Clear();
    }

    float P(float v) { return v * S; }

    // ------------------------------------------------------------------ frame
    public void Begin(SkinPanelInput input) {
        inp = input ?? new SkinPanelInput();
        LastCommitId = null;
        // a fresh press always starts clean: if an 'up' event was ever lost, the
        // old press would otherwise keep every other widget from going hot
        if (inp.Pressed) ActiveId = null;
        AnyHot = false; HotId = null;
        if (g != null) { g.Dispose(); g = null; }
        if (bmp != null) { bmp.Dispose(); bmp = null; }
        bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb);
        g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g.Clear(Color.Transparent);
        using (var path = Round(new RectangleF(0, 0, W - 1, H - 1), P(10)))
        using (var br = new SolidBrush(Bg))
        using (var pen = new Pen(Line, 1f)) {
            g.FillPath(br, path);
            g.DrawPath(pen, path);
        }
        x0 = P(16); x1 = W - P(16); y = P(14);
        clipTop = 0; clipBot = H;
        scrollId = null;
    }

    // Finished frame. Releases the press on the way out, so a drag cannot stick
    // if the release lands on the next frame's layout somewhere else.
    public Bitmap End() {
        if (inp.Released || !inp.Down) {
            if (inp.Released && ActiveId != null && LastCommitId == null) LastCommitId = ActiveId;
            ActiveId = null;
        }
        var outBmp = bmp; bmp = null;
        g.Dispose(); g = null;
        return outBmp;
    }

    public static void SavePng(Bitmap b, string path) {
        // write-then-rename, so the game never imports half a file
        string tmp = path + ".tmp";
        b.Save(tmp, ImageFormat.Png);
        for (int i = 0; i < 40; i++) {
            try {
                if (File.Exists(path)) File.Delete(path);
                File.Move(tmp, path);
                return;
            } catch (IOException) { System.Threading.Thread.Sleep(15); }
        }
        throw new IOException("could not replace " + path);
    }

    // ---------------------------------------------------------------- helpers
    static GraphicsPath Round(RectangleF r, float rad) {
        var p = new GraphicsPath();
        float d = Math.Min(rad * 2, Math.Min(r.Width, r.Height));
        if (d <= 0.5f) { p.AddRectangle(r); return p; }
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    void Fill(RectangleF r, Color c, float rad) {
        using (var path = Round(r, rad)) using (var br = new SolidBrush(c)) g.FillPath(br, path);
    }
    void Stroke(RectangleF r, Color c, float rad, float w) {
        using (var path = Round(r, rad)) using (var pen = new Pen(c, w)) g.DrawPath(pen, path);
    }
    void Str(string s, Font f, Color c, RectangleF r, StringFormat sf) {
        using (var br = new SolidBrush(c)) g.DrawString(s ?? "", f, br, r, sf);
    }

    bool Inside(RectangleF r) {
        return inp.X >= r.Left && inp.X < r.Right && inp.Y >= r.Top && inp.Y < r.Bottom
            && inp.Y >= clipTop && inp.Y < clipBot;
    }

    // hot = under the mouse, and nothing else holds the press
    bool Hot(string id, RectangleF r) {
        bool h = Inside(r) && (ActiveId == null || ActiveId == id);
        if (h) { AnyHot = true; HotId = id; }
        return h;
    }

    // standard press/release button logic; returns true on a completed click
    bool Behave(string id, RectangleF r, out bool hot, out bool held) {
        hot = Hot(id, r);
        if (hot && inp.Pressed) ActiveId = id;
        held = ActiveId == id && inp.Down;
        bool clicked = inp.Released && ActiveId == id && hot;
        return clicked;
    }

    public static Color Hex(string hex) {
        if (string.IsNullOrEmpty(hex)) return Color.White;
        string h = hex.TrimStart('#');
        if (h.Length == 3) h = "" + h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
        if (h.Length != 6) return Color.White;
        try { return Color.FromArgb(255, Convert.ToInt32(h.Substring(0, 2), 16), Convert.ToInt32(h.Substring(2, 2), 16), Convert.ToInt32(h.Substring(4, 2), 16)); }
        catch { return Color.White; }
    }
    public static string ToHex(Color c) { return string.Format("#{0:X2}{1:X2}{2:X2}", c.R, c.G, c.B); }

    public static Color FromHsv(double h, double s, double v) {
        h = ((h % 360) + 360) % 360; s = Math.Max(0, Math.Min(1, s)); v = Math.Max(0, Math.Min(1, v));
        double c = v * s, x = c * (1 - Math.Abs((h / 60.0) % 2 - 1)), m = v - c;
        double r = 0, gg = 0, b = 0;
        if (h < 60) { r = c; gg = x; } else if (h < 120) { r = x; gg = c; } else if (h < 180) { gg = c; b = x; }
        else if (h < 240) { gg = x; b = c; } else if (h < 300) { r = x; b = c; } else { r = c; b = x; }
        return Color.FromArgb(255, (int)Math.Round((r + m) * 255), (int)Math.Round((gg + m) * 255), (int)Math.Round((b + m) * 255));
    }
    public static double[] ToHsv(Color c) {
        double r = c.R / 255.0, gg = c.G / 255.0, b = c.B / 255.0;
        double mx = Math.Max(r, Math.Max(gg, b)), mn = Math.Min(r, Math.Min(gg, b)), d = mx - mn;
        double h = 0;
        if (d > 1e-9) {
            if (mx == r) h = 60 * (((gg - b) / d) % 6);
            else if (mx == gg) h = 60 * ((b - r) / d + 2);
            else h = 60 * ((r - gg) / d + 4);
        }
        if (h < 0) h += 360;
        return new double[] { h, mx <= 0 ? 0 : d / mx, mx };
    }

    Bitmap LoadImg(string path) {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return null;
        Bitmap b;
        if (imgCache.TryGetValue(path, out b)) return b;
        try {
            // full decode through a stream: GDI+ otherwise keeps the file locked
            using (var ms = new MemoryStream(File.ReadAllBytes(path)))
            using (var tmp = new Bitmap(ms)) b = new Bitmap(tmp);
        } catch { b = null; }
        imgCache[path] = b;
        return b;
    }
    public void ForgetImage(string path) {
        Bitmap b;
        if (imgCache.TryGetValue(path, out b)) { if (b != null) b.Dispose(); imgCache.Remove(path); }
    }

    // ---------------------------------------------------------------- layout
    public void Space(float px) { y += P(px); }
    public float CursorY { get { return y; } }

    // Title bar, outside any scroll region. Returns 1 = back, 2 = close, 0 = none.
    float titleH = 0;
    public int TitleBar(string title, string sub, bool showBack) {
        float h = P(58);
        titleH = h;
        int result = 0;
        float tx = x0;
        if (showBack) {
            var rb = new RectangleF(P(6), P(8), P(42), P(42));
            bool hot, held;
            if (Behave("__back", rb, out hot, out held)) result = 1;
            if (hot || held) Fill(rb, held ? SageDk : Hover, P(6));
            DrawChevron(rb, true, hot ? Text : SageLt);
            tx = rb.Right + P(6);
        }
        var rc = new RectangleF(W - P(48), P(8), P(42), P(42));
        {
            bool hot, held;
            if (Behave("__close", rc, out hot, out held)) result = 2;
            if (hot || held) Fill(rc, held ? SageDk : Hover, P(6));
            using (var pen = new Pen(hot ? Text : Muted, P(1.6f))) {
                float c = P(7);
                float cx = rc.X + rc.Width / 2, cy = rc.Y + rc.Height / 2;
                g.DrawLine(pen, cx - c, cy - c, cx + c, cy + c);
                g.DrawLine(pen, cx - c, cy + c, cx + c, cy - c);
            }
        }
        Str(title, fTitle, Text, new RectangleF(tx, P(8), rc.X - tx - P(4), P(24)), sfLeft);
        Str(sub, fSub, Muted, new RectangleF(tx, P(32), rc.X - tx - P(4), P(18)), sfLeft);
        using (var pen = new Pen(Line, 1f)) g.DrawLine(pen, 0, h, W, h);
        y = h + P(10);
        return result;
    }

    void DrawChevron(RectangleF r, bool left, Color c) {
        float cx = r.X + r.Width / 2, cy = r.Y + r.Height / 2, a = P(5);
        using (var pen = new Pen(c, P(2f)) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round }) {
            if (left) g.DrawLines(pen, new[] { new PointF(cx + a / 2, cy - a), new PointF(cx - a / 2, cy), new PointF(cx + a / 2, cy + a) });
            else g.DrawLines(pen, new[] { new PointF(cx - a / 2, cy - a), new PointF(cx + a / 2, cy), new PointF(cx - a / 2, cy + a) });
        }
    }

    // A footer strip pinned to the bottom (status line). Call BEFORE BeginScroll
    // so the scroll region knows where to stop.
    float footerTop = -1;
    public void Footer(string text, bool warn) {
        float h = P(34);
        footerTop = H - h;
        using (var pen = new Pen(Line, 1f)) g.DrawLine(pen, 0, footerTop, W, footerTop);
        Str(text, fTiny, warn ? Amber : Muted, new RectangleF(x0, footerTop, x1 - x0, h), sfLeft);
    }

    public void BeginScroll(string id) {
        scrollId = id;
        scrollTop = y;
        float bottom = footerTop > 0 ? footerTop - P(4) : H - P(8);
        clipTop = scrollTop; clipBot = bottom;
        float off;
        scroll.TryGetValue(id, out off);
        float max;
        scrollMax.TryGetValue(id, out max);
        var region = new RectangleF(0, clipTop, W, clipBot - clipTop);
        if (inp.Wheel != 0 && Inside(region)) off -= inp.Wheel * P(60);
        off = Math.Max(0, Math.Min(off, max));
        scroll[id] = off;
        g.SetClip(new RectangleF(0, clipTop, W, clipBot - clipTop));
        scrollContentStart = scrollTop - off;
        y = scrollContentStart;
    }

    public void EndScroll() {
        if (scrollId == null) return;
        float contentH = y - scrollContentStart + P(8);
        float viewH = clipBot - clipTop;
        float max = Math.Max(0, contentH - viewH);
        scrollMax[scrollId] = max;
        g.ResetClip();
        float off; scroll.TryGetValue(scrollId, out off);
        if (off > max) { off = max; scroll[scrollId] = off; }
        if (max > 0.5f) {
            // scrollbar: drag the thumb, or click the track to jump
            var track = new RectangleF(W - P(10), clipTop + P(2), P(6), viewH - P(4));
            float thumbH = Math.Max(P(36), track.Height * viewH / contentH);
            float thumbY = track.Y + (track.Height - thumbH) * (off / max);
            var thumb = new RectangleF(track.X, thumbY, track.Width, thumbH);
            var grab = new RectangleF(track.X - P(8), track.Y, track.Width + P(12), track.Height);
            string sid = "__sb_" + scrollId;
            float saveTop = clipTop, saveBot = clipBot; clipTop = 0; clipBot = H;
            bool hot = Hot(sid, grab);
            if (hot && inp.Pressed) {
                ActiveId = sid;
                dragGrabDy = (inp.Y >= thumbY && inp.Y <= thumbY + thumbH) ? inp.Y - thumbY : thumbH / 2;
            }
            if (ActiveId == sid && inp.Down) {
                float t = (inp.Y - dragGrabDy - track.Y) / Math.Max(1, track.Height - thumbH);
                off = Math.Max(0, Math.Min(1, t)) * max;
                scroll[scrollId] = off;
                thumbY = track.Y + (track.Height - thumbH) * (off / max);
                thumb = new RectangleF(track.X, thumbY, track.Width, thumbH);
            }
            clipTop = saveTop; clipBot = saveBot;
            Fill(track, Color.FromArgb(40, 255, 255, 255), P(2.5f));
            Fill(thumb, (hot || ActiveId == sid) ? SageLt : Faint, P(2.5f));
        }
        clipTop = 0; clipBot = H;
        scrollId = null;
        y = footerTop > 0 ? footerTop : H;
    }

    public void ScrollTo(string id, float v) { scroll[id] = Math.Max(0, v); }

    // ---------------------------------------------------------------- widgets
    public void Section(string text) {
        y += P(6);
        Str(text.ToUpperInvariant(), fSmall, Faint, new RectangleF(x0, y, x1 - x0, P(18)), sfLeft);
        y += P(22);
    }

    public void Label(string text, Color c) {
        var sz = g.MeasureString(text ?? "", fBody, (int)(x1 - x0), sfWrap);
        Str(text, fBody, c, new RectangleF(x0, y, x1 - x0, sz.Height + 2), sfWrap);
        y += sz.Height + P(6);
    }
    public void Label(string text) { Label(text, Text); }
    public void Hint(string text) {
        var sz = g.MeasureString(text ?? "", fTiny, (int)(x1 - x0), sfWrap);
        Str(text, fTiny, Muted, new RectangleF(x0, y, x1 - x0, sz.Height + 2), sfWrap);
        y += sz.Height + P(6);
    }

    // style: 0 plain, 1 accent (sage fill), 2 danger (red text), 3 quiet (no fill),
    // 4 disabled (drawn, never clickable)
    const float BtnH = 42;
    public bool Button(string id, string text, int style) {
        var r = new RectangleF(x0, y, x1 - x0, P(BtnH));
        bool c = ButtonAt(id, r, text, style, Color.Empty);
        y += P(BtnH) + P(6);
        return c;
    }
    public bool Button(string id, string text) { return Button(id, text, 0); }

    public bool ButtonAt(string id, RectangleF r, string text, int style, Color chip) {
        bool hot = false, held = false, clicked = false;
        if (style != 4) clicked = Behave(id, r, out hot, out held);
        Color fill, fg;
        if (style == 1) { fill = held ? SageDk : (hot ? SageHi : Sage); fg = Color.FromArgb(24, 30, 22); }
        else if (style == 3) { fill = held ? SageDk : (hot ? Hover : Color.Transparent); fg = hot ? Text : SageLt; }
        else if (style == 4) { fill = Card; fg = Color.FromArgb(90, 255, 255, 255); }
        else { fill = held ? SageDk : (hot ? Hover : Raised); fg = style == 2 ? Danger : Text; }
        if (fill.A > 0) Fill(r, fill, P(6));
        var tr = r;
        if (!chip.IsEmpty) {
            var cr = new RectangleF(r.X + P(8), r.Y + (r.Height - P(16)) / 2, P(16), P(16));
            Fill(cr, chip, P(4)); Stroke(cr, Color.FromArgb(90, 0, 0, 0), P(4), 1f);
            tr = new RectangleF(cr.Right + P(4), r.Y, r.Right - cr.Right - P(8), r.Height);
            Str(text, style == 1 ? fBold : fBody, fg, tr, sfLeft);
        } else {
            Str(text, style == 1 ? fBold : fBody, fg, tr, sfCenter);
        }
        return clicked;
    }

    // n buttons sharing one row; returns the clicked index or -1
    public int ButtonRow(string id, string[] texts, int accentIndex) {
        var styles = new int[texts.Length];
        for (int i = 0; i < texts.Length; i++) styles[i] = i == accentIndex ? 1 : 0;
        return ButtonRow(id, texts, styles);
    }
    // the same with a style per button (see ButtonAt; 4 = disabled)
    public int ButtonRow(string id, string[] texts, int[] styles) {
        int hit = -1;
        float gap = P(6);
        float w = (x1 - x0 - gap * (texts.Length - 1)) / texts.Length;
        for (int i = 0; i < texts.Length; i++) {
            var r = new RectangleF(x0 + i * (w + gap), y, w, P(BtnH));
            int st = styles != null && i < styles.Length ? styles[i] : 0;
            if (ButtonAt(id + "#" + i, r, texts[i], st, Color.Empty)) hit = i;
        }
        y += P(BtnH) + P(6);
        return hit;
    }

    // Wrapped pill picker (modes, directions). Returns the clicked index or -1.
    public int Pills(string id, string[] opts, int sel) {
        int hit = -1;
        float gap = P(6), h = P(36), x = x0;
        for (int i = 0; i < opts.Length; i++) {
            float w = g.MeasureString(opts[i], fBody).Width + P(22);
            if (x + w > x1 && x > x0) { x = x0; y += h + gap; }
            var r = new RectangleF(x, y, w, h);
            bool hot, held;
            if (Behave(id + "#" + i, r, out hot, out held)) hit = i;
            bool on = i == sel;
            Color fill = on ? (held ? SageDk : Sage) : (held ? SageDk : (hot ? Hover : Raised));
            Fill(r, fill, h / 2);
            Str(opts[i], on ? fBold : fBody, on ? Color.FromArgb(24, 30, 22) : Text, r, sfCenter);
            x += w + gap;
        }
        y += h + P(10);
        return hit;
    }

    // A list row: optional thumbnail, title, subtitle, optional colour chips on the
    // right, chevron. Returns true when clicked.
    public bool ListItem(string id, string title, string sub, string thumbPath, Color[] chips, bool selected) {
        float h = P(64);
        var r = new RectangleF(x0, y, x1 - x0, h);
        bool hot, held;
        bool clicked = Behave(id, r, out hot, out held);
        Fill(r, held ? SageDk : (hot ? Hover : (selected ? Raised : Card)), P(8));
        if (selected) Stroke(r, Sage, P(8), P(1.5f));
        float tx = r.X + P(10);
        var bmpThumb = LoadImg(thumbPath);
        if (bmpThumb != null) {
            var tr = new RectangleF(r.X + P(7), r.Y + P(7), h - P(14), h - P(14));
            using (var path = Round(tr, P(5))) {
                var save = g.Clip; g.SetClip(path, CombineMode.Intersect);
                g.DrawImage(bmpThumb, tr);
                g.Clip = save;
            }
            tx = tr.Right + P(10);
        }
        float right = r.Right - P(28);
        if (chips != null && chips.Length > 0) {
            float cw = P(14), cg = P(4);
            float cx = right - chips.Length * (cw + cg);
            for (int i = 0; i < chips.Length; i++) {
                var cr = new RectangleF(cx + i * (cw + cg), r.Y + (h - cw) / 2, cw, cw);
                Fill(cr, chips[i], cw / 2); Stroke(cr, Color.FromArgb(110, 0, 0, 0), cw / 2, 1f);
            }
            right = cx - P(6);
        }
        Str(title, fBold, Text, new RectangleF(tx, r.Y + P(10), right - tx, P(22)), sfLeft);
        Str(sub, fTiny, Muted, new RectangleF(tx, r.Y + P(34), right - tx, P(20)), sfLeft);
        DrawChevron(new RectangleF(r.Right - P(26), r.Y, P(20), h), false, hot ? Text : Faint);
        y += h + P(6);
        return clicked;
    }

    // Labelled slider. Returns the (possibly dragged) value; LastCommitId == id
    // on the frame the drag is released, which is when the caller re-renders the
    // texture. Clicking the track jumps there and starts dragging.
    public double Slider(string id, string label, double value, double min, double max, string valueText) {
        float lh = P(20);
        Str(label, fBody, Text, new RectangleF(x0, y, (x1 - x0) * 0.7f, lh), sfLeft);
        float trackY = y + lh + P(10);
        var track = new RectangleF(x0 + P(2), trackY, x1 - x0 - P(4), P(6));
        var grab = new RectangleF(x0, trackY - P(14), x1 - x0, P(34));
        bool hot = Hot(id, grab);
        if (hot && inp.Pressed) ActiveId = id;
        bool drag = ActiveId == id && (inp.Down || inp.Released);
        if (drag && inp.X >= 0) {
            double t = (inp.X - track.X) / Math.Max(1, track.Width);
            t = Math.Max(0, Math.Min(1, t));
            value = min + t * (max - min);
        }
        if (inp.Released && ActiveId == id) LastCommitId = id;
        double tt = max > min ? (value - min) / (max - min) : 0;
        tt = Math.Max(0, Math.Min(1, tt));
        Fill(track, Line, P(3));
        var filled = new RectangleF(track.X, track.Y, (float)(track.Width * tt), track.Height);
        if (filled.Width > 0.5f) Fill(filled, Sage, P(3));
        float kx = track.X + (float)(track.Width * tt);
        float kr = (hot || drag) ? P(9) : P(7.5f);
        var knob = new RectangleF(kx - kr, track.Y + track.Height / 2 - kr, kr * 2, kr * 2);
        Fill(knob, drag ? SageLt : Text, kr);
        Str(valueText, fMono, drag ? SageLt : Muted, new RectangleF(x0, y, x1 - x0, lh), sfRight);
        y = trackY + P(6) + P(18);
        return value;
    }

    public bool Toggle(string id, string label, bool value, string hint) {
        float h = P(38);
        var r = new RectangleF(x0, y, x1 - x0, h);
        bool hot, held;
        if (Behave(id, r, out hot, out held)) value = !value;
        if (hot) Fill(r, Color.FromArgb(28, 255, 255, 255), P(6));
        var sw = new RectangleF(x1 - P(44), y + (h - P(20)) / 2, P(38), P(20));
        Fill(sw, value ? Sage : Line, sw.Height / 2);
        float kx = value ? sw.Right - P(18) : sw.X + P(2);
        Fill(new RectangleF(kx, sw.Y + P(2), P(16), P(16)), value ? Color.FromArgb(24, 30, 22) : Muted, P(8));
        Str(label, fBody, Text, new RectangleF(x0 + P(4), y, sw.X - x0 - P(8), h), sfLeft);
        y += h;
        if (!string.IsNullOrEmpty(hint)) {
            var sz = g.MeasureString(hint, fTiny, (int)(x1 - x0 - P(4)), sfWrap);
            Str(hint, fTiny, Muted, new RectangleF(x0 + P(4), y, x1 - x0 - P(4), sz.Height + 2), sfWrap);
            y += sz.Height;
        }
        y += P(8);
        return value;
    }

    // Big colour preview with its hex. Returns true when clicked.
    public bool ColorBar(string id, string label, Color c, bool selected) {
        float h = P(44);
        var r = new RectangleF(x0, y, x1 - x0, h);
        bool hot, held;
        bool clicked = Behave(id, r, out hot, out held);
        Fill(r, held ? SageDk : (hot ? Hover : Raised), P(8));
        if (selected) Stroke(r, Sage, P(8), P(1.5f));
        var sw = new RectangleF(r.X + P(6), r.Y + P(6), P(64), h - P(12));
        Fill(sw, c, P(5)); Stroke(sw, Color.FromArgb(110, 0, 0, 0), P(5), 1f);
        Str(label, fBody, Text, new RectangleF(sw.Right + P(10), r.Y, r.Width * 0.5f, h), sfLeft);
        Str(ToHex(c), fMono, Muted, new RectangleF(r.X, r.Y, r.Width - P(10), h), sfRight);
        y += h + P(6);
        return clicked;
    }

    // Saturation/value square + hue strip. h in degrees, s/v 0..1, edited in place.
    // Returns true while the colour changed this frame; LastCommitId == id on release.
    public bool ColorPicker(string id, ref double h, ref double s, ref double v) {
        float side = x1 - x0;
        float sq = Math.Min(side - P(48), P(230));
        var box = new RectangleF(x0, y, sq, sq);
        var hue = new RectangleF(box.Right + P(14), y, P(30), sq);
        bool changed = false;

        // SV square: white->hue horizontally, then black vertically
        using (var lg = new LinearGradientBrush(box, Color.White, FromHsv(h, 1, 1), 0f)) g.FillRectangle(lg, box);
        using (var lg = new LinearGradientBrush(new RectangleF(box.X, box.Y - 1, box.Width, box.Height + 2), Color.FromArgb(0, 0, 0, 0), Color.Black, 90f)) g.FillRectangle(lg, box);
        using (var pen = new Pen(Line, 1f)) g.DrawRectangle(pen, box.X, box.Y, box.Width, box.Height);

        // hue strip, top = 0 degrees
        using (var lg = new LinearGradientBrush(new RectangleF(hue.X, hue.Y - 1, hue.Width, hue.Height + 2), Color.Red, Color.Red, 90f)) {
            var cb = new ColorBlend(7);
            for (int i = 0; i < 7; i++) { cb.Colors[i] = FromHsv(i * 60, 1, 1); cb.Positions[i] = i / 6f; }
            lg.InterpolationColors = cb;
            g.FillRectangle(lg, hue);
        }
        using (var pen = new Pen(Line, 1f)) g.DrawRectangle(pen, hue.X, hue.Y, hue.Width, hue.Height);

        string idSv = id + ".sv", idH = id + ".h";
        bool hotSv = Hot(idSv, box), hotH = Hot(idH, new RectangleF(hue.X - P(6), hue.Y, hue.Width + P(12), hue.Height));
        if (hotSv && inp.Pressed) ActiveId = idSv;
        if (hotH && inp.Pressed) ActiveId = idH;
        if (ActiveId == idSv && (inp.Down || inp.Released) && inp.X >= 0) {
            s = Math.Max(0, Math.Min(1, (inp.X - box.X) / box.Width));
            v = Math.Max(0, Math.Min(1, 1 - (inp.Y - box.Y) / box.Height));
            changed = true;
        }
        if (ActiveId == idH && (inp.Down || inp.Released) && inp.Y >= 0) {
            h = Math.Max(0, Math.Min(359.9, (inp.Y - hue.Y) / hue.Height * 360));
            changed = true;
        }
        if (inp.Released && (ActiveId == idSv || ActiveId == idH)) LastCommitId = id;

        // markers
        float mx = box.X + (float)(s * box.Width), my = box.Y + (float)((1 - v) * box.Height);
        using (var pen = new Pen(Color.Black, P(3))) g.DrawEllipse(pen, mx - P(6), my - P(6), P(12), P(12));
        using (var pen = new Pen(Color.White, P(1.5f))) g.DrawEllipse(pen, mx - P(6), my - P(6), P(12), P(12));
        float hy = hue.Y + (float)(h / 360 * hue.Height);
        var hm = new RectangleF(hue.X - P(3), hy - P(3), hue.Width + P(6), P(6));
        Fill(hm, Color.White, P(2)); Stroke(hm, Color.Black, P(2), 1f);

        y += sq + P(10);
        return changed;
    }

    // Grid of colour swatches. Returns the clicked index or -1.
    public int Swatches(string id, Color[] colors, int columns) {
        int hit = -1;
        float gap = P(6);
        float w = (x1 - x0 - gap * (columns - 1)) / columns;
        float h = Math.Min(w, P(34));
        for (int i = 0; i < colors.Length; i++) {
            int row = i / columns, col = i % columns;
            var r = new RectangleF(x0 + col * (w + gap), y + row * (h + gap), w, h);
            bool hot, held;
            if (Behave(id + "#" + i, r, out hot, out held)) hit = i;
            Fill(r, colors[i], P(4));
            Stroke(r, hot ? Color.White : Color.FromArgb(90, 0, 0, 0), P(4), hot ? P(2) : 1f);
        }
        int rows = (colors.Length + columns - 1) / columns;
        y += rows * (h + gap) + P(6);
        return hit;
    }

    // Before/after strip for a texture: two thumbnails side by side.
    public void Preview(string beforePath, string afterPath, string caption) {
        float gap = P(8);
        float w = (x1 - x0 - gap) / 2;
        float h = Math.Min(w, P(120));
        var a = new RectangleF(x0, y, w, h);
        var b = new RectangleF(x0 + w + gap, y, w, h);
        foreach (var pair in new[] { Tuple.Create(a, beforePath, "vanilla"), Tuple.Create(b, afterPath, "yours") }) {
            Fill(pair.Item1, Sink, P(6));
            var img = LoadImg(pair.Item2);
            if (img != null) {
                float sc = Math.Min(pair.Item1.Width / img.Width, pair.Item1.Height / img.Height);
                float iw = img.Width * sc, ih = img.Height * sc;
                g.DrawImage(img, pair.Item1.X + (pair.Item1.Width - iw) / 2, pair.Item1.Y + (pair.Item1.Height - ih) / 2, iw, ih);
            }
            float lw = g.MeasureString(pair.Item3, fSmall).Width + P(8);
            var lr = new RectangleF(pair.Item1.X + P(4), pair.Item1.Bottom - P(20), lw, P(16));
            Fill(lr, Color.FromArgb(190, 20, 20, 20), P(4));
            Str(pair.Item3, fSmall, Text, lr, sfCenter);
        }
        y += h + P(4);
        if (!string.IsNullOrEmpty(caption)) Hint(caption);
        y += P(4);
    }

    // Layer row inside a stack: index badge, label, colour chip, up/down/delete.
    // Returns 0 none, 1 open, 2 up, 3 down, 4 delete.
    public int LayerRow(string id, int index, string text, Color chip, bool canUp, bool canDown) {
        float h = P(40);
        var r = new RectangleF(x0, y, x1 - x0, h);
        float bw = P(28);
        var rDel = new RectangleF(r.Right - bw - P(4), r.Y + P(6), bw, h - P(12));
        var rDn = new RectangleF(rDel.X - bw - P(2), rDel.Y, bw, rDel.Height);
        var rUp = new RectangleF(rDn.X - bw - P(2), rDel.Y, bw, rDel.Height);
        var rMain = new RectangleF(r.X, r.Y, rUp.X - r.X - P(4), h);
        int res = 0;
        bool hot, held;
        if (Behave(id, rMain, out hot, out held)) res = 1;
        Fill(r, Card, P(8));
        if (hot || held) Fill(rMain, held ? SageDk : Hover, P(8));
        var badge = new RectangleF(r.X + P(8), r.Y + (h - P(22)) / 2, P(22), P(22));
        Fill(badge, Line, P(11));
        Str((index + 1).ToString(), fSmall, Text, badge, sfCenter);
        float tx = badge.Right + P(8);
        if (!chip.IsEmpty) {
            var cr = new RectangleF(tx, r.Y + (h - P(16)) / 2, P(16), P(16));
            Fill(cr, chip, P(8)); Stroke(cr, Color.FromArgb(110, 0, 0, 0), P(8), 1f);
            tx = cr.Right + P(8);
        }
        Str(text, fBody, Text, new RectangleF(tx, r.Y, rMain.Right - tx, h), sfLeft);
        if (IconButton(id + ".up", rUp, "up", canUp)) res = 2;
        if (IconButton(id + ".dn", rDn, "down", canDown)) res = 3;
        if (IconButton(id + ".del", rDel, "del", true)) res = 4;
        y += h + P(6);
        return res;
    }

    bool IconButton(string id, RectangleF r, string kind, bool enabled) {
        bool hot = false, held = false, clicked = false;
        if (enabled) clicked = Behave(id, r, out hot, out held);
        if (hot || held) Fill(r, held ? SageDk : Hover, P(5));
        Color c = !enabled ? Color.FromArgb(70, 255, 255, 255) : (kind == "del" ? (hot ? Danger : Muted) : (hot ? Text : Muted));
        float cx = r.X + r.Width / 2, cy = r.Y + r.Height / 2, a = P(5);
        using (var pen = new Pen(c, P(1.8f)) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round }) {
            if (kind == "up") g.DrawLines(pen, new[] { new PointF(cx - a, cy + a / 2), new PointF(cx, cy - a / 2), new PointF(cx + a, cy + a / 2) });
            else if (kind == "down") g.DrawLines(pen, new[] { new PointF(cx - a, cy - a / 2), new PointF(cx, cy + a / 2), new PointF(cx + a, cy - a / 2) });
            else { g.DrawLine(pen, cx - a, cy - a, cx + a, cy + a); g.DrawLine(pen, cx - a, cy + a, cx + a, cy - a); }
        }
        return clicked && enabled;
    }

    // Every part of the hero as a thumbnail, so switching part is one tap instead
    // of back-to-the-list-and-in-again. The line underneath names the part under
    // the mouse. Returns the clicked index or -1.
    public int PartStrip(string id, string[] thumbs, string[] names, int sel, string idleCaption) {
        int hit = -1;
        float side = P(48), gap = P(6), x = x0;
        string caption = idleCaption;
        for (int i = 0; i < thumbs.Length; i++) {
            if (x + side > x1 + 0.5f && x > x0) { x = x0; y += side + gap; }
            var r = new RectangleF(x, y, side, side);
            bool hot, held;
            if (Behave(id + "#" + i, r, out hot, out held)) hit = i;
            Fill(r, Sink, P(6));
            var img = LoadImg(thumbs[i]);
            if (img != null) {
                using (var path = Round(r, P(6))) {
                    var save = g.Clip; g.SetClip(path, CombineMode.Intersect);
                    g.DrawImage(img, r);
                    // the others step back so the current one reads at a glance
                    if (i != sel && !hot) using (var br = new SolidBrush(Color.FromArgb(110, 20, 20, 20))) g.FillRectangle(br, r);
                    g.Clip = save;
                }
            }
            if (i == sel) Stroke(r, Sage, P(6), P(3f));
            else if (hot || held) Stroke(r, held ? SageDk : Text, P(6), P(2f));
            if (hot && i < names.Length) caption = (i == sel ? "Editing: " : "Go to: ") + names[i];
            x += side + gap;
        }
        y += side + P(4);
        Str(caption, fTiny, Muted, new RectangleF(x0, y, x1 - x0, P(20)), sfLeft);
        y += P(26);
        return hit;
    }

    // The layer stack as tabs: number, colour dot, name. The selected tab is
    // sage and its controls are drawn right under the row, on the same screen.
    // A trailing tab (addText) adds a layer. Returns the clicked index,
    // labels.Length for the add tab, or -1.
    public int LayerTabs(string id, string[] labels, Color[] chips, int sel, string addText) {
        int hit = -1;
        float gap = P(6), h = P(40), x = x0;
        int n = labels.Length + (string.IsNullOrEmpty(addText) ? 0 : 1);
        for (int i = 0; i < n; i++) {
            bool add = i == labels.Length;
            string text = add ? addText : labels[i];
            bool chip = !add && chips != null && i < chips.Length && !chips[i].IsEmpty;
            float tw = g.MeasureString(text, fBody).Width;
            float w = add ? tw + P(24) : P(10) + P(22) + P(8) + (chip ? P(16) + P(6) : 0) + tw + P(12);
            if (x + w > x1 && x > x0) { x = x0; y += h + gap; }
            var r = new RectangleF(x, y, Math.Min(w, x1 - x0), h);
            bool hot, held;
            if (Behave(id + "#" + i, r, out hot, out held)) hit = i;
            bool on = !add && i == sel;
            Color fill = held ? SageDk : (on ? Sage : (hot ? Hover : (add ? Card : Raised)));
            Color fg = on ? Color.FromArgb(24, 30, 22) : (add ? SageLt : Text);
            Fill(r, fill, P(8));
            if (add) {
                Stroke(r, hot ? SageLt : Line, P(8), 1f);
                Str(text, fBold, fg, r, sfCenter);
            } else {
                var badge = new RectangleF(r.X + P(10), r.Y + (h - P(22)) / 2, P(22), P(22));
                Fill(badge, on ? Color.FromArgb(60, 0, 0, 0) : Line, P(11));
                Str((i + 1).ToString(), fSmall, on ? Color.FromArgb(24, 30, 22) : Text, badge, sfCenter);
                float tx = badge.Right + P(8);
                if (chip) {
                    var cr = new RectangleF(tx, r.Y + (h - P(16)) / 2, P(16), P(16));
                    Fill(cr, chips[i], P(8)); Stroke(cr, Color.FromArgb(110, 0, 0, 0), P(8), 1f);
                    tx = cr.Right + P(6);
                }
                Str(text, on ? fBold : fBody, fg, new RectangleF(tx, r.Y, r.Right - tx - P(4), h), sfLeft);
            }
            x += w + gap;
        }
        y += h + P(10);
        return hit;
    }

    // One step of a job (the Build mod screen): a status disc, the step's name,
    // and a muted line under it. state: 0 waiting, 1 running, 2 done,
    // 3 failed, 4 skipped.
    public void Step(string text, string sub, int state) {
        float h = P(string.IsNullOrEmpty(sub) ? 34 : 52);
        var disc = new RectangleF(x0 + P(2), y + P(5), P(22), P(22));
        Color ring = state == 2 ? Sage : (state == 3 ? Danger : (state == 1 ? SageLt : Line));
        if (state == 2 || state == 3) Fill(disc, ring, P(11));
        else using (var path = Round(disc, P(11))) using (var pen = new Pen(ring, P(2f))) g.DrawPath(pen, path);
        float cx = disc.X + disc.Width / 2, cy = disc.Y + disc.Height / 2, a = P(5);
        if (state == 1) Fill(new RectangleF(cx - P(4), cy - P(4), P(8), P(8)), SageLt, P(4));
        using (var pen = new Pen(Color.FromArgb(24, 30, 22), P(2.2f)) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round }) {
            if (state == 2) g.DrawLines(pen, new[] { new PointF(cx - a, cy), new PointF(cx - a / 3, cy + a * 0.7f), new PointF(cx + a, cy - a * 0.6f) });
            else if (state == 3) { g.DrawLine(pen, cx - a * 0.7f, cy - a * 0.7f, cx + a * 0.7f, cy + a * 0.7f); g.DrawLine(pen, cx - a * 0.7f, cy + a * 0.7f, cx + a * 0.7f, cy - a * 0.7f); }
        }
        if (state == 4) using (var pen = new Pen(Faint, P(2f))) g.DrawLine(pen, disc.X + P(6), cy, disc.Right - P(6), cy);
        float tx = disc.Right + P(10);
        Color fg = (state == 0 || state == 4) ? Muted : (state == 3 ? Danger : Text);
        Str(text, state == 1 ? fBold : fBody, fg, new RectangleF(tx, y + P(4), x1 - tx, P(24)), sfLeft);
        if (!string.IsNullOrEmpty(sub)) Str(sub, fTiny, state == 3 ? Amber : Muted, new RectangleF(tx, y + P(28), x1 - tx, P(20)), sfLeft);
        y += h + P(4);
    }

    // Busy veil over everything: shown while textures render.
    public void Veil(string text) {
        float top = titleH > 0 ? titleH + 1 : 0;
        using (var br = new SolidBrush(Color.FromArgb(150, 20, 20, 20))) g.FillRectangle(br, 0, top, W, H - top);
        var r = new RectangleF(P(40), H / 2 - P(26), W - P(80), P(52));
        Fill(r, Card, P(10)); Stroke(r, Sage, P(10), P(1.5f));
        Str(text, fBold, SageLt, r, sfCenter);
    }
}

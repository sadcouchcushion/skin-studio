# ============================================================================
# Variant Skin Studio - the studio's own look.
#
# This is the Variant UI chrome (C:\rs\ThemeStudio\ThemeStudio.ps1) lifted into
# a module of its own so the two studios are visibly the same product: same
# neutral-grey surfaces, same rounded owner-drawn buttons and cards, same
# hand-painted sliders / drop-downs / colour picker, same dark title bar and
# scrollbars, same Black Ops One display face.
#
# The ONE difference is the accent: Variant UI wears the logo pink, and Skin
# Studio wears a light sage green. Everything else is byte-for-byte the code
# that already ships in Variant UI, so a fix there ports here by re-running
# build-vuistyle.ps1 (kept beside this file) rather than by hand-editing.
#
# To re-skin the whole studio, change the four Sage* entries below - nothing
# else in the app names an accent colour.
#
# Dot-source it AFTER Add-Type for System.Windows.Forms / System.Drawing:
#     . "$PSScriptRoot\vuistyle.ps1"
# ============================================================================

# ---- palette ---------------------------------------------------------------
# Neutral greys on purpose: the studio is a frame around the skin YOU are
# recolouring, so nothing in the chrome should compete with the texture
# previews. Every surface is exactly R=G=B, exactly as in Variant UI.
#
# The accent is rationed the same way the pink is over there - the wordmark,
# the thing you are on, and the one button that commits - so it always means
# "here".
#
# Sage is 158,189,148: the pink's own HSL, walked round to a green hue and let
# down to a soft, light sage (HSL 105 / 24% / 66%). It is a LIGHT accent, which
# is the one place this palette departs from Variant UI's: white on sage is a
# 2.0:1 contrast and unreadable, so filled accent buttons carry near-black
# labels (8.5:1) instead of white ones. Sage on the grey panels reads 7.3:1.
$Pal = @{
  Bg      = [System.Drawing.Color]::FromArgb(27,27,27)     # app background
  Panel   = [System.Drawing.Color]::FromArgb(40,40,40)     # cards / grouped areas
  # the card gradient stays deliberately shallow: controls that fill a flat
  # rectangle (check boxes, and anything sampling SurfaceOf) can only match ONE
  # point on it, so a strong gradient would outline each in a slightly-wrong box
  CardTop = [System.Drawing.Color]::FromArgb(44,44,44)     # card gradient - top
  CardBot = [System.Drawing.Color]::FromArgb(37,37,37)     # card gradient - bottom
  Panel2  = [System.Drawing.Color]::FromArgb(52,52,52)     # inputs, lists, raised bits
  PanelHi = [System.Drawing.Color]::FromArgb(67,67,67)     # hover
  Line    = [System.Drawing.Color]::FromArgb(74,74,74)     # hairlines / borders
  Text    = [System.Drawing.Color]::FromArgb(233,233,233)  # primary text
  Muted   = [System.Drawing.Color]::FromArgb(155,155,155)  # secondary text / hints
  Faint   = [System.Drawing.Color]::FromArgb(118,118,118)  # disabled-ish
  Sage    = [System.Drawing.Color]::FromArgb(158,189,148)  # THE accent - used sparingly
  SageLt  = [System.Drawing.Color]::FromArgb(190,214,182)  # sage text on grey
  SageDk  = [System.Drawing.Color]::FromArgb(116,146,107)  # pressed
  SageHi  = [System.Drawing.Color]::FromArgb(176,203,167)  # hover on a filled accent
  SageWash= [System.Drawing.Color]::FromArgb(60,60,60)     # hover fill (neutral)
  Amber   = [System.Drawing.Color]::FromArgb(228,172,102)  # warnings only
  Sink    = [System.Drawing.Color]::FromArgb(31,31,31)     # image wells / preview backdrops
}
function PalDim([System.Drawing.Color]$c,[double]$f){
  [System.Drawing.Color]::FromArgb(255,[int]($c.R*$f),[int]($c.G*$f),[int]($c.B*$f))
}

# ---- type -------------------------------------------------------------------
# Segoe UI Variable is the Windows 11 refresh of Segoe - same metrics family,
# noticeably cleaner at small sizes. Everything is resolved against the fonts
# actually installed, so an older Windows falls back to plain Segoe UI rather
# than Microsoft Sans Serif.
function HasFont($name){
  if(-not $script:instFams){
    $script:instFams=@{}
    foreach($ff in (New-Object System.Drawing.Text.InstalledFontCollection).Families){ $script:instFams[$ff.Name]=$true }
  }
  return $script:instFams.ContainsKey($name)
}
function PickFam($prefs){ foreach($p in $prefs){ if(HasFont $p){ return $p } } return 'Segoe UI' }
$FamBody  = PickFam @('Segoe UI Variable Text','Segoe UI')
$FamHead  = PickFam @('Segoe UI Variable Display','Segoe UI Semibold','Segoe UI')
$FamBrand = PickFam @('Bahnschrift SemiBold','Bahnschrift','Segoe UI Semibold','Segoe UI')
function UIFont([double]$size,$style,$fam){
  if(-not $fam){ $fam=$FamBody }
  if($null -eq $style){ $style=[System.Drawing.FontStyle]::Regular }
  New-Object System.Drawing.Font($fam,$size,$style)
}
# the font dialogs inherit, so DressDialog does not have to reach for a form
$script:VuiBaseFont = UIFont 9

# ---- the display face for headers ------------------------------------------
# Black Ops One, shipped in branding\ under the SIL OFL, so it lands on another
# machine without anyone installing anything. Two traps:
#
#  1. It must be built from the PrivateFontCollection's FontFamily OBJECT.
#     New-Object Font('Black Ops One',...) goes through GDI+, which only knows
#     INSTALLED families - on a machine without it that quietly hands back
#     Microsoft Sans Serif instead of failing, so it looks fine here and wrong
#     for everyone else. A Font built from the collection's family paints
#     correctly under BOTH renderers the studio uses - GDI for Labels, GDI+ for
#     the hand-drawn headers.
#  2. The collection has to outlive every Font made from it, so it is held in
#     script scope. Letting it fall out of scope repaints headers as garbage.
#
# It is a single-weight display face, so headers ask for Regular - a synthesized
# Bold just blobs the counters shut.
$script:funPfc = $null; $script:famFun = $null
foreach($fp in @("$PSScriptRoot\branding\BlackOpsOne-Regular.ttf")){
  if(Test-Path -LiteralPath $fp){
    try {
      $pfc = New-Object System.Drawing.Text.PrivateFontCollection
      $pfc.AddFontFile($fp)
      if($pfc.Families.Count -gt 0){ $script:funPfc = $pfc; $script:famFun = $pfc.Families[0] }
    } catch { $script:funPfc = $null; $script:famFun = $null }
    break
  }
}
# A header in the display face. $fallback is the size the same header would use
# in Segoe bold, so a missing branding\ folder just looks like a plain dark app -
# Black Ops One runs ~18% wider, hence the smaller nominal size.
function FunFont([double]$size,[double]$fallback){
  if($script:famFun){
    try { return (New-Object System.Drawing.Font($script:famFun,$size,[System.Drawing.FontStyle]::Regular)) } catch {}
  }
  if($fallback -le 0){ $fallback = $size }
  return (UIFont $fallback ([System.Drawing.FontStyle]::Bold) $FamHead)
}

# ---- the mark ---------------------------------------------------------------
# The Variant lockup and the V badge, recoloured to sage by branding\build-
# branding.ps1 from the pink originals in ThemeStudio\branding. Missing wordmark
# = badge + type; missing both = text-only.
#
# Loaded through a MemoryStream, never Bitmap::FromFile - FromFile keeps a lock
# on the file for as long as the bitmap lives, which would mean the studio held
# its own branding open and you could not replace the artwork without closing it.
function LoadBrandPng($paths){
  foreach($p in $paths){
    if(Test-Path -LiteralPath $p){
      try {
        $bytes = [System.IO.File]::ReadAllBytes($p)
        $ms = New-Object System.IO.MemoryStream(,$bytes)
        $src = [System.Drawing.Image]::FromStream($ms)
        $bmp = New-Object System.Drawing.Bitmap($src.Width,$src.Height,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.DrawImage($src,0,0,$src.Width,$src.Height)
        $g.Dispose(); $src.Dispose(); $ms.Dispose()
        return $bmp
      } catch { }
    }
  }
  return $null
}
$script:markImg = LoadBrandPng @("$PSScriptRoot\branding\variant-sage-mark.png")
$script:wordImg = LoadBrandPng @("$PSScriptRoot\branding\variant-sage-wordmark.png")

# ---- the two things the lifted code reaches for -----------------------------
# VuiColorDialog was written inside Variant UI and uses two of its globals. They
# are declared here so the lifted block needs no edits beyond the owner, which
# build-vuistyle.ps1 repoints at $script:VuiOwnerForm.
#
# The shared ToolTip. The studio's tooltips are little manuals - keep them up
# long enough to actually read. It has to live in script scope: a ToolTip that
# falls out of scope stops showing.
$tt = New-Object System.Windows.Forms.ToolTip
$tt.AutoPopDelay = 32000; $tt.InitialDelay = 400; $tt.ReshowDelay = 100

# The window a modal should be owned by. Set it once, right after the main form
# exists: Set-VuiOwner $frm. Unset is survivable (an unowned dialog still opens)
# but it loses centre-on-parent and the taskbar grouping, so do set it.
# NB not [Form]::ActiveForm - that reads $null often enough to be a trap,
# including under a test harness.
$script:VuiOwnerForm = $null
function Set-VuiOwner($f){ $script:VuiOwnerForm = $f }

# vvv lifted from ThemeStudio.ps1 lines 78-109: HSV helpers (the colour picker square needs HSV, not HSL)
# ---- HSV, for the colour picker ---------------------------------------------
# HSL above is what the theme engine thinks in; the picker's square needs HSV,
# where the top-right corner is the pure hue. Color.GetSaturation/GetBrightness
# are HSL and will NOT substitute - HSL saturation stays 1.0 all the way down a
# column that HSV reads as running to black.
function ColorToHsv([System.Drawing.Color]$c){
  $r=$c.R/255.0; $g=$c.G/255.0; $b=$c.B/255.0
  $mx=[Math]::Max($r,[Math]::Max($g,$b)); $mn=[Math]::Min($r,[Math]::Min($g,$b))
  $d=$mx-$mn; $h=0.0
  if($d -gt 0){
    if($mx -eq $r){ $h=60.0*((($g-$b)/$d)%6.0) }
    elseif($mx -eq $g){ $h=60.0*((($b-$r)/$d)+2.0) }
    else{ $h=60.0*((($r-$g)/$d)+4.0) }
  }
  if($h -lt 0){ $h+=360.0 }
  @{ h=$h; s=$(if($mx -le 0){0.0}else{$d/$mx}); v=$mx }
}
function HsvToColor([double]$h,[double]$s,[double]$v){
  $h=(($h % 360.0)+360.0)%360.0
  $s=[Math]::Min(1.0,[Math]::Max(0.0,$s)); $v=[Math]::Min(1.0,[Math]::Max(0.0,$v))
  $c=$v*$s; $x=$c*(1.0-[Math]::Abs(((($h/60.0)%2.0))-1.0)); $m=$v-$c
  switch([int][Math]::Floor($h/60.0)){
    0 { $r=$c;$g=$x;$b=0.0 }
    1 { $r=$x;$g=$c;$b=0.0 }
    2 { $r=0.0;$g=$c;$b=$x }
    3 { $r=0.0;$g=$x;$b=$c }
    4 { $r=$x;$g=0.0;$b=$c }
    default { $r=$c;$g=0.0;$b=$x }
  }
  [System.Drawing.Color]::FromArgb(255,
    [int][Math]::Round(($r+$m)*255.0),[int][Math]::Round(($g+$m)*255.0),[int][Math]::Round(($b+$m)*255.0))
}

# vvv lifted from ThemeStudio.ps1 lines 164-185: PickScreenColor - the eyedropper
function PickScreenColor {
  $vs=[System.Windows.Forms.SystemInformation]::VirtualScreen
  $shot=New-Object System.Drawing.Bitmap($vs.Width,$vs.Height)
  $g=[System.Drawing.Graphics]::FromImage($shot)
  $g.CopyFromScreen($vs.X,$vs.Y,0,0,$shot.Size); $g.Dispose()
  $script:eyeDropPick=$null
  $f=New-Object System.Windows.Forms.Form
  $f.FormBorderStyle='None'; $f.StartPosition='Manual'; $f.ShowInTaskbar=$false; $f.TopMost=$true; $f.KeyPreview=$true
  $f.Bounds=New-Object System.Drawing.Rectangle($vs.X,$vs.Y,$vs.Width,$vs.Height)
  $pb=New-Object System.Windows.Forms.PictureBox
  $pb.Dock='Fill'; $pb.Image=$shot; $pb.SizeMode='Normal'; $pb.Cursor=[System.Windows.Forms.Cursors]::Cross
  $f.Controls.Add($pb)
  $pb.Add_MouseClick({ param($s,$e)
    $script:eyeDropPick=([System.Drawing.Bitmap]$this.Image).GetPixel($e.X,$e.Y)
    $this.FindForm().Close()
  })
  $f.Add_KeyDown({ param($s,$e) if($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape){ $this.Close() } })
  [void]$f.ShowDialog()
  $pb.Image=$null; $shot.Dispose(); $f.Dispose()
  if($script:eyeDropPick){ return [System.Drawing.Color]::FromArgb(255,$script:eyeDropPick.R,$script:eyeDropPick.G,$script:eyeDropPick.B) }
  return $null
}

# vvv lifted from ThemeStudio.ps1 lines 343-563: rounded / gradient painting: RoundControl, cards, sinks
# ---- rounded / gradient painting -------------------------------------------
function RoundedPath([single]$x,[single]$y,[single]$w,[single]$h,[single]$r){
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  if($r -le 0){ $p.AddRectangle((New-Object System.Drawing.RectangleF($x,$y,$w,$h))); return $p }
  $d = $r*2
  $p.AddArc($x,$y,$d,$d,180,90)
  $p.AddArc(($x+$w-$d),$y,$d,$d,270,90)
  $p.AddArc(($x+$w-$d),($y+$h-$d),$d,$d,0,90)
  $p.AddArc($x,($y+$h-$d),$d,$d,90,90)
  $p.CloseFigure()
  return $p
}
function DoubleBuffer($ctl){
  try {
    $pr=[System.Windows.Forms.Control].GetProperty('DoubleBuffered',[System.Reflection.BindingFlags]'Instance,NonPublic')
    $pr.SetValue($ctl,$true,$null)
  } catch {}
}
# the area BETWEEN an outer rectangle and an inner rounded outline, as one path.
# Two subpaths under the Alternate fill rule = a ring, and FillPath antialiases -
# where Region.Exclude + FillRegion, which this replaced, could not.
function RingPath([single]$w,[single]$h,$inner){
  $p=New-Object System.Drawing.Drawing2D.GraphicsPath
  $p.AddRectangle((New-Object System.Drawing.RectangleF(0,0,$w,$h)))
  $p.AddPath($inner,$false)
  $p.FillMode=[System.Drawing.Drawing2D.FillMode]::Alternate
  return $p
}
# Rounded corners, antialiased.
#
# This used to clip the control to a Region. GDI+ rasterises a Region as a 1-bit
# scanline mask - a pixel is wholly in or wholly out, there is no partial
# coverage - so every curve came out as a visible staircase. That was tolerable
# while the app was near-black on near-black, but the neutral-grey restyle put
# real contrast across those edges and the facets became obvious: worst on the
# round colour chips, which are curve the whole way round and read as polygons.
#
# So each button paints itself instead: the surface it sits on, then an
# antialiased fill of its own shape. It reads BackColor / ForeColor /
# FlatAppearance off the control, which is where every button already declares
# its look, so none of the ~100 call sites change - primary sage, accent, amber
# and the plain grey buttons all keep exactly the styling they set.
$script:btnRound = @{}
function RoundControl($ctl,[int]$radius,[bool]$circle=$false){
  try {
    if($ctl.Width -lt 4 -or $ctl.Height -lt 4){ return }
    # StyleTree runs again for dialogs and runtime-built toggles - update the
    # shape but never stack a second Paint handler on the same control
    if($script:btnRound.ContainsKey($ctl)){
      $script:btnRound[$ctl].R=$radius; $script:btnRound[$ctl].Circle=$circle
      $ctl.Invalidate(); return
    }
    $script:btnRound[$ctl]=@{ R=$radius; Circle=$circle; Hover=$false; Down=$false }
    DoubleBuffer $ctl
    $ctl.FlatStyle='Flat'
    $ctl.FlatAppearance.BorderSize=0        # we draw the edge on the rounded path
    $ctl.Add_MouseEnter({ $st=$script:btnRound[$this]; if($st){ $st.Hover=$true;  $this.Invalidate() } })
    $ctl.Add_MouseLeave({ $st=$script:btnRound[$this]; if($st){ $st.Hover=$false; $st.Down=$false; $this.Invalidate() } })
    $ctl.Add_MouseDown({  $st=$script:btnRound[$this]; if($st){ $st.Down=$true;   $this.Invalidate() } })
    $ctl.Add_MouseUp({    $st=$script:btnRound[$this]; if($st){ $st.Down=$false;  $this.Invalidate() } })
    $ctl.Add_EnabledChanged({ $this.Invalidate() })
    $ctl.Add_Paint({ param($s,$e) PaintRoundBtn $s $e })
    # every modal the studio opens runs StyleTree over throwaway controls; without
    # this the table would hold them alive for the life of the process
    $ctl.Add_Disposed({ try { $script:btnRound.Remove($this) } catch {} })
    $ctl.Invalidate()
  } catch {}
}
function PaintRoundBtn($s,$e){
  $st=$script:btnRound[$s]; if(-not $st){ return }
  $g=$e.Graphics; $g.SmoothingMode='AntiAlias'
  # Without this GDI+ puts pixel centres ON the integer grid, so an edge at x=0
  # cuts pixel 0 in half and every straight side ramps over 2px. Half moves the
  # centres to +0.5: whole-pixel edges land crisp, arcs still antialias.
  $g.PixelOffsetMode='Half'
  [single]$w=$s.Width; [single]$h=$s.Height
  if($w -lt 4 -or $h -lt 4){ return }
  # 1. erase the flat rectangle WinForms just painted, back to whatever the
  #    button sits on - the card gradient sampled at this control's own height
  $back=SurfaceOf $s
  $bb=New-Object System.Drawing.SolidBrush($back); $g.FillRectangle($bb,0,0,$s.Width,$s.Height); $bb.Dispose()
  # 2. the button's own shape, in its own colour, with the hover/press shifts
  #    FlatAppearance used to apply for us.
  #    The FILL runs on whole-pixel geometry and the STROKE on half-pixel: a fill
  #    edge landing mid-pixel makes GDI+ ramp it over ~2px, which left every
  #    straight side looking soft. On whole pixels the flat runs stay crisp and
  #    only the arcs - the part that actually needs it - are antialiased.
  $rad=[Math]::Min($st.R,[Math]::Floor([Math]::Min($w,$h)/2))
  if($st.Circle){
    $p=New-Object System.Drawing.Drawing2D.GraphicsPath;  $p.AddEllipse(0,0,$w,$h)
    $q=New-Object System.Drawing.Drawing2D.GraphicsPath;  $q.AddEllipse(0.5,0.5,($w-1),($h-1))
  } else {
    $p=RoundedPath 0 0 $w $h $rad
    $q=RoundedPath 0.5 0.5 ($w-1) ($h-1) $rad
  }
  $fill=$s.BackColor
  if(-not $s.Enabled){ $fill=if($s.BackColor.GetSaturation() -gt 0.12){ $Pal.Panel2 } else { PalDim $s.BackColor 0.72 } }
  elseif($st.Down -and $s.FlatAppearance.MouseDownBackColor.A -gt 0){ $fill=$s.FlatAppearance.MouseDownBackColor }
  elseif($st.Hover -and $s.FlatAppearance.MouseOverBackColor.A -gt 0){ $fill=$s.FlatAppearance.MouseOverBackColor }
  $fb=New-Object System.Drawing.SolidBrush($fill); $g.FillPath($fb,$p); $fb.Dispose()
  # 3. the edge. BorderSize was zeroed so WinForms would not draw a square one,
  #    so a swatch/plain button is edged unless it deliberately went borderless
  #    (the sage primary), which is what BorderColor being unset signals
  $bc=$s.FlatAppearance.BorderColor
  if($bc.A -gt 0 -and $bc -ne [System.Drawing.Color]::Empty -and $bc.ToArgb() -ne $s.BackColor.ToArgb()){
    $pn=New-Object System.Drawing.Pen($bc,1); $g.DrawPath($pn,$q); $pn.Dispose()
  }
  $q.Dispose()
  # 4. keyboard focus needs to stay visible now that we own the whole surface
  if($s.Focused -and $s.Text){
    $ip=if($st.Circle){
      $fe=New-Object System.Drawing.Drawing2D.GraphicsPath; $fe.AddEllipse(2.5,2.5,($w-5),($h-5)); $fe
    } else {
      RoundedPath 2.5 2.5 ($w-5) ($h-5) ([Math]::Max(1,$rad-2))
    }
    $fp=New-Object System.Drawing.Pen($Pal.Muted,1); $fp.DashStyle='Dot'
    $g.DrawPath($fp,$ip); $fp.Dispose(); $ip.Dispose()
  }
  $p.Dispose()
  # 5. an image, if one was ever set - no button carries one today, but a future
  #    one would otherwise vanish without a word
  if($s.Image){
    $iw=[Math]::Min($s.Image.Width,$s.Width-6); $ih=[Math]::Min($s.Image.Height,$s.Height-6)
    $g.InterpolationMode='HighQualityBicubic'
    $g.DrawImage($s.Image,[int](($s.Width-$iw)/2),[int](($s.Height-$ih)/2),$iw,$ih)
  }
  # 6. the label, through TextRenderer so it matches every other WinForms caption
  if($s.Text){
    $fc=if($s.Enabled){ $s.ForeColor } else { $Pal.Faint }
    $r=New-Object System.Drawing.Rectangle(2,1,($s.Width-4),($s.Height-2))
    $al=[string]$s.TextAlign
    $ff=[System.Windows.Forms.TextFormatFlags]::EndEllipsis
    $ff=$ff -bor $(if($al -like '*Left'){ [System.Windows.Forms.TextFormatFlags]::Left }
                   elseif($al -like '*Right'){ [System.Windows.Forms.TextFormatFlags]::Right }
                   else { [System.Windows.Forms.TextFormatFlags]::HorizontalCenter })
    $ff=$ff -bor $(if($al -like 'Top*'){ [System.Windows.Forms.TextFormatFlags]::Top }
                   elseif($al -like 'Bottom*'){ [System.Windows.Forms.TextFormatFlags]::Bottom }
                   else { [System.Windows.Forms.TextFormatFlags]::VerticalCenter })
    [System.Windows.Forms.TextRenderer]::DrawText($g,$s.Text,$s.Font,$r,$fc,$ff)
  }
}
# a "card": subtle top-to-bottom gradient inside a rounded, hairlined outline.
# Painted rather than styled, because WinForms panels can do neither.
# a "sink": the recessed well that images and previews sit in
function PaintSink($ctl,[int]$radius){
  DoubleBuffer $ctl
  $ctl.Tag = "keep-card r$radius"
  $ctl.Add_Paint({
    param($s,$e)
    $gfx=$e.Graphics; $gfx.SmoothingMode='AntiAlias'
    $rad = if(([string]$s.Tag) -match 'r(\d+)'){ [int]$matches[1] } else { 10 }
    $bg = if($s.Parent){ $s.Parent.BackColor } else { $Pal.Bg }
    $sb=New-Object System.Drawing.SolidBrush($bg)
    $gfx.FillRectangle($sb,0,0,$s.Width,$s.Height); $sb.Dispose()
    $path=RoundedPath 0.5 0.5 ($s.Width-1.5) ($s.Height-1.5) $rad
    $fb=New-Object System.Drawing.SolidBrush($Pal.Sink); $gfx.FillPath($fb,$path); $fb.Dispose()
    $pn=New-Object System.Drawing.Pen($Pal.Line,1); $gfx.DrawPath($pn,$path); $pn.Dispose(); $path.Dispose()
  })
}
# The gradient lives in the control's BackgroundImage, NOT in a Paint handler:
# WinForms composites a BackgroundImage correctly underneath transparent child
# labels, whereas a Paint-drawn gradient is re-run from the top for each one -
# stamping a slightly-too-light rectangle behind every caption.
function SetGradientBg($ctl){
  try {
    $gh=[Math]::Max(2,$ctl.Height)
    $bmp=New-Object System.Drawing.Bitmap(2,$gh,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $gg=[System.Drawing.Graphics]::FromImage($bmp)
    $lg=New-Object System.Drawing.Drawing2D.LinearGradientBrush(
          (New-Object System.Drawing.Point(0,0)),(New-Object System.Drawing.Point(0,$gh)),
          $Pal.CardTop,$Pal.CardBot)
    $gg.FillRectangle($lg,0,0,2,$gh); $lg.Dispose(); $gg.Dispose()
    $ctl.BackgroundImage=$bmp
    $ctl.BackgroundImageLayout='Stretch'
  } catch {}
}
$script:cardTitle = @{}
function PaintCard($ctl,[int]$radius,$title){
  DoubleBuffer $ctl
  SetGradientBg $ctl
  $ctl.Tag = "keep-card r$radius"
  # A GroupBox draws its own etched frame and caption before our Paint runs, so
  # take the caption off it and redraw it ourselves - otherwise the title shows
  # twice, slightly offset.
  $ttl = if($title){ $title } elseif($ctl -is [System.Windows.Forms.GroupBox]){ [string]$ctl.Text } else { '' }
  if($ttl){ $script:cardTitle[$ctl] = $ttl }
  if($ctl -is [System.Windows.Forms.GroupBox]){ $ctl.Text='' }
  $ctl.Add_Paint({
    param($s,$e)
    $gfx=$e.Graphics
    $gfx.SmoothingMode='AntiAlias'; $gfx.TextRenderingHint='ClearTypeGridFit'
    $rad = if(([string]$s.Tag) -match 'r(\d+)'){ [int]$matches[1] } else { 10 }
    $bg = if($s.Parent){ $s.Parent.BackColor } else { $Pal.Bg }
    # erase the native frame by redrawing the outer band from the control's OWN
    # background image - same bitmap, same rect, so there is no seam to spot
    if($s.BackgroundImage){
      $band=New-Object System.Drawing.Region((New-Object System.Drawing.Rectangle(0,0,$s.Width,$s.Height)))
      $band.Exclude((New-Object System.Drawing.Rectangle(3,20,($s.Width-6),($s.Height-23))))
      $gfx.SetClip($band,[System.Drawing.Drawing2D.CombineMode]::Replace)
      $gfx.DrawImage($s.BackgroundImage,0,0,$s.Width,$s.Height)
      $gfx.ResetClip(); $band.Dispose()
    }
    $path=RoundedPath 0.5 0.5 ($s.Width-1.5) ($s.Height-1.5) $rad
    # knock the four corners back to whatever sits behind the card, then edge it.
    # An AA ring fill, not Region.Exclude + FillRegion - a Region is a 1-bit mask,
    # so that left a stair-stepped notch under the smooth outline.
    $ring=RingPath $s.Width $s.Height $path
    $sb=New-Object System.Drawing.SolidBrush($bg); $gfx.FillPath($sb,$ring); $sb.Dispose(); $ring.Dispose()
    $pn=New-Object System.Drawing.Pen($Pal.Line,1)
    $gfx.DrawPath($pn,$path); $pn.Dispose(); $path.Dispose()
    $ttl2 = [string]$script:cardTitle[$s]
    if($ttl2){
      $f=FunFont 8.25 9
      $tb=New-Object System.Drawing.SolidBrush($Pal.Text)
      $gfx.DrawString($ttl2,$f,$tb,14,3)
      $f.Dispose(); $tb.Dispose()
    }
  })
  $ctl.Invalidate()
}


# vvv lifted from ThemeStudio.ps1 lines 564-954: VuiSlider + VuiCombo (our own slider and drop-down)
# ---- sliders and drop-downs: our own, because Windows' are not ours ---------
# Everything else in the studio is hand-painted (RoundControl, the cards, the
# tab bar), but TrackBar and ComboBox are Win32 common controls: they paint
# themselves from the SYSTEM theme and ignore BackColor for everything except
# the bit behind the text. So a slider stayed a chunky grey channel with a
# system-blue focus, and a drop-down kept a raised light button, a hard square
# frame and a bright blue selection bar in its list - the two loudest reminders
# that this is a WinForms app sitting inside an otherwise custom interface.
#
# VuiSlider is a Control that draws the whole thing; VuiCombo is a ComboBox that
# owner-draws its items and repaints its own frame/arrow after Windows has had
# its go (WM_PAINT for the screen, WM_PRINTCLIENT so DrawToBitmap captures it
# too - see the verification note in the corner-AA work).
#
# Both keep the exact API the studio already used - Value/Minimum/Maximum/
# TickFrequency/ValueChanged, and every ComboBox member - so the ~120 call sites
# and 17 sliders did not change. Colors come from $Pal via the static fields
# below: the palette stays the one place a color is decided.
#
# The rule the look follows: quiet by default, SAGE ONLY UNDER YOUR HAND. A
# slider thumb and a drop-down's chevron/edge go sage while you are dragging,
# hovering or have the list open, and are neutral grey otherwise - so sage still
# means "here", same as the browse mode you are in and the button that commits.
if(-not ('VuiSlider' -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class VuiDraw {
  public static GraphicsPath Round(float x,float y,float w,float h,float r){
    GraphicsPath p = new GraphicsPath();
    if(r <= 0 || w <= 0 || h <= 0){ p.AddRectangle(new RectangleF(x,y,Math.Max(1,w),Math.Max(1,h))); return p; }
    if(r > w/2f) r = w/2f;
    if(r > h/2f) r = h/2f;
    float d = r*2;
    p.AddArc(x,y,d,d,180,90);
    p.AddArc(x+w-d,y,d,d,270,90);
    p.AddArc(x+w-d,y+h-d,d,d,0,90);
    p.AddArc(x,y+h-d,d,d,90,90);
    p.CloseFigure();
    return p;
  }
  // outer rectangle + inner path under the Alternate fill rule = an antialiased
  // ring. Same trick as RingPath in the PowerShell above; a Region would give a
  // 1-bit staircase instead.
  public static GraphicsPath Ring(float w,float h,GraphicsPath inner){
    GraphicsPath p = new GraphicsPath();
    p.AddRectangle(new RectangleF(0,0,w,h));
    p.AddPath(inner,false);
    p.FillMode = FillMode.Alternate;
    return p;
  }
  // a chevron, drawn the same way the section headers draw theirs
  public static void Chevron(Graphics g,float cx,float cy,float half,Color c){
    using(Pen pn = new Pen(c,2f)){
      pn.StartCap = LineCap.Round; pn.EndCap = LineCap.Round; pn.LineJoin = LineJoin.Round;
      g.DrawLines(pn,new PointF[]{
        new PointF(cx-half,cy-half/2f), new PointF(cx,cy+half/2f), new PointF(cx+half,cy-half/2f) });
    }
  }
}

public class VuiSlider : Control {
  // set from $Pal right after this type is loaded
  public static Color TrackCol = Color.FromArgb(31,31,31);
  public static Color FillCol  = Color.FromArgb(155,155,155);
  public static Color ThumbCol = Color.FromArgb(233,233,233);
  public static Color HotCol   = Color.FromArgb(208,104,168);
  public static Color EdgeCol  = Color.FromArgb(74,74,74);
  public static Color DisCol   = Color.FromArgb(118,118,118);
  public static Color FocusCol = Color.FromArgb(155,155,155);

  int _thumbD = 14;               // thumb diameter; the track insets by half of it
  float _trackH = 5f;

  int _min = 0, _max = 100, _val = 0, _tick = 10;
  bool _hot, _drag;

  // ---- gradient tracks (the colour picker's R/G/B rows) ---------------------
  // Left alone, a VuiSlider is exactly what it always was: grey groove, filled
  // bar, pale grip. Hand it TrackStops and it drops the fill bar and paints the
  // groove as the ramp itself, so the R slider shows you the colour you are
  // dragging toward instead of a number you have to imagine.
  Color[] _stops = null;
  public Color[] TrackStops {
    get { return _stops; }
    set { _stops = (value != null && value.Length >= 2) ? value : null; Invalidate(); }
  }
  // the resulting colour, painted INTO the grip - a pale grip vanishes on a
  // track that ramps to white (every slider does, at K=0)
  Color _thumbFill = Color.Empty;
  public Color ThumbFill { get { return _thumbFill; } set { _thumbFill = value; Invalidate(); } }
  public float TrackThickness { get { return _trackH; } set { _trackH = Math.Max(2f,value); Invalidate(); } }
  public int ThumbSize { get { return _thumbD; } set { _thumbD = Math.Max(8,value); Invalidate(); } }

  public event EventHandler ValueChanged;

  public VuiSlider(){
    SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
             ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
             ControlStyles.Selectable | ControlStyles.SupportsTransparentBackColor, true);
    TabStop = true;
    Size = new Size(160,30);
    Cursor = Cursors.Hand;
  }

  public int Minimum {
    get { return _min; }
    set { _min = value; if(_max < _min) _max = _min; if(_val < _min) Value = _min; Invalidate(); }
  }
  public int Maximum {
    get { return _max; }
    set { _max = value; if(_min > _max) _min = _max; if(_val > _max) Value = _max; Invalidate(); }
  }
  // kept so AddSlider's call still works; the studio's sliders read as a filled
  // bar, and tick marks under one only added noise
  public int TickFrequency { get { return _tick; } set { _tick = Math.Max(1,value); } }
  public int Value {
    get { return _val; }
    set {
      int v = value;
      if(v < _min) v = _min;
      if(v > _max) v = _max;
      if(v == _val) return;
      _val = v;
      Invalidate();
      if(ValueChanged != null) ValueChanged(this,EventArgs.Empty);
    }
  }

  float TrackX { get { return _thumbD/2f + 1f; } }
  float TrackW { get { return Math.Max(1f, Width - (_thumbD + 2f)); } }
  float ThumbCX {
    get {
      float f = (_max > _min) ? (float)(_val - _min)/(float)(_max - _min) : 0f;
      return TrackX + TrackW*f;
    }
  }

  void SetFromX(int x){
    float f = (x - TrackX)/TrackW;
    if(f < 0f) f = 0f;
    if(f > 1f) f = 1f;
    Value = _min + (int)Math.Round(f*(_max - _min));
  }

  protected override void OnPaint(PaintEventArgs e){
    Graphics g = e.Graphics;
    g.SmoothingMode = SmoothingMode.AntiAlias;
    g.PixelOffsetMode = PixelOffsetMode.Half;   // or every straight edge ramps over 2px
    using(SolidBrush bb = new SolidBrush(BackColor)) g.FillRectangle(bb,0,0,Width,Height);
    bool on = Enabled;
    float ty = (float)Math.Round((Height - _trackH)/2f);
    float cx = ThumbCX, cy = ty + _trackH/2f;
    // the groove
    using(GraphicsPath tr = VuiDraw.Round(TrackX,ty,TrackW,_trackH,_trackH/2f)){
      if(_stops != null && on){
        // the ramp IS the groove. A LinearGradientBrush samples half a pixel
        // outside the rect it was built on, which wraps the far colour onto the
        // near edge - TileFlipX mirrors instead, so both ends stay true.
        RectangleF gr = new RectangleF(TrackX,ty,TrackW,_trackH);
        using(LinearGradientBrush lg = new LinearGradientBrush(gr,_stops[0],_stops[_stops.Length-1],0f)){
          lg.WrapMode = WrapMode.TileFlipX;
          if(_stops.Length > 2){
            ColorBlend cb = new ColorBlend(_stops.Length);
            float[] pos = new float[_stops.Length];
            for(int i=0;i<_stops.Length;i++) pos[i] = (float)i/(_stops.Length-1);
            cb.Colors = _stops; cb.Positions = pos;
            lg.InterpolationColors = cb;
          }
          g.FillPath(lg,tr);
        }
      } else {
        using(SolidBrush b = new SolidBrush(TrackCol)) g.FillPath(b,tr);
      }
      using(Pen pn = new Pen(EdgeCol,1f)) g.DrawPath(pn,tr);
    }
    // how far along it you are. A gradient track already says that with its own
    // colour, and a grey bar over it would only mud the ramp up.
    if(_stops == null){
      float fw = cx - TrackX;
      if(fw > 0.5f){
        using(GraphicsPath fp = VuiDraw.Round(TrackX,ty,Math.Max(_trackH,fw),_trackH,_trackH/2f))
        using(SolidBrush b = new SolidBrush(on ? FillCol : DisCol)) g.FillPath(b,fp);
      }
    }
    // the grip - sage while you are actually on it
    RectangleF th = new RectangleF(cx - _thumbD/2f, cy - _thumbD/2f, _thumbD, _thumbD);
    Color tc = !on ? DisCol : ((_drag || _hot) ? HotCol : ThumbCol);
    if(_stops != null){
      // carry the colour inside the grip and ring it, so it reads against a
      // track that runs white at one end and near-black at the other
      Color core = (_thumbFill.A > 0) ? _thumbFill : tc;
      using(SolidBrush b = new SolidBrush(core)) g.FillEllipse(b,th);
      using(Pen pn = new Pen(tc,2.5f)) g.DrawEllipse(pn,th.X+1.25f,th.Y+1.25f,_thumbD-2.5f,_thumbD-2.5f);
    } else {
      using(SolidBrush b = new SolidBrush(tc)) g.FillEllipse(b,th);
    }
    using(Pen pn = new Pen(EdgeCol,1f)) g.DrawEllipse(pn,th.X+0.5f,th.Y+0.5f,_thumbD-1,_thumbD-1);
    if(Focused && on){
      using(Pen fp = new Pen(FocusCol,1f)){
        fp.DashStyle = DashStyle.Dot;
        g.DrawEllipse(fp,th.X-3.5f,th.Y-3.5f,_thumbD+6,_thumbD+6);
      }
    }
  }

  protected override void OnMouseDown(MouseEventArgs e){
    if(Enabled && e.Button == MouseButtons.Left){
      _drag = true;
      if(CanFocus) Focus();
      SetFromX(e.X);
      Invalidate();
    }
    base.OnMouseDown(e);
  }
  protected override void OnMouseMove(MouseEventArgs e){
    if(_drag && Enabled) SetFromX(e.X);
    base.OnMouseMove(e);
  }
  // state first, THEN the event - the studio hangs AutoPreview off MouseUp and
  // it should see a slider that has finished moving
  protected override void OnMouseUp(MouseEventArgs e){
    if(_drag){ _drag = false; Invalidate(); }
    base.OnMouseUp(e);
  }
  protected override void OnMouseEnter(EventArgs e){ _hot = true;  Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e){ _hot = false; Invalidate(); base.OnMouseLeave(e); }
  protected override void OnGotFocus(EventArgs e){ Invalidate(); base.OnGotFocus(e); }
  protected override void OnLostFocus(EventArgs e){ Invalidate(); base.OnLostFocus(e); }
  protected override void OnEnabledChanged(EventArgs e){ Invalidate(); base.OnEnabledChanged(e); }

  // arrows are dialog-navigation keys unless a control claims them
  protected override bool IsInputKey(Keys keyData){
    Keys k = keyData & Keys.KeyCode;
    if(k == Keys.Left || k == Keys.Right || k == Keys.Up || k == Keys.Down ||
       k == Keys.Home || k == Keys.End || k == Keys.PageUp || k == Keys.Next) return true;
    return base.IsInputKey(keyData);
  }
  protected override void OnKeyDown(KeyEventArgs e){
    int page = Math.Max(1,(_max - _min)/10);
    switch(e.KeyCode){
      case Keys.Left:  case Keys.Down: Value = _val - 1;    e.Handled = true; break;
      case Keys.Right: case Keys.Up:   Value = _val + 1;    e.Handled = true; break;
      case Keys.PageUp:                Value = _val + page; e.Handled = true; break;
      case Keys.Next:                  Value = _val - page; e.Handled = true; break;
      case Keys.Home:                  Value = _min;        e.Handled = true; break;
      case Keys.End:                   Value = _max;        e.Handled = true; break;
    }
    base.OnKeyDown(e);
  }
}

public class VuiCombo : ComboBox {
  public static Color BackCol  = Color.FromArgb(52,52,52);
  public static Color HoverCol = Color.FromArgb(67,67,67);
  public static Color TextCol  = Color.FromArgb(233,233,233);
  public static Color MutedCol = Color.FromArgb(155,155,155);
  public static Color EdgeCol  = Color.FromArgb(74,74,74);
  public static Color HotCol   = Color.FromArgb(208,104,168);
  public static Color DisCol   = Color.FromArgb(118,118,118);
  public static int   Radius   = 6;             // same as the studio's buttons

  const int WM_PAINT = 0x000F, WM_PRINT = 0x0317, WM_PRINTCLIENT = 0x0318;
  const int PRF_CLIENT = 0x00000004;
  const int ArrowW = 20;                        // the strip we repaint over Windows' own button

  bool _hot;
  // the colour BEHIND the control, so the rounded corners can be knocked back to
  // it. StyleTree sets this from SurfaceOf (which samples the card gradient).
  Color _surface = Color.Empty;
  public Color SurfaceColor { get { return _surface; } set { _surface = value; Invalidate(); } }

  public VuiCombo(){
    DropDownStyle = ComboBoxStyle.DropDownList;
    FlatStyle = FlatStyle.Flat;
    DrawMode = DrawMode.OwnerDrawFixed;
    ItemHeight = 18;                            // -> a 24px closed box, the height every row was laid out for
    BackColor = BackCol;
    ForeColor = TextCol;
  }

  Color Surface { get { if(_surface != Color.Empty) return _surface; return Parent != null ? Parent.BackColor : BackCol; } }
  Color Fill    { get { return (Enabled && (_hot || DroppedDown)) ? HoverCol : BackCol; } }

  // The popup list is its own window, so nothing we paint here reaches its frame
  // or its scrollbar (the pattern/accent lists are long enough to grow one).
  // Same undocumented uxtheme route DarkScrollbars uses - wrapped, because on a
  // build without it we simply get the light frame back.
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int left,top,right,bottom; }
  [StructLayout(LayoutKind.Sequential)] struct COMBOBOXINFO {
    public int cbSize; public RECT rcItem; public RECT rcButton; public int stateButton;
    public IntPtr hwndCombo, hwndItem, hwndList; }
  [DllImport("user32.dll")] static extern bool GetComboBoxInfo(IntPtr hWnd, ref COMBOBOXINFO pcbi);
  [DllImport("uxtheme.dll", CharSet=CharSet.Unicode)] static extern int SetWindowTheme(IntPtr hWnd, string sub, string idList);
  protected override void OnHandleCreated(EventArgs e){
    base.OnHandleCreated(e);
    try {
      COMBOBOXINFO ci = new COMBOBOXINFO();
      ci.cbSize = Marshal.SizeOf(typeof(COMBOBOXINFO));
      if(GetComboBoxInfo(Handle, ref ci) && ci.hwndList != IntPtr.Zero)
        SetWindowTheme(ci.hwndList,"DarkMode_Explorer",null);
    } catch {}
  }

  protected override void OnMouseEnter(EventArgs e){ _hot = true;  Invalidate(); base.OnMouseEnter(e); }
  protected override void OnMouseLeave(EventArgs e){ _hot = false; Invalidate(); base.OnMouseLeave(e); }
  protected override void OnDropDown(EventArgs e){ Invalidate(); base.OnDropDown(e); }
  protected override void OnDropDownClosed(EventArgs e){ Invalidate(); base.OnDropDownClosed(e); }
  protected override void OnEnabledChanged(EventArgs e){ Invalidate(); base.OnEnabledChanged(e); }

  // Items in the popup list. The closed box also comes through here
  // (ComboBoxEdit) but only to be filled - DrawChrome paints its text, so the
  // frame, arrow and label are decided in one place.
  protected override void OnDrawItem(DrawItemEventArgs e){
    if(e.Bounds.Height <= 0) return;
    Graphics g = e.Graphics;
    bool edit = (e.State & DrawItemState.ComboBoxEdit) == DrawItemState.ComboBoxEdit;
    bool sel  = !edit && (e.State & DrawItemState.Selected) == DrawItemState.Selected;
    using(SolidBrush b = new SolidBrush(edit ? Fill : (sel ? HoverCol : BackCol))) g.FillRectangle(b,e.Bounds);
    // the list repaints mid-refresh while RefreshAccents/RefreshPatterns rebuild
    // Items, so an index can point past the end for a frame
    if(edit || e.Index < 0 || e.Index >= Items.Count) return;
    // the row you are on wears the same sage bar the active tab does
    if(sel) using(SolidBrush pb = new SolidBrush(HotCol)) g.FillRectangle(pb,e.Bounds.X+2,e.Bounds.Y+2,3,e.Bounds.Height-4);
    TextRenderer.DrawText(g,GetItemText(Items[e.Index]),Font,
      new Rectangle(e.Bounds.X+10,e.Bounds.Y,e.Bounds.Width-14,e.Bounds.Height),
      Enabled ? ForeColor : DisCol,
      TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
  }

  // Windows paints the flat frame and the arrow button from system colours and
  // there is no property that stops it, so we paint over the top of it.
  // WM_PAINT is the screen. The two print messages are DrawToBitmap: a combo is
  // a native control, so which of them comctl32 actually forwards varies -
  // answer both or the control prints in raw Win32 classic chrome (measured:
  // the Accents tab did exactly that when only WM_PRINTCLIENT was handled).
  protected override void WndProc(ref Message m){
    base.WndProc(ref m);
    if(m.Msg == WM_PAINT){
      using(Graphics g = Graphics.FromHwnd(Handle)) DrawChrome(g);
    } else if((m.Msg == WM_PRINTCLIENT || (m.Msg == WM_PRINT && ((int)m.LParam & PRF_CLIENT) != 0))
              && m.WParam != IntPtr.Zero){
      using(Graphics g = Graphics.FromHdc(m.WParam)) DrawChrome(g);
    }
  }

  void DrawChrome(Graphics g){
    int w = Width, h = Height;
    if(w < 6 || h < 6) return;
    g.SmoothingMode = SmoothingMode.AntiAlias;
    g.PixelOffsetMode = PixelOffsetMode.Half;
    g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
    Color fill = Fill;
    // 1. our own surface, over whatever Windows just drew
    using(GraphicsPath p = VuiDraw.Round(0,0,w,h,Radius))
    using(SolidBrush b = new SolidBrush(fill)) g.FillPath(b,p);
    // 2. corners back to what the control sits on
    using(GraphicsPath p = VuiDraw.Round(0,0,w,h,Radius))
    using(GraphicsPath ring = VuiDraw.Ring(w,h,p))
    using(SolidBrush sb = new SolidBrush(Surface)) g.FillPath(sb,ring);
    // 3. the label
    string txt = SelectedIndex >= 0 ? GetItemText(SelectedItem) : Text;
    if(!string.IsNullOrEmpty(txt)){
      TextRenderer.DrawText(g,txt,Font,new Rectangle(8,0,w-ArrowW-10,h),
        Enabled ? ForeColor : DisCol,
        TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
    }
    // 4. the chevron, sage only while you are on it
    Color arrow = !Enabled ? DisCol : ((_hot || DroppedDown) ? HotCol : MutedCol);
    VuiDraw.Chevron(g,w-ArrowW/2f-3f,h/2f-1f,4.5f,arrow);
    // 5. the edge (stroked on half-pixel geometry so the flats stay crisp)
    Color edge = !Enabled ? EdgeCol : (DroppedDown ? HotCol : ((_hot || Focused) ? MutedCol : EdgeCol));
    using(GraphicsPath q = VuiDraw.Round(0.5f,0.5f,w-1,h-1,Radius))
    using(Pen pn = new Pen(edge,1f)) g.DrawPath(pn,q);
  }
}
'@ -ReferencedAssemblies System.Windows.Forms,System.Drawing
}
# the palette is still the one place a colour is decided
[VuiSlider]::TrackCol = $Pal.Sink;   [VuiSlider]::FillCol  = $Pal.Muted
[VuiSlider]::ThumbCol = $Pal.Text;   [VuiSlider]::HotCol   = $Pal.Sage
[VuiSlider]::EdgeCol  = $Pal.Line;   [VuiSlider]::DisCol   = $Pal.Faint
[VuiSlider]::FocusCol = $Pal.Muted
[VuiCombo]::BackCol   = $Pal.Panel2; [VuiCombo]::HoverCol  = $Pal.PanelHi
[VuiCombo]::TextCol   = $Pal.Text;   [VuiCombo]::MutedCol  = $Pal.Muted
[VuiCombo]::EdgeCol   = $Pal.Line;   [VuiCombo]::HotCol    = $Pal.Sage
[VuiCombo]::DisCol    = $Pal.Faint

# vvv lifted from ThemeStudio.ps1 lines 976-1056: control factories: AddLabel / AddButton / MakePrimary / ...
function AddLabel($parent,$text,$x,$y,$w,$bold){
  $l = New-Object System.Windows.Forms.Label
  $l.Text=$text; $l.Location=New-Object System.Drawing.Point($x,$y); $l.Size=New-Object System.Drawing.Size($w,20)
  if($bold){
    # section headers: the display face carries the hierarchy, not color. 8.25 is
    # not a shrink - Black Ops One sets ~18% wider than Segoe bold, and these
    # Labels are fixed-width and only 20px tall, so at the old 9.75 the longest
    # two ("Divider (optional)", "Edit this texture") wrapped and lost a line.
    $l.Font = FunFont 8.25 9.75
    $l.ForeColor = $Pal.Text
  }
  $parent.Controls.Add($l); return $l
}
function AddColorBtn($parent,$x,$y,[System.Drawing.Color]$init){
  $b = New-Object System.Windows.Forms.Button
  $b.Location=New-Object System.Drawing.Point($x,$y); $b.Size=New-Object System.Drawing.Size(56,26)
  $b.BackColor=$init; $b.FlatStyle='Flat'
  $b.Tag='keep-swatch'                     # StyleTree must never repaint a color swatch
  $b.FlatAppearance.BorderColor=$Pal.Line
  $b.Add_Click({
    # the studio's own picker, not the Windows one - see VuiColorDialog
    $c = VuiColorDialog $this.BackColor
    if($c){ $this.BackColor=$c }
  })
  # right-click = eyedropper (pick the color from anywhere on screen)
  $b.Add_MouseDown({ param($s,$e)
    if($e.Button -eq [System.Windows.Forms.MouseButtons]::Right){ $c=PickScreenColor; if($c){ $this.BackColor=$c } }
  })
  $parent.Controls.Add($b); return $b
}
function AddSlider($parent,$x,$y,$w,$min,$max,$val){
  # VuiSlider, not TrackBar - same Value/Minimum/Maximum/ValueChanged surface,
  # but drawn in the studio's own palette instead of the Windows theme's
  $s = New-Object VuiSlider
  $s.Location=New-Object System.Drawing.Point($x,$y); $s.Size=New-Object System.Drawing.Size($w,30)
  $s.Minimum=$min; $s.Maximum=$max; $s.Value=$val; $s.TickFrequency=[Math]::Max(1,[int](($max-$min)/10))
  $parent.Controls.Add($s); return $s
}
function AddButton($parent,$text,$x,$y,$w,$h){
  $b = New-Object System.Windows.Forms.Button
  $b.Text=$text; $b.Location=New-Object System.Drawing.Point($x,$y); $b.Size=New-Object System.Drawing.Size($w,$h)
  # quiet grey buttons so the sage ones (BUILD MOD, OPEN SKIN) read as the actions
  $b.FlatStyle='Flat'
  $b.BackColor=$Pal.Panel2
  $b.ForeColor=$Pal.Text
  $b.FlatAppearance.BorderColor=$Pal.Line
  $b.FlatAppearance.BorderSize=1
  $b.FlatAppearance.MouseOverBackColor=$Pal.PanelHi
  $b.FlatAppearance.MouseDownBackColor=$Pal.SageWash
  $parent.Controls.Add($b); return $b
}
# the one loud button on a screen: filled logo sage
function MakePrimary($b){
  $b.Tag='keep-primary'
  $b.FlatStyle='Flat'
  $b.BackColor=$Pal.Sage; $b.ForeColor=$Pal.Bg
  $b.FlatAppearance.BorderSize=0
  $b.FlatAppearance.MouseOverBackColor=$Pal.SageHi
  $b.FlatAppearance.MouseDownBackColor=$Pal.SageDk
  return $b
}
# second-tier emphasis: same grey button, just a brighter edge and label
function MakeAccent($b){
  $b.Tag='keep-accent'
  $b.FlatStyle='Flat'
  $b.BackColor=$Pal.Panel2; $b.ForeColor=$Pal.Text
  $b.FlatAppearance.BorderColor=$Pal.Muted
  $b.FlatAppearance.BorderSize=1
  $b.FlatAppearance.MouseOverBackColor=$Pal.PanelHi
  return $b
}
function AddCombo($parent,$x,$y,$w,$items,$sel){
  # VuiCombo is a ComboBox subclass - every member the studio uses is unchanged,
  # it just paints its own frame, arrow and list rows
  $c = New-Object VuiCombo
  $c.Location=New-Object System.Drawing.Point($x,$y); $c.Size=New-Object System.Drawing.Size($w,24)
  foreach($i in $items){ [void]$c.Items.Add($i) }
  if($c.Items.Count -gt 0){ $c.SelectedIndex=[Math]::Min($sel,$c.Items.Count-1) }
  $parent.Controls.Add($c); return $c
}


# vvv lifted from ThemeStudio.ps1 lines 1057-1157: StyleTree - one pass that dresses every control
# ---- StyleTree: one pass that dresses every control in the palette ----------
# The studio is thousands of lines of hand-placed controls, most of which never
# named a color (they inherited the old light look). Rather than touch every one,
# this walks the tree once at the end of construction and applies the grey/sage
# scheme by control type. It also runs on the dialogs and on anything built at
# runtime (the layer stack, the dialogs), so nothing is left looking light.
#
# Opt out by setting .Tag to 'keep-...' - color swatches, the sage BUILD MOD
# button does that, since their color IS the meaning.
# the flat color a control should use to sit invisibly on whatever is behind it.
# Anything that fills a whole rectangle before drawing (the Flat check box glyph,
# VuiSlider's own erase) gets the card gradient sampled at its own height, so the
# fill disappears into the card instead of leaving a pale block.
function SurfaceOf($ctl){
  $parent = $ctl.Parent
  if(-not $parent){ return $Pal.Panel }
  if(-not (($parent -is [System.Windows.Forms.TabPage]) -or (([string]$parent.Tag) -like 'keep-card*'))){
    return $parent.BackColor
  }
  # sample the card gradient at this control's own height so its flat fill
  # disappears into the background instead of leaving a pale rectangle
  $h=[Math]::Max(1,$parent.Height)
  $t=[Math]::Min(1.0,[Math]::Max(0.0,($ctl.Top + $ctl.Height/2.0)/$h))
  [System.Drawing.Color]::FromArgb(255,
    [int][Math]::Round($Pal.CardTop.R + ($Pal.CardBot.R-$Pal.CardTop.R)*$t),
    [int][Math]::Round($Pal.CardTop.G + ($Pal.CardBot.G-$Pal.CardTop.G)*$t),
    [int][Math]::Round($Pal.CardTop.B + ($Pal.CardBot.B-$Pal.CardTop.B)*$t))
}
function StyleFore($c){
  # a foreground darker than the panel came from the old light theme - relight it,
  # keeping whatever meaning its hue carried (gray = quiet, amber = careful)
  $fc = $c.ForeColor
  if($fc.GetBrightness() -ge 0.55){ return }
  if($fc.GetSaturation() -lt 0.18){ $c.ForeColor = $Pal.Muted }
  elseif($fc.GetHue() -ge 20 -and $fc.GetHue() -le 55){ $c.ForeColor = $Pal.Amber }
  else { $c.ForeColor = $Pal.Text }
}
# pop-up dialogs get the same treatment - call right before ShowDialog
function DressDialog($f){
  $f.BackColor=$Pal.Bg; $f.ForeColor=$Pal.Text
  try { $f.Font=$script:VuiBaseFont } catch {}
  StyleTree $f
  DarkCaption $f
  return $f
}
function StyleTree($ctl){
  foreach($c in $ctl.Controls){
    $keep = ([string]$c.Tag) -like 'keep-*'
    if(-not $keep){
      switch($c.GetType().Name){
        # transparent so the card gradient shows through instead of a flat block
        'Label'          { $c.BackColor=[System.Drawing.Color]::Transparent; StyleFore $c }
        'LinkLabel'      { $c.BackColor=[System.Drawing.Color]::Transparent; $c.LinkColor=$Pal.SageLt; $c.ActiveLinkColor=$Pal.Sage; StyleFore $c }
        # tick boxes fill with their BackColor in Flat style - transparent leaves
        # them stark white, so give them the surface they sit on instead
        'CheckBox'       { $c.FlatStyle='Flat'; $c.BackColor=(SurfaceOf $c); $c.FlatAppearance.BorderColor=$Pal.Line; StyleFore $c }
        'RadioButton'    { $c.FlatStyle='Flat'; $c.BackColor=(SurfaceOf $c); $c.FlatAppearance.BorderColor=$Pal.Line; StyleFore $c }
        'Button'         {
          $c.FlatStyle='Flat'
          $c.BackColor=$Pal.Panel2; $c.ForeColor=$Pal.Text
          $c.FlatAppearance.BorderColor=$Pal.Line
          $c.FlatAppearance.BorderSize=1
          $c.FlatAppearance.MouseOverBackColor=$Pal.PanelHi
        }
        'TextBox'        { $c.BackColor=$Pal.Panel2; $c.ForeColor=$Pal.Text; $c.BorderStyle='FixedSingle' }
        'RichTextBox'    { $c.BackColor=$Pal.Panel;  $c.ForeColor=$Pal.Text }
        'ComboBox'       { $c.FlatStyle='Flat'; $c.BackColor=$Pal.Panel2; $c.ForeColor=$Pal.Text }
        # our own drop-down: it paints its own frame/arrow/list, and needs to be
        # told what it is sitting ON so it can knock its rounded corners back
        'VuiCombo'       { $c.BackColor=$Pal.Panel2; $c.ForeColor=$Pal.Text; $c.SurfaceColor=(SurfaceOf $c) }
        'ListBox'        { $c.BackColor=$Pal.Panel2; $c.ForeColor=$Pal.Text; $c.BorderStyle='FixedSingle' }
        'CheckedListBox' { $c.BackColor=$Pal.Panel2; $c.ForeColor=$Pal.Text; $c.BorderStyle='FixedSingle' }
        'ListView'       { $c.BackColor=$Pal.Panel2; $c.ForeColor=$Pal.Text; $c.BorderStyle='FixedSingle' }
        'NumericUpDown'  { $c.BackColor=$Pal.Panel2; $c.ForeColor=$Pal.Text; $c.BorderStyle='FixedSingle' }
        'TrackBar'       { $c.BackColor=(SurfaceOf $c) }
        # VuiSlider erases to its own BackColor before drawing, so hand it the
        # card gradient sampled at its height and its rectangle disappears
        'VuiSlider'      { $c.BackColor=(SurfaceOf $c) }
        'GroupBox'       { $c.FlatStyle='Flat'; $c.ForeColor=$Pal.Text; $c.BackColor=$c.Parent.BackColor }
        'TabPage'        { $c.BackColor=$Pal.Panel }
        'PictureBox'     { if($c.BackColor.GetBrightness() -gt 0.6){ $c.BackColor=$Pal.Sink } }
        'Panel'          { if($c.BackColor.GetBrightness() -gt 0.6){ $c.BackColor=$Pal.Panel } }
        'FlowLayoutPanel'{ if($c.BackColor.GetBrightness() -gt 0.6){ $c.BackColor=$Pal.Sink } }
        'TableLayoutPanel'{ if($c.BackColor.GetBrightness() -gt 0.6){ $c.BackColor=$Pal.Panel } }
      }
    }
    # rounding is shape, not color - even the "keep" controls get it. It runs
    # AFTER the switch above, which is the pass that sets a button's final
    # BackColor and FlatAppearance: RoundControl hands those to the owner-draw
    # painter, so it has to see the finished values.
    if($c -is [System.Windows.Forms.Button]){
      if(([string]$c.Tag) -eq 'keep-swatch'){
        # colour chips: circular when square, softly rounded when they are wells
        RoundControl $c 8 ($c.Width -eq $c.Height)
      } elseif(-not ($keep -and ([string]$c.Tag) -like 'keep-card*')){
        RoundControl $c 6
      }
    }
    StyleTree $c
  }
}

# vvv lifted from ThemeStudio.ps1 lines 1159-1455: VuiColorDialog - the studio colour picker
# ---- the colour picker ------------------------------------------------------
# The last piece of Windows chrome left in the studio was the stock ColorDialog:
# a 1995 grey box of 48 "basic colours" and 16 empty custom slots, opening out
# of an app that draws every other pixel itself. This replaces it, and every
# swatch in the studio goes through AddColorBtn, so themeing it once themes all
# thirty of them.
#
# The two swatch grids are gone on purpose - they were somebody else's palette,
# and you are here to mix your own - so the space went to R/G/B sliders. Each
# groove is painted as the ramp that channel actually takes, from 0 to 255, with
# the other two held where they are, so you drag toward a colour you can see
# rather than a number you have to imagine.
#
# RGB is the model the whole dialog agrees on, which keeps this honest: the
# sliders ARE the stored value, so nothing is ever converted and converted back.
# The square and the hue strip work in HSV and hand RGB out; hex parses to RGB.
# The only state that has to be remembered separately is H and S (see AdoptRgb).
#
# Returns the chosen Color, or $null if cancelled.
function VuiColorDialog([System.Drawing.Color]$init){
  $st = @{
    R=[int]$init.R; G=[int]$init.G; B=[int]$init.B
    H=0.0; S=0.0; V=0.0
    Orig=[System.Drawing.Color]::FromArgb(255,$init.R,$init.G,$init.B)
    Lock=$false; DragSV=$false; DragHue=$false
  }
  # text that stays readable on the swatch half it is drawn over
  $TxtOn={ param([System.Drawing.Color]$c) if($c.GetBrightness() -gt 0.58){ $Pal.Bg } else { $Pal.Text } }

  $f=New-Object System.Windows.Forms.Form
  $f.Text='Choose a color'
  $f.FormBorderStyle='FixedDialog'; $f.StartPosition='CenterParent'
  $f.ClientSize=New-Object System.Drawing.Size(596,390)
  $f.MaximizeBox=$false; $f.MinimizeBox=$false; $f.ShowInTaskbar=$false
  $f.KeyPreview=$true

  AddLabel $f "Pick" 18 10 120 $true | Out-Null
  AddLabel $f "RGB" 316 10 120 $true | Out-Null

  # the saturation/value square, and the hue strip that feeds it
  $svField=New-Object System.Windows.Forms.Panel
  $svField.Location=New-Object System.Drawing.Point(18,34)
  $svField.Size=New-Object System.Drawing.Size(244,200)
  $svField.Tag='keep-field'; $svField.Cursor=[System.Windows.Forms.Cursors]::Cross
  DoubleBuffer $svField; $f.Controls.Add($svField)

  $hueStrip=New-Object System.Windows.Forms.Panel
  $hueStrip.Location=New-Object System.Drawing.Point(272,34)
  $hueStrip.Size=New-Object System.Drawing.Size(22,200)
  $hueStrip.Tag='keep-field'; $hueStrip.Cursor=[System.Windows.Forms.Cursors]::Hand
  DoubleBuffer $hueStrip; $f.Controls.Add($hueStrip)

  # was / now, so you can see what you are about to change - and click back
  $swatch=New-Object System.Windows.Forms.Panel
  $swatch.Location=New-Object System.Drawing.Point(18,246)
  $swatch.Size=New-Object System.Drawing.Size(276,40)
  $swatch.Tag='keep-field'
  DoubleBuffer $swatch; $f.Controls.Add($swatch)

  $eye=AddButton $f "Eyedropper" 18 298 132 28
  $tt.SetToolTip($eye,"Pick a colour from anywhere on screen - a game shot, reference art, another window. Esc cancels.")

  # ---- R / G / B rows ------------------------------------------------------
  $sliders=New-Object 'object[]' 3
  $lblNum =New-Object 'object[]' 3
  $chan=@('R','G','B')
  $chanName=@('Red, 0-255','Green, 0-255','Blue, 0-255')
  for($i=0;$i -lt 3;$i++){
    [int]$ry=38+$i*46
    $lc=AddLabel $f $chan[$i] 316 ($ry+5) 16 $false
    $lc.ForeColor=$Pal.Muted
    $sl=New-Object VuiSlider
    $sl.Location=New-Object System.Drawing.Point(336,$ry)
    $sl.Size=New-Object System.Drawing.Size(186,30)
    $sl.Minimum=0; $sl.Maximum=255
    $sl.TrackThickness=10; $sl.ThumbSize=18
    $f.Controls.Add($sl)
    $tt.SetToolTip($sl,$chanName[$i])
    $ln=AddLabel $f "0" 526 ($ry+5) 52 $false
    $ln.TextAlign='MiddleRight'
    $sliders[$i]=$sl; $lblNum[$i]=$ln
  }

  $rule=New-Object System.Windows.Forms.Panel
  $rule.Location=New-Object System.Drawing.Point(316,186)
  $rule.Size=New-Object System.Drawing.Size(262,1)
  $rule.BackColor=$Pal.Line
  $f.Controls.Add($rule)

  AddLabel $f "Hex" 316 203 32 $false | Out-Null
  $hex=New-Object System.Windows.Forms.TextBox
  $hex.Location=New-Object System.Drawing.Point(352,200)
  $hex.Size=New-Object System.Drawing.Size(100,22)
  $hex.MaxLength=9
  $f.Controls.Add($hex)

  $hint=AddLabel $f "Tip: you don't have to open this at all - right-click any colour swatch in the studio to eyedrop straight into it." 316 240 262 $false
  $hint.Size=New-Object System.Drawing.Size(262,52)
  $hint.ForeColor=$Pal.Muted
  $hint.Font=UIFont 7.5

  $ok=MakePrimary (AddButton $f "OK" 366 340 100 30); $ok.DialogResult='OK'
  $cancel=AddButton $f "Cancel" 478 340 100 30; $cancel.DialogResult='Cancel'
  $f.AcceptButton=$ok; $f.CancelButton=$cancel

  # ---- the wiring ----------------------------------------------------------
  # Every mutable thing lives in $st: a plain script block runs in a CHILD scope
  # of the one it was written in, so assigning to a local here would quietly
  # make a copy and throw it away. Hash-table members are the same object either
  # way. (These are deliberately NOT .GetNewClosure() - see the closure note on
  # PanelCornerDialog: a closure cannot call the script's own functions.)

  # HSV follows RGB. A grey has no hue and black has no saturation, so keep the
  # ones we had - otherwise the crosshair snaps to red the moment you drag the
  # sliders to black, and coming back up hands you red instead of your colour.
  $AdoptRgb={
    $hsv=ColorToHsv ([System.Drawing.Color]::FromArgb(255,$st.R,$st.G,$st.B))
    if($hsv.s -gt 0.0001){ $st.H=$hsv.h }
    if($hsv.v -gt 0.0001){ $st.S=$hsv.s }
    $st.V=$hsv.v
  }
  # each slider's groove IS its own ramp: what this channel would do to the
  # colour you have, from 0 to 255, with the other two held where they are.
  # That is a straight line in RGB, so two stops is exact - no mid points.
  $SetStops={ param($sl,$i)
    $lo=@([int]$st.R,[int]$st.G,[int]$st.B); $lo[$i]=0
    $hi=@([int]$st.R,[int]$st.G,[int]$st.B); $hi[$i]=255
    $arr=New-Object 'System.Drawing.Color[]' 2
    $arr[0]=[System.Drawing.Color]::FromArgb(255,$lo[0],$lo[1],$lo[2])
    $arr[1]=[System.Drawing.Color]::FromArgb(255,$hi[0],$hi[1],$hi[2])
    $sl.TrackStops=$arr
  }
  # push $st out to every control. Lock stops the write-back below from hearing
  # our own ValueChanged and mistaking it for a drag.
  $Sync={
    $st.Lock=$true
    $cur=[System.Drawing.Color]::FromArgb(255,$st.R,$st.G,$st.B)
    $vals=@($st.R,$st.G,$st.B)
    for($i=0;$i -lt 3;$i++){
      $sliders[$i].Value=[int]$vals[$i]
      $sliders[$i].ThumbFill=$cur
      & $SetStops $sliders[$i] $i
      $lblNum[$i].Text=[string][int]$vals[$i]
    }
    $hex.Text=('#{0:X2}{1:X2}{2:X2}' -f $st.R,$st.G,$st.B)
    $svField.Invalidate(); $hueStrip.Invalidate(); $swatch.Invalidate()
    $st.Lock=$false
  }
  $SvSet={ param($p,$x,$y)
    $w=[Math]::Max(1,$p.Width-1); $h=[Math]::Max(1,$p.Height-1)
    $st.S=[Math]::Min(1.0,[Math]::Max(0.0,$x/[double]$w))
    $st.V=[Math]::Min(1.0,[Math]::Max(0.0,1.0-($y/[double]$h)))
    $c=HsvToColor $st.H $st.S $st.V
    $st.R=[int]$c.R; $st.G=[int]$c.G; $st.B=[int]$c.B
    & $Sync
  }
  $HueSet={ param($p,$y)
    $h=[Math]::Max(1,$p.Height-1)
    $st.H=[Math]::Min(359.999,[Math]::Max(0.0,($y/[double]$h)*360.0))
    $c=HsvToColor $st.H $st.S $st.V
    $st.R=[int]$c.R; $st.G=[int]$c.G; $st.B=[int]$c.B
    & $Sync
  }
  $ApplyHex={
    $t=($hex.Text -replace '[^0-9A-Fa-f]','')
    if($t.Length -eq 3){ $t="$($t[0])$($t[0])$($t[1])$($t[1])$($t[2])$($t[2])" }
    if($t.Length -eq 6){
      $st.R=[Convert]::ToInt32($t.Substring(0,2),16)
      $st.G=[Convert]::ToInt32($t.Substring(2,2),16)
      $st.B=[Convert]::ToInt32($t.Substring(4,2),16)
      & $AdoptRgb
    }
    & $Sync      # anything unparseable snaps back to the colour we still have
  }

  # ---- painting ------------------------------------------------------------
  $svField.Add_Paint({ param($s,$e)
    $g=$e.Graphics; $g.PixelOffsetMode='Half'; $g.SmoothingMode='AntiAlias'
    [int]$w=$s.Width; [int]$h=$s.Height
    $rc=New-Object System.Drawing.Rectangle(0,0,$w,$h)
    # pure hue, washed to white across, faded to black down - three GDI+ calls
    # instead of 48,800 SetPixels, which is the difference between instant and
    # a visible hitch on every drag
    $sb=New-Object System.Drawing.SolidBrush((HsvToColor $st.H 1.0 1.0))
    $g.FillRectangle($sb,$rc); $sb.Dispose()
    $wb=New-Object System.Drawing.Drawing2D.LinearGradientBrush($rc,[System.Drawing.Color]::White,([System.Drawing.Color]::FromArgb(0,255,255,255)),0.0)
    $wb.WrapMode='TileFlipX'; $g.FillRectangle($wb,$rc); $wb.Dispose()
    $bb=New-Object System.Drawing.Drawing2D.LinearGradientBrush($rc,([System.Drawing.Color]::FromArgb(0,0,0,0)),[System.Drawing.Color]::Black,90.0)
    $bb.WrapMode='TileFlipY'; $g.FillRectangle($bb,$rc); $bb.Dispose()
    $pn=New-Object System.Drawing.Pen($Pal.Line,1); $g.DrawRectangle($pn,0,0,($w-1),($h-1)); $pn.Dispose()
    # crosshair: a dark ring under a white one reads on every corner of the square
    [single]$cx=[single]($st.S*($w-1)); [single]$cy=[single]((1.0-$st.V)*($h-1))
    $p1=New-Object System.Drawing.Pen(([System.Drawing.Color]::FromArgb(200,0,0,0)),3)
    $g.DrawEllipse($p1,[single]($cx-6),[single]($cy-6),[single]12,[single]12); $p1.Dispose()
    $p2=New-Object System.Drawing.Pen([System.Drawing.Color]::White,1.6)
    $g.DrawEllipse($p2,[single]($cx-6),[single]($cy-6),[single]12,[single]12); $p2.Dispose()
  })
  $hueStrip.Add_Paint({ param($s,$e)
    $g=$e.Graphics; $g.PixelOffsetMode='Half'; $g.SmoothingMode='AntiAlias'
    [int]$w=$s.Width; [int]$h=$s.Height
    $rc=New-Object System.Drawing.Rectangle(0,0,$w,$h)
    $lb=New-Object System.Drawing.Drawing2D.LinearGradientBrush($rc,[System.Drawing.Color]::Red,[System.Drawing.Color]::Red,90.0)
    $lb.WrapMode='TileFlipY'
    $cols=New-Object 'System.Drawing.Color[]' 7
    $pos=New-Object 'single[]' 7
    for($i=0;$i -lt 7;$i++){ $cols[$i]=HsvToColor ($i*60.0) 1.0 1.0; $pos[$i]=[single]($i/6.0) }
    $cb=New-Object System.Drawing.Drawing2D.ColorBlend(7)
    $cb.Colors=$cols; $cb.Positions=$pos; $lb.InterpolationColors=$cb
    $g.FillRectangle($lb,$rc); $lb.Dispose()
    $pn=New-Object System.Drawing.Pen($Pal.Line,1); $g.DrawRectangle($pn,0,0,($w-1),($h-1)); $pn.Dispose()
    [single]$my=[single](($st.H/360.0)*($h-1))
    $p1=New-Object System.Drawing.Pen(([System.Drawing.Color]::FromArgb(200,0,0,0)),3)
    $g.DrawLine($p1,[single]1,$my,[single]($w-2),$my); $p1.Dispose()
    $p2=New-Object System.Drawing.Pen([System.Drawing.Color]::White,1.6)
    $g.DrawLine($p2,[single]1,$my,[single]($w-2),$my); $p2.Dispose()
  })
  $swatch.Add_Paint({ param($s,$e)
    $g=$e.Graphics; $g.SmoothingMode='AntiAlias'; $g.PixelOffsetMode='Half'
    [single]$w=$s.Width; [single]$h=$s.Height
    $bg=New-Object System.Drawing.SolidBrush($s.Parent.BackColor)
    $g.FillRectangle($bg,0,0,$s.Width,$s.Height); $bg.Dispose()
    $cur=[System.Drawing.Color]::FromArgb(255,$st.R,$st.G,$st.B)
    $p=RoundedPath 0 0 $w $h 6
    $old=$g.Clip
    $g.SetClip($p)
    $b1=New-Object System.Drawing.SolidBrush($st.Orig)
    $g.FillRectangle($b1,[single]0,[single]0,[single]($w/2),$h); $b1.Dispose()
    $b2=New-Object System.Drawing.SolidBrush($cur)
    $g.FillRectangle($b2,[single]($w/2),[single]0,[single]($w/2),$h); $b2.Dispose()
    $g.Clip=$old
    $fnt=UIFont 7.5
    $sf=New-Object System.Drawing.StringFormat
    $sf.Alignment='Near'; $sf.LineAlignment='Center'
    $t1=New-Object System.Drawing.SolidBrush((& $TxtOn $st.Orig))
    $r1=New-Object System.Drawing.RectangleF([single]10,[single]0,[single]($w/2-14),$h)
    $g.DrawString("was",$fnt,$t1,$r1,$sf); $t1.Dispose()
    $t2=New-Object System.Drawing.SolidBrush((& $TxtOn $cur))
    $r2=New-Object System.Drawing.RectangleF([single]($w/2+10),[single]0,[single]($w/2-14),$h)
    $g.DrawString("now",$fnt,$t2,$r2,$sf); $t2.Dispose()
    $sf.Dispose(); $fnt.Dispose()
    $q=RoundedPath 0.5 0.5 ($w-1) ($h-1) 6
    $pn=New-Object System.Drawing.Pen($Pal.Line,1)
    $g.DrawPath($pn,$q)
    $g.DrawLine($pn,[single]($w/2),[single]1,[single]($w/2),[single]($h-1))
    $pn.Dispose(); $p.Dispose(); $q.Dispose()
  })

  # ---- input ---------------------------------------------------------------
  $svField.Add_MouseDown({ param($s,$e)
    if($e.Button -ne [System.Windows.Forms.MouseButtons]::Left){ return }
    $st.DragSV=$true; $s.Capture=$true; & $SvSet $s $e.X $e.Y
  })
  $svField.Add_MouseMove({ param($s,$e) if($st.DragSV){ & $SvSet $s $e.X $e.Y } })
  $svField.Add_MouseUp({ param($s,$e) $st.DragSV=$false; $s.Capture=$false })
  $hueStrip.Add_MouseDown({ param($s,$e)
    if($e.Button -ne [System.Windows.Forms.MouseButtons]::Left){ return }
    $st.DragHue=$true; $s.Capture=$true; & $HueSet $s $e.Y
  })
  $hueStrip.Add_MouseMove({ param($s,$e) if($st.DragHue){ & $HueSet $s $e.Y } })
  $hueStrip.Add_MouseUp({ param($s,$e) $st.DragHue=$false; $s.Capture=$false })
  # click the "was" half to put it back
  $swatch.Add_MouseDown({ param($s,$e)
    if($e.X -ge ($s.Width/2)){ return }
    $st.R=[int]$st.Orig.R; $st.G=[int]$st.Orig.G; $st.B=[int]$st.Orig.B
    & $AdoptRgb; & $Sync
  })
  $tt.SetToolTip($swatch,"Left half is the colour you started with - click it to go back.")

  foreach($sl in $sliders){
    $sl.Add_ValueChanged({
      if($st.Lock){ return }
      $st.R=[int]$sliders[0].Value; $st.G=[int]$sliders[1].Value; $st.B=[int]$sliders[2].Value
      & $AdoptRgb; & $Sync
    })
  }
  $hex.Add_Leave({ & $ApplyHex })
  $hex.Add_KeyDown({ param($s,$e)
    if($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter){
      & $ApplyHex; $e.Handled=$true; $e.SuppressKeyPress=$true   # not the OK button
    }
  })
  $eye.Add_Click({
    $c=PickScreenColor
    if($c){
      $st.R=[int]$c.R; $st.G=[int]$c.G; $st.B=[int]$c.B
      & $AdoptRgb; & $Sync
    }
  })

  DressDialog $f | Out-Null
  & $AdoptRgb; & $Sync
  $res=$f.ShowDialog($script:VuiOwnerForm)
  $out=$null
  if($res -eq 'OK'){ $out=[System.Drawing.Color]::FromArgb(255,$st.R,$st.G,$st.B) }
  $f.Dispose()
  return $out
}

# vvv lifted from ThemeStudio.ps1 lines 1854-1909: dark title bar + dark scrollbars
# ---- window chrome: match the title bar to the app ---------------------------
Add-Type -Namespace VUIDwm -Name Api -MemberDefinition @'
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
'@
# COLORREF = 0x00bbggrr. NB the [int] casts: PowerShell's -shl keeps a [byte]
# operand a byte, so Color.G -shl 8 silently becomes 0 (that shipped a red title bar).
function ColorRef([System.Drawing.Color]$c){
  [int]([int]$c.R -bor ([int]$c.G -shl 8) -bor ([int]$c.B -shl 16))
}
function DarkCaption($f){
  try {
    $h=$f.Handle
    $on=1
    [void][VUIDwm.Api]::DwmSetWindowAttribute($h,20,[ref]$on,4)            # immersive dark mode
    $cap=ColorRef $Pal.Bg
    [void][VUIDwm.Api]::DwmSetWindowAttribute($h,35,[ref]$cap,4)           # caption fill
    $txt=ColorRef $Pal.Text
    [void][VUIDwm.Api]::DwmSetWindowAttribute($h,36,[ref]$txt,4)           # caption text
    $bor=ColorRef $Pal.Line
    [void][VUIDwm.Api]::DwmSetWindowAttribute($h,34,[ref]$bor,4)           # window border
  } catch {}
}

# ---- dark scrollbars --------------------------------------------------------
# AutoScroll / list scrollbars are non-client, drawn by the OS, so nothing in
# StyleTree can touch them - on a narrow window the section hosts sprouted stark
# WHITE bars down the side of a black app. uxtheme has no public API for this;
# the ordinals below are the same ones Explorer and WinUI use (1809+): put the
# process in dark mode, then hand each scrolling control the DarkMode_Explorer
# theme class. Undocumented, so every call is wrapped - on a build where it does
# not exist we simply get the old light bars back, nothing breaks.
Add-Type -Namespace VUIDarkUx -Name Api -MemberDefinition @'
[DllImport("uxtheme.dll", EntryPoint="#135", CharSet=CharSet.Unicode)] public static extern int SetPreferredAppMode(int mode);
[DllImport("uxtheme.dll", EntryPoint="#136")] public static extern void FlushMenuThemes();
[DllImport("uxtheme.dll", CharSet=CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr hWnd, string sub, string idList);
'@
# 2 = ForceDark: the studio is dark whatever the user's system setting is
try { [void][VUIDarkUx.Api]::SetPreferredAppMode(2); [VUIDarkUx.Api]::FlushMenuThemes() } catch {}
# only controls that can actually show a scrollbar - handing the theme class to
# every button would fight the flat styling StyleTree just applied
function DarkScrollbars($ctl){
  foreach($c in $ctl.Controls){
    $scrolls = ($c -is [System.Windows.Forms.ListBox]) -or ($c -is [System.Windows.Forms.CheckedListBox]) -or
               ($c -is [System.Windows.Forms.ListView]) -or ($c -is [System.Windows.Forms.TreeView]) -or
               ($c -is [System.Windows.Forms.RichTextBox]) -or ($c -is [System.Windows.Forms.ComboBox]) -or
               (($c -is [System.Windows.Forms.TextBox]) -and $c.Multiline) -or
               ((($c -is [System.Windows.Forms.Panel]) -or ($c -is [System.Windows.Forms.TabPage])) -and $c.AutoScroll)
    if($scrolls){
      try {
        [void][VUIDarkUx.Api]::SetWindowTheme($c.Handle,'DarkMode_Explorer',$null)
        $c.Invalidate()
      } catch {}
    }
    DarkScrollbars $c
  }
}

# ---- retitling a card -------------------------------------------------------
# PaintCard takes the caption OFF a GroupBox (WinForms draws its own before our
# Paint handler runs, so it would show twice, slightly offset) and paints it
# from $script:cardTitle instead. Anything that used to assign .Text at runtime
# has to come through here, or the native caption comes back AND the painted one
# never changes.
function Set-CardTitle($ctl,[string]$title){
  $script:cardTitle[$ctl] = $title
  if($ctl -is [System.Windows.Forms.GroupBox]){ $ctl.Text='' }
  $ctl.Invalidate()
}

# ---- the brand band ---------------------------------------------------------
# Variant UI wears its lockup down the side of the always-on guide column. Skin
# Studio has no guide column - every pixel of width is spoken for by the four
# working columns - so the same brand block lies on its side as a strip across
# the top: lockup, sage rule, the app's name in the display face, and a muted
# note on the right the app keeps up to date (which skin is open).
#
# It is a card like any other, so it picks up the same gradient, hairline and
# rounded corners as the panels below it.
#
# The strings live in script scope, not on the control: the Paint handler is a
# plain script block on purpose (a .GetNewClosure() one could not reach FunFont
# or $Pal at all), and Tag is already spoken for by the card radius.
$script:brandNote    = ''
$script:brandTitle   = ''
$script:brandSub     = ''
$script:brandNoteCtl = $null
function AddBrandHeader($parent,[int]$x,[int]$y,[int]$w,[int]$h,[string]$title,[string]$sub){
  $p = New-Object System.Windows.Forms.Panel
  $p.Location = New-Object System.Drawing.Point($x,$y)
  $p.Size = New-Object System.Drawing.Size($w,$h)
  $p.BackColor = $Pal.Panel
  $parent.Controls.Add($p)
  $script:brandTitle = $title
  $script:brandSub   = $sub
  $script:brandNoteCtl = $p
  DoubleBuffer $p
  SetGradientBg $p
  $p.Tag = 'keep-card r12'
  $p.Add_Paint({
    param($s,$e)
    $gfx=$e.Graphics; $gfx.SmoothingMode='AntiAlias'; $gfx.TextRenderingHint='ClearTypeGridFit'
    $path=RoundedPath 0.5 0.5 ($s.Width-1.5) ($s.Height-1.5) 12
    # knock the corners back to the app background, then edge the card
    $ring=RingPath $s.Width $s.Height $path
    $sb=New-Object System.Drawing.SolidBrush($Pal.Bg); $gfx.FillPath($sb,$ring); $sb.Dispose(); $ring.Dispose()
    $pn=New-Object System.Drawing.Pen($Pal.Line,1); $gfx.DrawPath($pn,$path); $pn.Dispose(); $path.Dispose()
    $gfx.InterpolationMode='HighQualityBicubic'
    $lx = 18.0
    if($script:wordImg){
      # the real lockup - badge and wordmark are one drawing, so nothing here
      # has to fake the spacing between them. Height drives the size; the width
      # comes off the artwork's own aspect so a re-export can change shape safely.
      $wh = 26.0
      $ww = [single]($wh * ($script:wordImg.Width / [double]$script:wordImg.Height))
      $gfx.DrawImage($script:wordImg,[single]$lx,8.0,$ww,[single]$wh)
      $rule=RoundedPath ([single]($lx+1)) 38 44 3 1.5
      $br=New-Object System.Drawing.SolidBrush($Pal.Sage); $gfx.FillPath($br,$rule); $br.Dispose(); $rule.Dispose()
      $lx = $lx + $ww + 20
    } elseif($script:markImg){
      $gfx.DrawImage($script:markImg,[int]$lx,10,28,28)
      $lx = $lx + 44
    }
    # the hairline that separates the product from this app's own name
    $ln=New-Object System.Drawing.SolidBrush($Pal.Line)
    $gfx.FillRectangle($ln,[single]$lx,12,1,($s.Height-24)); $ln.Dispose()
    $lx = $lx + 17
    $ttl=[string]$script:brandTitle; if(-not $ttl){ $ttl='Skin Studio' }
    $f=FunFont 12 13
    $tb=New-Object System.Drawing.SolidBrush($Pal.Text)
    $gfx.DrawString($ttl,$f,$tb,[single]$lx,6.0)
    $f.Dispose(); $tb.Dispose()
    $sb2=[string]$script:brandSub
    if($sb2){
      $f2=UIFont 8.25
      $mb=New-Object System.Drawing.SolidBrush($Pal.Muted)
      $gfx.DrawString($sb2,$f2,$mb,[single]($lx+2),27.0)
      $f2.Dispose(); $mb.Dispose()
    }
    # right-hand note: whatever the app last put there (the open skin)
    if($script:brandNote){
      $f3=UIFont 8.25
      $mb=New-Object System.Drawing.SolidBrush($Pal.Muted)
      $nw=$gfx.MeasureString($script:brandNote,$f3).Width
      $gfx.DrawString($script:brandNote,$f3,$mb,[single]($s.Width-20-$nw),[single](($s.Height-15)/2))
      $f3.Dispose(); $mb.Dispose()
    }
  })
  return $p
}
function Set-BrandNote([string]$text){
  $script:brandNote = $text
  if($script:brandNoteCtl){ $script:brandNoteCtl.Invalidate() }
}

# ---- a status strip we own --------------------------------------------------
# StatusStrip is a ToolStrip: it renders from the system theme's colour table,
# so a dark BackColor still leaves a light 1px top border and a light grip. A
# docked Panel with a Label in it is the whole feature, and it takes the
# palette without argument.
function AddStatusBar($form,[string]$initial){
  $bar = New-Object System.Windows.Forms.Panel
  $bar.Height = 26; $bar.Dock = 'Bottom'; $bar.BackColor = $Pal.Panel
  DoubleBuffer $bar
  $bar.Add_Paint({
    param($s,$e)
    $pn=New-Object System.Drawing.Pen($Pal.Line,1)
    $e.Graphics.DrawLine($pn,0,0,$s.Width,0); $pn.Dispose()
  })
  $lbl = New-Object System.Windows.Forms.Label
  $lbl.Location = New-Object System.Drawing.Point(16,5)
  $lbl.Size = New-Object System.Drawing.Size(($form.ClientSize.Width-32),18)
  $lbl.ForeColor = $Pal.SageLt
  $lbl.BackColor = [System.Drawing.Color]::Transparent
  $lbl.Text = $initial
  $lbl.Tag = 'keep-status'          # StyleTree must not relight it to Muted
  $bar.Controls.Add($lbl)
  $form.Controls.Add($bar)
  return $lbl
}

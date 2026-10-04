# ============================================================================
# Skin Studio branding: the Variant lockup and V badge, walked from the logo
# pink to the studio's sage.
#
# The logo art is flat ink on transparency - 208,105,169 for 99% of the
# pixels, the rest antialiasing fringe - so the recolour is done in HSL and
# applied per pixel: the hue rotated by the same amount for every pixel, the
# saturation scaled by the same ratio, the lightness offset by the same delta.
# A flat "paint every non-transparent pixel sage" would look identical on this
# art today, but it would flatten any shading a future logo revision had.
#
# Writes, next to this script:
#   variant-sage-mark.png      512x512 badge
#   variant-sage-wordmark.png  the "Variant" lockup, tight-cropped
#   skin-studio.ico            the window / taskbar icon
#
# Bitmaps load through a MemoryStream, never FromFile: GDI+ keeps a lock on the
# backing store of a FromFile bitmap for as long as it lives.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\rs\SkinStudio\branding\build-branding.ps1
# ============================================================================
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$srcDir = 'C:\rs\ThemeStudio\branding'
$outDir = $PSScriptRoot

# the two ends of the walk: Variant UI's logo pink, and Skin Studio's sage
$FromCol = [System.Drawing.Color]::FromArgb(208,105,169)
$ToCol   = [System.Drawing.Color]::FromArgb(158,189,148)

function LoadBmp($path){
  $bytes=[System.IO.File]::ReadAllBytes($path)
  $ms=New-Object System.IO.MemoryStream(,$bytes)
  $src=[System.Drawing.Image]::FromStream($ms)
  $b=New-Object System.Drawing.Bitmap($src.Width,$src.Height,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g=[System.Drawing.Graphics]::FromImage($b); $g.DrawImage($src,0,0,$src.Width,$src.Height)
  $g.Dispose(); $src.Dispose(); $ms.Dispose(); return $b
}
function NewCanvas([int]$w,[int]$h){
  New-Object System.Drawing.Bitmap($w,$h,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
}
function Gfx($bmp){
  $g=[System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode='AntiAlias'; $g.InterpolationMode='HighQualityBicubic'
  $g.PixelOffsetMode='HighQuality'; $g.CompositingQuality='HighQuality'
  return $g
}
function SavePng($bmp,$path){
  $ms=New-Object System.IO.MemoryStream
  $bmp.Save($ms,[System.Drawing.Imaging.ImageFormat]::Png)
  [System.IO.File]::WriteAllBytes($path,$ms.ToArray()); $ms.Dispose()
}
function HslToColor([double]$h,[double]$s,[double]$l){
  $h=(($h % 360.0)+360.0)%360.0
  $s=[Math]::Min(1.0,[Math]::Max(0.0,$s)); $l=[Math]::Min(1.0,[Math]::Max(0.0,$l))
  $c=(1.0-[Math]::Abs(2.0*$l-1.0))*$s
  $x=$c*(1.0-[Math]::Abs((($h/60.0)%2.0)-1.0)); $m=$l-$c/2.0
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
# LockBits, not GetPixel/SetPixel: the wordmark is 452k pixels and the per-call
# marshalling turns a blink into most of a minute.
function Recolor($bmp){
  $dh = $ToCol.GetHue() - $FromCol.GetHue()
  $rs = if($FromCol.GetSaturation() -gt 0){ $ToCol.GetSaturation()/$FromCol.GetSaturation() } else { 1.0 }
  $dl = $ToCol.GetBrightness() - $FromCol.GetBrightness()
  $rect=New-Object System.Drawing.Rectangle(0,0,$bmp.Width,$bmp.Height)
  $bd=$bmp.LockBits($rect,'ReadWrite','Format32bppArgb')
  $len=$bd.Stride*$bmp.Height
  $px=New-Object byte[] $len
  [System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0,$px,0,$len)
  # one HSL round-trip per DISTINCT colour, not per pixel - the art is 99% one
  # ink, so the memo turns 452k conversions into a few hundred
  $memo=@{}
  for($i=0;$i -lt $len;$i+=4){
    if($px[$i+3] -eq 0){ continue }                                  # fully transparent: leave it
    $key=([int]$px[$i+2] -shl 16) -bor ([int]$px[$i+1] -shl 8) -bor [int]$px[$i]
    if(-not $memo.ContainsKey($key)){
      $c=[System.Drawing.Color]::FromArgb(255,$px[$i+2],$px[$i+1],$px[$i])
      $memo[$key]=HslToColor ($c.GetHue()+$dh) ($c.GetSaturation()*$rs) ($c.GetBrightness()+$dl)
    }
    $n=$memo[$key]
    $px[$i]=$n.B; $px[$i+1]=$n.G; $px[$i+2]=$n.R                     # alpha untouched
  }
  [System.Runtime.InteropServices.Marshal]::Copy($px,0,$bd.Scan0,$len)
  $bmp.UnlockBits($bd)
  return $bmp
}

$mark = Recolor (LoadBmp "$srcDir\variant-ui-mark.png")
SavePng $mark "$outDir\variant-sage-mark.png"
"wrote variant-sage-mark.png      $($mark.Width)x$($mark.Height)"
$word = Recolor (LoadBmp "$srcDir\variant-ui-wordmark.png")
SavePng $word "$outDir\variant-sage-wordmark.png"
"wrote variant-sage-wordmark.png  $($word.Width)x$($word.Height)"

# ---- the icon ---------------------------------------------------------------
# Hand-rolled ICO, every entry a classic 32bpp DIB - NOT PNG-compressed.
# System.Drawing cannot decode PNG frames: Icon.ToBitmap() on one throws
# "Requested range extends past the end of the array", and the studio hands the
# .ico straight to System.Drawing.Icon. Every entry is drawn from the 512px
# badge, not from the next size up, so nothing compounds resampling error.
$sizes = @(16,20,24,32,40,48,64,128,256)
$entries = New-Object System.Collections.Generic.List[object]
foreach($s in $sizes){
  $b = NewCanvas $s $s
  $g = Gfx $b
  $g.DrawImage($mark,(New-Object System.Drawing.Rectangle(0,0,$s,$s)),0,0,$mark.Width,$mark.Height,'Pixel')
  $g.Dispose()
  $bd=$b.LockBits((New-Object System.Drawing.Rectangle(0,0,$s,$s)),'ReadOnly','Format32bppArgb')
  $stride=$bd.Stride; $px=New-Object byte[] ($stride*$s)
  [System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0,$px,0,$px.Length)
  $b.UnlockBits($bd); $b.Dispose()
  # NB [Math]::Floor, not [int]: PowerShell's [int] cast ROUNDS, and a rounded
  # mask stride runs the index off the end of the buffer.
  $maskStride = [int]([Math]::Floor(($s+31)/32)*4)
  $ms=New-Object System.IO.MemoryStream
  $bw=New-Object System.IO.BinaryWriter($ms)
  # BITMAPINFOHEADER - height is doubled to cover the (unused) AND mask
  $bw.Write([int]40); $bw.Write([int]$s); $bw.Write([int]($s*2))
  $bw.Write([int16]1); $bw.Write([int16]32); $bw.Write([int]0)
  $bw.Write([int]($s*$s*4 + $maskStride*$s))
  $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0)
  for($y=$s-1;$y -ge 0;$y--){ $bw.Write($px,$y*$stride,$s*4) }   # XOR bitmap, bottom-up BGRA
  $zero=New-Object byte[] ($maskStride*$s)                       # AND mask: alpha already carries it
  $bw.Write($zero,0,$zero.Length)
  $bw.Flush()
  $entries.Add(@{ Size=$s; Data=$ms.ToArray() })
  $bw.Dispose(); $ms.Dispose()
}
$ico=New-Object System.IO.MemoryStream
$bw=New-Object System.IO.BinaryWriter($ico)
$bw.Write([int16]0); $bw.Write([int16]1); $bw.Write([int16]$entries.Count)
$offset = 6 + 16*$entries.Count
foreach($e in $entries){
  $d = if($e.Size -ge 256){ 0 } else { $e.Size }
  $bw.Write([byte]$d); $bw.Write([byte]$d); $bw.Write([byte]0); $bw.Write([byte]0)
  $bw.Write([int16]1); $bw.Write([int16]32)
  $bw.Write([int]$e.Data.Length); $bw.Write([int]$offset)
  $offset += $e.Data.Length
}
foreach($e in $entries){ $bw.Write($e.Data,0,$e.Data.Length) }
$bw.Flush()
[System.IO.File]::WriteAllBytes("$outDir\skin-studio.ico",$ico.ToArray())
$bw.Dispose(); $ico.Dispose()
"wrote skin-studio.ico            $($entries.Count) sizes: $(($entries|ForEach-Object{$_.Size}) -join ', ')"

# every frame must decode through System.Drawing, which is what will read it
$icon=New-Object System.Drawing.Icon("$outDir\skin-studio.ico")
foreach($s in $sizes){
  $i2=New-Object System.Drawing.Icon($icon,(New-Object System.Drawing.Size($s,$s)))
  $bm=$i2.ToBitmap(); $bm.Dispose(); $i2.Dispose()
}
$icon.Dispose()
"icon frames all decode clean."
$mark.Dispose(); $word.Dispose()
"done."

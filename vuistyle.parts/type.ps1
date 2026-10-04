
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

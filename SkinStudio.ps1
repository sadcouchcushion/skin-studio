# Skin Studio - GUI mod generator for Marvel Rivals character models & skins.
# Browse every hero/skin, preview each texture, recolor / replace / hand-edit
# any of them, then build + install the mod (Luna-pipeline: ddstools 5.3 inject
# -> rrcli pack -> loose triplet at ~mods root).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
# Taskbar identity. The Skin Studio shortcuts (Desktop, Start, the taskbar pin)
# carry this same AppUserModelID, so the window groups under the sage pin instead
# of under powershell.exe - where it would join every other PowerShell window,
# Variant UI included. Must run before the first window is created.
Add-Type -Namespace SSTaskbar -Name Api -MemberDefinition '[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);' -ErrorAction SilentlyContinue
try { [void][SSTaskbar.Api]::SetCurrentProcessExplicitAppUserModelID('Chicory.VariantSkinStudio') } catch {}
. "$PSScriptRoot\skinlib.ps1"
. "$PSScriptRoot\meshlib.ps1"
Add-Type -Path "$PSScriptRoot\SkinArt.cs" -ReferencedAssemblies System.Drawing
. "$PSScriptRoot\viewlib.ps1"
. "$PSScriptRoot\atelierlib.ps1"
# Project Galacta detection, for what BUILD MOD tells her (the swap itself runs
# in the build window - build_skin.ps1)
. "$PSScriptRoot\galacta.ps1"
[System.Windows.Forms.Application]::EnableVisualStyles()
# the studio's look: Variant UI's chrome in sage. See vuistyle.ps1 (assembled
# from ThemeStudio.ps1 by build-vuistyle.ps1 - do not hand-edit it).
. "$PSScriptRoot\vuistyle.ps1"

# ---- palette ----------------------------------------------------------------
# The colours themselves live in $Pal, over in vuistyle.ps1. These are the six
# names this file has always used, re-pointed at it, so every one of the ~200
# existing colour references lands on the shared palette untouched.
$colBack   = $Pal.Bg
$colPanel  = $Pal.Panel2      # lists and wells
$colField  = $Pal.Panel2      # inputs
$colFore   = $Pal.Text
$colDim    = $Pal.Muted
$colAccent = $Pal.Sage        # THE accent - the mode you are in, the button that commits
$colPink   = $Pal.SageLt      # the quiet half of it: edited rows, the open texture

function New-Btn([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    # a quiet grey button, so the few sage ones read as the actions. StyleTree
    # rounds it at the end of construction; the hover/press shifts are declared
    # here because that is where the round painter reads them from.
    $b.FlatStyle = 'Flat'; $b.BackColor = $Pal.Panel2; $b.ForeColor = $Pal.Text
    $b.FlatAppearance.BorderColor = $Pal.Line
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.MouseOverBackColor = $Pal.PanelHi
    $b.FlatAppearance.MouseDownBackColor = $Pal.SageWash
    $b
}
function New-Lbl([string]$text, [int]$x, [int]$y, [int]$w) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.AutoSize = $false
    $l.BackColor = [System.Drawing.Color]::Transparent
    # A SHOUTED label is this app's section caption (SEARCH HERO, SKINS,
    # VANILLA, MODIFIED, TEXTURES). Those get the display face and the bright
    # text colour - hierarchy by weight, not by colour, same as Variant UI.
    # Everything else is a quiet hint. 20px, not 18: Black Ops One sets ~18%
    # wider and needs the extra line box or the descenders clip.
    if ($text -cmatch '^[A-Z0-9 ]{2,}$') {
        $l.Size = New-Object System.Drawing.Size($w, 20)
        $l.Font = FunFont 8.25 9.75
        $l.ForeColor = $Pal.Text
    } else {
        $l.Size = New-Object System.Drawing.Size($w, 18)
        $l.ForeColor = $Pal.Muted
    }
    $l
}
# The three browse-mode buttons behave like Variant UI's tab strip: the one you
# are in is filled sage, the others are quiet grey. The hover/press colours have
# to move with the fill or an active button would flash grey under the cursor -
# the round painter reads them straight off FlatAppearance.
function Set-ModeBtn($b, [bool]$on) {
    if ($on) {
        $b.BackColor = $Pal.Sage; $b.ForeColor = $Pal.Bg
        $b.FlatAppearance.BorderColor = $Pal.Sage          # same as the fill = no edge drawn
        $b.FlatAppearance.MouseOverBackColor = $Pal.SageHi
        $b.FlatAppearance.MouseDownBackColor = $Pal.SageDk
    } else {
        $b.BackColor = $Pal.Panel2; $b.ForeColor = $Pal.Text
        $b.FlatAppearance.BorderColor = $Pal.Line
        $b.FlatAppearance.MouseOverBackColor = $Pal.PanelHi
        $b.FlatAppearance.MouseDownBackColor = $Pal.SageWash
    }
    $b.Invalidate()
}
# A colour swatch: a rounded, hairlined chip filled with whatever colour it is
# currently showing, so it matches the round chips in Variant UI instead of
# being a square Panel with a system border. Tagged keep-swatch because the
# colour IS the value - StyleTree must never repaint one. Setting .BackColor at
# runtime repaints it, so every existing assignment keeps working.
function Make-Swatch($p, [int]$radius) {
    $p.BorderStyle = 'None'
    $p.Tag = "keep-swatch r$radius"
    DoubleBuffer $p
    $p.Add_Paint({
        param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'Half'
        $rad = if (([string]$s.Tag) -match 'r(\d+)') { [int]$matches[1] } else { 6 }
        # erase the flat rectangle back to the card gradient underneath, then
        # lay the chip's own shape on top
        $bb = New-Object System.Drawing.SolidBrush((SurfaceOf $s))
        $g.FillRectangle($bb, 0, 0, $s.Width, $s.Height); $bb.Dispose()
        $path = RoundedPath 0 0 $s.Width $s.Height $rad
        $fb = New-Object System.Drawing.SolidBrush($s.BackColor)
        $g.FillPath($fb, $path); $fb.Dispose(); $path.Dispose()
        $q = RoundedPath 0.5 0.5 ($s.Width - 1) ($s.Height - 1) $rad
        $pn = New-Object System.Drawing.Pen($Pal.Line, 1); $g.DrawPath($pn, $q); $pn.Dispose(); $q.Dispose()
    })
}

# ---- persistent naming ------------------------------------------------------
$heroNamesPath = Join-Path $SS_Root 'heroes.json'
$skinNamesPath = Join-Path $SS_Root 'skins.json'
$script:HeroNames = @{}
$script:SkinNames = @{}
if (Test-Path $heroNamesPath) {
    (Get-Content $heroNamesPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $script:HeroNames[$_.Name] = $_.Value }
}
if (Test-Path $skinNamesPath) {
    (Get-Content $skinNamesPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $script:SkinNames[$_.Name] = $_.Value }
}
function Save-Names {
    $ho = [ordered]@{}; foreach ($k in ($script:HeroNames.Keys | Sort-Object)) { $ho[$k] = $script:HeroNames[$k] }
    $so = [ordered]@{}; foreach ($k in ($script:SkinNames.Keys | Sort-Object)) { $so[$k] = $script:SkinNames[$k] }
    $ho | ConvertTo-Json | Set-Content -LiteralPath $heroNamesPath -Encoding utf8
    $so | ConvertTo-Json | Set-Content -LiteralPath $skinNamesPath -Encoding utf8
}
function HeroLabel([string]$hid) {
    $nm = $script:HeroNames[$hid]; if (-not $nm) { $nm = "Hero $hid" }
    '{0}  ·  {1}' -f $nm, $hid
}
function SkinLabel([string]$sid) {
    $nm = $script:SkinNames[$sid]
    if (-not $nm) { if ($sid.EndsWith('001')) { $nm = 'Default' } else { $nm = 'Unnamed skin' } }
    '{0}  ·  {1}' -f $nm, $sid
}
# list rows read 'Name  ·  id' - the id is always the last segment
function LabelId([string]$lab) { $lab.Split('·')[-1].Trim() }

# ---- game data index (fast after first run) ---------------------------------
Write-Host 'Skin Studio: loading character texture index...'
$idxPath = SS-EnsureTexIndex { param($m) Write-Host "  $m" }
$script:Map = SS-LoadSkinMap $idxPath
$script:HeroIds = @($script:Map.heroSkins.Keys | Sort-Object { -not $_.StartsWith('10') }, { $script:HeroNames[$_] }, { $_ })
Write-Host ('  {0} heroes, {1} skins.' -f $script:HeroIds.Count, $script:Map.skinLines.Count)

# ---- session state ----------------------------------------------------------
$script:CurSkin = $null
$script:CurHero = $null
$script:CurCk = $null
$script:TexItems = @()          # objects: Rel, Png, Thumb, Dims, Role, ImgIdx, OrigImgIdx, Item
$script:OpsBySkin = @{}         # skin -> @{ rel -> @(layer hashtables) }
$script:SelTex = $null
$script:Links = @{}             # rel -> @(other rels that are the SAME map, see SS-LinkGroups)
$script:ChromaT = $null         # @{ Sure; Maybe } = recolor skins of the open one (SS-ChromaGroups)
$script:ChromaRels = @{}        # recolor skin -> HashSet of its texture rels (what a mirror may land on)
$script:ChromaMaskRels = @{}    # recolor skin -> @{ '<T_..._ColorID>' = rel } (the dye masks)
# "Recolor color family": which hue band moves. -1 = let the engine detect the
# dominant family; >= 0 = the centre you picked. Width 0 = the 34-degree default.
$script:BandCenter = -1.0
$script:BandWidth = 0.0
$script:PvImgs = @()            # disposables
$script:EditLayerIdx = -1       # -1 = panel is a DRAFT layer; >=0 = editing that stack layer
# ---- color editing (materials + particle color curves) ----------------------
$script:BrowseMode = 'tex'      # 'tex' | 'mat' (material colors) | 'fx' (particle colors)
$script:ColorItems = @()        # current color rows (material params, or aggregated particle effects)
$script:ColorShownKind = $null  # "<skin>/<kind>" currently populated in the color list
$script:ColorOpsBySkin = @{}    # skin -> @{ rel -> @{ "<export>_<ordinal>" -> @{export,ordinal,name,[kind,]r,g,b} } }
$script:SelColor = $null        # selected ColorItem
$script:PvTimer = New-Object System.Windows.Forms.Timer   # preview debounce (see $onOpChanged)
$script:PvTimer.Interval = 120
$script:PvTimer.Add_Tick({ $script:PvTimer.Stop(); Show-Preview })

# ---- form -------------------------------------------------------------------
$frm = New-Object System.Windows.Forms.Form
$frm.Text = 'Variant Skin Studio - Marvel Rivals character mod generator'
# 964, not 930: the brand band across the top takes 54 of it and the rest comes
# out of slack that was already at the bottom. Still under a 1080p screen with a
# taskbar once the title bar is added.
$frm.ClientSize = New-Object System.Drawing.Size(1758, 964)
$frm.FormBorderStyle = 'FixedSingle'; $frm.MaximizeBox = $false
# CenterScreen centres in the WORK area, so the status bar clears the taskbar.
# Windows' default placement put the window at y=77 on a 1080p screen, which hid
# the bottom of it behind the taskbar - true of the old 930px layout too.
$frm.StartPosition = 'CenterScreen'
$frm.BackColor = $colBack; $frm.ForeColor = $colFore
$frm.Font = UIFont 9
foreach ($ip in @("$PSScriptRoot\branding\skin-studio.ico")) {
    if (Test-Path -LiteralPath $ip) { try { $frm.Icon = New-Object System.Drawing.Icon($ip) } catch {} }
}
# the window every modal the module opens is owned by (the colour picker)
Set-VuiOwner $frm

# our own status bar, not a StatusStrip - see AddStatusBar
$lblStatus = AddStatusBar $frm 'Pick a hero, pick a skin, double-click to open it.'
function Set-Status([string]$msg) { $lblStatus.Text = $msg; [System.Windows.Forms.Application]::DoEvents() }
$pump = { [System.Windows.Forms.Application]::DoEvents() }

# == left column: heroes + skins ==============================================
$frm.Controls.Add((New-Lbl 'SEARCH HERO' 14 10 120))
$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(14, 30); $txtSearch.Width = 240
$txtSearch.BackColor = $colField; $txtSearch.ForeColor = $colFore; $txtSearch.BorderStyle = 'FixedSingle'
$frm.Controls.Add($txtSearch)

$lstHeroes = New-Object System.Windows.Forms.ListBox
$lstHeroes.Location = New-Object System.Drawing.Point(14, 60)
$lstHeroes.Size = New-Object System.Drawing.Size(240, 420)
$lstHeroes.BackColor = $colPanel; $lstHeroes.ForeColor = $colFore; $lstHeroes.BorderStyle = 'FixedSingle'
$frm.Controls.Add($lstHeroes)

$btnRenameHero = New-Btn 'rename hero…' 14 484 116 26
$frm.Controls.Add($btnRenameHero)
$btnRenameSkin = New-Btn 'rename skin…' 138 484 116 26
$frm.Controls.Add($btnRenameSkin)

$frm.Controls.Add((New-Lbl 'SKINS' 14 518 120))
$lstSkins = New-Object System.Windows.Forms.ListBox
$lstSkins.Location = New-Object System.Drawing.Point(14, 538)
# 216, not 260: the two recolor tick boxes below need the room. Everything in
# this column is later pushed DOWN 54px for the brand band, and the status bar
# is docked to the bottom, so the column has to end by y=900 pre-shift.
$lstSkins.Size = New-Object System.Drawing.Size(240, 216)
$lstSkins.BackColor = $colPanel; $lstSkins.ForeColor = $colFore; $lstSkins.BorderStyle = 'FixedSingle'
$frm.Controls.Add($lstSkins)

# A chroma is a recolour of this costume sold as its own skin id, so editing the
# costume alone leaves every chroma of it vanilla in game. These carry whatever
# you apply onto the matching maps of those skins, and the build ships them in
# the SAME mod. Shown only when the open skin has recolours; see SS-ChromaGroups.
$chkChroma = New-Object System.Windows.Forms.CheckBox
$chkChroma.Text = 'also edit its recolors'
$chkChroma.Location = New-Object System.Drawing.Point(14, 758); $chkChroma.Size = New-Object System.Drawing.Size(150, 20)
$chkChroma.ForeColor = $colFore; $chkChroma.Checked = $true; $chkChroma.Visible = $false
$frm.Controls.Add($chkChroma)
$chkChromaMaybe = New-Object System.Windows.Forms.CheckBox
$chkChromaMaybe.Text = '+ possible recolors'
$chkChromaMaybe.Location = New-Object System.Drawing.Point(14, 780); $chkChromaMaybe.Size = New-Object System.Drawing.Size(240, 20)
$chkChromaMaybe.ForeColor = $colDim; $chkChromaMaybe.Checked = $false; $chkChromaMaybe.Visible = $false
$frm.Controls.Add($chkChromaMaybe)
# A recolour's dyed zones render one flat colour each, sampled from the atlas -
# which holds more than is ever on screen, so it lands duller than the part
# does. This opens the measurement (see Show-DyeCalDialog).
$btnDyeCal = New-Btn 'calibrate…' 166 757 88 22
$btnDyeCal.Visible = $false
$frm.Controls.Add($btnDyeCal)

$btnOpen = New-Btn 'OPEN SKIN' 14 804 240 34
MakePrimary $btnOpen | Out-Null      # filled sage: the one action on this column
$btnOpen.Font = UIFont 10 ([System.Drawing.FontStyle]::Bold) $FamHead
$frm.Controls.Add($btnOpen)

$btnOutDir = New-Btn 'output folder' 14 846 116 26
$frm.Controls.Add($btnOutDir)
$btnEditDir = New-Btn 'edit folder' 138 846 116 26
$frm.Controls.Add($btnEditDir)

# == middle: texture / color browser (mode toggle) ============================
# caption and hint are two labels now: the caption wears the display face like
# every other section header, and the hint gets a line of its own instead of
# being cut off at 274px (the longest of the three never fit).
$lblBrowse = New-Lbl 'TEXTURES' 270 6 270
$frm.Controls.Add($lblBrowse)
$lblBrowseHint = New-Lbl 'white = color + specular maps (editable) · gray = technical maps (normals / ORM / masks)' 272 28 556
$frm.Controls.Add($lblBrowseHint)
# mode toggle: Textures (pixels) · Materials (lighting colors) · Particles (VFX)
$btnModeTex = New-Btn 'Textures' 548 6 74 22
Set-ModeBtn $btnModeTex $true
$frm.Controls.Add($btnModeTex)
$btnModeMat = New-Btn 'Materials' 624 6 80 22
$frm.Controls.Add($btnModeMat)
$btnModeFx = New-Btn 'Particles' 706 6 82 22
$frm.Controls.Add($btnModeFx)
# Atelier round-trip (atelierlib.ps1) - the strip above the Layers card is the
# one free spot in the layout (smoke 14 checks it stays clear)
$btnAtImport = New-Btn 'import Atelier…' 1484 4 128 24
$frm.Controls.Add($btnAtImport)
$btnAtExport = New-Btn 'export to Atelier…' 1616 4 128 24
$frm.Controls.Add($btnAtExport)

$imgList = New-Object System.Windows.Forms.ImageList
$imgList.ImageSize = New-Object System.Drawing.Size(96, 96)
$imgList.ColorDepth = 'Depth32Bit'

$lvTex = New-Object System.Windows.Forms.ListView
$lvTex.Location = New-Object System.Drawing.Point(270, 48)   # 48, not 30: the hint line above it
$lvTex.Size = New-Object System.Drawing.Size(560, 782)
$lvTex.View = 'LargeIcon'; $lvTex.LargeImageList = $imgList
$lvTex.BackColor = $colPanel; $lvTex.ForeColor = $colFore; $lvTex.BorderStyle = 'FixedSingle'
$lvTex.HideSelection = $false; $lvTex.MultiSelect = $true; $lvTex.ShowItemToolTips = $true
$frm.Controls.Add($lvTex)

# Colors browser: one row per named material color, swatch icon = current color.
# Overlays the same region as the texture list; visibility swaps with the toggle.
$colorImgList = New-Object System.Windows.Forms.ImageList
$colorImgList.ImageSize = New-Object System.Drawing.Size(40, 40)
$colorImgList.ColorDepth = 'Depth32Bit'
$lvColors = New-Object System.Windows.Forms.ListView
$lvColors.Location = New-Object System.Drawing.Point(270, 48)
$lvColors.Size = New-Object System.Drawing.Size(560, 782)
$lvColors.View = 'Details'; $lvColors.SmallImageList = $colorImgList
$lvColors.BackColor = $colPanel; $lvColors.ForeColor = $colFore; $lvColors.BorderStyle = 'FixedSingle'
$lvColors.HideSelection = $false; $lvColors.MultiSelect = $true; $lvColors.FullRowSelect = $true
[void]$lvColors.Columns.Add('', 46)
[void]$lvColors.Columns.Add('material', 210)
[void]$lvColors.Columns.Add('color parameter', 190)
[void]$lvColors.Columns.Add('role', 100)
$lvColors.Visible = $false
$frm.Controls.Add($lvColors)

$chkAdvanced = New-Object System.Windows.Forms.CheckBox
$chkAdvanced.Text = 'Advanced: allow editing technical maps (normals / ORM / masks - can break shading)'
$chkAdvanced.Location = New-Object System.Drawing.Point(270, 838)
$chkAdvanced.Size = New-Object System.Drawing.Size(560, 20)
$chkAdvanced.ForeColor = $colDim
$frm.Controls.Add($chkAdvanced)

$lblCache = New-Lbl '' 270 860 560
$frm.Controls.Add($lblCache)

# == right: preview + ops + build =============================================
$frm.Controls.Add((New-Lbl 'VANILLA' 846 6 200))
$frm.Controls.Add((New-Lbl 'MODIFIED' 1163 6 200))
# The two previews sit in recessed wells, like every image slot in Variant UI.
# The well is a Panel BEHIND the PictureBox rather than a Paint handler ON it:
# a PictureBox draws its Image in OnPaint, and our handler runs after that, so
# painting the sink on the control itself would cover the picture. Adding the
# panel last puts it at the back of the z-order, which is where it belongs.
function Add-SinkWell($pic, [int]$pad) {
    $s = New-Object System.Windows.Forms.Panel
    $s.Location = New-Object System.Drawing.Point(($pic.Left - $pad), ($pic.Top - $pad))
    $s.Size = New-Object System.Drawing.Size(($pic.Width + 2*$pad), ($pic.Height + 2*$pad))
    $pic.Parent.Controls.Add($s)
    PaintSink $s 10
    return $s
}
$picVan = New-Object System.Windows.Forms.PictureBox
$picVan.Location = New-Object System.Drawing.Point(846, 30); $picVan.Size = New-Object System.Drawing.Size(305, 305)
$picVan.SizeMode = 'Zoom'; $picVan.BackColor = $Pal.Sink; $picVan.BorderStyle = 'None'
$frm.Controls.Add($picVan)
$picMod = New-Object System.Windows.Forms.PictureBox
$picMod.Location = New-Object System.Drawing.Point(1163, 30); $picMod.Size = New-Object System.Drawing.Size(305, 305)
$picMod.SizeMode = 'Zoom'; $picMod.BackColor = $Pal.Sink; $picMod.BorderStyle = 'None'
$frm.Controls.Add($picMod)
$sinkVan = Add-SinkWell $picVan 3
$sinkMod = Add-SinkWell $picMod 3

$lblTexName = New-Lbl 'no texture selected' 846 340 622
$lblTexName.ForeColor = $colPink
$frm.Controls.Add($lblTexName)

$grpOp = New-Object System.Windows.Forms.GroupBox
$grpOp.Text = 'Texture operation'
$grpOp.Location = New-Object System.Drawing.Point(846, 362)
$grpOp.Size = New-Object System.Drawing.Size(622, 328)
$grpOp.ForeColor = $colAccent; $grpOp.BackColor = $colPanel
$frm.Controls.Add($grpOp)

$rbVanilla = New-Object System.Windows.Forms.RadioButton
$rbVanilla.Text = 'Keep vanilla'; $rbVanilla.Location = New-Object System.Drawing.Point(16, 24)
$rbVanilla.Size = New-Object System.Drawing.Size(140, 20); $rbVanilla.ForeColor = $colFore; $rbVanilla.Checked = $true
$grpOp.Controls.Add($rbVanilla)

$rbRecolor = New-Object System.Windows.Forms.RadioButton
$rbRecolor.Text = 'Recolor:'; $rbRecolor.Location = New-Object System.Drawing.Point(16, 50)
$rbRecolor.Size = New-Object System.Drawing.Size(80, 20); $rbRecolor.ForeColor = $colFore
$grpOp.Controls.Add($rbRecolor)

# VuiCombo, not ComboBox - a ComboBox subclass that paints its own frame, arrow
# and list rows, so the drop-down stops being the one bit of Windows chrome left
# on the panel. Every member used below is unchanged.
$cmbMode = New-Object VuiCombo
$cmbMode.Location = New-Object System.Drawing.Point(100, 48); $cmbMode.Size = New-Object System.Drawing.Size(150, 24)
$cmbMode.DropDownStyle = 'DropDownList'
[void]$cmbMode.Items.AddRange(@('Tint to color', 'Flat paint', 'Recolor color family', 'Hue shift', 'HSL adjust', 'Grayscale', 'Invert', 'Gradient tint', 'Gradient paint'))
$cmbMode.SelectedIndex = 0
$cmbMode.BackColor = $colField; $cmbMode.ForeColor = $colFore; $cmbMode.FlatStyle = 'Flat'
$grpOp.Controls.Add($cmbMode)

$pnlColor = New-Object System.Windows.Forms.Panel
$pnlColor.Location = New-Object System.Drawing.Point(262, 46); $pnlColor.Size = New-Object System.Drawing.Size(26, 26)
$pnlColor.BackColor = [System.Drawing.Color]::FromArgb(185, 167, 230); $pnlColor.BorderStyle = 'FixedSingle'
$grpOp.Controls.Add($pnlColor)
$btnColor = New-Btn 'pick color…' 296 46 100 26
$grpOp.Controls.Add($btnColor)

$lblStr = New-Lbl 'Strength: 100%' 412 50 120
$grpOp.Controls.Add($lblStr)
# VuiSlider, not TrackBar - same Value/Minimum/Maximum/TickFrequency/
# ValueChanged surface, drawn in the studio's palette instead of the Windows
# theme's chunky grey channel and system-blue focus ring
$trkStr = New-Object VuiSlider
$trkStr.Location = New-Object System.Drawing.Point(408, 70); $trkStr.Size = New-Object System.Drawing.Size(200, 30)
$trkStr.Minimum = 0; $trkStr.Maximum = 100; $trkStr.Value = 100; $trkStr.TickFrequency = 25
$grpOp.Controls.Add($trkStr)

$lblHueL = New-Lbl 'Hue shift °' 16 84 80
$grpOp.Controls.Add($lblHueL)
$numHue = New-Object System.Windows.Forms.NumericUpDown
$numHue.Location = New-Object System.Drawing.Point(100, 82); $numHue.Width = 70
$numHue.Minimum = -180; $numHue.Maximum = 180; $numHue.Value = 0
$numHue.BackColor = $colField; $numHue.ForeColor = $colFore
$grpOp.Controls.Add($numHue)

# "Recolor color family" takes this slot instead of Hue shift: for that mode the
# target hue comes from the swatch, so a hue nudge is noise, and WHICH family
# moves is the question that actually matters on a shared atlas.
$btnBand = New-Btn 'auto' 100 82 70 26
$grpOp.Controls.Add($btnBand)

$lblSatL = New-Lbl 'Sat %' 184 84 46
$grpOp.Controls.Add($lblSatL)
$numSat = New-Object System.Windows.Forms.NumericUpDown
$numSat.Location = New-Object System.Drawing.Point(230, 82); $numSat.Width = 62
$numSat.Minimum = 0; $numSat.Maximum = 300; $numSat.Value = 100
$numSat.BackColor = $colField; $numSat.ForeColor = $colFore
$grpOp.Controls.Add($numSat)

$lblLightL = New-Lbl 'Light %' 300 84 56
$grpOp.Controls.Add($lblLightL)
$numLight = New-Object System.Windows.Forms.NumericUpDown
$numLight.Location = New-Object System.Drawing.Point(356, 82); $numLight.Width = 62
$numLight.Minimum = 0; $numLight.Maximum = 300; $numLight.Value = 100
$numLight.BackColor = $colField; $numLight.ForeColor = $colFore
$grpOp.Controls.Add($numLight)

# gradient controls share the hue/sat/light row - visibility swaps by mode.
# main swatch = color A (top/left/top-left); B = end color; C/D = bottom corners
$pnlColorB = New-Object System.Windows.Forms.Panel
$pnlColorB.Location = New-Object System.Drawing.Point(100, 82); $pnlColorB.Size = New-Object System.Drawing.Size(26, 26)
$pnlColorB.BackColor = $colPink; $pnlColorB.BorderStyle = 'FixedSingle'
$grpOp.Controls.Add($pnlColorB)
$btnColorB = New-Btn 'B…' 132 82 40 26
$grpOp.Controls.Add($btnColorB)
$pnlColorC = New-Object System.Windows.Forms.Panel
$pnlColorC.Location = New-Object System.Drawing.Point(178, 82); $pnlColorC.Size = New-Object System.Drawing.Size(26, 26)
$pnlColorC.BackColor = $colAccent; $pnlColorC.BorderStyle = 'FixedSingle'
$grpOp.Controls.Add($pnlColorC)
$btnColorC = New-Btn 'C…' 210 82 40 26
$grpOp.Controls.Add($btnColorC)
$pnlColorD = New-Object System.Windows.Forms.Panel
$pnlColorD.Location = New-Object System.Drawing.Point(256, 82); $pnlColorD.Size = New-Object System.Drawing.Size(26, 26)
$pnlColorD.BackColor = [System.Drawing.Color]::FromArgb(120, 200, 220); $pnlColorD.BorderStyle = 'FixedSingle'
$grpOp.Controls.Add($pnlColorD)
$btnColorD = New-Btn 'D…' 288 82 40 26
$grpOp.Controls.Add($btnColorD)
$cmbGradDir = New-Object VuiCombo
$cmbGradDir.Location = New-Object System.Drawing.Point(336, 82); $cmbGradDir.Size = New-Object System.Drawing.Size(130, 24)
$cmbGradDir.DropDownStyle = 'DropDownList'
[void]$cmbGradDir.Items.AddRange(@('top → bottom', 'left → right', 'diagonal', 'radial', '4-corner mesh'))
$cmbGradDir.SelectedIndex = 0
$cmbGradDir.BackColor = $colField; $cmbGradDir.ForeColor = $colFore
$grpOp.Controls.Add($cmbGradDir)

$chkProtect = New-Object System.Windows.Forms.CheckBox
$chkProtect.Text = 'Protect skin tones (leave warm face/skin hues alone)'
$chkProtect.Location = New-Object System.Drawing.Point(16, 110); $chkProtect.Size = New-Object System.Drawing.Size(326, 20)
$chkProtect.ForeColor = $colFore; $chkProtect.Checked = $true
$grpOp.Controls.Add($chkProtect)

# Some skins ship the same map two or three times under different names - a
# transformed form, a second costume state - and editing one leaves the others
# vanilla in game. This mirrors whatever you apply onto them. Shown only when
# the selected texture actually has another version; see SS-LinkGroups.
$chkLinked = New-Object System.Windows.Forms.CheckBox
$chkLinked.Text = 'also apply to the other version'
$chkLinked.Location = New-Object System.Drawing.Point(348, 110); $chkLinked.Size = New-Object System.Drawing.Size(260, 20)
$chkLinked.ForeColor = $colFore; $chkLinked.Checked = $true
$chkLinked.Visible = $false
$grpOp.Controls.Add($chkLinked)

$rbReplace = New-Object System.Windows.Forms.RadioButton
$rbReplace.Text = 'Replace with image:'; $rbReplace.Location = New-Object System.Drawing.Point(16, 140)
$rbReplace.Size = New-Object System.Drawing.Size(150, 20); $rbReplace.ForeColor = $colFore
$grpOp.Controls.Add($rbReplace)
$btnPickImg = New-Btn 'choose file…' 170 137 100 26
$grpOp.Controls.Add($btnPickImg)
$lblImgPath = New-Lbl '(none - stretched to the vanilla canvas)' 278 141 330
$grpOp.Controls.Add($lblImgPath)

$rbEdited = New-Object System.Windows.Forms.RadioButton
$rbEdited.Text = 'Use my hand-edited PNG'; $rbEdited.Location = New-Object System.Drawing.Point(16, 170)
$rbEdited.Size = New-Object System.Drawing.Size(180, 20); $rbEdited.ForeColor = $colFore
$grpOp.Controls.Add($rbEdited)
$btnEditPng = New-Btn 'send PNG to edit folder…' 200 167 170 26
$grpOp.Controls.Add($btnEditPng)
$lblEditPath = New-Lbl '' 378 171 230
$grpOp.Controls.Add($lblEditPath)

$btnApply = New-Btn 'APPLY TO THIS TEXTURE' 16 206 220 34
MakePrimary $btnApply | Out-Null
$btnApply.Font = UIFont 9 ([System.Drawing.FontStyle]::Bold) $FamHead
$grpOp.Controls.Add($btnApply)
$btnRevert = New-Btn 'revert to vanilla' 244 206 130 34
$grpOp.Controls.Add($btnRevert)
$btnBulk = New-Btn 'bulk apply recolor…' 384 206 224 34
$grpOp.Controls.Add($btnBulk)

$lblBulkCats = New-Lbl 'bulk also touches:' 16 250 108
$grpOp.Controls.Add($lblBulkCats)
$chkBHair = New-Object System.Windows.Forms.CheckBox
$chkBHair.Text = 'hair'; $chkBHair.Checked = $false
$chkBHair.Location = New-Object System.Drawing.Point(126, 247); $chkBHair.Size = New-Object System.Drawing.Size(56, 20)
$chkBHair.ForeColor = $colFore
$grpOp.Controls.Add($chkBHair)
$chkBFace = New-Object System.Windows.Forms.CheckBox
$chkBFace.Text = 'face / eyes'; $chkBFace.Checked = $false
$chkBFace.Location = New-Object System.Drawing.Point(186, 247); $chkBFace.Size = New-Object System.Drawing.Size(92, 20)
$chkBFace.ForeColor = $colFore
$grpOp.Controls.Add($chkBFace)
$chkBProps = New-Object System.Windows.Forms.CheckBox
$chkBProps.Text = 'weapons / props'; $chkBProps.Checked = $true
$chkBProps.Location = New-Object System.Drawing.Point(284, 247); $chkBProps.Size = New-Object System.Drawing.Size(126, 20)
$chkBProps.ForeColor = $colFore
$grpOp.Controls.Add($chkBProps)

$lblOpHint = New-Lbl 'Bulk = outfit + ticked groups. Ctrl-click several thumbnails to bulk only those. LOD2 atlas rides with outfit.' 16 274 590
$grpOp.Controls.Add($lblOpHint)
$lblTechWarn = New-Lbl '' 16 296 590
$lblTechWarn.ForeColor = $Pal.Amber        # a caution, not an accent - amber is the only warning colour
$grpOp.Controls.Add($lblTechWarn)

# == color operation panel (shown in Colors mode, over the texture op panel) ==
$grpColorOp = New-Object System.Windows.Forms.GroupBox
$grpColorOp.Text = 'Color operation  (material lighting · emissive · rim · tint · eyes)'
$grpColorOp.Location = New-Object System.Drawing.Point(846, 362)
$grpColorOp.Size = New-Object System.Drawing.Size(622, 328)
$grpColorOp.ForeColor = $colAccent; $grpColorOp.BackColor = $colPanel
$grpColorOp.Visible = $false
$frm.Controls.Add($grpColorOp)

$grpColorOp.Controls.Add((New-Lbl 'Current' 16 26 80))
$pnlColCur = New-Object System.Windows.Forms.Panel
$pnlColCur.Location = New-Object System.Drawing.Point(16, 46); $pnlColCur.Size = New-Object System.Drawing.Size(70, 70)
$pnlColCur.BorderStyle = 'FixedSingle'; $pnlColCur.BackColor = $colField
$grpColorOp.Controls.Add($pnlColCur)

$grpColorOp.Controls.Add((New-Lbl 'New color' 120 26 120))
$pnlColNew = New-Object System.Windows.Forms.Panel
$pnlColNew.Location = New-Object System.Drawing.Point(120, 46); $pnlColNew.Size = New-Object System.Drawing.Size(70, 70)
$pnlColNew.BorderStyle = 'FixedSingle'; $pnlColNew.BackColor = $colField
$grpColorOp.Controls.Add($pnlColNew)
$btnColPick = New-Btn 'pick color…' 210 46 120 30
$grpColorOp.Controls.Add($btnColPick)
$btnColApply = New-Btn 'APPLY COLOR' 210 84 120 32
MakePrimary $btnColApply | Out-Null
$btnColApply.Font = UIFont 9 ([System.Drawing.FontStyle]::Bold) $FamHead
$grpColorOp.Controls.Add($btnColApply)
$btnColRevert = New-Btn 'revert this color' 342 84 130 32
$grpColorOp.Controls.Add($btnColRevert)

$lblColInfo = New-Lbl 'Select a color on the left. Values are HDR-aware; picker is sRGB.' 16 126 600
$lblColInfo.ForeColor = $colDim
$grpColorOp.Controls.Add($lblColInfo)

# bulk retint every material color of the skin to one target
$grpColorOp.Controls.Add((New-Lbl 'Bulk:' 16 160 40))
$pnlColBulk = New-Object System.Windows.Forms.Panel
$pnlColBulk.Location = New-Object System.Drawing.Point(58, 158); $pnlColBulk.Size = New-Object System.Drawing.Size(26, 26)
$pnlColBulk.BorderStyle = 'FixedSingle'; $pnlColBulk.BackColor = $colPink
$grpColorOp.Controls.Add($pnlColBulk)
$btnColBulkPick = New-Btn 'B…' 90 158 40 26
$grpColorOp.Controls.Add($btnColBulkPick)
$btnColBulkAll = New-Btn 'retint ALL shown →' 138 158 220 26
$grpColorOp.Controls.Add($btnColBulkAll)
$btnColBulkRim = New-Btn 'retint rim/emissive only →' 364 158 200 26
$grpColorOp.Controls.Add($btnColBulkRim)

$lblColWarn = New-Lbl 'No live 3D preview for colors (needs the game engine) - the swatch is the intended value; verify in-game after building.' 16 196 600
$lblColWarn.Size = New-Object System.Drawing.Size(600, 40)
$lblColWarn.ForeColor = $Pal.Amber
$grpColorOp.Controls.Add($lblColWarn)

$lblColStats = New-Lbl '' 16 244 600
$lblColStats.ForeColor = $colAccent
$grpColorOp.Controls.Add($lblColStats)

# == far right: layer stack ===================================================
$grpLayers = New-Object System.Windows.Forms.GroupBox
$grpLayers.Text = 'Layers (applied top to bottom)'
$grpLayers.Location = New-Object System.Drawing.Point(1484, 30)
$grpLayers.Size = New-Object System.Drawing.Size(260, 640)
$grpLayers.ForeColor = $colAccent; $grpLayers.BackColor = $colPanel
$frm.Controls.Add($grpLayers)

$lstLayers = New-Object System.Windows.Forms.ListBox
$lstLayers.Location = New-Object System.Drawing.Point(12, 24)
$lstLayers.Size = New-Object System.Drawing.Size(236, 400)
$lstLayers.BackColor = $colField; $lstLayers.ForeColor = $colFore; $lstLayers.BorderStyle = 'FixedSingle'
$grpLayers.Controls.Add($lstLayers)

$btnLayerAdd = New-Btn '+ add panel op as new layer' 12 434 236 30
MakePrimary $btnLayerAdd | Out-Null
$grpLayers.Controls.Add($btnLayerAdd)
$btnLayerUpd = New-Btn 'update layer' 12 470 113 28
$grpLayers.Controls.Add($btnLayerUpd)
$btnLayerDel = New-Btn 'remove layer' 135 470 113 28
$grpLayers.Controls.Add($btnLayerDel)
$btnLayerUp = New-Btn 'move up' 12 504 113 28
$grpLayers.Controls.Add($btnLayerUp)
$btnLayerDn = New-Btn 'move down' 135 504 113 28
$grpLayers.Controls.Add($btnLayerDn)

$lblDraft = New-Lbl '' 12 540 236
$lblDraft.Size = New-Object System.Drawing.Size(236, 54)
$lblDraft.ForeColor = $Pal.Amber
$grpLayers.Controls.Add($lblDraft)
$lblLayerHint = New-Lbl 'Preview shows the stack plus the panel as a draft until you add/update.' 12 596 236
$lblLayerHint.Size = New-Object System.Drawing.Size(236, 36)
$grpLayers.Controls.Add($lblLayerHint)

# == far right: Blender bridge ================================================
$grpBlend = New-Object System.Windows.Forms.GroupBox
$grpBlend.Text = 'Model'
$grpBlend.Location = New-Object System.Drawing.Point(1484, 676)
$grpBlend.Size = New-Object System.Drawing.Size(260, 198)
$grpBlend.ForeColor = $colAccent; $grpBlend.BackColor = $colPanel
$frm.Controls.Add($grpBlend)

$btnBlender = New-Btn 'OPEN IN BLENDER' 12 24 236 34
MakePrimary $btnBlender | Out-Null
$btnBlender.Font = UIFont 10 ([System.Drawing.FontStyle]::Bold) $FamHead
$grpBlend.Controls.Add($btnBlender)
$btnBlendRefresh = New-Btn 'refresh textures in Blender' 12 64 236 28
$grpBlend.Controls.Add($btnBlendRefresh)
$btnBlendPull = New-Btn 'import painted textures' 12 98 236 28
$grpBlend.Controls.Add($btnBlendPull)
# uses the same mesh export as the Blender bridge, which is why it lives here
$btnPaintId = New-Btn 'what paints this?…' 12 132 116 28
$grpBlend.Controls.Add($btnPaintId)
# live 3D window (viewer\ + viewlib.ps1); follows every edit by itself. Shares
# the row with paint-ID: the column is full down to the status bar (smoke 14)
$btn3D = New-Btn '3D PREVIEW' 132 132 116 28
$btn3D.Font = UIFont 9 ([System.Drawing.FontStyle]::Bold) $FamHead
$grpBlend.Controls.Add($btn3D)
$lblBlend = New-Lbl 'View + paint the model with your design. Geometry edits cannot ship.' 12 166 236
$lblBlend.Size = New-Object System.Drawing.Size(236, 30)
$grpBlend.Controls.Add($lblBlend)

# ---- build bar --------------------------------------------------------------
$grpBuild = New-Object System.Windows.Forms.GroupBox
$grpBuild.Text = 'Build'
$grpBuild.Location = New-Object System.Drawing.Point(846, 698)
$grpBuild.Size = New-Object System.Drawing.Size(622, 176)
$grpBuild.ForeColor = $colAccent; $grpBuild.BackColor = $colPanel
$frm.Controls.Add($grpBuild)

$grpBuild.Controls.Add((New-Lbl 'Mod name (letters/digits)' 16 24 170))
$txtModName = New-Object System.Windows.Forms.TextBox
$txtModName.Location = New-Object System.Drawing.Point(16, 44); $txtModName.Width = 180
$txtModName.BackColor = $colField; $txtModName.ForeColor = $colFore; $txtModName.BorderStyle = 'FixedSingle'
$grpBuild.Controls.Add($txtModName)

$grpBuild.Controls.Add((New-Lbl 'Display name (zip)' 212 24 150))
$txtDisplay = New-Object System.Windows.Forms.TextBox
$txtDisplay.Location = New-Object System.Drawing.Point(212, 44); $txtDisplay.Width = 200
$txtDisplay.BackColor = $colField; $txtDisplay.ForeColor = $colFore; $txtDisplay.BorderStyle = 'FixedSingle'
$grpBuild.Controls.Add($txtDisplay)

$chkInstall = New-Object System.Windows.Forms.CheckBox
$chkInstall.Text = 'install to ~mods'; $chkInstall.Checked = $true
$chkInstall.Location = New-Object System.Drawing.Point(430, 30); $chkInstall.Size = New-Object System.Drawing.Size(130, 20)
$chkInstall.ForeColor = $colFore
$grpBuild.Controls.Add($chkInstall)
$chkZip = New-Object System.Windows.Forms.CheckBox
$chkZip.Text = 'zip to Downloads'; $chkZip.Checked = $true
$chkZip.Location = New-Object System.Drawing.Point(430, 52); $chkZip.Size = New-Object System.Drawing.Size(130, 20)
$chkZip.ForeColor = $colFore
$grpBuild.Controls.Add($chkZip)

$grpBuild.Controls.Add((New-Lbl 'Designs' 16 78 100))
$cmbDesign = New-Object VuiCombo
$cmbDesign.Location = New-Object System.Drawing.Point(16, 98); $cmbDesign.Size = New-Object System.Drawing.Size(240, 24)
$cmbDesign.DropDownStyle = 'DropDownList'
$cmbDesign.BackColor = $colField; $cmbDesign.ForeColor = $colFore
$grpBuild.Controls.Add($cmbDesign)
$btnSaveD = New-Btn 'save design' 266 96 100 26
$grpBuild.Controls.Add($btnSaveD)
$btnLoadD = New-Btn 'load design' 372 96 100 26
$grpBuild.Controls.Add($btnLoadD)
$btnClearMods = New-Btn 'uninstall all my mods…' 478 96 128 26
$grpBuild.Controls.Add($btnClearMods)

$btnBuild = New-Btn 'BUILD MOD' 16 132 404 34
MakePrimary $btnBuild | Out-Null
$btnBuild.Font = UIFont 11 ([System.Drawing.FontStyle]::Bold) $FamHead
$grpBuild.Controls.Add($btnBuild)
# Live preview sits beside the build, not inside it: it writes the design out as
# PNGs the in-game menu re-imports on a keypress, so a colour can be judged on
# the real model without a pak, an install or a restart. Nothing it does touches
# ~mods, so it is safe to leave running while a built mod is out for delivery.
$btnLive = New-Btn 'LIVE PREVIEW' 430 132 176 34
$btnLive.Font = UIFont 10 ([System.Drawing.FontStyle]::Bold) $FamHead
$grpBuild.Controls.Add($btnLive)

# ---- the brand band, and the room it needs ----------------------------------
# Every control above is hand-placed against the top of the window, and there
# are four full columns of them - so rather than re-coordinate the file, the
# whole layout is pushed down in one pass and the band drops into the gap. The
# status bar is Dock='Bottom' and looks after itself, hence the docked skip.
# Nothing in this app repositions a top-level control at runtime (checked), so
# this is the only place window coordinates are ever decided.
$BandY = 6; $BandH = 46; $Shift = 54
foreach ($c in @($frm.Controls)) {
    if ($c.Dock -ne 'None') { continue }
    $c.Top = $c.Top + $Shift
}
$band = AddBrandHeader $frm 14 $BandY ($frm.ClientSize.Width - 28) $BandH `
            'Skin Studio' 'recolour, replace and paint any hero skin'

# ---- cards ------------------------------------------------------------------
# The five GroupBoxes become Variant UI cards: shallow gradient, rounded
# hairline outline, caption redrawn in the display face. PaintCard has to run
# BEFORE StyleTree - it is what tags them 'keep-card', which is how SurfaceOf
# knows to sample the gradient for every check box and slider inside them.
foreach ($g in @($grpOp, $grpColorOp, $grpLayers, $grpBlend, $grpBuild)) { PaintCard $g 12 $null }
# and the colour chips, before StyleTree - the keep-swatch tag is what stops it
# flattening a light swatch to panel grey
foreach ($p in @($pnlColor, $pnlColorB, $pnlColorC, $pnlColorD, $pnlColBulk)) { Make-Swatch $p 6 }
foreach ($p in @($pnlColCur, $pnlColNew)) { Make-Swatch $p 8 }

# ---- helpers ----------------------------------------------------------------
function Get-SelHero {
    if ($lstHeroes.SelectedItem) { LabelId ([string]$lstHeroes.SelectedItem) } else { $null }
}
function Get-SelSkin {
    if ($lstSkins.SelectedItem) { LabelId ([string]$lstSkins.SelectedItem) } else { $null }
}
function Refresh-HeroList {
    $needle = $txtSearch.Text.Trim()
    $lstHeroes.BeginUpdate(); $lstHeroes.Items.Clear()
    foreach ($hid in $script:HeroIds) {
        $lab = HeroLabel $hid
        if ($needle -and ($lab -notmatch [regex]::Escape($needle))) { continue }
        [void]$lstHeroes.Items.Add($lab)
    }
    $lstHeroes.EndUpdate()
}
function Refresh-SkinList {
    $hid = Get-SelHero
    $lstSkins.BeginUpdate(); $lstSkins.Items.Clear()
    if ($hid) {
        foreach ($sid in ($script:Map.heroSkins[$hid].Keys | Sort-Object)) {
            [void]$lstSkins.Items.Add((SkinLabel $sid))
        }
    }
    $lstSkins.EndUpdate()
}
function Get-Ops {
    if (-not $script:CurSkin) { return @{} }
    if (-not $script:OpsBySkin.ContainsKey($script:CurSkin)) { $script:OpsBySkin[$script:CurSkin] = @{} }
    $script:OpsBySkin[$script:CurSkin]
}
$modeMap = @{ 'Tint to color' = 'tint'; 'Flat paint' = 'paint'; 'Recolor color family' = 'huerange'; 'Hue shift' = 'hueshift'; 'HSL adjust' = 'hsl'; 'Grayscale' = 'gray'; 'Invert' = 'invert'; 'Gradient tint' = 'gradtint'; 'Gradient paint' = 'gradpaint' }
$gradDirMap = @{ 'top → bottom' = 'v'; 'left → right' = 'h'; 'diagonal' = 'diag'; 'radial' = 'radial'; '4-corner mesh' = 'corners' }
# the band button's caption IS the readout: "auto", or the centre and half-width
function Update-BandButton {
    if ($script:BandCenter -lt 0) { $btnBand.Text = 'auto' }
    else { $btnBand.Text = '{0:N0}° ±{1:N0}' -f $script:BandCenter, $(if ($script:BandWidth -gt 0) { $script:BandWidth } else { 34 }) }
}
function Update-OpControlVis {
    # hue/sat/light row doubles as the gradient row - swap by selected mode
    $isGrad = ([string]$cmbMode.SelectedItem) -like 'Gradient*'
    $isBand = ($modeMap[[string]$cmbMode.SelectedItem] -eq 'huerange')
    foreach ($c in @($lblHueL, $lblSatL, $numSat, $lblLightL, $numLight)) { $c.Visible = -not $isGrad }
    $numHue.Visible  = (-not $isGrad) -and (-not $isBand)
    $btnBand.Visible = (-not $isGrad) -and $isBand
    $lblHueL.Text = if ($isBand) { 'Color family' } else { 'Hue shift °' }
    if ($isBand) { Update-BandButton }
    foreach ($c in @($pnlColorB, $btnColorB, $cmbGradDir)) { $c.Visible = $isGrad }
    $isMesh = $isGrad -and (([string]$cmbGradDir.SelectedItem) -eq '4-corner mesh')
    foreach ($c in @($pnlColorC, $btnColorC, $pnlColorD, $btnColorD)) { $c.Visible = $isMesh }
}
# bulk-apply category: hair and face/eyes are opt-in, weapons/props opt-out,
# everything else (equip/cloth/body + the LOD2 atlas) is the core outfit group
function Get-BulkCat([string]$rel) {
    $leaf = (Split-Path $rel -Leaf).ToUpperInvariant()
    if ($leaf -match 'HAIR') { return 'hair' }
    if ($leaf -match 'HEAD|_SKIN_|EYE|FACE|TOOTH|SCLERA|MOUTH') { return 'face' }
    if ($rel -match '(?i)\\Weapons\\|\\Slots\\' -or $leaf -like 'T_WP_*' -or $leaf -like 'T_SLOT*') { return 'props' }
    'outfit'
}
function Get-PanelOp {
    # translate the current panel state into an op hashtable (or $null = vanilla)
    if ($rbVanilla.Checked) { return $null }
    if ($rbRecolor.Checked) {
        $op = @{
            mode        = $modeMap[[string]$cmbMode.SelectedItem]
            color       = ('#{0:X2}{1:X2}{2:X2}' -f $pnlColor.BackColor.R, $pnlColor.BackColor.G, $pnlColor.BackColor.B)
            strength    = [Math]::Round($trkStr.Value / 100.0, 3)
            hueShift    = [double]$numHue.Value
            satMul      = [Math]::Round($numSat.Value / 100.0, 3)
            lightMul    = [Math]::Round($numLight.Value / 100.0, 3)
            protectSkin = [bool]$chkProtect.Checked
        }
        if ($op.mode -like 'grad*') {
            $op.color2  = ('#{0:X2}{1:X2}{2:X2}' -f $pnlColorB.BackColor.R, $pnlColorB.BackColor.G, $pnlColorB.BackColor.B)
            $op.color3  = ('#{0:X2}{1:X2}{2:X2}' -f $pnlColorC.BackColor.R, $pnlColorC.BackColor.G, $pnlColorC.BackColor.B)
            $op.color4  = ('#{0:X2}{1:X2}{2:X2}' -f $pnlColorD.BackColor.R, $pnlColorD.BackColor.G, $pnlColorD.BackColor.B)
            $op.gradDir = $gradDirMap[[string]$cmbGradDir.SelectedItem]
        }
        if ($op.mode -eq 'huerange') {
            # which hue family moves. -1 = let the engine pick the dominant one.
            $op.bandCenter = [double]$script:BandCenter
            $op.bandWidth  = [double]$script:BandWidth
        }
        return $op
    }
    if ($rbReplace.Checked) {
        if (-not $lblImgPath.Tag) { return $null }
        return @{ mode = 'replace'; file = [string]$lblImgPath.Tag; strength = [Math]::Round($trkStr.Value / 100.0, 3) }
    }
    if ($rbEdited.Checked) {
        if (-not $script:SelTex) { return $null }
        $editPath = Join-Path $SS_Root ('work\edit\{0}\{1}' -f $script:CurSkin, [IO.Path]::GetFileName($script:SelTex.Rel))
        $editPath = [IO.Path]::ChangeExtension($editPath, 'png')
        if (-not (Test-Path -LiteralPath $editPath)) { return $null }
        return @{ mode = 'edited'; file = $editPath; strength = 1.0 }
    }
    $null
}
function Set-PanelFromOp($op) {
    if (-not $op) { $rbVanilla.Checked = $true; return }
    $mode = [string](SS-OpVal $op 'mode' 'tint')
    if ($mode -eq 'replace') {
        $rbReplace.Checked = $true
        $lblImgPath.Tag = [string](SS-OpVal $op 'file' '')
        $lblImgPath.Text = Split-Path ([string](SS-OpVal $op 'file' '')) -Leaf
    } elseif ($mode -eq 'edited') {
        $rbEdited.Checked = $true
    } else {
        $rbRecolor.Checked = $true
        foreach ($kv in $modeMap.GetEnumerator()) { if ($kv.Value -eq $mode) { $cmbMode.SelectedItem = $kv.Key } }
        try { $pnlColor.BackColor = [System.Drawing.ColorTranslator]::FromHtml([string](SS-OpVal $op 'color' '#B9A7E6')) } catch {}
        if ($mode -like 'grad*') {
            try { $pnlColorB.BackColor = [System.Drawing.ColorTranslator]::FromHtml([string](SS-OpVal $op 'color2' '#F2B8D8')) } catch {}
            try { $pnlColorC.BackColor = [System.Drawing.ColorTranslator]::FromHtml([string](SS-OpVal $op 'color3' '#B9A7E6')) } catch {}
            try { $pnlColorD.BackColor = [System.Drawing.ColorTranslator]::FromHtml([string](SS-OpVal $op 'color4' '#78C8DC')) } catch {}
            $dirVal = [string](SS-OpVal $op 'gradDir' 'v')
            foreach ($kv in $gradDirMap.GetEnumerator()) { if ($kv.Value -eq $dirVal) { $cmbGradDir.SelectedItem = $kv.Key } }
        }
        $numHue.Value = [Math]::Max(-180, [Math]::Min(180, [decimal](SS-OpVal $op 'hueShift' 0)))
        $numSat.Value = [Math]::Max(0, [Math]::Min(300, [decimal](100 * (SS-OpVal $op 'satMul' 1))))
        $numLight.Value = [Math]::Max(0, [Math]::Min(300, [decimal](100 * (SS-OpVal $op 'lightMul' 1))))
        $chkProtect.Checked = [bool](SS-OpVal $op 'protectSkin' $false)
        # a design saved before the band picker existed has neither key, and the
        # defaults (-1 / 0) are exactly "auto", so old work reloads unchanged
        $script:BandCenter = [double](SS-OpVal $op 'bandCenter' -1.0)
        $script:BandWidth  = [double](SS-OpVal $op 'bandWidth' 0.0)
        Update-BandButton
    }
    $trkStr.Value = [Math]::Max(0, [Math]::Min(100, [int](100 * (SS-OpVal $op 'strength' 1))))
}

# ---- "what paints this?" ----------------------------------------------------
# Click a part of the model and get told what actually colours it. Reading an
# atlas by eye is guesswork - it was wrong twice on White Fox, where the tie
# turned out to be a violet BaseTint on a material rather than anything in a
# texture. Two cached renders do it properly: one says which MATERIAL owns a
# pixel, the other says WHERE in that material's atlas it came from.
$script:piDir = $null; $script:piView = 'front'
$script:piId = $null; $script:piUv = $null; $script:piLegend = $null
$script:piMatTex = $null; $script:piColors = $null
$script:piPic = $null; $script:piOut = $null; $script:piCrop = $null; $script:piCoord = $null
$script:piParams = $null; $script:piParamImgs = $null; $script:piTexList = $null
$script:piHitTex = $null        # the base texture of the last click, for the jump button

function PiFromSrgb([double]$b) {
    $c = $b / 255.0
    if ($c -le 0.04045) { return $c / 12.92 }
    return [Math]::Pow(($c + 0.055) / 1.055, 2.4)
}
function PiToSrgb([double]$c) {
    if ($c -le 0.0031308) { $v = $c * 12.92 } else { $v = 1.055 * [Math]::Pow($c, 1.0 / 2.4) - 0.055 }
    [int][Math]::Round([Math]::Max(0.0, [Math]::Min(1.0, $v)) * 255.0)
}
function PiTexKind([string]$name) {
    switch -Regex ($name) {
        '_D$'   { 'base colour' ; break }
        '_E$'   { 'emissive' ; break }
        '_S$'   { 'specular tint' ; break }
        '_N$'   { 'normal' ; break }
        '_ORM$' { 'ORM' ; break }
        '_M$'   { 'mask' ; break }
        default { 'other' }
    }
}
# a colour parameter counts as an override if it is not white. MC_Shade* are the
# stock shading ramp and are never white, so they are noise here.
function PiIsOverride($c) {
    if ([string]$c.name -like 'MC_*') { return $false }
    if (([string]$c.name -notmatch 'Tint') -and ([string]$c.name -notmatch 'Color')) { return $false }
    $d = [Math]::Max([Math]::Abs(1.0 - $c.r), [Math]::Max([Math]::Abs(1.0 - $c.g), [Math]::Abs(1.0 - $c.b)))
    return ($d -gt 0.02)
}

function Update-PaintIdView {
    if (-not $script:piDir) { return }
    foreach ($k in 'Id', 'Uv') {
        $old = if ($k -eq 'Id') { $script:piId } else { $script:piUv }
        if ($old) { $old.Dispose() }
    }
    $script:piId = [SkinArt]::Load((Join-Path $script:piDir ('id-{0}.png' -f $script:piView)))
    $script:piUv = [SkinArt]::Load((Join-Path $script:piDir ('uv-{0}.png' -f $script:piView)))
    $prev = $script:piPic.Image
    $script:piPic.Image = [SkinArt]::Load((Join-Path $script:piDir ('id-{0}.png' -f $script:piView)))
    if ($prev) { $prev.Dispose() }
}

function Show-PaintId {
    if (-not $script:CurSkin) { Set-Status 'Open a skin first.'; return }
    $gltf = Find-SkinGltf
    if (-not $gltf) {
        [void][System.Windows.Forms.MessageBox]::Show((@(
            'This needs the skin''s mesh, which comes from the one-off FModel export.'
            ''
            'Click OPEN IN BLENDER once for this skin - that walks you through the export - then come back.'
        ) -join "`r`n"), 'Skin Studio')
        return
    }
    $frm.Cursor = 'WaitCursor'
    try {
        $script:piDir = SS-EnsurePaintId $script:CurSkin $gltf { param($m) Set-Status $m }
        $script:piLegend = Get-Content -LiteralPath (Join-Path $script:piDir 'legend.json') -Raw | ConvertFrom-Json
        $mt = SS-EnsureMatTextures $script:CurSkin { param($m) Set-Status $m }
        $script:piMatTex = Get-Content -LiteralPath $mt -Raw | ConvertFrom-Json
        $cj = SS-EnsureColorCache $script:CurSkin { param($m) Set-Status $m } $pump 'mat'
        $script:piColors = Get-Content -LiteralPath $cj -Raw | ConvertFrom-Json
    } catch {
        $frm.Cursor = 'Default'
        [void][System.Windows.Forms.MessageBox]::Show(("Could not build the model trace:`r`n`r`n" + $_.Exception.Message), 'Skin Studio')
        return
    } finally { $frm.Cursor = 'Default' }

    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'What paints this?'
    $f.ClientSize = New-Object System.Drawing.Size(1010, 744)
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.StartPosition = 'CenterParent'

    $f.Controls.Add((New-Lbl 'THE MODEL' 16 10 200))
    $f.Controls.Add((New-Lbl 'Click any part. Colours here are one per material, not the real skin.' 16 700 440))
    $script:piPic = New-Object System.Windows.Forms.PictureBox
    $script:piPic.Location = New-Object System.Drawing.Point(16, 32)
    $script:piPic.Size = New-Object System.Drawing.Size(450, 660)
    $script:piPic.SizeMode = 'Zoom'; $script:piPic.BackColor = $Pal.Sink; $script:piPic.BorderStyle = 'None'
    $script:piPic.Cursor = [System.Windows.Forms.Cursors]::Cross
    $f.Controls.Add($script:piPic)

    $btnFront = New-Btn 'front' 300 8 80 24
    $btnBack = New-Btn 'back' 386 8 80 24
    $f.Controls.Add($btnFront); $f.Controls.Add($btnBack)
    $btnFront.Add_Click({ $script:piView = 'front'; Update-PaintIdView })
    $btnBack.Add_Click({ $script:piView = 'back'; Update-PaintIdView })

    $f.Controls.Add((New-Lbl 'MATERIAL' 486 10 300))
    # a Label, not a RichTextBox: it is three lines of read-only text, it wraps,
    # it takes the palette without a bright native scrollbar, and unlike a
    # RichTextBox it actually renders under DrawToBitmap (which is how this
    # dialog gets layout-checked without opening a window)
    $script:piOut = New-Object System.Windows.Forms.Label
    $script:piOut.Location = New-Object System.Drawing.Point(486, 32)
    $script:piOut.Size = New-Object System.Drawing.Size(508, 86)
    $script:piOut.AutoSize = $false
    $script:piOut.BackColor = [System.Drawing.Color]::Transparent
    $script:piOut.ForeColor = $Pal.Text
    $script:piOut.Font = UIFont 9
    $script:piOut.Text = 'Click a part of the model on the left.'
    $f.Controls.Add($script:piOut)

    # ---- the material's colour parameters, each one a row you can jump to ----
    $f.Controls.Add((New-Lbl 'COLOUR PARAMETERS' 486 126 300))
    $script:piParamImgs = New-Object System.Windows.Forms.ImageList
    $script:piParamImgs.ImageSize = New-Object System.Drawing.Size(16, 16)
    $script:piParamImgs.ColorDepth = 'Depth32Bit'
    $script:piParams = New-Object System.Windows.Forms.ListView
    $script:piParams.Location = New-Object System.Drawing.Point(486, 148)
    $script:piParams.Size = New-Object System.Drawing.Size(508, 140)
    $script:piParams.View = 'Details'; $script:piParams.FullRowSelect = $true
    $script:piParams.HideSelection = $false; $script:piParams.MultiSelect = $false
    $script:piParams.SmallImageList = $script:piParamImgs
    [void]$script:piParams.Columns.Add('', 26)
    [void]$script:piParams.Columns.Add('parameter', 176)
    [void]$script:piParams.Columns.Add('colour', 80)
    [void]$script:piParams.Columns.Add('copy', 84)
    [void]$script:piParams.Columns.Add('', 120)
    $f.Controls.Add($script:piParams)
    $btnGoParam = New-Btn 'open this colour in Materials' 486 294 250 28
    $f.Controls.Add($btnGoParam)
    $f.Controls.Add((New-Lbl 'A tint here multiplies the texture - it wins.' 744 298 250))

    # ---- every texture the material binds ----
    $f.Controls.Add((New-Lbl 'TEXTURES IT USES' 486 332 300))
    $script:piTexList = New-Object System.Windows.Forms.ListView
    $script:piTexList.Location = New-Object System.Drawing.Point(486, 354)
    $script:piTexList.Size = New-Object System.Drawing.Size(508, 150)
    $script:piTexList.View = 'Details'; $script:piTexList.FullRowSelect = $true
    $script:piTexList.HideSelection = $false; $script:piTexList.MultiSelect = $false
    [void]$script:piTexList.Columns.Add('texture', 258)
    [void]$script:piTexList.Columns.Add('role', 110)
    [void]$script:piTexList.Columns.Add('', 124)
    $f.Controls.Add($script:piTexList)
    $btnGoTex = New-Btn 'select this texture in the browser' 486 510 250 28
    $f.Controls.Add($btnGoTex)

    $f.Controls.Add((New-Lbl 'THAT SPOT ON THE ATLAS' 486 548 300))
    $script:piCrop = New-Object System.Windows.Forms.PictureBox
    $script:piCrop.Location = New-Object System.Drawing.Point(486, 570)
    $script:piCrop.Size = New-Object System.Drawing.Size(110, 110)
    $script:piCrop.SizeMode = 'Zoom'; $script:piCrop.BackColor = $Pal.Sink; $script:piCrop.BorderStyle = 'None'
    $f.Controls.Add($script:piCrop)
    $script:piCoord = New-Lbl '' 606 570 388
    $script:piCoord.Size = New-Object System.Drawing.Size(388, 110)
    $f.Controls.Add($script:piCoord)

    # jumping closes the dialog on purpose - you asked to be taken somewhere
    $btnGoParam.Add_Click({
        if ($script:piParams.SelectedItems.Count -eq 0) { Set-Status 'Pick a colour parameter first.'; return }
        $t = $script:piParams.SelectedItems[0].Tag
        if (-not $t) { return }
        $this.FindForm().Close()
        if (-not (Select-ColorItemBy $t.Asset $t.Name $t.Export $t.Ordinal)) {
            Set-Status ('{0} is not in the Materials list - it may be a shading parameter the studio does not edit.' -f $t.Name)
        }
    })
    $btnGoTex.Add_Click({
        if ($script:piTexList.SelectedItems.Count -eq 0) { Set-Status 'Pick a texture first.'; return }
        $leaf = [string]$script:piTexList.SelectedItems[0].Tag
        if (-not $leaf) { return }
        $tex = @($script:TexItems | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.Rel) -eq $leaf })[0]
        if (-not $tex -or -not $tex.Item) { Set-Status ('{0} is shared game-wide - it is not part of this skin, so the studio cannot edit it.' -f $leaf); return }
        $this.FindForm().Close()
        Set-Mode 'tex'
        $lvTex.SelectedItems.Clear()
        $tex.Item.Selected = $true; $tex.Item.EnsureVisible(); $lvTex.Select()
    })
    $script:piParams.Add_DoubleClick({ $btnGoParam.PerformClick() })
    $script:piTexList.Add_DoubleClick({ $btnGoTex.PerformClick() })

    $script:piPic.Add_MouseDown({
        param($s, $e)
        if (-not $script:piId) { return }
        $iw = $script:piId.Width; $ih = $script:piId.Height
        $sc = [Math]::Min($s.Width / [double]$iw, $s.Height / [double]$ih)
        $ox = ($s.Width - $iw * $sc) / 2.0; $oy = ($s.Height - $ih * $sc) / 2.0
        $ix = [int](($e.X - $ox) / $sc); $iy = [int](($e.Y - $oy) / $sc)
        if ($ix -lt 0 -or $iy -lt 0 -or $ix -ge $iw -or $iy -ge $ih) { return }
        Report-PaintId $ix $iy
    })

    $close = New-Btn 'Close' 886 704 108 30
    $close.DialogResult = 'Cancel'; $f.Controls.Add($close)
    $f.CancelButton = $close

    DressDialog $f | Out-Null
    Update-PaintIdView
    # layout check without putting a window on anyone's screen: build it, fill
    # it in, draw it to a file, close. Set RS_SS_PAINTIDSHOT=<png>.
    if ($env:RS_SS_PAINTIDSHOT) {
        $f.CreateControl()
        foreach ($c in @($f.Controls)) { try { [void]$c.Handle } catch {} }
        $hit = @($script:TexItems | Where-Object { $true })  # keep the pipeline warm
        if ($script:piId) {
            # click the first non-background pixel we can find, so the lists fill
            :found for ($y = 0; $y -lt $script:piId.Height; $y += 3) {
                for ($x = 0; $x -lt $script:piId.Width; $x += 3) {
                    $p = $script:piId.GetPixel($x, $y)
                    if ($p.R -gt 4 -or $p.G -gt 4 -or $p.B -gt 4) { Report-PaintId $x $y; break found }
                }
            }
        }
        [System.Windows.Forms.Application]::DoEvents()
        $bmp = New-Object System.Drawing.Bitmap($f.Width, $f.Height)
        $f.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $f.Width, $f.Height)))
        $bmp.Save($env:RS_SS_PAINTIDSHOT, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Write-Host ("PAINTIDSHOT wrote " + $env:RS_SS_PAINTIDSHOT)
        $f.Dispose()
        return
    }
    [void]$f.ShowDialog($frm)
    foreach ($b in @($script:piId, $script:piUv)) { if ($b) { $b.Dispose() } }
    if ($script:piPic.Image) { $script:piPic.Image.Dispose() }
    if ($script:piCrop.Image) { $script:piCrop.Image.Dispose() }
    $script:piId = $null; $script:piUv = $null
    $f.Dispose()
}

# Take the Materials list to one exact colour parameter: switch to that browse
# mode, find the row (asset + parameter + export/ordinal, because one material
# can carry the same parameter name more than once) and select it so the op
# panel is already pointed at it.
function Select-ColorItemBy([string]$assetLeaf, [string]$paramName, [int]$export, [int]$ordinal) {
    Set-Mode 'mat'
    $hit = @($script:ColorItems | Where-Object {
        ([IO.Path]::GetFileNameWithoutExtension($_.Rel) -eq $assetLeaf) -and
        ($_.Name -eq $paramName) -and ($_.Export -eq $export) -and ($_.Ordinal -eq $ordinal)
    })[0]
    if (-not $hit) {
        # fall back to any parameter of that name on that material
        $hit = @($script:ColorItems | Where-Object {
            ([IO.Path]::GetFileNameWithoutExtension($_.Rel) -eq $assetLeaf) -and ($_.Name -eq $paramName)
        })[0]
    }
    if (-not $hit -or -not $hit.Item) { return $false }
    $lvColors.SelectedItems.Clear()
    $hit.Item.Selected = $true
    $hit.Item.EnsureVisible()
    $lvColors.Select()
    $script:SelColor = $hit
    Show-ColorSel
    Set-Status ('{0} - {1} on {2}. Pick a new colour and APPLY COLOR.' -f $hit.Mat, $hit.Name, $hit.Role)
    return $true
}

function Report-PaintId([int]$ix, [int]$iy) {
    $script:piParams.Items.Clear(); $script:piParamImgs.Images.Clear()
    $script:piTexList.Items.Clear()
    $script:piCoord.Text = ''
    $c = $script:piId.GetPixel($ix, $iy)
    if ($c.R -lt 4 -and $c.G -lt 4 -and $c.B -lt 4) {
        $script:piOut.Text = 'That is the background - click on the model.'
        return
    }
    # legend holds LINEAR values; the render is sRGB. Convert before matching or
    # every distance is wrong by the same misleading amount.
    $best = $null; $bd = [double]::MaxValue
    foreach ($m in $script:piLegend.PSObject.Properties) {
        $v = $m.Value
        $d = [Math]::Pow((PiToSrgb $v[0]) - $c.R, 2) + [Math]::Pow((PiToSrgb $v[1]) - $c.G, 2) + [Math]::Pow((PiToSrgb $v[2]) - $c.B, 2)
        if ($d -lt $bd) { $bd = $d; $best = $m.Name }
    }
    if (-not $best -or [Math]::Sqrt($bd) -gt 24) {
        $script:piOut.Text = 'Could not pin that pixel to a material - try clicking well inside a part.'
        return
    }
    $uvc = $script:piUv.GetPixel($ix, $iy)
    $u = PiFromSrgb $uvc.R; $v2 = PiFromSrgb $uvc.G

    # the mesh names materials with and without the chunk prefix; try both
    $key = $best
    $entry = $script:piMatTex.PSObject.Properties[$key]
    if (-not $entry) {
        $alt = @($script:piMatTex.PSObject.Properties | Where-Object { $_.Name -like "*$($best -replace '^MI_', '')" } | Select-Object -First 1)
        if ($alt) { $entry = $alt[0]; $key = $alt[0].Name }
    }

    # ---- colour parameters, one row per parameter per copy of the material ----
    $nOver = 0
    foreach ($a in $script:piColors) {
        $an = if ($a.PSObject.Properties['asset']) { [string]$a.asset } else { [string]$a.rel }
        if ([IO.Path]::GetFileNameWithoutExtension($an) -ne $key) { continue }
        $where = if ($an -match '[/\\]Lobby[/\\]') { 'lobby' } else { 'in-match' }
        foreach ($cp in $a.colors) {
            if ([string]$cp.kind -eq 'curve') { continue }
            if ([string]$cp.name -like 'MC_*') { continue }     # the stock shading ramp, never white, never interesting
            $rgbv = [SkinArt]::LinearToHex([double]$cp.r, [double]$cp.g, [double]$cp.b)
            $hex = '#{0:X2}{1:X2}{2:X2}' -f $rgbv[0], $rgbv[1], $rgbv[2]
            $isOver = PiIsOverride $cp
            if ($isOver) { $nOver++ }
            $chip = New-Object System.Drawing.Bitmap(16, 16)
            $g = [System.Drawing.Graphics]::FromImage($chip)
            $br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, $rgbv[0], $rgbv[1], $rgbv[2]))
            $g.FillRectangle($br, 0, 0, 16, 16); $br.Dispose()
            $pn = New-Object System.Drawing.Pen($Pal.Line, 1); $g.DrawRectangle($pn, 0, 0, 15, 15); $pn.Dispose()
            $g.Dispose()
            [void]$script:piParamImgs.Images.Add($chip); $chip.Dispose()
            $it = New-Object System.Windows.Forms.ListViewItem
            $it.ImageIndex = $script:piParamImgs.Images.Count - 1
            $it.Text = ''
            [void]$it.SubItems.Add([string]$cp.name)
            [void]$it.SubItems.Add($hex)
            [void]$it.SubItems.Add($where)
            [void]$it.SubItems.Add($(if ($isOver) { 'tints the texture' } else { '' }))
            if ($isOver) { $it.ForeColor = $Pal.Amber }
            $it.Tag = [pscustomobject]@{ Asset = $key; Name = [string]$cp.name; Export = [int]$cp.export; Ordinal = [int]$cp.ordinal }
            [void]$script:piParams.Items.Add($it)
        }
    }

    # ---- textures ----
    $script:piHitTex = $null
    if ($entry) {
        $ops = Get-Ops
        foreach ($t in @($entry.Value.textures)) {
            $tex = @($script:TexItems | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.Rel) -eq $t })[0]
            $it = New-Object System.Windows.Forms.ListViewItem($t)
            [void]$it.SubItems.Add((PiTexKind $t))
            if (-not $tex) {
                [void]$it.SubItems.Add('shared, not in this skin')
                $it.ForeColor = $Pal.Faint
            } else {
                $edited = $ops.ContainsKey($tex.Rel)
                [void]$it.SubItems.Add($(if ($edited) { 'you edited this' } else { '' }))
                if ($edited) { $it.ForeColor = $colPink }
                $it.Tag = $t
                if (-not $script:piHitTex -and $t -match '_D$') { $script:piHitTex = $t }
            }
            [void]$script:piTexList.Items.Add($it)
        }
    }

    $verdict = if ($nOver -gt 0) {
        "{0} colour parameter(s) below are NOT white, so they multiply the texture.`r`nRepainting the maps alone will not move this part - change the tint, and change every copy listed (in-match AND lobby)." -f $nOver
    } else {
        'Every colour parameter is white, so this part takes its colour straight from the textures below.'
    }
    $script:piOut.Text = ($key + "`r`n`r`n" + $verdict)

    # ---- where on the atlas ----
    $lines = @(('u {0:N3}   v {1:N3}' -f $u, $v2))
    if ($script:piHitTex) {
        $tex = @($script:TexItems | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.Rel) -eq $script:piHitTex })[0]
        if ($tex) {
            $dim = 2048
            if ($tex.Dims -match '^(\d+)x') { $dim = [int]$matches[1] }
            # V is flipped relative to image rows
            $lines += ('{0}, {1} px of {2}' -f [int]($u * $dim), [int]((1.0 - $v2) * $dim), $tex.Dims)
            $lines += $script:piHitTex
            try {
                $src = [SkinArt]::Load($tex.Png)
                $half = [Math]::Max(24, [int]($src.Width / 12))
                $x0 = [Math]::Max(0, [Math]::Min($src.Width - 1, [int]($u * $src.Width) - $half))
                $y0 = [Math]::Max(0, [Math]::Min($src.Height - 1, [int]((1.0 - $v2) * $src.Height) - $half))
                $w = [Math]::Min($half * 2, $src.Width - $x0); $h = [Math]::Min($half * 2, $src.Height - $y0)
                $crop = New-Object System.Drawing.Bitmap($w, $h)
                $g = [System.Drawing.Graphics]::FromImage($crop)
                $g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)), $x0, $y0, $w, $h, 'Pixel')
                $g.Dispose(); $src.Dispose()
                $old = $script:piCrop.Image
                $script:piCrop.Image = $crop
                if ($old) { $old.Dispose() }
            } catch {}
        }
    }
    $script:piCoord.Text = ($lines -join "`r`n")
}


# ---- the colour-family picker -----------------------------------------------
# "Recolor color family" moves ONE hue band and leaves the rest alone. Which
# band was, until now, always auto-detected from the whole image - fine for a
# texture with one obvious subject, useless on a shared atlas where a cap,
# badges, a red top, a tie and headphones share one sheet and you want only the
# magenta.
#
# This picks it by hand. The left pane is the texture with everything OUTSIDE
# the band dropped to grey, so the selection is literally what you see; click it
# to set the band from a pixel you want. The strip and the sliders set it by
# number. SkinArt.BandPreview does the masking with the same feathered weight the
# real op uses, so the preview cannot drift from the result.
#
# Plain script blocks and $script: state throughout - a .GetNewClosure() handler
# cannot reach script-scope functions, which is what silently broke every button
# in the corner-art editor once.
$script:bpImg = $null; $script:bpCenter = 0.0; $script:bpHalf = 34.0; $script:bpAuto = $true
$script:bpPic = $null; $script:bpStrip = $null; $script:bpCov = $null
$script:bpSlC = $null; $script:bpSlW = $null; $script:bpChk = $null; $script:bpLblC = $null

# the strip is click-and-drag; a script-level function, not a local script block
# captured by the handlers - that only works while the modal is still on the
# stack, and quietly stops working the moment anything reuses it
function Set-BandFromStripX([int]$x) {
    $script:bpAuto = $false
    $script:bpChk.Checked = $false
    $script:bpCenter = [Math]::Max(0.0, [Math]::Min(359.9, 360.0 * $x / [double]$script:bpStrip.Width))
    $script:bpSlC.Value = [int]$script:bpCenter
    Update-BandPreview
}
function Update-BandPreview {
    if (-not $script:bpImg) { return }
    $c = if ($script:bpAuto) { [SkinArt]::AutoBandCenter($script:bpImg) } else { $script:bpCenter }
    if ($c -lt 0) { $c = 0 }
    # keep the slider showing where the band actually is, even while auto owns it
    if ($script:bpAuto -and $script:bpSlC) { $script:bpSlC.Value = [Math]::Max(0, [Math]::Min(359, [int]$c)) }
    $old = $script:bpPic.Image
    $script:bpPic.Image = [SkinArt]::BandPreview($script:bpImg, $c, $script:bpHalf)
    if ($old) { $old.Dispose() }
    $script:bpCov.Text = 'selects {0:P0} of this texture' -f [SkinArt]::LastCoverage
    $script:bpLblC.Text = if ($script:bpAuto) { 'Centre: {0:N0}°  (detected)' -f $c } else { 'Centre: {0:N0}°' -f $c }
    $script:bpStrip.Invalidate()
}

function Show-BandPicker {
    if (-not $script:SelTex) { return $false }
    $pv = Ensure-Preview $script:SelTex
    $script:bpImg = [SkinArt]::Load($pv)
    $script:bpAuto = ($script:BandCenter -lt 0)
    $script:bpCenter = if ($script:bpAuto) { 0.0 } else { [double]$script:BandCenter }
    $script:bpHalf = if ($script:BandWidth -gt 0) { [double]$script:BandWidth } else { 34.0 }

    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Color family'
    $f.ClientSize = New-Object System.Drawing.Size(726, 486)
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.StartPosition = 'CenterParent'

    $f.Controls.Add((New-Lbl 'IN THE BAND' 16 10 200))
    $hint = New-Lbl 'Everything grey is left alone. Click the picture to take the band from a pixel you want.' 16 382 694
    $f.Controls.Add($hint)
    $script:bpPic = New-Object System.Windows.Forms.PictureBox
    $script:bpPic.Location = New-Object System.Drawing.Point(16, 32)
    $script:bpPic.Size = New-Object System.Drawing.Size(346, 346)
    $script:bpPic.SizeMode = 'Zoom'; $script:bpPic.BackColor = $Pal.Sink; $script:bpPic.BorderStyle = 'None'
    $script:bpPic.Cursor = [System.Windows.Forms.Cursors]::Cross
    $f.Controls.Add($script:bpPic)

    $f.Controls.Add((New-Lbl 'HUE BAND' 386 10 200))
    $script:bpStrip = New-Object System.Windows.Forms.Panel
    $script:bpStrip.Location = New-Object System.Drawing.Point(386, 32)
    $script:bpStrip.Size = New-Object System.Drawing.Size(324, 44)
    $script:bpStrip.Cursor = [System.Windows.Forms.Cursors]::Hand
    $f.Controls.Add($script:bpStrip)
    DoubleBuffer $script:bpStrip
    $script:bpStrip.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        # the spectrum, one column per pixel
        for ($x = 0; $x -lt $s.Width; $x++) {
            $h = 360.0 * $x / [double]$s.Width
            $c = HsvToColor $h 0.9 0.95      # HsvToColor, from vuistyle - there is no HslToColor here
            $pn = New-Object System.Drawing.Pen($c, 1)
            $g.DrawLine($pn, $x, 0, $x, ($s.Height - 12)); $pn.Dispose()
        }
        # the band, drawn as a bracket - it wraps, so draw it as up to two spans
        $cen = if ($script:bpAuto) { [SkinArt]::AutoBandCenter($script:bpImg) } else { $script:bpCenter }
        if ($cen -lt 0) { $cen = 0 }
        $half = $script:bpHalf + [Math]::Max(4.0, $script:bpHalf * 0.38)   # include the feather
        $sc = $s.Width / 360.0
        $br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70, 255, 255, 255))
        foreach ($off in @(-360.0, 0.0, 360.0)) {
            $x0 = ($cen + $off - $half) * $sc; $x1 = ($cen + $off + $half) * $sc
            if ($x1 -lt 0 -or $x0 -gt $s.Width) { continue }
            $g.FillRectangle($br, [single]$x0, 0.0, [single]($x1 - $x0), [single]($s.Height - 12))
        }
        $br.Dispose()
        $pn2 = New-Object System.Drawing.Pen($Pal.Text, 2)
        $cx = [single]($cen * $sc)
        $g.DrawLine($pn2, $cx, 0.0, $cx, [single]($s.Height - 12)); $pn2.Dispose()
        $tb = New-Object System.Drawing.SolidBrush($Pal.Muted)
        $fn = UIFont 7
        foreach ($d in @(0, 60, 120, 180, 240, 300)) {
            $g.DrawString(([string]$d), $fn, $tb, [single]($d * $sc), [single]($s.Height - 12))
        }
        $fn.Dispose(); $tb.Dispose()
    })
    $script:bpStrip.Add_MouseDown({ param($s, $e) Set-BandFromStripX $e.X })
    $script:bpStrip.Add_MouseMove({ param($s, $e) if ($e.Button -eq 'Left') { Set-BandFromStripX $e.X } })

    $script:bpChk = New-Object System.Windows.Forms.CheckBox
    $script:bpChk.Text = 'Detect the family automatically'
    $script:bpChk.Location = New-Object System.Drawing.Point(386, 88)
    $script:bpChk.Size = New-Object System.Drawing.Size(324, 20)
    $script:bpChk.Checked = $script:bpAuto
    $f.Controls.Add($script:bpChk)
    $script:bpChk.Add_CheckedChanged({
        $script:bpAuto = $script:bpChk.Checked
        $script:bpSlC.Enabled = -not $script:bpAuto
        if ($script:bpAuto) {
            $a = [SkinArt]::AutoBandCenter($script:bpImg)
            if ($a -ge 0) { $script:bpCenter = $a; $script:bpSlC.Value = [int]$a }
        }
        Update-BandPreview
    })

    $script:bpLblC = New-Lbl 'Centre' 386 116 324
    $f.Controls.Add($script:bpLblC)
    $script:bpSlC = AddSlider $f 382 136 328 0 359 ([int]$script:bpCenter)
    $script:bpSlC.Enabled = -not $script:bpAuto
    $script:bpSlC.Add_ValueChanged({
        if ($script:bpAuto) { return }
        $script:bpCenter = [double]$script:bpSlC.Value
        Update-BandPreview
    })

    $lblW = New-Lbl 'Width' 386 176 324
    $f.Controls.Add($lblW)
    $script:bpSlW = AddSlider $f 382 196 328 5 90 ([int]$script:bpHalf)
    $script:bpSlW.Add_ValueChanged({
        $script:bpHalf = [double]$script:bpSlW.Value
        $lblW.Text = 'Width: ±{0:N0}°  - wider takes in more neighbouring hues' -f $script:bpHalf
        Update-BandPreview
    })
    $lblW.Text = 'Width: ±{0:N0}°  - wider takes in more neighbouring hues' -f $script:bpHalf

    $script:bpCov = New-Lbl '' 386 238 324
    $script:bpCov.ForeColor = $Pal.SageLt
    $f.Controls.Add($script:bpCov)

    $btnAuto = New-Btn 'detect again' 386 266 140 28
    $f.Controls.Add($btnAuto)
    $btnAuto.Add_Click({
        $a = [SkinArt]::AutoBandCenter($script:bpImg)
        if ($a -lt 0) { return }
        $script:bpAuto = $false; $script:bpChk.Checked = $false
        $script:bpCenter = $a; $script:bpSlC.Value = [int]$a
        Update-BandPreview
    })
    $f.Controls.Add((New-Lbl 'Picks the dominant saturated hue, then lets you nudge it.' 386 298 324))

    # click the picture to take the band centre from that pixel
    $script:bpPic.Add_MouseDown({
        param($s, $e)
        if (-not $script:bpImg) { return }
        # SizeMode=Zoom letterboxes: undo the fit to get image coordinates
        $iw = $script:bpImg.Width; $ih = $script:bpImg.Height
        $sc = [Math]::Min($s.Width / [double]$iw, $s.Height / [double]$ih)
        $dw = $iw * $sc; $dh = $ih * $sc
        $ox = ($s.Width - $dw) / 2.0; $oy = ($s.Height - $dh) / 2.0
        $ix = [int](($e.X - $ox) / $sc); $iy = [int](($e.Y - $oy) / $sc)
        if ($ix -lt 0 -or $iy -lt 0 -or $ix -ge $iw -or $iy -ge $ih) { return }
        $px = $script:bpImg.GetPixel($ix, $iy)
        if ($px.GetSaturation() -lt 0.06) {
            $script:bpCov.Text = 'that pixel is grey - it has no hue to aim at'
            return
        }
        $script:bpAuto = $false; $script:bpChk.Checked = $false
        $script:bpCenter = [double]$px.GetHue()
        $script:bpSlC.Value = [int]$script:bpCenter
        Update-BandPreview
    })

    $ok = MakePrimary (New-Btn 'USE THIS BAND' 452 442 140 30)
    $ok.DialogResult = 'OK'; $f.Controls.Add($ok)
    $cancel = New-Btn 'Cancel' 602 442 108 30
    $cancel.DialogResult = 'Cancel'; $f.Controls.Add($cancel)
    $f.AcceptButton = $ok; $f.CancelButton = $cancel

    DressDialog $f | Out-Null
    Update-BandPreview
    $res = $f.ShowDialog($frm)
    $changed = $false
    if ($res -eq 'OK') {
        $script:BandCenter = if ($script:bpAuto) { -1.0 } else { $script:bpCenter }
        $script:BandWidth = $script:bpHalf
        Update-BandButton
        $changed = $true
    }
    if ($script:bpPic.Image) { $script:bpPic.Image.Dispose(); $script:bpPic.Image = $null }
    $script:bpImg.Dispose(); $script:bpImg = $null
    $f.Dispose()
    return $changed
}

function Ensure-Preview($tex) {
    # 512px preview base, built lazily per texture
    $pv = Join-Path $script:CurCk ('pv\{0}.png' -f $tex.ImgIdx)
    if (-not (Test-Path -LiteralPath $pv)) { [SkinArt]::Thumb($tex.Png, $pv, 512) }
    $pv
}
function Get-CurStack {
    # committed layer stack for the selected texture (always an array).
    # The leading comma matters: PowerShell unrolls a returned array, so a
    # ONE-layer stack used to come back as the bare layer hashtable - .Count was
    # its number of settings (7+), $stack[0] was $null, and "+ add" died with
    # "A hash table can only be added to another hash table". That is why a
    # second layer could never be added.
    if (-not $script:SelTex) { return ,@() }
    $ops = Get-Ops
    if ($ops.ContainsKey($script:SelTex.Rel)) { return ,@($ops[$script:SelTex.Rel]) }
    ,@()
}
function Get-PreviewStack {
    # what the MODIFIED pane should show: the committed stack with the panel op
    # either replacing the layer being edited or appended as a draft layer
    $stack = Get-CurStack
    $panelOp = Get-PanelOp
    if ($script:EditLayerIdx -ge 0 -and $script:EditLayerIdx -lt $stack.Count) {
        $out = @()
        for ($i = 0; $i -lt $stack.Count; $i++) {
            if ($i -eq $script:EditLayerIdx) { if ($panelOp) { $out += ,$panelOp } }
            else { $out += ,$stack[$i] }
        }
        return ,$out
    }
    if ($panelOp) { return ,($stack + ,$panelOp) }
    ,$stack
}
function Refresh-Layers {
    $lstLayers.BeginUpdate(); $lstLayers.Items.Clear()
    $stack = Get-CurStack
    for ($i = 0; $i -lt $stack.Count; $i++) {
        [void]$lstLayers.Items.Add(('{0}.  {1}' -f ($i + 1), (SS-OpLabel $stack[$i])))
    }
    $lstLayers.EndUpdate()
    if ($script:EditLayerIdx -ge 0 -and $script:EditLayerIdx -lt $lstLayers.Items.Count) {
        $lstLayers.SelectedIndex = $script:EditLayerIdx
    }
    $panelOp = Get-PanelOp
    if ($script:EditLayerIdx -ge 0) { $lblDraft.Text = ('editing layer {0} - "update layer" saves changes. Click it again to stop editing and draft a new layer.' -f ($script:EditLayerIdx + 1)) }
    elseif ($panelOp) { $lblDraft.Text = 'panel = NEW layer draft, previewed on top (not saved) - use "+ add"' }
    elseif ($stack.Count -gt 0) { $lblDraft.Text = 'set up the panel to draft another layer on top, or click a layer to edit it' }
    else { $lblDraft.Text = '' }
}
function Show-Preview {
    $script:PvTimer.Stop()   # coalesce any pending debounced refresh into this one
    $picVan.Image = $null; $picMod.Image = $null
    foreach ($old in $script:PvImgs) { try { $old.Dispose() } catch {} }
    $script:PvImgs = @()
    if (-not $script:SelTex) { Refresh-Layers; return }
    $pv = Ensure-Preview $script:SelTex
    $vanImg = [SkinArt]::Load($pv)
    $picVan.Image = $vanImg; $script:PvImgs += $vanImg
    $stack = Get-PreviewStack
    if ($stack.Count -gt 0) {
        try {
            # rendered fully in memory - no temp-PNG roundtrip per layer
            $modImg = SS-RenderStack $pv $stack
            $picMod.Image = $modImg; $script:PvImgs += $modImg
        } catch { $lblTechWarn.Text = 'preview failed: ' + $_.Exception.Message }
    } else {
        $modImg2 = [SkinArt]::Load($pv)
        $picMod.Image = $modImg2; $script:PvImgs += $modImg2
    }
    # the material Tint (BaseTint) edits of the materials that use this map -
    # set here or in game (F8 panel) - shown over it, as the game multiplies them
    $tint = Get-PreviewTint $script:SelTex
    if ($tint -and $picMod.Image) {
        try {
            $tImg = [SkinArt]::MultiplyLinear($picMod.Image, $tint[0], $tint[1], $tint[2])
            $picMod.Image = $tImg; $script:PvImgs += $tImg
        } catch {}
    }
    Refresh-Layers
}
# edit / vanilla BaseTint of the first material that binds this texture and has
# a Tint edit, or $null. Materials -> textures comes from the skin's cache.
$script:PvMatTex = @{}
function Get-PreviewTint($tex) {
    if (-not $tex -or -not $script:CurSkin) { return $null }
    $ops = Get-ColorOps
    if (-not $ops -or $ops.Count -eq 0) { return $null }
    $leaf = [IO.Path]::GetFileNameWithoutExtension([string]$tex.Rel)
    # only what is already cached: the preview redraws on every click and must
    # never extract anything (her report: "it freezes the app now"). One try per
    # skin - a skin without the caches just shows no tint.
    if (-not $script:PvMatTex.ContainsKey($script:CurSkin)) {
        $script:PvMatTex[$script:CurSkin] = $false
        try {
            $dir = Join-Path $SS_Cache $script:CurSkin
            $mtp = Join-Path $dir 'mat_textures.json'; $ccp = Join-Path $dir 'colors.json'
            if ((Test-Path -LiteralPath $mtp) -and (Test-Path -LiteralPath $ccp)) {
                $mt = Get-Content -LiteralPath $mtp -Raw | ConvertFrom-Json
                $parsed = Get-Content -LiteralPath $ccp -Raw | ConvertFrom-Json
                $van = @{}
                foreach ($m in @($parsed)) { $b = @($m.colors | Where-Object { $_.name -eq 'BaseTint' })[0]; if ($b) { $van[[string]$m.asset] = $b } }
                $script:PvMatTex[$script:CurSkin] = @{ Tex = $mt; Van = $van }
            }
        } catch {}
    }
    $c = $script:PvMatTex[$script:CurSkin]
    if (-not $c) { return $null }
    foreach ($rel in @($ops.Keys | Sort-Object { $_ -match '/Lobby/' })) {
        $mi = [IO.Path]::GetFileNameWithoutExtension([string]$rel)
        $entry = $c.Tex.PSObject.Properties[$mi]
        if (-not $entry -or @($entry.Value.textures) -notcontains $leaf) { continue }
        foreach ($e in $ops[$rel].Values) {
            if ([string]$e.name -ne 'BaseTint') { continue }
            $van = $c.Van[[string]$rel]
            $vr = if ($van) { [Math]::Max(0.001, [double]$van.r) } else { 1.0 }
            $vg = if ($van) { [Math]::Max(0.001, [double]$van.g) } else { 1.0 }
            $vb = if ($van) { [Math]::Max(0.001, [double]$van.b) } else { 1.0 }
            $fr = [double]$e.r / $vr; $fg = [double]$e.g / $vg; $fb = [double]$e.b / $vb
            # a Tint left at its own value changes nothing - look further
            if ([Math]::Abs($fr - 1) -lt 0.01 -and [Math]::Abs($fg - 1) -lt 0.01 -and [Math]::Abs($fb - 1) -lt 0.01) { continue }
            return @($fr, $fg, $fb)
        }
    }
    $null
}
$script:Loading = $false
function Refresh-OpPanelEnabled {
    $role = if ($script:SelTex) { $script:SelTex.Role } else { $null }
    $isTech = ($role -eq 'tech')
    $enabled = [bool]$script:SelTex
    if ($isTech -and -not $chkAdvanced.Checked) { $enabled = $false }
    foreach ($c in $grpOp.Controls) { $c.Enabled = $enabled }
    foreach ($c in $grpLayers.Controls) { $c.Enabled = $enabled }
    if ($isTech -and -not $chkAdvanced.Checked) {
        $lblTechWarn.Text = 'Technical map - tick the Advanced box under the texture list to edit it anyway.'
        $lblTechWarn.ForeColor = $Pal.Amber
        $lblTechWarn.Enabled = $true
    } elseif ($role -eq 'spec') {
        # not a warning - say what the map does, because it is the one people
        # hunt for when a part looks pearlescent/metallic and the _D looks plain
        $lblTechWarn.Text = 'Specular map: the TINT of the shine. A near-neutral _D plus a coloured _S is what reads as pearlescent in game - recolor both to move the whole look.'
        $lblTechWarn.ForeColor = $Pal.Muted
        $lblTechWarn.Enabled = $true
    } else { $lblTechWarn.Text = '' }
}
# ● = edited, ⇄ = this map exists more than once in this skin under another name
# (edit one and the others stay vanilla in game - see SS-LinkGroups)
function Tex-Label($tex, [bool]$isMod) {
    $s = [IO.Path]::GetFileNameWithoutExtension($tex.Rel)
    if ($isMod) { $s = "● $s" }
    if ($script:Links.ContainsKey($tex.Rel)) { $s = "$s ⇄" }
    $s
}
# colour + specular maps read as editable (bright); only the genuinely technical
# ones are dimmed, because those are the ones the Advanced box guards
function Tex-Fore($tex) {
    if ($tex.Role -eq 'tech') { $colDim } else { $colFore }
}
function Tex-Tip($tex) {
    $t = '{0}  ({1}, {2} map)' -f $tex.Rel, $tex.Dims, $tex.Role
    $lk = $script:Links[$tex.Rel]
    if ($lk) {
        $t += ("`r`n⇄ " + $(if ($lk.Sure) { 'same map as: ' } else { 'possibly the same map as: ' }) +
               (($lk.Others | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }) -join ', ') +
               "`r`n   edit one and the rest stay vanilla in game.")
    }
    $t
}
# Push whatever is now on $rel onto every map linked to it, so both halves of a
# transformed / alternate-costume skin change together. An empty stack means the
# texture was reverted, so its twins revert too. Layers are cloned rather than
# shared - two ops entries pointing at one hashtable would be a quiet aliasing
# bug the first time a layer is edited in place.
function Mirror-ToLinked([string]$rel, $stack, [switch]$SureOnly) {
    if (-not $SureOnly -and -not $chkLinked.Checked) { return 0 }
    $lk = $script:Links[$rel]
    if (-not $lk) { return 0 }
    if ($SureOnly -and -not $lk.Sure) { return 0 }
    $twins = $lk.Others
    $ops = Get-Ops
    $n = 0
    foreach ($t in $twins) {
        if (@($stack).Count -eq 0) {
            if ($ops.ContainsKey($t)) { $ops.Remove($t); $n++ }
        } else {
            # count only the ones this actually filled in - a category bulk
            # sweep already hit both halves, and reporting those as "carried
            # across" would be noise
            if (-not $ops.ContainsKey($t)) { $n++ }
            $copy = @()
            foreach ($layer in @($stack)) {
                $c = @{}; foreach ($k in $layer.Keys) { $c[$k] = $layer[$k] }
                $copy += ,$c
            }
            $ops[$t] = $copy
        }
        $tex = $script:TexItems | Where-Object { $_.Rel -eq $t } | Select-Object -First 1
        if ($tex) { Refresh-Thumb $tex }
    }
    $n
}
# ---- chroma (recolor) skins --------------------------------------------------
# A chroma is a recolour of the open costume sold under its own skin id, with its
# own copy of every map. Ops are stored per skin ($script:OpsBySkin) and every
# texture rel carries its skin id, so mirroring is just "translate the rel and
# write it into that skin's ops" - build_skin then groups the design's ops back
# by skin and ships them all in ONE mod.
function Set-ChromaBoxes([string]$sid) {
    $script:ChromaT = SS-ChromaTargets $sid { param($m) Set-Status $m }
    $script:ChromaRels = @{}
    $script:ChromaMaskRels = @{}
    foreach ($t in (@($script:ChromaT.Sure) + @($script:ChromaT.Maybe))) {
        $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $masks = @{}
        foreach ($ln in @($script:Map.skinLines[$t])) {
            # extra parens: a comma inside a method call binds as another argument
            $rel = ((((SS-ManifestRel $ln) -replace '\.uasset$', '.png')) -replace '/', '\')
            [void]$set.Add($rel)
            # the dye masks, looked up by leaf when a map is carried across
            $rLeaf = [IO.Path]::GetFileNameWithoutExtension($rel)
            if ($rLeaf -match '_ColorID$') { $masks[$rLeaf] = $rel }
        }
        $script:ChromaRels[$t] = $set
        $script:ChromaMaskRels[$t] = $masks
    }
    $nS = @($script:ChromaT.Sure).Count
    $nM = @($script:ChromaT.Maybe).Count
    $chkChroma.Visible = ($nS -gt 0)
    $btnDyeCal.Visible = ($nS -gt 0)
    if ($nS -gt 0) {
        $tt.SetToolTip($btnDyeCal, ("Measure the recolours' dyed parts against the costume in game." + [char]13 + [char]10 +
            "A dyed part renders ONE flat colour, sampled from that zone's average in the atlas - which holds more than you ever see, so it lands duller than the part does. This walks the fix: build a white 'meter', take three screenshots, and the difference is measured and saved into the design."))
    }
    $chkChroma.Text = if ($nS -eq 1) { 'also edit its 1 recolor' } else { 'also edit its {0} recolors' -f $nS }
    if ($nS -gt 0) {
        $tt.SetToolTip($chkChroma, ("Recolours (chromas) of this costume - the same art repainted, sold as their own skins:`r`n  " +
            ((@($script:ChromaT.Sure) | ForEach-Object { SkinLabel $_ }) -join "`r`n  ") +
            "`r`nTicked, your edits are carried onto their matching maps and all of it ships in ONE mod."))
    }
    $chkChromaMaybe.Visible = ($nM -gt 0)
    $chkChromaMaybe.Text = if ($nM -eq 1) { '+ 1 possible recolor' } else { '+ {0} possible recolors' -f $nM }
    if ($nM -gt 0) {
        $tt.SetToolTip($chkChromaMaybe, ("These share this costume's mesh and most technical maps, but they may be their own costume rather than a recolour of it (Jeff's Gwenpool shares the default's normals, for instance). Check them before ticking:`r`n  " +
            ((@($script:ChromaT.Maybe) | ForEach-Object { SkinLabel $_ }) -join "`r`n  ")))
    }
}
# the recolor skins edits should be carried onto right now
function Get-ChromaActive {
    # gate on the detected targets, NOT on .Visible: a control reports Visible
    # false while its form has never been shown (headless smoke), and the tick
    # boxes are only ever shown when the matching list is non-empty anyway
    $out = @()
    if ($script:ChromaT) {
        if ($chkChroma.Checked) { $out += @($script:ChromaT.Sure) }
        if ($chkChromaMaybe.Checked) { $out += @($script:ChromaT.Maybe) }
    }
    ,@($out | Sort-Object -Unique)
}
# Push a stack onto the same map of every active recolor skin. Layers are cloned,
# never shared (two ops entries on one hashtable would alias the first time a
# layer is edited in place - same rule as Mirror-ToLinked). Returns the number of
# recolor skins actually touched.
# Render the OPEN skin's finished art for one map and hand back the PNG. The
# recolor is COPIED onto the recolor skins rather than re-run on their own art:
# re-running lands on a different colour on every chroma (their base art differs,
# and their dye tints it again), while a copy makes them all show exactly the
# design. Re-rendered on every carry-across, so it can never go stale.
function Ensure-ChromaSourcePng([string]$rel, $stack) {
    if (@($stack).Count -eq 0 -or -not $script:CurCk) { return $null }
    $srcPng = Join-Path (Join-Path $script:CurCk 'png\src') $rel
    if (-not (Test-Path -LiteralPath $srcPng)) { return $null }
    $dir = Join-Path $SS_Root ('work\chroma\{0}' -f $script:CurSkin)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dst = Join-Path $dir ([IO.Path]::GetFileName($rel))
    try { SS-ApplyOp $srcPng $dst $stack } catch { return $null }
    $dst
}
# PROVEN IN GAME (probe build, 2026-09-18), so do not re-invent either of these:
#   * In a dyed zone the dye REPLACES the art. Blue Breezes shipped with flat
#     CYAN art and white dye rendered cyan skin and a WHITE outfit - the art
#     under the dye counts for nothing.
#   * Blacking the _ColorID mask does NOT switch dyeing off. Viridian Vibes
#     shipped with magenta art and a black mask rendered a magenta face and,
#     again, a WHITE outfit: black selects "no region", which paints white.
#     That white outfit is what she had been seeing all along.
# So the mask is left alone and the dye colours are what get aimed: the zones
# the mask dyes take the design's own colour, and everything the mask does not
# touch (skin, face, hands) shows the copied art exactly.
function Mirror-ToChromas([string]$rel, $stack) {
    $targets = Get-ChromaActive
    if (@($targets).Count -eq 0) { return 0 }
    $copyPng = if (@($stack).Count -gt 0) { Ensure-ChromaSourcePng $rel $stack } else { $null }
    # plain array, NO leading comma: ",@(...)" survives as an array INSIDE an
    # array when it is assigned directly, and then [0] is that inner array, not
    # the op - which silently wrote empty ops
    $copyOp = if ($copyPng) { @(@{ mode = 'replace'; file = $copyPng; strength = 1.0 }) } else { @() }
    $n = 0
    foreach ($t in $targets) {
        $tRel = SS-RelForSkin $rel $script:CurSkin $t
        $set = $script:ChromaRels[$t]
        if (-not $set -or -not $set.Contains($tRel)) { continue }   # that recolor has no such map
        if (-not $script:OpsBySkin.ContainsKey($t)) { $script:OpsBySkin[$t] = @{} }
        $ops = $script:OpsBySkin[$t]
        # its dye is told to paint the design's own colour over the masked zones
        [void](Mirror-DyeToChroma $t $tRel $(if ($copyOp) { $copyOp } else { @() }) $copyPng)
        $maskRel = Get-ChromaMaskRel $t $tRel
        if (@($stack).Count -eq 0) {
            if ($ops.ContainsKey($tRel)) { [void]$ops.Remove($tRel); $n++ }
            if ($maskRel -and $ops.ContainsKey($maskRel)) { [void]$ops.Remove($maskRel) }
            continue
        }
        if (-not $copyOp) { continue }
        $c = @{}; foreach ($k in @($copyOp)[0].Keys) { $c[$k] = @($copyOp)[0][$k] }
        $ops[$tRel] = ,$c
        if ($maskRel -and $ops.ContainsKey($maskRel)) { [void]$ops.Remove($maskRel) }   # never touch the mask
        $n++
    }
    $n
}
# the _ColorID map that dyes this texture on that recolor skin, if it ships one
function Get-ChromaMaskRel([string]$skin, [string]$texRel) {
    if (-not $script:ChromaMaskRels.ContainsKey($skin)) { return $null }
    $maskLeaf = ([IO.Path]::GetFileNameWithoutExtension($texRel) -replace '_D$', '_ColorID')
    if ($script:ChromaMaskRels[$skin].ContainsKey($maskLeaf)) { return $script:ChromaMaskRels[$skin][$maskLeaf] }
    $null
}
# Push (or pull back) the WHOLE current op set across the recolor skins. Ticking
# the box is a statement about the design, not just about the next edit, so it has
# to cover what is already edited - otherwise a design saved before this existed
# (or loaded from disk) would never reach its recolors.
# A recolor is a copy of the WHOLE costume, not just of the maps she edited.
# The two share far more than the edited ones - the face (Head_D), the eyes, and
# the _S speculars that carry the sheen's colour - and leaving those on the
# recolor's own art is what kept it looking different. So every colour map they
# share is carried across: her edit where she made one, the costume's vanilla art
# where she did not.
function Get-CostumeArtForChroma([string]$rel, $ops) {
    if ($ops.ContainsKey($rel)) { return Ensure-ChromaSourcePng $rel $ops[$rel] }
    $van = Join-Path (Join-Path $script:CurCk 'png\src') $rel
    if (Test-Path -LiteralPath $van) { return $van }
    $null
}
function Sync-ChromaOps {
    if (-not $script:CurSkin -or -not $script:ChromaT) { return 0 }
    $active = Get-ChromaActive
    $ops = Get-Ops
    $n = 0
    foreach ($t in (@($script:ChromaT.Sure) + @($script:ChromaT.Maybe) | Sort-Object -Unique)) {
        if (-not $script:OpsBySkin.ContainsKey($t)) { $script:OpsBySkin[$t] = @{} }
        $tOps = $script:OpsBySkin[$t]
        $on = ($active -contains $t)
        # every colour map the two share, not only the edited ones
        $rels = @($ops.Keys)
        if ($on) {
            # every map except the dye mask - NOT just _D/_E/_S. Colour hides in
            # other suffixes too: Blue Breezes tints its hair through Hair_AO
            # (avg #C36A82 against the costume's grey #393839), so leaving "AO"
            # out left that recolor with red hair. Maps whose bytes already match
            # are skipped: copying those changes nothing and only bloats the mod.
            $hashes = $null
            try { $hashes = SS-TextureHashes (@($script:CurSkin) + @($t)) } catch {}
            foreach ($tex in $script:TexItems) {
                if ($tex.Rel -match '_ColorID\.png$') { continue }
                if ($rels -contains $tex.Rel) { continue }
                if ($ops.ContainsKey($tex.Rel)) { $rels += $tex.Rel; continue }   # she edited it
                if ($hashes) {
                    $bLeaf = [IO.Path]::GetFileNameWithoutExtension($tex.Rel)
                    if (-not (SS-MapDiffers $hashes $bLeaf ($bLeaf.Replace($script:CurSkin, $t)))) { continue }
                }
                $rels += $tex.Rel
            }
        }
        foreach ($rel in $rels) {
            $tRel = SS-RelForSkin $rel $script:CurSkin $t
            $maskRel = Get-ChromaMaskRel $t $tRel
            if (-not $on) {
                [void](Mirror-DyeToChroma $t $tRel @() $null)      # take its dye colours back too
                if ($tOps.ContainsKey($tRel)) { [void]$tOps.Remove($tRel); $n++ }
                if ($maskRel -and $tOps.ContainsKey($maskRel)) { [void]$tOps.Remove($maskRel) }
                continue
            }
            $set = $script:ChromaRels[$t]
            if (-not $set -or -not $set.Contains($tRel)) { continue }
            $copyPng = Get-CostumeArtForChroma $rel $ops   # her edit, or the costume's vanilla art
            if (-not $copyPng) { continue }
            $copyOp = @(@{ mode = 'replace'; file = $copyPng; strength = 1.0 })
            [void](Mirror-DyeToChroma $t $tRel $copyOp $copyPng)   # dye paints the design's colour
            $c = @{}; foreach ($k in @($copyOp)[0].Keys) { $c[$k] = @($copyOp)[0][$k] }
            $tOps[$tRel] = ,$c
            if ($maskRel -and $tOps.ContainsKey($maskRel)) { [void]$tOps.Remove($maskRel) }   # never touch the mask
            $n++
        }
    }
    $n
}
# ---- a recolor skin's DYE colours -------------------------------------------
# Carrying the texture across is only half of it: a chroma's colour also comes
# from per-region dye colours in its materials (see SS-IsDyeColor). Those are
# read once per recolor skin and cached for the session - building them needs
# the material list and the colour dump, which are themselves cached on disk.
# Shape: @{ tex = @{ '<texture name>' = @(material leaf names) };
#           par = @{ '<material leaf name>' = @( @{ rel; params } ) } }
# Keyed by material LEAF NAME on both sides on purpose: mat_textures.json keys by
# name ("MI_1064301_Body") while colors.json keys by full rel
# ("Marvel/.../MI_1064301_Body.uasset"), and a skin usually ships the material
# TWICE (in-match + lobby) under one name - both need dyeing or the lobby model
# stays the old colour.
$script:ChromaDye = @{}
function Get-ChromaDye([string]$skin) {
    if ($script:ChromaDye.ContainsKey($skin)) { return $script:ChromaDye[$skin] }
    $out = @{ tex = @{}; par = @{} }
    try {
        Set-Status ("Reading {0}'s material colours (first time for this skin)..." -f (SkinLabel $skin))
        $mt = Get-Content -LiteralPath (SS-EnsureMatTextures $skin { param($m) Set-Status $m }) -Raw | ConvertFrom-Json
        $cj = Get-Content -LiteralPath (SS-EnsureColorCache $skin { param($m) Set-Status $m } $pump 'mat') -Raw | ConvertFrom-Json
        foreach ($a in $cj) {
            $keep = @()
            foreach ($c in $a.colors) {
                if ([string]$c.kind -eq 'curve') { continue }
                # a "Region N - Color*" IS a dye colour even when it is HDR - the
                # 0..1 gate is there for directions and packed triples, and using
                # it here is what left the bright accents at the recolor's colour
                if (-not (SS-IsRegionDye ([string]$c.name)) -and
                    -not (SS-ColorIsPickable ([string]$c.name) ([double]$c.r) ([double]$c.g) ([double]$c.b))) { continue }
                if (-not (SS-IsDyeColor ([double]$c.r) ([double]$c.g) ([double]$c.b))) { continue }
                $keep += ,([pscustomobject]@{ export = [int]$c.export; ordinal = [int]$c.ordinal; name = [string]$c.name; r = [double]$c.r; g = [double]$c.g; b = [double]$c.b })
            }
            if (-not $keep.Count) { continue }
            $leaf = [IO.Path]::GetFileNameWithoutExtension([string]$a.asset)
            if (-not $out.par.ContainsKey($leaf)) { $out.par[$leaf] = @() }
            $out.par[$leaf] += ,([pscustomobject]@{ rel = [string]$a.asset; params = $keep })
        }
        foreach ($p in $mt.PSObject.Properties) {
            $leaf = [IO.Path]::GetFileNameWithoutExtension([string]$p.Name)
            if (-not $out.par.ContainsKey($leaf)) { continue }        # this material has no dye
            foreach ($t in @($p.Value.textures)) {
                if (-not $out.tex.ContainsKey($t)) { $out.tex[$t] = @() }
                if ($out.tex[$t] -notcontains $leaf) { $out.tex[$t] += $leaf }
            }
        }
    } catch {
        Set-Status ("(could not read {0}'s material colours: {1})" -f $skin, $_.Exception.Message)
    }
    $script:ChromaDye[$skin] = $out
    $out
}
# Push the op stack onto the dye colours of whatever materials paint this map on
# a recolor skin. Entries are tagged viaChroma so unticking can take back exactly
# what the tick box added and leave hand-made colour edits alone.
function Mirror-DyeToChroma([string]$skin, [string]$texRel, $stack, [string]$artPng) {
    $dye = Get-ChromaDye $skin
    if (@($dye.tex.Keys).Count -eq 0) { return 0 }
    $leaf = [IO.Path]::GetFileNameWithoutExtension($texRel)
    if (-not $dye.tex.ContainsKey($leaf)) { return 0 }
    # What the dye should paint. Each region is sampled over the pixels IT dyes
    # (the mask's alpha says which), so the shorts take the shorts' colour and
    # the jacket the jacket's, instead of one average smeared over the lot.
    $dyeColor = $null
    $byRegion = @{}
    if (@($stack).Count -gt 0 -and $artPng) {
        $maskPng = $null
        $maskLeaf = ($leaf -replace '_D$', '_ColorID')
        if ($script:ChromaMaskRels.ContainsKey($skin) -and $script:ChromaMaskRels[$skin].ContainsKey($maskLeaf)) {
            $maskPng = Join-Path (Join-Path (Join-Path $SS_Cache $skin) 'png\src') $script:ChromaMaskRels[$skin][$maskLeaf]
        }
        $byRegion = SS-SampleDyeRegions $artPng $maskPng
        $dyeColor = SS-SampleDyeColor $artPng $maskPng     # fallback for anything unregioned
    }
    if (@($stack).Count -gt 0 -and -not $dyeColor -and @($byRegion.Keys).Count -eq 0) { return 0 }
    if (-not $script:ColorOpsBySkin.ContainsKey($skin)) { $script:ColorOpsBySkin[$skin] = @{} }
    $cops = $script:ColorOpsBySkin[$skin]
    $n = 0
    foreach ($matLeaf in @($dye.tex[$leaf])) {
      foreach ($entry in @($dye.par[$matLeaf])) {
        $matRel = $entry.rel
        foreach ($p in @($entry.params)) {
            $key = '{0}_{1}' -f $p.export, $p.ordinal
            if (@($stack).Count -eq 0) {
                if ($cops.ContainsKey($matRel) -and $cops[$matRel].ContainsKey($key) -and $cops[$matRel][$key].viaChroma) {
                    [void]$cops[$matRel].Remove($key); $n++
                }
                continue
            }
            # "Region 3 - ColorA" takes region 3's dark end, "- ColorB" its light
            # end, and the G/B channel colours its overall colour. Anything that
            # is not a region param (or a region this mask never dyes) falls back
            # to the material's average.
            $new = $dyeColor
            if ([string]$p.name -match '^Region (\d+) - Color(A|B|GChannel|BChannel)$') {
                $rgn = [int]$Matches[1]; $which = $Matches[2]
                if ($byRegion.ContainsKey($rgn)) {
                    $bucket = $byRegion[$rgn]
                    $new = switch ($which) {
                        'A'        { $bucket.a }
                        'B'        { $bucket.b }
                        'GChannel' { if ($bucket.g) { $bucket.g } else { $bucket.b } }
                        'BChannel' { if ($bucket.bch) { $bucket.bch } else { $bucket.b } }
                        default    { $bucket.b }
                    }
                } else {
                    continue                    # this mask never dyes that region - leave it alone
                }
            }
            if (-not $new) { continue }
            # the dye REPLACES the art in its zone (proven in game with a white
            # dye: the zone rendered flat neutral, not the art), so the value to
            # write is simply the design's colour - no scaling to the vanilla's
            # brightness, which would make the zone glow where the costume does not
            if (-not $cops.ContainsKey($matRel)) { $cops[$matRel] = @{} }
            # never overwrite a colour she set by hand on that skin
            if ($cops[$matRel].ContainsKey($key) -and -not $cops[$matRel][$key].viaChroma) { continue }
            $cops[$matRel][$key] = @{ export = $p.export; ordinal = $p.ordinal; name = $p.name; r = $new.r; g = $new.g; b = $new.b; viaChroma = $true }
            $n++
        }
      }
    }
    $n
}
# every op in the session that belongs to a recolor of the open skin
function Get-ChromaOpCount {
    $n = 0
    if ($script:ChromaT) {
        foreach ($t in (@($script:ChromaT.Sure) + @($script:ChromaT.Maybe))) {
            if ($script:OpsBySkin.ContainsKey($t)) { $n += @($script:OpsBySkin[$t].Keys).Count }
        }
    }
    $n
}
function Refresh-Thumb($tex) {
    $ops = Get-Ops
    $isMod = $ops.ContainsKey($tex.Rel)
    $bmp = $null
    if ($isMod) {
        try { $bmp = SS-RenderStack $tex.Thumb $ops[$tex.Rel] } catch { $bmp = $null }
    }
    if (-not $bmp) { $bmp = [SkinArt]::Load($tex.Thumb) }
    [void]$imgList.Images.Add($bmp); $bmp.Dispose()
    $tex.ImgIdxLive = $imgList.Images.Count - 1
    $tex.Item.ImageIndex = $tex.ImgIdxLive
    $tex.Item.Text = Tex-Label $tex $isMod
    $tex.Item.ForeColor = if ($isMod) { $colPink } else { Tex-Fore $tex }
}

# ---- color editing (materials + particle color curves) ----------------------
function Get-ColorOps {
    if (-not $script:CurSkin) { return @{} }
    if (-not $script:ColorOpsBySkin.ContainsKey($script:CurSkin)) { $script:ColorOpsBySkin[$script:CurSkin] = @{} }
    $script:ColorOpsBySkin[$script:CurSkin]
}
# every (export,ordinal) key a color item covers: 1 for a material param, many
# for an aggregated particle effect (all curves of that color group).
function ColorKeys($ci) {
    if ($ci.Kind -eq 'curve') { return @($ci.Curves | ForEach-Object { '{0}_{1}' -f $_.export, $_.ordinal }) }
    @('{0}_{1}' -f $ci.Export, $ci.Ordinal)
}
function Get-ColorEdit($ci) {
    $ops = Get-ColorOps
    if (-not $ops.ContainsKey($ci.Rel)) { return $null }
    $k = @(ColorKeys $ci)[0]
    if ($ops[$ci.Rel].ContainsKey($k)) { return $ops[$ci.Rel][$k] }
    $null
}
function Count-ColorEdits { $n = 0; foreach ($rel in (Get-ColorOps).Keys) { $n += (Get-ColorOps)[$rel].Count }; $n }
# classify a material param name -> role + whether it is a real editable color
# (many FLinearColors are actually directions/ranges/smoothness - hide those).
# Which FLinearColor properties are actually COLOURS you can pick with a colour
# picker. Plenty are not: UE stores directions, positions, tangents and packed
# parameter triples in the same type. Editing one of those with an sRGB swatch
# clamps it into 0..1 and wrecks the material - a bulk retint of White Fox set
# PortalCenter (vanilla 10,000,000 / 457,515 / 6,201,983), TangentB, RampLightDir
# and 102 MC_Shade ramp steps, and the skin came out broken in game.
#
# Two gates, because a name list alone will always miss something:
#   1. the name looks like a vector / parameter pack  -> not a colour
#   2. (in Load-ColorItems) its vanilla value is outside 0..1 -> not a colour,
#      since a picker cannot even express it
function ColorRole([string]$name, [string]$mat) {
    if ($name -match '(?i)direction|\bdir\b|dir$|dir_|tangent|center|centre|position|\bpos\b|axis|tiling|param|mix\d*$|range|power|offset|smooth|fresnel|mask|uv|depth|bias|multiplier|intensity|roughness') {
        return @{ role = 'param'; color = $false }
    }
    if ($name -match '(?i)rim')                                  { return @{ role = 'rim';      color = $true } }
    if ($name -match '(?i)emiss|glow|luminous|fx_color|fx_self')  { return @{ role = 'emissive'; color = $true } }
    if ($mat  -match '(?i)eye')                                  { return @{ role = 'eyes';     color = $true } }
    # the cel-shading ramp. Editable on purpose - but it is the LIGHTING steps,
    # not the surface colour, so it is kept out of bulk retints (see $bulkColor)
    if ($name -match '(?i)shade')                                 { return @{ role = 'shade';    color = $true } }
    if ($name -match '(?i)base|tint|colou?r|ramp|inner|line|spec') { return @{ role = 'tint';    color = $true } }
    @{ role = 'other'; color = $true }
}
function MatLabel([string]$rel) {
    $leaf = [IO.Path]::GetFileNameWithoutExtension($rel)
    $short = $leaf -replace '(?i)^MI_\d+_?', ''
    if (-not $short) { $short = $leaf }
    if ($rel -match '(?i)/Lobby/') { $short = "$short  (lobby)" }
    $short
}
# NS_103121_Attack_02 -> "Attack_02" (drop NS_ + hero/ability id prefix)
function FxLabel([string]$rel) {
    $leaf = [IO.Path]::GetFileNameWithoutExtension($rel)
    $s = $leaf -replace '(?i)^NS_\d+_?', ''
    if (-not $s) { $s = $leaf }
    $s
}
# Drop colour ops that point at something the studio no longer considers an
# editable colour - a direction vector, a position, an HDR value, anything the
# rules above now reject. Designs saved before those rules existed carry them,
# and shipping one is what breaks a skin in game, so this heals them quietly.
# Materials only: particle ops have their own items and are not validated here.
function Prune-BadColorOps {
    if (-not $script:CurSkin) { return 0 }
    $ops = Get-ColorOps
    if ($ops.Count -eq 0) { return 0 }
    $valid = @{}
    foreach ($ci in $script:ColorItems) {
        if ($ci.Kind -ne 'linear') { continue }
        # parenthesised: -f inside an index or an argument list needs it, or the
        # format string is handed fewer arguments than it has placeholders
        $valid[('{0}|{1}|{2}' -f $ci.Rel, $ci.Export, $ci.Ordinal)] = $true
    }
    if ($valid.Count -eq 0) { return 0 }        # nothing loaded to validate against
    $dropped = 0
    foreach ($rel in @($ops.Keys)) {
        if ($rel -notmatch '(?i)[/\\]Materials[/\\]') { continue }   # leave particles alone
        # and effect materials (VFX/Materials/...): they are never in the skin's
        # Materials list, so validating them here would silently delete them all
        if ($rel -match '(?i)(^|[/\\])VFX[/\\]') { continue }
        $inner = $ops[$rel]
        foreach ($k in @($inner.Keys)) {
            $e = $inner[$k]
            if ([string]$e.kind -eq 'curve') { continue }
            if (-not $valid.ContainsKey(('{0}|{1}|{2}' -f $rel, $e.export, $e.ordinal))) {
                $inner.Remove($k); $dropped++
            }
        }
        if ($inner.Count -eq 0) { $ops.Remove($rel) }
    }
    return $dropped
}
function ColorDisp($ci) {
    $e = Get-ColorEdit $ci
    if ($e) { @([double]$e.r, [double]$e.g, [double]$e.b) } else { @([double]$ci.R, [double]$ci.G, [double]$ci.B) }
}
function Refresh-ColorRow($ci) {
    $disp = ColorDisp $ci
    $bmp = [SkinArt]::Swatch($disp[0], $disp[1], $disp[2], 40, 40)
    [void]$colorImgList.Images.Add($bmp); $bmp.Dispose()
    $ci.Item.ImageIndex = $colorImgList.Images.Count - 1
    $edited = [bool](Get-ColorEdit $ci)
    $ci.Item.SubItems[2].Text = if ($edited) { "● $($ci.Name)" } else { $ci.Name }
    $ci.Item.ForeColor = if ($edited) { $colPink } else { $colFore }
}
# build the color rows for the current skin + kind ('mat' materials, 'fx' particles)
function Load-ColorItems([string]$kind) {
    if (-not $script:CurSkin) { return }
    $tag = '{0}/{1}' -f $script:CurSkin, $kind
    if ($script:ColorShownKind -eq $tag -and $script:ColorItems.Count -gt 0) { return }
    $frm.Cursor = 'WaitCursor'
    try {
        $cj = SS-EnsureColorCache $script:CurSkin { param($m) Set-Status $m } $pump $kind
        $doc = Get-Content -LiteralPath $cj -Raw | ConvertFrom-Json
        $lvColors.BeginUpdate(); $lvColors.Items.Clear(); $colorImgList.Images.Clear()
        $script:ColorItems = @()
        if ($kind -eq 'mat') {
            foreach ($a in $doc) {
                $mat = MatLabel $a.asset
                foreach ($c in $a.colors) {
                    if ($c.kind -eq 'curve') { continue }
                    $rc = ColorRole $c.name $a.asset
                    if (-not $rc.color) { continue }
                    # second gate: a value outside 0..1 is not something an sRGB
                    # swatch can express - it is an HDR value or a packed vector,
                    # and picking a colour for it would clamp and break it
                    $mx = [Math]::Max([double]$c.r, [Math]::Max([double]$c.g, [double]$c.b))
                    $mn = [Math]::Min([double]$c.r, [Math]::Min([double]$c.g, [double]$c.b))
                    if ($mx -gt 1.001 -or $mn -lt -0.001) { continue }
                    $script:ColorItems += [pscustomobject]@{
                        Rel = [string]$a.asset; Export = [int]$c.export; Ordinal = [int]$c.ordinal
                        Name = [string]$c.name; Mat = $mat; R = [double]$c.r; G = [double]$c.g; B = [double]$c.b; A = [double]$c.a
                        Role = $rc.role; Kind = 'linear'; Curves = $null; Item = $null
                    }
                }
            }
            $order = @{ emissive = 0; rim = 1; tint = 2; eyes = 3; shade = 4; other = 5 }
            $sorted = @($script:ColorItems | Sort-Object @{e = { $order[$_.Role] } }, Mat, Name)
        } else {
            # particles: one row per NS effect per distinct color-over-life; picking
            # a color retints ALL that group's baked curves (GPU/CPU/LOD variants).
            foreach ($a in $doc) {
                $ns = FxLabel $a.asset
                $groups = [ordered]@{}
                foreach ($c in $a.colors) {
                    if ($c.kind -ne 'curve') { continue }
                    $gk = '{0:0.0}_{1:0.0}_{2:0.0}' -f [double]$c.r, [double]$c.g, [double]$c.b
                    if (-not $groups.Contains($gk)) { $groups[$gk] = @{ curves = @(); r = [double]$c.r; g = [double]$c.g; b = [double]$c.b; a = [double]$c.a } }
                    $groups[$gk].curves += @{ export = [int]$c.export; ordinal = [int]$c.ordinal }
                }
                $gi = 0
                foreach ($gk in $groups.Keys) {
                    $g = $groups[$gk]; $gi++
                    $nm = if ($groups.Count -gt 1) { "effect color $gi" } else { 'effect color' }
                    $script:ColorItems += [pscustomobject]@{
                        Rel = [string]$a.asset; Export = -1; Ordinal = -1; Name = $nm; Mat = $ns
                        R = $g.r; G = $g.g; B = $g.b; A = $g.a; Role = 'particle'; Kind = 'curve'; Curves = $g.curves; Item = $null
                    }
                }
            }
            $sorted = @($script:ColorItems | Sort-Object Mat, Name)
        }
        foreach ($ci in $sorted) {
            $item = New-Object System.Windows.Forms.ListViewItem('')
            [void]$item.SubItems.Add($ci.Mat)
            [void]$item.SubItems.Add($ci.Name)
            [void]$item.SubItems.Add($ci.Role)
            $item.Tag = $ci; $ci.Item = $item
            [void]$lvColors.Items.Add($item)
            Refresh-ColorRow $ci
        }
        $lvColors.EndUpdate()
        $script:ColorShownKind = $tag; $script:SelColor = $null
        if ($kind -eq 'mat') {
            $gone = Prune-BadColorOps
            if ($gone -gt 0) {
                foreach ($ci in $script:ColorItems) { Refresh-ColorRow $ci }
                Set-Status ('Dropped {0} colour edit(s) that pointed at a direction / position / HDR value rather than a colour - those are what break a skin in game. Rebuild to ship the cleaned design.' -f $gone)
            }
        }
        $noun = if ($kind -eq 'fx') { 'particle effect colors' } else { 'material colors' }
        Set-Status ('{0} editable {1} ({2} edited). Click one, pick a color, APPLY.' -f $script:ColorItems.Count, $noun, (Count-ColorEdits))
    } catch {
        $lvColors.EndUpdate()
        Set-Status ('color load failed: ' + $_.Exception.Message)
    } finally { $frm.Cursor = 'Default' }
}
function Set-Mode([string]$mode) {
    $script:BrowseMode = $mode
    $isTex = $mode -eq 'tex'
    $lvTex.Visible = $isTex; $grpOp.Visible = $isTex; $chkAdvanced.Visible = $isTex; $grpLayers.Visible = $isTex
    $picVan.Visible = $isTex; $picMod.Visible = $isTex
    $lvColors.Visible = -not $isTex; $grpColorOp.Visible = -not $isTex
    Set-ModeBtn $btnModeTex ($mode -eq 'tex')
    Set-ModeBtn $btnModeMat ($mode -eq 'mat')
    Set-ModeBtn $btnModeFx  ($mode -eq 'fx')
    if ($isTex) {
        $lblBrowse.Text = 'TEXTURES'
        $lblBrowseHint.Text = 'white = color + specular maps (editable) · gray = technical maps (normals / ORM / masks)'
    } elseif ($mode -eq 'mat') {
        $lblBrowse.Text = 'MATERIAL COLORS'
        $lblBrowseHint.Text = 'lighting · emissive · rim · tint · eyes · "(lobby)" = hero-select preview'
        # Set-CardTitle, not .Text: the card paints its own title (see PaintCard)
        Set-CardTitle $grpColorOp 'Color operation  (material lighting · emissive · rim · tint · eyes)'
        Load-ColorItems 'mat'
    } else {
        $lblBrowse.Text = 'PARTICLE COLORS'
        $lblBrowseHint.Text = 'recolor an ability effect - retints its whole color-over-life'
        Set-CardTitle $grpColorOp 'Particle color  (recolors the whole effect gradient, brightness kept)'
        Load-ColorItems 'fx'
    }
    if (-not $isTex -and -not $script:SelColor) { $lblTexName.Text = 'no color selected' }
}
function Show-ColorSel {
    $ci = $script:SelColor
    if (-not $ci) { $pnlColCur.BackColor = $colField; $pnlColNew.BackColor = $colField; return }
    $rgb = [SkinArt]::LinearToHex([double]$ci.R, [double]$ci.G, [double]$ci.B)
    $pnlColCur.BackColor = [System.Drawing.Color]::FromArgb($rgb[0], $rgb[1], $rgb[2])
    $disp = ColorDisp $ci
    $drgb = [SkinArt]::LinearToHex($disp[0], $disp[1], $disp[2])
    $pnlColNew.BackColor = [System.Drawing.Color]::FromArgb($drgb[0], $drgb[1], $drgb[2])
    $edited = [bool](Get-ColorEdit $ci)
    $lblTexName.Text = ('{0}  ·  {1}   [{2}]{3}' -f $ci.Mat, $ci.Name, $ci.Role, $(if ($edited) { '  (edited)' } else { '' }))
}
function Apply-ColorTo($ci, $sRGB) {
    $lin = [SkinArt]::HexToLinear($sRGB.R, $sRGB.G, $sRGB.B)
    $ops = Get-ColorOps
    if (-not $ops.ContainsKey($ci.Rel)) { $ops[$ci.Rel] = @{} }
    if ($ci.Kind -eq 'curve') {
        foreach ($cv in $ci.Curves) {
            $ops[$ci.Rel]['{0}_{1}' -f $cv.export, $cv.ordinal] = @{ export = $cv.export; ordinal = $cv.ordinal; name = $ci.Name; kind = 'curve'; r = [double]$lin[0]; g = [double]$lin[1]; b = [double]$lin[2] }
        }
    } else {
        $ops[$ci.Rel]['{0}_{1}' -f $ci.Export, $ci.Ordinal] = @{ export = $ci.Export; ordinal = $ci.Ordinal; name = $ci.Name; r = [double]$lin[0]; g = [double]$lin[1]; b = [double]$lin[2] }
    }
    Refresh-ColorRow $ci
}
function Revert-ColorOf($ci) {
    $ops = Get-ColorOps
    if ($ops.ContainsKey($ci.Rel)) {
        foreach ($k in (ColorKeys $ci)) { $ops[$ci.Rel].Remove($k) }
        if ($ops[$ci.Rel].Count -eq 0) { $ops.Remove($ci.Rel) }
    }
    Refresh-ColorRow $ci
}

function Open-Skin([string]$sid) {
    if (-not $sid) { return }
    $frm.Cursor = 'WaitCursor'
    $btnOpen.Enabled = $false
    try {
        $lines = $script:Map.skinLines[$sid]
        $ck = SS-EnsureSkinCache $sid $lines { param($m) Set-Status $m } $pump
        $script:CurSkin = $sid; $script:CurHero = Get-SelHero; $script:CurCk = $ck
        $script:SelTex = $null
        # reset color browser state for the new skin (colors load lazily on toggle)
        $script:ColorShownKind = $null; $script:ColorItems = @(); $script:SelColor = $null
        $lvColors.Items.Clear(); $colorImgList.Images.Clear()
        New-Item -ItemType Directory -Force -Path (Join-Path $ck 'pv') | Out-Null

        # thumbs.map -> tex objects + list items
        $lvTex.BeginUpdate()
        $lvTex.Items.Clear(); $imgList.Images.Clear()
        $script:TexItems = @()
        $mapFile = Join-Path $ck 'thumbs.map'
        $rows = [IO.File]::ReadAllLines($mapFile)
        $pngRoot = Join-Path $ck 'png\src'
        foreach ($row in $rows) {
            $parts = $row.Split('|')
            $tex = [pscustomobject]@{
                # Role is recomputed, not read from thumbs.map column 3: caches
                # only rebuild on a game update, so a change to SS-TexRole would
                # otherwise not reach any skin already cached.
                Rel = $parts[0]; Thumb = $parts[1]; Dims = $parts[2]; Role = (SS-TexRole $parts[0])
                Png = (Join-Path $pngRoot $parts[0])
                ImgIdx = $script:TexItems.Count; ImgIdxLive = 0; Item = $null
            }
            $script:TexItems += $tex
        }
        # which of these are the SAME map under another name (see SS-LinkGroups)
        $script:Links = SS-LinkGroups @($script:TexItems | ForEach-Object { $_.Rel })
        # this costume's recolours (chromas): other skin ids whose maps are the
        # same art repainted. Editing only this one leaves them vanilla in game.
        Set-ChromaBoxes $sid
        # color maps first, tech after (stable within group)
        $sorted = @($script:TexItems | Sort-Object @{e = { if ($_.Role -eq 'color') { 0 } else { 1 } } }, Rel)
        foreach ($tex in $sorted) {
            $bmp = [SkinArt]::Load($tex.Thumb)
            [void]$imgList.Images.Add($bmp); $bmp.Dispose()
            $tex.ImgIdxLive = $imgList.Images.Count - 1
            $item = New-Object System.Windows.Forms.ListViewItem
            $item.Text = Tex-Label $tex $false
            $item.ImageIndex = $tex.ImgIdxLive
            $item.ToolTipText = Tex-Tip $tex
            $item.ForeColor = Tex-Fore $tex
            $item.Tag = $tex; $tex.Item = $item
            [void]$lvTex.Items.Add($item)
        }
        $lvTex.EndUpdate()

        # re-apply any ops from a loaded design / earlier this session
        foreach ($tex in $script:TexItems) { if ((Get-Ops).ContainsKey($tex.Rel)) { Refresh-Thumb $tex } }
        $nCol = @($script:TexItems | Where-Object Role -eq 'color').Count
        $lblCache.Text = 'cache: ' + $ck
        # a design loaded from disk (or saved before recolors were a thing) carries
        # ops for this skin only - with the box ticked, extend them to the recolors
        $nSync = Sync-ChromaOps
        $cNote = if ($nSync -gt 0) { ' Carried its edits onto {0} recolor map(s).' -f $nSync } else { '' }
        Set-Status ('{0} open: {1} textures ({2} color maps). Click one to edit.{3}' -f (SkinLabel $sid), $script:TexItems.Count, $nCol, $cNote)
        # the brand band keeps the open skin on show, so it is readable from the
        # far side of the window whichever column you are working in
        Set-BrandNote ('{0}  ·  {1}  ·  {2} textures' -f (HeroLabel $script:CurHero), (SkinLabel $sid), $script:TexItems.Count)
        if (-not $txtModName.Text) {
            $heroNm = ($script:HeroNames[$script:CurHero] -replace '[^A-Za-z0-9]', '')
            if (-not $heroNm) { $heroNm = $sid }
            $txtModName.Text = "My${heroNm}Skin"
            $txtDisplay.Text = "My $heroNm Skin"
        }
        if ($script:BrowseMode -ne 'tex') { Load-ColorItems $script:BrowseMode }
    } finally {
        $btnOpen.Enabled = $true
        $frm.Cursor = 'Default'
    }
}

# ---- events -----------------------------------------------------------------
$txtSearch.Add_TextChanged({ Refresh-HeroList })
$lstHeroes.Add_SelectedIndexChanged({ Refresh-SkinList })
$lstSkins.Add_DoubleClick({ Open-Skin (Get-SelSkin) })
$btnOpen.Add_Click({ Open-Skin (Get-SelSkin) })

$btnRenameHero.Add_Click({
    $hid = Get-SelHero; if (-not $hid) { return }
    $cur = $script:HeroNames[$hid]; if (-not $cur) { $cur = '' }
    $nm = [Microsoft.VisualBasic.Interaction]::InputBox("Name for hero $hid :", 'Rename hero', $cur)
    if ($nm) { $script:HeroNames[$hid] = $nm; Save-Names; Refresh-HeroList; Refresh-SkinList }
})
$btnRenameSkin.Add_Click({
    $sid = Get-SelSkin; if (-not $sid) { return }
    $cur = $script:SkinNames[$sid]; if (-not $cur) { $cur = '' }
    $nm = [Microsoft.VisualBasic.Interaction]::InputBox("Name for skin $sid :", 'Rename skin', $cur)
    if ($nm) { $script:SkinNames[$sid] = $nm; Save-Names; Refresh-SkinList }
})
$onChromaToggle = {
    if ($script:Loading -or -not $script:CurSkin) { return }
    $n = Sync-ChromaOps
    $act = @(Get-ChromaActive).Count
    if ($act -gt 0) { Set-Status ('Recolor skins included: {0}. {1} map(s) carried across - they ship in the same mod.' -f $act, $n) }
    else { Set-Status ('Recolor skins excluded again ({0} map(s) dropped) - only this skin is edited.' -f $n) }
}
$chkChroma.Add_CheckedChanged($onChromaToggle)
$chkChromaMaybe.Add_CheckedChanged($onChromaToggle)
$btnOutDir.Add_Click({ Start-Process explorer.exe (Join-Path $SS_Root 'output') })
$btnEditDir.Add_Click({
    $d = Join-Path $SS_Root 'work\edit'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Start-Process explorer.exe $d
})

$lvTex.Add_SelectedIndexChanged({
    if ($lvTex.SelectedItems.Count -eq 0) { return }
    $script:SelTex = $lvTex.SelectedItems[0].Tag
    $script:Loading = $true
    # 1-layer stack: load it into the panel for direct editing (classic feel);
    # multi-layer: panel starts as an empty draft, click a layer to edit it
    $stack = Get-CurStack
    if ($stack.Count -eq 1) { $script:EditLayerIdx = 0; Set-PanelFromOp $stack[0] }
    else { $script:EditLayerIdx = -1; Set-PanelFromOp $null }
    $script:Loading = $false
    $lblTexName.Text = '{0}   ({1}, {2} map)' -f $script:SelTex.Rel, $script:SelTex.Dims, $script:SelTex.Role
    # this map may exist more than once in the skin - offer to carry the edit
    # across. A certain match is ticked for you; a possible one is not, because
    # nothing in the filenames can tell "the same coat on the other form" from
    # "a different prop" (see SS-LinkGroups).
    $lk = $script:Links[$script:SelTex.Rel]
    $chkLinked.Visible = [bool]$lk
    if ($lk) {
        $n = @($lk.Others).Count
        $chkLinked.Text = if ($lk.Sure) {
            if ($n -eq 1) { '⇄ also apply to the other version' } else { '⇄ also apply to the other {0} versions' -f $n }
        } else {
            if ($n -eq 1) { '⇄ also apply to the possible match' } else { '⇄ also apply to the {0} possible matches' -f $n }
        }
        $chkLinked.Checked = [bool]$lk.Sure
        $tt.SetToolTip($chkLinked, ($(if ($lk.Sure) {
                "This skin ships the same map more than once - same name, different character form or folder:" }
            else {
                "These key to the same body part, but their names differ by more than an id, so they MIGHT be a different object. Check the thumbnails before ticking:" }) +
            "`r`n  " + (($lk.Others | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }) -join "`r`n  ") +
            "`r`nEditing only one leaves the rest vanilla in game."))
    }
    $editPath = Join-Path $SS_Root ('work\edit\{0}\{1}' -f $script:CurSkin, ([IO.Path]::ChangeExtension([IO.Path]::GetFileName($script:SelTex.Rel), 'png')))
    if (Test-Path -LiteralPath $editPath) { $lblEditPath.Text = 'found: ' + (Split-Path $editPath -Leaf) } else { $lblEditPath.Text = '' }
    Refresh-OpPanelEnabled
    Show-Preview
})
$chkAdvanced.Add_CheckedChanged({ Refresh-OpPanelEnabled })

# ---- color mode events ------------------------------------------------------
$btnModeTex.Add_Click({ Set-Mode 'tex' })
$btnModeMat.Add_Click({ Set-Mode 'mat' })
$btnModeFx.Add_Click({ Set-Mode 'fx' })
$lvColors.Add_SelectedIndexChanged({
    if ($lvColors.SelectedItems.Count -eq 0) { return }
    $script:SelColor = $lvColors.SelectedItems[0].Tag
    Show-ColorSel
})
$btnColPick.Add_Click({
    # the studio's own picker, not the Windows one - see VuiColorDialog
    $c = VuiColorDialog $pnlColNew.BackColor
    if ($c) { $pnlColNew.BackColor = $c }
})
$btnColApply.Add_Click({
    if (-not $script:SelColor) { Set-Status 'Select a color on the left first.'; return }
    Apply-ColorTo $script:SelColor $pnlColNew.BackColor
    Show-ColorSel
    Set-Status ('Color applied. {0} color edit(s) on this skin.' -f (Count-ColorEdits))
})
$btnColRevert.Add_Click({
    if (-not $script:SelColor) { return }
    Revert-ColorOf $script:SelColor
    Show-ColorSel
    Set-Status ('Reverted. {0} color edit(s) remain.' -f (Count-ColorEdits))
})
$btnColBulkPick.Add_Click({
    $c = VuiColorDialog $pnlColBulk.BackColor
    if ($c) { $pnlColBulk.BackColor = $c }
})
$bulkColor = {
    param($predicate, $desc)
    if ($script:ColorItems.Count -eq 0) { Set-Status 'Open a skin in Colors mode first.'; return }
    $targets = @($script:ColorItems | Where-Object $predicate)
    if ($targets.Count -eq 0) { Set-Status "No $desc colors to retint."; return }
    $ans = [System.Windows.Forms.MessageBox]::Show(("Retint {0} {1} color(s) to the bulk swatch?" -f $targets.Count, $desc), 'Skin Studio', 'YesNo')
    if ($ans -ne 'Yes') { return }
    $frm.Cursor = 'WaitCursor'
    try { foreach ($ci in $targets) { Apply-ColorTo $ci $pnlColBulk.BackColor } }
    finally { $frm.Cursor = 'Default' }
    if ($script:SelColor) { Show-ColorSel }
    Set-Status ('Bulk retint applied to {0} {1} color(s). {2} total edits.' -f $targets.Count, $desc, (Count-ColorEdits))
}
# NOT { $true }: 'shade' is the cel-shading ramp, three or four grey steps per
# material that define how light falls off. Retinting those along with everything
# else is what turned White Fox into a flat mess - 102 of the 305 sites in that
# build were MC_Shade. Change them one at a time if you really mean to.
$btnColBulkAll.Add_Click({ & $bulkColor { $_.Role -ne 'shade' } 'shown (not the shading ramps)' })
$btnColBulkRim.Add_Click({ & $bulkColor { $_.Role -eq 'rim' -or $_.Role -eq 'emissive' } 'rim/emissive' })

# live-preview debounce: a slider drag fires ValueChanged on every notch -
# labels update instantly, but the render coalesces to ONE pass ~120ms after
# the last change (Show-Preview stops the timer, so direct calls also absorb
# any pending tick)
$onOpChanged = { if (-not $script:Loading) { $lblStr.Text = 'Strength: {0}%' -f $trkStr.Value; $script:PvTimer.Stop(); $script:PvTimer.Start() } }
foreach ($ctl in @($rbVanilla, $rbRecolor, $rbReplace, $rbEdited)) { $ctl.Add_CheckedChanged($onOpChanged) }
$cmbMode.Add_SelectedIndexChanged($onOpChanged)
$trkStr.Add_ValueChanged($onOpChanged)
$numHue.Add_ValueChanged($onOpChanged)
$numSat.Add_ValueChanged($onOpChanged)
$numLight.Add_ValueChanged($onOpChanged)
$chkProtect.Add_CheckedChanged($onOpChanged)

$btnColor.Add_Click({
    $c = VuiColorDialog $pnlColor.BackColor
    if ($c) { $pnlColor.BackColor = $c; & $onOpChanged }
})
$pickInto = {
    param($swatch)
    $c = VuiColorDialog $swatch.BackColor
    if ($c) { $swatch.BackColor = $c; & $onOpChanged }
}
$btnColorB.Add_Click({ & $pickInto $pnlColorB })
$btnColorC.Add_Click({ & $pickInto $pnlColorC })
$btnColorD.Add_Click({ & $pickInto $pnlColorD })
$cmbGradDir.Add_SelectedIndexChanged({ Update-OpControlVis; & $onOpChanged })
$cmbMode.Add_SelectedIndexChanged({ Update-OpControlVis })
$btnBand.Add_Click({
    if (-not $script:SelTex) { Set-Status 'Open a skin and click a texture first - the picker works on what you can see.'; return }
    if (Show-BandPicker) {
        & $onOpChanged        # re-render the preview with the new band
        Set-Status $(if ($script:BandCenter -lt 0) {
            'Color family: back to auto-detect.'
        } else {
            'Color family: hue {0:N0}° ±{1:N0}° - only that band gets recolored.' -f $script:BandCenter, $script:BandWidth
        })
    }
})
$btnPickImg.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Images|*.png;*.jpg;*.jpeg;*.bmp;*.webp'
    if ($dlg.ShowDialog() -eq 'OK') {
        $lblImgPath.Tag = $dlg.FileName
        $lblImgPath.Text = Split-Path $dlg.FileName -Leaf
        $rbReplace.Checked = $true
        & $onOpChanged
    }
})
$btnEditPng.Add_Click({
    if (-not $script:SelTex) { return }
    $d = Join-Path $SS_Root ('work\edit\{0}' -f $script:CurSkin)
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    $dst = Join-Path $d ([IO.Path]::ChangeExtension([IO.Path]::GetFileName($script:SelTex.Rel), 'png'))
    if (-not (Test-Path -LiteralPath $dst)) { Copy-Item -LiteralPath $script:SelTex.Png -Destination $dst }
    Start-Process explorer.exe "/select,`"$dst`""
    $lblEditPath.Text = 'found: ' + (Split-Path $dst -Leaf)
    Set-Status 'Edit the PNG in your editor (keep the size), save it, then pick "Use my hand-edited PNG" + Apply.'
})

$btnApply.Add_Click({
    if (-not $script:SelTex) { return }
    $op = Get-PanelOp
    $ops = Get-Ops
    $stack = Get-CurStack
    if ($stack.Count -gt 1) {
        $ans = [System.Windows.Forms.MessageBox]::Show(("Replace all {0} layers on this texture with the single panel op? (use the Layers buttons to keep the stack)" -f $stack.Count), 'Skin Studio', 'YesNo')
        if ($ans -ne 'Yes') { return }
    }
    if ($op) { $ops[$script:SelTex.Rel] = ,$op; $script:EditLayerIdx = 0 }
    else { $ops.Remove($script:SelTex.Rel); $script:EditLayerIdx = -1 }
    Refresh-Thumb $script:SelTex
    $mirrored = Mirror-ToLinked $script:SelTex.Rel $(if ($op) { ,$op } else { @() })
    $chroma = Mirror-ToChromas $script:SelTex.Rel $(if ($op) { ,$op } else { @() })
    Show-Preview
    $also = if ($mirrored) { ' (+{0} other version(s) of this map)' -f $mirrored } else { '' }
    if ($chroma) { $also += ' (+{0} recolor skin(s))' -f $chroma }
    Set-Status ('Applied{0}. {1} texture(s) modified for this skin.' -f $also, $ops.Count)
})
$btnRevert.Add_Click({
    if (-not $script:SelTex) { return }
    (Get-Ops).Remove($script:SelTex.Rel)
    $script:EditLayerIdx = -1
    $script:Loading = $true; $rbVanilla.Checked = $true; $script:Loading = $false
    Refresh-Thumb $script:SelTex
    [void](Mirror-ToLinked $script:SelTex.Rel @())      # its other versions go back too
    [void](Mirror-ToChromas $script:SelTex.Rel @())     # and so do the recolor skins
    Show-Preview
})

# ---- layer stack buttons ----------------------------------------------------
$lstLayers.Add_Click({
    if ($script:Loading -or -not $script:SelTex) { return }
    $idx = $lstLayers.SelectedIndex
    $stack = Get-CurStack
    if ($idx -lt 0 -or $idx -ge $stack.Count) { return }
    if ($idx -eq $script:EditLayerIdx) {
        # clicking the layer you are already editing lets go of it: the panel
        # becomes a draft for a NEW layer on top (there was no way back before)
        $script:EditLayerIdx = -1
        $script:Loading = $true; Set-PanelFromOp $null; $script:Loading = $false
        $lstLayers.ClearSelected()
        Show-Preview
        Set-Status 'Stopped editing that layer. Set up the panel to draft a new layer on top.'
        return
    }
    $script:EditLayerIdx = $idx
    $script:Loading = $true
    Set-PanelFromOp $stack[$idx]
    $script:Loading = $false
    Show-Preview
})
function Commit-Stack($newStack) {
    $ops = Get-Ops
    if (@($newStack).Count -eq 0) { $ops.Remove($script:SelTex.Rel) }
    else { $ops[$script:SelTex.Rel] = @($newStack) }
    Refresh-Thumb $script:SelTex
    [void](Mirror-ToLinked $script:SelTex.Rel $newStack)
    [void](Mirror-ToChromas $script:SelTex.Rel $newStack)
    Show-Preview
}
$btnLayerAdd.Add_Click({
    if (-not $script:SelTex) { return }
    $op = Get-PanelOp
    if (-not $op) { Set-Status 'Set up a recolor / replace in the panel first, then add it as a layer.'; return }
    $stack = (Get-CurStack) + ,$op
    # the new layer is committed; the panel goes back to a clean draft so the
    # NEXT thing you set up previews on top of the stack instead of quietly
    # re-editing the layer you just added
    $script:EditLayerIdx = -1
    $script:Loading = $true; Set-PanelFromOp $null; $script:Loading = $false
    Commit-Stack $stack
    Set-Status ('Layer {0} added. Pick Recolor/Replace again to draft the next layer (your last settings are kept), or click a layer to edit it.' -f $stack.Count)
})
$btnLayerUpd.Add_Click({
    if (-not $script:SelTex) { return }
    $stack = Get-CurStack
    $idx = $script:EditLayerIdx
    if ($idx -lt 0 -or $idx -ge $stack.Count) { Set-Status 'Click a layer in the list first.'; return }
    $op = Get-PanelOp
    if ($op) { $stack[$idx] = $op }
    else {
        $trimmed = @()
        for ($i = 0; $i -lt $stack.Count; $i++) { if ($i -ne $idx) { $trimmed += ,$stack[$i] } }
        $stack = $trimmed; $script:EditLayerIdx = -1
    }
    Commit-Stack $stack
    Set-Status ('Layer {0} updated.' -f ($idx + 1))
})
$btnLayerDel.Add_Click({
    if (-not $script:SelTex) { return }
    $stack = Get-CurStack
    $idx = $script:EditLayerIdx
    if ($idx -lt 0 -or $idx -ge $stack.Count) { Set-Status 'Click a layer in the list first.'; return }
    $newStack = @()
    for ($i = 0; $i -lt $stack.Count; $i++) { if ($i -ne $idx) { $newStack += ,$stack[$i] } }
    $script:EditLayerIdx = -1
    $script:Loading = $true; Set-PanelFromOp $null; $script:Loading = $false
    Commit-Stack $newStack
    Set-Status 'Layer removed.'
})
$swapLayer = {
    param($delta)
    if (-not $script:SelTex) { return }
    $stack = Get-CurStack
    $idx = $script:EditLayerIdx
    $to = $idx + $delta
    if ($idx -lt 0 -or $idx -ge $stack.Count -or $to -lt 0 -or $to -ge $stack.Count) { return }
    $tmpOp = $stack[$idx]; $stack[$idx] = $stack[$to]; $stack[$to] = $tmpOp
    $script:EditLayerIdx = $to
    Commit-Stack $stack
}
$btnLayerUp.Add_Click({ & $swapLayer -1 })
$btnLayerDn.Add_Click({ & $swapLayer 1 })
$btnBulk.Add_Click({
    if (-not $script:CurSkin) { return }
    if (-not $rbRecolor.Checked) { [void][System.Windows.Forms.MessageBox]::Show('Pick a Recolor mode first - bulk apply pushes the current recolor to several textures at once.', 'Skin Studio'); return }
    $op = Get-PanelOp; if (-not $op) { return }
    $selItems = @($lvTex.SelectedItems)
    $targets = @()
    if ($selItems.Count -gt 1) {
        # explicit multi-selection wins: bulk exactly those (advanced unlocks tech maps)
        foreach ($it in $selItems) {
            $tex = $it.Tag
            if ($tex.Role -ne 'tech' -or $chkAdvanced.Checked) { $targets += $tex }
        }
        $prompt = 'Apply this recolor to the {0} selected texture(s)?' -f $targets.Count
    } else {
        $skipped = @{}
        foreach ($tex in @($script:TexItems | Where-Object Role -eq 'color')) {
            $cat = Get-BulkCat $tex.Rel
            if ($cat -eq 'hair' -and -not $chkBHair.Checked) { $skipped['hair'] = 1; continue }
            if ($cat -eq 'face' -and -not $chkBFace.Checked) { $skipped['face/eyes'] = 1; continue }
            if ($cat -eq 'props' -and -not $chkBProps.Checked) { $skipped['weapons/props'] = 1; continue }
            $targets += $tex
        }
        $skipTxt = ''
        if ($skipped.Count -gt 0) { $skipTxt = ' Skipping: ' + (($skipped.Keys | Sort-Object) -join ', ') + ' (untick/tick the boxes to change).' }
        $prompt = ('Apply this recolor to {0} color maps?{1}' -f $targets.Count, $skipTxt)
    }
    if ($targets.Count -eq 0) { Set-Status 'Nothing to bulk-apply with the current selection / category boxes.'; return }
    $ans = [System.Windows.Forms.MessageBox]::Show($prompt, 'Skin Studio', 'YesNo')
    if ($ans -ne 'Yes') { return }
    $frm.Cursor = 'WaitCursor'
    try {
        $ops = Get-Ops
        $done = 0
        foreach ($tex in $targets) {
            $ops[$tex.Rel] = ,($op.Clone())
            Refresh-Thumb $tex
            $done++
            if ($done % 5 -eq 0) { Set-Status ("bulk apply... {0}/{1}" -f $done, $targets.Count) }
        }
        # a category sweep already covers both halves of a linked pair; an
        # explicit multi-selection does not, so carry it across. SureOnly: a
        # bulk run is not the place to guess at a "possible" match, and the
        # tick box belongs to whatever texture happened to be selected.
        $mirrored = 0
        $chromaN = 0
        foreach ($tex in $targets) {
            $mirrored += (Mirror-ToLinked $tex.Rel $ops[$tex.Rel] -SureOnly)
            $chromaN += (Mirror-ToChromas $tex.Rel $ops[$tex.Rel])
        }
        $others = @($ops.Keys | Where-Object { $k = $_; -not ($targets | Where-Object { $_.Rel -eq $k }) }).Count
        $note = ''
        if ($mirrored -gt 0) { $note += " Carried onto {0} other version(s) of the same maps." -f $mirrored }
        if ($chromaN -gt 0) { $note += " Carried onto the recolor skins ({0} map(s))." -f $chromaN }
        if ($others -gt 0) { $note += " NOTE: {0} other texture(s) still carry earlier edits - revert them individually if unwanted." -f $others }
        Set-Status (('Bulk recolor applied to {0} texture(s).' -f $done) + $note)
    } finally { $frm.Cursor = 'Default' }
})

function Get-DesignPath { Join-Path $SS_Root ('designs\{0}.json' -f ($txtModName.Text -replace '[^A-Za-z0-9]', '')) }
function Refresh-DesignList {
    $keep = $cmbDesign.SelectedItem
    $cmbDesign.Items.Clear()
    Get-ChildItem (Join-Path $SS_Root 'designs') -Filter *.json -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$cmbDesign.Items.Add($_.BaseName) }
    if ($keep) { $i = $cmbDesign.Items.IndexOf($keep); if ($i -ge 0) { $cmbDesign.SelectedIndex = $i } }
}
# Designs made or changed IN GAME (the F8 panel's Designs, 2026-09-28) land in
# designs\ through the in-game helper's sync. Her ask: "when the app is
# installed i want the designs to update in the app too" - so the list follows
# the folder, and the design that is open reloads when the game changed it,
# unless there are edits here that were never saved (then it only says so).
$script:OpenDesign = ''; $script:OpenDesignTime = [DateTime]::MinValue; $script:OpenSnap = ''
function Get-EditSnap { try { (@{ o = $script:OpsBySkin; c = $script:ColorOpsBySkin } | ConvertTo-Json -Depth 10 -Compress) } catch { '' } }
function Remember-OpenDesign([string]$path) {
    $script:OpenDesign = $path
    $script:OpenDesignTime = if (Test-Path -LiteralPath $path) { (Get-Item -LiteralPath $path).LastWriteTimeUtc } else { [DateTime]::MinValue }
    $script:OpenSnap = Get-EditSnap
}
$script:DesignSig = ''
$script:DesignWatch = New-Object System.Windows.Forms.Timer
$script:DesignWatch.Interval = 2000
# "Open in App" from the F8 panel (2026-09-28): the in-game helper leaves the
# design's name in work\ingame\open_request.txt (or passes RS_SS_OPEN when it
# starts the app). Load it the way the Load button does and come to the front.
$script:OpenRequestFile = Join-Path $SS_Root 'work\ingame\open_request.txt'
function Open-DesignRequest([string]$key) {
    if (-not $key) { return }
    Refresh-DesignList
    $i = $cmbDesign.Items.IndexOf($key)
    if ($i -lt 0) { Set-Status ("The game asked for design '{0}', but it is not in designs\ yet." -f $key); return }
    $cmbDesign.SelectedIndex = $i
    $btnLoadD.GetType().GetMethod('OnClick', [Reflection.BindingFlags]'NonPublic,Instance').Invoke($btnLoadD, @([EventArgs]::Empty))
    if ($frm.WindowState -eq 'Minimized') { $frm.WindowState = 'Normal' }
    $frm.TopMost = $true; $frm.Activate(); $frm.TopMost = $false
    Set-Status ("Opened '{0}' from the game." -f $key)
}$script:DesignWatch.Add_Tick({
    try {
        if ([IO.File]::Exists($script:OpenRequestFile)) {
            $req = ([IO.File]::ReadAllText($script:OpenRequestFile)).Trim()
            [IO.File]::Delete($script:OpenRequestFile)
            Open-DesignRequest $req
        }
        $files = @(Get-ChildItem (Join-Path $SS_Root 'designs') -Filter *.json -File -ErrorAction SilentlyContinue)
        $sig = '{0}|{1}' -f $files.Count, (($files | ForEach-Object { $_.LastWriteTimeUtc.Ticks } | Measure-Object -Maximum).Maximum)
        if ($sig -eq $script:DesignSig) { return }
        $first = -not $script:DesignSig
        $script:DesignSig = $sig
        if ($first) { return }
        Refresh-DesignList
        $p = $script:OpenDesign
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { return }
        $now = (Get-Item -LiteralPath $p).LastWriteTimeUtc
        if ($now -le $script:OpenDesignTime) { return }
        $name = [IO.Path]::GetFileNameWithoutExtension($p)
        if ((Get-EditSnap) -ne $script:OpenSnap) {
            $script:OpenDesignTime = $now
            Set-Status ("'{0}' was changed in game - you have unsaved edits here, so it was not reloaded. Load it to take the game's version." -f $name)
            return
        }
        $i = $cmbDesign.Items.IndexOf($name)
        if ($i -ge 0) { $cmbDesign.SelectedIndex = $i; $btnLoadD.PerformClick(); Set-Status ("'{0}' was updated in game - reloaded." -f $name) }
    } catch {}
})
$script:DesignWatch.Start()
# ---- calibrate the recolour dyes -------------------------------------------
# A dyed zone renders ONE flat colour, and the colour sampled for it is an
# average of the whole region in the texture atlas - which covers more than is
# ever on screen, so the flat colour comes out diluted (Jubilee's shorts landed
# about half as warm as the costume's). No amount of sampling fixes it; the gap
# only exists in the render. This dialog walks the measurement:
#   1. build the METER - every dye white, so the recolor renders the LIGHTING
#   2. three screenshots in the same pose: costume, recolor, meter
#   3. solve -> the design's dyeCal, which every later build applies
# NB script-scoped control refs, not GetNewClosure: a closure gets its own
# module scope and cannot see $SS_Root or the skinlib functions (see the band
# picker, which is script-scoped for the same reason).
$script:dcBox = @{}
$script:dcOut = $null
$script:dcMeterLbl = $null
$script:dcForm = $null
function New-DyeCalForm {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Calibrate recolour colours'
    $f.ClientSize = New-Object System.Drawing.Size(640, 470)
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.StartPosition = 'CenterParent'; $f.BackColor = $Pal.Panel; $f.ForeColor = $Pal.Text
    $script:dcForm = $f

    $f.Controls.Add((New-Lbl 'WHY' 16 12 200))
    $why = New-Lbl 'A recolour paints each dyed part ONE flat colour, taken from the average of that zone in the texture atlas. The atlas holds more than you ever see, so that average lands duller and darker than the part on screen. This measures the difference in the game instead of guessing at it.' 16 32 608
    $why.Height = 56
    $f.Controls.Add($why)

    $f.Controls.Add((New-Lbl 'STEP 1  -  BUILD THE LIGHT METER' 16 96 400))
    $l1 = New-Lbl 'A copy of this mod with every recolour dye set to white. White paints nothing of its own, so the recolour renders the LIGHTING - which is what makes the sums work.' 16 116 608
    $l1.Height = 34
    $f.Controls.Add($l1)
    $btnMeter = New-Btn 'BUILD THE METER MOD' 16 154 220 26
    $f.Controls.Add($btnMeter)
    $script:dcMeterLbl = New-Lbl '' 246 160 378
    $f.Controls.Add($script:dcMeterLbl)

    $f.Controls.Add((New-Lbl 'STEP 2  -  THREE SCREENSHOTS, SAME POSE' 16 194 480))
    $l2 = New-Lbl 'In the hero gallery, same camera and pose every time: the costume, one recolour, and that same recolour again with the meter mod installed.' 16 214 608
    $l2.Height = 34
    $f.Controls.Add($l2)

    $script:dcBox = @{}
    $y = 252
    foreach ($r in @(@('Costume shot', 'costume'), @('Recolour shot', 'recolor'), @('Meter shot', 'meter'))) {
        $f.Controls.Add((New-Lbl $r[0] 16 ($y + 4) 110))
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point(130, $y)
        $tb.Size = New-Object System.Drawing.Size(410, 22)
        $tb.BackColor = $Pal.Sink; $tb.ForeColor = $Pal.Text; $tb.BorderStyle = 'FixedSingle'
        $f.Controls.Add($tb)
        $script:dcBox[$r[1]] = $tb
        $bb = New-Btn '...' 548 ($y - 1) 76 24
        $bb.Name = 'dcBrowse_' + $r[1]      # NOT .Tag - StyleTree reads Tag for its keep-* markers
        $bb.Add_Click({
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Filter = 'Screenshots (*.png;*.jpg)|*.png;*.jpg'
            $pics = [Environment]::GetFolderPath('MyPictures')
            foreach ($cand in @((Join-Path $pics 'Screenshots 1'), (Join-Path $pics 'Screenshots'), $pics)) {
                if (Test-Path -LiteralPath $cand) { $dlg.InitialDirectory = $cand; break }
            }
            if ($dlg.ShowDialog() -eq 'OK') { $script:dcBox[($this.Name -split '_')[1]].Text = $dlg.FileName }
        })
        $f.Controls.Add($bb)
        $y += 30
    }

    $f.Controls.Add((New-Lbl 'STEP 3  -  SOLVE' 16 348 300))
    $btnSolve = New-Btn 'MEASURE AND SAVE INTO THE DESIGN' 16 368 300 28
    MakePrimary $btnSolve | Out-Null
    $f.Controls.Add($btnSolve)
    $script:dcOut = New-Object System.Windows.Forms.TextBox
    $script:dcOut.Location = New-Object System.Drawing.Point(16, 402)
    $script:dcOut.Size = New-Object System.Drawing.Size(608, 54)
    $script:dcOut.Multiline = $true; $script:dcOut.ReadOnly = $true; $script:dcOut.ScrollBars = 'Vertical'
    $script:dcOut.BackColor = $Pal.Sink; $script:dcOut.ForeColor = $Pal.Text; $script:dcOut.BorderStyle = 'FixedSingle'
    $f.Controls.Add($script:dcOut)

    $btnMeter.Add_Click({
        $path = Save-Design
        if (-not $path) { $script:dcMeterLbl.Text = 'Name the mod and make an edit first.'; return }
        Start-Process powershell.exe -WorkingDirectory $SS_Root -ArgumentList @(
            '-NoExit', '-NoProfile', '-ExecutionPolicy', 'RemoteSigned',
            '-File', (Join-Path $SS_Root 'build_skin.ps1'), '-Design', $path,
            '-DyeMeter', '-Combined', '-Install', '-Zip', '-Version', 'meter')   # one throwaway install, not a mod to keep
        $script:dcMeterLbl.Text = 'Building in its own window. Install it, restart Rivals, then shoot the meter.'
    })

    $btnSolve.Add_Click({
        $path = Get-DesignPath
        if (-not (Test-Path -LiteralPath $path)) { $script:dcOut.Text = 'Save the design first.'; return }
        foreach ($k in 'costume', 'recolor', 'meter') {
            if (-not $script:dcBox[$k].Text -or -not (Test-Path -LiteralPath $script:dcBox[$k].Text)) {
                $script:dcOut.Text = "Pick the $k shot."; return
            }
        }
        $script:dcForm.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $script:dcOut.Text = 'Measuring...'
        [System.Windows.Forms.Application]::DoEvents()
        try {
            $res = SS-SolveDyeCal -DesignPath $path -CostumeShot $script:dcBox['costume'].Text `
                -RecolorShot $script:dcBox['recolor'].Text -MeterShot $script:dcBox['meter'].Text `
                -Progress { param($m) $script:dcOut.Text = $m; [System.Windows.Forms.Application]::DoEvents() }
            $script:dcOut.Text = (@(
                ('{0} zone(s) measured, {1} dye site(s) corrected. Build again and they are applied.' -f $res.groups, $res.sites)
                ('Zones that never showed on screen take x{0:N2} {1:N2} {2:N2}.' -f $res.fallback[0], $res.fallback[1], $res.fallback[2])
                ''
            ) + $res.rows) -join "`r`n"
            Set-Status ('Recolour calibration saved into the design ({0} zone(s) measured).' -f $res.groups)
        } catch {
            $script:dcOut.Text = 'Could not measure: ' + $_.Exception.Message
        } finally {
            $script:dcForm.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    })

    StyleTree $f
    $f
}
function Show-DyeCalDialog {
    if (-not $script:CurSkin) { Set-Status 'Open a skin first.'; return }
    $f = New-DyeCalForm
    [void]$f.ShowDialog($frm)
    $f.Dispose()
    $script:dcForm = $null
}
$btnDyeCal.Add_Click({ Show-DyeCalDialog })

function Save-Design {
    if (-not $script:CurSkin) { Set-Status 'Open a skin first.'; return $null }
    $modName = $txtModName.Text -replace '[^A-Za-z0-9]', ''
    if (-not $modName) { Set-Status 'Give the mod a name (letters/digits).'; return $null }
    # ops of the open skin PLUS any carried onto its recolor (chroma) skins. Every
    # rel carries its own skin id, so they live in one flat map and build_skin
    # groups them back by skin - one mod covers the costume and its recolors.
    $ops = @{}
    foreach ($kv in (Get-Ops).GetEnumerator()) { $ops[$kv.Key] = $kv.Value }
    $chromaSkins = @()
    if ($script:ChromaT) {
        foreach ($t in (@($script:ChromaT.Sure) + @($script:ChromaT.Maybe) | Sort-Object -Unique)) {
            if (-not $script:OpsBySkin.ContainsKey($t)) { continue }
            $tOps = $script:OpsBySkin[$t]
            if (@($tOps.Keys).Count -eq 0) { continue }
            foreach ($kv in $tOps.GetEnumerator()) { $ops[$kv.Key] = $kv.Value }
            $chromaSkins += $t
        }
    }
    # colorOps in state are rel -> @{ key -> edit }; the design JSON stores
    # rel -> @(edits) (what build_skin.ps1 reads).
    # the open skin's colour edits, plus the dye colours carried onto its recolors
    # (a chroma's colour is half material, so its textures alone would come out
    # re-tinted - see Mirror-DyeToChroma)
    $colorSets = @(Get-ColorOps)
    if ($script:ChromaT) {
        foreach ($t in (@($script:ChromaT.Sure) + @($script:ChromaT.Maybe) | Sort-Object -Unique)) {
            if ($script:ColorOpsBySkin.ContainsKey($t)) { $colorSets += $script:ColorOpsBySkin[$t] }
        }
    }
    $colorOut = [ordered]@{}
    foreach ($set in $colorSets) {
        foreach ($rel in ($set.Keys | Sort-Object)) {
            $arr = @(); foreach ($k in $set[$rel].Keys) { $arr += $set[$rel][$k] }
            if ($arr.Count -gt 0) { $colorOut[$rel] = $arr }
        }
    }
    if ($ops.Count -eq 0 -and $colorOut.Count -eq 0) { Set-Status 'No edits yet - recolor a texture or a material color first.'; return $null }
    $doc = [ordered]@{
        modName = $modName
        displayName = $txtDisplay.Text
        hero = $script:CurHero
        skin = $script:CurSkin
        chromaSkins = $chromaSkins        # recolor skins this design also edits (informational; ops carry their own ids)
        ops = $ops
        colorOps = $colorOut
    }
    $path = Get-DesignPath
    # carry the recolour calibration forward: it is measured in game, not
    # derived from anything in here, so a later save must not drop it
    if (Test-Path -LiteralPath $path) {
        try {
            $prev = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            if ($prev.PSObject.Properties['dyeCal'] -and $prev.dyeCal) { $doc['dyeCal'] = $prev.dyeCal }
        } catch {}
    }
    $doc | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
    Remember-OpenDesign $path
    Refresh-DesignList
    $cNote = if ($chromaSkins.Count) { ', {0} recolor skin(s)' -f $chromaSkins.Count } else { '' }
    Set-Status ('Design saved: designs\{0}.json ({1} texture edits{2}, {3} color edits)' -f $modName, $ops.Count, $cNote, (Count-ColorEdits))
    $path
}
$btnSaveD.Add_Click({
    if (-not (Save-Design)) { return }
    # Say whether this save reaches the game. With live preview off a save goes
    # nowhere, and until this nothing on screen said so. Also catches a watcher
    # that died while the button still read LIVE: ON.
    if (Test-LiveOn) {
        Set-Status 'Saved - sent to the game in a second or two. Press F6 (if Jubilee already changed this match, swap hero and back first).'
    } else {
        $btnLive.Text = 'LIVE PREVIEW'
        Set-Status 'Saved to disk - but LIVE PREVIEW is OFF, so the game will not see this. Click LIVE PREVIEW.'
    }
})
$btnLoadD.Add_Click({
    if (-not $cmbDesign.SelectedItem) { return }
    $path = Join-Path $SS_Root ('designs\{0}.json' -f $cmbDesign.SelectedItem)
    if (-not (Test-Path -LiteralPath $path)) { return }
    $doc = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $txtModName.Text = [string]$doc.modName
    $txtDisplay.Text = [string]$doc.displayName
    # select hero + skin in the lists, then open
    $txtSearch.Text = ''
    Refresh-HeroList
    for ($i = 0; $i -lt $lstHeroes.Items.Count; $i++) {
        if (((LabelId ([string]$lstHeroes.Items[$i])) -eq [string]$doc.hero)) { $lstHeroes.SelectedIndex = $i; break }
    }
    Refresh-SkinList
    for ($i = 0; $i -lt $lstSkins.Items.Count; $i++) {
        if (((LabelId ([string]$lstSkins.Items[$i])) -eq [string]$doc.skin)) { $lstSkins.SelectedIndex = $i; break }
    }
    # ops may belong to the costume AND to its recolor (chroma) skins - each rel
    # carries its skin id, so split them back into per-skin op sets
    $opsBySkin = @{}
    $rxSkin = [regex]'[\\/]Characters[\\/]\d{4}[\\/](\d{7})[\\/]'
    foreach ($p in $doc.ops.PSObject.Properties) {
        $stack = @()
        foreach ($layerRaw in (SS-OpLayers $p.Value)) {
            $o = @{}
            foreach ($q in $layerRaw.PSObject.Properties) { $o[$q.Name] = $q.Value }
            $stack += ,$o
        }
        if ($stack.Count -eq 0) { continue }
        $m = $rxSkin.Match($p.Name)
        $owner = if ($m.Success) { $m.Groups[1].Value } else { [string]$doc.skin }
        if (-not $opsBySkin.ContainsKey($owner)) { $opsBySkin[$owner] = @{} }
        $opsBySkin[$owner][$p.Name] = $stack
    }
    foreach ($k in $opsBySkin.Keys) { $script:OpsBySkin[$k] = $opsBySkin[$k] }
    if (-not $opsBySkin.ContainsKey([string]$doc.skin)) { $script:OpsBySkin[[string]$doc.skin] = @{} }
    # restore color edits: rel -> @(edits) back into rel -> @{ "<exp>_<ord>" -> edit }
    # colour edits split by skin as well: the dye colours of a recolor skin live
    # under its own material rels
    $colorBySkin = @{}
    if ($doc.PSObject.Properties['colorOps']) {
        foreach ($p in $doc.colorOps.PSObject.Properties) {
            $inner = @{}
            foreach ($e in @($p.Value)) {
                $edit = @{ export = [int]$e.export; ordinal = [int]$e.ordinal; name = [string]$e.name; r = [double]$e.r; g = [double]$e.g; b = [double]$e.b }
                if ($e.PSObject.Properties['a'] -and $null -ne $e.a) { $edit.a = [double]$e.a }
                if ($e.PSObject.Properties['kind'] -and $e.kind) { $edit.kind = [string]$e.kind }
                if ($e.PSObject.Properties['viaChroma'] -and $e.viaChroma) { $edit.viaChroma = $true }
                $inner['{0}_{1}' -f $e.export, $e.ordinal] = $edit
            }
            if ($inner.Count -eq 0) { continue }
            $m = $rxSkin.Match([string]$p.Name)
            $owner = if ($m.Success) { $m.Groups[1].Value } else { [string]$doc.skin }
            if (-not $colorBySkin.ContainsKey($owner)) { $colorBySkin[$owner] = @{} }
            $colorBySkin[$owner][[string]$p.Name] = $inner
        }
    }
    foreach ($k in $colorBySkin.Keys) { $script:ColorOpsBySkin[$k] = $colorBySkin[$k] }
    if (-not $colorBySkin.ContainsKey([string]$doc.skin)) { $script:ColorOpsBySkin[[string]$doc.skin] = @{} }
    Open-Skin ([string]$doc.skin)
    Remember-OpenDesign $path
})

# ---- Blender bridge ---------------------------------------------------------
function Find-SkinGltf([switch]$NoDecode) {
    if (-not $script:CurSkin) { return $null }
    # Not 'SK_<hero>_<skin>*': the mesh is often named for the CHUNK, not the
    # hero - White Fox 1060500 ships as SK_10600_1060500_Lobby (and the spirit
    # form as SK_10601_1060500), which the old pattern missed entirely, so both
    # this and OPEN IN BLENDER reported "no mesh export" for her.
    $hits = @()
    foreach ($fmRoot in $SS_FmRoots) {
        $hits += @(Get-ChildItem $fmRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -like "SK_*$($script:CurSkin)*" -and $_.Extension -in '.gltf', '.glb' })
    }
    if ($hits.Count -eq 0) {
        # no FModel export: decode it ourselves with Atelier's AtelierMesh
        # (~10 s once per skin, cached in cache\<skin>\mesh\). -NoDecode is the
        # FModel wait-timer's cheap poll, which must never block for 10 s.
        if ($NoDecode -or -not (SS-AtelierMeshAvailable)) { return $null }
        $frm.Cursor = 'WaitCursor'
        try {
            $g = @(SS-EnsureMesh $script:CurSkin -Lobby -Progress { param($m) Set-Status $m })
            if ($g.Count -eq 0) { $g = @(SS-EnsureMesh $script:CurSkin -Progress { param($m) Set-Status $m }) }
            return $g[0]
        } catch {
            Set-Status ('automatic mesh export failed ({0}) - falling back to FModel' -f $_.Exception.Message)
            return $null
        } finally { $frm.Cursor = 'Default' }
    }
    $lobby = $hits | Where-Object BaseName -like '*_Lobby' | Select-Object -First 1
    if ($lobby) { return $lobby.FullName }
    ($hits | Select-Object -First 1).FullName
}
function Get-BlendTexDir { Join-Path $SS_Root ('blender\tex\{0}' -f $script:CurSkin) }
function Bake-And-LaunchBlender {
    $gltf = Find-SkinGltf
    if (-not $gltf) { return $false }
    $texDir = Get-BlendTexDir
    Set-Status 'baking design textures for Blender...'
    $frm.Cursor = 'WaitCursor'
    try {
        $bakeStats = SS-BakeBlenderTex $script:CurCk (Get-Ops) $texDir { param($m) Set-Status $m }
    } finally { $frm.Cursor = 'Default' }
    $editDir = Join-Path $SS_Root ('work\edit\{0}' -f $script:CurSkin)
    New-Item -ItemType Directory -Force -Path $editDir | Out-Null
    $bArgs = @('--python', (Join-Path $SS_Root 'blender\bridge.py'), '--',
        '--gltf', $gltf, '--texdir', $texDir, '--editdir', $editDir, '--skin', $script:CurSkin)
    Start-Process -FilePath $SS_Blender -ArgumentList $bArgs
    Set-Status ('Blender launching: {0} color maps baked ({1} with your edits). Sidebar > "Skin Studio" tab has reload/send-paint.' -f $bakeStats.total, $bakeStats.baked)
    $true
}
# ---- 3D preview -------------------------------------------------------------
# One window, rebuilt incrementally: SS-BuildViewScene re-bakes only the maps
# whose op stack changed, then the page swaps just those textures. A timer
# watches the design's signature so APPLY / revert / colour edits show up
# without any extra click.
function Get-ViewSig {
    $co = $null
    if ($script:ColorOpsBySkin -and $script:ColorOpsBySkin.ContainsKey($script:CurSkin)) { $co = $script:ColorOpsBySkin[$script:CurSkin] }
    '{0}|{1}|{2}' -f $script:CurSkin, ((Get-Ops) | ConvertTo-Json -Depth 12 -Compress), ($co | ConvertTo-Json -Depth 6 -Compress)
}
function Update-3DPreview([switch]$Open) {
    if (-not $script:CurSkin) { Set-Status 'Open a skin first.'; return }
    if (-not $Open -and -not $script:SS_ViewForm) { return }
    if (-not (SS-AtelierMeshAvailable)) { Set-Status "The 3D preview needs Atelier's mesh decoder ($SS_AtelierMesh)."; return }
    # Set-Status pumps messages, so the timer can fire mid-rebuild - never nest
    if ($script:ViewBusy) { return }
    $script:ViewBusy = $true
    $co = $null
    if ($script:ColorOpsBySkin -and $script:ColorOpsBySkin.ContainsKey($script:CurSkin)) { $co = $script:ColorOpsBySkin[$script:CurSkin] }
    $script:ViewSig = Get-ViewSig
    $frm.Cursor = 'WaitCursor'
    try {
        $title = 'Skin Studio 3D - {0}' -f $script:CurSkin
        $url = SS-BuildViewScene $script:CurSkin (Get-Ops) $co $script:CurSkin { param($m) Set-Status $m }
        # smoke runs keep the window off-screen and unowned (the studio form
        # itself is never shown there)
        if ($env:RS_SS_SMOKE) { [void](Show-3DPreview $url $null $title -Headless) }
        else { [void](Show-3DPreview $url $frm $title) }
    } catch {
        Set-Status ('3D preview failed: {0}' -f $_.Exception.Message)
    } finally { $frm.Cursor = 'Default'; $script:ViewBusy = $false }
}
$btn3D.Add_Click({ Update-3DPreview -Open })
$script:ViewTimer = New-Object System.Windows.Forms.Timer
$script:ViewTimer.Interval = 1500
$script:ViewTimer.Add_Tick({
    if (-not $script:SS_ViewForm -or -not $script:CurSkin -or $script:ViewBusy) { return }
    $sig = Get-ViewSig
    if ($sig -ne $script:ViewSig) { Update-3DPreview }
})
$script:ViewTimer.Start()

# ---- Atelier round-trip -----------------------------------------------------
# import: an Atelier project becomes a design (only what differs from vanilla);
# export: the current design becomes a NEW Atelier project. Both verified
# lossless on Toasty Jubilee (23 layers byte-identical, 248/248 colours exact).
function Show-AtelierImportDialog {
    $projs = @(SS-AtelierProjectList)
    if ($projs.Count -eq 0) { Set-Status "No Atelier projects found in $SS_AtelierProjects"; return }
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Import an Atelier project'
    $d.Size = New-Object System.Drawing.Size(560, 360)
    $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.BackColor = $Pal.Bg; $d.ForeColor = $colFore
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.HideSelection = $false; $lv.MultiSelect = $false
    $lv.Location = New-Object System.Drawing.Point(14, 14); $lv.Size = New-Object System.Drawing.Size(516, 200)
    $lv.BackColor = $colField; $lv.ForeColor = $colFore; $lv.BorderStyle = 'FixedSingle'
    [void]$lv.Columns.Add('Project', 200); [void]$lv.Columns.Add('Skins', 150); [void]$lv.Columns.Add('Maps', 60); [void]$lv.Columns.Add('Materials', 80)
    foreach ($p in $projs) {
        $it = New-Object System.Windows.Forms.ListViewItem($p.Name)
        [void]$it.SubItems.Add(($p.Skins -join ', ')); [void]$it.SubItems.Add([string]$p.Textures); [void]$it.SubItems.Add([string]$p.Materials)
        $it.Tag = $p
        [void]$lv.Items.Add($it)
    }
    $d.Controls.Add($lv)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = 'Design name (letters/digits)'; $lbl.Location = New-Object System.Drawing.Point(14, 226); $lbl.AutoSize = $true
    $d.Controls.Add($lbl)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(14, 246); $txt.Width = 250
    $txt.BackColor = $colField; $txt.ForeColor = $colFore; $txt.BorderStyle = 'FixedSingle'
    $d.Controls.Add($txt)
    $lv.Add_SelectedIndexChanged({ if ($lv.SelectedItems.Count) { $txt.Text = ($lv.SelectedItems[0].Text -replace '[^A-Za-z0-9]', '') } })
    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'Only what differs from vanilla comes across. Edited PNGs are copied into imports\ so later changes in Atelier do not alter this design.'
    $note.Location = New-Object System.Drawing.Point(280, 226); $note.Size = New-Object System.Drawing.Size(250, 48); $note.ForeColor = $Pal.Muted
    $d.Controls.Add($note)
    $ok = New-Btn 'IMPORT' 330 282 96 30; $d.Controls.Add($ok)
    $cancel = New-Btn 'cancel' 434 282 96 30; $d.Controls.Add($cancel)
    $cancel.Add_Click({ $d.Close() })
    $ok.Add_Click({
        if (-not $lv.SelectedItems.Count) { [void][System.Windows.Forms.MessageBox]::Show('Pick a project first.', 'Import'); return }
        $name = $txt.Text -replace '[^A-Za-z0-9]', ''
        if (-not $name) { [void][System.Windows.Forms.MessageBox]::Show('Give the design a name.', 'Import'); return }
        $dest = Join-Path $SS_Root "designs\$name.json"
        if ((Test-Path -LiteralPath $dest) -and [System.Windows.Forms.MessageBox]::Show("designs\$name.json already exists. Replace it?", 'Import', 'YesNo') -ne 'Yes') { return }
        $proj = $lv.SelectedItems[0].Tag
        $d.Cursor = 'WaitCursor'
        try {
            $r = SS-ImportAtelierProject $proj.Dir $name $null { param($m) Set-Status $m }
        } catch {
            $d.Cursor = 'Default'
            [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Import failed'); return
        }
        $d.Cursor = 'Default'
        $d.Close()
        Refresh-DesignList
        $i = $cmbDesign.Items.IndexOf($name); if ($i -ge 0) { $cmbDesign.SelectedIndex = $i; $btnLoadD.PerformClick() }
        $msg = @(
            ('Imported "{0}" as designs\{1}.json' -f $r.project, $name)
            ''
            ('  {0} edited texture(s)   ({1} untouched copies skipped)' -f $r.texEdited, $r.texSame)
            ('  {0} material colour(s) from {1} material file(s)' -f $r.colours, $r.materialsRead)
            ('  skins: {0}' -f ($r.skins -join ', '))
        )
        if (@($r.skippedParams).Count) {
            $msg += ''; $msg += 'NOT carried - these changed values are not colours (packed settings Atelier shows as colours):'
            $msg += @($r.skippedParams | Select-Object -First 8 | ForEach-Object { '  ' + $_ })
        }
        if (@($r.texNoVanilla).Count) { $msg += ''; $msg += ('{0} texture(s) have no vanilla match in this game version and were skipped.' -f @($r.texNoVanilla).Count) }
        [void][System.Windows.Forms.MessageBox]::Show(($msg -join [Environment]::NewLine), 'Atelier import')
    })
    [void]$d.ShowDialog($frm)
    $d.Dispose()
}
$btnAtImport.Add_Click({ Show-AtelierImportDialog })
$btnAtExport.Add_Click({
    if (-not $script:CurSkin) { Set-Status 'Open a skin (or load a design) first.'; return }
    $path = Save-Design
    if (-not $path) { return }
    $def = if ($txtDisplay.Text) { $txtDisplay.Text } else { $txtModName.Text }
    $name = [Microsoft.VisualBasic.Interaction]::InputBox("Name for the new Atelier project.`n`nSkin Studio makes a NEW project and never overwrites an existing one.", 'Export to Atelier', $def)
    if (-not $name) { return }
    $frm.Cursor = 'WaitCursor'
    try {
        $r = SS-ExportAtelierProject $path $name $null { param($m) Set-Status $m }
        Set-Status ('Exported to Atelier: {0} texture(s), {1} material(s) -> {2}' -f $r.textures, $r.materials, $r.project)
        [void][System.Windows.Forms.MessageBox]::Show((@(
            ('Atelier project "{0}" is ready: {1} texture(s), {2} material(s).' -f (Split-Path $r.project -Leaf), $r.textures, $r.materials)
            ''
            'In Atelier: Back to Projects, then open it (restart Atelier if it was already open).'
            $(if (@($r.skipped).Count) { "`n{0} item(s) could not be exported (not in the current game data)." -f @($r.skipped).Count } else { '' })
        ) -join [Environment]::NewLine), 'Export to Atelier')
    } catch {
        Set-Status ('Export to Atelier failed: {0}' -f $_.Exception.Message)
        [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Export to Atelier failed')
    } finally { $frm.Cursor = 'Default' }
})

$script:FmTimer = New-Object System.Windows.Forms.Timer
$script:FmTimer.Interval = 3000
$script:FmTimer.Add_Tick({
    if (Find-SkinGltf -NoDecode) {
        $script:FmTimer.Stop()
        [void](Bake-And-LaunchBlender)
    }
})
$btnBlender.Add_Click({
    if (-not $script:CurSkin) { Set-Status 'Open a skin first.'; return }
    if (-not (Test-Path $SS_Blender)) { Set-Status "Blender not found at $SS_Blender"; return }
    if (Bake-And-LaunchBlender) { return }
    # no exported mesh yet: guide through the one-time FModel export, then auto-continue
    if (-not (Test-Path $SS_FModel)) { Set-Status "FModel not found at $SS_FModel"; return }
    # FModel only saves settings on exit - repair ours while it is closed
    if (-not (Get-Process -Name FModel -ErrorAction SilentlyContinue)) {
        try { & (Join-Path $SS_Root 'blender\fix_fmodel_settings.ps1') | Out-Null } catch {}
    }
    Start-Process -FilePath $SS_FModel -WorkingDirectory (Split-Path $SS_FModel -Parent)
    $meshPath = 'Marvel/Content/Marvel/Characters/{0}/{1}/Meshes' -f $script:CurHero, $script:CurSkin
    $meshName = 'SK_{0}_{1}_Lobby' -f $script:CurHero, $script:CurSkin
    [System.Windows.Forms.Clipboard]::SetText($meshName)
    [void][System.Windows.Forms.MessageBox]::Show((@(
        'One-time mesh export via FModel (just opened):'
        ''
        '  1. Pick the Marvel Rivals directory and press LOAD (top bar) -'
        '     the archive list fills in; give it a moment.'
        ('  2. In the folder tree go to  ' + $meshPath)
        ('     (or just search for  ' + $meshName + '  - the name is on your clipboard).')
        ('  3. Right-click  ' + $meshName + '  and hit "Save Model".')
        ''
        'Skin Studio is watching the export folders - Blender opens by itself once the mesh lands.'
        ''
        'If folders come up empty or models refuse to save, close FModel and reopen it:'
        'Skin Studio auto-repairs its settings (AES key, mappings, glTF format) whenever it closes.'
    ) -join [Environment]::NewLine), 'Skin Studio - export the mesh once')
    Set-Status 'waiting for the FModel mesh export... (auto-continues)'
    $script:FmTimer.Start()
})
$btnBlendRefresh.Add_Click({
    if (-not $script:CurSkin) { return }
    $texDir = Get-BlendTexDir
    if (-not (Test-Path $texDir)) { Set-Status 'No Blender session for this skin yet - use OPEN IN BLENDER first.'; return }
    # a rebake overwrites every file - do not clobber paint that has not been imported
    $stampFile = Join-Path $texDir '_bake.stamp'
    if (Test-Path -LiteralPath $stampFile) {
        $stamp = New-Object DateTime ([long](Get-Content -LiteralPath $stampFile -Raw).Trim()), ([DateTimeKind]::Utc)
        $painted = @(Get-ChildItem $texDir -Filter *.png -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -gt $stamp.AddSeconds(5) })
        if ($painted.Count -gt 0) {
            Set-Status ('STOP: {0} painted texture(s) not imported yet - click "import painted textures" first, then refresh.' -f $painted.Count)
            return
        }
    }
    $frm.Cursor = 'WaitCursor'
    try { $bakeStats = SS-BakeBlenderTex $script:CurCk (Get-Ops) $texDir { param($m) Set-Status $m } }
    finally { $frm.Cursor = 'Default' }
    Set-Status ('Rebaked {0} textures ({1} with edits). In Blender: sidebar > Skin Studio > "Reload textures".' -f $bakeStats.total, $bakeStats.baked)
})
$btnPaintId.Add_Click({ Show-PaintId })
$btnBlendPull.Add_Click({
    if (-not $script:CurSkin) { return }
    $editDir = Join-Path $SS_Root ('work\edit\{0}' -f $script:CurSkin)
    New-Item -ItemType Directory -Force -Path $editDir | Out-Null
    # source 1: paint saved straight into the bake dir (Blender Image>Save or
    # the Send button) - anything newer than the bake stamp is hers
    $texDir = Get-BlendTexDir
    $stampFile = Join-Path $texDir '_bake.stamp'
    if (Test-Path -LiteralPath $stampFile) {
        $stamp = New-Object DateTime ([long](Get-Content -LiteralPath $stampFile -Raw).Trim()), ([DateTimeKind]::Utc)
        Get-ChildItem $texDir -Filter *.png -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -gt $stamp.AddSeconds(5) } |
            ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $editDir $_.Name) -Force }
    }
    # source 2: the exact list Blender reported; fall back to every PNG present
    $files = @()
    $sessionFile = Join-Path $editDir '_blender_session.json'
    if (Test-Path -LiteralPath $sessionFile) {
        $session = Get-Content -LiteralPath $sessionFile -Raw | ConvertFrom-Json
        foreach ($name in @($session.sent)) {
            $fp = Join-Path $editDir $name
            if (Test-Path -LiteralPath $fp) { $files += (Get-Item -LiteralPath $fp) }
        }
    }
    if ($files.Count -eq 0) { $files = @(Get-ChildItem $editDir -Filter *.png -ErrorAction SilentlyContinue) }
    if ($files.Count -eq 0) { Set-Status 'No painted textures found yet - in Blender: sidebar (N) > Skin Studio tab > "Send paint to Skin Studio" (while Blender is still open).'; return }
    $ops = Get-Ops
    $matched = 0
    foreach ($f in $files) {
        $tex = $script:TexItems | Where-Object { (Split-Path $_.Rel -Leaf) -eq $f.Name } | Select-Object -First 1
        if (-not $tex) { continue }
        $ops[$tex.Rel] = ,@{ mode = 'edited'; file = $f.FullName; strength = 1.0 }
        Refresh-Thumb $tex
        $matched++
    }
    Show-Preview
    Set-Status ('Imported {0} painted texture(s) as hand-edited layers. They replace any recolor stack on those textures.' -f $matched)
})

$btnClearMods.Add_Click({
    # every mod THIS studio built = design names + work dirs; remove exactly
    # those triplets from ~mods. Theme Studio / Vortex mods are never touched.
    $modsDir = Join-Path $SS_Paks '~mods'
    $names = New-Object 'System.Collections.Generic.HashSet[string]'
    Get-ChildItem (Join-Path $SS_Root 'designs') -Filter *.json -ErrorAction SilentlyContinue | ForEach-Object { [void]$names.Add($_.BaseName) }
    Get-ChildItem (Join-Path $SS_Root 'work') -Directory -ErrorAction SilentlyContinue | ForEach-Object { [void]$names.Add($_.Name) }
    $targets = @()
    foreach ($nm in $names) {
        foreach ($ext in '.pak', '.utoc', '.ucas') {
            $f = Join-Path $modsDir ('{0}_9999999_P{1}' -f $nm, $ext)
            if (Test-Path -LiteralPath $f) { $targets += (Get-Item -LiteralPath $f) }
        }
    }
    if ($targets.Count -eq 0) { Set-Status 'No Skin Studio mods are installed in ~mods right now.'; return }
    if (SS-GameRunning) { Set-Status 'Close Marvel Rivals first - installed paks are locked while it runs.'; return }
    $modNames = @($targets | ForEach-Object { $_.BaseName -replace '_9999999_P$', '' } | Sort-Object -Unique)
    $ans = [System.Windows.Forms.MessageBox]::Show((@(
        ('Remove {0} installed skin mod(s) from the game?' -f $modNames.Count)
        ''
        ($modNames -join ', ')
        ''
        'Designs, builds and zips are all kept - hitting BUILD on any design reinstalls it.'
    ) -join [Environment]::NewLine), 'Skin Studio', 'YesNo')
    if ($ans -ne 'Yes') { return }
    $removed = 0
    foreach ($f in $targets) {
        try { Remove-Item -LiteralPath $f.FullName -Force; $removed++ }
        catch { Set-Status ('could not remove {0}: {1}' -f $f.Name, $_.Exception.Message); return }
    }
    Set-Status ('Removed {0} mod(s) ({1} files): {2}. Restart the game for vanilla skins.' -f $modNames.Count, $removed, ($modNames -join ', '))
})

$btnBuild.Add_Click({
    # Last line of defence against the "it didn't fully change" bug: an edited
    # map whose certain twin in this skin was left vanilla. Catches designs
    # saved before the ⇄ box existed, and anything reverted by hand. Only
    # CERTAIN links are offered - a "possible" match is a judgement call and
    # belongs to the tick box, not to a build prompt.
    $gaps = @()
    $ops = Get-Ops
    foreach ($rel in @($ops.Keys)) {
        $lk = $script:Links[$rel]
        if (-not $lk -or -not $lk.Sure) { continue }
        foreach ($t in @($lk.Others)) {
            if ($t -and -not $ops.ContainsKey($t) -and $gaps -notcontains $t) { $gaps += $t }
        }
    }
    if ($gaps.Count) {
        $names = ($gaps | ForEach-Object { '  ' + [IO.Path]::GetFileNameWithoutExtension($_) }) -join "`r`n"
        $ans = [System.Windows.Forms.MessageBox]::Show((@(
            "{0} map(s) you edited have another version in this skin that is still vanilla:" -f $gaps.Count
            ''
            $names
            ''
            'Those are the same artwork under a second name - a different character form, or a lobby copy - so in game the mod would only half-change.'
            ''
            'Copy the same layers onto them before building?'
        ) -join "`r`n"), 'Skin Studio', 'YesNoCancel', 'Warning')
        if ($ans -eq 'Cancel') { return }
        if ($ans -eq 'Yes') {
            foreach ($rel in @($ops.Keys)) { [void](Mirror-ToLinked $rel $ops[$rel] -SureOnly) }
            [void](Sync-ChromaOps)      # the maps just filled in must reach the recolors too
            Set-Status ('Filled in {0} matching map(s). Building...' -f $gaps.Count)
        }
    }
    # Colour ops are validated against the real parameter list before they can
    # ship. A design saved before the vector/HDR rules existed can carry edits to
    # directions, positions and shading ramps, and those break the skin in game -
    # so load the list (cheap, cached) and prune rather than trusting the file.
    if ((Get-ColorOps).Count -gt 0) {
        Load-ColorItems 'mat'
        $gone = Prune-BadColorOps
        if ($gone -gt 0) {
            [void][System.Windows.Forms.MessageBox]::Show((@(
                "Dropped {0} colour edit(s) from this design before building." -f $gone
                ''
                'They pointed at things stored as colours but which are not colours - light directions, positions, tangents, HDR values, shading ramps. A colour picker clamps those into 0-1 and the material comes out broken in game.'
                ''
                'The rest of the design is untouched.'
            ) -join "`r`n"), 'Skin Studio', 'OK', 'Warning')
        }
    }
    $path = Save-Design
    if (-not $path) { return }
    $buildArgs = @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', (Join-Path $SS_Root 'build_skin.ps1'), '-Design', $path)
    if ($chkInstall.Checked) { $buildArgs += '-Install' }
    if ($chkZip.Checked) { $buildArgs += '-Zip' }
    Start-Process powershell.exe -ArgumentList $buildArgs -WorkingDirectory $SS_Root
    # a costume and its recolours ALWAYS come out as one mod per skin (her rule,
    # 2026-09-22) - build_skin does the split itself; this only says so
    $nMods = 1
    try { $nMods = @(SS-SplitDesignBySkin (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)).Count } catch {}
    $modsNote = if ($nMods -gt 1) { ' It makes {0} mods, one per skin.' -f $nMods } else { '' }
    # Rivals running with Project Galacta: the build window swaps it in through
    # Galacta's F7 unload / reload - no restart
    $galOn = $false
    if ($chkInstall.Checked -and (SS-GameRunning)) { try { $galOn = (SS-GalactaInfo).Installed } catch {} }
    if ($galOn) {
        Set-Status ('Build launched in its own window.{0} Rivals is running with Project Galacta: when that window asks, press F7 in game, then F7 again - no restart.' -f $modsNote)
    } else {
        Set-Status ('Build launched in its own window - watch it there.{0} Paks mount at game BOOT, so restart Rivals after install.' -f $modsNote)
    }
})

# ---- live preview -----------------------------------------------------------
# live_preview.ps1 runs as its own process on purpose: it dot-sources skinlib and
# Add-Types SkinArt, and both are already loaded in here - a second Add-Type of
# the same type throws. It also keeps the long -Watch loop off the UI thread.
$script:LiveProc = $null
# LIVE PREVIEW is STICKY across restarts. Closing the studio still kills the
# watcher (no orphan process writing into the game folder), but it leaves this
# flag behind and the next start resumes it. Without that, reopening the studio
# silently turned live preview off and every later save went nowhere - which
# looks exactly like "save design does not change the skin in game" (hit on
# 2026-09-22). Only the LIVE PREVIEW button turning it off removes the flag.
$script:LiveFlag = Join-Path $SS_Root 'work\live_preview.on'
# 2026-09-27: the in-game panel has the same button, and the in-game helper
# (ingame\helper.ps1) runs a watcher with no window while Rivals is up, so the
# app is not needed to play. The flag file is the one truth for "on", and one
# watcher runs at a time (ingame\livestate.ps1) - this window's, or the helper's.
. (Join-Path $SS_Root 'ingame\livestate.ps1')
function Test-OwnWatcher { [bool]($script:LiveProc -and -not $script:LiveProc.HasExited) }
function Test-LiveOn { (LS-FlagOn $script:LiveFlag) -and ((Test-OwnWatcher) -or (LS-WatcherAlive '')) }
# the watcher's "Skin Studio is listening" flag for the in-game mod (it writes
# SkinLiveOn.sav at start): with it gone, the game stops announcing each hero
# it spawns as, so a game played without the app writes nothing
function Clear-LiveOnFlag {
    $f = Join-Path $env:LOCALAPPDATA 'Marvel\Saved\SaveGames\SkinLiveOn.sav'
    try { if (Test-Path -LiteralPath $f) { [IO.File]::Delete($f) } } catch {}
}
function Start-LiveWatcher {
    # -WatchDesigns, not -Design <path> -Watch: it follows whichever design was
    # saved last, so opening another one and saving switches the preview to it.
    # Locking onto one design instead meant working on a second one silently left
    # the game showing the first.
    # The flag goes first: a watcher reads it at start to know it is on.
    try { LS-SetFlag $true $script:LiveFlag } catch {}
    $btnLive.Text = 'LIVE: ON  (stop)'
    # the in-game helper's watcher is already running: it sees the flag and
    # turns on by itself - a second watcher would only stop at once
    if ((Test-OwnWatcher) -or (LS-WatcherAlive '')) { return }
    $script:LiveProc = Start-Process powershell.exe -PassThru -WorkingDirectory $SS_Root -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'RemoteSigned',
        '-File', (Join-Path $SS_Root 'live_preview.ps1'), '-WatchDesigns')
}
$btnLive.Add_Click({
    if (Test-LiveOn) {
        $own = Test-OwnWatcher
        if ($own) { try { $script:LiveProc.Kill(); $null = $script:LiveProc.WaitForExit(3000) } catch {} }
        $script:LiveProc = $null
        try { LS-SetFlag $false $script:LiveFlag } catch {}
        if (-not $own -and (LS-WatcherAlive '')) {
            # the in-game helper's watcher (no window): it sees the flag go,
            # writes the vanilla textures back itself and has the game re-import
            # them - running -Clear here too would race it over the same files
            $btnLive.Text = 'LIVE PREVIEW'
            Set-Status 'Live preview off - the game puts your hero back to its own skin in a moment.'
            return
        }
        Clear-LiveOnFlag
        # -Clear WRITES the vanilla textures back rather than deleting the PNGs -
        # deleting cannot undo a preview already showing in game, since a missing
        # file just means "not edited" and the game keeps what it loaded. So this
        # renders, and takes a second or two; say so before it blocks.
        Set-Status 'Turning live preview off - writing the vanilla textures back...'
        Start-Process powershell.exe -WindowStyle Hidden -Wait -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'RemoteSigned',
            '-File', (Join-Path $SS_Root 'live_preview.ps1'), '-Clear')
        $btnLive.Text = 'LIVE PREVIEW'
        Set-Status 'Live preview off - press F6 in game once more to go back to vanilla.'
        return
    }
    # saving is what makes THIS design the newest, which is how -WatchDesigns
    # picks it up - the returned path is not passed on, only the save matters
    if (-not (Save-Design)) { return }
    Start-LiveWatcher
    Set-Status 'Live preview on - save any design and it goes live. Press F6 in game (in a match) to see it.'
})
# closing the studio must not leave a watcher writing into the game folder -
# but the flag stays, so the next start picks live preview back up
# (only this window's watcher: the in-game helper's keeps serving the game, and
# if this one goes while Rivals runs with live preview on, the helper starts its
# own within a second or two)
$frm.Add_FormClosing({ if (Test-OwnWatcher) { try { $script:LiveProc.Kill() } catch {}; Clear-LiveOnFlag } })
$frm.Add_Shown({
    if ($env:RS_SS_SMOKE) { return }     # never launch a watcher from a test render
    # the in-game helper, in case Windows did not start it at sign-in
    try { if (LS-StartHelper) { Write-Host 'started the in-game helper' } } catch {}
    if (Test-Path -LiteralPath $script:LiveFlag) {
        Start-LiveWatcher
        Set-Status 'Live preview resumed (it was on when the studio last closed) - save a design, then F6 in game.'
    }
})
# the in-game button flips live preview too: keep this one's label honest
$script:LiveUiTimer = New-Object System.Windows.Forms.Timer
$script:LiveUiTimer.Interval = 2000
$script:LiveUiTimer.Add_Tick({
    $want = if (Test-LiveOn) { 'LIVE: ON  (stop)' } else { 'LIVE PREVIEW' }
    if ($btnLive.Text -ne $want) { $btnLive.Text = $want }
})
$script:LiveUiTimer.Start()
# ---- the look, in one pass --------------------------------------------------
# Most of this file's controls never named a colour - they inherited whatever
# WinForms gave them. StyleTree walks the whole tree once, here at the end of
# construction, and dresses every one by type; it also rounds the buttons, so it
# has to run AFTER the pass that gave each its final BackColor. Opt-outs are
# tagged 'keep-...' (the colour swatches, the sage primaries, the cards).
StyleTree $frm
# the title bar, the border and the list scrollbars are non-client: nothing in
# StyleTree can reach them, and both need a window handle, so they wait for Shown
$frm.Add_Shown({ DarkCaption $frm })
$frm.Add_Shown({ try { DarkScrollbars $frm } catch {} })

# ---- boot -------------------------------------------------------------------
Refresh-HeroList
Refresh-DesignList
Refresh-OpPanelEnabled
# started by the helper for an in-game Open in App
if ($env:RS_SS_OPEN) { $frm.Add_Shown({ Open-DesignRequest $env:RS_SS_OPEN }) }
Update-OpControlVis
Set-Mode 'tex'
if ($env:RS_SS_SMOKE -eq '15') {
    # render the window to a PNG without showing it (RS_SS_SHOT=<path>), so a
    # layout change can be LOOKED at, not just measured. Owner-drawn controls
    # (VuiSlider / VuiCombo) come out plain here - that is a WM_PRINT limitation,
    # not a bug in the layout.
    $out = if ($env:RS_SS_SHOT) { $env:RS_SS_SHOT } else { Join-Path $SS_Root 'work\_shot.png' }
    New-Item -ItemType Directory -Force -Path (Split-Path $out -Parent) | Out-Null
    # RS_SS_SHOT_SKIN=<id> fills in the recolor tick boxes for that skin, so the
    # shot shows them the way they look with a costume that has chromas open
    if ($env:RS_SS_SHOT_SKIN) { Set-ChromaBoxes $env:RS_SS_SHOT_SKIN; $chkChroma.Visible = $true; $chkChromaMaybe.Visible = $true }
    $frm.PerformLayout()
    # DrawToBitmap on a form that was never shown paints the frame and nothing
    # else, so show it - off screen and WITHOUT activating it (SW_SHOWNA), or it
    # would steal the keystrokes of whoever is at the keyboard.
    Add-Type -Namespace SSShot -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int n);' -ErrorAction SilentlyContinue
    $frm.StartPosition = 'Manual'
    $frm.ShowInTaskbar = $false
    $frm.Location = New-Object System.Drawing.Point(-4000, -4000)
    [void][SSShot.Win]::ShowWindow($frm.Handle, 8)      # 8 = SW_SHOWNA
    for ($i = 0; $i -lt 40; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 25 }
    $bmp = New-Object System.Drawing.Bitmap $frm.ClientSize.Width, $frm.ClientSize.Height
    $frm.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle 0, 0, $frm.ClientSize.Width, $frm.ClientSize.Height))
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host ("SMOKE15 OK: {0}" -f $out)
    $frm.Dispose()
    exit 0
}
if ($env:RS_SS_SMOKE -eq '18') {
    # one design -> one mod per skin (build_skin.ps1 -PerSkin). The split is a
    # filter on the skin id every rel carries, so the checks are: every op lands
    # in exactly one piece, in its own skin's piece, the costume comes first,
    # the mod names cannot collide, and a calibration travels with every piece.
    $fail = New-Object System.Collections.Generic.List[string]
    function S18-Check([bool]$ok, [string]$msg) { if (-not $ok) { $fail.Add($msg) } }
    $root = 'Marvel/Content/Marvel/Characters/1064'
    $doc = [pscustomobject]@{
        modName = 'Smoke18'; displayName = 'Smoke 18'; hero = '1064'; skin = '1064300'
        chromaSkins = @('1064301', '1064302')
        ops = [pscustomobject]@{
            "$root/1064300/Textures/T_1064300_Body_D.png"        = @(@{ mode = 'tint' })
            "$root/1064300/Weapons/T_WP_1064300_Balloon_D.png"   = @(@{ mode = 'tint' })   # a shared prop: goes with the costume
            "$root/1064301/Textures/T_1064301_Body_D.png"        = @(@{ mode = 'replace' })
            "$root/1064302/Textures/T_1064302_Body_D.png"        = @(@{ mode = 'replace' })
            "$root/1064302/Textures/T_1064302_Head_D.png"        = @(@{ mode = 'replace' })
        }
        colorOps = [pscustomobject]@{
            "$root/1064301/Materials/MI_1064301_Body.uasset" = @(@{ name = 'Region 1 - ColorA'; r = 0.5; g = 0.4; b = 0.3 })
            "$root/1064302/Materials/MI_1064302_Body.uasset" = @(@{ name = 'Region 1 - ColorA'; r = 0.5; g = 0.4; b = 0.3 })
        }
        dyeCal = [pscustomobject]@{ 'MI_#_Body|1|A' = @(1.5, 1.2, 1.1); '*' = @(1.1, 1.1, 1.1) }
    }
    $parts = @(SS-SplitDesignBySkin $doc)
    S18-Check ($parts.Count -eq 3) ("expected 3 pieces, got {0}" -f $parts.Count)
    if ($parts.Count -ge 1) { S18-Check ($parts[0].skin -eq '1064300') ("the costume should come first, got {0}" -f $parts[0].skin) }
    $seen = @{}
    foreach ($pt in $parts) {
        foreach ($k in @($pt.doc.ops.Keys) + @($pt.doc.colorOps.Keys)) {
            S18-Check (-not $seen.ContainsKey($k)) "$k landed in two pieces"
            $seen[$k] = 1
            S18-Check ($k -match $pt.skin) "$k landed in $($pt.skin)'s piece"
        }
        S18-Check ($pt.doc.modName -match '^[A-Za-z0-9]+$') ("mod name '{0}' is not letters/digits" -f $pt.doc.modName)
        S18-Check ($null -ne $pt.doc['dyeCal']) ("{0} lost the calibration" -f $pt.doc.modName)
        S18-Check ($pt.doc.skin -eq $pt.skin) ("{0} says skin {1}" -f $pt.doc.modName, $pt.doc.skin)
    }
    S18-Check ($seen.Count -eq 7) ("placed {0} of 7 ops" -f $seen.Count)
    $names = @($parts | ForEach-Object { $_.doc.modName })
    S18-Check (@($names | Sort-Object -Unique).Count -eq $names.Count) ("mod names collide: {0}" -f ($names -join ', '))
    $prop = @($parts | Where-Object { @($_.doc.ops.Keys) -match 'Balloon' })
    S18-Check ($prop.Count -eq 1 -and $prop[0].skin -eq '1064300') 'the shared prop should go with the costume only'
    # a design with a single skin is left alone (the builder then makes one mod)
    $one = [pscustomobject]@{ modName = 'Solo'; displayName = 'Solo'; hero = '1064'; skin = '1064300'
        ops = [pscustomobject]@{ "$root/1064300/Textures/T_1064300_Body_D.png" = @(@{ mode = 'tint' }) }; colorOps = [pscustomobject]@{} }
    S18-Check (@(SS-SplitDesignBySkin $one).Count -eq 1) 'a one-skin design should not split'

    if ($fail.Count) { Write-Host ('SMOKE18 FAIL: ' + ($fail -join ' | ')); $frm.Dispose(); exit 1 }
    Write-Host ('SMOKE18 OK: 7 ops across 3 skins split into {0} with every op placed once in its own skin, the shared prop with the costume, distinct mod names ({1}), and the calibration on every piece' -f $parts.Count, ($names -join ', '))
    $frm.Dispose()
    exit 0
}
if ($env:RS_SS_SMOKE -eq '17') {
    # the calibration dialog: build it, measure it, and draw it to a PNG
    # (RS_SS_CALSHOT=<path>) without ever showing it. Same reason as SMOKE15 -
    # a dialog that is never opened headlessly is a dialog nobody checks until
    # it throws under her hands.
    $fail = New-Object System.Collections.Generic.List[string]
    $d = New-DyeCalForm
    $names = @($d.Controls | ForEach-Object { $_.GetType().Name })
    if (@($names | Where-Object { $_ -eq 'TextBox' }).Count -lt 4) { $fail.Add('expected 3 shot boxes plus the results box') }
    if (@($names | Where-Object { $_ -eq 'Button' }).Count -lt 5) { $fail.Add('expected the meter, solve and three browse buttons') }
    foreach ($k in 'costume', 'recolor', 'meter') {
        if (-not $script:dcBox.ContainsKey($k)) { $fail.Add("no textbox for the $k shot") }
    }
    # every control inside the dialog, same rule as the main window
    foreach ($c in @($d.Controls)) {
        $b = $c.Bounds
        if ($b.Right -gt $d.ClientSize.Width -or $b.Bottom -gt $d.ClientSize.Height -or $b.Left -lt 0 -or $b.Top -lt 0) {
            $fail.Add(("{0} '{1}' is outside the dialog ({2},{3},{4},{5})" -f $c.GetType().Name, $c.Text, $b.Left, $b.Top, $b.Right, $b.Bottom))
        }
    }
    # and nothing may sit on top of anything else
    $all = @($d.Controls)
    for ($i = 0; $i -lt $all.Count; $i++) {
        for ($j = $i + 1; $j -lt $all.Count; $j++) {
            if ($all[$i].Bounds.IntersectsWith($all[$j].Bounds)) {
                $fail.Add(("{0} '{1}' overlaps {2} '{3}'" -f $all[$i].GetType().Name, $all[$i].Text, $all[$j].GetType().Name, $all[$j].Text))
            }
        }
    }
    $shot = if ($env:RS_SS_CALSHOT) { $env:RS_SS_CALSHOT } else { Join-Path $SS_Root 'work\_calshot.png' }
    New-Item -ItemType Directory -Force -Path (Split-Path $shot -Parent) | Out-Null
    Add-Type -Namespace SSShot2 -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int n);' -ErrorAction SilentlyContinue
    $d.StartPosition = 'Manual'; $d.ShowInTaskbar = $false
    $d.Location = New-Object System.Drawing.Point(-4000, -4000)
    [void][SSShot2.Win]::ShowWindow($d.Handle, 8)       # SW_SHOWNA: never steal the keyboard
    for ($i = 0; $i -lt 30; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 }
    $bmp = New-Object System.Drawing.Bitmap $d.ClientSize.Width, $d.ClientSize.Height
    $d.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle 0, 0, $d.ClientSize.Width, $d.ClientSize.Height))
    $bmp.Save($shot, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $nCtl = @($d.Controls).Count
    $dw = $d.ClientSize.Width; $dh = $d.ClientSize.Height
    $d.Dispose()
    if ($fail.Count) { Write-Host ('SMOKE17 FAIL: ' + ($fail -join ' | ')); $frm.Dispose(); exit 1 }
    Write-Host ("SMOKE17 OK: calibration dialog builds, {0} controls all inside {1}x{2} with no overlaps; drawn to {3}" -f $nCtl, $dw, $dh, $shot)
    $frm.Dispose()
    exit 0
}
if ($env:RS_SS_SMOKE -eq '16') {
    # recolour dye calibration, end to end and headless. Paints three synthetic
    # "screenshots" from known numbers - a costume, a recolor whose dyed zones
    # carry known dye values, and a meter whose dyes are white - then checks
    # that SS-SolveDyeCal recovers the dye it was given (the agreement that says
    # the measurement is sound) and that applying its answer lands the design on
    # the albedo the costume actually shows.
    $fail = New-Object System.Collections.Generic.List[string]
    function S16-Check([bool]$ok, [string]$msg) { if (-not $ok) { $fail.Add($msg) } }
    $dir = Join-Path $SS_Root 'work\_smoke16'
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $rel = 'Marvel/Content/Marvel/Characters/1064/1064301/Materials/MI_1064301_Equip_01.uasset'
    $dyes = @(@(0.30, 0.20, 0.15), @(0.80, 0.75, 0.70))       # ColorA, ColorB
    $arts = @(@(0.70, 0.40, 0.25), @(0.95, 0.88, 0.80))       # what the costume shows there
    $design = [ordered]@{
        modName = 'Smoke16'; displayName = 'Smoke 16'; hero = '1064'; skin = '1064300'
        ops = [ordered]@{}
        colorOps = [ordered]@{ $rel = @(
            [ordered]@{ export = 1; ordinal = 0; name = 'Region 1 - ColorA'; r = $dyes[0][0]; g = $dyes[0][1]; b = $dyes[0][2] }
            [ordered]@{ export = 1; ordinal = 1; name = 'Region 1 - ColorB'; r = $dyes[1][0]; g = $dyes[1][1]; b = $dyes[1][2] }
        ) }
    }
    $djPath = Join-Path $dir 'Smoke16.json'
    $design | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $djPath -Encoding utf8

    # three shots of one "scene": lighting varies across the frame, two dyed
    # bands, and a third band the recolor does not touch (it must be ignored)
    $W = 320; $H = 240
    $bmp = @{}
    foreach ($k in 'costume', 'recolor', 'meter') { $bmp[$k] = New-Object System.Drawing.Bitmap $W, $H }
    function S16-Byte([double]$lin) { [int][Math]::Max(0, [Math]::Min(255, [Math]::Round(255 * [SkinArt]::LinearToSrgb($lin)))) }
    for ($y = 0; $y -lt $H; $y++) {
        for ($x = 0; $x -lt $W; $x++) {
            $L = 0.25 + 0.65 * ($x / $W) * (0.55 + 0.45 * ($y / $H))
            # the right of the frame is BACKGROUND - identical in all three, and
            # patterned so the aligner has something to lock onto. That is where
            # SS-SolveDyeCal looks for its offset, exactly as in a real shot.
            if ($x -gt 0.52 * $W) {
                $v = 0.18 + 0.55 * ((((($x -shr 3) * 73 + ($y -shr 3) * 151) % 97) / 97.0))   # non-periodic: a checker gives the aligner ties
                $bg = [System.Drawing.Color]::FromArgb(255, (S16-Byte $v), (S16-Byte ($v * 0.8)), (S16-Byte ($v * 0.6)))
                foreach ($k in 'costume', 'recolor', 'meter') { $bmp[$k].SetPixel($x, $y, $bg) }
                continue
            }
            $zone = if ($y -lt 80) { 0 } elseif ($y -lt 160) { 1 } else { -1 }
            $lit = [System.Drawing.Color]::FromArgb(255, (S16-Byte $L), (S16-Byte $L), (S16-Byte $L))
            $bmp['meter'].SetPixel($x, $y, $lit)
            if ($zone -lt 0) {
                $flat = [System.Drawing.Color]::FromArgb(255, (S16-Byte (0.5 * $L)), (S16-Byte (0.5 * $L)), (S16-Byte (0.5 * $L)))
                $bmp['costume'].SetPixel($x, $y, $flat); $bmp['recolor'].SetPixel($x, $y, $flat)
            } else {
                $a = $arts[$zone]; $d = $dyes[$zone]
                $bmp['costume'].SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, (S16-Byte ($a[0]*$L)), (S16-Byte ($a[1]*$L)), (S16-Byte ($a[2]*$L))))
                $bmp['recolor'].SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, (S16-Byte ($d[0]*$L)), (S16-Byte ($d[1]*$L)), (S16-Byte ($d[2]*$L))))
            }
        }
    }
    $png = @{}
    foreach ($k in 'costume', 'recolor', 'meter') {
        $png[$k] = Join-Path $dir "$k.png"
        $bmp[$k].Save($png[$k], [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp[$k].Dispose()
    }

    $res = SS-SolveDyeCal -DesignPath $djPath -CostumeShot $png['costume'] -RecolorShot $png['recolor'] -MeterShot $png['meter']
    S16-Check ($res.groups -eq 2) ("expected 2 zones, measured {0}" -f $res.groups)
    S16-Check ([int]$res.align.recolor[0] -eq 0 -and [int]$res.align.recolor[1] -eq 0) ("recolor aligned to {0},{1}, expected 0,0" -f $res.align.recolor[0], $res.align.recolor[1])
    S16-Check ([int]$res.align.meter[0] -eq 0 -and [int]$res.align.meter[1] -eq 0) ("meter aligned to {0},{1}, expected 0,0" -f $res.align.meter[0], $res.align.meter[1])
    $solved = Get-Content -LiteralPath $djPath -Raw | ConvertFrom-Json
    S16-Check ($null -ne $solved.dyeCal) 'no dyeCal written into the design'
    # SS-DyeCalKey keeps the A / B / GChannel / BChannel suffix, not the 'Color' prefix
    $keyA = 'MI_#_Equip_01|1|A'; $keyB = 'MI_#_Equip_01|1|B'
    foreach ($k in $keyA, $keyB) {
        S16-Check (@($solved.dyeCal.PSObject.Properties.Name) -contains $k) "dyeCal has no entry for $k"
    }
    S16-Check (@($solved.dyeCal.PSObject.Properties.Name) -contains '*') 'dyeCal has no fallback for unseen zones'

    # applying it must land the dye on what the costume actually shows
    $n = SS-ApplyDyeCal $solved
    S16-Check ($n -ge 2) ("apply moved {0} site(s)" -f $n)
    $got = @($solved.colorOps.$rel)
    for ($i = 0; $i -lt 2; $i++) {
        $want = $arts[$i]
        $off = [Math]::Abs([double]$got[$i].r - $want[0]) + [Math]::Abs([double]$got[$i].g - $want[1]) + [Math]::Abs([double]$got[$i].b - $want[2])
        S16-Check ($off -lt 0.05) ("{0} landed {1:N3} {2:N3} {3:N3}, wanted {4} {5} {6}" -f $got[$i].name, $got[$i].r, $got[$i].g, $got[$i].b, $want[0], $want[1], $want[2])
    }
    # and the meter build must be white everywhere, with no calibration on it
    $meterDoc = Get-Content -LiteralPath $djPath -Raw | ConvertFrom-Json
    $nm = SS-DyeMeterDesign $meterDoc
    S16-Check ($nm -eq 2) ("meter whitened {0} site(s), expected 2" -f $nm)
    foreach ($e in @($meterDoc.colorOps.$rel)) {
        S16-Check ([double]$e.r -eq 1.0 -and [double]$e.g -eq 1.0 -and [double]$e.b -eq 1.0) ("meter left {0} at {1},{2},{3}" -f $e.name, $e.r, $e.g, $e.b)
    }
    S16-Check ($null -eq $meterDoc.PSObject.Properties['dyeCal']) 'the meter build kept a calibration - it must measure the raw dye'

    if ($fail.Count) { Write-Host ('SMOKE16 FAIL: ' + ($fail -join ' | ')); $frm.Dispose(); exit 1 }
    Write-Host ('SMOKE16 OK: measured 2 dyed zones out of 3 bands, recovered the dye values, and applying the answer put the design within 0.05 of what the costume shows; the meter build is white and carries no calibration')
    $frm.Dispose()
    exit 0
}
if ($env:RS_SS_SMOKE -eq '14') {
    # layout smoke: every top-level control must fit inside the window. Added
    # after the recolor tick boxes shipped INVISIBLE - the whole layout is pushed
    # down 54px for the brand band (see $Shift) and the status bar is docked to
    # the bottom, so a control placed by eye at the bottom of a column lands
    # behind it. Nothing on screen tells you; the control is simply not there.
    $fail = New-Object System.Collections.Generic.List[string]
    $frm.PerformLayout()
    $cw = $frm.ClientSize.Width
    $chH = $frm.ClientSize.Height
    $barTop = $chH
    foreach ($c in @($frm.Controls)) { if ($c.Dock -eq 'Bottom' -and $c.Top -lt $barTop) { $barTop = $c.Top } }
    foreach ($c in @($frm.Controls)) {
        if ($c.Dock -ne 'None') { continue }
        $b = $c.Bounds
        $name = if ($c.Text) { ('{0} "{1}"' -f $c.GetType().Name, $c.Text) } else { $c.GetType().Name }
        if ($b.Bottom -gt $barTop) { $fail.Add(("{0} bottom={1} is under the status bar (top={2})" -f $name, $b.Bottom, $barTop)) }
        if ($b.Right -gt $cw) { $fail.Add(("{0} right={1} is past the window ({2})" -f $name, $b.Right, $cw)) }
        if ($b.Top -lt 0 -or $b.Left -lt 0) { $fail.Add(("{0} sits off the top/left ({1},{2})" -f $name, $b.Left, $b.Top)) }
    }
    # the recolor boxes in particular: they are hidden until a skin with recolors
    # is open, so an off-screen position would never show up in normal use
    foreach ($c in @($chkChroma, $chkChromaMaybe, $btnDyeCal)) {
        if ($c.Bounds.Bottom -gt $barTop) { $fail.Add(("recolor control '{0}' is off-screen (bottom={1}, bar={2})" -f $c.Text, $c.Bounds.Bottom, $barTop)) }
    }
    # ...and it must not land on top of something either - the left column is
    # full to the 884 line, which is how the first attempt ended up covering
    # OPEN SKIN with nothing on screen to say so
    foreach ($c in @($frm.Controls)) {
        if ($c.Dock -ne 'None' -or [object]::ReferenceEquals($c, $btnDyeCal)) { continue }
        if ($c.Bounds.IntersectsWith($btnDyeCal.Bounds)) {
            $fail.Add(("calibrate button overlaps {0} '{1}'" -f $c.GetType().Name, $c.Text))
        }
    }
    # the Build card is packed too - the per-skin tick box went into the one
    # free row under 'zip to Downloads'; nothing inside the Build card may overlap
    $kids = @($grpBuild.Controls)
    for ($i = 0; $i -lt $kids.Count; $i++) {
        for ($j = $i + 1; $j -lt $kids.Count; $j++) {
            if ($kids[$i].Bounds.IntersectsWith($kids[$j].Bounds)) {
                $fail.Add(("inside the Build card, {0} '{1}' overlaps {2} '{3}'" -f $kids[$i].GetType().Name, $kids[$i].Text, $kids[$j].GetType().Name, $kids[$j].Text))
            }
        }
        if ($kids[$i].Bounds.Bottom -gt $grpBuild.ClientSize.Height -or $kids[$i].Bounds.Right -gt $grpBuild.ClientSize.Width) {
            $fail.Add(("{0} '{1}' spills out of the Build card" -f $kids[$i].GetType().Name, $kids[$i].Text))
        }
    }
    if ($fail.Count) { Write-Host ('SMOKE14 FAIL: ' + ($fail -join ' | ')); $frm.Dispose(); exit 1 }
    Write-Host ('SMOKE14 OK: {0} top-level controls all inside {1}x{2} (status bar top {3}); recolor boxes at y={4} and {5}' -f @($frm.Controls).Count, $cw, $chH, $barTop, $chkChroma.Top, $chkChromaMaybe.Top)
    $frm.Dispose()
    exit 0
}
if ($env:RS_SS_SMOKE -eq '13') {
    # chroma smoke: edits carried onto a costume's recolor skins, saved into one
    # design. Drives the real Apply / layer / revert handlers. No window shown.
    function Smoke-Click($ctl) { [void]$ctl.GetType().GetMethod('OnClick', [Reflection.BindingFlags]'Instance,NonPublic').Invoke($ctl, @([EventArgs]::Empty)) }
    $fail = New-Object System.Collections.Generic.List[string]
    function Smoke-Check($ok, [string]$what) { if (-not $ok) { $fail.Add($what) } }
    for ($i = 0; $i -lt $lstHeroes.Items.Count; $i++) { if (((LabelId ([string]$lstHeroes.Items[$i])) -eq '1064')) { $lstHeroes.SelectedIndex = $i; break } }
    Refresh-SkinList
    for ($i = 0; $i -lt $lstSkins.Items.Count; $i++) { if (((LabelId ([string]$lstSkins.Items[$i])) -eq '1064300')) { $lstSkins.SelectedIndex = $i; break } }
    Open-Skin '1064300'
    # NB: not .Visible - a control reports false while the form has never been shown
    Smoke-Check (@($script:ChromaT.Sure).Count -eq 2 -and $chkChroma.Text -eq 'also edit its 2 recolors') ("chroma box: text='{0}' sure={1}" -f $chkChroma.Text, @($script:ChromaT.Sure).Count)
    Smoke-Check (@($script:ChromaT.Sure) -contains '1064301' -and @($script:ChromaT.Sure) -contains '1064302') ("targets={0}" -f (@($script:ChromaT.Sure) -join ','))
    $tex = @($script:TexItems | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.Rel) -eq 'T_1064300_Body_D' })[0]
    if (-not $tex) { Write-Host 'SMOKE13 FAIL: T_1064300_Body_D not in this skin'; $frm.Dispose(); exit 1 }
    foreach ($s in '1064300', '1064301', '1064302') { if ($script:OpsBySkin.ContainsKey($s)) { $script:OpsBySkin[$s].Clear() } }
    $script:SelTex = $tex
    $chkLinked.Checked = $false
    $chkChroma.Checked = $true
    $script:Loading = $true
    Set-PanelFromOp $null
    # flat paint, skin protection off: the whole map becomes one colour, so
    # "did the copy really get the edited art" is unmistakable
    $rbRecolor.Checked = $true; $cmbMode.SelectedItem = 'Flat paint'
    $pnlColor.BackColor = [System.Drawing.Color]::FromArgb(255, 0, 128); $trkStr.Value = 100
    $chkProtect.Checked = $false
    $script:Loading = $false

    # 1. APPLY carries onto both recolors, at their own rels
    Smoke-Click $btnApply
    $r1 = SS-RelForSkin $tex.Rel '1064300' '1064301'
    $r2 = SS-RelForSkin $tex.Rel '1064300' '1064302'
    Smoke-Check ($script:OpsBySkin['1064301'].ContainsKey($r1)) "recolor 1064301 missing $r1"
    Smoke-Check ($script:OpsBySkin['1064302'].ContainsKey($r2)) "recolor 1064302 missing $r2"

    # 2. the recolor gets a COPY of the costume's finished art, not a re-run of
    #    the recipe on its own art (which lands on a different colour per chroma)
    $theirs = @($script:OpsBySkin['1064301'][$r1])
    Smoke-Check ($theirs.Count -eq 1 -and (SS-OpVal $theirs[0] 'mode' '') -eq 'replace') ("recolor op should be a copy: {0} layer(s), mode={1}" -f $theirs.Count, (SS-OpVal $theirs[0] 'mode' ''))
    # the dye MASK must be left alone: blacking it renders the zone WHITE in game
    # (proven by the probe build), which is what made every earlier version pale
    $maskRel = Get-ChromaMaskRel '1064301' $r1
    Smoke-Check ($maskRel) 'the recolor dye mask could not be located'
    Smoke-Check (-not ($maskRel -and $script:OpsBySkin['1064301'].ContainsKey($maskRel))) 'the dye mask was overwritten - black paints the zone WHITE in game'
    $copyPng = [string](SS-OpVal $theirs[0] 'file' '')
    Smoke-Check ((Test-Path -LiteralPath $copyPng) -and $copyPng -like '*\work\chroma\1064300\*') "copy source missing or misplaced: $copyPng"
    # the copy really is the edited art: it must differ from the costume's vanilla
    # NB: not AvgLumDiff - a tint keeps luminance on purpose, so measure COLOUR
    function Smoke-Avg([string]$p) {
        $b = [SkinArt]::Load($p)
        try {
            $r = 0.0; $g = 0.0; $bl = 0.0; $n = 0
            for ($y = 0; $y -lt $b.Height; $y += [Math]::Max(1, [int]($b.Height / 24))) {
                for ($x = 0; $x -lt $b.Width; $x += [Math]::Max(1, [int]($b.Width / 24))) {
                    $c = $b.GetPixel($x, $y); if ($c.A -lt 8) { continue }
                    $r += $c.R; $g += $c.G; $bl += $c.B; $n++
                }
            }
            if ($n -eq 0) { return @(0, 0, 0) }
            @(($r / $n), ($g / $n), ($bl / $n))    # parens: commas bind tighter than /
        } finally { $b.Dispose() }
    }
    $vanAvg = Smoke-Avg (Join-Path (Join-Path $script:CurCk 'png\src') $tex.Rel)
    $copyAvg = Smoke-Avg $copyPng
    $copyDrift = [Math]::Abs($vanAvg[0] - $copyAvg[0]) + [Math]::Abs($vanAvg[1] - $copyAvg[1]) + [Math]::Abs($vanAvg[2] - $copyAvg[2])
    Smoke-Check ($copyDrift -gt 10) ("the copied art barely differs from vanilla (colour drift {0:N1}) - the recolor did not render into it" -f $copyDrift)
    # a second layer re-renders the copy rather than stacking on the chroma
    $script:Loading = $true; $rbRecolor.Checked = $true; $cmbMode.SelectedItem = 'Hue shift'; $numHue.Value = 90; $script:Loading = $false
    Smoke-Click $btnLayerAdd
    $mine = Get-CurStack
    $theirs2 = @($script:OpsBySkin['1064301'][$r1])
    Smoke-Check ($mine.Count -eq 2) ("costume layers={0}" -f $mine.Count)
    Smoke-Check ($theirs2.Count -eq 1 -and (SS-OpVal $theirs2[0] 'mode' '') -eq 'replace') 'recolor should still carry a single copy op'
    # the copy is re-rendered in place, so compare how far it now sits from vanilla
    $copyAvg2 = Smoke-Avg ([string](SS-OpVal $theirs2[0] 'file' ''))
    $copyDrift2 = [Math]::Abs($vanAvg[0] - $copyAvg2[0]) + [Math]::Abs($vanAvg[1] - $copyAvg2[1]) + [Math]::Abs($vanAvg[2] - $copyAvg2[2])
    Smoke-Check ([Math]::Abs($copyDrift2 - $copyDrift) -gt 2) ("adding a layer did not re-render the copy handed to the recolor (drift {0:N1} -> {1:N1})" -f $copyDrift, $copyDrift2)
    # the recolor's dye must PAINT the design's colour, not white (white washes
    # the masked zones out - the chroma's own art is desaturated there)
    $dyeOps = if ($script:ColorOpsBySkin.ContainsKey('1064301')) { $script:ColorOpsBySkin['1064301'] } else { @{} }
    $bodyMat = @($dyeOps.Keys | Where-Object { $_ -match '(?i)MI_1064301_Body' })
    Smoke-Check ($bodyMat.Count -gt 0) 'no dye colours carried onto the recolor'
    if ($bodyMat.Count) {
        $vals = @($dyeOps[$bodyMat[0]].Values)
        $white = @($vals | Where-Object { $_.r -gt 0.99 -and $_.g -gt 0.99 -and $_.b -gt 0.99 }).Count
        Smoke-Check ($white -eq 0) "dye was set to white on $($white) param(s) - that washes the zone out"
        # it must equal the design's own colour over the dyed zones, i.e. a fresh
        # sample of the art that was just copied across
        $maskLeaf = ([IO.Path]::GetFileNameWithoutExtension($r1) -replace '_D$', '_ColorID')
        $maskPng = $null
        if ($script:ChromaMaskRels['1064301'].ContainsKey($maskLeaf)) {
            $maskPng = Join-Path (Join-Path (Join-Path $SS_Cache '1064301') 'png\src') $script:ChromaMaskRels['1064301'][$maskLeaf]
        }
        $expect = SS-SampleDyeColor ([string](SS-OpVal $theirs2[0] 'file' '')) $maskPng
        Smoke-Check ($null -ne $expect) 'could not sample the design colour for the dye'
        if ($expect) {
            $off = @($vals | Where-Object { [Math]::Abs($_.r - $expect.r) + [Math]::Abs($_.g - $expect.g) + [Math]::Abs($_.b - $expect.b) -gt 0.02 }).Count
            Smoke-Check ($off -eq 0) ("dye does not match the copied art on {0} of {1} params" -f $off, $vals.Count)
            Smoke-Check ($maskPng -and (Test-Path -LiteralPath $maskPng)) 'the recolor dye mask was not found (sampling fell back to the whole map)'
        }
    }

    # 3. one design file holds all three skins
    $txtModName.Text = 'SmokeChroma'; $txtDisplay.Text = 'Smoke Chroma'
    # start from nothing: saves now carry a calibration forward, so a design
    # left by the previous run would hand its dyeCal to this one
    $stale = Get-DesignPath
    if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Force }
    $saved = Save-Design
    $doc = Get-Content -LiteralPath $saved -Raw | ConvertFrom-Json
    $ids = @($doc.ops.PSObject.Properties | ForEach-Object { ([regex]'[\\/](\d{7})[\\/]').Match($_.Name).Groups[1].Value } | Sort-Object -Unique)
    Smoke-Check ($ids.Count -eq 3) ("design covers skins: {0}" -f ($ids -join ','))
    Smoke-Check (@($doc.chromaSkins).Count -eq 2) ("chromaSkins={0}" -f (@($doc.chromaSkins) -join ','))

    # 3b. a save must not drop the calibration: it is measured in game, so
    #     nothing in the design can rebuild it if a later save wipes it
    $withCal = Get-Content -LiteralPath $saved -Raw | ConvertFrom-Json
    $withCal | Add-Member -Force -NotePropertyName dyeCal -NotePropertyValue ([ordered]@{ 'MI_#_Body|1|A' = @(1.5, 1.2, 1.1); '*' = @(1.2, 1.2, 1.2) })
    $withCal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $saved -Encoding utf8
    [void](Save-Design)
    $after = Get-Content -LiteralPath $saved -Raw | ConvertFrom-Json
    Smoke-Check ($null -ne $after.dyeCal -and @($after.dyeCal.PSObject.Properties.Name) -contains 'MI_#_Body|1|A') 'saving the design dropped its recolour calibration'
    $applied = SS-ApplyDyeCal $after
    Smoke-Check ($applied -ge 0) 'SS-ApplyDyeCal threw on a real design'

    # 4. a design with foreign rels reloads into the right per-skin op sets
    $script:OpsBySkin = @{}
    $cmbDesign.SelectedItem = 'SmokeChroma'
    Smoke-Click $btnLoadD
    Smoke-Check ($script:OpsBySkin.ContainsKey('1064301') -and $script:OpsBySkin['1064301'].ContainsKey($r1)) 'reload did not restore the recolor ops'
    Smoke-Check ($script:OpsBySkin['1064300'].Keys.Count -eq 1) ("reload put {0} ops on the costume" -f $script:OpsBySkin['1064300'].Keys.Count)

    # 5. unticking the box pulls the recolor edits back out, reticking re-adds them
    #    (it is a statement about the design, not just about the next edit)
    $chkChroma.Checked = $false
    Smoke-Check (-not $script:OpsBySkin['1064301'].ContainsKey($r1)) 'untick left the recolor edited'
    $chkChroma.Checked = $true
    Smoke-Check ($script:OpsBySkin['1064301'].ContainsKey($r1)) 'retick did not carry the edits back'

    # 6. a design that predates this (ops for the costume only) gains its recolors
    #    when it is opened with the box ticked
    $onlyMine = @{}
    foreach ($kv in $script:OpsBySkin['1064300'].GetEnumerator()) { $onlyMine[$kv.Key] = $kv.Value }
    $script:OpsBySkin = @{ '1064300' = $onlyMine }
    Open-Skin '1064300'
    Smoke-Check ($script:OpsBySkin.ContainsKey('1064301') -and $script:OpsBySkin['1064301'].ContainsKey($r1)) 'opening an old design did not extend it to the recolors'

    # 6b. a recolor is a copy of the WHOLE costume: maps she never edited (the
    #     face, the eyes, the _S speculars) have to come across too, or it keeps
    #     the recolor's own art there and still looks different
    # an unedited map that DIFFERS between the two must come across (Hair_AO is
    # exactly that case - it is what tints Blue Breezes' hair red); one that is
    # byte-identical must NOT, or the mod carries 39 pointless textures
    $hashes = SS-TextureHashes @('1064300', '1064301')
    # NB: not $tex as the loop variable - step 7 still needs the texture under
    # test, and a foreach leaves its variable pointing at the LAST item
    $carried = 0; $wrongly = 0; $missed = @()
    foreach ($ti in $script:TexItems) {
        if ($ti.Rel -match '_ColorID\.png$') { continue }
        $bLeaf = [IO.Path]::GetFileNameWithoutExtension($ti.Rel)
        $tRel2 = SS-RelForSkin $ti.Rel '1064300' '1064301'
        if (-not $script:ChromaRels['1064301'].Contains($tRel2)) { continue }
        $differs = SS-MapDiffers $hashes $bLeaf ($bLeaf.Replace('1064300', '1064301'))
        $has = $script:OpsBySkin['1064301'].ContainsKey($tRel2)
        if ($differs -and $has) { $carried++ }
        elseif ($differs -and -not $has -and -not (Get-Ops).ContainsKey($ti.Rel)) { $missed += $bLeaf }
        elseif (-not $differs -and $has -and -not (Get-Ops).ContainsKey($ti.Rel)) { $wrongly++ }
    }
    Smoke-Check ($carried -gt 0) 'no differing maps were carried onto the recolor'
    Smoke-Check ($missed.Count -eq 0) ("maps that differ but were not carried: {0}" -f ($missed -join ', '))
    Smoke-Check ($wrongly -eq 0) ("{0} identical map(s) copied for nothing" -f $wrongly)

    # 7. revert takes the recolors back with it
    $script:SelTex = @($script:TexItems | Where-Object { $_.Rel -eq $tex.Rel })[0]
    Smoke-Click $btnRevert
    $left = if ($script:OpsBySkin['1064301'].ContainsKey($r1)) { [string](SS-OpVal @($script:OpsBySkin['1064301'][$r1])[0] 'file' '?') } else { '' }
    Smoke-Check (-not $left) "revert left the recolor edited (source: $left)"

    if ($fail.Count) { Write-Host ('SMOKE13 FAIL: ' + ($fail -join ' | ')); $frm.Dispose(); exit 1 }
    Write-Host 'SMOKE13 OK: recolor targets found; the costume''s finished art is COPIED onto them (re-rendered per edit), their dye colours are re-aimed at the design''s own colour over the masked zones (never white), and save/reload/untick/retick/revert all follow'
    $frm.Dispose()
    exit 0
}
if ($env:RS_SS_SMOKE -eq '11') {
    # layer-stack smoke: fires the REAL Layers button/list Click handlers (smoke 2
    # only ever wrote a stack straight into Get-Ops, which is how "+ add" on a
    # one-layer stack could stay broken). No window is shown.
    function Smoke-Click($ctl) { [void]$ctl.GetType().GetMethod('OnClick', [Reflection.BindingFlags]'Instance,NonPublic').Invoke($ctl, @([EventArgs]::Empty)) }
    $fail = New-Object System.Collections.Generic.List[string]
    function Smoke-Check($ok, [string]$what) { if (-not $ok) { $fail.Add($what) } }
    function Smoke-Panel([scriptblock]$set) { $script:Loading = $true; & $set; $script:Loading = $false }
    for ($i = 0; $i -lt $lstHeroes.Items.Count; $i++) { if (((LabelId ([string]$lstHeroes.Items[$i])) -eq '1047')) { $lstHeroes.SelectedIndex = $i; break } }
    Refresh-SkinList
    for ($i = 0; $i -lt $lstSkins.Items.Count; $i++) { if (((LabelId ([string]$lstSkins.Items[$i])) -eq '1047001')) { $lstSkins.SelectedIndex = $i; break } }
    Open-Skin '1047001'
    $tex = @($script:TexItems | Where-Object Role -eq 'color')[0]
    $script:SelTex = $tex
    [void](Get-Ops).Remove($tex.Rel)
    $chkLinked.Checked = $false
    $script:EditLayerIdx = -1
    Smoke-Panel { Set-PanelFromOp $null }

    # 1. first layer
    Smoke-Panel { $rbRecolor.Checked = $true; $cmbMode.SelectedItem = 'Tint to color'; $pnlColor.BackColor = [System.Drawing.Color]::FromArgb(255, 0, 0); $trkStr.Value = 100; $chkProtect.Checked = $false }
    Smoke-Click $btnLayerAdd
    Smoke-Check ((Get-CurStack).Count -eq 1) ("add #1: stack={0}" -f (Get-CurStack).Count)
    Smoke-Check ($script:EditLayerIdx -eq -1 -and $rbVanilla.Checked) 'after add the panel should be a clean draft'

    # 2. second layer on a ONE-layer stack (the path that threw)
    Smoke-Panel { $rbRecolor.Checked = $true; $cmbMode.SelectedItem = 'Hue shift'; $numHue.Value = 120 }
    Smoke-Check ((Get-PreviewStack).Count -eq 2) ("draft preview should be stack + draft = 2, got {0}" -f (Get-PreviewStack).Count)
    Smoke-Click $btnLayerAdd
    $st = Get-CurStack
    Smoke-Check ($st.Count -eq 2) ("add #2: stack={0}" -f $st.Count)
    Smoke-Check ($lstLayers.Items.Count -eq 2) ("layer list rows={0}" -f $lstLayers.Items.Count)
    Smoke-Check ((SS-OpVal $st[0] 'mode' '') -eq 'tint' -and (SS-OpVal $st[1] 'mode' '') -eq 'hueshift') ("order: {0} / {1}" -f (SS-OpVal $st[0] 'mode' ''), (SS-OpVal $st[1] 'mode' ''))

    # 3. the preview is the whole stack, and differs from layer 1 alone
    Show-Preview
    $pv = Ensure-Preview $tex
    $one = SS-RenderStack $pv @($st[0]); $two = SS-RenderStack $pv $st
    $x = [int]($two.Width / 2); $y = [int]($two.Height / 2)
    Smoke-Check ([bool]$picMod.Image) 'no modified preview image'
    if ($picMod.Image) { Smoke-Check ($picMod.Image.GetPixel($x, $y).ToArgb() -eq $two.GetPixel($x, $y).ToArgb()) 'preview pixel != 2-layer render' }
    $samePx = 0; foreach ($f in 0.3, 0.5, 0.7) { $px = [int]($two.Width * $f); if ($one.GetPixel($px, $px).ToArgb() -eq $two.GetPixel($px, $px).ToArgb()) { $samePx++ } }
    Smoke-Check ($samePx -lt 3) 'layer 2 changed nothing in the render'
    $one.Dispose(); $two.Dispose()

    # 4. click layer 1 -> edit it, change colour, update
    $lstLayers.SelectedIndex = 0; Smoke-Click $lstLayers
    Smoke-Check ($script:EditLayerIdx -eq 0 -and [string]$cmbMode.SelectedItem -eq 'Tint to color') ("click layer 1: idx={0} mode={1}" -f $script:EditLayerIdx, $cmbMode.SelectedItem)
    Smoke-Panel { $pnlColor.BackColor = [System.Drawing.Color]::FromArgb(0, 255, 0) }
    Smoke-Check ((Get-PreviewStack).Count -eq 2) 'editing a layer should preview it in place, not add one'
    Smoke-Click $btnLayerUpd
    $st = Get-CurStack
    Smoke-Check ($st.Count -eq 2 -and (SS-OpVal $st[0] 'color' '') -eq '#00FF00') ("update: count={0} color={1}" -f $st.Count, (SS-OpVal $st[0] 'color' ''))

    # 5. clicking the edited layer again releases it
    $lstLayers.SelectedIndex = 0; Smoke-Click $lstLayers
    Smoke-Check ($script:EditLayerIdx -eq -1) ("re-click should release the layer, idx={0}" -f $script:EditLayerIdx)

    # 6. move layer 1 down, then remove it
    $lstLayers.SelectedIndex = 0; Smoke-Click $lstLayers
    Smoke-Click $btnLayerDn
    $st = Get-CurStack
    Smoke-Check ((SS-OpVal $st[1] 'mode' '') -eq 'tint' -and $script:EditLayerIdx -eq 1) ("move down: {0} idx={1}" -f (SS-OpVal $st[1] 'mode' ''), $script:EditLayerIdx)
    Smoke-Click $btnLayerDel
    $st = Get-CurStack
    Smoke-Check ($st.Count -eq 1 -and (SS-OpVal $st[0] 'mode' '') -eq 'hueshift') ("remove: count={0}" -f $st.Count)

    # 7. back to one layer: adding must still work
    Smoke-Panel { $rbRecolor.Checked = $true; $cmbMode.SelectedItem = 'Grayscale' }
    Smoke-Click $btnLayerAdd
    Smoke-Check ((Get-CurStack).Count -eq 2) ("re-add on one layer: stack={0}" -f (Get-CurStack).Count)
    Smoke-Check ($tex.Item.ForeColor -eq $colPink) 'thumbnail not marked modified'

    # 8. design save -> json keeps both layers
    $txtModName.Text = 'SmokeLayers'; $txtDisplay.Text = 'Smoke Layers'
    $saved = Save-Design
    $chk = Get-Content -LiteralPath $saved -Raw | ConvertFrom-Json
    $jl = @(SS-OpLayers ($chk.ops.PSObject.Properties[$tex.Rel].Value))
    Smoke-Check ($jl.Count -eq 2) ("design json layers={0}" -f $jl.Count)
    Remove-Item -LiteralPath $saved -Force

    if ($fail.Count) { Write-Host ('SMOKE11 FAIL: ' + ($fail -join ' | ')); $frm.Dispose(); exit 1 }
    Write-Host ('SMOKE11 OK: add/add-on-one-layer/preview/edit/update/release/move/remove/re-add/save all pass ({0})' -f [IO.Path]::GetFileName($tex.Rel))
    $frm.Dispose()
    exit 0
}
# load one design the way the Load button does, and report what the app holds
# for it (a test seam: RS_SS_LOADTEST=<design name>)
# Open-DesignRequest as the helper triggers it (test seam: RS_SS_OPENTEST=<design>)
if ($env:RS_SS_OPENTEST) {
    Open-DesignRequest $env:RS_SS_OPENTEST
    Write-Host ('OPENTEST: skin {0}, colour edits {1}, design box {2}' -f $script:CurSkin, (Count-ColorEdits), $cmbDesign.SelectedItem)
    $frm.Dispose(); exit 0
}
if ($env:RS_SS_LOADTEST) {
    $i = $cmbDesign.Items.IndexOf($env:RS_SS_LOADTEST)
    if ($i -lt 0) { Write-Host ('LOADTEST: no design ' + $env:RS_SS_LOADTEST); $frm.Dispose(); exit 1 }
    $cmbDesign.SelectedIndex = $i
    # PerformClick does nothing on a form that was never shown: raise Click directly
    $btnLoadD.GetType().GetMethod('OnClick', [Reflection.BindingFlags]'NonPublic,Instance').Invoke($btnLoadD, @([EventArgs]::Empty))
    Load-ColorItems 'mat'
    $edited = @($script:ColorItems | Where-Object { Get-ColorEdit $_ })
    foreach ($tx in @($script:TexItems)) {
        $tn = Get-PreviewTint $tx
        if ($tn) {
            $script:SelTex = $tx; $sw = [Diagnostics.Stopwatch]::StartNew(); for ($q = 0; $q -lt 5; $q++) { Show-Preview }; Write-Host ('LOADTEST: preview redraw {0} ms each' -f [int]($sw.ElapsedMilliseconds / 5))
            $sv = [SkinArt]::Size((Ensure-Preview $tx))
            $a = $picVan.Image.GetPixel([int]($picVan.Image.Width / 2), [int]($picVan.Image.Height / 2)); $b = $picMod.Image.GetPixel([int]($picMod.Image.Width / 2), [int]($picMod.Image.Height / 2))
            Write-Host ('LOADTEST: {0} tint x({1:0.00},{2:0.00},{3:0.00}) centre pixel {4} -> {5}' -f [IO.Path]::GetFileName($tx.Rel), $tn[0], $tn[1], $tn[2], $a.Name, $b.Name)
            break
        }
    }
    Write-Host ('LOADTEST: skin {0}, colour edits {1}, rows {2}, edited rows {3}, texture ops {4}' -f $script:CurSkin, (Count-ColorEdits), $script:ColorItems.Count, $edited.Count, @((Get-Ops).Keys).Count)
    $frm.Dispose(); exit 0
}if ($env:RS_SS_SMOKE -eq '1') {
    if ($lstHeroes.Items.Count -gt 0) { $lstHeroes.SelectedIndex = 0 }
    Write-Host ('SMOKE OK: {0} heroes listed, {1} skins for first hero, {2} designs.' -f $lstHeroes.Items.Count, $lstSkins.Items.Count, $cmbDesign.Items.Count)
    $frm.Dispose()
    exit 0
}
if ($env:RS_SS_SMOKE -eq '20') {
    # Atelier round-trip smoke, entirely in work\_smoke20 - never designs\
    # (the live watcher treats the newest design there as live) and never
    # Atelier's own projects folder. A tint layer + a small painted patch + two
    # colour edits go out as an Atelier project and must come back LOSSLESS:
    # every layer re-renders byte-identical, every colour within 1e-4, and the
    # untouched map Atelier-style projects carry is recognised and dropped.
    $fail = @()
    $dir = Join-Path $SS_Root 'work\_smoke20'
    if (Test-Path $dir) { [IO.Directory]::Delete($dir, $true) }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $skin = '1064300'
    $ck = SS-EnsureSkinCache $skin $script:Map.skinLines[$skin] $null $null
    $rows = [IO.File]::ReadAllLines((Join-Path $ck 'thumbs.map'))
    $relOf = @{}; foreach ($row in $rows) { $rr = $row.Split('|')[0]; $relOf[[IO.Path]::GetFileNameWithoutExtension($rr)] = $rr }
    $relBody = $relOf['T_1064300_Body_D']; $relHair = $relOf['T_1064300_Hair_D']
    # a patch small enough to vanish into any AVERAGE - the import must still see it
    $patchPng = Join-Path $dir 'patch.png'
    $bmp = [SkinArt]::Load((Join-Path (Join-Path $ck 'png\src') $relHair))
    try { $g = [System.Drawing.Graphics]::FromImage($bmp); $g.FillRectangle([System.Drawing.Brushes]::Magenta, 10, 10, 12, 12); $g.Dispose(); $bmp.Save($patchPng, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }
    $cj = Get-Content -LiteralPath (SS-EnsureColorCache $skin $null $null 'mat') -Raw | ConvertFrom-Json
    $mat = $null; foreach ($a in $cj) { if ([string]$a.asset -like '*/Materials/MI_1064300_Body.uasset') { $mat = $a } }
    $bt = @($mat.colors | Where-Object { $_.name -eq 'BaseTint' })[0]
    # any second real colour the material stores (not every MI has a rim light)
    $rim = @($mat.colors | Where-Object { $_.name -ne 'BaseTint' -and [string]$_.kind -ne 'curve' -and (SS-ColorIsPickable ([string]$_.name) ([double]$_.r) ([double]$_.g) ([double]$_.b)) })[0]
    if (-not $bt -or -not $rim) { Write-Host 'SMOKE20 FAIL: MI_1064300_Body lacks the colour sites this test edits'; $frm.Dispose(); exit 1 }
    $doc = [ordered]@{
        modName = 'Smoke20'; displayName = 'Smoke 20'; hero = '1064'; skin = $skin; chromaSkins = @()
        ops = [ordered]@{ $relBody = @(@{ mode = 'tint'; color = '#7A4FD0'; strength = 0.8 }); $relHair = @(@{ mode = 'replace'; file = $patchPng; strength = 1.0 }) }
        colorOps = [ordered]@{ $mat.asset = @(
            [ordered]@{ export = $bt.export; ordinal = $bt.ordinal; name = 'BaseTint'; r = 0.8; g = 0.6; b = 0.9 }
            [ordered]@{ export = $rim.export; ordinal = $rim.ordinal; name = [string]$rim.name; r = 0.1; g = 0.7; b = 0.3 }) }
    }
    $dp = Join-Path $dir 'Smoke20.json'
    $doc | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $dp -Encoding utf8
    $x = SS-ExportAtelierProject $dp 'Smoke20' (Join-Path $dir 'projects') $null
    if ($x.textures -ne 2 -or $x.materials -ne 1) { $fail += "export wrote $($x.textures) texture(s) / $($x.materials) material(s), want 2 / 1" }
    # an Atelier project usually also holds untouched imports - add one
    $relHead = $relOf['T_1064300_Head_D']
    $plain = Join-Path $x.project ($relHead -replace '^Marvel\\Content\\Marvel\\', '')
    Copy-Item -LiteralPath (Join-Path (Join-Path $ck 'png\src') $relHead) -Destination $plain
    $r = SS-ImportAtelierProject $x.project 'Smoke20Back' (Join-Path $dir 'designs') $null
    if ($r.texEdited -ne 2) { $fail += "import found $($r.texEdited) edited texture(s), want 2 (the small patch must not vanish)" }
    if ($r.texSame -ne 1) { $fail += "import skipped $($r.texSame) untouched texture(s), want 1" }
    $back = Get-Content -LiteralPath $r.design -Raw | ConvertFrom-Json
    $tmpPng = Join-Path $dir 'render.png'
    foreach ($p in $back.ops.PSObject.Properties) {
        $src = Join-Path (Join-Path $ck 'png\src') $p.Name
        $b1 = SS-RenderStack $src @($p.Value); try { [SkinArt]::SavePngLike($b1, $tmpPng, $src) } finally { $b1.Dispose() }
        $want = Join-Path $dir 'want.png'
        $b2 = SS-RenderStack $src @($doc.ops[$p.Name]); try { [SkinArt]::SavePngLike($b2, $want, $src) } finally { $b2.Dispose() }
        $st = [ViewArt]::DiffStats($tmpPng, $want)
        if ($st[1] -ne 0) { $fail += ('{0} came back {1} off' -f (Split-Path $p.Name -Leaf), $st[1]) }
    }
    $got = @($back.colorOps.PSObject.Properties | ForEach-Object { @($_.Value) })
    foreach ($e in @($doc.colorOps[$mat.asset])) {
        $h = @($got | Where-Object { $_.export -eq $e.export -and $_.ordinal -eq $e.ordinal })[0]
        if (-not $h) { $fail += "$($e.name) did not come back"; continue }
        if ([Math]::Abs($h.r - $e.r) + [Math]::Abs($h.g - $e.g) + [Math]::Abs($h.b - $e.b) -gt 1e-4) { $fail += "$($e.name) drifted" }
    }
    if ($got.Count -ne 2) { $fail += "import produced $($got.Count) colour edit(s), want 2" }
    if ($fail.Count) { Write-Host ('SMOKE20 FAIL: ' + ($fail -join ' | ')); $frm.Dispose(); exit 1 }
    Write-Host ('SMOKE20 OK: design -> Atelier project -> design is lossless (2 layers byte-identical incl. a 12px patch, 2 colours exact, 1 untouched import dropped); all in {0}' -f $dir)
    [IO.Directory]::Delete($dir, $true)
    $snap = Join-Path $SS_ImportRoot 'Smoke20Back'
    if (Test-Path -LiteralPath $snap) { [IO.Directory]::Delete($snap, $true) }
    $frm.Dispose()
    exit 0
}
if ($env:RS_SS_SMOKE -eq '19') {
    # 3D preview smoke: open Jubilee, show the viewer OFF-SCREEN, then add a
    # layer and let the design-watch timer rebuild it. Passes when the page
    # reports a new render, ONLY the edited map was re-baked, and a capture of
    # the WebView lands in work\_shot3d.png. Never shows a window on screen.
    $fail = @()
    $waitLoaded = {
        param($afterRev, $secs)
        $t0 = [DateTime]::UtcNow
        while (([DateTime]::UtcNow - $t0).TotalSeconds -lt $secs) {
            [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 25
            $l = $script:SS_ViewLast
            if ($l -and $l.ev -eq 'error') { return $l }
            if ($l -and $l.ev -eq 'loaded' -and [string]$l.rev -ne [string]$afterRev) { return $l }
        }
        $null
    }
    for ($i = 0; $i -lt $lstHeroes.Items.Count; $i++) { if (((LabelId ([string]$lstHeroes.Items[$i])) -eq '1064')) { $lstHeroes.SelectedIndex = $i; break } }
    Refresh-SkinList
    Open-Skin '1064300'
    $script:SS_ViewLast = $null
    Update-3DPreview -Open
    $l1 = & $waitLoaded '' 120
    if (-not $l1 -or $l1.ev -ne 'loaded') { Write-Host ('SMOKE19 FAIL: first render never arrived ({0})' -f ($l1 | ConvertTo-Json -Compress)); $frm.Dispose(); exit 1 }
    if ([int]$l1.bound -lt 5) { $fail += "only $($l1.bound) parts textured" }
    $scF = Join-Path (SS-ViewDir '1064300') 'scene.json'
    $v1 = (Get-Content $scF -Raw | ConvertFrom-Json).tex
    $tex = @($script:TexItems | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.Rel) -eq 'T_1064300_Body_D' })[0]
    if (-not $tex) { Write-Host 'SMOKE19 FAIL: T_1064300_Body_D not in this skin'; $frm.Dispose(); exit 1 }
    $had = (Get-Ops).ContainsKey($tex.Rel)
    (Get-Ops)[$tex.Rel] = @(@{ mode = 'tint'; color = '#3060FF'; strength = 1.0 })
    $l2 = & $waitLoaded $l1.rev 60
    if (-not $l2 -or $l2.ev -ne 'loaded') { $fail += 'the edit never reached the 3D view' }
    $v2 = (Get-Content $scF -Raw | ConvertFrom-Json).tex
    $changed = @($v1.PSObject.Properties | Where-Object { [string]$v2.($_.Name) -ne [string]$_.Value } | ForEach-Object Name)
    if ($changed -notcontains 'T_1064300_Body_D.png') { $fail += 'Body_D was not re-baked' }
    $extra = @($changed | Where-Object { $_ -ne 'T_1064300_Body_D.png' -and $_ -notlike '*__dye.png' })
    if ($extra.Count) { $fail += ('re-baked maps nobody edited: ' + ($extra -join ', ')) }
    $shot = Join-Path $SS_Root 'work\_shot3d.png'
    $fs = [IO.File]::Create($shot)
    $task = $script:SS_ViewWeb.CoreWebView2.CapturePreviewAsync([Microsoft.Web.WebView2.Core.CoreWebView2CapturePreviewImageFormat]::Png, $fs)
    while (-not $task.IsCompleted) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 }
    $fs.Dispose()
    if (-not $had) { [void](Get-Ops).Remove($tex.Rel) }
    if ($script:SS_ViewForm) { $script:SS_ViewForm.Close() }
    if ($fail.Count) { Write-Host ('SMOKE19 FAIL: ' + ($fail -join ' | ')); $frm.Dispose(); exit 1 }
    Write-Host ('SMOKE19 OK: 3D view rendered {0}/{1} slots, an APPLY re-rendered it by itself with only Body_D re-baked; capture {2}' -f $l1.bound, $l1.slots, $shot)
    $frm.Dispose()
    exit 0
}
if ($env:RS_SS_SMOKE -eq '2') {
    # deep smoke: open a cached skin and drive the edit flow without showing the form
    for ($i = 0; $i -lt $lstHeroes.Items.Count; $i++) { if (((LabelId ([string]$lstHeroes.Items[$i])) -eq '1047')) { $lstHeroes.SelectedIndex = $i; break } }
    Refresh-SkinList
    for ($i = 0; $i -lt $lstSkins.Items.Count; $i++) { if (((LabelId ([string]$lstSkins.Items[$i])) -eq '1047001')) { $lstSkins.SelectedIndex = $i; break } }
    Open-Skin '1047001'
    $script:SelTex = @($script:TexItems | Where-Object Role -eq 'color')[0]
    Set-PanelFromOp $null
    $rbRecolor.Checked = $true
    Show-Preview
    $op = Get-PanelOp
    # two-layer stack: tint then hue shift, previewed + saved + reloaded
    (Get-Ops)[$script:SelTex.Rel] = @($op, @{ mode = 'hueshift'; hueShift = 40; strength = 1.0 })
    Refresh-Thumb $script:SelTex
    Show-Preview
    $txtModName.Text = 'SmokeDeep'; $txtDisplay.Text = 'Smoke Deep'
    $saved = Save-Design
    $chk = Get-Content -LiteralPath $saved -Raw | ConvertFrom-Json
    $firstProp = @($chk.ops.PSObject.Properties)[0]
    $nLayers = @(SS-OpLayers $firstProp.Value).Count
    Write-Host ('SMOKE2 OK: {0} textures, preview={1}, op={2}, design={3}, json-layers={4}' -f $script:TexItems.Count, [bool]$picMod.Image, $op.mode, [bool]$saved, $nLayers)
    $frm.Dispose()
    exit 0
}
if ($env:RS_SS_SMOKE -eq '5') {
    # linked-map smoke: skin 1011001 carries Hulk / Banner / enraged Hulk side by
    # side (T_1011001_1011_Body_D, _1012_, _1013_), so an edit to one has to land
    # on the other two or the mod half-changes in game. No window is shown.
    for ($i = 0; $i -lt $lstHeroes.Items.Count; $i++) { if (((LabelId ([string]$lstHeroes.Items[$i])) -eq '1011')) { $lstHeroes.SelectedIndex = $i; break } }
    Refresh-SkinList
    Open-Skin '1011001'
    $nGroups = @($script:Links.Keys).Count
    $tex = @($script:TexItems | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.Rel) -eq 'T_1011001_1011_Body_D' })[0]
    if (-not $tex) { Write-Host 'SMOKE5 FAIL: T_1011001_1011_Body_D not in this skin'; $frm.Dispose(); exit 1 }
    $lk = $script:Links[$tex.Rel]
    if (-not $lk) { Write-Host 'SMOKE5 FAIL: Body_D has no links'; $frm.Dispose(); exit 1 }

    # 1. the certain twins are found, and the panel would tick the box for them
    $twins = @($lk.Others | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) } | Sort-Object)
    $sure = [bool]$lk.Sure

    # 2. applying mirrors onto them
    $script:SelTex = $tex
    Set-PanelFromOp $null
    $rbRecolor.Checked = $true
    $op = Get-PanelOp
    $ops = Get-Ops
    $ops[$tex.Rel] = ,$op
    $chkLinked.Checked = $true
    $mirrored = Mirror-ToLinked $tex.Rel (,$op)
    $landed = @($lk.Others | Where-Object { $ops.ContainsKey($_) }).Count

    # 3. the layers really were cloned, not shared - editing one must not move the other
    $twinRel = @($lk.Others)[0]
    $ops[$tex.Rel][0]['strength'] = 0.25
    $independent = ((SS-OpVal $ops[$twinRel][0] 'strength' 1) -ne 0.25)

    # 4. reverting takes them back with it
    $ops.Remove($tex.Rel)
    [void](Mirror-ToLinked $tex.Rel @())
    $cleared = @($lk.Others | Where-Object { $ops.ContainsKey($_) }).Count

    # 5. a different prop must NOT be linked: Peni's Girl vs Robot body keys the
    #    same but is only ever a "maybe", never applied on its own
    $peniOk = $true
    try {
        $peni = SS-LinkGroups @('Marvel\Content\x\T_1042001_Girl_Body_D.png', 'Marvel\Content\x\T_1042001_Robot_Body_D.png')
        $peniOk = ($peni.Count -eq 0)      # same folder + different prefixes = dropped outright
    } catch { $peniOk = $false }

    $ok = $sure -and ($twins.Count -eq 2) -and ($mirrored -eq 2) -and ($landed -eq 2) -and $independent -and ($cleared -eq 0) -and $peniOk
    Write-Host ('SMOKE5 {0}: {1} linked map(s) in skin, Body_D twins=[{2}] sure={3}, mirrored={4} landed={5}, cloned-not-shared={6}, revert-cleared={7}, different-props-rejected={8}' -f `
        $(if ($ok) { 'OK' } else { 'FAIL' }), $nGroups, ($twins -join ','), $sure, $mirrored, $landed, $independent, ($cleared -eq 0), $peniOk)
    $frm.Dispose()
    exit $(if ($ok) { 0 } else { 1 })
}
if ($env:RS_SS_SMOKE -eq '10') {
    # Material colour editing must only ever offer things that ARE colours.
    # White Fox is the case that broke: a bulk retint wrote 102 shading-ramp
    # steps, a portal POSITION and three tangent vectors, and the skin came out
    # broken in game. No window.
    for ($i = 0; $i -lt $lstHeroes.Items.Count; $i++) { if (((LabelId ([string]$lstHeroes.Items[$i])) -eq '1060')) { $lstHeroes.SelectedIndex = $i; break } }
    Refresh-SkinList
    Open-Skin '1060500'
    Load-ColorItems 'mat'
    $names = @($script:ColorItems | ForEach-Object { $_.Name } | Sort-Object -Unique)
    $banned = @('PortalCenter', 'TangentA', 'TangentB', 'Tangent', 'RampLightDir', 'LightDir_LineSpec', 'AnisoParamMix', 'AnisoParamMix2')
    $leaked = @($banned | Where-Object { $names -contains $_ })
    $okBanned = ($leaked.Count -eq 0)
    $okKept = ($names -contains 'BaseTint')
    # nothing offered may sit outside 0..1 - a picker cannot express it
    $outOfRange = @($script:ColorItems | Where-Object {
        ([Math]::Max($_.R, [Math]::Max($_.G, $_.B)) -gt 1.001) -or ([Math]::Min($_.R, [Math]::Min($_.G, $_.B)) -lt -0.001)
    })
    $okRange = ($outOfRange.Count -eq 0)
    # the shading ramp stays editable by hand but is held out of bulk
    $nShade = @($script:ColorItems | Where-Object { $_.Role -eq 'shade' }).Count
    $okShade = ($nShade -gt 0) -and (@($script:ColorItems | Where-Object { $_.Role -ne 'shade' }).Count -lt $script:ColorItems.Count)
    # a stale design's bad op must be pruned rather than shipped
    $ops = Get-ColorOps
    $victim = @($script:ColorItems | Where-Object { $_.Name -eq 'BaseTint' })[0]
    $okPrune = $false
    if ($victim) {
        $ops[$victim.Rel] = @{}
        $ops[$victim.Rel]['{0}_{1}' -f $victim.Export, $victim.Ordinal] = @{ export = $victim.Export; ordinal = $victim.Ordinal; name = 'BaseTint'; r = 0.5; g = 0.5; b = 0.5 }
        $ops[$victim.Rel]['9999_9999'] = @{ export = 9999; ordinal = 9999; name = 'PortalCenter'; r = 0.5; g = 0.5; b = 0.5 }
        $gone = Prune-BadColorOps
        $okPrune = ($gone -eq 1) -and ($ops.ContainsKey($victim.Rel)) -and ($ops[$victim.Rel].Count -eq 1)
    }
    $ok = $okBanned -and $okKept -and $okRange -and $okShade -and $okPrune
    Write-Host ('SMOKE10 {0}: {1} colour params offered | vectors excluded={2}{3} BaseTint kept={4} all-in-0..1={5} shade-held-from-bulk={6} ({7} ramp steps) prune-drops-stale={8}' -f `
        $(if ($ok) { 'OK' } else { 'FAIL' }), $script:ColorItems.Count, $okBanned,
        $(if ($leaked.Count) { " (leaked: $($leaked -join ','))" } else { '' }), $okKept, $okRange, $okShade, $nShade, $okPrune)
    $frm.Dispose()
    exit $(if ($ok) { 0 } else { 1 })
}
if ($env:RS_SS_SMOKE -eq '9') {
    # layout check for the What-paints-this dialog. Pair with RS_SS_PAINTIDSHOT
    # to get a PNG of it without a window ever appearing on screen.
    for ($i = 0; $i -lt $lstHeroes.Items.Count; $i++) { if (((LabelId ([string]$lstHeroes.Items[$i])) -eq '1060')) { $lstHeroes.SelectedIndex = $i; break } }
    Refresh-SkinList
    Open-Skin '1060500'
    Show-PaintId
    $frm.Dispose()
    exit 0
}
if ($env:RS_SS_SMOKE -eq '7') {
    # "what paints this?" end to end, no window. White Fox's tie is the case that
    # made this feature exist: it is NOT painted by any texture you can edit, it
    # is a violet BaseTint on MI_10600_1060500_Laser_02. If this ever stops
    # saying so, the trace has broken.
    for ($i = 0; $i -lt $lstHeroes.Items.Count; $i++) { if (((LabelId ([string]$lstHeroes.Items[$i])) -eq '1060')) { $lstHeroes.SelectedIndex = $i; break } }
    Refresh-SkinList
    Open-Skin '1060500'
    $gltf = Find-SkinGltf
    if (-not $gltf) { Write-Host 'SMOKE7 SKIP: no mesh export for 1060500 - run OPEN IN BLENDER once'; $frm.Dispose(); exit 0 }
    $script:piDir = SS-EnsurePaintId '1060500' $gltf { param($m) Write-Host "  $m" }
    $script:piLegend = Get-Content -LiteralPath (Join-Path $script:piDir 'legend.json') -Raw | ConvertFrom-Json
    $script:piMatTex = Get-Content -LiteralPath (SS-EnsureMatTextures '1060500' { param($m) Write-Host "  $m" }) -Raw | ConvertFrom-Json
    $script:piColors = Get-Content -LiteralPath (SS-EnsureColorCache '1060500' { param($m) Write-Host "  $m" } $pump 'mat') -Raw | ConvertFrom-Json
    $script:piView = 'front'
    $script:piId = [SkinArt]::Load((Join-Path $script:piDir 'id-front.png'))
    $script:piUv = [SkinArt]::Load((Join-Path $script:piDir 'uv-front.png'))
    # stand-ins for the dialog's controls so the real reporting code runs
    $script:piOut = New-Object System.Windows.Forms.Label
    $script:piCrop = New-Object System.Windows.Forms.PictureBox
    $script:piCoord = New-Object System.Windows.Forms.Label
    $script:piParamImgs = New-Object System.Windows.Forms.ImageList
    $script:piParamImgs.ImageSize = New-Object System.Drawing.Size(16, 16)
    $script:piParams = New-Object System.Windows.Forms.ListView
    $script:piParams.SmallImageList = $script:piParamImgs
    1..5 | ForEach-Object { [void]$script:piParams.Columns.Add('', 60) }
    $script:piTexList = New-Object System.Windows.Forms.ListView
    1..3 | ForEach-Object { [void]$script:piTexList.Columns.Add('', 60) }

    # find any pixel belonging to the tie's material, rather than hard-coding a
    # spot that a re-render could move
    $target = 'MI_10600_1060500_Laser_02'
    $lg = $script:piLegend.PSObject.Properties[$target]
    if (-not $lg) { Write-Host "SMOKE7 FAIL: $target not in the legend"; $frm.Dispose(); exit 1 }
    $want = @((PiToSrgb $lg.Value[0]), (PiToSrgb $lg.Value[1]), (PiToSrgb $lg.Value[2]))
    $hx = -1; $hy = -1
    for ($y = 0; $y -lt $script:piId.Height -and $hx -lt 0; $y += 2) {
        for ($x = 0; $x -lt $script:piId.Width; $x += 2) {
            $p = $script:piId.GetPixel($x, $y)
            if ([Math]::Abs($p.R - $want[0]) -le 2 -and [Math]::Abs($p.G - $want[1]) -le 2 -and [Math]::Abs($p.B - $want[2]) -le 2) { $hx = $x; $hy = $y; break }
        }
    }
    if ($hx -lt 0) { Write-Host 'SMOKE7 FAIL: no pixel of the tie material in the render'; $frm.Dispose(); exit 1 }
    Report-PaintId $hx $hy
    $t = [string]$script:piOut.Text
    $okMat  = $t.Contains($target)
    $okWarn = $t.Contains('multiply the texture')
    # the tint is a ROW now, with the data needed to jump straight to it
    $tintRow = @($script:piParams.Items | Where-Object { $_.SubItems[1].Text -eq 'BaseTint' })[0]
    $okTint = ($null -ne $tintRow) -and ($tintRow.SubItems[2].Text -eq '#8D6C89') -and ($tintRow.SubItems[4].Text -eq 'tints the texture')
    $okTex  = @($script:piTexList.Items | Where-Object { $_.Text -eq 'T_10600_1060500_Equip_01_D' }).Count -eq 1
    $okAtlas = ([string]$script:piCoord.Text).Contains('px of')
    # both copies of the material must be offered, not just one
    $okCopies = (@($script:piParams.Items | Where-Object { $_.SubItems[1].Text -eq 'BaseTint' -and $_.SubItems[3].Text -eq 'lobby' }).Count -ge 1) -and
                (@($script:piParams.Items | Where-Object { $_.SubItems[1].Text -eq 'BaseTint' -and $_.SubItems[3].Text -eq 'in-match' }).Count -ge 1)
    # and the jump actually lands on that exact parameter in the Materials list
    $okJump = $false
    if ($tintRow -and $tintRow.Tag) {
        $tg = $tintRow.Tag
        $okJump = (Select-ColorItemBy $tg.Asset $tg.Name $tg.Export $tg.Ordinal) -and
                  ($script:SelColor) -and ($script:SelColor.Name -eq 'BaseTint') -and
                  ([IO.Path]::GetFileNameWithoutExtension($script:SelColor.Rel) -eq $target)
    }
    Set-Mode 'tex'
    # and a control case: the ear cups' material must NOT be flagged as tinted
    $eq = 'MI_10600_1060500_Equip_01'
    $lg2 = $script:piLegend.PSObject.Properties[$eq]
    $okEquip = $true
    if ($lg2) {
        $w2 = @((PiToSrgb $lg2.Value[0]), (PiToSrgb $lg2.Value[1]), (PiToSrgb $lg2.Value[2]))
        $ex = -1; $ey = -1
        for ($y = 0; $y -lt $script:piId.Height -and $ex -lt 0; $y += 2) {
            for ($x = 0; $x -lt $script:piId.Width; $x += 2) {
                $p = $script:piId.GetPixel($x, $y)
                if ([Math]::Abs($p.R - $w2[0]) -le 2 -and [Math]::Abs($p.G - $w2[1]) -le 2 -and [Math]::Abs($p.B - $w2[2]) -le 2) { $ex = $x; $ey = $y; break }
            }
        }
        if ($ex -ge 0) {
            Report-PaintId $ex $ey
            $okEquip = ([string]$script:piOut.Text).Contains($eq) -and
                       (@($script:piParams.Items | Where-Object { $_.SubItems[4].Text -eq 'tints the texture' }).Count -eq 0)
        }
    }
    $ok = $okMat -and $okTint -and $okWarn -and $okTex -and $okAtlas -and $okCopies -and $okJump -and $okEquip
    Write-Host ('SMOKE7 {0}: tie pixel {1},{2} -> material={3} tint-row={4} warned={5} texture-row={6} atlas={7} both-copies={8} jump-lands={9} | white-tint material clean={10}' -f `
        $(if ($ok) { 'OK' } else { 'FAIL' }), $hx, $hy, $okMat, $okTint, $okWarn, $okTex, $okAtlas, $okCopies, $okJump, $okEquip)
    $frm.Dispose()
    exit $(if ($ok) { 0 } else { 1 })
}
if ($env:RS_SS_SMOKE -eq '6') {
    # colour-family band: a hand-picked band must move ONLY that hue family.
    # White Fox's specular atlas is the case auto-detect cannot serve - a magenta
    # tie rim (hue ~304) and green (hue ~139) share one sheet, and auto can only
    # ever pick the bigger one. No window is shown.
    for ($i = 0; $i -lt $lstHeroes.Items.Count; $i++) { if (((LabelId ([string]$lstHeroes.Items[$i])) -eq '1060')) { $lstHeroes.SelectedIndex = $i; break } }
    Refresh-SkinList
    Open-Skin '1060500'
    $tex = @($script:TexItems | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.Rel) -eq 'T_10600_1060500_Equip_01_S' })[0]
    if (-not $tex) { Write-Host 'SMOKE6 FAIL: Equip_01_S not found'; $frm.Dispose(); exit 1 }
    if ($tex.Role -ne 'spec') { Write-Host "SMOKE6 FAIL: _S role is '$($tex.Role)', expected 'spec'"; $frm.Dispose(); exit 1 }

    $mx = 159; $my = 120       # a magenta pixel (the tie rim), hue ~304
    $gx = 204; $gy = 105       # a green pixel on the same sheet,  hue ~139
    function HueOf($bmp, $x, $y) { [double]$bmp.GetPixel($x, $y).GetHue() }
    function HueGap([double]$a, [double]$b) { $d = [Math]::Abs($a - $b) % 360.0; if ($d -gt 180) { $d = 360 - $d }; $d }
    $gold = '#FFC83C'          # hue ~43
    $van = [SkinArt]::Load($tex.Png)
    $auto = [SkinArt]::AutoBandCenter($van)
    $mag0 = HueOf $van $mx $my; $grn0 = HueOf $van $gx $gy
    $van.Dispose()

    # 1. band aimed at the magenta: magenta goes gold, green must not budge
    $b1 = SS-ApplySingleBitmap ([SkinArt]::Load($tex.Png)) @{ mode = 'huerange'; color = $gold; strength = 1.0; bandCenter = 300.0; bandWidth = 25.0 }
    $m1 = HueOf $b1 $mx $my; $g1 = HueOf $b1 $gx $gy; $b1.Dispose()
    # 2. band aimed at the green: the other way round
    $b2 = SS-ApplySingleBitmap ([SkinArt]::Load($tex.Png)) @{ mode = 'huerange'; color = $gold; strength = 1.0; bandCenter = 140.0; bandWidth = 25.0 }
    $m2 = HueOf $b2 $mx $my; $g2 = HueOf $b2 $gx $gy; $b2.Dispose()
    # 3. no band keys at all = the old auto behaviour, so old designs are safe
    $b3 = SS-ApplySingleBitmap ([SkinArt]::Load($tex.Png)) @{ mode = 'huerange'; color = $gold; strength = 1.0 }
    $m3 = HueOf $b3 $mx $my; $g3 = HueOf $b3 $gx $gy; $b3.Dispose()
    # 4. the preview mask agrees with the op about how much is selected
    $pv = [SkinArt]::Load($tex.Png)
    $mask = [SkinArt]::BandPreview($pv, 300.0, 25.0); $cov = [SkinArt]::LastCoverage
    $mask.Dispose(); $pv.Dispose()

    # 5. the panel carries the band into an op and reads it back - no window
    #    needed, and this is the plumbing that actually has to hold
    $script:SelTex = $tex
    $rbRecolor.Checked = $true
    $cmbMode.SelectedItem = 'Recolor color family'
    $pnlColor.BackColor = [System.Drawing.Color]::FromArgb(255, 200, 60)
    $script:BandCenter = 206.0; $script:BandWidth = 22.0
    $opP = Get-PanelOp
    $carried = ($opP.mode -eq 'huerange' -and $opP.bandCenter -eq 206.0 -and $opP.bandWidth -eq 22.0)
    $script:BandCenter = -1.0; $script:BandWidth = 0.0
    Set-PanelFromOp $opP
    $restored = ($script:BandCenter -eq 206.0 -and $script:BandWidth -eq 22.0 -and $btnBand.Text -eq '206° ±22')
    # an op with no band keys must read back as auto
    Set-PanelFromOp @{ mode = 'huerange'; color = $gold; strength = 1.0 }
    $autoBack = ($script:BandCenter -lt 0 -and $btnBand.Text -eq 'auto')

    $magMoved1 = (HueGap $m1 43.0) -lt 12    # magenta -> gold
    $grnHeld1  = (HueGap $g1 $grn0) -lt 2    # green untouched
    $grnMoved2 = (HueGap $g2 43.0) -lt 12
    $magHeld2  = (HueGap $m2 $mag0) -lt 2
    $autoMoved = (HueGap $m3 43.0) -lt 12    # auto lands on the magenta family here
    $covOk = ($cov -gt 0.2 -and $cov -lt 0.95)
    $ok = $magMoved1 -and $grnHeld1 -and $grnMoved2 -and $magHeld2 -and $autoMoved -and $covOk -and $carried -and $restored -and $autoBack
    Write-Host ('SMOKE6 {0}: auto={1:N0}deg  vanilla mag={2:N0} grn={3:N0} | band300 -> mag={4:N0} grn={5:N0} | band140 -> mag={6:N0} grn={7:N0} | no-band -> mag={8:N0} | mask covers {9:P0} | panel carried={10} restored={11} auto-reads-back={12}' -f `
        $(if ($ok) { 'OK' } else { 'FAIL' }), $auto, $mag0, $grn0, $m1, $g1, $m2, $g2, $m3, $cov, $carried, $restored, $autoBack)
    $frm.Dispose()
    exit $(if ($ok) { 0 } else { 1 })
}
if ($env:RS_SS_SMOKE -eq '3') {
    # color smoke: open a cached skin, switch to Colors, apply + bulk, save + reload
    for ($i = 0; $i -lt $lstHeroes.Items.Count; $i++) { if (((LabelId ([string]$lstHeroes.Items[$i])) -eq '1031')) { $lstHeroes.SelectedIndex = $i; break } }
    Refresh-SkinList
    for ($i = 0; $i -lt $lstSkins.Items.Count; $i++) { if (((LabelId ([string]$lstSkins.Items[$i])) -eq '1031001')) { $lstSkins.SelectedIndex = $i; break } }
    Open-Skin '1031001'
    Set-Mode 'mat'
    $ci = @($script:ColorItems | Where-Object Role -eq 'rim')[0]
    if (-not $ci) { $ci = $script:ColorItems[0] }
    $script:SelColor = $ci
    Apply-ColorTo $ci ([System.Drawing.Color]::FromArgb(255, 0, 255))
    $applied = [bool](Get-ColorEdit $ci)
    $txtModName.Text = 'SmokeColor'; $txtDisplay.Text = 'Smoke Color'
    $saved = Save-Design
    $chk = Get-Content -LiteralPath $saved -Raw | ConvertFrom-Json
    $nAssets = @($chk.colorOps.PSObject.Properties).Count
    Write-Host ('SMOKE3 OK: colorItems={0}, rimApplied={1}, saved={2}, colorOps-assets={3}, edits={4}' -f $script:ColorItems.Count, $applied, [bool]$saved, $nAssets, (Count-ColorEdits))
    $frm.Dispose()
    exit 0
}
if ($env:RS_SS_SMOKE -eq '4') {
    # particle smoke: open a cached skin, switch to Particles, recolor one effect
    for ($i = 0; $i -lt $lstHeroes.Items.Count; $i++) { if (((LabelId ([string]$lstHeroes.Items[$i])) -eq '1031')) { $lstHeroes.SelectedIndex = $i; break } }
    Refresh-SkinList
    for ($i = 0; $i -lt $lstSkins.Items.Count; $i++) { if (((LabelId ([string]$lstSkins.Items[$i])) -eq '1031001')) { $lstSkins.SelectedIndex = $i; break } }
    Open-Skin '1031001'
    Set-Mode 'fx'
    $ci = $script:ColorItems[0]
    $script:SelColor = $ci
    Apply-ColorTo $ci ([System.Drawing.Color]::FromArgb(255, 0, 255))
    $nCurves = @($ci.Curves).Count
    $applied = [bool](Get-ColorEdit $ci)
    $txtModName.Text = 'SmokeFx'; $txtDisplay.Text = 'Smoke Fx'
    $saved = Save-Design
    $chk = Get-Content -LiteralPath $saved -Raw | ConvertFrom-Json
    $nAssets = @($chk.colorOps.PSObject.Properties).Count
    $firstEdits = @($chk.colorOps.PSObject.Properties)[0].Value
    $hasKind = [bool]($firstEdits[0].PSObject.Properties['kind'])
    Write-Host ('SMOKE4 OK: fxItems={0}, curvesInFirst={1}, applied={2}, saved={3}, colorOps-assets={4}, edits={5}, kindStored={6}' -f $script:ColorItems.Count, $nCurves, $applied, [bool]$saved, $nAssets, (Count-ColorEdits), $hasKind)
    $frm.Dispose()
    exit 0
}
[void]$frm.ShowDialog()

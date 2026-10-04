# build_live_mod.ps1 - build the Skin Studio in-game live-preview mod.
#
# Two files ship:
#   1. the widget          - our cooked UserWidget (the F6 refresh graph)
#   2. WBP_UIDPanel        - the vanilla login panel, byte-patched so its existing
#                            child widget class points at ours instead of
#                            WBP_BackstageShader_Progress02
#
# The patch is an equal-length name-table string swap, so nothing in the package
# moves and no offset needs fixing up. See INGAME_MENU.md "route B".
#
# Usage:
#   .\build_live_mod.ps1                     # build the real widget, rrcli
#   .\build_live_mod.ps1 -Install
#   .\build_live_mod.ps1 -Widget WBP_SkinLivePreviewBootstrap02 -NoGraphCheck -Install
#   .\build_live_mod.ps1 -Packer retoc -Install
#
# -Widget must stay 30 characters: the four swapped strings have to match the
# victim's byte lengths exactly (leaf 30, path 63, _C 32, Default__ 41).

[CmdletBinding()]
param(
    [switch]$Install,
    [string]$Widget = 'WBP_SkinLivePreviewBootstrap01',
    [ValidateSet('rrcli','retoc')]
    [string]$Packer = 'rrcli',
    [switch]$NoGraphCheck,
    [switch]$KeepChildProps,
    # v2: the panel the bootstrap creates - the whole in-game editor lives here.
    # -PanelWidget '' builds the v1 bootstrap alone (no panel shipped).
    [string]$PanelWidget = 'WBP_SkinLiveEditor',
    # how the panel asks Rivals for the mouse (patch_hud_calls.ps1): NoBlock =
    # MarvelHUD.NeedInputModeUINoBlock (keys like F7 keep reaching the game),
    # Block = NeedInputModeUI, None = no HUD call (the old SetInputMode only).
    # Switching needs no Unreal work - just rebuild with another value.
    [ValidateSet('NoBlock', 'Block', 'None')]
    [string]$HudMode = 'NoBlock',
    # the in-game Build mod button's refresh (patch_live_calls.ps1): repoint the
    # manifest reader and the mount stand-ins at MarvelFileUtil / NePatchUtility.
    # -NoLiveMount ships the stand-ins unpatched (reader = a console variable,
    # mount = a save-slot check): the button still builds and installs, and the
    # hero keeps its PNG preview.
    [switch]$NoLiveMount,
    [int]$ChildExportSize = 6,
    # '!!' first: Project Galacta also overrides WBP_UIDPanel (as !ProjectGalacta)
    # and only one override loads. The engine mounts paks in reverse name order
    # and a later mount wins a tie (UE 5.3 FilePackageStore / IoDispatcher), so
    # the first name wins - and our bootstrap then hosts Galacta's widget too.
    [string]$ModName   = '!!SkinLive',
    [string]$CookedDir = 'D:/SkinLiveUE/Saved/Cooked/Windows/SkinLive/Content/Marvel/SkinLive/UI/Widgets',
    [string]$Vanilla   = '',     # leave empty to extract fresh from the live game (recommended)
    [string]$UIChunk   = 'pakchunkUI-Windows.utoc',
    [string]$Work      = 'D:/SkinLiveUE/pack',
    [string]$Rr        = 'C:/rs/tools/rrcli/retoc-rivals-cli.exe',
    [string]$Retoc     = 'C:/rs/tools/retoc.exe',
    [string]$Paks      = 'C:/Program Files (x86)/Steam/steamapps/common/MarvelRivals/MarvelGame/Marvel/Content/Paks'
)

$ErrorActionPreference = 'Stop'
function Log($m) { Write-Host ("  " + $m) }

# ---------------------------------------------------------------- the swap table
# Every pair MUST be the same byte length: the name table is length-prefixed and
# the package summary stores offsets past it, so a length change shifts everything
# after it. Longest first - the short leaf is a substring of the others, and the
# trailing-NUL test only keeps them apart once the longer ones are already gone.
$ourPath = '/Game/Marvel/SkinLive/UI/Widgets/' + $Widget
$swaps = @(
    @{ old = '/Game/Marvel/UI/Blueprints/Squad/WBP_BackstageShader_Progress02'; new = $ourPath },
    @{ old = 'Default__WBP_BackstageShader_Progress02_C'; new = 'Default__' + $Widget + '_C' },
    @{ old = 'WBP_BackstageShader_Progress02_C';          new = $Widget + '_C' },
    @{ old = 'WBP_BackstageShader_Progress02';            new = $Widget }
)

Write-Host ''
Write-Host "Skin Studio - in-game live preview mod"
Write-Host "--------------------------------------"
Log "widget : $Widget"
Log "packer : $Packer"

# ---------------------------------------------------------------- preflight
foreach ($p in @("$CookedDir/$Widget.uasset", "$CookedDir/$Widget.uexp", $Paks)) {
    if (-not (Test-Path $p)) { throw "missing input: $p" }
}
if ($Packer -eq 'rrcli' -and -not (Test-Path $Rr))    { throw "missing packer: $Rr" }
if ($Packer -eq 'retoc' -and -not (Test-Path $Retoc)) { throw "missing packer: $Retoc" }
if (-not (Test-Path $Rr)) { throw "rrcli is needed for the vanilla extract: $Rr" }

# ---------------------------------------------------------------- vanilla panel
# ALWAYS take the panel out of the live game, never out of an old extraction.
# We override this package, so our copy has to be the CURRENT one - a stale
# widget override is a hard launch crash, not a cosmetic bug. (The July copy in
# C:\rs\uifull is already three bytes out of date in its .uexp; two independent
# extraction paths agree against it.)
$panelLine = '../../../Marvel/Content/Marvel/UI/Blueprints/Login/WBP_UIDPanel.uasset'
if (-not $Vanilla) {
    $vanRoot = Join-Path $Work 'vanilla'
    if (Test-Path $vanRoot) { Remove-Item $vanRoot -Recurse -Force }
    $utoc = Join-Path $Paks $UIChunk
    if (-not (Test-Path $utoc)) { throw "missing UI chunk: $utoc" }
    # -o is not optional: without it rrcli extracts next to the INPUT, i.e. into
    # the game's own Paks directory.
    $unp = & $Rr unpack $utoc -o $vanRoot -f $panelLine --game-paks-dir $Paks 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("vanilla extract failed: " + (($unp | Select-Object -Last 2) -join ' | ')) }
    $Vanilla = Join-Path $vanRoot 'Marvel/Content/Marvel/UI/Blueprints/Login'
}
foreach ($p in @("$Vanilla/WBP_UIDPanel.uasset", "$Vanilla/WBP_UIDPanel.uexp")) {
    if (-not (Test-Path $p)) { throw "missing vanilla panel: $p" }
}
Log ("vanilla panel  uasset {0}" -f (Get-FileHash "$Vanilla/WBP_UIDPanel.uasset" -Algorithm SHA256).Hash.Substring(0,16))
Log ("vanilla panel  uexp   {0}" -f (Get-FileHash "$Vanilla/WBP_UIDPanel.uexp"   -Algorithm SHA256).Hash.Substring(0,16))

# ---------------------------------------------------------------- widget checks
$wAsset = Get-Item "$CookedDir/$Widget.uasset"
$bytes  = [System.IO.File]::ReadAllBytes($wAsset.FullName)
$txt    = [System.Text.Encoding]::ASCII.GetString($bytes)

# Rivals ships UNVERSIONED packages: after the tag and LegacyFileVersion the
# summary is all zeroes (no UE3/UE4/UE5 version, no custom version array). A
# plain "-run=Cook" writes a VERSIONED package (LegacyUE3Version 864) and rrcli
# rejects it with "Expected to find zero UE3 version, got 864". UAT passes
# -unversioned by default; a hand-run cook commandlet does not.
$legacyUE3 = [System.BitConverter]::ToInt32($bytes, 8)
if ($legacyUE3 -ne 0) {
    throw "cooked widget is VERSIONED (LegacyUE3Version $legacyUE3). Re-cook with -unversioned."
}
Log "cooked widget is unversioned"

# ...but the PROPERTY serialization must be the opposite: TAGGED, not unversioned.
# Unversioned properties are matched by POSITION in the class layout, so a package
# cooked against stock UE 5.3 decodes against Marvel's modified engine classes and
# desyncs - the game dies on load with
#   ObjectSerializationError: ... Bad export index <garbage>/<n>
# and it does this even for an EMPTY UserWidget's CDO, so it looks nothing like a
# problem with your graph. Fix is Config/DefaultEngine.ini:
#   [Core.System]
#   CanUseUnversionedPropertySerialization=False
# Reference point: the working published mod Galacta ships PackageFlags 0x80040200
# (no PKG_UnversionedProperties); an unfixed cook here gives 0x80002200.
$p = 4
$legacy = [System.BitConverter]::ToInt32($bytes, $p); $p += 4
if ($legacy -ne -4) { $p += 4 }                                   # LegacyUE3Version
$p += 12                                                          # UE4, UE5, licensee
$ncustom = [System.BitConverter]::ToInt32($bytes, $p); $p += 4
$p += $ncustom * 20
$p += 4                                                           # TotalHeaderSize
$flen = [System.BitConverter]::ToInt32($bytes, $p); $p += 4
$p += $(if ($flen -ge 0) { $flen } else { -2 * $flen })           # FolderName
$pkgFlags = [System.BitConverter]::ToUInt32($bytes, $p)
if ($pkgFlags -band 0x2000) {
    throw ("cooked widget uses UNVERSIONED PROPERTY serialization (PackageFlags 0x{0:X8}). This crashes Marvel Rivals on load. Set CanUseUnversionedPropertySerialization=False under [Core.System] in D:\SkinLiveUE\Config\DefaultEngine.ini and re-cook." -f $pkgFlags)
}
Log ("cooked widget properties are TAGGED  (PackageFlags 0x{0:X8})" -f $pkgFlags)

# A Widget Blueprint saved WITHOUT being compiled cooks to an empty class - same
# file names, no bytecode, and a completely clean cook log. Cheapest tell: the
# uexp is a few hundred bytes instead of a few thousand, and the name table has
# no ExecuteUbergraph_ entry.
if (-not $NoGraphCheck) {
    # v2: the refresh chain moved into the panel widget (checked further down);
    # the bootstrap's own job is to find or make that panel on F6 / F7.
    # 2026-09-26: + hosting Project Galacta's widget and the login splash
    # 2026-09-26 evening: + AutoTick (hero announce, Galacta's F7 pressed for her)
    foreach ($needle in @("ExecuteUbergraph_$Widget", 'GetAllWidgetsOfClass', $PanelWidget, 'LoadClassAsset_Blocking', 'GetCurrentLevelName', 'Splash',
                         'AutoTick', 'K2_SetTimerDelegate', 'K2_SetTimer', 'GetAllActorsOfClass', 'AutoStart')) {
        if ($txt.IndexOf($needle) -lt 0) {
            throw "cooked widget has no '$needle' - it was saved without being compiled. Open it in UE, press Compile, Save, then re-cook."
        }
    }
    Log ("cooked widget graph OK  ({0:N0} bytes uasset)" -f $wAsset.Length)
    # string literals live in the bytecode (.uexp): the Galacta class path and
    # the login-level test prove the hosting chain survived the compile
    $bExp = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes("$CookedDir/$Widget.uexp"))
    foreach ($lit in @('/Game/Marvel/ProjectGalacta/UI/WBP_Galacta.WBP_Galacta_C', 'ClientEntry',
                      'SkinLiveGalToggle', '/Game/Marvel/ProjectGalacta/Blueprints/GAL_ModLoader.GAL_ModLoader_C', 'ToggleMods', 'gal_1', 'gal_0', 'SkinLiveOn', 'SLA_')) {
        if ($bExp.IndexOf($lit) -lt 0) { throw "bootstrap's code has no '$lit' - the Galacta host, splash or AutoTick chain is missing (unwired nodes are pruned silently)." }
    }
    Log 'bootstrap hosts Project Galacta when installed, shows the login splash, and runs AutoTick (hero announce + Galacta''s F7)'

    # Report the graph's SHAPE, so a graph edit can be confirmed from the cooked
    # class rather than from the editor looking right - unreachable nodes are
    # pruned silently, so a forgotten wire cooks clean and looks like success.
    # Needles calibrated against the shipped v1 class: it has
    # CallFunc_GetAttachedActors_OutActors and neither of the other two.
    # v2: the character walk lives in the PANEL widget, not the bootstrap, so
    # read the shape out of whichever class actually carries it
    $walkTxt = $txt
    if ($PanelWidget -and (Test-Path "$CookedDir/$PanelWidget.uasset")) {
        $walkTxt = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes("$CookedDir/$PanelWidget.uasset"))
    }
    $wide     = $walkTxt.IndexOf('GetAllActorsOfClass') -ge 0
    $pawnOnly = $walkTxt.IndexOf('GetAttachedActors') -ge 0
    $deferred = $walkTxt.IndexOf('MaterialInstanceConstant') -ge 0
    $search = if ($wide -and $pawnOnly) { 'all-actors + pawn' }
              elseif ($wide)            { 'all-actors (lobby and match)' }
              elseif ($pawnOnly)        { 'pawn + attached (match only)' }
              else                      { 'UNKNOWN' }
    $mid = if ($deferred) { 'deferred (per edited texture)' } else { 'eager (per material slot)' }
    Log ("graph shape: search = {0}" -f $search)
    Log ("             MID    = {0}" -f $mid)
    if ($search -eq 'UNKNOWN') {
        Write-Warning "no actor search found in the cooked class - F6 will find nothing to repaint. A wire is probably missing."
    }
    # edit A without edit B: every skeletal mesh in the level gets dynamic
    # material instances minted for every slot, before anything knows whether
    # that texture was even edited. See GRAPH_RECIPE.md "v2 edits".
    if ($wide -and -not $deferred) {
        Write-Warning "level-wide search with EAGER MIDs - this mints a dynamic material instance for every slot of every skeletal mesh in the level on each F6. Do edit B (Get Material + deferred Create Dynamic Material Instance) from GRAPH_RECIPE.md."
    }
} else {
    Log ("graph check skipped  ({0:N0} bytes uasset)" -f $wAsset.Length)
}

# ------------------------------------------------------- the panel widget (v2)
# WBP_SkinLiveEditor is the in-game editor: it shows the PC-drawn panel PNG,
# reports the mouse, and owns the whole texture-refresh chain. Same two package
# rules as the bootstrap - a versioned summary is rejected by rrcli, unversioned
# PROPERTIES crash the game on load.
function Test-CookedPackage([string]$path, [string]$label, [string[]]$needles) {
    if (-not (Test-Path $path)) { throw "missing cooked $label - $path. Compile, Save, then re-cook." }
    $b = [System.IO.File]::ReadAllBytes($path)
    if ([System.BitConverter]::ToInt32($b, 8) -ne 0) {
        throw "$label is VERSIONED. Re-cook with -unversioned."
    }
    $q = 4
    $lg = [System.BitConverter]::ToInt32($b, $q); $q += 4
    if ($lg -ne -4) { $q += 4 }
    $q += 12
    $nc = [System.BitConverter]::ToInt32($b, $q); $q += 4
    $q += $nc * 20 + 4
    $fl = [System.BitConverter]::ToInt32($b, $q); $q += 4
    $q += $(if ($fl -ge 0) { $fl } else { -2 * $fl })
    $pf = [System.BitConverter]::ToUInt32($b, $q)
    if ($pf -band 0x2000) {
        throw ("$label uses UNVERSIONED PROPERTY serialization (PackageFlags 0x{0:X8}) - this crashes the game on load. Set CanUseUnversionedPropertySerialization=False under [Core.System] in the project's DefaultEngine.ini and re-cook." -f $pf)
    }
    $s = [System.Text.Encoding]::ASCII.GetString($b)
    foreach ($needle in $needles) {
        if ($s.IndexOf($needle) -lt 0) {
            throw "$label has no '$needle' - either it was saved without being compiled, or a wire is missing (unreachable nodes are pruned silently)."
        }
    }
    Log ("{0} OK  (tagged, 0x{1:X8}, {2:N0} bytes)" -f $label, $pf, $b.Length)
    $s
}

$panelFiles = @()
if ($PanelWidget) {
    $pAsset = "$CookedDir/$PanelWidget.uasset"
    $needles = @()
    if (-not $NoGraphCheck) {
        $needles = @("ExecuteUbergraph_$PanelWidget", 'ImportFileAsTexture2D', 'SetTextureParameterValue',
                     'BaseColor', 'SetBrushFromTexture', 'DoesSaveGameExist', 'SaveGameToSlot',
                     'GetMousePositionOnPlatform', 'SetInputMode_GameAndUIEx',
                     # 2026-09-24: the dye-mask slot and the HUD input-mode stand-ins
                     'DyeingTexture', 'GetHUD', 'ClassIsChildOf', 'RemoveTickPrerequisiteActor', 'ForceNetUpdate',
                     # 2026-09-26: the Build mod button's mount-and-load (Galacta's method).
                     # Names only: string literals ('SkinLiveMount', '_pak.txt') live in the .uexp.
                     'MountLive', 'GetConsoleVariableStringValue', 'LoadAsset_Blocking',
                     'Conv_SoftObjPathToSoftObjRef', 'RightChop', 'SelectString',
                     # 2026-09-26: the login splash and its logo
                     'Splash', 'T_VariantWordmark', 'Delay',
                     # 2026-09-26 evening: the hero announce the bootstrap's AutoTick starts
                     'AutoStart')
    }
    $pTxt = Test-CookedPackage $pAsset 'panel widget' $needles
    $panelFiles = @($pAsset, "$CookedDir/$PanelWidget.uexp")
    if (-not $NoGraphCheck) {
        # string literals sit in the bytecode (.uexp): the Build mod flag, the
        # manifest path and the mount answer prove MountLive and the pak route
        # survived the compile (an unwired chain is pruned without a word)
        $pExp = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes("$CookedDir/$PanelWidget.uexp"))
        foreach ($lit in @('SkinLiveMount', 'SkinStudioLive/_pak.txt', 'mnt_', 'mnt_nofile', '||||', 'pk_', 'auto_')) {
            if ($pExp.IndexOf($lit) -lt 0) { throw "panel widget's code has no '$lit' - a Build mod wire is missing, or the widget was saved without compiling." }
        }
        Log 'panel widget carries the Build mod mount + pak route'
    }
    if (-not $NoGraphCheck) {
        # rewrite the stand-ins into MarvelHUD calls (see patch_hud_calls.ps1);
        # it verifies its own output and throws on anything unexpected
        $hudDir = Join-Path $Work 'hudpatch'
        if (Test-Path $hudDir) { Remove-Item $hudDir -Recurse -Force }
        & (Join-Path $PSScriptRoot 'patch_hud_calls.ps1') -Asset $pAsset -OutDir $hudDir -Mode $HudMode
        $panelFiles = @((Join-Path $hudDir "$PanelWidget.uasset"), (Join-Path $hudDir "$PanelWidget.uexp"))
        $hudNeedles = if ($HudMode -eq 'None') { @() } else { @('MarvelHUD', '/Script/Marvel', $(if ($HudMode -eq 'Block') { 'StopNeedInputModeUI' } else { 'StopNeedInputModeUINoBlock' })) }
        $null = Test-CookedPackage $panelFiles[0] "panel widget (HUD calls: $HudMode)" $hudNeedles
        if (-not $NoLiveMount) {
            # the Build mod button: reader -> MarvelFileUtil, mount -> NePatchUtility
            # (see patch_live_calls.ps1); it verifies its own output
            $liveDir = Join-Path $Work 'livepatch'
            if (Test-Path $liveDir) { Remove-Item $liveDir -Recurse -Force }
            & (Join-Path $PSScriptRoot 'patch_live_calls.ps1') -Asset $panelFiles[0] -OutDir $liveDir
            $panelFiles = @((Join-Path $liveDir "$PanelWidget.uasset"), (Join-Path $liveDir "$PanelWidget.uexp"))
            $null = Test-CookedPackage $panelFiles[0] 'panel widget (Build mod mount)' @('NePatchUtility', 'MountPak', 'MarvelFileUtil', 'LoadFromFileWithFullFilePath')
        } else {
            Log 'Build mod mount NOT patched (-NoLiveMount): builds install, the hero keeps the PNG preview'
        }
    }
    if (-not $NoGraphCheck) {
        # ★ the repeat-press fix: the vanilla texture name must be read off the
        # MID's PARENT. Reading it off the MID itself works once - after that the
        # MID holds the imported Texture2D_N and every later press looks for
        # "Texture2D_N.png" and skips. Tell: a Parent getter and a cast to
        # MaterialInstanceConstant in the cooked class.
        $viaParent = ($pTxt.IndexOf('MaterialInstanceConstant') -ge 0)
        Log ("panel refresh reads the vanilla name from: {0}" -f $(if ($viaParent) { 'the MID PARENT (repeats work)' } else { 'the MID ITSELF - only the first press per match will work' }))
        if (-not $viaParent) { Write-Warning "panel widget has no MaterialInstanceConstant cast - the repeat-press bug is still in this build." }
        foreach ($p in @('SpecularTexture', 'Emissive')) {
            if ($pTxt.IndexOf($p) -lt 0) { Write-Warning "panel widget never mentions '$p' - that map kind will not refresh in game." }
        }
    }
}

# ---------------------------------------------------------------- patch the panel
$panel = [System.IO.File]::ReadAllBytes("$Vanilla/WBP_UIDPanel.uasset")
$enc   = [System.Text.Encoding]::ASCII

foreach ($s in $swaps) {
    if ($s.old.Length -ne $s.new.Length) {
        throw ("length mismatch: '{0}' ({1}) vs '{2}' ({3}) - the swap must be byte-for-byte" -f $s.old, $s.old.Length, $s.new, $s.new.Length)
    }
    $oldB = $enc.GetBytes($s.old)
    $newB = $enc.GetBytes($s.new)

    $hits = @()
    for ($i = 0; $i -le $panel.Length - $oldB.Length - 1; $i++) {
        if ($panel[$i] -ne $oldB[0]) { continue }
        $match = $true
        for ($j = 1; $j -lt $oldB.Length; $j++) {
            if ($panel[$i + $j] -ne $oldB[$j]) { $match = $false; break }
        }
        if ($match -and $panel[$i + $oldB.Length] -eq 0) { $hits += $i }
    }

    if ($hits.Count -ne 1) {
        throw ("expected exactly 1 name-table entry for '{0}', found {1}. The panel has changed - re-extract it and re-check the four strings." -f $s.old, $hits.Count)
    }

    [Array]::Copy($newB, 0, $panel, $hits[0], $newB.Length)
    Log ("patched @{0,5}  {1}" -f $hits[0], $s.new)
}

# ---------------------------------------------------------------- stage
$stage = Join-Path $Work "stage/$ModName"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }

$dWidget = Join-Path $stage 'Marvel/Content/Marvel/SkinLive/UI/Widgets'
$dPanel  = Join-Path $stage 'Marvel/Content/Marvel/UI/Blueprints/Login'
$null = New-Item -ItemType Directory -Force -Path $dWidget, $dPanel

# the login splash's logo (a cooked texture the panel widget references)
if ($PanelWidget -and -not $NoGraphCheck) {
    $texCooked = Join-Path (Split-Path $CookedDir -Parent) 'Textures'
    $logo = @(Get-ChildItem -LiteralPath $texCooked -Filter 'T_VariantWordmark.*' -File -ErrorAction SilentlyContinue)
    if ($logo.Count -lt 2) { throw "missing cooked logo texture T_VariantWordmark in $texCooked - import it (D:/SkinLiveUE/import_logo.py) and re-cook" }
    $dTex = Join-Path $stage 'Marvel/Content/Marvel/SkinLive/UI/Textures'
    $null = New-Item -ItemType Directory -Force -Path $dTex
    foreach ($f in $logo) { Copy-Item $f.FullName $dTex }
    Log ("logo texture staged ({0} files)" -f $logo.Count)
}
Copy-Item "$CookedDir/$Widget.uasset" $dWidget
Copy-Item "$CookedDir/$Widget.uexp"   $dWidget
foreach ($f in $panelFiles) { Copy-Item $f $dWidget }      # the in-game editor widget
[System.IO.File]::WriteAllBytes((Join-Path $dPanel 'WBP_UIDPanel.uasset'), $panel)

# ---------------------------------------------------------------- blank the child's property block
# ★ THIS is what made every class with a graph crash while an empty one loaded.
#
# WBP_UIDPanel is one of the GAME's packages, so it uses UNVERSIONED (positional)
# property serialization: the block it stores for its child widget is a list of
# "skip N, read 1" fragments resolved against THE CHILD CLASS'S property layout,
# by index, not by name. The vanilla block is 13 bytes and reads slots 77 and 98
# of WBP_BackstageShader_Progress02_C - a class that inherits from the Python
# widget PyWidget_CompileInfo_Resident and so has a long property list.
#
# Repoint that child at our class and those two indices are resolved against
# OUR layout instead: a plain UserWidget subclass, nowhere near 99 properties.
# The loader walks off the end of the schema, gets a junk FProperty*, and dies
# with EXCEPTION_ACCESS_VIOLATION reading 0x0 - at construction, which is why no
# amount of bisecting the graph ever moved it. The empty control survived the
# same over-read by luck; adding an ubergraph changes the class's property count
# and the luck ran out.
#
# Project Galacta sidesteps this by shipping a hand-rebuilt WBP_UIDPanel that is
# a TAGGED package, where properties are matched by name and unknown ones are
# skipped. We get the same immunity for two bytes: rewrite the fragment header
# to "skip 0, read 0, last" so the panel stores NO properties for that child.
# Encoding (FUnversionedHeader::FFragment::Pack): SkipNum | bHasAnyZeroes<<7 |
# bIsLast<<8 | ValueNum<<9, so an empty terminated header is 0x0100 = bytes 00 01.
#
# The 11 bytes after it are simply never read. One of the two dropped values is
# the child's Slot; the parent MarvelHorizontalBox holds the same slot in its own
# Slots array, and our bootstrap widget draws nothing, so nothing is lost.
$uexp = [System.IO.File]::ReadAllBytes("$Vanilla/WBP_UIDPanel.uexp")
if (-not $KeepChildProps) {
    # Locate by content, not by a hard-coded offset, so a game patch that moves
    # the export is caught instead of silently mis-patched.
    $sig  = [byte[]](0x4D,0x02,0x14,0x03,0x04,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00)
    $hits = @()
    for ($i = 0; $i -le $uexp.Length - $sig.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $sig.Length; $j++) { if ($uexp[$i + $j] -ne $sig[$j]) { $match = $false; break } }
        if ($match) { $hits += $i }
    }
    if ($hits.Count -ne 1) {
        throw ("expected exactly 1 child property block in WBP_UIDPanel.uexp, found {0}. The panel's stored properties have changed - re-decode it with zenparse.ps1 before shipping, or pass -KeepChildProps to skip this patch (and expect the access-violation crash)." -f $hits.Count)
    }
    $uexp[$hits[0]]     = 0x00
    $uexp[$hits[0] + 1] = 0x01
    # zero the rest of the block too. If anything past the property header does get
    # read, zeroes are the benign reading (null refs, zero counts); leaving the old
    # fragment words there invites them to be decoded as something.
    for ($k = 2; $k -lt $sig.Length; $k++) { $uexp[$hits[0] + $k] = 0x00 }
    Log ("blanked child property block @{0,5}  (was: skip 77 read 1 / skip 20 read 1)" -f $hits[0])
} else {
    Log "child property block LEFT INTACT (-KeepChildProps) - expect a load crash"
}

# ---------------------------------------------------------------- resize the child export
# Blanking the header was necessary but NOT sufficient. The game's export table
# declares a fixed 13-byte budget for that child, and the engine checks it:
#   ObjectSerializationError: ... WBP_UIDPanel_C:WidgetTree.<our widget>:
#   Serial size mismatch: Expected read size 13, Actual read size 22
# 13 bytes was only ever enough because the vanilla child's class descends from
# the Python widget PyWidget_CompileInfo_Resident, which serialises compactly
# under unversioned encoding. A plain UserWidget subclass consumes more, so the
# export has to be grown to fit and every later export slid down to match.
#
# CONFIRMED IN GAME 2026-09-21 at size 6: mounted, no crash, login screen reached.
# The right size is SMALLER than vanilla, not larger. Consumption depends on the
# block's CONTENT, not just our class: declared 13 with the old fragment words
# still in the tail over-ran to 22, but declared 22 with the tail zeroed settled
# at 6 - the 2-byte empty header plus a 4-byte length field that reads as zero.
# So the block is "00 01 00 00 00 00" and the export is 6 bytes.
#
# The engine is a precise oracle here: if the size is wrong it says so and names
# the real number, and nothing is corrupted in the meantime. Pass
# -ChildExportSize <n> to follow it, or 0 to leave the export at its vanilla size.
if ($ChildExportSize -gt 0 -and -not $KeepChildProps) {
    # TotalHeaderSize sits just after the custom-version array; re-walk the summary.
    $q = 4
    $lg = [System.BitConverter]::ToInt32($panel, $q); $q += 4
    if ($lg -ne -4) { $q += 4 }
    $q += 12
    $nc = [System.BitConverter]::ToInt32($panel, $q); $q += 4
    $q += $nc * 20
    $totalHeader = [System.BitConverter]::ToInt32($panel, $q)

    $childDataOff = $hits[0]                      # offset of the block inside .uexp
    $childSerial  = [int64]($totalHeader + $childDataOff)
    $oldSize      = [int64]13
    $delta        = [int64]($ChildExportSize - $oldSize)

    if ($delta -ne 0) {
        # find this child's entry in the legacy export table: SerialSize then SerialOffset,
        # two adjacent int64s. Entries are 96 bytes apart.
        $entry = -1
        for ($i = 0; $i -le $panel.Length - 16; $i++) {
            if ([System.BitConverter]::ToInt64($panel, $i) -eq $oldSize -and
                [System.BitConverter]::ToInt64($panel, $i + 8) -eq $childSerial) {
                if ($entry -ge 0) { throw "child export entry is not unique in the export table" }
                $entry = $i
            }
        }
        if ($entry -lt 0) { throw "could not find the child's export-table entry (size $oldSize, offset $childSerial)" }

        [Array]::Copy([System.BitConverter]::GetBytes([int64]$ChildExportSize), 0, $panel, $entry, 8)

        # slide every export that starts after this one
        $uexpEnd = [int64]($totalHeader + $uexp.Length)
        $moved = 0
        foreach ($dir in -96, 96) {
            $p2 = $entry + $dir
            while ($p2 -ge 0 -and $p2 -le $panel.Length - 16) {
                $sz = [System.BitConverter]::ToInt64($panel, $p2)
                $of = [System.BitConverter]::ToInt64($panel, $p2 + 8)
                if ($of -lt $totalHeader -or $of -gt $uexpEnd -or $sz -lt 0 -or $sz -gt $uexp.Length) { break }
                if ($of -gt $childSerial) {
                    [Array]::Copy([System.BitConverter]::GetBytes([int64]($of + $delta)), 0, $panel, $p2 + 8, 8)
                    $moved++
                }
                $p2 += $dir
            }
        }

        # BulkDataStartOffset marks the end of the export data (the .uexp minus its
        # 4-byte trailing package tag) and has to move with it.
        $bulkOld = [int64]($totalHeader + $uexp.Length - 4)
        $bulkAt  = -1
        for ($i = 0; $i -le $panel.Length - 8; $i++) {
            if ([System.BitConverter]::ToInt64($panel, $i) -eq $bulkOld) { $bulkAt = $i; break }
        }
        if ($bulkAt -ge 0) { [Array]::Copy([System.BitConverter]::GetBytes([int64]($bulkOld + $delta)), 0, $panel, $bulkAt, 8) }

        # resize the block itself: keep as much of the (already blanked) block as
        # still fits, zero-pad when growing, truncate when shrinking.
        $keep   = [Math]::Min($oldSize, [int64]$ChildExportSize)
        $resized = New-Object byte[] ($uexp.Length + $delta)
        [Array]::Copy($uexp, 0, $resized, 0, $childDataOff)                       # everything before
        [Array]::Copy($uexp, $childDataOff, $resized, $childDataOff, $keep)       # the block, clipped
        [Array]::Copy($uexp, $childDataOff + $oldSize, $resized, $childDataOff + $ChildExportSize,
                      $uexp.Length - $childDataOff - $oldSize)                    # everything after
        $uexp = $resized

        Log ("child export resized 13 -> {0} ({1}{2}), {3} later exports slid, bulk offset {4}" -f $ChildExportSize, $(if ($delta -gt 0) { '+' } else { '' }), $delta, $moved, $(if ($bulkAt -ge 0) { "fixed @$bulkAt" } else { 'not found' }))
        [System.IO.File]::WriteAllBytes((Join-Path $dPanel 'WBP_UIDPanel.uasset'), $panel)
    }
}

[System.IO.File]::WriteAllBytes((Join-Path $dPanel 'WBP_UIDPanel.uexp'), $uexp)
Log ("staged {0} files" -f @(Get-ChildItem -LiteralPath $stage -Recurse -File).Count)

# ---------------------------------------------------------------- pack
$out = Join-Path $Work 'out'
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $out

$packLog = Join-Path $Work 'pack.log'
if ($Packer -eq 'rrcli') {
    & $Rr pack $stage --output $out --game-paks-dir $Paks *> $packLog
    if ($LASTEXITCODE -ne 0) { throw "pack failed (exit $LASTEXITCODE) - see $packLog" }
} else {
    & $Retoc to-zen --version UE5_3 $stage (Join-Path $out "${ModName}_9999999_P.utoc") *> $packLog
    if ($LASTEXITCODE -ne 0) { throw "pack failed (exit $LASTEXITCODE) - see $packLog" }

    # ---- the companion pak has to come from rrcli ----------------------------
    # retoc writes a 347-byte stub pak with an UNENCRYPTED index, and the engine
    # rejects the ENTIRE container for it: the mod lands in
    #   %LOCALAPPDATA%\Marvel\Saved\pak_invalid.txt
    # and never mounts. The game then launches perfectly - which reads as "the
    # build works" when in fact nothing was loaded. rrcli's 416-byte stub has an
    # encrypted index and is accepted. Both are 0-entry paks, so this is NOT the
    # chunknames rejection. Container flag at .utoc offset 80: working = 0x09,
    # retoc alone = 0x08.
    $rrTmp = Join-Path $Work 'out-rrcli-pak'
    if (Test-Path $rrTmp) { Remove-Item $rrTmp -Recurse -Force }
    $null = New-Item -ItemType Directory -Force -Path $rrTmp
    & $Rr pack $stage --output $rrTmp --game-paks-dir $Paks *>> $packLog
    if ($LASTEXITCODE -ne 0) { throw "companion-pak build (rrcli) failed - see $packLog" }
    $rrPak = Get-ChildItem $rrTmp -Filter '*.pak' | Select-Object -First 1
    if (-not $rrPak) { throw "rrcli produced no .pak to use as companion - see $packLog" }
    Copy-Item $rrPak.FullName (Join-Path $out "${ModName}_9999999_P.pak") -Force
    Log ("companion pak taken from rrcli ({0:N0} bytes, encrypted index)" -f $rrPak.Length)
}

$triplet = Get-ChildItem $out -File
if (-not ($triplet | Where-Object Extension -eq '.ucas')) { throw "pack produced no .ucas - see $packLog" }
foreach ($f in $triplet) { Log ("packed  {0,-40} {1,10:N0}" -f $f.Name, $f.Length) }

# ---------------------------------------------------------------- install
if ($Install) {
    if (Get-Process -Name 'Marvel-Win64-Shipping','MarvelRivals' -ErrorAction SilentlyContinue) {
        Write-Host ''
        Write-Host "INSTALL SKIPPED: Marvel Rivals is running. Close it, then re-run with -Install."
    } else {
        $modsDir = Join-Path $Paks '~mods'
        # the same mod under its old name would override the panel twice: move it
        # aside (never delete in ~mods), into the pack folder
        if ($ModName -eq '!!SkinLive') {
            $old = @(Get-ChildItem -LiteralPath $modsDir -Filter 'SkinLive_9999999_P.*' -File -ErrorAction SilentlyContinue)
            if ($old.Count) {
                $aside = Join-Path $Work ('replaced/' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
                $null = New-Item -ItemType Directory -Force -Path $aside
                foreach ($f in $old) { Move-Item -LiteralPath $f.FullName -Destination $aside }
                Write-Host ("moved the old-named SkinLive_9999999_P.* out of ~mods to {0}" -f $aside)
            }
        }
        $null = New-Item -ItemType Directory -Force -Path $modsDir
        foreach ($f in $triplet) { Copy-Item $f.FullName (Join-Path $modsDir $f.Name) -Force }
        Write-Host ''
        Write-Host "installed loose at ~mods root - restart Marvel Rivals (paks mount at boot)."
        Write-Host ("to back out: delete {0}\{1}_9999999_P.*" -f $modsDir, $ModName)
    }
} else {
    Write-Host ''
    Write-Host "built, not installed. Re-run with -Install, or copy:"
    Write-Host ("  {0}\*" -f $out)
    Write-Host ("into {0}\~mods\   (loose at the root - no subfolder)" -f $Paks)
}
Write-Host ''

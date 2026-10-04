# build_standalone.ps1 - pack the standalone Skin Studio mod: the in-game colour
# panel that works with NO app running (2026-09-26).
#
# Four packages ship, all under /Game/Marvel/SkinLive/UI/Widgets except the host:
#   WBP_SkinStudioStandaloneBoot01  the bootstrap: 1 s re-paint pulse + the F8 key
#   WBP_SkinStudioPanel             the panel (HUD calls patched after the cook)
#   SkinStudioSave                  the SaveGame class that holds the colours
#   WBP_UIDPanel                    the vanilla login/UID panel, byte-patched so
#                                   its child widget class is our bootstrap
#
# The WBP_UIDPanel surgery is the proven recipe from ingame\build_live_mod.ps1
# (equal-length name swap, blank the child's positional property block, resize
# that export to 6 bytes) - copied, not called, because that script stages its
# own two widgets only. Read its comments for the why of every step.
#
# Plus the app half (2026-09-27, one mod for everyone): SkinLive's panel
# (WBP_SkinLiveEditor, textures + designs + Build mod, drawn by the app), its
# bootstrap built with gen_graphs.ps1 -Hosted (no F8) and the wordmark texture,
# taken ready-patched from build_live_mod.ps1's stage. Our bootstrap hosts that
# bootstrap; the colour panel's Studio button opens the app panel. -NoApp packs
# the colour panel alone.
#
#   .\build_standalone.ps1            build into D:\SkinStudioProbeUE\pack\out
param(
    [string]$AppStage = 'D:/SkinLiveUE/pack-hosted/stage/!!SkinLive/Marvel/Content/Marvel/SkinLive/UI',
    [switch]$NoApp,
    # '!!' first: Project Galacta also overrides WBP_UIDPanel and the first name
    # wins (see ingame\build_live_mod.ps1); our bootstrap then hosts Galacta's widget
    [string]$ModName = '!!SkinStudio',
    [string]$Cooked  = 'D:/SkinStudioProbeUE/Saved/Cooked/Windows/SkinProbe/Content/Marvel/SkinLive/UI/Widgets',
    [string]$Boot    = 'WBP_SkinStudioStandaloneBoot01',
    [string]$Panel   = 'WBP_SkinStudioPanel',
    [string]$Save    = 'SkinStudioSave',
    [ValidateSet('NoBlock', 'Block', 'None')][string]$HudMode = 'NoBlock',
    [int]$ChildExportSize = 6,
    [string]$Work    = 'D:/SkinStudioProbeUE/pack',
    [string]$Rr      = 'C:/rs/tools/rrcli/retoc-rivals-cli.exe',
    [string]$Paks    = 'C:/Program Files (x86)/Steam/steamapps/common/MarvelRivals/MarvelGame/Marvel/Content/Paks'
)
$ErrorActionPreference = 'Stop'
function Log($m) { Write-Host ('  ' + $m) }
Write-Host ''
Write-Host 'Skin Studio - standalone mod'
Write-Host '----------------------------'
if ($Boot.Length -ne 30) { throw "the bootstrap name must be 30 characters (the swap is byte-for-byte): '$Boot' is $($Boot.Length)" }

# ---------------------------------------------------------------- cooked packages
function Test-Cooked([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { throw "missing cooked package: $path (compile, save, cook -unversioned)" }
    $b = [IO.File]::ReadAllBytes($path)
    if ([BitConverter]::ToInt32($b, 8) -ne 0) { throw "$path is VERSIONED - re-cook with -unversioned" }
    $q = 4; $lg = [BitConverter]::ToInt32($b, $q); $q += 4
    if ($lg -ne -4) { $q += 4 }
    $q += 12; $nc = [BitConverter]::ToInt32($b, $q); $q += 4; $q += $nc * 20 + 4
    $fl = [BitConverter]::ToInt32($b, $q); $q += 4; $q += $(if ($fl -ge 0) { $fl } else { -2 * $fl })
    $pf = [BitConverter]::ToUInt32($b, $q)
    if ($pf -band 0x2000) { throw ("{0} uses UNVERSIONED properties (0x{1:X8}) - crashes the game; set CanUseUnversionedPropertySerialization=False" -f $path, $pf) }
    Log ("{0,-34} tagged 0x{1:X8}  {2,9:N0} bytes" -f [IO.Path]::GetFileName($path), $pf, $b.Length)
}
foreach ($n in @($Boot, $Panel, $Save)) { Test-Cooked "$Cooked/$n.uasset" }

# ---------------------------------------------------------------- HUD calls
# Open/Close ask MarvelHUD for the mouse (NeedInputModeUI*/StopNeedInputModeUI*)
# through two stand-in calls renamed after the cook - the in-game editor's own
# script, run read-only on our panel.
$hudDir = Join-Path $Work 'hud'
if (Test-Path $hudDir) { Remove-Item $hudDir -Recurse -Force }
& 'C:\rs\SkinStudio\ingame\patch_hud_calls.ps1' -Asset "$Cooked/$Panel.uasset" -OutDir $hudDir -Mode $HudMode
$panelFiles = @((Join-Path $hudDir "$Panel.uasset"), (Join-Path $hudDir "$Panel.uexp"))
foreach ($f in $panelFiles) { if (-not (Test-Path $f)) { throw "HUD patch produced no $f" } }

# ---------------------------------------------------------------- vanilla panel (live game, never an old copy)
$panelLine = '../../../Marvel/Content/Marvel/UI/Blueprints/Login/WBP_UIDPanel.uasset'
$vanRoot = Join-Path $Work 'vanilla'
if (Test-Path $vanRoot) { Remove-Item $vanRoot -Recurse -Force }
$unp = & $Rr unpack (Join-Path $Paks 'pakchunkUI-Windows.utoc') -o $vanRoot -f $panelLine --game-paks-dir $Paks 2>&1
if ($LASTEXITCODE -ne 0) { throw ('vanilla extract failed: ' + (($unp | Select-Object -Last 2) -join ' | ')) }
$Vanilla = Join-Path $vanRoot 'Marvel/Content/Marvel/UI/Blueprints/Login'
Log ('vanilla WBP_UIDPanel uasset {0}' -f (Get-FileHash "$Vanilla/WBP_UIDPanel.uasset").Hash.Substring(0, 16))

# ---------------------------------------------------------------- name swap (equal lengths: path 63, leaf 30)
$ourPath = '/Game/Marvel/SkinLive/UI/Widgets/' + $Boot
$swaps = @(
    @{ old = '/Game/Marvel/UI/Blueprints/Squad/WBP_BackstageShader_Progress02'; new = $ourPath },
    @{ old = 'Default__WBP_BackstageShader_Progress02_C'; new = 'Default__' + $Boot + '_C' },
    @{ old = 'WBP_BackstageShader_Progress02_C';          new = $Boot + '_C' },
    @{ old = 'WBP_BackstageShader_Progress02';            new = $Boot }
)
$hostBytes = [IO.File]::ReadAllBytes("$Vanilla/WBP_UIDPanel.uasset")
$enc = [Text.Encoding]::ASCII
foreach ($s in $swaps) {
    if ($s.old.Length -ne $s.new.Length) { throw ("length mismatch: '{0}' vs '{1}'" -f $s.old, $s.new) }
    $oldB = $enc.GetBytes($s.old); $newB = $enc.GetBytes($s.new)
    $hits = @()
    for ($i = 0; $i -le $hostBytes.Length - $oldB.Length - 1; $i++) {
        if ($hostBytes[$i] -ne $oldB[0]) { continue }
        $ok = $true
        for ($j = 1; $j -lt $oldB.Length; $j++) { if ($hostBytes[$i + $j] -ne $oldB[$j]) { $ok = $false; break } }
        if ($ok -and $hostBytes[$i + $oldB.Length] -eq 0) { $hits += $i }
    }
    if ($hits.Count -ne 1) { throw ("expected exactly 1 name entry for '{0}', found {1} - the panel changed" -f $s.old, $hits.Count) }
    [Array]::Copy($newB, 0, $hostBytes, $hits[0], $newB.Length)
    Log ('patched @{0,5}  {1}' -f $hits[0], $s.new)
}

# ---------------------------------------------------------------- blank the child's property block, resize its export to 6
$uexp = [IO.File]::ReadAllBytes("$Vanilla/WBP_UIDPanel.uexp")
$sig = [byte[]](0x4D, 0x02, 0x14, 0x03, 0x04, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00)
$hits = @()
for ($i = 0; $i -le $uexp.Length - $sig.Length; $i++) {
    $ok = $true
    for ($j = 0; $j -lt $sig.Length; $j++) { if ($uexp[$i + $j] -ne $sig[$j]) { $ok = $false; break } }
    if ($ok) { $hits += $i }
}
if ($hits.Count -ne 1) { throw "expected exactly 1 child property block in WBP_UIDPanel.uexp, found $($hits.Count) - the panel's stored properties changed" }
$uexp[$hits[0]] = 0x00; $uexp[$hits[0] + 1] = 0x01
for ($k = 2; $k -lt $sig.Length; $k++) { $uexp[$hits[0] + $k] = 0x00 }
Log ('blanked child property block @{0}' -f $hits[0])

$q = 4; $lg = [BitConverter]::ToInt32($hostBytes, $q); $q += 4
if ($lg -ne -4) { $q += 4 }
$q += 12; $nc = [BitConverter]::ToInt32($hostBytes, $q); $q += 4; $q += $nc * 20
$totalHeader = [BitConverter]::ToInt32($hostBytes, $q)
$childDataOff = $hits[0]
$childSerial = [int64]($totalHeader + $childDataOff)
$oldSize = [int64]13
$delta = [int64]($ChildExportSize - $oldSize)
$entry = -1
for ($i = 0; $i -le $hostBytes.Length - 16; $i++) {
    if ([BitConverter]::ToInt64($hostBytes, $i) -eq $oldSize -and [BitConverter]::ToInt64($hostBytes, $i + 8) -eq $childSerial) {
        if ($entry -ge 0) { throw 'child export entry is not unique' }
        $entry = $i
    }
}
if ($entry -lt 0) { throw "could not find the child's export-table entry" }
[Array]::Copy([BitConverter]::GetBytes([int64]$ChildExportSize), 0, $hostBytes, $entry, 8)
$uexpEnd = [int64]($totalHeader + $uexp.Length)
$moved = 0
foreach ($dir in -96, 96) {
    $p2 = $entry + $dir
    while ($p2 -ge 0 -and $p2 -le $hostBytes.Length - 16) {
        $sz = [BitConverter]::ToInt64($hostBytes, $p2); $of = [BitConverter]::ToInt64($hostBytes, $p2 + 8)
        if ($of -lt $totalHeader -or $of -gt $uexpEnd -or $sz -lt 0 -or $sz -gt $uexp.Length) { break }
        if ($of -gt $childSerial) { [Array]::Copy([BitConverter]::GetBytes([int64]($of + $delta)), 0, $hostBytes, $p2 + 8, 8); $moved++ }
        $p2 += $dir
    }
}
$bulkOld = [int64]($totalHeader + $uexp.Length - 4)
$bulkAt = -1
for ($i = 0; $i -le $hostBytes.Length - 8; $i++) { if ([BitConverter]::ToInt64($hostBytes, $i) -eq $bulkOld) { $bulkAt = $i; break } }
if ($bulkAt -ge 0) { [Array]::Copy([BitConverter]::GetBytes([int64]($bulkOld + $delta)), 0, $hostBytes, $bulkAt, 8) }
$keep = [Math]::Min($oldSize, [int64]$ChildExportSize)
$resized = New-Object byte[] ($uexp.Length + $delta)
[Array]::Copy($uexp, 0, $resized, 0, $childDataOff)
[Array]::Copy($uexp, $childDataOff, $resized, $childDataOff, $keep)
[Array]::Copy($uexp, $childDataOff + $oldSize, $resized, $childDataOff + $ChildExportSize, $uexp.Length - $childDataOff - $oldSize)
$uexp = $resized
Log ('child export 13 -> {0}, {1} later exports slid, bulk offset {2}' -f $ChildExportSize, $moved, $(if ($bulkAt -ge 0) { "fixed @$bulkAt" } else { 'not found' }))

# ---------------------------------------------------------------- stage + pack
$stage = Join-Path $Work "stage/$ModName"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$dW = Join-Path $stage 'Marvel/Content/Marvel/SkinLive/UI/Widgets'
$dP = Join-Path $stage 'Marvel/Content/Marvel/UI/Blueprints/Login'
New-Item -ItemType Directory -Force -Path $dW, $dP | Out-Null
foreach ($n in @($Boot, $Save)) { foreach ($x in 'uasset', 'uexp') { Copy-Item "$Cooked/$n.$x" $dW } }
foreach ($f in $panelFiles) { Copy-Item $f $dW }
# the colour wheel's image (T_SSWheel, cooked beside the widgets)
$wheelDir = Join-Path (Split-Path $Cooked -Parent) 'Textures'
$wheel = @(Get-ChildItem -LiteralPath $wheelDir -Filter 'T_SSWheel.*' -File -ErrorAction SilentlyContinue)
if ($wheel.Count -lt 2) { throw "the colour wheel texture is not cooked: $wheelDir\T_SSWheel.uasset" }
$dTW = Join-Path $stage 'Marvel/Content/Marvel/SkinLive/UI/Textures'
New-Item -ItemType Directory -Force -Path $dTW | Out-Null
foreach ($w in $wheel) { Copy-Item -LiteralPath $w.FullName $dTW }
$appPkgs = @()
if (-not $NoApp) {
    $dT = Join-Path $stage 'Marvel/Content/Marvel/SkinLive/UI/Textures'
    New-Item -ItemType Directory -Force -Path $dT | Out-Null
    foreach ($a in @(@('Widgets', 'WBP_SkinLiveEditor', $dW), @('Widgets', 'WBP_SkinLivePreviewBootstrap01', $dW), @('Textures', 'T_VariantWordmark', $dT))) {
        foreach ($x in 'uasset', 'uexp') {
            $src = "$AppStage/$($a[0])/$($a[1]).$x"
            if (-not (Test-Path -LiteralPath $src)) { throw "app half missing: $src (build_live_mod.ps1 -Work D:/SkinLiveUE/pack-hosted, or -NoApp)" }
            Copy-Item -LiteralPath $src $a[2]
        }
        $appPkgs += $a[1]
    }
    Log ('app half from {0}: {1}' -f $AppStage, ($appPkgs -join ', '))
}
[IO.File]::WriteAllBytes((Join-Path $dP 'WBP_UIDPanel.uasset'), $hostBytes)
[IO.File]::WriteAllBytes((Join-Path $dP 'WBP_UIDPanel.uexp'), $uexp)
Log ('staged {0} files' -f @(Get-ChildItem -LiteralPath $stage -Recurse -File).Count)

$out = Join-Path $Work 'out'
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out | Out-Null
$packLog = Join-Path $Work 'pack.log'
& $Rr pack $stage --output $out --game-paks-dir $Paks *> $packLog
if ($LASTEXITCODE -ne 0) { throw "pack failed - see $packLog" }
$utoc = Get-ChildItem $out -Filter '*.utoc' | Select-Object -First 1
if (-not $utoc) { throw "pack produced no .utoc - see $packLog" }
$names = @(& $Rr manifest $utoc.FullName 2>$null | Select-String '"filename"' | ForEach-Object { ($_.Line -replace '^.*/', '') -replace '\.uasset.*$', '' })
foreach ($want in (@($Boot, $Panel, $Save, 'WBP_UIDPanel', 'T_SSWheel') + $appPkgs)) { if ($names -notcontains $want) { throw "container is missing $want" } }
Log ('container flags 0x{0:X2}, packages: {1}' -f ([IO.File]::ReadAllBytes($utoc.FullName))[80], ($names -join ', '))
Get-ChildItem $out -File | ForEach-Object { Log ('packed  {0,-32} {1,10:N0}' -f $_.Name, $_.Length) }
Write-Host ''

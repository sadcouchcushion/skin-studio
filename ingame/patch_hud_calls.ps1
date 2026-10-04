# patch_hud_calls.ps1 - point the in-game editor's stand-in HUD calls at
# Rivals' own input-mode functions, in the COOKED widget.
#
# Why: in a match Rivals owns the input mode. MarvelHUD counts how many of its
# own menus need the mouse (InputModeUINeededCnt) and puts gameplay mode back
# when none do, so our plain SetInputMode_GameAndUIEx + bShowMouseCursor lost
# and the mouse kept turning the camera (2026-09-23). The game's menus call
# MarvelHUD.NeedInputModeUI(InWidgetToFocus) / StopNeedInputModeUI(); we call
# the same pair.
#
# Our UE project has no MarvelHUD class (no C++, no Visual Studio here), so the
# graph is authored against stock stand-ins and this rewrites them after the
# cook. Two different mechanisms, both size-neutral:
#
#  1. THE CALLS go by NAME. Both stand-ins are C++-virtual AActor UFUNCTIONs,
#     so they are NOT FUNC_Final in our stock 5.3 editor and the compiler emits
#     EX_VirtualFunction + an FName; at runtime the VM looks that name up on the
#     real object (FindFunctionChecked). Renaming the FName redirects the call:
#       Actor.RemoveTickPrerequisiteActor(None) -> MarvelHUD.NeedInputModeUI[NoBlock](InWidgetToFocus)
#       Actor.ForceNetUpdate()                  -> MarvelHUD.StopNeedInputModeUI[NoBlock]()
#     Same parameter shape (one object / none), so the native thunk reads the
#     argument stream exactly as the bytecode wrote it. An FName on disk is
#     name index + number, 8 bytes whatever the string - nothing moves.
#     NB: a Final stand-in would compile to EX_FinalFunction + an IMPORT instead,
#     and a name rename would do nothing - silently. No Final AActor/AHUD
#     function has the one-object-param shape (checked in the editor DLL), which
#     is why this route and not import repointing. Checked flags 2026-09-24:
#     RemoveTickPrerequisiteActor 0x04020402, ForceNetUpdate 0x04020402 (not Final).
#
#  2. THE GUARD is a class literal. FindFunctionChecked is FATAL when the name
#     is missing, so the graph only calls when ClassIsChildOf(GetObjectClass(HUD),
#     <class literal>) - authored as /Script/Engine.Info and repointed here to
#     /Script/Marvel.MarvelHUD by rewriting that one class import (name + outer;
#     the /Script/Marvel package import is appended, so no index moves). Any
#     other HUD falls back to the old SetInputMode path instead of crashing.
#
# Signatures and flags were read from the game exe's and the editor DLL's
# reflection tables; the targets are in global.utoc's script objects
# (INGAME_EDITOR.md). Round trip verified 2026-09-24: UAssetTool to_json ->
# ConvertFrom-Json -> ConvertTo-Json -> from_json is byte-identical.
#
# -Mode None copies the cooked widget unchanged: the guard then tests "is the
# HUD an Info" (never), so the build behaves exactly like the old one.
param(
    [Parameter(Mandatory)][string]$Asset,       # cooked .uasset, its .uexp beside it
    [Parameter(Mandatory)][string]$OutDir,      # patched .uasset/.uexp land here
    [ValidateSet('NoBlock', 'Block', 'None')][string]$Mode = 'NoBlock',
    [string]$Uat = (Join-Path $env:LOCALAPPDATA 'Atelier\Tools\UAssetTool.exe'),
    [string]$Usmap = ''
)
$ErrorActionPreference = 'Stop'
function PLog($m) { Write-Host ('  hud: ' + $m) }

$suffix = if ($Mode -eq 'Block') { '' } else { 'NoBlock' }
$renames = [ordered]@{
    'RemoveTickPrerequisiteActor' = 'NeedInputModeUI' + $suffix
    'ForceNetUpdate'              = 'StopNeedInputModeUI' + $suffix
}
$guardClass = 'Info'

if (-not (Test-Path -LiteralPath $Uat)) { throw "UAssetTool not found: $Uat" }
if (-not $Usmap) {
    $cfg = Join-Path $env:LOCALAPPDATA 'Atelier\mr_config.json'
    if (Test-Path -LiteralPath $cfg) { $Usmap = [string](Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).usmap }
    if (-not $Usmap -or -not (Test-Path -LiteralPath $Usmap)) {
        $Usmap = @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Atelier\Tools\Mappings') -Filter *.usmap | Sort-Object LastWriteTime -Descending)[0].FullName
    }
}

# UAssetTool prints warnings on stderr; under EAP Stop that is terminating in 5.1
function Invoke-Uat([string[]]$argv) {
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = @(& $Uat @argv 2>&1 | ForEach-Object { [string]$_ }) } finally { $ErrorActionPreference = $eap }
    if ($LASTEXITCODE -ne 0) { throw ('UAssetTool {0} failed: {1}' -f $argv[0], ($o -join ' | ')) }
    $o
}

# every EX_VirtualFunction node in the bytecode (never the Local variant: those
# are calls to our own events), wherever it nests
function Get-VirtualCalls($node) {
    if ($null -eq $node) { return }
    if ($node -is [System.Management.Automation.PSCustomObject]) {
        $t = $node.PSObject.Properties['$type']
        if ($t -and ([string]$t.Value) -like 'UAssetAPI.Kismet.Bytecode.Expressions.EX_VirtualFunction,*') { $node }
        foreach ($p in $node.PSObject.Properties) {
            if ($p.Value -is [System.Management.Automation.PSCustomObject] -or ($p.Value -is [System.Collections.IList] -and $p.Value -isnot [string])) { Get-VirtualCalls $p.Value }
        }
    } elseif ($node -is [System.Collections.IList] -and $node -isnot [string]) {
        foreach ($x in $node) { Get-VirtualCalls $x }
    }
}

# Imports are addressed as -(1-based position)
function Find-Import($imports, [string]$name, [string]$className, [int]$outer) {
    $hits = @()
    for ($i = 0; $i -lt $imports.Count; $i++) {
        $im = $imports[$i]
        if ([string]$im.ObjectName -ne $name) { continue }
        if ($className -and [string]$im.ClassName -ne $className) { continue }
        if ($outer -ne 0 -and [int]$im.OuterIndex -ne $outer) { continue }
        $hits += -($i + 1)
    }
    $hits      # unrolled; every caller wraps it in @()
}
function Import-Path($imports, [int]$idx) {
    $parts = @()
    while ($idx -lt 0) { $im = $imports[-$idx - 1]; $parts = , [string]$im.ObjectName + $parts; $idx = [int]$im.OuterIndex }
    $parts -join '/'
}

$leaf = [IO.Path]::GetFileNameWithoutExtension($Asset)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if ($Mode -eq 'None') {
    Copy-Item -LiteralPath $Asset -Destination $OutDir -Force
    Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($Asset, 'uexp')) -Destination $OutDir -Force
    PLog 'mode None - stand-ins left as they are (the guard never passes), no mouse fix in this build'
    return
}
$tmp = Join-Path $OutDir '_json'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$null = Invoke-Uat @('to_json', $Asset, $Usmap, $tmp)
$j = Get-Content -LiteralPath (Join-Path $tmp ($leaf + '.json')) -Raw | ConvertFrom-Json

# ---- 1. the calls
# ★ A name used by EXPORT DATA (the bytecode's FName) must sit inside the first
# NamesReferencedFromExportDataCount entries of the name map: the Zen package
# keeps only those, so a name appended at the end is past the table in game and
# the load asserts "Bad name index 290/187" - which crashed Rivals at launch on
# 2026-09-24. Insert at the end of that section and grow the count; UAssetAPI
# re-resolves every FName by string on write, so nothing else needs touching.
# Header-only names (the guard's import) may go anywhere.
function Add-ExportName([string]$n) {
    $names = [System.Collections.ArrayList]@($j.NameMap)
    $cut = [int]$j.NamesReferencedFromExportDataCount
    $at = $names.IndexOf($n)
    if ($at -ge 0 -and $at -lt $cut) { return }
    if ($at -ge 0) { $names.RemoveAt($at) }      # header-only so far: move it up
    $names.Insert($cut, $n)
    $j.NameMap = $names.ToArray()
    $j.NamesReferencedFromExportDataCount = $cut + 1
}
$calls = @(Get-VirtualCalls $j.Exports)
foreach ($s in $renames.Keys) {
    $hit = @($calls | Where-Object { [string]$_.VirtualFunctionName -eq $s })
    if ($hit.Count -ne 1) { throw ("expected exactly one EX_VirtualFunction '{0}' (the stand-in call), found {1}. Were the new graphs pasted and the widget re-cooked? A Final function would show up as EX_FinalFunction instead." -f $s, $hit.Count) }
    $hit[0].VirtualFunctionName = $renames[$s]
    Add-ExportName $renames[$s]
    PLog ('call  {0,-28} ->  MarvelHUD.{1}  (by name)' -f $s, $renames[$s])
}

# ---- 2. the guard's class literal
$engine = @(Find-Import $j.Imports '/Script/Engine' 'Package' 0)
if ($engine.Count -ne 1) { throw 'no /Script/Engine package import - is this the cooked editor widget?' }
$guard = @(Find-Import $j.Imports $guardClass 'Class' $engine[0])
if ($guard.Count -ne 1) { throw "expected one /Script/Engine.$guardClass class import (the guard's class literal), found $($guard.Count)" }
foreach ($n in @('/Script/Marvel', 'MarvelHUD')) { if (@($j.NameMap) -notcontains $n) { $j.NameMap += $n } }
$pkg = @(Find-Import $j.Imports '/Script/Marvel' 'Package' 0)
if ($pkg.Count -eq 1) { $pkgIdx = $pkg[0] } else {
    $j.Imports += [pscustomobject][ordered]@{
        '$type' = 'UAssetAPI.Import, UAssetAPI'; ObjectName = '/Script/Marvel'; OuterIndex = 0
        ClassPackage = '/Script/CoreUObject'; ClassName = 'Package'; PackageName = $null; bImportOptional = $false
    }
    $pkgIdx = -($j.Imports.Count)
}
$gi = $j.Imports[-$guard[0] - 1]
$gi.ObjectName = 'MarvelHUD'
$gi.OuterIndex = $pkgIdx
PLog ('guard import {0,4}  /Script/Engine.{1}  ->  /Script/Marvel.MarvelHUD' -f $guard[0], $guardClass)

$pj = Join-Path $tmp ($leaf + '.patched.json')
[IO.File]::WriteAllText($pj, ($j | ConvertTo-Json -Depth 100), (New-Object System.Text.UTF8Encoding($false)))
$outAsset = Join-Path $OutDir ($leaf + '.uasset')
$null = Invoke-Uat @('from_json', $pj, $outAsset, $Usmap)

# ---- verify by reading the written package back
$vdir = Join-Path $tmp 'verify'
New-Item -ItemType Directory -Force -Path $vdir | Out-Null
$null = Invoke-Uat @('to_json', $outAsset, $Usmap, $vdir)
$v = Get-Content -LiteralPath (Join-Path $vdir ($leaf + '.json')) -Raw | ConvertFrom-Json
$vcalls = @(Get-VirtualCalls $v.Exports | ForEach-Object { [string]$_.VirtualFunctionName })
$vcut = [int]$v.NamesReferencedFromExportDataCount
foreach ($s in $renames.Keys) {
    if ($vcalls -contains $s) { throw "verify: stand-in call '$s' survived" }
    if (@($vcalls | Where-Object { $_ -eq $renames[$s] }).Count -ne 1) { throw "verify: '$($renames[$s])' is not called exactly once" }
    $ni = [array]::IndexOf([string[]]@($v.NameMap), $renames[$s])
    if ($ni -lt 0 -or $ni -ge $vcut) { throw ("verify: '{0}' is name {1} but only the first {2} names ship in the Zen package - the game would assert 'Bad name index'" -f $renames[$s], $ni, $vcut) }
}
# every name the bytecode's by-name calls use must be inside the shipped section
foreach ($n in $vcalls) {
    $ni = [array]::IndexOf([string[]]@($v.NameMap), $n)
    if ($ni -lt 0 -or $ni -ge $vcut) { throw "verify: virtual call name '$n' is outside the export-name section ($ni of $vcut)" }
}
if ((Import-Path $v.Imports $guard[0]) -ne '/Script/Marvel/MarvelHUD') { throw "verify: guard import reads '$(Import-Path $v.Imports $guard[0])'" }
$inExp = (Get-Item -LiteralPath ([IO.Path]::ChangeExtension($Asset, 'uexp'))).Length
$outExp = (Get-Item -LiteralPath ([IO.Path]::ChangeExtension($outAsset, 'uexp'))).Length
if ($inExp -ne $outExp) { throw "verify: export data changed size ($inExp -> $outExp) - a rename should never move bytecode" }
PLog ('verified: calls renamed, guard -> MarvelHUD, export data {0:N0} bytes unchanged ({1})' -f $outExp, $Mode)
Remove-Item -LiteralPath $tmp -Recurse -Force

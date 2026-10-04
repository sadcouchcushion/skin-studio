# patch_live_calls.ps1 - point the in-game editor's two "built mod" stand-ins at
# the Rivals functions Project Galacta refreshes its mods with, in the COOKED
# widget (run after patch_hud_calls.ps1, on its output).
#
# The in-game Build mod button needs two things stock Blueprint does not have:
#   - read a text file   MarvelFileUtil.LoadFromFileWithFullFilePath(FullFilePath) -> string
#   - mount a pak NOW    NePatchUtility.MountPak(PakFilename, Order) -> bool
# Both are static, Final, native UFUNCTIONs in the game exe (signatures and
# parameter flags read from its reflection tables 2026-09-26: every parameter
# is a plain by-value Parm, same as the stand-ins). Galacta's GAL_ModLoader /
# WBP_Galacta call exactly these. Our stock 5.3 project has neither class, so
# the graph uses stock stand-ins of the same shape:
#
#   KismetSystemLibrary.GetConsoleVariableStringValue(VariableName) -> string
#       only the manifest reader uses it, so its IMPORT is repointed whole
#   GameplayStatics.DoesSaveGameExist(SlotName, UserIndex) -> bool
#       the only stock (string, int) -> bool, but the flag checks use it too -
#       so a NEW import is added and only the mount call is retargeted: the
#       one whose UserIndex is not a constant (MountLive passes the order it
#       parsed; every flag check passes 0)
#
# Static Final calls compile to EX_CallMath + an import index (not a name), so
# this is import work only: nothing in the bytecode changes size, and every new
# name is a header-only import name (safe to append - export data never refers
# to it, see the "Bad name index" note in patch_hud_calls.ps1).
#
# /Script/NePatchUtility is NOT in global.utoc's script-object list (rrcli names
# Galacta's imports of it "UnknownExport"); the engine resolves script imports
# against the classes actually compiled into the exe, and Galacta's working
# ModLoader depends on exactly that. MarvelFileUtil is in the list.
param(
    [Parameter(Mandatory)][string]$Asset,       # cooked .uasset, its .uexp beside it
    [Parameter(Mandatory)][string]$OutDir,      # patched .uasset/.uexp land here
    [string]$Uat = (Join-Path $env:LOCALAPPDATA 'Atelier\Tools\UAssetTool.exe'),
    [string]$Usmap = ''
)
$ErrorActionPreference = 'Stop'
function PLog($m) { Write-Host ('  live: ' + $m) }

if (-not (Test-Path -LiteralPath $Uat)) { throw "UAssetTool not found: $Uat" }
if (-not $Usmap) {
    $cfg = Join-Path $env:LOCALAPPDATA 'Atelier\mr_config.json'
    if (Test-Path -LiteralPath $cfg) { $Usmap = [string](Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).usmap }
    if (-not $Usmap -or -not (Test-Path -LiteralPath $Usmap)) {
        $Usmap = @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Atelier\Tools\Mappings') -Filter *.usmap | Sort-Object LastWriteTime -Descending)[0].FullName
    }
}

function Invoke-Uat([string[]]$argv) {
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = @(& $Uat @argv 2>&1 | ForEach-Object { [string]$_ }) } finally { $ErrorActionPreference = $eap }
    if ($LASTEXITCODE -ne 0) { throw ('UAssetTool {0} failed: {1}' -f $argv[0], ($o -join ' | ')) }
    $o
}

# every call node carrying a function import (EX_CallMath / EX_FinalFunction /
# EX_LocalFinalFunction all have StackNode + Parameters), wherever it nests
function Get-ImportCalls($node) {
    if ($null -eq $node) { return }
    if ($node -is [System.Management.Automation.PSCustomObject]) {
        if ($node.PSObject.Properties['StackNode'] -and $node.PSObject.Properties['Parameters']) { $node }
        foreach ($p in $node.PSObject.Properties) {
            if ($p.Value -is [System.Management.Automation.PSCustomObject] -or ($p.Value -is [System.Collections.IList] -and $p.Value -isnot [string])) { Get-ImportCalls $p.Value }
        }
    } elseif ($node -is [System.Collections.IList] -and $node -isnot [string]) {
        foreach ($x in $node) { Get-ImportCalls $x }
    }
}
function Get-ExprType($e) { ([string]$e.'$type') -replace '^UAssetAPI\.Kismet\.Bytecode\.Expressions\.(EX_\w+),.*$', '$1' }
$ConstInts = @('EX_IntConst', 'EX_IntZero', 'EX_IntOne', 'EX_IntConstByte', 'EX_ByteConst')

# imports are addressed as -(1-based position)
function Find-Import($imports, [string]$name, [string]$className, [int]$outer) {
    $hits = @()
    for ($i = 0; $i -lt $imports.Count; $i++) {
        $im = $imports[$i]
        if ([string]$im.ObjectName -ne $name) { continue }
        if ($className -and [string]$im.ClassName -ne $className) { continue }
        if ($outer -ne 0 -and [int]$im.OuterIndex -ne $outer) { continue }
        $hits += -($i + 1)
    }
    $hits
}
function Import-Path($imports, [int]$idx) {
    $parts = @()
    while ($idx -lt 0) { $im = $imports[-$idx - 1]; $parts = , [string]$im.ObjectName + $parts; $idx = [int]$im.OuterIndex }
    $parts -join '/'
}
# find-or-append an import; returns its index
function Use-Import([string]$name, [string]$className, [int]$outer) {
    $have = @(Find-Import $script:j.Imports $name $className $outer)
    if ($have.Count -ge 1) { return $have[0] }
    if (@($script:j.NameMap) -notcontains $name) { $script:j.NameMap += $name }
    $script:j.Imports += [pscustomobject][ordered]@{
        '$type' = 'UAssetAPI.Import, UAssetAPI'; ObjectName = $name; OuterIndex = $outer
        ClassPackage = '/Script/CoreUObject'; ClassName = $className; PackageName = $null; bImportOptional = $false
    }
    -($script:j.Imports.Count)
}

$leaf = [IO.Path]::GetFileNameWithoutExtension($Asset)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$tmp = Join-Path $OutDir '_json_live'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$null = Invoke-Uat @('to_json', $Asset, $Usmap, $tmp)
$script:j = Get-Content -LiteralPath (Join-Path $tmp ($leaf + '.json')) -Raw | ConvertFrom-Json

# ---- the table: stock stand-in -> Rivals function, as /Script paths
#   Mode 'whole'   repoints the stand-in's import, so EVERY call to it moves.
#                  Only for a stand-in the graph uses for nothing else.
#   Mode 'argvar'  adds a new import and retargets only the calls whose
#                  argument number Arg (0-based) is NOT a constant - for a
#                  stand-in the graph also uses for real with constants.
#   Calls          how many calls must move (a missing wire prunes a call
#                  without a word, so the count is checked, never assumed).
# Add a row for a new call; the verify below checks every row.
$Repoints = @(
    @{ From = '/Script/Engine/KismetSystemLibrary/GetConsoleVariableStringValue'
       To = '/Script/Marvel/MarvelFileUtil/LoadFromFileWithFullFilePath'
       Mode = 'whole'; Calls = 2; Why = 'the built-mod manifest reader (Walk and MountLive)' }
    @{ From = '/Script/Engine/GameplayStatics/DoesSaveGameExist'
       To = '/Script/NePatchUtility/NePatchUtility/MountPak'
       Mode = 'argvar'; Arg = 1; Calls = 1; Why = 'MountLive''s mount (the flag checks pass index 0)' }
)

# the import for a /Script/<pkg>/<Class>/<Function> path, found or appended
function Use-FunctionImport([string]$path) {
    $p = $path.Split('/')      # '', 'Script', pkg, class, fn
    if ($p.Count -ne 5 -or $p[1] -ne 'Script') { throw "not a /Script/<pkg>/<Class>/<Function> path: $path" }
    $pkg = Use-Import ('/Script/' + $p[2]) 'Package' 0
    $cls = Use-Import $p[3] 'Class' $pkg
    Use-Import $p[4] 'Function' $cls
}
# the existing import for a path, or 0
function Find-FunctionImport([string]$path) {
    for ($i = 0; $i -lt $script:j.Imports.Count; $i++) {
        # Import-Path starts with the package name, which carries its own '/'
        if ((Import-Path $script:j.Imports (-($i + 1))) -eq $path) { return -($i + 1) }
    }
    0
}

$calls = @(Get-ImportCalls $j.Exports)
foreach ($r in $Repoints) {
    $from = Find-FunctionImport $r.From
    if ($from -eq 0) { throw ("no import of {0} ({1}). Were the new graphs pasted, compiled and re-cooked?" -f $r.From, $r.Why) }
    $hit = @($calls | Where-Object { [int]$_.StackNode -eq $from })
    if ($r.Mode -eq 'argvar') {
        $hit = @($hit | Where-Object { @($_.Parameters).Count -gt $r.Arg -and ($ConstInts -notcontains (Get-ExprType @($_.Parameters)[$r.Arg])) })
    }
    if ($hit.Count -ne $r.Calls) { throw ("{0}: expected {1} call(s) to move, found {2} ({3}). A wire may be missing - unreachable nodes are pruned silently." -f $r.From, $r.Calls, $hit.Count, $r.Why) }
    if ($r.Mode -eq 'whole') {
        $t = $r.To.Split('/')
        $pkg = Use-Import ('/Script/' + $t[2]) 'Package' 0
        $cls = Use-Import $t[3] 'Class' $pkg
        if (@($j.NameMap) -notcontains $t[4]) { $j.NameMap += $t[4] }
        $im = $j.Imports[-$from - 1]
        $im.ObjectName = $t[4]; $im.OuterIndex = $cls
        PLog ('import {0,4} {1}  ->  {2}  ({3} call(s), whole)' -f $from, $r.From, $r.To, $hit.Count)
    } else {
        $to = Use-FunctionImport $r.To
        foreach ($c in $hit) { $c.StackNode = $to }
        PLog ('calls -> new import {0,4} {1}  ({2} call(s) of {3} whose argument {4} is a variable)' -f $to, $r.To, $hit.Count, $r.From, $r.Arg)
    }
}

$pj = Join-Path $tmp ($leaf + '.patched.json')
[IO.File]::WriteAllText($pj, ($j | ConvertTo-Json -Depth 100), (New-Object System.Text.UTF8Encoding($false)))
$outAsset = Join-Path $OutDir ($leaf + '.uasset')
$null = Invoke-Uat @('from_json', $pj, $outAsset, $Usmap)

# ---- verify by reading the written package back
$vdir = Join-Path $tmp 'verify'
New-Item -ItemType Directory -Force -Path $vdir | Out-Null
$null = Invoke-Uat @('to_json', $outAsset, $Usmap, $vdir)
$v = Get-Content -LiteralPath (Join-Path $vdir ($leaf + '.json')) -Raw | ConvertFrom-Json
$vcalls = @(Get-ImportCalls $v.Exports)
function Count-CallsTo([string]$path) { @($vcalls | Where-Object { (Import-Path $v.Imports ([int]$_.StackNode)) -eq $path }).Count }
$said = @()
foreach ($r in $Repoints) {
    $n = Count-CallsTo $r.To
    # several rows may share a target; each one's calls must all be there
    $want = (@($Repoints | Where-Object { $_.To -eq $r.To } | ForEach-Object { $_.Calls }) | Measure-Object -Sum).Sum
    if ($n -ne $want) { throw ("verify: {0} call(s) to {1}, expected {2}" -f $n, $r.To, $want) }
    $left = Count-CallsTo $r.From
    if ($r.Mode -eq 'whole' -and $left -ne 0) { throw ("verify: {0} call(s) to the stand-in {1} survived" -f $left, $r.From) }
    $said += ('{0} x {1}' -f $n, $r.To.Split('/')[-1])
}
$inExp = (Get-Item -LiteralPath ([IO.Path]::ChangeExtension($Asset, 'uexp'))).Length
$outExp = (Get-Item -LiteralPath ([IO.Path]::ChangeExtension($outAsset, 'uexp'))).Length
if ($inExp -ne $outExp) { throw "verify: export data changed size ($inExp -> $outExp) - an import retarget should never move bytecode" }
PLog ('verified: {0}; export data {1:N0} bytes unchanged' -f ($said -join ', '), $outExp)
Remove-Item -LiteralPath $tmp -Recurse -Force

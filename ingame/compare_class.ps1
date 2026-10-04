# compare_class.ps1 - dump a cooked Blueprint class package out of an IoStore
# container and, optionally, diff it against ours.
#
# Built to compare Project Galacta's WBP_Galacta (a function-bearing widget class
# that DOES load in Marvel Rivals) against our own stock-UE-5.3 cook, which does
# not. Everything it reports is read straight out of the Zen package bytes - see
# zenparse.ps1 for the header layout, and the memory note for the landmines
# (FZenPackageSummary is 52 bytes; dependency bundle entries are FPackageIndex,
# so decode them as v-1).
#
# Usage:
#   .\compare_class.ps1 -Container <path to .utoc or a folder with one>
#       ...lists the packages in it.
#   .\compare_class.ps1 -Container <...> -Package WBP_Galacta
#       ...full dossier for that package, side by side with ours.
#   .\compare_class.ps1 -Container <...> -Package WBP_Galacta -Ours ''
#       ...dossier for that package only.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Container,
    [string]$Package = '',
    [string]$Ours       = 'D:/SkinLiveUE/pack/out/SkinLive_9999999_P.utoc',
    [string]$OursPackage = 'Bootstrap',
    [string]$Retoc  = 'C:/rs/tools/retoc.exe',
    [string]$Key    = '0x0C263D8C22DCB085894899C3A3796383E9BF9DE0CBFB08C9BF2DEF2E84F29D74',
    [string]$Work   = 'D:/SkinLiveUE/pack/compare',
    [string]$Global = 'C:/Program Files (x86)/Steam/steamapps/common/MarvelRivals/MarvelGame/Marvel/Content/Paks/global.utoc'
)

$ErrorActionPreference = 'Stop'
$zen = Join-Path $PSScriptRoot 'zenparse.ps1'
if (-not (Test-Path $zen))   { throw "missing zenparse.ps1 beside this script: $zen" }
if (-not (Test-Path $Retoc)) { throw "missing retoc: $Retoc" }
$null = New-Item -ItemType Directory -Force -Path $Work

# ------------------------------------------------------------------ resolve input
function Resolve-Utoc([string]$p) {
    if (-not (Test-Path $p)) { throw "not found: $p" }
    if ((Get-Item $p).PSIsContainer) {
        $u = Get-ChildItem $p -Filter *.utoc -Recurse | Select-Object -First 1
        if (-not $u) { throw "no .utoc under $p" }
        return $u.FullName
    }
    return (Resolve-Path $p).Path
}

# retoc writes pakstore.json into the CURRENT directory, so give each container its own.
function Get-Packages([string]$utoc, [string]$tag) {
    $dir = Join-Path $Work $tag
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    $null = New-Item -ItemType Directory -Force -Path $dir
    Push-Location $dir
    try { & $Retoc -a $Key manifest $utoc *> (Join-Path $dir 'manifest.log') } finally { Pop-Location }
    $json = Join-Path $dir 'pakstore.json'
    if (-not (Test-Path $json)) { throw "manifest failed for $utoc - see $dir\manifest.log" }
    $txt = Get-Content $json -Raw
    $out = @()
    foreach ($m in [regex]::Matches($txt, '"packagename":"([^"]*)"[^\]]*?"id":"([a-f0-9]+)"')) {
        $out += [pscustomobject]@{ Name = $m.Groups[1].Value; Id = $m.Groups[2].Value }
    }
    $out
}

function Get-Chunk([string]$utoc, [string]$id, [string]$outFile) {
    & $Retoc -a $Key get $utoc $id $outFile *> (Join-Path $Work 'get.log')
    if (-not (Test-Path $outFile)) { throw "retoc get failed for $id - see $Work\get.log" }
    $outFile
}

# ------------------------------------------------------------------ script objects
$script:Known = $null
function Get-KnownScriptObjects {
    if ($script:Known) { return $script:Known }
    $f = Join-Path $Work 'scriptobjects.txt'
    if (-not (Test-Path $f)) {
        if (-not (Test-Path $Global)) { Write-Warning "global.utoc not found - skipping import resolution"; return $null }
        & $Retoc -a $Key print-script-objects $Global *> $f
    }
    $set = New-Object 'System.Collections.Generic.HashSet[UInt64]'
    Select-String -Path $f -Pattern 'global_index:\s+Some\((\d+)\)' |
        ForEach-Object { [void]$set.Add([uint64]$_.Matches[0].Groups[1].Value) }
    $script:Known = $set
    $set
}

# ------------------------------------------------------------------ the dossier
function Show-Dossier([string]$bin, [string]$label) {
    $P = & $zen $bin
    $b = [System.IO.File]::ReadAllBytes($bin)

    Write-Host ''
    Write-Host "=============== $label ===============" -ForegroundColor Cyan
    Write-Host ("  PackageFlags      0x{0:X8}{1}" -f $P.Summary.PackageFlags,
        $(if ($P.Summary.PackageFlags -band 0x2000) { '   <- PKG_UnversionedProperties SET (fatal for a mod)' } else { '   (tagged properties)' }))
    Write-Host ("  HeaderSize        {0}" -f $P.Summary.HeaderSize)
    Write-Host ("  CookedHeaderSize  {0}" -f $P.Summary.CookedHeaderSize)
    Write-Host ("  names {0}   exports {1}   depEntries {2}" -f $P.Names.Count, $P.Exports.Count, $P.DepEntCount)

    # imports: script vs package, and which script ones the game does not know
    $impOff = $P.Summary.ImportMapOff; $expOff = $P.Summary.ExportMapOff
    $n = [int](($expOff - $impOff) / 8)
    $known = Get-KnownScriptObjects
    $nScript = 0; $nPkg = 0; $missing = @()
    for ($i = 0; $i -lt $n; $i++) {
        $v = [System.BitConverter]::ToUInt64($b, $impOff + $i * 8)
        switch ([int]($v -shr 62)) {
            1 { $nScript++; if ($known -and -not $known.Contains($v)) { $missing += ("imp{0} 0x{1:X16}" -f $i, $v) } }
            2 { $nPkg++ }
        }
    }
    Write-Host ("  imports {0}  (script {1}, package {2})" -f $n, $nScript, $nPkg)
    if ($missing.Count) {
        Write-Host ("  UNRESOLVED SCRIPT IMPORTS: {0}" -f ($missing -join ', ')) -ForegroundColor Red
    } elseif ($known) {
        Write-Host "  all script imports resolve against global.utoc" -ForegroundColor Green
    }

    Write-Host ''
    Write-Host "  exports (FPackageIndex arcs decoded as v-1):"
    function D($v, $Pk) { if ($v -gt 0) { "exp$($v-1)" } elseif ($v -lt 0) { "imp$(-$v-1)" } else { 'null' } }
    foreach ($e in $P.Exports) {
        $bd = $P.Bundles[$e.Idx]
        Write-Host ("  {0,3} {1,-50} flags={2} size={3}" -f $e.Idx, $e.Name, $e.Flags, $e.Size)
        $arcs = @()
        $lbl = 'CbC','SbC','CbS','SbS'
        for ($k = 0; $k -lt 4; $k++) {
            if ($bd.Entries[$k].Count) { $arcs += ("{0}[{1}]" -f $lbl[$k], (($bd.Entries[$k] | ForEach-Object { D $_ $P }) -join ' ')) }
        }
        if ($arcs.Count) { Write-Host ("        {0}" -f ($arcs -join '  ')) }
    }

    # the class export - Class/Super/Template hashes are the fingerprint that says
    # what it derives from and what cooked it.
    $cls = $P.Exports | Where-Object { $_.Flags -eq '0x00000009' } | Select-Object -First 1
    if ($cls) {
        Write-Host ''
        Write-Host ("  class export '{0}':" -f $cls.Name)
        Write-Host ("     Class    {0}" -f $cls.Class)
        Write-Host ("     Super    {0}" -f $cls.Super)
        Write-Host ("     Template {0}" -f $cls.Template)
    }
    $P
}

# ------------------------------------------------------------------ run
$utoc = Resolve-Utoc $Container
Write-Host ''
Write-Host "container: $utoc"
$pkgs = Get-Packages $utoc 'target'

if (-not $Package) {
    Write-Host ''
    Write-Host ("{0} packages:" -f $pkgs.Count)
    $pkgs | ForEach-Object { Write-Host ("  {0}" -f $_.Name) }
    Write-Host ''
    Write-Host 'Re-run with -Package <substring> for the full dossier.'
    return
}

$hit = $pkgs | Where-Object { $_.Name -like "*$Package*" }
if (-not $hit)            { throw "no package matching '$Package'. Run without -Package to list them." }
if ($hit -is [array])     { Write-Host "matches: $(($hit | ForEach-Object Name) -join ', ')"; $hit = $hit[0] }
Write-Host ("selected: {0}" -f $hit.Name)

$bin = Get-Chunk $utoc $hit.Id (Join-Path $Work 'target.bin')
$A = Show-Dossier $bin $hit.Name

if ($Ours -and (Test-Path $Ours)) {
    $oPkgs = Get-Packages (Resolve-Utoc $Ours) 'ours'
    $oHit  = $oPkgs | Where-Object { $_.Name -like "*$OursPackage*" } | Select-Object -First 1
    if ($oHit) {
        $oBin = Get-Chunk (Resolve-Utoc $Ours) $oHit.Id (Join-Path $Work 'ours.bin')
        $B = Show-Dossier $oBin ($oHit.Name + '  (OURS)')

        Write-Host ''
        Write-Host '=============== what differs ===============' -ForegroundColor Yellow
        $rows = @(
            @{ k = 'PackageFlags';  a = ('0x{0:X8}' -f $A.Summary.PackageFlags); b = ('0x{0:X8}' -f $B.Summary.PackageFlags) },
            @{ k = 'exports';       a = $A.Exports.Count;  b = $B.Exports.Count },
            @{ k = 'names';         a = $A.Names.Count;    b = $B.Names.Count },
            @{ k = 'depEntries';    a = $A.DepEntCount;    b = $B.DepEntCount }
        )
        foreach ($r in $rows) {
            $same = ($r.a -eq $r.b)
            Write-Host ("  {0,-14} theirs {1,-14} ours {2,-14} {3}" -f $r.k, $r.a, $r.b, $(if ($same) { 'same' } else { 'DIFFERENT' })) -ForegroundColor $(if ($same) { 'Gray' } else { 'Yellow' })
        }
        $ac = $A.Exports | Where-Object { $_.Flags -eq '0x00000009' } | Select-Object -First 1
        $bc = $B.Exports | Where-Object { $_.Flags -eq '0x00000009' } | Select-Object -First 1
        if ($ac -and $bc) {
            foreach ($f in 'Class','Super','Template') {
                $same = ($ac.$f -eq $bc.$f)
                Write-Host ("  class.{0,-8} theirs {1} ours {2} {3}" -f $f, $ac.$f, $bc.$f, $(if ($same) { 'same' } else { 'DIFFERENT' })) -ForegroundColor $(if ($same) { 'Gray' } else { 'Yellow' })
            }
        }
    } else {
        Write-Warning "no package matching '$OursPackage' in $Ours - skipping the comparison half."
    }
}
Write-Host ''

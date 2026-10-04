# probe_install.ps1 - put the standalone PROBE mod in the game, take it out
# again, and read what it left behind.
#
#   .\probe_install.ps1            install (game must be closed)
#   .\probe_install.ps1 -Report    what happened in game (breadcrumbs, rejection, crashes)
#   .\probe_install.ps1 -Uninstall take the probe out, put SkinLive back
#
# The probe and SkinLive both hook WBP_UIDPanel, so only one can be installed:
# install PARKS SkinLive_9999999_P.* in standalone\parked\ and uninstall puts it
# back - but only if ~mods has no SkinLive triplet by then, so a newer SkinLive
# build is never overwritten by the parked one.
param([switch]$Uninstall, [switch]$Report)
$ErrorActionPreference = 'Stop'
$Mods   = 'C:\Program Files (x86)\Steam\steamapps\common\MarvelRivals\MarvelGame\Marvel\Content\Paks\~mods'
$Built  = 'D:\SkinStudioProbeUE\pack\out'
$Parked = Join-Path $PSScriptRoot 'parked'
$Saved  = Join-Path $env:LOCALAPPDATA 'Marvel\Saved'
$Saves  = Join-Path $Saved 'SaveGames'
$State  = Join-Path $PSScriptRoot 'probe_state.json'
$Exts   = @('pak', 'ucas', 'utoc')

function Get-Triplet([string]$dir, [string]$name) {
    @($Exts | ForEach-Object { Join-Path $dir ('{0}_9999999_P.{1}' -f $name, $_) } | Where-Object { Test-Path -LiteralPath $_ })
}
function Assert-GameClosed {
    if (Get-Process -Name 'Marvel-Win64-Shipping', 'MarvelRivals' -ErrorAction SilentlyContinue) {
        throw 'Marvel Rivals is running - close it first (paks only mount at launch).'
    }
}

if ($Report) {
    $st = if (Test-Path $State) { Get-Content $State -Raw | ConvertFrom-Json } else { $null }
    Write-Host ''
    Write-Host 'Standalone probe - what the game left behind'
    Write-Host '--------------------------------------------'
    if ($st) { Write-Host ('installed        : {0}' -f $st.installed) }
    $inv = Join-Path $Saved 'pak_invalid.txt'
    Write-Host ('pak_invalid.txt  : {0}' -f $(if (Test-Path $inv) { 'PRESENT - the container was rejected: ' + ((Get-Content $inv -Raw) -replace '\s+', ' ') } else { 'absent (the container mounted)' }))
    $crashes = @(Get-ChildItem (Join-Path $Saved 'Crashes') -Directory -ErrorAction SilentlyContinue).Count
    Write-Host ('crash reports    : {0}{1}' -f $crashes, $(if ($st) { " (was $($st.crashes) at install)" } else { '' }))
    foreach ($f in @(Get-ChildItem $Saves -Filter 'SSProbe*.sav' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)) {
        $what = switch -Regex ($f.BaseName) {
            '^SSProbeInit$'   { 'the probe class loaded and ran'; break }
            '^SSProbeF8$'     { 'F8 reached it'; break }
            '^SSProbeF9$'     { 'F9 reached it'; break }
            '^SSProbeColors$' { 'the colour save (our own SaveGame class)'; break }
            '^SSProbeNew_'    { 'a pass painted fresh materials (first paint / respawn / new match)'; break }
            default           { '' }
        }
        Write-Host ('{0:HH:mm:ss}  {1,-28} {2}' -f $f.LastWriteTime, $f.Name, $what)
    }
    $cs = Join-Path $Saves 'SSProbeColors.sav'
    if (Test-Path $cs) {
        $txt = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($cs))
        $m = [regex]::Match($txt, '[0-9.]+,[0-9.]+,[0-9.]+\|[0-9.,|]+')
        Write-Host ('saved colours    : {0}' -f $(if ($m.Success) { $m.Value } else { '(no colour text found in the save)' }))
    }
    return
}

if ($Uninstall) {
    Assert-GameClosed
    $probe = Get-Triplet $Mods 'SkinProbe'
    $pp = Join-Path $Parked 'probe'
    New-Item -ItemType Directory -Force -Path $pp | Out-Null
    foreach ($f in $probe) { Move-Item -LiteralPath $f -Destination $pp -Force }
    Write-Host ('probe taken out ({0} files -> {1})' -f $probe.Count, $pp)
    $live = Get-Triplet $Parked 'SkinLive'
    if ((Get-Triplet $Mods 'SkinLive').Count -gt 0) {
        Write-Host 'a SkinLive build is already in ~mods - the parked copy stays parked (never overwrite a newer build)'
    } elseif ($live.Count -eq 3) {
        foreach ($f in $live) { Move-Item -LiteralPath $f -Destination $Mods -Force }
        Write-Host 'SkinLive put back in ~mods:'
        Get-Triplet $Mods 'SkinLive' | ForEach-Object { Get-Item -LiteralPath $_ } | ForEach-Object { Write-Host ('  {0,-26} {1,8:N0}  {2:yyyy-MM-dd HH:mm}' -f $_.Name, $_.Length, $_.LastWriteTime) }
    } else {
        Write-Host 'no parked SkinLive to put back'
    }
    return
}

# ---- install
Assert-GameClosed
$src = Get-Triplet $Built 'SkinProbe'
if ($src.Count -ne 3) { throw "the probe is not built ($Built) - run the build first" }
if (@(Get-ChildItem $Mods -Filter '*_P.utoc' | Where-Object { $_.Name -ne 'SkinProbe_9999999_P.utoc' -and $_.Name -ne 'SkinLive_9999999_P.utoc' } | ForEach-Object {
        [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($_.FullName)) } | Where-Object { $_.Contains('WBP_UIDPanel') }).Count -gt 0) {
    Write-Warning 'another mod in ~mods also carries WBP_UIDPanel (Project Galacta?) - only one of them can win'
}
$live = Get-Triplet $Mods 'SkinLive'
if ($live.Count -gt 0) {
    New-Item -ItemType Directory -Force -Path $Parked | Out-Null
    foreach ($f in $live) { Move-Item -LiteralPath $f -Destination $Parked -Force }
    Write-Host ('SkinLive parked -> {0} (put back by -Uninstall)' -f $Parked)
}
foreach ($f in $src) { Copy-Item -LiteralPath $f -Destination $Mods -Force }
# the verdict procedure: rejection file cleared, crash count noted, old crumbs gone
$inv = Join-Path $Saved 'pak_invalid.txt'
if (Test-Path $inv) { Remove-Item -LiteralPath $inv -Force }
Get-ChildItem $Saves -Filter 'SSProbe*.sav' -ErrorAction SilentlyContinue | Remove-Item -Force
$crashes = @(Get-ChildItem (Join-Path $Saved 'Crashes') -Directory -ErrorAction SilentlyContinue).Count
@{ installed = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); crashes = $crashes } | ConvertTo-Json | Set-Content -LiteralPath $State -Encoding UTF8
Write-Host 'probe installed:'
Get-Triplet $Mods 'SkinProbe' | ForEach-Object { Get-Item -LiteralPath $_ } | ForEach-Object { Write-Host ('  {0,-26} {1,8:N0}' -f $_.Name, $_.Length) }
Write-Host ('crash reports now: {0}.  Launch the game (do any Vortex deploy BEFORE, not after).' -f $crashes)

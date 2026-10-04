# mod_install.ps1 - put a standalone Skin Studio build in the game, take it out,
# and read what it left behind.
#
#   .\mod_install.ps1                     install SkinStudio (game must be closed)
#   .\mod_install.ps1 -Report             what happened in game
#   .\mod_install.ps1 -Uninstall          take it out, put the app mod back
#   -Mod SkinProbe -Built <dir>           the same for the probe
#
# Every one of these mods hooks WBP_UIDPanel, so only one can be installed:
# install PARKS the app's SkinLive build (old name SkinLive_9999999_P or the new
# !!SkinLive_9999999_P) and any other standalone build in standalone\parked\;
# uninstall puts SkinLive back only if ~mods has no SkinLive by then, so a newer
# build of it is never overwritten.
param(
    [string]$Mod = '!!SkinStudio',
    [string]$Built = 'D:\SkinStudioProbeUE\pack\out',
    [switch]$Uninstall, [switch]$Report
)
$ErrorActionPreference = 'Stop'
$Mods   = 'C:\Program Files (x86)\Steam\steamapps\common\MarvelRivals\MarvelGame\Marvel\Content\Paks\~mods'
$Parked = Join-Path $PSScriptRoot 'parked'
$Saved  = Join-Path $env:LOCALAPPDATA 'Marvel\Saved'
$Saves  = Join-Path $Saved 'SaveGames'
$State  = Join-Path $PSScriptRoot ('install_state_{0}.json' -f $Mod)
$Exts   = @('pak', 'ucas', 'utoc')
# '!!SkinLive' first: uninstall restores the first parked build it finds, and the
# older 'SkinLive' name loses WBP_UIDPanel to Project Galacta (panel never opens)
$AppMods = @('!!SkinLive', 'SkinLive')
$Ours    = @('SkinProbe', 'SkinStudio', '!!SkinStudio')

function Get-Triplet([string]$dir, [string]$name) {
    @($Exts | ForEach-Object { Join-Path $dir ('{0}_9999999_P.{1}' -f $name, $_) } | Where-Object { Test-Path -LiteralPath $_ })
}
function Assert-GameClosed {
    if (Get-Process -Name 'Marvel-Win64-Shipping', 'MarvelRivals' -ErrorAction SilentlyContinue) {
        throw 'Marvel Rivals is running - close it first (paks only mount at launch).'
    }
}
function Show-Triplets([string]$dir) {
    Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match '_9999999_P\.(pak|ucas|utoc)$' } |
        ForEach-Object { Write-Host ('  {0,-30} {1,9:N0}  {2:MM-dd HH:mm}' -f $_.Name, $_.Length, $_.LastWriteTime) }
}

if ($Report) {
    $st = if (Test-Path $State) { Get-Content $State -Raw | ConvertFrom-Json } else { $null }
    Write-Host ''
    Write-Host "Skin Studio ($Mod) - what the game left behind"
    if ($st) { Write-Host ('installed        : {0}' -f $st.installed) }
    $inv = Join-Path $Saved 'pak_invalid.txt'
    Write-Host ('pak_invalid.txt  : {0}' -f $(if (Test-Path $inv) { 'PRESENT - rejected: ' + ((Get-Content $inv -Raw) -replace '\s+', ' ') } else { 'absent (the container mounted)' }))
    $crashes = @(Get-ChildItem (Join-Path $Saved 'Crashes') -Directory -ErrorAction SilentlyContinue).Count
    Write-Host ('crash reports    : {0}{1}' -f $crashes, $(if ($st) { " (was $($st.crashes) at install)" } else { '' }))
    $cs = Join-Path $Saves 'SkinStudioColors.sav'
    if (Test-Path $cs) {
        $f = Get-Item $cs
        $txt = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($cs))
        $edits = [regex]::Matches($txt, '(MI_[A-Za-z0-9_]+)\|([^|;]+)\|([0-9.,-]+)')
        Write-Host ('colour save      : {0:HH:mm:ss}, {1} colour edit(s)' -f $f.LastWriteTime, $edits.Count)
        foreach ($m in $edits) { Write-Host ('    {0,-28} {1,-22} {2}' -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value) }
    } else { Write-Host 'colour save      : none yet (nothing saved in game)' }
    return
}

if ($Uninstall) {
    Assert-GameClosed
    $dest = Join-Path $Parked $Mod
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $mine = Get-Triplet $Mods $Mod
    foreach ($f in $mine) { Move-Item -LiteralPath $f -Destination $dest -Force }
    Write-Host ('{0} taken out ({1} files -> {2})' -f $Mod, $mine.Count, $dest)
    $inMods = @($AppMods | ForEach-Object { Get-Triplet $Mods $_ } | Where-Object { $_ })
    if ($inMods.Count -gt 0) {
        Write-Host 'a SkinLive build is already in ~mods - the parked copy stays parked (never overwrite a newer build)'
    } else {
        foreach ($a in $AppMods) {
            $pk = Get-Triplet $Parked $a
            if ($pk.Count -eq 3) { foreach ($f in $pk) { Move-Item -LiteralPath $f -Destination $Mods -Force }; Write-Host "$a put back in ~mods"; break }
        }
    }
    Show-Triplets $Mods
    return
}

# ---- install
Assert-GameClosed
$src = Get-Triplet $Built $Mod
if ($src.Count -ne 3) { throw "$Mod is not built in $Built" }
New-Item -ItemType Directory -Force -Path $Parked | Out-Null
foreach ($a in @($AppMods + $Ours)) {
    if ($a -eq $Mod) { continue }
    $t = Get-Triplet $Mods $a
    if ($t.Count -gt 0) {
        $dest = if ($AppMods -contains $a) { $Parked } else { Join-Path $Parked $a }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        foreach ($f in $t) { Move-Item -LiteralPath $f -Destination $dest -Force }
        Write-Host ('parked {0} -> {1}' -f $a, $dest)
    }
}
# rollback copy of the build this one replaces: rollback\<Mod>\<timestamp>
$old = Get-Triplet $Mods $Mod
if ($old.Count -gt 0) {
    $rb = Join-Path $PSScriptRoot ('rollback\{0}\{1}' -f $Mod, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $rb | Out-Null
    foreach ($f in $old) { Copy-Item -LiteralPath $f -Destination $rb -Force }
    Write-Host ('rollback copy -> {0}' -f $rb)
}
foreach ($f in $src) { Copy-Item -LiteralPath $f -Destination $Mods -Force }
$inv = Join-Path $Saved 'pak_invalid.txt'
if (Test-Path $inv) { Remove-Item -LiteralPath $inv -Force }
$crashes = @(Get-ChildItem (Join-Path $Saved 'Crashes') -Directory -ErrorAction SilentlyContinue).Count
@{ installed = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); crashes = $crashes } | ConvertTo-Json | Set-Content -LiteralPath $State -Encoding UTF8
Write-Host ("$Mod installed. Crash reports now: $crashes. Our mods in ~mods:")
Show-Triplets $Mods

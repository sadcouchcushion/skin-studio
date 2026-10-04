# protect_live.ps1 - the F8 panel's Protect skin, painted in game WITHOUT the
# app's live preview (2026-09-27). Her report: turning Protect on did "the same
# thing as the live preview button" - it switched live preview on, so her app
# designs took over every hero. Now only the colour panel's own Tint is
# repainted, for one skin, and nothing else changes:
#
#   1. build_colours.ps1 -Protect -Live writes the design (Tint -> texture ops
#      with the app's skin guard) into work\ingame\protect\, NOT designs\
#   2. live_preview.ps1 -Design <it> paints it once into the game's
#      SkinStudioLive folder (same renderer, gamma and stale sweep as the app)
#   3. SLT_<texture>.sav for every texture of that skin + SkinLiveTex.sav: the
#      in-game panel's Walk swaps them onto the hero (the F6 path)
#
# -Off paints the empty design, which sweeps that skin's textures back to
# vanilla, and flags them the same way. -FlagOnly just re-flags (a respawn).
# -Design <app design json>: a design picked from the panel's list - painted as
# it is (its texture ops) instead of the colour panel's Tint.
# When the app's own live preview watcher is running it owns SkinStudioLive:
# this steps aside and says so.
#
# Keep this file ASCII: PS 5.1 reads a BOM-less script as Windows-1252.
param(
    [Parameter(Mandatory)][string]$Skin,
    # an app design loaded in game (its textures, as the app would paint them)
    [string]$Design = '',
    [switch]$Off,
    [switch]$FlagOnly,
    [string]$SaveDir = (Join-Path $env:LOCALAPPDATA 'Marvel\Saved\SaveGames'),
    [string]$LiveDir = 'C:\Program Files (x86)\Steam\steamapps\common\MarvelRivals\MarvelGame\Marvel\Content\SkinStudioLive',
    [string]$ProtectDir = 'C:\rs\SkinStudio\work\ingame\protect'
)
$ErrorActionPreference = 'Stop'
. 'C:\rs\SkinStudio\ingame\livestate.ps1'
function PLog([string]$m) { Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $m) }

if (LS-WatcherAlive $SaveDir) { PLog 'the app''s live preview is running - it owns the live textures, Protect skin steps aside'; exit 3 }

if ($Design -and -not $FlagOnly) {
    & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File 'C:\rs\SkinStudio\live_preview.ps1' -Design $Design -LiveDir $LiveDir
    if ($LASTEXITCODE -ne 0) { throw "live_preview.ps1 failed (exit $LASTEXITCODE)" }
} elseif (-not $FlagOnly) {
    $bc = Join-Path $PSScriptRoot 'build_colours.ps1'
    $mode = if ($Off) { '-Off' } else { '-Live' }
    & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File $bc -Skin $Skin -Protect $mode -SaveDir $SaveDir -DesignDir $ProtectDir
    if ($LASTEXITCODE -ne 0) { throw "build_colours.ps1 failed (exit $LASTEXITCODE)" }
    $dp = Join-Path $ProtectDir ('InGameColours{0}.json' -f $Skin)
    if (-not (Test-Path -LiteralPath $dp)) { PLog "no design for $Skin - nothing to paint"; return }
    & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File 'C:\rs\SkinStudio\live_preview.ps1' -Design $dp -LiveDir $LiveDir
    if ($LASTEXITCODE -ne 0) { throw "live_preview.ps1 failed (exit $LASTEXITCODE)" }
}

# flag every texture of this skin the live list knows (live or back to vanilla)
$list = Join-Path $LiveDir '_live.txt'
if (-not (Test-Path -LiteralPath $list)) { PLog 'no live list - nothing to flag'; return }
$hl = Join-Path $SaveDir 'HighlightSettings.sav'
$bytes = if (Test-Path -LiteralPath $hl) { [IO.File]::ReadAllBytes($hl) } else { [Text.Encoding]::ASCII.GetBytes('SkinStudio') }
$n = 0
foreach ($ln in [IO.File]::ReadAllLines($list)) {
    if ($ln.StartsWith('#') -or -not $ln.Trim()) { continue }
    $f = $ln.Split('|')
    if ($f.Count -lt 5 -or $f[1] -ne $Skin) { continue }
    [IO.File]::WriteAllBytes((Join-Path $SaveDir ('SLT_{0}.sav' -f [IO.Path]::GetFileNameWithoutExtension($f[0]))), $bytes)
    $n++
}
if ($n) { [IO.File]::WriteAllBytes((Join-Path $SaveDir 'SkinLiveTex.sav'), $bytes) }
PLog ('{0} texture(s) of {1} flagged for the game{2}' -f $n, $Skin, $(if ($Off) { ' (back to vanilla)' } else { '' }))

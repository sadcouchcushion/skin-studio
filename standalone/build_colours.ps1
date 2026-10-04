# build_colours.ps1 - turn the colours made in the F8 colour panel (the
# standalone mod's save, SkinStudioColors.sav) into real mods, one per skin,
# and put a shareable zip of each in Downloads. Her ask 2026-09-27: build the
# mod and send it to Downloads without leaving the game.
#
# The panel's Build mod button leaves SSBuild_<MI name>.sav; the helper
# (ingame\helper.ps1) sees it and runs this hidden. Nothing is installed: the
# game is running, and the zip is the deliverable.
#
# The save holds "<MI name>|<param>|r,g,b;..." (linear colours read off the
# MIDs). Each edit becomes a design colorOp on every stored colour of that
# name in every material instance of that name (the lobby copy too, so the mod
# looks the same everywhere). A param the MI does not store (the panel can set
# it on a MID because the parent has it) cannot be patched in and is listed as
# skipped.
#
# -Protect (the panel's Protect skin toggle, app installed only): Tint
# (BaseTint) edits become TEXTURE ops instead - 'paint' on the material's _D
# texture with the app's Protect skin tones, so warm skin pixels are left
# alone. -Live writes that as an app design in work\ingame\protect\ (InGameColours<skin>)
# for the live preview to paint in game: texture ops only, since the panel
# keeps putting the other colours on the MIDs itself. -Off writes the live
# design empty, so the preview puts the textures back.
#
#   .\build_colours.ps1 [-Skin 1058500] [-Protect]    build, zip to Downloads
#   .\build_colours.ps1 -Skin 1058500 -Protect -Live  the live app design
#   .\build_colours.ps1 -Skin 1058500 -Off            empty live design
#   -SaveDir <dir> -DesignDir <dir> -NoBuild           test seams
#
# Keep this file ASCII: PS 5.1 reads a BOM-less script as Windows-1252.
param(
    [string]$SaveDir = (Join-Path $env:LOCALAPPDATA 'Marvel\Saved\SaveGames'),
    [string]$DesignDir = '',
    # only this skin (the panel's button sends the hero it is looking at)
    [string]$Skin = '',
    [switch]$Protect,
    [switch]$Live,
    [switch]$Off,
    [switch]$NoBuild
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\skinlib.ps1')
function CLog([string]$m) { Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $m) }
$liveMode = $Live -or $Off
if (-not $DesignDir) { $DesignDir = if ($liveMode) { Join-Path $SS_Root 'work\ingame\protect' } else { Join-Path $SS_Root 'work\ingame\colourbuild' } }
if ($liveMode -and -not $Skin) { throw '-Live / -Off need -Skin' }
New-Item -ItemType Directory -Force -Path $DesignDir | Out-Null

$names = @{}
try { $sj = Get-Content (Join-Path $SS_Root 'skins.json') -Raw | ConvertFrom-Json; foreach ($p in $sj.PSObject.Properties) { $names[$p.Name] = [string]$p.Value } } catch {}
function Skin-Label([string]$sid) { if ($names.ContainsKey($sid)) { $names[$sid] } else { $sid } }
# write only when the content changed: the live preview follows the newest
# design, and a rewrite of the same thing would only make it repaint
function Write-Design($doc, [string]$path) {
    $json = $doc | ConvertTo-Json -Depth 8
    if ((Test-Path -LiteralPath $path) -and ([IO.File]::ReadAllText($path).Trim([char]0xFEFF).Trim() -eq $json.Trim())) { return $false }
    [IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
    $true
}
function Live-Doc([string]$sid, $ops) {
    [ordered]@{ modName = 'InGameColours' + $sid; displayName = ('In-game colours - {0}' -f (Skin-Label $sid))
                hero = $sid.Substring(0, 4); skin = $sid; chromaSkins = @(); ops = $ops; colorOps = [ordered]@{} }
}

if ($Off) {
    $dp = Join-Path $DesignDir ('InGameColours{0}.json' -f $Skin)
    if (-not (Test-Path -LiteralPath $dp)) { CLog "no live design for $Skin - nothing to clear"; return }
    $w = Write-Design (Live-Doc $Skin ([ordered]@{})) $dp
    CLog ('live design for {0} emptied{1}' -f $Skin, $(if ($w) { '' } else { ' (already empty)' }))
    return
}

$sav = Join-Path $SaveDir 'SkinStudioColors.sav'
if (-not (Test-Path -LiteralPath $sav)) { throw 'no colour save yet - make a colour edit in the F8 panel first' }
$txt = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($sav))
$inv = [Globalization.CultureInfo]::InvariantCulture
$bySkin = [ordered]@{}
foreach ($m in [regex]::Matches($txt, '(MI_[A-Za-z0-9_]+)\|([^|;\x00]+)\|([0-9.eE+-]+),([0-9.eE+-]+),([0-9.eE+-]+)')) {
    $mi = $m.Groups[1].Value
    # the skin id can sit after a prefix (MI_WP_1067001_Sickle, MI_10600_1060001_Head)
    $sk = [regex]::Match($mi, '_(\d{7})(?:_|$)')
    if (-not $sk.Success) { if (-not $Skin) { CLog "  skipped $mi (no skin id in its name)" }; continue }
    $sid = $sk.Groups[1].Value
    if ($Skin -and $sid -ne $Skin) { continue }
    if (-not $bySkin.Contains($sid)) { $bySkin[$sid] = New-Object System.Collections.ArrayList }
    [void]$bySkin[$sid].Add(@{ Mi = $mi; Param = $m.Groups[2].Value.Trim()
        R = [double]::Parse($m.Groups[3].Value, $inv); G = [double]::Parse($m.Groups[4].Value, $inv); B = [double]::Parse($m.Groups[5].Value, $inv) })
}
if ($bySkin.Count -eq 0) {
    if ($Live) { $bySkin[$Skin] = New-Object System.Collections.ArrayList }      # nothing to paint = an empty live design
    else { throw $(if ($Skin) { "the colour save holds no edits for skin $Skin" } else { 'the colour save holds no edits' }) }
}

# texture leaf -> op rel ("Marvel\Content\...\T_x_D.png"), from the game index
$texRel = @{}
if ($Protect -or $Live) {
    $null = SS-EnsureTexIndex { param($x) CLog "  $x" }
    foreach ($raw in [IO.File]::ReadLines((Join-Path $SS_Cache 'char_manifest.txt'))) {
        $t = $raw.Trim([char]0xFEFF).Trim()
        if (-not $t.EndsWith('_D.uasset')) { continue }
        $leaf = $t.Substring($t.LastIndexOf('/') + 1) -replace '\.uasset$', ''
        if (-not $texRel.ContainsKey($leaf)) { $texRel[$leaf] = ($t -replace '^(\.\./)+', '' -replace '\.uasset$', '.png') -replace '/', '\' }
    }
}
function To-SrgbHex([double]$r, [double]$g, [double]$b) {
    $c = foreach ($v in @($r, $g, $b)) {
        $v = [Math]::Max(0.0, [Math]::Min(1.0, $v))
        $s = if ($v -le 0.0031308) { 12.92 * $v } else { 1.055 * [Math]::Pow($v, 1.0 / 2.4) - 0.055 }
        [int][Math]::Round([Math]::Max(0.0, [Math]::Min(1.0, $s)) * 255)
    }
    '#{0:X2}{1:X2}{2:X2}' -f $c[0], $c[1], $c[2]
}

$built = @(); $failed = @()
foreach ($sid in @($bySkin.Keys)) {
    $edits = @($bySkin[$sid])
    CLog ("skin {0}: {1} colour edit(s){2}" -f $sid, $edits.Count, $(if ($Protect -or $Live) { ', Protect skin on' } else { '' }))
    $cj = SS-EnsureColorCache $sid { param($x) CLog "  $x" }
    # PS 5.1 emits a JSON array as ONE pipeline object: assign first, then @()
    $parsed = Get-Content -LiteralPath $cj -Raw | ConvertFrom-Json
    $mats = @($parsed)
    $matTex = $null
    if ($Protect -or $Live) { $matTex = Get-Content -LiteralPath (SS-EnsureMatTextures $sid { param($x) CLog "  $x" }) -Raw | ConvertFrom-Json }
    $colorOps = [ordered]@{}
    $ops = [ordered]@{}
    $skipped = @()
    foreach ($e in $edits) {
        if (($Protect -or $Live) -and $e.Param -eq 'BaseTint') {
            # white = no tint: nothing to paint
            if ($e.R -ge 0.98 -and $e.G -ge 0.98 -and $e.B -ge 0.98) { continue }
            $entry = if ($matTex) { $matTex.PSObject.Properties[$e.Mi] } else { $null }
            $dTex = if ($entry) { @($entry.Value.textures | Where-Object { $_ -cmatch '_D$' -and $texRel.ContainsKey($_) }) } else { @() }
            if ($dTex.Count -eq 0) { $skipped += ('{0} Tint (no texture found)' -f $e.Mi); continue }
            $hex = To-SrgbHex $e.R $e.G $e.B
            # a grey Tint only darkens in game (a multiply); 'paint' would wash
            # the part out towards that grey, so darken it instead (hsl, light
            # x the grey's own lightness in sRGB)
            $mx = [Math]::Max($e.R, [Math]::Max($e.G, $e.B)); $mn = [Math]::Min($e.R, [Math]::Min($e.G, $e.B))
            $grey = ($mx -le 0) -or ((($mx - $mn) / $mx) -lt 0.08)
            $lum = [Convert]::ToInt32($hex.Substring(1, 2), 16) / 255.0
            $op = if ($grey) { [ordered]@{ mode = 'hsl'; color = $hex; strength = 1.0; hueShift = 0.0; satMul = 1.0; lightMul = [Math]::Round($lum, 3); protectSkin = $true } }
                  else { [ordered]@{ mode = 'paint'; color = $hex; strength = 1.0; hueShift = 0.0; satMul = 1.0; lightMul = 1.0; protectSkin = $true } }
            foreach ($d in $dTex) {
                $rel = $texRel[$d]
                if ($ops.Contains($rel)) { CLog ("  {0} is shared - {1}'s Tint loses to an earlier part" -f $d, $e.Mi); continue }
                $ops[$rel] = @($op)
            }
            continue
        }
        if ($Live) { continue }      # the panel keeps the other colours on the MIDs itself
        $hit = 0
        foreach ($mat in $mats) {
            $leaf = [IO.Path]::GetFileNameWithoutExtension([string]$mat.asset)
            if ($leaf -ne $e.Mi) { continue }
            # the first stored colour of that name (MC_Shade repeats: the
            # panel's value is the one a MID read returns, the first)
            $c = @($mat.colors | Where-Object { $_.name -eq $e.Param })[0]
            if (-not $c) { continue }
            if (-not $colorOps.Contains([string]$mat.asset)) { $colorOps[[string]$mat.asset] = New-Object System.Collections.ArrayList }
            [void]$colorOps[[string]$mat.asset].Add([ordered]@{ export = $c.export; ordinal = $c.ordinal; name = $e.Param; r = $e.R; g = $e.G; b = $e.B })
            $hit++
        }
        if ($hit -eq 0) { $skipped += ('{0} {1}' -f $e.Mi, $e.Param) }
    }
    if ($skipped.Count) { CLog ("  skipped: {0}" -f ($skipped -join '; ')) }
    if ($Live) {
        $dp = Join-Path $DesignDir ('InGameColours{0}.json' -f $sid)
        $w = Write-Design (Live-Doc $sid $ops) $dp
        CLog ('  live design {0}: {1} texture(s){2}' -f $dp, $ops.Count, $(if ($w) { '' } else { ' (unchanged)' }))
        continue
    }
    if ($colorOps.Count -eq 0 -and $ops.Count -eq 0) { CLog "  nothing buildable for $sid"; $failed += $sid; continue }
    $doc = [ordered]@{
        modName = 'SkinStudio' + $sid; displayName = ('Skin Studio colours - {0}' -f (Skin-Label $sid))
        hero = $sid.Substring(0, 4); skin = $sid; chromaSkins = @(); ops = $ops; colorOps = $colorOps
    }
    $dp = Join-Path $DesignDir ('SkinStudio{0}.json' -f $sid)
    $null = Write-Design $doc $dp
    CLog ("  design: {0} ({1} texture(s), {2} material(s))" -f $dp, $ops.Count, $colorOps.Count)
    if ($NoBuild) { continue }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $SS_Root 'build_skin.ps1') -Design $dp -Zip
    if ($LASTEXITCODE -eq 0) { $built += $sid; CLog "  built $sid - zip copied to Downloads" } else { $failed += $sid; CLog "  build FAILED for $sid (exit $LASTEXITCODE)" }
}
if (-not $Live) {
    CLog ('done: built {0}; failed {1}' -f $(if ($built.Count) { $built -join ', ' } else { '-' }), $(if ($failed.Count) { $failed -join ', ' } else { '-' }))
    if (-not $NoBuild -and $failed.Count -and -not $built.Count) { exit 1 }
}

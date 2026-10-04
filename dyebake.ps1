# dyebake.ps1 - "your texture edits win over the game's dye" (her call,
# 2026-09-24), shared by live_preview.ps1 (the F6 preview) and build_skin.ps1
# (real mods) so the preview and the mod can never disagree. Dot-source after
# skinlib.ps1 and viewlib.ps1 (ViewArt.DyeComposite, SS-ViewMatColors,
# SS-ViewDyeBlock).
#
# In a dyed material the game PAINTS each masked region with its dye colour,
# whatever the diffuse holds there - so a texture edit under a dye region never
# showed. The dye mask's alpha picks the region and alpha 0 means "undyed, the
# art shows" (proven in game on Viridian's jacket, 2026-09-24). So for a dyed
# material whose D she edits:
#   1. bake the dye (vanilla, or with her colour edits) into the VANILLA D,
#      with the verified rules the 3D preview uses (ViewArt.DyeComposite),
#   2. lay her texture edits ON TOP of that - what the game shows is what she
#      edits, and a whole-image replace (her chroma copies) comes out exact,
#   3. ship a blank dye mask for the material, so the game's dye stops painting.
# Areas she did not touch keep their in-game colours.
#
# The live preview also bakes pure colour edits (Blueprint cannot set vector
# params), BaseTint included as edited/vanilla. A build does NOT: its material
# params are patched for real, so it bakes only where a texture edit needs the
# dye out of the way.

if (-not ('LiveBake' -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class LiveBake {
    // multiply R,G,B in place; alpha is data, never touched. The game reads a
    // D map's bytes on the same scale as its material colours (the white-dye
    // meter, 2026-09-20), so BaseTint scales the bytes directly.
    public static void ScaleRgb(Bitmap b, double kr, double kg, double kb) {
        var rc = new Rectangle(0, 0, b.Width, b.Height);
        BitmapData d = b.LockBits(rc, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        try {
            int n = d.Stride * b.Height;
            byte[] px = new byte[n];
            Marshal.Copy(d.Scan0, px, 0, n);
            for (int y = 0; y < b.Height; y++) {
                int o = y * d.Stride;
                for (int x = 0; x < b.Width; x++, o += 4) {          // BGRA
                    px[o]     = Clamp(px[o] * kb);
                    px[o + 1] = Clamp(px[o + 1] * kg);
                    px[o + 2] = Clamp(px[o + 2] * kr);
                }
            }
            Marshal.Copy(px, 0, d.Scan0, n);
        } finally { b.UnlockBits(d); }
    }
    static byte Clamp(double v) { v = Math.Round(v); return (byte)(v < 0 ? 0 : (v > 255 ? 255 : v)); }
    // transparent black: alpha 0 everywhere = undyed
    public static Bitmap Blank(int w, int h) {
        var b = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(b)) g.Clear(Color.FromArgb(0, 0, 0, 0));
        return b;
    }
    public static void BlankMask(string path, int side) {
        using (var b = Blank(side, side)) b.Save(path, ImageFormat.Png);
    }
}
'@
}

$SS_DyeColorRx = '^Region \d+ - Color(A|B|GChannel|BChannel)$'

# what the standalone in-game panel applies by itself every match: its colour
# save (SkinStudioColors, "MI|Param|r,g,b;..."), "MI|Param" -> [r,g,b]. Empty
# when the standalone mod is not in ~mods (nothing applies the save then).
function SS-InGameTints {
    $out = @{}
    $mods = Join-Path $SS_Paks '~mods'
    if (-not (Test-Path -LiteralPath (Join-Path $mods '!!SkinStudio_9999999_P.pak'))) { return $out }
    $sav = Join-Path $env:LOCALAPPDATA 'Marvel\Saved\SaveGames\SkinStudioColors.sav'
    if (-not (Test-Path -LiteralPath $sav)) { return $out }
    $s = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($sav))
    $inv = [Globalization.CultureInfo]::InvariantCulture
    foreach ($m in [regex]::Matches($s, '(MI_[A-Za-z0-9_]+)\|([^|;\x00]+)\|([0-9.eE+-]+),([0-9.eE+-]+),([0-9.eE+-]+)')) {
        $out[$m.Groups[1].Value + '|' + $m.Groups[2].Value] = [double[]]@([double]::Parse($m.Groups[3].Value, $inv), [double]::Parse($m.Groups[4].Value, $inv), [double]::Parse($m.Groups[5].Value, $inv))
    }
    $out
}

# design colorOps (asset -> @(edits)) -> the viewer's shape,
# asset -> @{ "<export>_<ordinal>" -> edit }. Plain hashtables: SS-OpVal reads
# nothing else (an [ordered] one silently reads as empty).
function SS-EditMapFromDesign($dj) {
    $out = @{}
    if (-not $dj.PSObject.Properties['colorOps'] -or -not $dj.colorOps) { return $out }
    foreach ($p in $dj.colorOps.PSObject.Properties) {
        $inner = @{}
        foreach ($e in @($p.Value)) {
            if ($null -eq $e) { continue }
            $edit = @{ export = [int]$e.export; ordinal = [int]$e.ordinal; name = [string]$e.name; r = [double]$e.r; g = [double]$e.g; b = [double]$e.b }
            if ($e.PSObject.Properties['kind'] -and $e.kind) { $edit.kind = [string]$e.kind }
            $inner['{0}_{1}' -f $e.export, $e.ordinal] = $edit
        }
        if ($inner.Count) { $out[[string]$p.Name] = $inner }
    }
    $out
}

# a texture's cached vanilla PNG and its rel under png\src (the skin id is in
# the name; its cache is built on demand)
function SS-FindCachedTex([string]$texName, $map, [scriptblock]$Log) {
    if ($texName -notmatch '(?<!\d)(\d{7})(?!\d)') { return $null }
    $sid = $Matches[1]
    if ($map.skinLines.ContainsKey($sid)) { $null = SS-EnsureSkinCache $sid $map.skinLines[$sid] $Log $null }
    $root = Join-Path $SS_Cache (Join-Path $sid 'png\src')
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $hit = @(Get-ChildItem -LiteralPath $root -Filter ($texName + '.png') -File -Recurse -ErrorAction SilentlyContinue)
    if ($hit.Count -ne 1) { return $null }
    @{ src = $hit[0].FullName; rel = $hit[0].FullName.Substring($root.Length + 1) }
}

# D leaf (with .png) -> what to bake for it.
#   -Live: every match material whose dye (or BaseTint) the design changes, or
#          whose D it edits  (Blueprint can only swap textures)
#   build: only dyed materials whose D the design edits
# A plan: skin mi dName dLeaf dRel dSrc  mName mLeaf mRel mSrc (blank mask, or '')
#         op (her D edits or $null)  block (dye to bake or $null)  ratio (BaseTint, live only)
function SS-DyePlans($dj, $map, [bool]$Live, [scriptblock]$Log) {
    if (-not $Log) { $Log = { param($m) } }      # the cache builders call it unguarded
    $plans = @{}
    $edits = SS-EditMapFromDesign $dj
    $ops = @{}
    if ($dj.PSObject.Properties['ops'] -and $dj.ops) { foreach ($p in $dj.ops.PSObject.Properties) { $ops[$p.Name] = $p.Value } }
    $opRelOf = @{}
    foreach ($r in $ops.Keys) { $opRelOf[[IO.Path]::GetFileNameWithoutExtension($r)] = $r }
    $rxSkin = [regex]'[\\/]Characters[\\/]\d{4}[\\/](\d{7})[\\/]'
    $skinOf = { param($k) $mm = $rxSkin.Match($k); if ($mm.Success) { $mm.Groups[1].Value } else { [string]$dj.skin } }
    $skins = @{}
    foreach ($k in @(@($edits.Keys) + @($ops.Keys))) { $skins[(& $skinOf $k)] = $true }
    foreach ($sid in @($skins.Keys | Sort-Object)) {
        if (-not $map.skinLines.ContainsKey($sid)) { continue }
        $null = SS-EnsureSkinCache $sid $map.skinLines[$sid] $Log $null
        $null = SS-EnsureColorCache $sid $Log $null 'mat'
        $mt = Get-Content -LiteralPath (SS-EnsureMatTextures $sid $Log) -Raw | ConvertFrom-Json
        $mine = @{}
        foreach ($k in $edits.Keys) { if ((& $skinOf $k) -eq $sid) { $mine[$k] = $edits[$k] } }
        $now = SS-ViewMatColors $sid $mine
        $van = SS-ViewMatColors $sid $null
        # pass 1: every match material (the lobby set shares the same textures),
        # grouped by the D it draws - several can share one, e.g. Viridian's fur
        # shell MI_1064301_Equip_04 reuses Equip_01's D and mask with a
        # completely different dye palette (0 of 28 region colours match)
        $byD = @{}
        foreach ($key in @($van.Keys | Where-Object { $_ -like 'M|*' } | Sort-Object)) {
            $mi = $key.Substring(2)
            $mp = $mt.PSObject.Properties[$mi]
            if (-not $mp) { continue }
            $texs = @($mp.Value.textures)
            $dName = @($texs | Where-Object { $_ -like '*_D' })[0]
            if (-not $dName) { continue }
            $mName = @($texs | Where-Object { $_ -like '*_ColorID' })[0]
            $pv = $van[$key].params; $pe = $now[$key].params
            $dye = $false; $tint = $false
            foreach ($pn in @($pe.Keys)) {
                if (-not $pv.ContainsKey($pn)) { continue }
                $a = $pe[$pn]; $b = $pv[$pn]
                if (([Math]::Abs($a[0] - $b[0]) + [Math]::Abs($a[1] - $b[1]) + [Math]::Abs($a[2] - $b[2])) -lt 0.0005) { continue }
                if ($pn -match $SS_DyeColorRx) { $dye = $true } elseif ($pn -eq 'BaseTint') { $tint = $true }
            }
            $block = $null
            if ($mName) {
                $block = SS-ViewDyeBlock $pe
                if (-not ($block | Where-Object { $_ -ne 0 })) { $block = $null }   # a mask with no dye params dyes nothing
            }
            if (-not $byD.ContainsKey($dName)) { $byD[$dName] = @() }
            $byD[$dName] += , @{ mi = $mi; mName = $mName; pv = $pv; pe = $pe; dye = $dye; tint = $tint; block = $block }
        }
        # pass 2: one decision per D, made with the D's OWN material
        # (T_x_Equip_01_D -> MI_x_Equip_01). One baked D and one shared mask
        # cannot hold two palettes, so the others follow it.
        foreach ($dName in @($byD.Keys | Sort-Object)) {
            $cands = @($byD[$dName])
            $ownerName = 'MI_' + ($dName -replace '^T_', '' -replace '_D$', '')
            $owner = @($cands | Where-Object { $_.mi -eq $ownerName })[0]
            if (-not $owner -or -not $owner.block) {
                $dyedOne = @($cands | Where-Object { $_.block })[0]
                if ($dyedOne) { $owner = $dyedOne } elseif (-not $owner) { $owner = $cands[0] }
            }
            $others = @($cands | Where-Object { $_.mi -ne $owner.mi })
            $mi = $owner.mi; $mName = $owner.mName; $pv = $owner.pv; $pe = $owner.pe
            $dye = $owner.dye; $tint = $owner.tint; $block = $owner.block
            $opRel = $opRelOf[$dName]
            $full = if ($Live) { $block -and ($opRel -or $dye -or $tint) } else { $block -and $opRel }
            $tintOnly = $Live -and $tint -and -not $full
            foreach ($o in $others) {
                if ($o.dye -or $o.tint) {
                    if ($Live) { & $Log ("  note: colour edits on {0} can't be previewed live - it shares {1} with {2}; a real build shows them" -f $o.mi, $dName, $mi) }
                    elseif ($full) { & $Log ("  note: your texture edit on {0} also covers {1}'s dye, so its colour edits won't show" -f $dName, $o.mi) }
                }
                if ($full -and $o.block) { & $Log ("  note: {0} draws {1} too - while your edit is on, it shows these colours instead of its own dye" -f $o.mi, $dName) }
            }
            if (-not $full -and -not $tintOnly) { continue }
            $leaf = $dName + '.png'
            if ($plans.ContainsKey($leaf)) { continue }
            $dTex = SS-FindCachedTex $dName $map $Log
            if (-not $dTex) { if ($Log) { & $Log "  WARN: no cached PNG for $dName - $mi skipped" }; continue }
            $mTex = if ($full) { SS-FindCachedTex $mName $map $Log } else { $null }
            if ($full -and -not $mTex) { if ($Log) { & $Log "  WARN: no cached PNG for $mName - $mi skipped" }; continue }
            $ratio = $null
            if ($Live -and $tint) {
                # 2026-10-02: the in-game Skin Studio panel already sets BaseTint
                # on the material from its own save, so baking edited/vanilla on
                # top doubled the tint. Bake edited / (what the game applies).
                $applied = $pv['BaseTint']
                $gt = (SS-InGameTints)[$mi + '|BaseTint']
                if ($gt) { $applied = $gt; & $Log ("  {0}: the in-game panel already tints it, baking only the difference" -f $mi) }
                $ratio = [double[]]@(1, 1, 1)
                for ($c = 0; $c -lt 3; $c++) {
                    if ([Math]::Abs($applied[$c]) -lt 0.0001) { if ($Log) { & $Log "  WARN: $mi BaseTint is 0 in a channel - that channel cannot be previewed" }; continue }
                    $ratio[$c] = $pe['BaseTint'][$c] / $applied[$c]
                }
            }
            $plans[$leaf] = @{
                skin = $sid; mi = $mi; dName = $dName; dLeaf = $leaf; dRel = $dTex.rel; dSrc = $dTex.src
                mName = $(if ($mTex) { $mName } else { '' }); mLeaf = $(if ($mTex) { $mName + '.png' } else { '' })
                mRel = $(if ($mTex) { $mTex.rel } else { '' }); mSrc = $(if ($mTex) { $mTex.src } else { '' })
                op = $(if ($opRel) { $ops[$opRel] } else { $null }); block = $(if ($full) { $block } else { $null }); ratio = $ratio
                dyeEdited = $dye
            }
        }
    }
    $plans
}

# the finished D for a plan, as a Bitmap (the caller saves it and disposes it):
# dye baked into the VANILLA map, her edits on top, then (live) BaseTint
function SS-RenderDyeBake($plan) {
    $tmpDir = Join-Path $SS_Root 'work\dye_bake'
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    $dyed = Join-Path $tmpDir ('dyed_{0}_{1}.png' -f $PID, $plan.dName)
    try {
        $src = $plan.dSrc
        if ($plan.block) {
            # the VANILLA mask decides the regions - the blank one only goes to the game
            [void][ViewArt]::DyeComposite($src, $plan.mSrc, $dyed, $plan.block, 16384)
            $src = $dyed
        }
        $bmp = if ($plan.op) { SS-RenderStack $src $plan.op } else { [SkinArt]::Load($src) }
        if ($plan.ratio) { [LiveBake]::ScaleRgb($bmp, $plan.ratio[0], $plan.ratio[1], $plan.ratio[2]) }
        $bmp
    } finally {
        if (Test-Path -LiteralPath $dyed) { Remove-Item -LiteralPath $dyed -Force }
    }
}

# one short label for the log
function SS-DyePlanLabel($plan) {
    $w = @()
    if ($plan.block) { $w += $(if ($plan.dyeEdited) { 'your dye colours' } else { 'the dye' }) }
    if ($plan.op) { $w += 'your texture edits on top' }
    if ($plan.ratio) { $w += ('BaseTint x{0:0.##},{1:0.##},{2:0.##}' -f $plan.ratio[0], $plan.ratio[1], $plan.ratio[2]) }
    ($w -join ' + ') + ' (' + $plan.mi + ')'
}

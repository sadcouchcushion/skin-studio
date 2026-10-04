# meshlib.ps1 - character meshes without FModel, via Atelier's AtelierMesh.exe.
# Dot-sourced AFTER skinlib.ps1 (uses $SS_Paks, $SS_Cache, $SS_GameAes, $SS_Usmap,
# SS-ManifestRel, SS-GamePatchIndex).
#
# Atelier (github.com/clownfetus/Atelier, GPL-3.0) is a separate app she has
# installed. We only RUN its CUE4Parse mesh decoder as an external program - no
# Atelier code is copied in here - so nothing about Skin Studio's own licence
# changes. If Atelier is not installed every function here says so and the
# FModel route in SkinStudio.ps1 still works.
#
#   AtelierMesh.exe --paks <dir> --aes 0x<key> --usmap <usmap>
#                   --asset Marvel/Content/Marvel/.../SK_x   (no extension)
#                   --out <dir>        -> <dir>\Marvel\Content\...\SK_x.glb
#
# The .glb carries geometry, skeleton, UVs and one material slot per MI
# (named MI_<skin>_Body etc.) but NO textures - bind those from
# mat_textures.json (SS-EnsureMatTextures).

$SS_AtelierRoot = Join-Path $env:LOCALAPPDATA 'Atelier'
$SS_AtelierMesh = Join-Path $SS_AtelierRoot 'Tools\AtelierMesh\AtelierMesh.exe'

function SS-AtelierMeshAvailable { Test-Path -LiteralPath $SS_AtelierMesh }

# Newest usmap on the machine. Atelier re-downloads one per game build and names
# it for the build ("5.3.2-3870120+++depot_marvel+S10.0_release-Marvel.usmap"),
# so prefer that when it exists; ours (blender\Marvel.usmap) is the fallback.
function SS-BestUsmap {
    $cfgF = Join-Path $SS_AtelierRoot 'mr_config.json'
    try {
        if (Test-Path -LiteralPath $cfgF) {
            $u = [string](Get-Content -LiteralPath $cfgF -Raw | ConvertFrom-Json).usmap
            if ($u -and (Test-Path -LiteralPath $u)) { return $u }
        }
    } catch {}
    $SS_Usmap
}

# The Paks directory to hand AtelierMesh. CUE4Parse scans RECURSIVELY, so the
# real Paks folder would let ~mods win (the viewer would show installed mods,
# not vanilla). Atelier keeps a hardlink mirror of the top level for exactly
# this reason; we READ it when it matches the game, and never build, touch or
# delete one ourselves - a recursive delete over a hardlink mirror once took
# the game's 73 GB of paks with it.
# Returns @{ dir; vanilla = $true/$false }.
function SS-MeshPaksDir {
    $mirror = Join-Path $SS_AtelierRoot '_cache\vanilla_paks'
    if (Test-Path -LiteralPath $mirror) {
        $want = @{}
        foreach ($f in (Get-ChildItem -LiteralPath $SS_Paks -File -ErrorAction SilentlyContinue)) { $want[$f.Name] = $f.Length }
        $have = @{}
        foreach ($f in (Get-ChildItem -LiteralPath $mirror -File -ErrorAction SilentlyContinue)) { $have[$f.Name] = $f.Length }
        $ok = ($want.Count -gt 0 -and $want.Count -eq $have.Count)
        if ($ok) { foreach ($k in $want.Keys) { if (-not $have.ContainsKey($k) -or $have[$k] -ne $want[$k]) { $ok = $false; break } } }
        if ($ok) { return @{ dir = $mirror; vanilla = $true } }
    }
    @{ dir = $SS_Paks; vanilla = $false }
}

# SK_ lines from the mid-season Patch_-Windows_*_P containers. SS-GamePatchIndex
# keeps only T_/MI_/NS_, and a skin that ships whole in a patch (Jubilee's
# 1064300) has its mesh ONLY there. Own cache file, same stamp scheme, so the
# shared index is left exactly as it is.
function SS-GamePatchMeshLines {
    $utocs = @(Get-ChildItem $SS_Paks -Filter 'Patch_-Windows_*_P.utoc' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($utocs.Count -eq 0) { return @() }
    $stamp = (@($utocs | ForEach-Object { '{0}:{1}' -f $_.Name, $_.LastWriteTimeUtc.Ticks }) -join ';')
    $linesF = Join-Path $SS_Cache 'gamepatch_meshes.txt'
    $stampF = Join-Path $SS_Cache 'gamepatch_meshes.stamp'
    if ((Test-Path $linesF) -and (Test-Path $stampF) -and ((Get-Content $stampF -Raw).Trim() -eq $stamp)) {
        return [IO.File]::ReadAllLines($linesF)
    }
    [void](SS-GamePatchIndex)   # makes sure [SSUtocIndex] is compiled
    $keep = New-Object System.Collections.Generic.List[string]
    $rx = [regex]::new('/Characters/\d{4}/\d{7}/')
    foreach ($u in $utocs) {
        foreach ($t in [SSUtocIndex]::List($u.FullName, $SS_GameAes)) {
            if (-not $t.EndsWith('.uasset') -or -not $rx.IsMatch($t)) { continue }
            $leaf = $t.Substring($t.LastIndexOf('/') + 1)
            if ($leaf.StartsWith('SK_')) { $keep.Add($t) }
        }
    }
    New-Item -ItemType Directory -Force -Path $SS_Cache | Out-Null
    [IO.File]::WriteAllLines($linesF, $keep.ToArray())
    Set-Content -LiteralPath $stampF -Value $stamp -Encoding ascii
    $keep.ToArray()
}

# skin -> its skeletal mesh assets as content paths without extension
# (Marvel/Content/Marvel/Characters/<hero>/<skin>/Meshes/SK_...), lobby first.
# Named for the CHUNK, not always the hero (White Fox ships SK_10600_1060500_Lobby),
# so match any SK_ under the skin folder.
function SS-SkinMeshAssets([string]$skin) {
    $hero = $skin.Substring(0, 4)
    # the costume itself lives directly in <skin>/Meshes/; Slots/Accessories and
    # Weapons carry their own SK_ meshes and are not the body
    $needle = "/Characters/$hero/$skin/Meshes/"
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $out = New-Object System.Collections.Generic.List[string]
    $sources = New-Object System.Collections.Generic.List[string]
    $man = Join-Path $SS_Cache 'char_manifest.txt'
    if (Test-Path $man) { foreach ($l in [IO.File]::ReadLines($man)) { $sources.Add($l) } }
    foreach ($l in (SS-GamePatchMeshLines)) { $sources.Add($l) }
    foreach ($raw in $sources) {
        $t = $raw.Trim([char]0xFEFF).Trim()
        if (-not $t.EndsWith('.uasset') -or -not $t.Contains($needle)) { continue }
        $leaf = $t.Substring($t.LastIndexOf('/') + 1)
        if (-not $leaf.StartsWith('SK_')) { continue }
        # physics / shell / shadow proxies are not the costume
        # (Luna's folder also holds _Skeleton, _PA, _PhysicsAsset0, SK_Physics_Death)
        $base = $leaf -replace '\.uasset$', ''
        if ($base -match '(?i)_(PA|Skeleton|PhysicsAsset\d*|Physics|Shadow|Proxy)$' -or $base -like 'SK_Shell*' -or $base -like 'SK_Physics*') { continue }
        $asset = (SS-ManifestRel $t) -replace '\.uasset$', ''
        if ($seen.Add($asset)) { $out.Add($asset) }
    }
    @($out | Sort-Object @{ Expression = { if ($_ -like '*_Lobby') { 0 } else { 1 } } }, @{ Expression = { $_ } })
}

# Decode one skin's meshes to cache\<skin>\mesh\<SK_leaf>.glb (cached against
# the pak stamp). Returns the glb paths, lobby first. -Lobby keeps only the
# hero-select meshes (what the Blender bridge and paint-ID want), -Match only
# the in-match ones; neither = all.
function SS-EnsureMesh([string]$skin, [switch]$Lobby, [switch]$Match, [scriptblock]$Progress) {
    if (-not (SS-AtelierMeshAvailable)) { throw "Atelier is not installed ($SS_AtelierMesh) - use the FModel export instead" }
    $assets = @(SS-SkinMeshAssets $skin)
    if ($Lobby) { $assets = @($assets | Where-Object { $_ -like '*_Lobby' }) }
    if ($Match) { $assets = @($assets | Where-Object { $_ -notlike '*_Lobby' }) }
    if ($assets.Count -eq 0) { throw "no skeletal mesh found for skin $skin in the pak index" }
    $dir = Join-Path (Join-Path $SS_Cache $skin) 'mesh'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $stamp = (Get-Item $SS_Utoc).LastWriteTimeUtc.Ticks.ToString()
    try { $stamp += '|' + (SS-GamePatchIndex).stamp } catch {}
    $stampF = Join-Path $dir '.meshstamp'
    if (-not ((Test-Path $stampF) -and ((Get-Content $stampF -Raw).Trim() -eq $stamp))) {
        # game updated: drop the old decodes (plain files we wrote, no links)
        Get-ChildItem -LiteralPath $dir -Filter *.glb -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Delete() }
        Set-Content -LiteralPath $stampF -Value $stamp -Encoding ascii
    }
    $paks = $null
    $usmap = SS-BestUsmap
    $got = New-Object System.Collections.Generic.List[string]
    foreach ($a in $assets) {
        $leaf = $a.Substring($a.LastIndexOf('/') + 1)
        $glb = Join-Path $dir "$leaf.glb"
        if (-not (Test-Path -LiteralPath $glb)) {
            if (-not $paks) {
                $paks = SS-MeshPaksDir
                if (-not $paks.vanilla -and $Progress) { & $Progress 'note: reading the live Paks folder - an installed mesh mod would show instead of vanilla' | Out-Host }
            }
            if ($Progress) { & $Progress "Decoding mesh $leaf (about 10 s)..." | Out-Host }
            $tmp = Join-Path $dir '_out'
            if (Test-Path $tmp) { [IO.Directory]::Delete($tmp, $true) }
            $log = & $SS_AtelierMesh --paks $paks.dir --aes ('0x' + $SS_GameAes) --usmap $usmap --asset $a --out $tmp 2>&1
            $made = Join-Path $tmp (($a -replace '/', '\') + '.glb')
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $made)) {
                $why = (@($log) | Select-Object -Last 2) -join ' | '
                if (Test-Path $tmp) { [IO.Directory]::Delete($tmp, $true) }
                if ($Progress) { & $Progress "  could not decode $leaf : $why" | Out-Host }
                continue
            }
            [void](SS-GlbStripMorphs $made)
            [IO.File]::Move($made, $glb)
            [IO.Directory]::Delete($tmp, $true)
        }
        $got.Add($glb)
    }
    if ($got.Count -eq 0) { throw "AtelierMesh could not decode any mesh for skin $skin" }
    @($got)
}

# Read / write a .glb's JSON chunk. The BIN chunk is copied through untouched.
function SS-GlbReadJson([string]$glb) {
    $b = [IO.File]::ReadAllBytes($glb)
    $len = [BitConverter]::ToUInt32($b, 12)
    @{ bytes = $b; json = ([Text.Encoding]::UTF8.GetString($b, 20, $len) | ConvertFrom-Json); jsonLen = $len }
}
function SS-GlbWriteJson($g, [string]$outGlb) {
    $txt = $g.json | ConvertTo-Json -Depth 100 -Compress
    $jb = [Text.Encoding]::UTF8.GetBytes($txt)
    $pad = (4 - ($jb.Length % 4)) % 4
    $jLen = $jb.Length + $pad
    $restStart = 20 + $g.jsonLen                   # BIN chunk header onward
    $rest = $g.bytes.Length - $restStart
    $ms = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter($ms)
    $w.Write([uint32]0x46546C67); $w.Write([uint32]2); $w.Write([uint32](12 + 8 + $jLen + $rest))
    $w.Write([uint32]$jLen); $w.Write([uint32]0x4E4F534A)
    $w.Write($jb); for ($i = 0; $i -lt $pad; $i++) { $w.Write([byte]0x20) }
    $w.Write($g.bytes, $restStart, $rest)
    $w.Flush()
    [IO.File]::WriteAllBytes($outGlb, $ms.ToArray())
    $w.Dispose()
}

# Drop morph targets. AtelierMesh writes them with a different target count
# per primitive, and Blender 5.2's glTF importer then dies with
# "IndexError: list index out of range" in do_primitives (prim.targets[sk]).
# Nothing here needs facial morphs; the accessors stay in the file unused,
# which glTF allows.
function SS-GlbStripMorphs([string]$glb) {
    $g = SS-GlbReadJson $glb
    $n = 0
    foreach ($m in @($g.json.meshes)) {
        foreach ($p in @($m.primitives)) {
            if ($p.PSObject.Properties['targets']) { $p.PSObject.Properties.Remove('targets'); $n++ }
        }
        if ($m.PSObject.Properties['weights']) { $m.PSObject.Properties.Remove('weights') }
        if ($m.PSObject.Properties['extras'] -and $m.extras.PSObject.Properties['targetNames']) { $m.extras.PSObject.Properties.Remove('targetNames') }
    }
    if ($n -gt 0) { SS-GlbWriteJson $g $glb }
    $n
}

# material slot names inside a .glb (the JSON chunk), in primitive order
function SS-GlbMaterials([string]$glb) {
    $fs = [IO.File]::OpenRead($glb)
    try {
        $hdr = New-Object byte[] 20
        [void]$fs.Read($hdr, 0, 20)
        $len = [BitConverter]::ToUInt32($hdr, 12)
        $buf = New-Object byte[] $len
        [void]$fs.Read($buf, 0, $len)
    } finally { $fs.Dispose() }
    $js = [Text.Encoding]::UTF8.GetString($buf) | ConvertFrom-Json
    @($js.materials | ForEach-Object { [string]$_.name })
}

# skinlib.ps1 - shared plumbing for Skin Studio (dot-sourced by GUI + builder).
# Chain: rrcli manifest --filters -> filtered unpack (EXACT manifest lines only,
# globs match nothing) -> ddstools export png 5.3 -> [ops] -> ddstools inject
# cubic 5.3 -> rrcli pack -> loose triplet at ~mods root (S9 rule).

# Portable (2026-10-03): the app lives wherever this file is (C:\rs\SkinStudio on
# the dev PC, %LOCALAPPDATA%\SkinStudio for a Nexus install). Tools come from
# <root>\tools when shipped there, else the dev PC's C:\rs\tools.
$SS_Root  = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$SS_Tools = Join-Path $SS_Root 'tools'
if (-not (Test-Path -LiteralPath (Join-Path $SS_Tools 'rrcli'))) { $SS_Tools = 'C:\rs\tools' }
$SS_Rr    = Join-Path $SS_Tools 'rrcli\retoc-rivals-cli.exe'
$SS_Dds   = Join-Path $SS_Tools 'ddstools'

# The game's Paks folder, first hit wins: RS_SS_PAKS, <root>\game_paks.txt
# (written by setup.ps1 from the ~mods folder it ran in), every Steam library,
# then Epic's install manifests.
function SS-FindPaks {
    $tail = 'MarvelGame\Marvel\Content\Paks'
    $c = New-Object System.Collections.Generic.List[string]
    if ($env:RS_SS_PAKS) { $c.Add($env:RS_SS_PAKS) }
    $cfg = Join-Path $SS_Root 'game_paks.txt'
    if (Test-Path -LiteralPath $cfg) { $c.Add(([IO.File]::ReadAllText($cfg)).Trim()) }
    $steam = @('C:\Program Files (x86)\Steam')
    try { $r = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath; if ($r) { $steam += ($r -replace '/', '\') } } catch {}
    foreach ($s in @($steam)) {
        $vdf = [IO.Path]::Combine($s, 'steamapps\libraryfolders.vdf')
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) { $steam += ($m.Groups[1].Value -replace '\\\\', '\') }
        }
    }
    foreach ($s in ($steam | Select-Object -Unique)) { $c.Add([IO.Path]::Combine($s, 'steamapps\common\MarvelRivals', $tail)) }
    $epic = 'C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests'
    foreach ($f in @(Get-ChildItem -LiteralPath $epic -Filter *.item -File -ErrorAction SilentlyContinue)) {
        try { $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { continue }
        if ($j.InstallLocation -and (Test-Path -LiteralPath ([IO.Path]::Combine($j.InstallLocation, $tail)))) { $c.Add([IO.Path]::Combine($j.InstallLocation, $tail)) }
    }
    foreach ($p in $c) { if ($p -and (Test-Path -LiteralPath ([IO.Path]::Combine($p, 'pakchunkCharacter-Windows.utoc')))) { return $p } }
    'C:\Program Files (x86)\Steam\steamapps\common\MarvelRivals\' + $tail
}
$SS_Paks  = SS-FindPaks
$SS_Utoc  = Join-Path $SS_Paks 'pakchunkCharacter-Windows.utoc'
$SS_Cache = Join-Path $SS_Root 'cache'
# upstream retoc + the game's standard AES key: the only tool that can extract
# from the mid-season Patch_-Windows_*_P containers (see "game patch skins")
$SS_Retoc   = Join-Path $SS_Tools 'retoc.exe'
$SS_GameAes = '0C263D8C22DCB085894899C3A3796383E9BF9DE0CBFB08C9BF2DEF2E84F29D74'
if (-not (Test-Path $SS_Rr))  { $SS_Rr  = 'C:\rs\ThemeStudio\tools\rrcli\retoc-rivals-cli.exe' }
if (-not (Test-Path $SS_Dds)) { $SS_Dds = 'C:\rs\ThemeStudio\tools\ddstools' }

function SS-GameRunning { [bool](Get-Process -Name 'Marvel-Win64-Shipping','MarvelRivals' -ErrorAction SilentlyContinue) }

# ---- Blender bridge paths ---------------------------------------------------
$SS_Blender  = 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe'
$SS_FModel   = Join-Path $SS_Tools 'FModel\FModel.exe'
$SS_Usmap    = Join-Path $SS_Root 'blender\Marvel.usmap'
$SS_FmOut    = Join-Path $SS_Root 'blender\fmodel_out'
# model exports can land in FModel's ModelDirectory - watch every known root
$SS_FmRoots  = @($SS_FmOut, 'C:\rs\fmodel-out\Exports')

# bake the CURRENT design onto full-res PNGs for Blender: every color map lands
# flat in $texDir by leaf name - modified ones get their op stack applied,
# untouched ones are copied vanilla (so the whole model is dressed).
function SS-BakeBlenderTex([string]$ck, $ops, [string]$texDir, [scriptblock]$Progress) {
    New-Item -ItemType Directory -Force -Path $texDir | Out-Null
    $pngRoot = Join-Path $ck 'png\src'
    $rows = [IO.File]::ReadAllLines((Join-Path $ck 'thumbs.map'))
    $n = 0; $baked = 0
    foreach ($row in $rows) {
        $parts = $row.Split('|')
        # recompute the role rather than trusting thumbs.map column 3: caches
        # only rebuild on a game update, so a role change would never reach an
        # already-cached skin (same reason Open-Skin recomputes it)
        if ((SS-TexRole $parts[0]) -ne 'color') { continue }
        $rel = $parts[0]
        $srcPng = Join-Path $pngRoot $rel
        $dst = Join-Path $texDir (Split-Path $rel -Leaf)
        if ($ops -and $ops.ContainsKey($rel)) { SS-ApplyOp $srcPng $dst $ops[$rel]; $baked++ }
        else { Copy-Item -LiteralPath $srcPng -Destination $dst -Force }
        $n++
        if ($Progress -and ($n % 6 -eq 0)) { & $Progress ("baking design textures for Blender... {0}" -f $n) }
    }
    # Hand Blender the REAL material -> texture bindings. bridge.py used to work
    # them out from the names ('MI_x_Equip_01' -> 'T_x_Equip_01_D'), which is
    # right for most materials and silently wrong for the rest: White Fox's
    # MI_10600_1060500_Laser_02 draws from T_10600_1060500_Equip_01_D, and there
    # is no Laser_02 texture at all - so the tie, the lens, the teeth and the fox
    # tails all came up untextured. The MI packages know the answer; ship it.
    try {
        $skin = Split-Path $ck -Leaf
        $mt = Get-Content -LiteralPath (SS-EnsureMatTextures $skin $Progress) -Raw | ConvertFrom-Json
        $map = @{}
        foreach ($p in $mt.PSObject.Properties) {
            $pick = $null
            foreach ($sfx in '_D', '_E') {
                foreach ($t in @($p.Value.textures)) {
                    if ($t -notlike "*$sfx") { continue }
                    if (Test-Path -LiteralPath (Join-Path $texDir ($t + '.png'))) { $pick = $t + '.png'; break }
                }
                if ($pick) { break }
            }
            if ($pick) { $map[$p.Name] = $pick }
        }
        [IO.File]::WriteAllText((Join-Path $texDir '_matmap.json'), ($map | ConvertTo-Json -Depth 3))
        if ($Progress) { & $Progress ("material map: {0} of {1} materials bound to a baked texture" -f $map.Count, @($mt.PSObject.Properties).Count) }
    } catch {
        # never block the bake for this - Blender falls back to name matching
        if ($Progress) { & $Progress ("(no material map: {0} - Blender will match on names)" -f $_.Exception.Message) }
    }
    # anything in texDir newer than this stamp = paint saved from Blender
    Set-Content -LiteralPath (Join-Path $texDir '_bake.stamp') -Value ([DateTime]::UtcNow.Ticks) -Encoding ascii
    @{ total = $n; baked = $baked }
}

function SS-Workers {
    $cores = [Environment]::ProcessorCount
    if (SS-GameRunning) { [Math]::Max(2, [int][Math]::Floor($cores / 3)) }
    else                { [Math]::Max(2, $cores - 2) }
}

# keep SkinArt's parallel pixel engine on the same game-aware cap. Cached for
# 10s so hot paths (preview refresh, bulk thumbs) don't hit Get-Process per call.
$script:SS_ArtWorkersFixed = 0      # >0 pins the cap (build_skin -MaxWorkers)
$script:SS_ArtWorkersAt = [DateTime]::MinValue
function SS-SetArtWorkers {
    if ($script:SS_ArtWorkersFixed -gt 0) { [SkinArt]::MaxWorkers = $script:SS_ArtWorkersFixed; return }
    $now = [DateTime]::UtcNow
    if (($now - $script:SS_ArtWorkersAt).TotalSeconds -gt 10) {
        [SkinArt]::MaxWorkers = SS-Workers
        $script:SS_ArtWorkersAt = $now
    }
}

# ---- patch (encrypted) skins ------------------------------------------------
# Some just-dropped skins ship in an AES-encrypted Patch chunk keyed by a dynamic
# key GUID, so they never appear in the Character utoc. patch_skins.json maps
# skinId -> { chunk, key }. We decrypt a COPY (zero the utoc EncryptionKeyGuid so
# rrcli's --aes-key applies - the GUID is only a keyring label, not part of the
# AES) and extract through a minimal paks dir (global + chunk0 + Locres + the
# decrypted patch copies). The real Characteroptional chunk is unreadable and
# poisons rrcli's fast-path, so it is deliberately excluded.
$SS_PatchCfg  = Join-Path $SS_Root 'patch_skins.json'
$SS_PatchMini = Join-Path ([IO.Path]::GetPathRoot($SS_Paks)) 'SkinStudioPatch'   # on the paks volume (hardlinks)
$script:SS_PatchSkins = $null

function SS-LoadPatchSkins {
    if ($null -ne $script:SS_PatchSkins) { return $script:SS_PatchSkins }
    $h = @{}
    if (Test-Path $SS_PatchCfg) {
        try {
            $j = Get-Content $SS_PatchCfg -Raw | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) {
                if ($p.Value.chunk -and $p.Value.key) {
                    $h[$p.Name] = @{ chunk = [string]$p.Value.chunk; key = [string]$p.Value.key }
                }
            }
        } catch {}
    }
    $script:SS_PatchSkins = $h
    $h
}

function SS-LinkOrCopy([string]$src, [string]$dst) {
    if (Test-Path $dst) { Remove-Item $dst -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType HardLink -Path $dst -Target $src -ErrorAction SilentlyContinue | Out-Null
    if (-not (Test-Path $dst)) { Copy-Item $src $dst -Force }   # cross-volume fallback
}

# zero the 16-byte EncryptionKeyGuid at offset 64 of an IoStore .utoc copy
function SS-ZeroUtocGuid([string]$utoc) {
    $fs = [IO.File]::Open($utoc, 'Open', 'ReadWrite')
    try { $fs.Position = 64; $fs.Write((New-Object byte[] 16), 0, 16) } finally { $fs.Close() }
}

# ensure a decrypted mini paks dir for a patch chunk, fresh vs the source chunk.
# returns @{ dir; utoc } for use with rrcli --aes-key <key>.
function SS-EnsurePatchMini([string]$chunk, [scriptblock]$Progress) {
    $srcUtoc = Join-Path $SS_Paks "$chunk.utoc"
    if (-not (Test-Path $srcUtoc)) { throw "patch chunk '$chunk' not in the game paks (a game update may have replaced it)" }
    $optBase  = $chunk -replace '-Windows$', 'optional-Windows'
    $mini     = Join-Path $SS_PatchMini $chunk
    $miniUtoc = Join-Path $mini "$chunk.utoc"
    $stampF   = Join-Path $mini '.chunkstamp'
    $stamp    = (Get-Item $srcUtoc).LastWriteTimeUtc.Ticks.ToString()
    if ((Test-Path $miniUtoc) -and (Test-Path $stampF) -and ((Get-Content $stampF -Raw).Trim() -eq $stamp)) {
        return @{ dir = $mini; utoc = $miniUtoc }
    }
    if ($Progress) { & $Progress 'Preparing encrypted patch data (first use / after a game update)...' }
    if (Test-Path $mini) { Get-ChildItem $mini -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Delete() } }
    New-Item -ItemType Directory -Force -Path $mini | Out-Null
    foreach ($bs in 'global', 'pakchunk0-Windows', 'pakchunkLocres-Windows') {
        foreach ($f in Get-ChildItem $SS_Paks -Filter "$bs.*" -File -ErrorAction SilentlyContinue) {
            SS-LinkOrCopy $f.FullName (Join-Path $mini $f.Name)
        }
    }
    foreach ($cc in $chunk, $optBase) {
        foreach ($f in Get-ChildItem $SS_Paks -Filter "$cc.*" -File -ErrorAction SilentlyContinue) {
            Copy-Item $f.FullName (Join-Path $mini $f.Name) -Force
        }
        $u = Join-Path $mini "$cc.utoc"
        if (Test-Path $u) { SS-ZeroUtocGuid $u }
    }
    Set-Content -LiteralPath $stampF -Value $stamp -Encoding ascii
    @{ dir = $mini; utoc = $miniUtoc }
}

# tex_index lines for one patch skin (sidecar cache, refreshed when chunk changes)
function SS-PatchSkinLines([string]$skin, $info, [scriptblock]$Progress) {
    New-Item -ItemType Directory -Force -Path $SS_PatchMini | Out-Null
    $side  = Join-Path $SS_PatchMini "$skin.lines"
    $stF   = "$side.stamp"
    $srcUtoc = Join-Path $SS_Paks ("{0}.utoc" -f $info.chunk)
    if (-not (Test-Path $srcUtoc)) { return @() }
    $stamp = (Get-Item $srcUtoc).LastWriteTimeUtc.Ticks.ToString()
    if ((Test-Path $side) -and (Test-Path $stF) -and ((Get-Content $stF -Raw).Trim() -eq $stamp)) {
        return [IO.File]::ReadAllLines($side)
    }
    $mini = SS-EnsurePatchMini $info.chunk $Progress
    if ($Progress) { & $Progress ("Indexing patch skin $skin...") }
    $hero = $skin.Substring(0, 4)
    $man  = & $SS_Rr --aes-key $info.key manifest $mini.utoc --filters 2>$null
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($line in $man) {
        $t = ([string]$line).Trim([char]0xFEFF).Trim()
        if ($t.Length -eq 0) { continue }
        if ($t.Contains('/L10N/')) { continue }
        if (-not $t.Contains("/Characters/$hero/$skin/")) { continue }
        if (-not $t.EndsWith('.uasset')) { continue }
        $leaf = $t.Substring($t.LastIndexOf('/') + 1)
        if (-not $leaf.StartsWith('T_')) { continue }
        $keep.Add($t)
    }
    [IO.File]::WriteAllLines($side, $keep)
    Set-Content -LiteralPath $stF -Value $stamp -Encoding ascii
    $keep
}

# ---- game patch skins (Patch_-Windows_<build>_P containers) ------------------
# A mid-season game update does NOT touch pakchunkCharacter: it drops a
# Patch_-Windows_1.1.<build>_P container beside it carrying the new skins (and
# any re-cooked textures). Nothing keyed on the Character utoc ever notices, so
# new skins simply never showed up (2026-09-17: 11 skins in 1.1.3870120).
#
# rrcli cannot read these at all - manifest and unpack both abort with
# "FPackageId(...) has no path name entry", even with --full-iostore-check - and
# retoc's own `list` prints chunk ids only. So:
#   * paths come from the container's directory index, read directly below
#     (AES-256-ECB with the standard game key - the key GUID is zero)
#   * extraction uses `retoc to-legacy <Paks dir>` with the exact manifest line
#     as the filter. retoc reads only the TOP LEVEL of Paks (verified: it returns
#     vanilla bytes for a texture an installed ~mods container overrides), it
#     prefers the patch copy of a re-cooked package (verified on 1022506), and it
#     rebuilds the .uptnl top mip, so new-skin maps come out at full 2048x2048.
if (-not ('SSUtocIndex' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;

public static class SSUtocIndex
{
    static string ReadFString(BinaryReader r)
    {
        int len = r.ReadInt32();
        if (len == 0) return "";
        if (len < 0) { var u = r.ReadBytes(-len * 2); return Encoding.Unicode.GetString(u, 0, u.Length - 2); }
        var a = r.ReadBytes(len); return Encoding.UTF8.GetString(a, 0, a.Length - 1);
    }

    // every file path in an IoStore .utoc's directory index ("../../../Marvel/...")
    public static string[] List(string utoc, string aesHex) { return Walk(utoc, aesHex, false); }

    // same, each line prefixed "<40-hex content hash>|" - two files with the same
    // hash are byte-identical, which is how a chroma's reused maps are spotted
    // without extracting anything (see SS-ChromaGroups)
    public static string[] ListHashed(string utoc, string aesHex) { return Walk(utoc, aesHex, true); }

    static string[] Walk(string utoc, string aesHex, bool withHash)
    {
        byte[] idx; byte flags; byte[] metas = null; uint entryCountOut;
        using (var fs = File.OpenRead(utoc))
        using (var r = new BinaryReader(fs))
        {
            r.ReadBytes(16);
            byte version = r.ReadByte(); r.ReadBytes(3);
            uint headerSize = r.ReadUInt32();
            uint entryCount = r.ReadUInt32();
            uint blockCount = r.ReadUInt32();
            uint blockEntrySize = r.ReadUInt32();
            uint methodCount = r.ReadUInt32();
            uint methodLen = r.ReadUInt32();
            r.ReadUInt32();                         // compression block size
            uint dirIndexSize = r.ReadUInt32();
            r.ReadUInt32();                         // partition count
            r.ReadUInt64();                         // container id
            r.ReadBytes(16);                        // encryption key guid
            flags = r.ReadByte(); r.ReadBytes(3);
            uint seedsCount = r.ReadUInt32();
            r.ReadUInt64();                         // partition size
            uint noHashCount = r.ReadUInt32();
            entryCountOut = entryCount;
            if ((flags & 8) == 0 || dirIndexSize == 0) return new string[0];   // not indexed
            long pos = headerSize + entryCount * 12L + entryCount * 10L;        // chunk ids + offsets
            if (version >= 4) pos += seedsCount * 4L;                          // perfect hash seeds
            if (version >= 5) pos += noHashCount * 4L;                         // overflow chunks
            pos += blockCount * (long)blockEntrySize + methodCount * (long)methodLen;
            if ((flags & 4) != 0)                                              // signed
            {
                fs.Position = pos;
                int hashSize = r.ReadInt32();
                pos += 4 + hashSize * 2L + blockCount * 20L;
            }
            fs.Position = pos;
            idx = r.ReadBytes((int)dirIndexSize);
            // chunk metas follow the directory index: 32-byte content hash + 1 flag
            // byte each (verified 33.000 bytes/entry on both game containers)
            if (withHash) { metas = r.ReadBytes((int)(entryCount * 33)); }
        }
        if ((flags & 2) != 0)                                                  // encrypted
        {
            var key = new byte[aesHex.Length / 2];
            for (int i = 0; i < key.Length; i++) key[i] = Convert.ToByte(aesHex.Substring(i * 2, 2), 16);
            using (var aes = Aes.Create())
            {
                aes.Key = key; aes.Mode = CipherMode.ECB; aes.Padding = PaddingMode.None;
                using (var d = aes.CreateDecryptor()) idx = d.TransformFinalBlock(idx, 0, idx.Length - idx.Length % 16);
            }
        }
        var br = new BinaryReader(new MemoryStream(idx));
        string mount = ReadFString(br);
        int nd = br.ReadInt32();
        var dName = new uint[nd]; var dChild = new uint[nd]; var dSib = new uint[nd]; var dFile = new uint[nd];
        for (int i = 0; i < nd; i++) { dName[i] = br.ReadUInt32(); dChild[i] = br.ReadUInt32(); dSib[i] = br.ReadUInt32(); dFile[i] = br.ReadUInt32(); }
        int nf = br.ReadInt32();
        var fName = new uint[nf]; var fNext = new uint[nf]; var fData = new uint[nf];
        for (int i = 0; i < nf; i++) { fName[i] = br.ReadUInt32(); fNext[i] = br.ReadUInt32(); fData[i] = br.ReadUInt32(); }
        int ns = br.ReadInt32();
        var strs = new string[ns];
        for (int i = 0; i < ns; i++) strs[i] = ReadFString(br);
        const uint NONE = 0xFFFFFFFF;
        var outp = new List<string>(nf);
        var stack = new Stack<KeyValuePair<uint, string>>();
        if (nd > 0) stack.Push(new KeyValuePair<uint, string>(0, mount));
        var sb = new StringBuilder();
        while (stack.Count > 0)
        {
            var e = stack.Pop();
            for (uint f = dFile[e.Key]; f != NONE; f = fNext[f])
            {
                if (!withHash) { outp.Add(e.Value + strs[fName[f]]); continue; }
                sb.Length = 0;
                uint ti = fData[f];                       // directory index UserData = TOC entry
                if (ti < entryCountOut)
                {
                    int o = (int)(ti * 33);
                    for (int k = 0; k < 20; k++) sb.Append(metas[o + k].ToString("x2"));
                }
                sb.Append('|').Append(e.Value).Append(strs[fName[f]]);
                outp.Add(sb.ToString());
            }
            for (uint c = dChild[e.Key]; c != NONE; c = dSib[c])
                stack.Push(new KeyValuePair<uint, string>(c, e.Value + strs[dName[c]] + "/"));
        }
        return outp.ToArray();
    }
}
'@
}

$script:SS_GamePatch = $null
# @{ stamp; lines (T_/MI_/NS_ under a skin folder); set (HashSet of those lines);
#    skins (skinId -> $true) }. Cached on disk against the containers' write times.
function SS-GamePatchIndex {
    $utocs = @(Get-ChildItem $SS_Paks -Filter 'Patch_-Windows_*_P.utoc' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    $stamp = (@($utocs | ForEach-Object { '{0}:{1}' -f $_.Name, $_.LastWriteTimeUtc.Ticks }) -join ';')
    if ($script:SS_GamePatch -and $script:SS_GamePatch.stamp -eq $stamp) { return $script:SS_GamePatch }
    $linesF = Join-Path $SS_Cache 'gamepatch_lines.txt'
    $stampF = Join-Path $SS_Cache 'gamepatch.stamp'
    New-Item -ItemType Directory -Force -Path $SS_Cache | Out-Null
    if ((Test-Path $linesF) -and (Test-Path $stampF) -and ((Get-Content $stampF -Raw).Trim() -eq $stamp)) {
        $lines = [IO.File]::ReadAllLines($linesF)
    } else {
        $keep = New-Object System.Collections.Generic.List[string]
        $rx = [regex]::new('/Characters/\d{4}/\d{7}/')
        foreach ($u in $utocs) {
            foreach ($t in [SSUtocIndex]::List($u.FullName, $SS_GameAes)) {
                if (-not $t.EndsWith('.uasset') -or $t.Contains('/L10N/')) { continue }
                if (-not $rx.IsMatch($t)) { continue }
                $leaf = $t.Substring($t.LastIndexOf('/') + 1)
                if ($leaf.StartsWith('T_') -or $leaf.StartsWith('MI_') -or $leaf.StartsWith('NS_')) { $keep.Add($t) }
            }
        }
        $lines = $keep.ToArray()
        [IO.File]::WriteAllLines($linesF, $lines)
        Set-Content -LiteralPath $stampF -Value $stamp -Encoding ascii
    }
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    # skins per KIND - a patch can touch one kind and not the others. 1.1.3870120
    # carries 620 textures (13 skins) but re-cooks 16,540 materials across ~700
    # skins; lumping them together rebuilt every texture cache for nothing.
    $skins = @{ tex = @{}; mat = @{}; fx = @{} }
    $rx2 = [regex]::new('/Characters/(\d{4})/(\d{7})/')
    foreach ($l in $lines) {
        [void]$set.Add($l)
        $m = $rx2.Match($l)
        if (-not ($m.Success -and $m.Groups[2].Value.StartsWith($m.Groups[1].Value))) { continue }
        $leaf = $l.Substring($l.LastIndexOf('/') + 1)
        $kind = if ($leaf.StartsWith('T_')) { 'tex' } elseif ($leaf.StartsWith('MI_')) { 'mat' } elseif ($l.Contains('/Particles/')) { 'fx' } else { $null }
        if ($kind) { $skins[$kind][$m.Groups[2].Value] = $true }
    }
    $script:SS_GamePatch = @{ stamp = $stamp; lines = $lines; set = $set; skins = $skins }
    $script:SS_GamePatch
}

# does a patch container carry any of this skin's assets of that kind?
# kind: 'tex' (T_ textures) | 'mat' (MI_ materials) | 'fx' (NS_ particles)
# ---- chroma / recolor sibling skins -----------------------------------------
# A "chroma" is a recolour of a costume sold as its own skin id, so editing the
# costume leaves every chroma of it vanilla in game. Nothing in the ids says
# which is which: Magneto's 1037301 is a separate costume while 1037305 is a
# chroma of 1037304.
#
# What DOES say it: a recolour reuses the costume's technical maps (normals, ORM,
# metal/roughness, hair alpha) byte for byte - only the colour art is repainted.
# The container's directory index carries a content hash per file, so the whole
# roster can be grouped without extracting anything:
#   * compare the .ubulk/.uptnl hashes (the raw pixel payload). NOT .uasset -
#     those embed the asset's own name, so two copies of one texture never match.
#   * key each map by its leaf with the skin id blanked (T_#_Body_N.ubulk).
#   * same hero + >=3 shared technical maps + >=2 identical, then the ratio of
#     identical ones splits it (same Sure/Maybe idiom as SS-LinkGroups):
#       >= 0.8  SURE  - a real chroma. Measured: Vampy Jammies/Viridian 16/17,
#                       Radiant/Prismatic 21/22, Aqua Arsenal/Emerald 15/16,
#                       Master of Slumber/Jade Jammies 21/26.
#       0.5-0.8 MAYBE - shares the mesh but may be its own costume: Jeff default
#                       vs Gwenpool and Jeff-Pool both land at 7/12, and those are
#                       NOT recolours of each other. Cherry Delight/Blueberry Ice
#                       (a real pair) also lands here at 6/11, so maybes are
#                       offered, just not ticked.
#     Unrelated costumes are 0/7, 0/13 - the gap is wide.
$script:SS_ChromaGroups = $null
$SS_ChromaTechRx = '_(N|ORM|M|MRO|FM|AN|AO)\.(ubulk|uptnl)$'

function SS-ChromaGroups([scriptblock]$Progress) {
    $stamp = (Get-Item $SS_Utoc).LastWriteTimeUtc.Ticks.ToString() + '|' + (SS-GamePatchIndex).stamp
    if ($script:SS_ChromaGroups -and $script:SS_ChromaGroups.stamp -eq $stamp) { return $script:SS_ChromaGroups.groups }
    $jsonF = Join-Path $SS_Cache 'chroma_groups.json'
    $stampF = Join-Path $SS_Cache 'chroma_groups.stamp'
    New-Item -ItemType Directory -Force -Path $SS_Cache | Out-Null
    if ((Test-Path $jsonF) -and (Test-Path $stampF) -and ((Get-Content $stampF -Raw).Trim() -eq $stamp)) {
        $g = @{}
        try {
            $j = Get-Content $jsonF -Raw | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $g[$p.Name] = @{ Sure = @($p.Value.sure); Maybe = @($p.Value.maybe) } }
            $script:SS_ChromaGroups = @{ stamp = $stamp; groups = $g }
            return $g
        } catch {}
    }
    if ($Progress) { & $Progress 'Grouping recolor (chroma) skins - first run after a game update...' }
    $hashes = @{}
    $rx = [regex]::new('/Characters/(\d{4})/(\d{7})/', 'Compiled')
    $utocs = @($SS_Utoc) + @(Get-ChildItem $SS_Paks -Filter 'Patch_-Windows_*_P.utoc' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($u in $utocs) {
        foreach ($row in [SSUtocIndex]::ListHashed($u, $SS_GameAes)) {
            if (-not ($row.EndsWith('.ubulk') -or $row.EndsWith('.uptnl'))) { continue }
            $bar = $row.IndexOf('|'); if ($bar -lt 1) { continue }
            $path = $row.Substring($bar + 1)
            $m = $rx.Match($path); if (-not $m.Success) { continue }
            $skin = $m.Groups[2].Value
            if (-not $skin.StartsWith($m.Groups[1].Value)) { continue }
            $leaf = $path.Substring($path.LastIndexOf('/') + 1)
            if (-not $leaf.StartsWith('T_')) { continue }
            if ($leaf -notmatch $SS_ChromaTechRx) { continue }
            if (-not $hashes.ContainsKey($skin)) { $hashes[$skin] = @{} }
            $hashes[$skin][$leaf.Replace($skin, '#')] = $row.Substring(0, $bar)
        }
    }
    $groups = @{}
    foreach ($hero in ($hashes.Keys | Group-Object { $_.Substring(0, 4) })) {
        $ids = @($hero.Group | Sort-Object)
        for ($i = 0; $i -lt $ids.Count; $i++) {
            for ($j = $i + 1; $j -lt $ids.Count; $j++) {
                $a = $ids[$i]; $b = $ids[$j]
                $shared = 0; $same = 0
                foreach ($k in $hashes[$a].Keys) {
                    if (-not $hashes[$b].ContainsKey($k)) { continue }
                    $shared++
                    if ($hashes[$a][$k] -eq $hashes[$b][$k]) { $same++ }
                }
                if ($shared -lt 3 -or $same -lt 2 -or ($same / $shared) -lt 0.5) { continue }
                $tier = if (($same / $shared) -ge 0.8) { 'Sure' } else { 'Maybe' }
                foreach ($pair in @(@($a, $b), @($b, $a))) {
                    if (-not $groups.ContainsKey($pair[0])) { $groups[$pair[0]] = @{ Sure = New-Object System.Collections.Generic.List[string]; Maybe = New-Object System.Collections.Generic.List[string] } }
                    $groups[$pair[0]][$tier].Add($pair[1])
                }
            }
        }
    }
    $out = @{}
    $ord = [ordered]@{}
    foreach ($k in ($groups.Keys | Sort-Object)) {
        $out[$k] = @{ Sure = @($groups[$k].Sure | Sort-Object); Maybe = @($groups[$k].Maybe | Sort-Object) }
        $ord[$k] = [ordered]@{ sure = $out[$k].Sure; maybe = $out[$k].Maybe }
    }
    [IO.File]::WriteAllText($jsonF, ($ord | ConvertTo-Json -Depth 4))
    Set-Content -LiteralPath $stampF -Value $stamp -Encoding ascii
    $script:SS_ChromaGroups = @{ stamp = $stamp; groups = $out }
    $out
}

# leaf -> content hash for the textures of the given skins, from the container
# index (no extraction). Used to skip copying a map onto a recolor when the two
# already ship the SAME bytes: on Jubilee that is 39 of 52 maps, so the mod stays
# small and only what genuinely differs is shipped.
$script:SS_TexHashes = $null
function SS-TextureHashes([string[]]$skins) {
    $want = @{}
    foreach ($s in $skins) { $want[$s] = $true }
    $stamp = ((Get-Item $SS_Utoc).LastWriteTimeUtc.Ticks.ToString() + '|' + (SS-GamePatchIndex).stamp + '|' + (($skins | Sort-Object) -join ','))
    if ($script:SS_TexHashes -and $script:SS_TexHashes.stamp -eq $stamp) { return $script:SS_TexHashes.map }
    $out = @{}
    $rx = [regex]::new('/Characters/(\d{4})/(\d{7})/', 'Compiled')
    $utocs = @($SS_Utoc) + @(Get-ChildItem $SS_Paks -Filter 'Patch_-Windows_*_P.utoc' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($u in $utocs) {
        foreach ($row in [SSUtocIndex]::ListHashed($u, $SS_GameAes)) {
            if (-not ($row.EndsWith('.ubulk') -or $row.EndsWith('.uptnl'))) { continue }
            $bar = $row.IndexOf('|'); if ($bar -lt 1) { continue }
            $path = $row.Substring($bar + 1)
            $m = $rx.Match($path); if (-not $m.Success) { continue }
            if (-not $want.ContainsKey($m.Groups[2].Value)) { continue }
            $leaf = $path.Substring($path.LastIndexOf('/') + 1)
            if (-not $leaf.StartsWith('T_')) { continue }
            $out[$leaf] = $row.Substring(0, $bar)
        }
    }
    $script:SS_TexHashes = @{ stamp = $stamp; map = $out }
    $out
}

# do the costume and the recolor ship DIFFERENT bytes for this map? ($true when
# it cannot be told - copying is the safe answer)
function SS-MapDiffers($hashes, [string]$baseLeaf, [string]$chromaLeaf) {
    $any = $false
    foreach ($ext in '.ubulk', '.uptnl') {
        $a = $hashes[$baseLeaf + $ext]; $b = $hashes[$chromaLeaf + $ext]
        if ($a -and $b) { $any = $true; if ($a -ne $b) { return $true } }
        elseif ($a -or $b) { return $true }        # one has a mip the other lacks
    }
    -not $any
}

# the recolor siblings of one skin: @{ Sure = @(ids); Maybe = @(ids) }
function SS-ChromaTargets([string]$skin, [scriptblock]$Progress) {
    try {
        $g = SS-ChromaGroups $Progress
        if ($g.ContainsKey($skin)) { return @{ Sure = @($g[$skin].Sure); Maybe = @($g[$skin].Maybe) } }
    } catch {}
    @{ Sure = @(); Maybe = @() }
}

# translate a texture rel (or manifest line) from one skin to its sibling: the
# skin id appears in the folder AND in the leaf, so a plain replace does it
function SS-RelForSkin([string]$rel, [string]$fromSkin, [string]$toSkin) {
    $rel.Replace($fromSkin, $toSkin)
}

# ---- dye colours: why recolouring a chroma's TEXTURE is not enough ----------
# A chroma's colour does not live only in its art. Its materials carry per-region
# DYE colours - "Region 1 - ColorA/ColorB", "Region N - Color<R|G|B>Channel" -
# picked by the _ColorID mask the costume itself does not ship, and the shader
# multiplies them over the diffuse. Viridian Vibes is green because
# MI_1064301_Body's Region 1 is #62A488 / #A1F8D3, while MI_1064300_Body (the
# costume) carries no Region params at all. Recolour the texture alone and the
# dye re-tints it: a brown paint job came out muddy green in game.
# So the same op has to run over the dye colours as well.
#
# Which params count as dye: the studio's existing two gates (SS-ColorIsPickable)
# plus "it actually carries colour" - white means no dye, and black / grey ramp
# steps are lighting, not dye. Touching those would paint regions that were
# never tinted.
$SS_DyeNeutral = 0.035

# gate 1: the name says colour, not a direction / position / packed parameter.
# gate 2: the value sits in 0..1, so an sRGB colour can express it at all (an
# HDR dye like 1.4 would clamp and lose its punch). Mirrors the GUI's rules -
# see [[flinearcolor-is-not-always-a-colour]].
function SS-ColorIsPickable([string]$name, [double]$r, [double]$g, [double]$b) {
    if ($name -match '(?i)direction|\bdir\b|dir$|dir_|tangent|center|centre|position|\bpos\b|axis|tiling|param|mix\d*$|range|power|offset|smooth|fresnel|mask|uv|depth|bias|multiplier|intensity|roughness') { return $false }
    if ($name -match '(?i)hsv') { return $false }          # HSV control triples, not colours
    if ($name -match '(?i)shade') { return $false }        # cel-shading ramp = lighting steps
    $mx = [Math]::Max($r, [Math]::Max($g, $b))
    $mn = [Math]::Min($r, [Math]::Min($g, $b))
    if ($mx -gt 1.001 -or $mn -lt -0.001) { return $false }
    $true
}

# does this param actually dye anything? white = no tint, black = off, and a
# pure grey is a value, not a colour.
function SS-IsDyeColor([double]$r, [double]$g, [double]$b) {
    $mx = [Math]::Max($r, [Math]::Max($g, $b))
    $mn = [Math]::Min($r, [Math]::Min($g, $b))
    if ($mx -lt $SS_DyeNeutral) { return $false }                       # black
    if ($mn -gt (1 - $SS_DyeNeutral)) { return $false }                 # white
    if (($mx - $mn) -lt $SS_DyeNeutral) { return $false }               # grey
    $true
}

# ★ A REGION DYE PARAM IS A COLOUR EVEN WHEN IT IS HDR. Gate 2 above exists
# to keep DIRECTIONS and packed triples out of a colour picker - but a recolor's
# bright accents are dyed with components above 1 (Jubilee's jacket patches are
# 0.47 / 2.00 / 0.36 green, Blue Breezes' leg warmers 0.98 / 1.33 / 1.50), and
# skipping those is what left the patches green and the leg warmers blue after
# every carry-across up to v1-7. The NAME here is unambiguous, so trust it.
function SS-IsRegionDye([string]$name) {
    [bool]($name -match '^Region \d+ - Color(A|B|GChannel|BChannel)$')
}

# The HDR values are NOT a brightness to preserve. A white dye rendered a flat
# neutral zone in game, so the dye REPLACES the art rather than lighting it -
# a vanilla 2.0 accent is just an over-bright recolor choice, and the value to
# write is the design's own colour. (An earlier version scaled the sample up to
# the vanilla's brightest component; it made zones glow that the costume does
# not.) Only the 0..1 GATE had to go, which is what SS-IsRegionDye is for.
# ---- one design, one mod per skin ------------------------------------------
# A design that carries a costume's recolours builds as ONE mod by default. Split
# it and each skin becomes its own mod, so a player can take the look on one
# recolour without it landing on the others. Every op already carries its skin
# id in its rel, so the split is a filter - and it is clean: a recolour's
# materials reference none of the costume's textures (checked on Jubilee: 0 of
# 22), so no split mod depends on another.
# Props shared by the whole costume family (Jubilee's balloon and pillow live
# under the COSTUME's id) follow their id into the costume's mod. Each split mod
# then touches only its own skin's files and no two ever override the same one.

# the display name for a skin id, from skins.json ('' when it has none)
function SS-SkinName([string]$skin) {
    $p = Join-Path $SS_Root 'skins.json'
    if (-not (Test-Path -LiteralPath $p)) { return '' }
    try {
        $j = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
        $v = $j.PSObject.Properties[$skin]
        if ($v) { return [string]$v.Value }
    } catch {}
    ''
}

# Split a design object into one per skin. Returns @( @{ skin; doc } ), the
# costume first. modName gets the skin's name appended (letters/digits only, so
# the containers never collide), displayName gets " - <skin name>". dyeCal is
# keyed without skin ids, so every piece carries the whole of it.
function SS-SplitDesignBySkin($doc) {
    $rx = [regex]'[\\/](\d{7})[\\/]'
    # NB a plain @{} plus an order list, NOT [ordered]@{}: an OrderedDictionary
    # has an integer indexer too, and a skin id like '1064300' trips it
    # ("Argument types do not match")
    $bySkin = @{}
    $order = New-Object 'System.Collections.Generic.List[string]'
    $base = [string]$doc.skin
    if ($base) { $bySkin[$base] = @{ ops = [ordered]@{}; colorOps = [ordered]@{} }; $order.Add($base) }
    foreach ($p in @($doc.ops.PSObject.Properties)) {
        $m = $rx.Match([string]$p.Name); $s = if ($m.Success) { $m.Groups[1].Value } else { $base }
        if (-not $bySkin.ContainsKey($s)) { $bySkin[$s] = @{ ops = [ordered]@{}; colorOps = [ordered]@{} }; $order.Add($s) }
        $bySkin[$s].ops[[string]$p.Name] = $p.Value
    }
    if ($doc.PSObject.Properties['colorOps']) {
        foreach ($p in @($doc.colorOps.PSObject.Properties)) {
            $m = $rx.Match([string]$p.Name); $s = if ($m.Success) { $m.Groups[1].Value } else { $base }
            if (-not $bySkin.ContainsKey($s)) { $bySkin[$s] = @{ ops = [ordered]@{}; colorOps = [ordered]@{} }; $order.Add($s) }
            $bySkin[$s].colorOps[[string]$p.Name] = $p.Value
        }
    }
    $out = @()
    foreach ($s in $order) {
        $part = $bySkin[$s]
        if ($part.ops.Count -eq 0 -and $part.colorOps.Count -eq 0) { continue }
        $name = SS-SkinName $s
        $tag = if ($name) { $name -replace '[^A-Za-z0-9]', '' } else { $s }
        $disp = if ($name) { $name } else { $s }
        $d = [ordered]@{
            modName     = ([string]$doc.modName) + $tag
            displayName = ('{0} - {1}' -f [string]$doc.displayName, $disp)
            hero        = [string]$doc.hero
            skin        = $s
            chromaSkins = @()
            splitFrom   = [string]$doc.modName          # informational: which design this came out of
            ops         = $part.ops
            colorOps    = $part.colorOps
        }
        if ($doc.PSObject.Properties['dyeCal'] -and $doc.dyeCal) { $d['dyeCal'] = $doc.dyeCal }
        $out += , @{ skin = $s; doc = $d }
    }
    $out
}

# ---- recolour dye calibration ----------------------------------------------
# Sampling a region's average out of the ATLAS is the best a first build can do,
# but a region covers more than you can see, so the flat colour it produces is
# diluted - Jubilee's shorts came out about half as warm as the costume's. The
# only way to know the gap is to look at the game, so this measures it:
#
#   1. build with -DyeMeter: every recolor dye becomes 1,1,1, so the recolor
#      renders 1 x LIGHTING - a photograph of the light on every dyed pixel
#   2. screenshot the costume, the recolor and the meter in the same pose
#   3. SS-SolveDyeCal reads the three shots: recolor/meter is the dye actually
#      painting a pixel (which is how a pixel finds WHICH param owns it - no
#      region ids needed anywhere) and costume/meter is the albedo it should
#      have. The lighting cancels, so the scene light never has to be known.
#   4. the corrections land in the design as dyeCal and every later build
#      applies them (SS-ApplyDyeCal).
#
# The proof it works: the MEASURED dye comes back equal to the value the design
# wrote (0.433/0.315/0.264 against 0.437/0.308/0.233 on Jubilee). If those two
# disagree, the shots are misaligned or they are not the same pose - stop and
# fix that rather than trusting the numbers.

# A dye param's identity, independent of skin id and of the colour it happens to
# hold: "MI_#_Equip_01|1|ColorA". The correction belongs to the ZONE, so it
# survives re-sampling the design against new art.
function SS-DyeCalKey([string]$rel, [string]$name) {
    if ($name -notmatch '^Region (\d+) - Color(A|B|GChannel|BChannel)$') { return $null }
    $leaf = ([IO.Path]::GetFileNameWithoutExtension($rel)) -replace '\d{7}', '#'
    '{0}|{1}|{2}' -f $leaf, $Matches[1], $Matches[2]
}

# Every region dye to white: the meter build. Leaves non-dye colour edits alone.
function SS-DyeMeterDesign($doc) {
    $n = 0
    foreach ($p in $doc.colorOps.PSObject.Properties) {
        foreach ($e in $p.Value) {
            if (-not (SS-IsRegionDye ([string]$e.name))) { continue }
            $e.r = 1.0; $e.g = 1.0; $e.b = 1.0; $n++
        }
    }
    if ($doc.PSObject.Properties['dyeCal']) { $doc.PSObject.Properties.Remove('dyeCal') }   # never on a meter
    $n
}

# Multiply the stored calibration into the design's dye colours. Returns how many
# sites moved. Values are clamped to 2.0 - the vanilla dyes reach 2.0 and nothing
# sensible goes past it.
function SS-ApplyDyeCal($doc) {
    if (-not $doc.PSObject.Properties['dyeCal'] -or -not $doc.dyeCal) { return 0 }
    $cal = @{}
    foreach ($p in $doc.dyeCal.PSObject.Properties) { $cal[[string]$p.Name] = @($p.Value | ForEach-Object { [double]$_ }) }
    $fall = if ($cal.ContainsKey('*')) { $cal['*'] } else { @(1.0, 1.0, 1.0) }
    $n = 0
    foreach ($p in $doc.colorOps.PSObject.Properties) {
        foreach ($e in $p.Value) {
            $key = SS-DyeCalKey ([string]$p.Name) ([string]$e.name)
            if (-not $key) { continue }
            $k = if ($cal.ContainsKey($key)) { $cal[$key] } else { $fall }
            if ($k[0] -eq 1.0 -and $k[1] -eq 1.0 -and $k[2] -eq 1.0) { continue }
            $e.r = [Math]::Min(2.0, [double]$e.r * $k[0])
            $e.g = [Math]::Min(2.0, [double]$e.g * $k[1])
            $e.b = [Math]::Min(2.0, [double]$e.b * $k[2])
            $n++
        }
    }
    $n
}

# Solve the calibration from three screenshots and write it into the design.
# Returns @{ groups; sites; fallback; rows } - rows are printable lines.
function SS-SolveDyeCal {
    param(
        [Parameter(Mandatory)][string]$DesignPath,
        [Parameter(Mandatory)][string]$CostumeShot,
        [Parameter(Mandatory)][string]$RecolorShot,
        [Parameter(Mandatory)][string]$MeterShot,
        [scriptblock]$Progress
    )
    foreach ($f in $DesignPath, $CostumeShot, $RecolorShot, $MeterShot) {
        if (-not (Test-Path -LiteralPath $f)) { throw "not found: $f" }
    }
    $doc = Get-Content -LiteralPath $DesignPath -Raw | ConvertFrom-Json
    if (-not $doc.PSObject.Properties['colorOps']) { throw 'this design has no dye colours to calibrate' }

    # candidates = the distinct dye values the design wrote. A pixel matches the
    # nearest one, so ColorA and ColorB correct from THEIR OWN pixels (the dark
    # and light ends of a region) instead of sharing one average.
    $byVal = @{}
    foreach ($p in $doc.colorOps.PSObject.Properties) {
        foreach ($e in $p.Value) {
            $key = SS-DyeCalKey ([string]$p.Name) ([string]$e.name)
            if (-not $key) { continue }
            $vk = '{0:N3},{1:N3},{2:N3}' -f [double]$e.r, [double]$e.g, [double]$e.b
            if (-not $byVal.ContainsKey($vk)) { $byVal[$vk] = @{ r = [double]$e.r; g = [double]$e.g; b = [double]$e.b; keys = @{} } }
            $byVal[$vk].keys[$key] = $true
        }
    }
    if ($byVal.Count -eq 0) { throw 'this design has no region dye colours (nothing to calibrate)' }
    $vals = @($byVal.Keys | Sort-Object)
    if ($Progress) { & $Progress ("{0} distinct dye colour(s) to look for..." -f $vals.Count) }

    # align the other two shots to the costume on a patch of BACKGROUND - upper
    # right, away from the figure and away from the skin name (which differs)
    $sz = [SkinArt]::Size($CostumeShot)
    $rx = [int]($sz[0] * 0.55); $ry = [int]($sz[1] * 0.10)
    $rw = [int]($sz[0] * 0.40); $rh = [int]($sz[1] * 0.20)
    $aR = [SkinArt]::AlignShots($CostumeShot, $RecolorShot, $rx, $ry, $rw, $rh, 72) -split "`t"
    $aM = [SkinArt]::AlignShots($CostumeShot, $MeterShot,   $rx, $ry, $rw, $rh, 72) -split "`t"
    if ($Progress) {
        & $Progress ("aligned: recolor dx {0} dy {1} (diff {2}), meter dx {3} dy {4} (diff {5})" -f $aR[0], $aR[1], $aR[2], $aM[0], $aM[1], $aM[2])
    }

    $dr = @($vals | ForEach-Object { $byVal[$_].r })
    $dg = @($vals | ForEach-Object { $byVal[$_].g })
    $db = @($vals | ForEach-Object { $byVal[$_].b })
    $res = [SkinArt]::SolveDyeCal($CostumeShot, $RecolorShot, $MeterShot,
        [int]$aR[0], [int]$aR[1], [int]$aM[0], [int]$aM[1],
        [double[]]$dr, [double[]]$dg, [double[]]$db, 0.10, 14)

    $cal = @{}; $rows = @(); $ks = @()
    foreach ($ln in ($res -split "`n")) {
        if (-not $ln.Trim()) { continue }
        $f = $ln -split "`t"
        $i = [int]$f[0]; $px = [int]$f[1]
        if ($px -lt 200) { continue }                  # too little of it on screen to trust
        $A = @([double]$f[2], [double]$f[3], [double]$f[4])
        $D = @([double]$f[5], [double]$f[6], [double]$f[7])
        $v = $byVal[$vals[$i]]
        # the measured dye must agree with the value we wrote, or the shots do
        # not show what we think they show
        $drift = [Math]::Abs($D[0] - $v.r) + [Math]::Abs($D[1] - $v.g) + [Math]::Abs($D[2] - $v.b)
        $k = @(0, 1, 2) | ForEach-Object { [Math]::Max(0.4, [Math]::Min(3.0, $A[$_] / [Math]::Max(0.02, $D[$_]))) }
        $rows += ('  {0,7} px  dye {1:N3} {2:N3} {3:N3} -> albedo {4:N3} {5:N3} {6:N3}  (x{7:N2} {8:N2} {9:N2}){10}' -f `
            $px, $D[0], $D[1], $D[2], $A[0], $A[1], $A[2], $k[0], $k[1], $k[2], $(if ($drift -gt 0.15) { '  ** measured dye is off - check the shots' } else { '' }))
        foreach ($key in $v.keys.Keys) { $cal[$key] = @([double]$k[0], [double]$k[1], [double]$k[2]) }
        $ks += , $k
    }
    if ($ks.Count -eq 0) { throw 'no dyed pixels matched - are the three shots the same pose, and is the meter build the one installed?' }
    # zones that never showed on screen take the middle correction rather than
    # being left behind cool
    $fall = @(0, 1, 2) | ForEach-Object { $i = $_; $s = @($ks | ForEach-Object { $_[$i] } | Sort-Object); $s[[int]($s.Count / 2)] }
    $cal['*'] = @([double]$fall[0], [double]$fall[1], [double]$fall[2])

    $out = [ordered]@{}
    foreach ($k2 in ($cal.Keys | Sort-Object)) { $out[$k2] = $cal[$k2] }
    if ($doc.PSObject.Properties['dyeCal']) { $doc.PSObject.Properties.Remove('dyeCal') }
    $doc | Add-Member -NotePropertyName dyeCal -NotePropertyValue $out
    $doc | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $DesignPath -Encoding utf8
    @{ groups = $ks.Count; sites = ($cal.Count - 1); fallback = $fall; rows = $rows; align = @{ recolor = $aR; meter = $aM } }
}

# ---- which pixels belong to which dye region --------------------------------
# ★ The region lives in the _ColorID mask's ALPHA channel, in steps of 255/7:
#   A=0 undyed, 36 = region 1, 73 = 2, 109 = 3, 146 = 4, 182 = 5, 219 = 6, 255 = 7.
# Measured on Jubilee's recolors and confirmed against an in-game probe (shorts
# red = region 1, slippers green = 2, jacket blue = 3, top and leg warmers
# yellow = 4). RGB is NOT the selector: red is the gradient WITHIN a region
# (ColorA -> ColorB) and green/blue drive the ColorGChannel/ColorBChannel
# params. Slicing red into seven bands - the obvious guess - is noise.
$SS_DyeRegionStep = 255.0 / 7.0

# Per-region colours for a chroma: average the design's art over the pixels each
# region actually dyes, split by the red ramp so the region keeps its light and
# dark ends instead of going flat.
# Returns @{ <region 1..7> = @{ a = @{r;g;b}; b = @{r;g;b}; n = <pixels> } } LINEAR.
function SS-SampleDyeRegions([string]$artPng, [string]$maskPng) {
    if (-not (Test-Path -LiteralPath $artPng) -or -not $maskPng -or -not (Test-Path -LiteralPath $maskPng)) { return @{} }
    $art = $null; $mask = $null; $artS = $null; $maskS = $null
    try {
        $art = [SkinArt]::Load($artPng)
        $mask = [SkinArt]::Load($maskPng)
        # Work on 512px copies and read EVERY pixel rather than sampling a coarse
        # grid: a small region (a trim, a patch) is easy to step straight over,
        # and a region that is missed keeps the recolor's own colour in game.
        # The mask is scaled NEAREST-NEIGHBOUR - its alpha holds the region id,
        # and smoothing would invent regions that do not exist.
        $side = 512
        $maskS = New-Object System.Drawing.Bitmap $side, $side
        $g1 = [System.Drawing.Graphics]::FromImage($maskS)
        $g1.InterpolationMode = 'NearestNeighbor'; $g1.PixelOffsetMode = 'Half'
        $g1.DrawImage($mask, 0, 0, $side, $side); $g1.Dispose()
        $artS = New-Object System.Drawing.Bitmap $side, $side
        $g2 = [System.Drawing.Graphics]::FromImage($artS)
        $g2.InterpolationMode = 'HighQualityBilinear'
        $g2.DrawImage($art, 0, 0, $side, $side); $g2.Dispose()

        $acc = @{}
        for ($y = 0; $y -lt $side; $y++) {
            for ($x = 0; $x -lt $side; $x++) {
                $m = $maskS.GetPixel($x, $y)
                if ($m.A -lt ($SS_DyeRegionStep / 2)) { continue }          # undyed
                $rgn = [int][Math]::Round($m.A / $SS_DyeRegionStep)
                if ($rgn -lt 1 -or $rgn -gt 7) { continue }
                $c = $artS.GetPixel($x, $y)
                if ($c.A -lt 8) { continue }
                if (-not $acc.ContainsKey($rgn)) {
                    $acc[$rgn] = @{ lo = @(0.0, 0.0, 0.0, 0.0, 0.0); hi = @(0.0, 0.0, 0.0, 0.0, 0.0); gc = @(0.0, 0.0, 0.0, 0.0, 0.0); bc = @(0.0, 0.0, 0.0, 0.0, 0.0) }
                }
                # the red ramp is the light/dark end inside the region; the green
                # and blue channels mark sub-zones that the ColorGChannel /
                # ColorBChannel params paint (the patches on Jubilee's jacket)
                $key = if ($m.R -le 127) { 'lo' } else { 'hi' }
                $pmx = [Math]::Max($c.R, [Math]::Max($c.G, $c.B))
                $pmn = [Math]::Min($c.R, [Math]::Min($c.G, $c.B))
                $psat = if ($pmx -gt 1) { ($pmx - $pmn) / $pmx } else { 0.0 }
                $acc[$rgn][$key][0] += $c.R; $acc[$rgn][$key][1] += $c.G; $acc[$rgn][$key][2] += $c.B; $acc[$rgn][$key][3] += 1; $acc[$rgn][$key][4] += $psat
                if ($m.G -gt 8) { $acc[$rgn].gc[0] += $c.R; $acc[$rgn].gc[1] += $c.G; $acc[$rgn].gc[2] += $c.B; $acc[$rgn].gc[3] += 1; $acc[$rgn].gc[4] += $psat }
                if ($m.B -gt 8) { $acc[$rgn].bc[0] += $c.R; $acc[$rgn].bc[1] += $c.G; $acc[$rgn].bc[2] += $c.B; $acc[$rgn].bc[3] += 1; $acc[$rgn].bc[4] += $psat }
            }
        }
        # ★ NO sRGB CONVERSION HERE. A character diffuse map is LINEAR-flagged
        # (the gamma landmine in [[skin-studio-project]]), so byte/255 already IS
        # the linear value the shader samples, and the dye param is linear too.
        # Converting again landed every dyed zone ~2.5x too dark: measured in game
        # against a white-dye light meter, raw sampling predicts byte 100 and 126
        # at two points where the shots read 94 and 123; the converted value read 57.
        $mk = {
            param($s, $fallback)
            $src = if ($s[3] -ge 2) { $s } else { $fallback }
            if (-not $src -or $src[3] -lt 1) { return $null }
            $r = ($src[0] / $src[3]) / 255.0
            $g = ($src[1] / $src[3]) / 255.0
            $b = ($src[2] / $src[3]) / 255.0
            # A dyed zone renders FLAT, so it has to carry the zone's colour, not
            # the colour of its average: averaging shaded pixels pulls chroma out
            # (the mean of a lit and a shadowed brown is greyer than either).
            # Pull saturation back to the mean of the pixels', luminance held.
            $mx = [Math]::Max($r, [Math]::Max($g, $b))
            $mn = [Math]::Min($r, [Math]::Min($g, $b))
            if ($mx -gt 0.004 -and $src[4] -ge 1) {
                $s0 = ($mx - $mn) / $mx
                $s1 = $src[4] / $src[3]                      # mean per-pixel saturation
                if ($s0 -gt 0.004 -and $s1 -gt $s0) {
                    $k = [Math]::Min(1.6, $s1 / $s0)
                    $l0 = 0.2126 * $r + 0.7152 * $g + 0.0722 * $b
                    $r = $mx - ($mx - $r) * $k
                    $g = $mx - ($mx - $g) * $k
                    $b = $mx - ($mx - $b) * $k
                    $l1 = 0.2126 * $r + 0.7152 * $g + 0.0722 * $b
                    if ($l1 -gt 0.004) { $f = $l0 / $l1; $r *= $f; $g *= $f; $b *= $f }
                }
            }
            @{ r = [Math]::Min(1.0, $r); g = [Math]::Min(1.0, $g); b = [Math]::Min(1.0, $b) }
        }
        $out = @{}
        foreach ($rgn in $acc.Keys) {
            $lo = $acc[$rgn].lo; $hi = $acc[$rgn].hi
            $all = @(($lo[0] + $hi[0]), ($lo[1] + $hi[1]), ($lo[2] + $hi[2]), ($lo[3] + $hi[3]), ($lo[4] + $hi[4]))
            if ($all[3] -lt 2) { continue }
            $ca = & $mk $lo $all
            $cb = & $mk $hi $all
            if (-not $ca -or -not $cb) { continue }
            $out[$rgn] = @{
                a = $ca; b = $cb
                g = (& $mk $acc[$rgn].gc $all)
                bch = (& $mk $acc[$rgn].bc $all)
                n = $all[3]
            }
        }
        $out
    } catch { @{} } finally {
        foreach ($b in @($art, $mask, $artS, $maskS)) { if ($b) { $b.Dispose() } }
    }
}

# The colour a chroma's dye should become so the copied art reads as designed.
#
# Setting the dye WHITE does not neutralise it: the shader PAINTS the masked
# zones with these colours (the chroma's own diffuse is desaturated there -
# Viridian's outfit art is sat 0.13 against the costume's 0.31), so white washed
# the outfit out. Turning the dye off is not an option either: UseDyeing is a
# STATIC SWITCH, and flipping one on a cooked MI leaves its shader map behind -
# a material that silently stops rendering (see [[mi-shader-map-staleness]]).
#
# So the dye is told to paint the design's own colour: average the finished art
# over exactly the pixels the mask dyes (mask R > 8; G/B are always 0 in these
# masks, and the R ramp is sliced into regions by CutoutRange scalars we do not
# need to know for this). No mask -> average the whole map.
# Returns @{ r; g; b } LINEAR, or $null if it cannot be sampled.
function SS-SampleDyeColor([string]$artPng, [string]$maskPng) {
    if (-not (Test-Path -LiteralPath $artPng)) { return $null }
    $art = $null; $mask = $null
    try {
        $art = [SkinArt]::Load($artPng)
        if ($maskPng -and (Test-Path -LiteralPath $maskPng)) { $mask = [SkinArt]::Load($maskPng) }
        $steps = 96
        $sx = [Math]::Max(1, [int]($art.Width / $steps)); $sy = [Math]::Max(1, [int]($art.Height / $steps))
        $r = 0.0; $g = 0.0; $b = 0.0; $n = 0
        for ($y = 0; $y -lt $art.Height; $y += $sy) {
            for ($x = 0; $x -lt $art.Width; $x += $sx) {
                if ($mask) {
                    $mx = [int]($x * $mask.Width / $art.Width); $my = [int]($y * $mask.Height / $art.Height)
                    if ($mx -ge $mask.Width) { $mx = $mask.Width - 1 }
                    if ($my -ge $mask.Height) { $my = $mask.Height - 1 }
                    if ($mask.GetPixel($mx, $my).R -le 8) { continue }
                }
                $c = $art.GetPixel($x, $y)
                if ($c.A -lt 8) { continue }
                $r += $c.R; $g += $c.G; $b += $c.B; $n++
            }
        }
        if ($n -lt 8 -and $mask) {          # mask barely covers anything - use the map
            $mask.Dispose(); $mask = $null
            return SS-SampleDyeColor $artPng $null
        }
        if ($n -eq 0) { return $null }
        @{
            r = ($r / $n) / 255.0      # linear-flagged art: no sRGB step (see SS-SampleDyeRegions)
            g = ($g / $n) / 255.0
            b = ($b / $n) / 255.0
        }
    } catch { $null } finally {
        if ($art) { $art.Dispose() }
        if ($mask) { $mask.Dispose() }
    }
}

# Run a texture op stack over ONE colour. The colour goes through the very same
# pixel maths as the texture (a 1x1 bitmap through SkinArt), so "tint 60% to
# brown" moves a dye colour exactly as it moves a pixel. Material colours are
# LINEAR floats and SkinArt works in sRGB bytes, hence the conversions.
#   replace / edited -> the art is being swapped wholesale, so the dye goes
#   WHITE (neutral): whatever she painted is what should show.
#   gradient modes   -> a gradient has no meaning for a single colour, so the
#   primary swatch stands in for it.
# Returns @{ r; g; b } in LINEAR, or $null when the stack says nothing.
function SS-ApplyOpToColor([double]$r, [double]$g, [double]$b, $opStack) {
    $layers = @(SS-OpLayers $opStack)
    if ($layers.Count -eq 0) { return $null }
    SS-SetArtWorkers
    $toByte = { param($v) [int][Math]::Max(0, [Math]::Min(255, [Math]::Round(255 * [SkinArt]::LinearToSrgb($v)))) }
    $bmp = New-Object System.Drawing.Bitmap 1, 1
    try {
        $bmp.SetPixel(0, 0, [System.Drawing.Color]::FromArgb(255, (& $toByte $r), (& $toByte $g), (& $toByte $b)))
        foreach ($layer in $layers) {
            $mode = [string](SS-OpVal $layer 'mode' 'tint')
            if ($mode -eq 'replace' -or $mode -eq 'edited') {
                $bmp.SetPixel(0, 0, [System.Drawing.Color]::FromArgb(255, 255, 255, 255))
                continue
            }
            $use = $layer
            if ($mode -like 'grad*') {
                $use = @{}
                foreach ($k in $layer.Keys) { $use[$k] = $layer[$k] }
                $use['mode'] = if ($mode -eq 'gradpaint') { 'paint' } else { 'tint' }
            }
            $next = SS-ApplySingleBitmap $bmp $use
            if (-not [object]::ReferenceEquals($next, $bmp)) { $bmp.Dispose(); $bmp = $next }
        }
        $px = $bmp.GetPixel(0, 0)
        @{ r = [SkinArt]::SrgbToLinear($px.R / 255.0); g = [SkinArt]::SrgbToLinear($px.G / 255.0); b = [SkinArt]::SrgbToLinear($px.B / 255.0) }
    } finally { $bmp.Dispose() }
}

function SS-IsGamePatchSkin([string]$skin, [string]$kind = 'tex') {
    # NB: not [bool](SS-GamePatchIndex).skins[...] - the cast grabs the call
    # result (always $true) before the member access
    try { $gp = SS-GamePatchIndex; return ($gp.skins[$kind].ContainsKey($skin)) } catch { return $false }
}

# cache stamp for a skin: the Character utoc time, plus the patch containers'
# stamp when a patch carries that kind of asset for the skin (everything else
# keeps the old stamp, so existing caches stay valid)
function SS-SkinStamp([string]$skin, [string]$kind = 'tex') {
    $s = (Get-Item $SS_Utoc).LastWriteTimeUtc.Ticks.ToString()
    if (SS-IsGamePatchSkin $skin $kind) { $s += '|' + (SS-GamePatchIndex).stamp }
    $s
}

# extract exact manifest lines with retoc (full Paks dir, top level only)
function SS-RetocExtract($lines, [string]$destRoot, [scriptblock]$Pump) {
    if (-not (Test-Path $SS_Retoc)) { throw "retoc not found at $SS_Retoc" }
    New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
    $chunk = New-Object System.Collections.Generic.List[string]
    $flush = {
        if ($chunk.Count -eq 0) { return }
        $fArgs = @(); foreach ($ln in $chunk) { $fArgs += '-f'; $fArgs += $ln }
        $rOut = & $SS_Retoc -a $SS_GameAes to-legacy $SS_Paks $destRoot --no-shaders --no-script-objects @fArgs 2>&1
        if ($LASTEXITCODE -ne 0) { throw ("retoc to-legacy failed: " + (($rOut | Select-Object -Last 2) -join ' | ')) }
        $chunk.Clear()
    }
    foreach ($ln in $lines) { $chunk.Add(([string]$ln).Trim([char]0xFEFF).Trim()); if ($chunk.Count -ge 60) { & $flush; if ($Pump) { & $Pump } } }
    & $flush
}

# ---- manifest / texture index -----------------------------------------------
# tex_index.txt = only the T_*.uasset lines under Characters\<hero>\<skin>\,
# L10N excluded. Regenerated whenever the Character utoc is newer (new season).
# Final index = the Character-chunk base + any patch (encrypted) skins merged in.
function SS-EnsureTexIndex([scriptblock]$Progress) {
    $man = Join-Path $SS_Cache 'char_manifest.txt'
    $baseIdx = Join-Path $SS_Cache 'tex_index_base.txt'
    $idx = Join-Path $SS_Cache 'tex_index.txt'
    New-Item -ItemType Directory -Force -Path $SS_Cache | Out-Null
    $utocTime = (Get-Item $SS_Utoc).LastWriteTimeUtc
    $needMan = (-not (Test-Path $man)) -or ((Get-Item $man).LastWriteTimeUtc -lt $utocTime)
    if ($needMan) {
        if ($Progress) { & $Progress 'Reading game pak index (new season data, ~1-2 min)...' }
        $cl = '"{0}" manifest "{1}" --filters > "{2}" 2>"{3}"' -f $SS_Rr, $SS_Utoc, $man, "$SS_Cache\manifest.err"
        cmd /s /c " $cl "
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $man)) { throw "rrcli manifest failed (see cache\manifest.err)" }
    }
    if ($needMan -or -not (Test-Path $baseIdx)) {
        if ($Progress) { & $Progress 'Indexing character textures...' }
        $keep = New-Object System.Collections.Generic.List[string]
        foreach ($line in [IO.File]::ReadLines($man)) {
            $t = $line.Trim([char]0xFEFF).Trim()
            if ($t.Length -eq 0) { continue }
            if ($t.Contains('/L10N/')) { continue }
            if (-not $t.Contains('/Marvel/Characters/')) { continue }
            if (-not $t.EndsWith('.uasset')) { continue }
            $leaf = $t.Substring($t.LastIndexOf('/') + 1)
            if (-not $leaf.StartsWith('T_')) { continue }
            $keep.Add($t)
        }
        [IO.File]::WriteAllLines($baseIdx, $keep)
    }
    # merge patch (encrypted) skins - rebuilt each call (cheap); sidecars cache the decrypt
    $all = New-Object System.Collections.Generic.List[string]
    $all.AddRange([IO.File]::ReadAllLines($baseIdx))
    # merge game patch containers (new skins / new textures on existing skins)
    try {
        if ($Progress) { & $Progress 'Checking game patch containers for new skins...' }
        $gp = SS-GamePatchIndex
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($l in $all) { [void]$seen.Add($l) }
        foreach ($l in $gp.lines) {
            if (-not $l.Contains('/Marvel/Characters/')) { continue }
            if (-not $l.Substring($l.LastIndexOf('/') + 1).StartsWith('T_')) { continue }
            if ($seen.Add($l)) { $all.Add($l) }
        }
    } catch { if ($Progress) { & $Progress ("(game patch index unavailable: {0})" -f $_.Exception.Message) } }
    foreach ($k in (SS-LoadPatchSkins).Keys) {
        try { foreach ($l in (SS-PatchSkinLines $k (SS-LoadPatchSkins)[$k] $Progress)) { $all.Add($l) } }
        catch { if ($Progress) { & $Progress ("(patch skin {0} unavailable: {1})" -f $k, $_.Exception.Message) } }
    }
    # rewrite only when the index actually changed: two Skin Studio processes
    # starting together (GUI + a build, or a double launch) otherwise race on
    # this file and one dies with "being used by another process"
    $same = $false
    if (Test-Path $idx) {
        try {
            $old = [IO.File]::ReadAllLines($idx)
            if ($old.Length -eq $all.Count) {
                $same = $true
                for ($i = 0; $i -lt $old.Length; $i++) { if ($old[$i] -cne $all[$i]) { $same = $false; break } }
            }
        } catch { $same = $false }
    }
    if (-not $same) { [IO.File]::WriteAllLines($idx, $all) }
    $idx
}

# hero -> sorted skin ids; skin -> [manifest lines]. Skin folders are the
# 7-digit dirs directly under Characters\<hero>\.
function SS-LoadSkinMap([string]$idxPath) {
    $heroSkins = @{}
    $skinLines = @{}
    $rx = [regex]::new('/Characters/(\d{4})/(\d{7})/', 'Compiled')
    foreach ($line in [IO.File]::ReadLines($idxPath)) {
        $m = $rx.Match($line)
        if (-not $m.Success) { continue }
        $hero = $m.Groups[1].Value; $skin = $m.Groups[2].Value
        if (-not $skin.StartsWith($hero)) { continue }
        if (-not $heroSkins.ContainsKey($hero)) { $heroSkins[$hero] = @{} }
        $heroSkins[$hero][$skin] = $true
        if (-not $skinLines.ContainsKey($skin)) { $skinLines[$skin] = New-Object System.Collections.Generic.List[string] }
        $skinLines[$skin].Add($line)
    }
    @{ heroSkins = $heroSkins; skinLines = $skinLines }
}

# color maps (safe to recolor) vs technical maps (normals/ORM/masks - editing
# these with color ops breaks shading, locked behind the Advanced checkbox)
# D / E  = colour maps (diffuse, emissive) - what you normally recolour.
# S      = the SPECULAR texture. It is a colour map too: the materials bind it
#          to the `SpecularTexture` parameter (checked across the roster - 7 of
#          8 sampled MIs that carry an _S declare it), and it is what gives a
#          surface a *tinted* sheen. White Fox's tie reads pearlescent violet
#          because _D is near-neutral silver and _S paints a magenta rim over
#          it; the headphones are the same trick in blue. Recolouring it is
#          normal work, so it is NOT locked behind Advanced - lumping it in with
#          normals and ORM hid the only map that could answer "how do I make
#          this gold".
# anything else = technical (normals / ORM / masks); colour ops break shading,
#          so those stay behind the Advanced box.
function SS-TexRole([string]$name) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($name)
    $tok = $stem.Split('_')[-1].ToUpperInvariant()
    if ($tok -in @('D','E')) { 'color' }
    elseif ($tok -eq 'S') { 'spec' }
    else { 'tech' }
}

# ---- linked maps: the same texture shipped twice under different names ------
# Most skins are one set of textures. A lot are not: they carry two or three
# PARALLEL sets - a transformed form (Hulk / Banner / enraged Hulk all live in
# skin 1011001), a second costume state, a lobby set - and those are the same
# map under different names:
#     Textures\10600\T_10600_1060500_Equip_02_D
#     Textures\10601\T_1060500_SpiritualFox_Equip02_D
# Recolour one and the other stays vanilla, which in game reads as "it didn't
# fully change". 162 of 671 skins have at least one such pair (556 groups).
#
# The key: drop id-looking numbers, split letter/digit runs so Equip02 matches
# Equip_02, then keep the run from the first body/kit part word to the end -
# EQUIP_02_D.
$SS_PartWords = @('BODY','HEAD','FACE','SKIN','HAIR','EYE','EYES','EYESHIGHLIGHT','EYELASH','BROW',
                  'EQUIP','CLOTH','CLOTHES','TAIL','WING','WEAPON','WP','SLOT','ACC','ACCESSORY',
                  'MOUTH','TOOTH','TEETH','SCLERA','LINE','LOD2','MERGE','ARM','LEG','HAND','FOOT',
                  'CAPE','HAT','MASK','HELMET','GLOVE','BOOT','BELT','SHOE')
function SS-LinkKey([string]$stem) {
    $t = $stem
    if ($t.StartsWith('T_')) { $t = $t.Substring(2) }
    $tok = New-Object System.Collections.Generic.List[string]
    foreach ($r in ($t.Split('_') | Where-Object { $_ })) {
        foreach ($m in [regex]::Matches($r, '[A-Za-z]+|\d+')) { [void]$tok.Add($m.Value) }
    }
    $t2 = @($tok | Where-Object { -not ($_ -match '^\d{4,}$') })
    $i = -1
    for ($k = 0; $k -lt $t2.Count; $k++) { if ($SS_PartWords -contains $t2[$k].ToUpperInvariant()) { $i = $k; break } }
    if ($i -lt 0) { return $null }        # no part word we recognise - never link it
    $key = (($t2[$i..($t2.Count - 1)] | ForEach-Object { $_.ToUpperInvariant() }) -join '_')
    $pre = ''
    if ($i -gt 0) { $pre = (@($t2[0..($i - 1)] | Where-Object { $_ -match '[A-Za-z]' } | ForEach-Object { $_.ToUpperInvariant() }) -join '+') }
    @{ Key = $key; Pre = $pre }
}
# rel -> @{ Others = @(the other rels); Sure = $true/$false }. Rels are the
# thumbs.map paths (Marvel\Content\...\T_x_D.png).
#
# A matching key is NOT enough on its own. T_1011300_Grenade_Weapon_01_D and
# T_1011300_HandGun_Weapon_01_D both key to WEAPON_01_D and are two different
# props; so do Peni's T_1042001_Girl_Body_D and T_1042001_Robot_Body_D, and
# Bob's GiantUAV / MicroUAV drones. What separates them from a real pair is the
# PREFIX - the words sitting before the part name:
#
#   Sure   every member has the same prefix, so the names differ only by id
#          numbers or by folder. T_1011001_1011_Body_D / _1012_ / _1013_ (Hulk,
#          Banner, enraged Hulk) and the lobby-vs-in-match copies of one map.
#          These are the same artwork under two names, full stop.
#
#   Maybe  the prefixes differ (SpiritualFox vs none, Girl vs Robot). Sometimes
#          the same map on a second costume state, sometimes a different object
#          entirely - no rule in the filename tells them apart, so the studio
#          shows these but does not act on them unless you say so.
#
# Groups whose prefixes differ AND that share a folder are dropped outright:
# that is the Grenade/HandGun, Bow/Quiver/Sword, Device/SuperPowerAmplifier
# shape, and it is never a pair.
function SS-LinkGroups($rels) {
    $groups = @{}
    foreach ($rel in $rels) {
        $k = SS-LinkKey ([IO.Path]::GetFileNameWithoutExtension($rel))
        if (-not $k) { continue }
        if (-not $groups.ContainsKey($k.Key)) { $groups[$k.Key] = New-Object System.Collections.Generic.List[object] }
        $groups[$k.Key].Add([pscustomobject]@{ Rel = $rel; Dir = [IO.Path]::GetDirectoryName($rel); Pre = $k.Pre })
    }
    $links = @{}
    foreach ($grp in $groups.Values) {
        if ($grp.Count -lt 2) { continue }
        $dirs = @($grp | ForEach-Object { $_.Dir } | Sort-Object -Unique)
        $pres = @($grp | ForEach-Object { $_.Pre } | Sort-Object -Unique)
        $sure = ($pres.Count -le 1)
        if (-not $sure -and $dirs.Count -le 1) { continue }   # same folder, different objects
        foreach ($a in $grp) {
            $links[$a.Rel] = [pscustomobject]@{
                Others = @($grp | Where-Object { $_.Rel -ne $a.Rel } | ForEach-Object { $_.Rel })
                Sure   = $sure
            }
        }
    }
    $links
}

# ---- per-skin cache: extract vanilla assets + export PNGs + 96px thumbs ------
# Layout: cache\<skin>\src\Marvel\...  (vanilla uasset/uexp/ubulk/uptnl)
#         cache\<skin>\png\src\Marvel\...T_*.png   (ddstools export mirrors the
#         input folder leaf, so rel paths below png\src\ match those below src\)
#         cache\<skin>\thumb\<n>.png + thumbs.map (rel|thumbfile|WxH|role)
# .pakstamp holds the utoc write time - a game update invalidates the cache.
function SS-EnsureSkinCache([string]$skin, $lines, [scriptblock]$Progress, [scriptblock]$Pump) {
    $ck = Join-Path $SS_Cache $skin
    $stampFile = Join-Path $ck '.pakstamp'
    # patch (encrypted) skins are extracted from a decrypted mini paks dir and
    # stamped against their patch chunk, not the Character utoc.
    $pInfo = (SS-LoadPatchSkins)[$skin]
    if ($pInfo) {
        $pSrcUtoc = Join-Path $SS_Paks ("{0}.utoc" -f $pInfo.chunk)
        if (Test-Path $pSrcUtoc) {
            $stamp = (Get-Item $pSrcUtoc).LastWriteTimeUtc.Ticks.ToString()
        } else {
            $pInfo = $null   # patch chunk gone (skin likely baked into the base chunk) - use normal path
            $stamp = SS-SkinStamp $skin
        }
    } else {
        $stamp = SS-SkinStamp $skin
    }
    $viaRetoc = (-not $pInfo) -and (SS-IsGamePatchSkin $skin)
    if ((Test-Path "$ck\.done") -and (Test-Path $stampFile) -and ((Get-Content $stampFile -Raw).Trim() -eq $stamp)) {
        return $ck
    }
    if (Test-Path $ck) { Remove-Item $ck -Recurse -Force }
    New-Item -ItemType Directory -Force -Path "$ck\src", "$ck\png", "$ck\thumb" | Out-Null

    if ($Progress) { & $Progress ("Extracting {0} vanilla textures from the game paks..." -f $lines.Count) }
    # extraction source: normal skins use the Character utoc; patch skins use the
    # decrypted mini dir with their dynamic AES key.
    $unpUtoc = $SS_Utoc; $unpDir = $SS_Paks; $unpKey = $null
    if ($pInfo) {
        $mini = SS-EnsurePatchMini $pInfo.chunk $Progress
        $unpUtoc = $mini.utoc; $unpDir = $mini.dir; $unpKey = $pInfo.key
    }
    $chunk = New-Object System.Collections.Generic.List[string]
    $flush = {
        if ($chunk.Count -eq 0) { return }
        $fArgs = @()
        foreach ($ln in $chunk) { $fArgs += '-f'; $fArgs += $ln }
        if ($unpKey) {
            $unpOut = & $SS_Rr --aes-key $unpKey unpack $unpUtoc -o "$ck\src" @fArgs --game-paks-dir $unpDir 2>&1
        } else {
            $unpOut = & $SS_Rr unpack $unpUtoc -o "$ck\src" @fArgs --game-paks-dir $unpDir 2>&1
        }
        if ($LASTEXITCODE -ne 0) { throw ("rrcli unpack failed: " + (($unpOut | Select-Object -Last 2) -join ' | ')) }
        $chunk.Clear()
    }
    if ($viaRetoc) {
        # skin lives (at least partly) in a Patch_ container - rrcli can't read those
        SS-RetocExtract $lines "$ck\src" $Pump
    } else {
        foreach ($ln in $lines) { $chunk.Add($ln); if ($chunk.Count -ge 80) { & $flush; if ($Pump) { & $Pump } } }
        & $flush
    }
    $srcCount = @(Get-ChildItem "$ck\src" -Recurse -Filter *.uasset -ErrorAction SilentlyContinue).Count
    if ($srcCount -eq 0) { throw "extraction produced no assets for skin $skin" }

    if ($Progress) { & $Progress ("Rendering {0} textures to PNG (first open of this skin, ~1-3 min)..." -f $srcCount) }
    $expLog = Join-Path $ck 'export.log'
    $expArgs = '-E "{0}\src\main.py" "{1}" --mode export --export_as png --version 5.3 "--save_folder={2}" --skip_non_texture --max_workers={3}' -f $SS_Dds, "$ck\src", "$ck\png", (SS-Workers)
    $proc = Start-Process -FilePath "$SS_Dds\python\python.exe" -ArgumentList $expArgs `
        -RedirectStandardOutput $expLog -RedirectStandardError "$ck\export.err" `
        -WindowStyle Hidden -PassThru
    while (-not $proc.HasExited) {
        if ($Pump) { & $Pump }
        Start-Sleep -Milliseconds 250
    }
    $pngs = @(Get-ChildItem "$ck\png" -Recurse -Filter *.png -ErrorAction SilentlyContinue)
    if ($pngs.Count -eq 0) { throw "ddstools export produced no PNGs (see cache\$skin\export.log)" }

    if ($Progress) { & $Progress ("Building {0} thumbnails..." -f $pngs.Count) }
    $mapLines = New-Object System.Collections.Generic.List[string]
    $pngRoot = Join-Path $ck 'png\src'
    $sorted = @($pngs | Sort-Object FullName)
    SS-SetArtWorkers
    # parallel batches (dims ride along - no second decode per file); chunked
    # so the GUI message pump keeps breathing between batches
    $pos = 0
    while ($pos -lt $sorted.Count) {
        $take = [Math]::Min(24, $sorted.Count - $pos)
        $srcs = New-Object string[] $take
        $dsts = New-Object string[] $take
        for ($j = 0; $j -lt $take; $j++) {
            $srcs[$j] = $sorted[$pos + $j].FullName
            $dsts[$j] = Join-Path "$ck\thumb" ('{0}.png' -f ($pos + $j))
        }
        $dims = [SkinArt]::ThumbBatch($srcs, $dsts, 96)
        for ($j = 0; $j -lt $take; $j++) {
            $rel = $sorted[$pos + $j].FullName.Substring($pngRoot.Length + 1)
            $mapLines.Add(('{0}|{1}|{2}x{3}|{4}' -f $rel, $dsts[$j], $dims[2 * $j], $dims[2 * $j + 1], (SS-TexRole $sorted[$pos + $j].Name)))
        }
        $pos += $take
        if ($Pump) { & $Pump }
    }
    [IO.File]::WriteAllLines((Join-Path $ck 'thumbs.map'), $mapLines)
    Set-Content -LiteralPath $stampFile -Value $stamp -Encoding ascii
    Set-Content -LiteralPath "$ck\.done" -Value 'ok' -Encoding ascii
    $ck
}

# ---- color assets: material-instance FLinearColor params --------------------
# Beyond textures, a skin's LOOK is driven by colors baked into material
# instances (MI_): rim-light, emissive/glow, base tint, cel-shade, eyes. These
# mount from the Character chunk, so char_manifest.txt already lists them. We
# extract the vanilla MI_ uassets and run SkinColorTool (UAssetAPI + the Marvel
# usmap) to read every named FLinearColor, caching colors.json:
#   [ { asset: "Marvel/.../MI_x.uasset", class, colors:[{export,ordinal,name,
#       r,g,b,a}] } ]  - values are LINEAR (convert with SkinArt.SrgbToLinear).
# Load+re-serialize round-trips Rivals assets byte-identical, so a color edit
# changes only the touched floats (verified: 8 bytes for one channel pair).
# Niagara particle colors (NS_) are the same shape - added in a later phase.
$SS_ColorTool = Join-Path $SS_Root 'colortool\bin\Release\net8.0\SkinColorTool.exe'

# manifest line (../../../Marvel/...) -> extract-root-relative path (Marvel/...)
function SS-ManifestRel([string]$line) {
    ($line.Trim([char]0xFEFF).Trim()) -replace '^(\.\./)+', ''
}

# skin -> [manifest lines] for its color assets. kind 'mat' = MI_ instances under
# Characters\<hero>\<skin>\Materials\ ; 'fx' = NS_ niagara under the VFX subtree.
function SS-LoadColorMap([string]$skin, [string]$kind = 'mat') {
    $man = Join-Path $SS_Cache 'char_manifest.txt'
    if (-not (Test-Path $man)) { throw 'char_manifest.txt missing - build the texture index first (SS-EnsureTexIndex)' }
    $hero = $skin.Substring(0, 4)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($raw in [IO.File]::ReadLines($man)) {
        $t = $raw.Trim([char]0xFEFF).Trim()
        if ($t.Length -eq 0 -or -not $t.EndsWith('.uasset')) { continue }
        $leaf = $t.Substring($t.LastIndexOf('/') + 1)
        if ($kind -eq 'mat') {
            # anywhere under the skin, not just .../<skin>/Materials/ - a skin's
            # props keep their materials beside them (White Fox's
            # Weapons\Tail\Materials\MI_1060500_SixFoxTails_01, the MVP laptop),
            # and the old filter left those out of the Materials list entirely
            # and out of the Blender bridge's binding map.
            if (-not $t.Contains("/Characters/$hero/$skin/")) { continue }
            if (-not $leaf.StartsWith('MI_')) { continue }
        } else {
            if (-not $t.Contains("/Particles/Characters/$hero/$skin/")) { continue }
            if (-not $leaf.StartsWith('NS_')) { continue }
        }
        $lines.Add($t)
    }
    # plus the skin's materials / particle systems from game patch containers
    if (SS-IsGamePatchSkin $skin $kind) {
        $have = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($l in $lines) { [void]$have.Add($l) }
        foreach ($t in (SS-GamePatchIndex).lines) {
            $leaf = $t.Substring($t.LastIndexOf('/') + 1)
            if ($kind -eq 'mat') {
                if (-not $t.Contains("/Characters/$hero/$skin/") -or -not $leaf.StartsWith('MI_')) { continue }
            } else {
                if (-not $t.Contains("/Particles/Characters/$hero/$skin/") -or -not $leaf.StartsWith('NS_')) { continue }
            }
            if ($have.Add($t)) { $lines.Add($t) }
        }
    }
    $lines
}

# unpack a set of color assets (manifest lines) into $destRoot via rrcli. Returns
# the list of extracted uasset full paths that actually landed. Dependency
# closure rides along (rrcli pulls it); callers pass only the assets they want
# dumped/patched, so the extra deps are ignored.
function SS-UnpackColorAssets($lines, [string]$destRoot, [scriptblock]$Pump) {
    New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
    $chunk = New-Object System.Collections.Generic.List[string]
    $flush = {
        if ($chunk.Count -eq 0) { return }
        $fArgs = @(); foreach ($ln in $chunk) { $fArgs += '-f'; $fArgs += $ln }
        $out = & $SS_Rr unpack $SS_Utoc -o $destRoot @fArgs --game-paks-dir $SS_Paks 2>&1
        if ($LASTEXITCODE -ne 0) { throw ('rrcli unpack (colors) failed: ' + (($out | Select-Object -Last 2) -join ' | ')) }
        $chunk.Clear()
    }
    # any line living in a game patch container -> rrcli would abort; use retoc
    $gpSet = $null
    try { $gpSet = (SS-GamePatchIndex).set } catch {}
    $viaRetoc = $false
    if ($gpSet) { foreach ($ln in $lines) { if ($gpSet.Contains(([string]$ln).Trim())) { $viaRetoc = $true; break } } }
    if ($viaRetoc) {
        SS-RetocExtract $lines $destRoot $Pump
    } else {
        foreach ($ln in $lines) { $chunk.Add($ln); if ($chunk.Count -ge 60) { & $flush; if ($Pump) { & $Pump } } }
        & $flush
    }
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($ln in $lines) {
        $rel = SS-ManifestRel $ln
        $p = Join-Path $destRoot ($rel -replace '/', '\')
        if (Test-Path -LiteralPath $p) { $paths.Add($p) }
    }
    $paths
}

# per-skin color cache: extract the color assets, dump named colors -> json
# (asset ids relative to the extract root), then drop the bulky extraction. A
# game update (utoc write time) invalidates it, same as the texture cache.
#   kind 'mat' -> MI_ materials      -> colors.json    (.colorstamp)
#   kind 'fx'  -> NS_ niagara systems -> colors_fx.json (.fxcolorstamp)
function SS-EnsureColorCache([string]$skin, [scriptblock]$Progress, [scriptblock]$Pump, [string]$kind = 'mat') {
    $ck = Join-Path $SS_Cache $skin
    $jsonName = if ($kind -eq 'fx') { 'colors_fx.json' } else { 'colors.json' }
    $stampName = if ($kind -eq 'fx') { '.fxcolorstamp' } else { '.colorstamp' }
    $noun = if ($kind -eq 'fx') { 'particle systems' } else { 'material instances' }
    $colorsJson = Join-Path $ck $jsonName
    $stampFile = Join-Path $ck $stampName
    # the 'm2' suffix bumps this cache when the material SCAN changes, not just
    # when the game updates - the widened filter in SS-LoadColorMap must not be
    # served a stale list built by the old one
    $stamp = (SS-SkinStamp $skin $kind) + 'm2'
    if ((Test-Path $colorsJson) -and (Test-Path $stampFile) -and ((Get-Content $stampFile -Raw).Trim() -eq $stamp)) {
        return $colorsJson
    }
    if (-not (Test-Path $SS_ColorTool)) { throw "SkinColorTool not built - run 'dotnet build -c Release' in $SS_Root\colortool" }
    New-Item -ItemType Directory -Force -Path $ck | Out-Null
    $lines = SS-LoadColorMap $skin $kind
    if ($lines.Count -eq 0) {
        [IO.File]::WriteAllText($colorsJson, '[]')
        Set-Content -LiteralPath $stampFile -Value $stamp -Encoding ascii
        return $colorsJson
    }
    $csrc = Join-Path $ck ("colorsrc_" + $kind)
    if (Test-Path $csrc) { Remove-Item $csrc -Recurse -Force }
    if ($Progress) { & $Progress ("Extracting {0} {1} for color editing..." -f $lines.Count, $noun) }
    $paths = SS-UnpackColorAssets $lines $csrc $Pump
    if ($paths.Count -eq 0) { throw "no $noun extracted for skin $skin" }
    if ($Progress) { & $Progress ("Reading colors from {0} {1}..." -f $paths.Count, $noun) }
    $listFile = Join-Path $ck ("color_assets_" + $kind + ".txt")
    [IO.File]::WriteAllLines($listFile, $paths)
    # strip everything up to & including the extract dir so asset ids are stable rels
    $strip = "colorsrc_$kind"
    # no 2>&1: piping a native exe's stderr under ErrorActionPreference=Stop wraps
    # each line as a terminating NativeCommandError. Tool prints progress to stdout.
    & $SS_ColorTool dump $SS_Usmap $colorsJson $strip "@$listFile" | ForEach-Object { if ($Progress) { & $Progress ("  $_") } }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $colorsJson)) { throw "SkinColorTool dump failed for skin $skin (exit $LASTEXITCODE)" }
    Remove-Item $csrc -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $listFile -Force -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $stampFile -Value $stamp -Encoding ascii
    $colorsJson
}

# ---- "what paints this?" ----------------------------------------------------
# Reading an atlas by eye to work out which texture covers a part of the model
# is guesswork, and it was wrong twice on White Fox before the mesh settled it.
# These two caches make the real answer cheap.

# material -> the textures it binds, straight out of the MI packages. A UE
# package's name table carries every referenced object, so the T_* names in an
# MI ARE its texture parameters. Cached per skin against the pak stamp.
function SS-EnsureMatTextures([string]$skin, [scriptblock]$Progress) {
    $ck = Join-Path $SS_Cache $skin
    $outJson = Join-Path $ck 'mat_textures.json'
    $stampFile = Join-Path $ck '.mattexstamp'
    # same 'm2' bump as the colour cache - both are built from SS-LoadColorMap
    $stamp = (SS-SkinStamp $skin 'mat') + 'm2'
    if ((Test-Path $outJson) -and (Test-Path $stampFile) -and ((Get-Content $stampFile -Raw).Trim() -eq $stamp)) {
        return $outJson
    }
    New-Item -ItemType Directory -Force -Path $ck | Out-Null
    $lines = SS-LoadColorMap $skin 'mat'
    if ($lines.Count -eq 0) {
        [IO.File]::WriteAllText($outJson, '{}')
        Set-Content -LiteralPath $stampFile -Value $stamp -Encoding ascii
        return $outJson
    }
    if ($Progress) { & $Progress ("Reading {0} material(s) for texture bindings..." -f $lines.Count) }
    $tmp = Join-Path $ck 'mattexsrc'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    [void](SS-UnpackColorAssets $lines $tmp $null)
    $map = @{}
    foreach ($f in (Get-ChildItem $tmp -Recurse -Filter *.uasset -ErrorAction SilentlyContinue)) {
        $bytes = [IO.File]::ReadAllBytes($f.FullName)
        $cur = New-Object System.Text.StringBuilder
        $names = New-Object System.Collections.Generic.List[string]
        foreach ($b in $bytes) {
            if ($b -ge 32 -and $b -lt 127) { [void]$cur.Append([char]$b) }
            else { if ($cur.Length -ge 3) { [void]$names.Add($cur.ToString()) }; [void]$cur.Clear() }
        }
        if ($cur.Length -ge 3) { [void]$names.Add($cur.ToString()) }
        $tex = @($names | Where-Object { $_ -cmatch '^T_' -and $_ -notmatch '[/\\]' } | Sort-Object -Unique)
        $parent = @($names | Where-Object { $_ -cmatch '^M_' -and $_ -notmatch '[/\\]' } | Select-Object -First 1)
        # the mesh names materials without the chunk prefix too, so key on the
        # leaf and let the GUI match either form
        $map[$f.BaseName] = @{ textures = $tex; parent = ([string]$parent) }
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    [IO.File]::WriteAllText($outJson, ($map | ConvertTo-Json -Depth 5))
    Set-Content -LiteralPath $stampFile -Value $stamp -Encoding ascii
    $outJson
}

# the two render passes (see blender\paintid.py). Keyed on the MESH file, not
# the pak stamp - it is the mesh that decides the answer, and re-exporting one
# is a manual FModel trip.
function SS-EnsurePaintId([string]$skin, [string]$gltf, [scriptblock]$Progress) {
    if (-not (Test-Path -LiteralPath $gltf)) { throw "no mesh export for this skin" }
    if (-not (Test-Path -LiteralPath $SS_Blender)) { throw "Blender not found at $SS_Blender" }
    $dir = Join-Path (Join-Path $SS_Cache $skin) 'paintid'
    $stampFile = Join-Path $dir '.meshstamp'
    $stamp = (Get-Item -LiteralPath $gltf).LastWriteTimeUtc.Ticks.ToString()
    $need = $true
    if ((Test-Path $stampFile) -and ((Get-Content $stampFile -Raw).Trim() -eq $stamp)) {
        $need = $false
        foreach ($f in 'legend.json', 'id-front.png', 'id-back.png', 'uv-front.png', 'uv-back.png') {
            if (-not (Test-Path (Join-Path $dir $f))) { $need = $true }
        }
    }
    if (-not $need) { return $dir }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    if ($Progress) { & $Progress 'Rendering the model to trace materials (one-off per mesh, ~30s)...' }
    $py = Join-Path $SS_Root 'blender\paintid.py'
    $log = Join-Path $dir 'paintid.log'
    # -b headless; no 2>&1 redirect of the native exe under ErrorActionPreference
    # Stop (it wraps stderr lines as terminating errors)
    $cl = '"{0}" -b --python "{1}" -- "{2}" "{3}" > "{4}"' -f $SS_Blender, $py, $gltf, $dir, $log
    cmd /s /c " $cl "
    foreach ($f in 'legend.json', 'id-front.png', 'uv-front.png') {
        if (-not (Test-Path (Join-Path $dir $f))) { throw "the model render produced no $f (see cache\$skin\paintid\paintid.log)" }
    }
    Set-Content -LiteralPath $stampFile -Value $stamp -Encoding ascii
    $dir
}

# ops arrive as GUI hashtables OR ConvertFrom-Json PSCustomObjects - read both.
function SS-OpVal($op, [string]$name, $default) {
    if ($op -is [hashtable]) {
        if ($op.ContainsKey($name)) { return $op[$name] }
        return $default
    }
    $prop = $op.PSObject.Properties[$name]
    if ($prop) { return $prop.Value }
    $default
}

# A texture's op is a LAYER STACK. Canonical form: array of layer hashtables,
# applied top of file = first. Legacy designs stored a single op object - wrap it.
function SS-OpLayers($op) {
    if ($null -eq $op) { return @() }
    if (($op -is [System.Collections.IList]) -and -not ($op -is [string])) { return @($op) }
    $inner = SS-OpVal $op 'layers' $null
    if ($inner) { return @($inner) }
    @($op)
}

function SS-ApplySingleBitmap($bmp, $op) {
    # in-memory layer application; returns the result Bitmap (same object
    # mutated, or a NEW one for replace/edited - caller handles disposal)
    $mode = [string](SS-OpVal $op 'mode' 'tint')
    if ($mode -eq 'edited') { $mode = 'replace' }
    [SkinArt]::ApplyBitmap($bmp, $mode,
        [string](SS-OpVal $op 'color' '#FFFFFF'),
        [double](SS-OpVal $op 'strength' 1.0),
        [double](SS-OpVal $op 'hueShift' 0.0),
        [double](SS-OpVal $op 'satMul' 1.0),
        [double](SS-OpVal $op 'lightMul' 1.0),
        [string](SS-OpVal $op 'file' ''),
        [bool](SS-OpVal $op 'protectSkin' $false),
        [string](SS-OpVal $op 'color2' ''),
        [string](SS-OpVal $op 'color3' ''),
        [string](SS-OpVal $op 'color4' ''),
        [string](SS-OpVal $op 'gradDir' 'v'),
        # "Recolor color family": which hue family to move. -1 = auto-detect the
        # dominant one (right for a single-subject texture, wrong for a shared
        # atlas); 0 width = the 34-degree default half-band.
        [double](SS-OpVal $op 'bandCenter' -1.0),
        [double](SS-OpVal $op 'bandWidth' 0.0))
}

# render a whole stack in memory: vanilla src -> layer 1 -> ... -> Bitmap.
# No intermediate PNG encodes; the caller disposes the returned bitmap.
function SS-RenderStack([string]$srcPng, $op) {
    # @() - a one-layer stack unrolls to the bare hashtable, whose .Count is its
    # number of settings, not 1
    $layers = @(SS-OpLayers $op)
    if ($layers.Count -eq 0) { throw "empty op stack for $srcPng" }
    SS-SetArtWorkers
    $bmp = [SkinArt]::Load($srcPng)
    try {
        foreach ($layer in $layers) {
            $next = SS-ApplySingleBitmap $bmp $layer
            if (-not [object]::ReferenceEquals($next, $bmp)) { $bmp.Dispose(); $bmp = $next }
        }
    } catch { $bmp.Dispose(); throw }
    $bmp
}

# apply a whole stack to a file: single decode, single gamma-faithful save
# (SavePngLike copies the VANILLA source's color chunks - the Luna gamma guard).
function SS-ApplyOp([string]$srcPng, [string]$dstPng, $op) {
    $bmp = SS-RenderStack $srcPng $op
    try { [SkinArt]::SavePngLike($bmp, $dstPng, $srcPng) }
    finally { $bmp.Dispose() }
}

# short human label for a layer ("tint #E6EDEE 95% +skin", "hue +40", ...)
function SS-OpLabel($op) {
    $mode = [string](SS-OpVal $op 'mode' '?')
    $pct = [int](100 * [double](SS-OpVal $op 'strength' 1.0))
    switch ($mode) {
        'tint'     { $txt = 'tint {0} {1}%' -f (SS-OpVal $op 'color' '?'), $pct }
        'paint'    { $txt = 'paint {0} {1}%' -f (SS-OpVal $op 'color' '?'), $pct }
        'hueshift' { $txt = 'hue {0:+0;-0}° {1}%' -f [double](SS-OpVal $op 'hueShift' 0), $pct }
        'huerange' { $txt = 'recolor family → {0} {1}%' -f (SS-OpVal $op 'color' '?'), $pct }
        'hsl'      { $txt = 'hsl h{0:+0;-0} s×{1:0.##} l×{2:0.##} {3}%' -f [double](SS-OpVal $op 'hueShift' 0), [double](SS-OpVal $op 'satMul' 1), [double](SS-OpVal $op 'lightMul' 1), $pct }
        'gray'     { $txt = 'grayscale {0}%' -f $pct }
        'invert'   { $txt = 'invert {0}%' -f $pct }
        'gradtint'  { $txt = 'grad-tint {0}→{1} {2} {3}%' -f (SS-OpVal $op 'color' '?'), (SS-OpVal $op 'color2' '?'), (SS-OpVal $op 'gradDir' 'v'), $pct }
        'gradpaint' { $txt = 'grad-paint {0}→{1} {2} {3}%' -f (SS-OpVal $op 'color' '?'), (SS-OpVal $op 'color2' '?'), (SS-OpVal $op 'gradDir' 'v'), $pct }
        'replace'  { $txt = 'image: {0} {1}%' -f (Split-Path ([string](SS-OpVal $op 'file' '?')) -Leaf), $pct }
        'edited'   { $txt = 'hand-edited PNG' }
        default    { $txt = $mode }
    }
    if ([bool](SS-OpVal $op 'protectSkin' $false)) { $txt += ' ·skin-safe' }
    $txt
}

# livepak.ps1 - the in-game Build mod button's refresh: Project Galacta's method.
#
# Dot-sourced by panel_server.ps1 (so it runs inside the LIVE PREVIEW watcher).
#
# A pak mounted before the game loads an asset overrides it; once the asset is
# loaded, the engine keeps it cached by name and a pak mounted over it changes
# nothing on screen. Galacta gets live changes the only way that works: it
# mounts a pak WHILE THE GAME RUNS (NePatchUtility.MountPak, the game's own
# patch-system function) and loads assets from paths nothing has loaded yet,
# then puts them on the hero. So after a build this:
#
#   1. takes the textures the build staged (the real cooked mod textures),
#   2. renames each package in place, at equal length, from
#        /Game/Marvel/Characters/1020/1020309/Textures/T_x   to
#        /Game/Marvel/SLB0007/rs/1020/1020309/Textures/T_x
#      - the first Len(prefix) characters after the root swapped for
#        "SL<tag>/", so nothing in the file moves (the path is stored twice in
#        the header: FolderName and the name map) and the export data, mips and
#        bulk data stay byte-identical (proved 2026-09-26: packed, unpacked,
#        .uexp and .ubulk identical to the build's). A fresh tag per build means
#        a fresh package every time, never one the game has cached,
#   3. packs them with rrcli into <Content>\SkinStudioLive\paks\SkinLive<tag>_9999999_P.*
#   4. writes <Content>\SkinStudioLive\_pak.txt:
#        <pak, relative to Content>|<order>|<prefix>|T_a|T_b|...|
#      ("||||" = nothing mounted). In game, MountLive mounts the pak; the walk's
#      TrySwap loads each listed texture from  prefix + RightChop(vanilla path,
#      Len(prefix))  and falls back to the PNG preview when it will not load.
#
# The list only carries textures whose built pixels match what the live preview
# shows. They differ where a material colour edit is baked into the preview's
# D but lives in the MI in a build (BaseTint, say): the in-game MI is still
# vanilla this session, so the built D alone would drop that edit. Those keep
# the PNG. A texture the preview edits later drops off the list (Pnl-FlagLeaves).
#
# Keep this file ASCII: PS 5.1 reads a BOM-less script as Windows-1252.

$script:LP = @{
    Order = 1000
    Rr = $SS_Rr
    Log = $null          # scriptblock(msg)
}

function LP-Log([string]$m) { if ($script:LP.Log) { & $script:LP.Log $m } else { Write-Host ('[{0}] livepak: {1}' -f (Get-Date -Format HH:mm:ss), $m) } }

function LP-Dir([string]$liveDir) { Join-Path $liveDir 'paks' }
function LP-ManifestPath([string]$liveDir) { Join-Path $liveDir '_pak.txt' }

# the manifest: @{ Pak; Order; Prefix; Leaves (ordered list) } - empty fields when none
function LP-ReadManifest([string]$liveDir) {
    $m = @{ Pak = ''; Order = ''; Prefix = ''; Leaves = (New-Object System.Collections.ArrayList) }
    $p = LP-ManifestPath $liveDir
    if (-not (Test-Path -LiteralPath $p)) { return $m }
    $f = ([IO.File]::ReadAllText($p)).Trim() -split '\|'
    if ($f.Count -ge 3) { $m.Pak = $f[0]; $m.Order = $f[1]; $m.Prefix = $f[2] }
    for ($i = 3; $i -lt $f.Count; $i++) { if ($f[$i]) { [void]$m.Leaves.Add($f[$i]) } }
    $m
}

function LP-WriteManifest([string]$liveDir, $m) {
    New-Item -ItemType Directory -Force -Path $liveDir | Out-Null
    $txt = '||||'
    if ($m -and $m.Pak -and $m.Prefix) {
        # leading and trailing | so the game's Contains(|T_x|) needs no special case
        $txt = '{0}|{1}|{2}|{3}|' -f $m.Pak, $m.Order, $m.Prefix, ((@($m.Leaves) | Where-Object { $_ }) -join '|')
    }
    $p = LP-ManifestPath $liveDir
    $tmp = $p + '.tmp'
    [IO.File]::WriteAllText($tmp, $txt, (New-Object System.Text.UTF8Encoding($false)))
    for ($i = 0; $i -lt 40; $i++) {
        try { if (Test-Path -LiteralPath $p) { [IO.File]::Delete($p) }; [IO.File]::Move($tmp, $p); return } catch { Start-Sleep -Milliseconds 10 }
    }
    LP-Log 'could not replace _pak.txt (game reading it?) - left the old one'
}

function LP-Clear([string]$liveDir) { LP-WriteManifest $liveDir $null }

# textures the live preview just repainted or reverted: the PNG is newer than
# the build now, so the game must take the PNG for them
function LP-DropLeaves([string]$liveDir, [string[]]$leaves) {
    $m = LP-ReadManifest $liveDir
    if (-not $m.Pak -or $m.Leaves.Count -eq 0) { return 0 }
    $n = 0
    foreach ($lf in @($leaves)) {
        $name = [IO.Path]::GetFileNameWithoutExtension([string]$lf)
        if ($m.Leaves.Contains($name)) { $m.Leaves.Remove($name); $n++ }
    }
    if ($n -gt 0) { LP-WriteManifest $liveDir $m }
    $n
}

# the next build tag, B0001..B9999, never reused (a reused tag in the same game
# session would hit the cache and show the OLD build)
function LP-NextTag([string]$workDir) {
    $f = Join-Path $workDir 'livepak_counter.txt'
    $n = 0
    if (Test-Path -LiteralPath $f) { [void][int]::TryParse(([IO.File]::ReadAllText($f)).Trim(), [ref]$n) }
    $n = ($n % 9999) + 1
    [IO.File]::WriteAllText($f, [string]$n)
    'B{0:D4}' -f $n
}

# in-place, equal-length rename of one staged texture package; returns the
# new package path or '' (skipped, with the reason logged)
function LP-RenameTexture([string]$srcAsset, [string]$prefix, [string]$stageRoot) {
    $leaf = [IO.Path]::GetFileNameWithoutExtension($srcAsset)
    $b = [IO.File]::ReadAllBytes($srcAsset)
    $enc = [Text.Encoding]::ASCII
    $txt = $enc.GetString($b)
    $m = [regex]::Match($txt, '/Game/Marvel/[^\x00]*/' + [regex]::Escape($leaf) + '\x00')
    if (-not $m.Success) { LP-Log "  skip $leaf - no package path in its header"; return '' }
    $old = $m.Value.TrimEnd([char]0)
    # the first Len(prefix) characters are replaced; they must all sit in the
    # folder (never the leaf), and must not end right before a '/' ('//')
    if ($old.LastIndexOf('/') -lt $prefix.Length -or $old[$prefix.Length] -eq '/') { LP-Log "  skip $leaf - its folder is too short to rename in place"; return '' }
    $new = $prefix + $old.Substring($prefix.Length)
    $ob = $enc.GetBytes($old + [char]0); $nb = $enc.GetBytes($new + [char]0)
    $hits = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -le $b.Length - $ob.Length; $i++) {
        if ($b[$i] -ne $ob[0]) { continue }
        $ok = $true
        for ($k = 1; $k -lt $ob.Length; $k++) { if ($b[$i + $k] -ne $ob[$k]) { $ok = $false; break } }
        if ($ok) { $hits.Add($i) }
    }
    # FolderName + the name map entry; anything else means a layout we have not seen
    if ($hits.Count -ne 2) { LP-Log ("  skip {0} - its path appears {1} time(s), expected 2" -f $leaf, $hits.Count); return '' }
    foreach ($h in $hits) { [Array]::Copy($nb, 0, $b, $h, $nb.Length) }
    $folder = $new.Substring(6, $new.LastIndexOf('/') - 6) -replace '/', '\'     # /Game/X -> Marvel\Content\X
    $dst = Join-Path $stageRoot ('Marvel\Content\' + $folder)
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $dst ($leaf + '.uasset')), $b)
    foreach ($ext in 'uexp', 'ubulk') {
        $f = [IO.Path]::ChangeExtension($srcAsset, $ext)
        if (Test-Path -LiteralPath $f) { Copy-Item -LiteralPath $f -Destination $dst -Force }
    }
    $new
}

# Does the built texture show what the live preview shows? (see the header)
function LP-MatchesPreview([string]$liveDir, [string]$leaf, [string]$builtPng) {
    $live = Join-Path $liveDir ($leaf + '.png')
    if (-not (Test-Path -LiteralPath $live)) { return $true }          # nothing live for it: the build is the news
    if (-not $builtPng -or -not (Test-Path -LiteralPath $builtPng)) { return $false }
    try { return ([SkinArt]::AvgLumDiff($live, $builtPng, 64) -lt 1.5) } catch { return $false }
}

# Pack the textures of the given built mods into a fresh live pak.
# Returns @{ Ok; Tag; Pak (relative to Content); Prefix; Leaves; Skipped; Note }
function LP-Build([string[]]$mods, [string]$liveDir) {
    $res = @{ Ok = $false; Tag = ''; Pak = ''; Prefix = ''; Leaves = @(); Skipped = @(); Note = '' }
    $work = Join-Path $SS_Root 'work\ingame'
    $tag = LP-NextTag $work
    $prefix = '/Game/Marvel/SL' + $tag + '/'
    $name = 'SkinLive' + $tag
    $root = Join-Path $work 'livepak'
    $stage = Join-Path $root ('stage\' + $name)
    $out = Join-Path $root 'out'
    foreach ($d in @((Join-Path $root 'stage'), $out)) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force } }
    New-Item -ItemType Directory -Force -Path $stage, $out | Out-Null
    $leaves = New-Object System.Collections.ArrayList
    foreach ($mod in @($mods)) {
        $modStage = Join-Path $SS_Root ('work\{0}\stage\{0}' -f $mod)
        $modPng = Join-Path $SS_Root ('work\{0}\png' -f $mod)
        if (-not (Test-Path -LiteralPath $modStage)) { LP-Log "  $mod has no staged files"; continue }
        foreach ($ua in @(Get-ChildItem -LiteralPath $modStage -Recurse -File -Filter 'T_*.uasset')) {
            $leaf = $ua.BaseName
            if ($leaves.Contains($leaf)) { continue }
            # the PNG the build injected sits at the same rel under work\<mod>\png
            $rel = $ua.FullName.Substring($modStage.Length).TrimStart('\')       # Marvel\Content\Marvel\...\T_x.uasset
            $builtPng = Join-Path $modPng ([IO.Path]::ChangeExtension($rel, 'png'))
            if (-not (LP-MatchesPreview $liveDir $leaf ([string]$builtPng))) {
                $res.Skipped += $leaf
                LP-Log "  $leaf keeps the live preview (its material colours are baked there, not in the texture)"
                continue
            }
            $np = LP-RenameTexture $ua.FullName $prefix $stage
            if ($np) { [void]$leaves.Add($leaf) }
        }
    }
    if ($leaves.Count -eq 0) { $res.Note = 'no textures to load live'; return $res }
    $log = Join-Path $root 'pack.log'
    $cl = '"{0}" pack "{1}" --output "{2}" --game-paks-dir "{3}" --obfuscate > "{4}" 2>&1' -f $script:LP.Rr, $stage, $out, $SS_Paks, $log
    cmd /s /c " $cl "
    $utoc = @(Get-ChildItem -LiteralPath $out -Filter '*.utoc' -File -ErrorAction SilentlyContinue)[0]
    $ucas = @(Get-ChildItem -LiteralPath $out -Filter '*.ucas' -File -ErrorAction SilentlyContinue)[0]
    $pak = @(Get-ChildItem -LiteralPath $out -Filter '*.pak' -File -ErrorAction SilentlyContinue)[0]
    if (-not $utoc -or -not $ucas -or -not $pak) { $res.Note = 'the live pak did not pack (work\ingame\livepak\pack.log)'; return $res }
    # the package names are what the game will ask for - read them back
    $man = (& $script:LP.Rr manifest $utoc.FullName 2>$null) -join "`n"
    $names = @([regex]::Matches($man, '"packagename"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    $bad = @($names | Where-Object { -not $_.StartsWith($prefix) })
    if ($names.Count -ne $leaves.Count -or $bad.Count) { $res.Note = ('the live pak holds {0} package(s) for {1} texture(s), {2} under the wrong name' -f $names.Count, $leaves.Count, $bad.Count); return $res }
    $dir = LP-Dir $liveDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    foreach ($f in @($pak, $utoc, $ucas)) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dir $f.Name) -Force }
    $res.Ok = $true; $res.Tag = $tag; $res.Prefix = $prefix; $res.Leaves = @($leaves)
    $res.Pak = 'SkinStudioLive/paks/' + $pak.Name
    LP-Log ('live pak {0}: {1} texture(s), {2:N1} MB' -f $pak.BaseName, $leaves.Count, ($ucas.Length / 1MB))
    $res
}

# Old live paks: a pak mounted in a running game is locked, and a game restart
# unmounts every one of them, so anything we can delete is unused.
function LP-Sweep([string]$liveDir, [string]$keepPak) {
    $dir = LP-Dir $liveDir
    if (-not (Test-Path -LiteralPath $dir)) { return 0 }
    $keep = if ($keepPak) { [IO.Path]::GetFileNameWithoutExtension($keepPak) } else { '' }
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
        if ($keep -and $f.BaseName -eq $keep) { continue }
        try { [IO.File]::Delete($f.FullName); $n++ } catch {}
    }
    $n
}

# live_preview.ps1 - Skin Studio live preview: a design json becomes PNGs that
# the in-game menu re-imports on a keypress. No pak, no repack, no restart.
#
#   .\live_preview.ps1 -Design designs\MyMod.json            one shot
#   .\live_preview.ps1 -Design designs\MyMod.json -Watch      re-export on save
#   .\live_preview.ps1 -WatchDesigns                          follow whichever
#                                                             design you save
#   .\live_preview.ps1 -Clear                                 back to vanilla
#   .\live_preview.ps1 -Purge                                 empty the folder
#
# ---- why -Clear WRITES files instead of deleting them -----------------------
# Deleting a PNG cannot undo a preview in a running game. A null import IS the
# "not edited" test (below), so once a texture has been swapped into the MID,
# a missing file just means the chain skips that slot and the edited texture
# stays on screen. The only in-game undo is to hand the game the VANILLA pixels
# and let it import those - so -Clear re-writes each live texture from its
# cached vanilla PNG, through the same gamma pre-compensation as an edit. Then
# one refresh in game really is back to vanilla. -Purge is the old behaviour,
# for cleaning the game folder out when you are done.
#
# Protocol - deliberately just filenames. One PNG per edited texture, named
# after the VANILLA texture asset (T_1031001_Body_D.png). In game we walk the
# character's material slots, read each slot's BaseColor / Normal / ORM texture
# parameter, take that texture's object name, and look for a file of that name
# here. So there is no manifest to keep in sync and nothing to parse in
# Blueprint: ImportFileAsTexture2D returning null IS the "not edited" test.
#
# Runs standalone, own work dir, safe alongside a build or Theme Studio.
param(
    [string]$Design,
    [switch]$Watch,
    [switch]$WatchDesigns,
    [switch]$Clear,
    [switch]$Purge,
    # auto = per texture, from the vanilla map's own SRGB flag (see Get-LiveGamma);
    # srgb / linear / none force one mode on every map (tests only)
    [ValidateSet('auto', 'srgb', 'linear', 'none')][string]$Gamma = 'auto',
    [string]$LiveDir,
    [string]$DesignDir,
    [int]$MaxWorkers = 0,
    # the in-game editor (ingame\panel_server.ps1) rides on the watch loop.
    # -SaveDir / -FrameOut exist for tests; -NoPanel turns it off.
    [string]$SaveDir,
    [string]$FrameOut,
    [switch]$NoPanel,
    # LIVE PREVIEW on/off (ingame\livestate.ps1): -WatchDesigns follows
    # work\live_preview.on, which the app's button and the in-game one both flip.
    # -LiveFlag points a test at its own file; a test folder (-SaveDir) without
    # one is always on. -ExitWithGame: the in-game helper's watcher, which ends
    # when Rivals does.
    [string]$LiveFlag,
    [switch]$ExitWithGame
)
$ErrorActionPreference = 'Stop'
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}
. "$PSScriptRoot\ingame\livestate.ps1"
. "$PSScriptRoot\skinlib.ps1"
Add-Type -Path "$PSScriptRoot\SkinArt.cs" -ReferencedAssemblies System.Drawing
if ($MaxWorkers -gt 0) { $script:SS_ArtWorkersFixed = $MaxWorkers }
# the 3D preview's verified dye rules (ViewArt.DyeComposite) and its material
# colour readers (SS-ViewMatColors / SS-ViewDyeBlock) - reused, not rewritten,
# for baking material colour edits into the F6 PNGs. Only function definitions
# and one Add-Type run here; the window code stays unused.
. "$PSScriptRoot\viewlib.ps1"
# "your texture edits win over the dye" (her call 2026-09-24): the plan and
# the bake are shared with build_skin.ps1 so the preview and a real mod agree
. "$PSScriptRoot\dyebake.ps1"

# <game>\Marvel\Content\SkinStudioLive - next to Paks, reachable in Blueprint as
# ProjectContentDir() + "SkinStudioLive/", and writable without admin.
if (-not $LiveDir) { $LiveDir = Join-Path (Split-Path $SS_Paks -Parent) 'SkinStudioLive' }

function LLog($msg) { Write-Host ('[{0}] {1}' -f (Get-Date -Format HH:mm:ss), $msg) }

$LiveList = Join-Path $LiveDir '_live.txt'
# the in-game Build mod button's list of textures the game loads out of the
# built mod instead of these PNGs (ingame\livepak.ps1). Going back to vanilla
# must empty it, or F6 would put the built textures back on.
$PakList = Join-Path $LiveDir '_pak.txt'
function Reset-PakList { if (Test-Path -LiteralPath $PakList) { [IO.File]::WriteAllText($PakList, '||||') } }

# _live.txt is OUR bookkeeping only - the Blueprint never reads it (the protocol
# is filenames, nothing more), so it is free to carry what a revert needs:
# leaf|skin|rel|vanilla-png-path. The vanilla path is stored outright so -Clear
# needs no manifest, no tex index and no skin cache rebuild to undo a preview.
function Read-LiveList {
    $out = @{ gamma = ''; state = ''; design = ''; entries = @() }
    if (-not (Test-Path -LiteralPath $LiveList)) { return $out }
    foreach ($line in @(Get-Content -LiteralPath $LiveList)) {
        if ($line -match '^#\s*gamma\s*:\s*(\S+)')  { $out.gamma  = $Matches[1]; continue }
        if ($line -match '^#\s*state\s*:\s*(\S+)')  { $out.state  = $Matches[1]; continue }
        if ($line -match '^#\s*design\s*:\s*(.+)$') { $out.design = $Matches[1].Trim(); continue }
        if ($line -match '^\s*(#|$)') { continue }
        $f = $line -split '\|'
        # older runs wrote bare filenames; keep reading them, just without a
        # vanilla source to restore from
        if ($f.Count -ge 4) {
            # column 5 is new: a file already sitting at vanilla does not need
            # restoring again, so a cold process can skip it
            $st = if ($f.Count -ge 5 -and $f[4]) { $f[4] } else { 'live' }
            $out.entries += @{ leaf = $f[0]; skin = $f[1]; rel = $f[2]; src = $f[3]; st = $st }
        } else {
            $out.entries += @{ leaf = $f[0]; skin = ''; rel = ''; src = ''; st = 'live' }
        }
    }
    $out
}

function Write-LiveList([string]$designPath, [string]$state, $entries) {
    $lines = @('# Skin Studio live preview', "# design : $designPath",
        "# gamma  : $Gamma", "# state  : $state",
        "# written: $(Get-Date -Format s)", '',
        '# leaf|skin|rel|vanilla png|live or vanilla')
    foreach ($e in @($entries | Sort-Object { $_.leaf })) {
        $st = if ($e.st) { $e.st } else { 'live' }
        $lines += ('{0}|{1}|{2}|{3}|{4}' -f $e.leaf, $e.skin, $e.rel, $e.src, $st)
    }
    [IO.File]::WriteAllLines($LiveList, $lines)
}

# last resort for a leaf with no recorded source - a manifest from before this
# format, or a stray file. The skin id is in the texture name itself, and the
# cache is cache\<skin>\png\src\<rel>, so the vanilla pixels are findable from
# the filename alone.
# ★ Match the 7-digit id ANYWHERE in the name, not after a leading "T_": weapon
# and prop maps are "T_WP_1064300_Balloon_D.png", and an anchored pattern missed
# every one of them - which meant deleting them instead of reverting them.
# The digit guards stop a longer number matching its first seven.
function Find-VanillaPng([string]$leaf) {
    if ($leaf -notmatch '(?<!\d)(\d{7})(?!\d)') { return '' }
    $srcRoot = Join-Path $SS_Cache (Join-Path $Matches[1] 'png\src')
    if (-not (Test-Path -LiteralPath $srcRoot)) { return '' }
    $hit = @(Get-ChildItem -LiteralPath $srcRoot -Filter $leaf -File -Recurse -ErrorAction SilentlyContinue)
    if ($hit.Count -eq 1) { return $hit[0].FullName }
    ''
}

# ---- which maps need a gamma pre-comp (2026-09-24) ---------------------------
# ImportFileAsTexture2D always makes an sRGB-flagged texture (ImageUtils.cpp
# CreateTexture2DFromImage never sets SRGB, UTexture's default is true) and
# copies the PNG bytes unchanged. A vanilla map flagged the same way - every
# D, S, AO, AN and M map stores no SRGB property, i.e. the default, true - must
# get its bytes UNCHANGED: exactly what a built mod injects. Only a map stored
# with SRGB=false (ColorID, N, ORM, MRO, FM) needs the lin->sRGB encode, so the
# import's decode lands back on its values. The old blanket 'srgb' rested on
# "D maps are linear-flagged" - a reading of ddstools' BC1_UNORM label, not of
# the asset - and it washed out every live D and S (her report 2026-09-24).
$SrgbCacheFile = Join-Path $SS_Root 'work\ingame\srgb_flags.json'
$script:SrgbFlags = @{}
if (Test-Path -LiteralPath $SrgbCacheFile) {
    try { foreach ($p in (Get-Content -LiteralPath $SrgbCacheFile -Raw | ConvertFrom-Json).PSObject.Properties) { $script:SrgbFlags[$p.Name] = [bool]$p.Value } } catch {}
}
function Get-LiveUsmap {
    $cfg = Join-Path $env:LOCALAPPDATA 'Atelier\mr_config.json'
    try { $u = [string](Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).usmap; if ($u -and (Test-Path -LiteralPath $u)) { return $u } } catch {}
    $SS_Usmap
}
# $true = the vanilla texture is sRGB-flagged. Read once per texture from the
# cached vanilla uasset (UAssetTool + usmap), then remembered in srgb_flags.json;
# the suffix rule is the fallback when the asset or the tool is missing.
function Get-TexIsSrgb([string]$leaf) {
    $name = [IO.Path]::GetFileNameWithoutExtension($leaf)
    if ($script:SrgbFlags.ContainsKey($name)) { return $script:SrgbFlags[$name] }
    $byName = -not ($name -match '_(ColorID|N|ORM|MRO|FM)$')
    $flag = $byName
    $uat = Join-Path $env:LOCALAPPDATA 'Atelier\Tools\UAssetTool.exe'
    $asset = $null
    if ($name -match '(?<!\d)(\d{7})(?!\d)') {
        $srcRoot = Join-Path $SS_Cache (Join-Path $Matches[1] 'src')
        if (Test-Path -LiteralPath $srcRoot) { $asset = @(Get-ChildItem -LiteralPath $srcRoot -Filter ($name + '.uasset') -File -Recurse -ErrorAction SilentlyContinue)[0] }
    }
    if ($asset -and (Test-Path -LiteralPath $uat)) {
        $tmp = Join-Path $SS_Root 'work\ingame\_srgb'
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $null = & $uat to_json $asset.FullName (Get-LiveUsmap) $tmp 2>&1 } finally { $ErrorActionPreference = $eap }
        $jf = Join-Path $tmp ($name + '.json')
        if (Test-Path -LiteralPath $jf) {
            $flag = -not ([IO.File]::ReadAllText($jf) -match '"Name":\s*"SRGB"[\s\S]{0,300}?"Value":\s*false')
            Remove-Item -LiteralPath $jf -Force
        }
    }
    $script:SrgbFlags[$name] = $flag
    try { [IO.File]::WriteAllText($SrgbCacheFile, ($script:SrgbFlags | ConvertTo-Json)) } catch {}
    if ($flag -ne $byName) { LLog ("  note: {0} is {1} although its suffix says otherwise" -f $name, $(if ($flag) { 'sRGB' } else { 'linear' })) }
    $flag
}
function Get-LiveGamma([string]$leaf) {
    if ($Gamma -ne 'auto') { return $Gamma }
    if (Get-TexIsSrgb $leaf) { 'none' } else { 'srgb' }
}

# hand the game the vanilla pixels so its next import really is an undo
function Restore-Vanilla($entry) {
    $dst = Join-Path $LiveDir $entry.leaf
    if (-not $entry.src -or -not (Test-Path -LiteralPath $entry.src)) {
        $found = Find-VanillaPng $entry.leaf
        if ($found) { $entry.src = $found }
    }
    if (-not $entry.src -or -not (Test-Path -LiteralPath $entry.src)) {
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
        LLog ('  {0}  <- no cached vanilla PNG, deleted instead (restart the game to undo it)' -f $entry.leaf)
        return $false
    }
    $bmp = [SkinArt]::Load($entry.src)
    try { [SkinArt]::SaveLivePng($bmp, $dst, (Get-LiveGamma $entry.leaf)) } finally { $bmp.Dispose() }
    $true
}

if ($Purge) {
    if (Test-Path -LiteralPath $LiveDir) {
        Get-ChildItem -LiteralPath $LiveDir -Filter *.png -File | Remove-Item -Force
        if (Test-Path -LiteralPath $LiveList) { Remove-Item -LiteralPath $LiveList -Force }
        Reset-PakList
        LLog "purged $LiveDir - NOTE: this does not undo a preview already showing in game, restart Rivals for that"
    } else {
        LLog "nothing to purge ($LiveDir does not exist)"
    }
    return
}

if ($Clear) {
    Reset-PakList
    $live = Read-LiveList
    if ($live.entries.Count -eq 0) { LLog "nothing live to clear ($LiveDir)"; return }
    # vanilla is restored per texture (auto) whatever the preview was written
    # with - an old blanket 'srgb' restore would put back WASHED-OUT vanilla
    if ($live.state -eq 'reverted' -and $live.gamma -eq $Gamma) { LLog 'already reverted - refresh in game if you have not yet'; return }
    $ok = 0
    foreach ($e in @($live.entries)) {
        if ($e.st -eq 'vanilla' -and $live.gamma -eq $Gamma) { $ok++; continue }
        if (Restore-Vanilla $e) { $e.st = 'vanilla'; $ok++ }
    }
    Write-LiveList $live.design 'reverted' $live.entries
    LLog ('{0} texture(s) restored to vanilla (gamma {1}) - REFRESH IN GAME to see it' -f $ok, $Gamma)
    return
}

if ($WatchDesigns) {
    if (-not $DesignDir) { $DesignDir = Join-Path $SS_Root 'designs' }
    if (-not (Test-Path -LiteralPath $DesignDir)) { throw "no designs folder: $DesignDir" }
} elseif (-not $Design) {
    throw 'give me -Design <design json>, or -WatchDesigns, or -Clear'
}

# LIVE PREVIEW on or off. Off = the hero wears the game's own skin: nothing is
# rendered, and the in-game panel shows only its "Turn on live preview" screen.
$script:LiveFlagPath = ''
if ($WatchDesigns -and -not $NoPanel) {
    $script:LiveFlagPath = if ($LiveFlag) { $LiveFlag } elseif (-not $SaveDir) { $script:LS_Flag } else { '' }
}
$script:LiveOn = (-not $script:LiveFlagPath) -or (LS-FlagOn $script:LiveFlagPath)
# one watcher per save folder: the app's and the in-game helper's never both run
if (($Watch -or $WatchDesigns) -and -not $NoPanel) {
    $script:WatcherMutex = LS-TakeWatcherMutex $SaveDir
    if (-not $script:WatcherMutex) { LLog 'another Skin Studio watcher is already running - this one stops'; return }
}
# newest design json in the folder - -WatchDesigns' idea of "the one you are
# working on", which is what makes switching variants a matter of saving one
function Newest-Design {
    $j = @(Get-ChildItem -LiteralPath $DesignDir -Filter *.json -File -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTimeUtc -Descending)
    if ($j.Count -eq 0) { return '' }
    $j[0].FullName
}

if ($WatchDesigns) {
    $Design = Newest-Design
    if (-not $Design -and $script:LiveOn) { throw "no design json in $DesignDir yet - save one in Skin Studio first" }
    LLog ('following {0} - newest design there wins' -f $DesignDir)
} else {
    if (-not [IO.Path]::IsPathRooted($Design)) { $Design = Join-Path $SS_Root $Design }
    if (-not (Test-Path -LiteralPath $Design)) { throw "no such design: $Design" }
}
New-Item -ItemType Directory -Force -Path $LiveDir | Out-Null

# op rels carry their own skin id, exactly as in build_skin.ps1 - a design may
# edit the costume AND its chromas, and each needs its own vanilla cache.
$rxOpSkin = [regex]'[\\/]Characters[\\/]\d{4}[\\/](\d{7})[\\/]'
# what we last wrote, rel -> op signature, so a -Watch pass only redoes the
# textures that actually changed
$lastSig = @{}
# leaf -> @{leaf skin rel src}: every texture this folder has ever had live,
# seeded from _live.txt so a fresh process can still undo the last session's
# preview. An op dropped from the design needs its vanilla source long after it
# has stopped appearing in the design, which is the whole reason this persists.
$known = @{}
# leaves currently sitting at vanilla, so neither a -Watch pass nor a cold start
# re-renders them - the manifest's 5th column is what makes that survive restarts
$vanillaLeaf = @{}
$prevLive = Read-LiveList
# PNGs written under another gamma mode (the old blanket 'srgb' washed every D
# out) are all rewritten once: none counts as already vanilla
$regamma = ($prevLive.gamma -and $prevLive.gamma -ne $Gamma)
if ($regamma -and $prevLive.entries.Count) { LLog ("live PNGs were written with gamma '{0}' - rewriting them all as '{1}'" -f $prevLive.gamma, $Gamma) }
foreach ($e in @($prevLive.entries)) {
    if (-not $e.leaf) { continue }
    $known[$e.leaf] = $e
    if ($e.st -eq 'vanilla' -and -not $regamma) { $vanillaLeaf[$e.leaf] = $true }
}

# ---- material colour edits and dyed maps -------------------------------------
# Blueprint cannot read numbers from a file, so colour edits to a MATERIAL are
# BAKED into the D this watcher writes, and a dyed material's mask
# (DyeingTexture, T_x_ColorID) gets a blank one - alpha 0 = undyed, proven in
# game 2026-09-24 - which the in-game Walk swaps like any other map. The same
# happens for a dyed material whose D the design edits: her edits go ON TOP of
# the baked dye, so what she paints is what shows. SS-DyePlans / SS-RenderDyeBake
# in dyebake.ps1 (shared with build_skin.ps1). Undo is the ordinary stale sweep:
# both leaves are recorded with their vanilla sources, so dropping the edits
# writes the vanilla D and the vanilla mask back (never deletes them).

# Writes every leaf it painted or reverted to the pipeline, so the in-game panel
# can flag exactly those for the game to re-import. Call sites that only want
# the side effect discard it ($null = Export-Live ...).
function Export-Live([string]$designPath) {
    $dj = Get-Content -LiteralPath $designPath -Raw | ConvertFrom-Json
    $skin = [string]$dj.skin
    $opProps = @()
    if ($dj.ops) { $opProps = @($dj.ops.PSObject.Properties) }
    # no early return on an empty design: clearing the last edit in game must
    # still reach the stale sweep below, or that texture stays edited on screen
    $hasColor = ($dj.PSObject.Properties['colorOps'] -and $dj.colorOps -and @($dj.colorOps.PSObject.Properties).Count -gt 0)
    if ($opProps.Count -eq 0 -and -not $hasColor) { LLog 'design has no texture or colour edits - reverting anything still live' }
    $changedLeaves = New-Object System.Collections.Generic.List[string]

    $idx = SS-EnsureTexIndex { param($m) LLog $m }
    $map = SS-LoadSkinMap $idx

    # plain hashtable, NOT [ordered]@{}: an OrderedDictionary's integer indexer
    # wins for numeric-looking keys like "1064300" (build_skin.ps1 hit this)
    $opsBySkin = @{}
    foreach ($prop in $opProps) {
        $m = $rxOpSkin.Match($prop.Name)
        $sid = if ($m.Success) { $m.Groups[1].Value } else { $skin }
        if (-not $opsBySkin.ContainsKey($sid)) { $opsBySkin[$sid] = @() }
        $opsBySkin[$sid] += $prop
    }

    # dyed maps and material colour edits: these D maps are written by the bake
    # below instead (dyebake.ps1)
    $bakes = SS-DyePlans $dj $map $true { param($m) LLog $m }

    $written = 0; $skipped = 0; $seen = @{}
    foreach ($sid in @($opsBySkin.Keys | Sort-Object)) {
        if (-not $map.skinLines.ContainsKey($sid)) { LLog "  WARN: skin $sid is not in the current game data - skipped"; continue }
        $cacheDir = SS-EnsureSkinCache $sid $map.skinLines[$sid] { param($m) LLog $m } $null
        $pngRoot = Join-Path $cacheDir 'png\src'
        foreach ($prop in @($opsBySkin[$sid])) {
            $rel = $prop.Name
            $srcPng = Join-Path $pngRoot $rel
            if (-not (Test-Path -LiteralPath $srcPng)) { LLog "  WARN: no cached PNG for '$rel' - skipped"; continue }
            # the asset name is the whole protocol
            $leaf = Split-Path $rel -Leaf
            if ($bakes.ContainsKey($leaf)) { continue }      # baked with its material's colours below
            $dstPng = Join-Path $LiveDir $leaf
            $seen[$leaf] = $true
            $known[$leaf] = @{ leaf = $leaf; skin = $sid; rel = $rel; src = $srcPng; st = 'live' }
            $vanillaLeaf.Remove($leaf)
            # signature covers the op stack, the gamma mode, and - for 'replace'
            # / 'edited' layers - the mtime of the image they point at
            $lg = Get-LiveGamma $leaf
            $sig = ($prop.Value | ConvertTo-Json -Depth 12 -Compress) + '|' + $lg
            foreach ($layer in @(SS-OpLayers $prop.Value)) {
                $ext = [string](SS-OpVal $layer 'file' '')
                if ($ext -and (Test-Path -LiteralPath $ext)) { $sig += '|' + (Get-Item -LiteralPath $ext).LastWriteTimeUtc.Ticks }
            }
            if ($lastSig[$leaf] -eq $sig -and (Test-Path -LiteralPath $dstPng)) { $skipped++; continue }

            $bmp = SS-RenderStack $srcPng $prop.Value
            try { [SkinArt]::SaveLivePng($bmp, $dstPng, $lg) } finally { $bmp.Dispose() }
            $lastSig[$leaf] = $sig
            $written++
            $changedLeaves.Add($leaf)
            LLog ('  {0}  <- {1}' -f $leaf, ((SS-OpLayers $prop.Value | ForEach-Object { SS-OpLabel $_ }) -join ' + '))
        }
    }

    foreach ($bk in @($bakes.Values)) {
        foreach ($t in @(@($bk.dLeaf, $bk.dRel, $bk.dSrc), @($bk.mLeaf, $bk.mRel, $bk.mSrc))) {
            if (-not $t[0]) { continue }
            $seen[$t[0]] = $true
            $known[$t[0]] = @{ leaf = $t[0]; skin = $bk.skin; rel = $t[1]; src = $t[2]; st = 'live' }
            $vanillaLeaf.Remove($t[0])
        }
        $dDst = Join-Path $LiveDir $bk.dLeaf
        $mDst = if ($bk.mLeaf) { Join-Path $LiveDir $bk.mLeaf } else { '' }
        $lg = Get-LiveGamma $bk.dLeaf
        # 'ontop' marks the edits-over-dye order, so a watcher restart re-renders
        # anything an older order wrote
        $sig = @('ontop',
            $(if ($bk.op) { $bk.op | ConvertTo-Json -Depth 12 -Compress } else { '-' }),
            $(if ($bk.block) { $bk.block -join ',' } else { '-' }),
            $(if ($bk.ratio) { $bk.ratio -join ',' } else { '-' }),
            $lg, (Get-Item -LiteralPath $bk.dSrc).LastWriteTimeUtc.Ticks) -join '|'
        if ($bk.op) {
            foreach ($layer in @(SS-OpLayers $bk.op)) {
                $ext = [string](SS-OpVal $layer 'file' '')
                if ($ext -and (Test-Path -LiteralPath $ext)) { $sig += '|' + (Get-Item -LiteralPath $ext).LastWriteTimeUtc.Ticks }
            }
        }
        if ($lastSig[$bk.dLeaf] -eq $sig -and (Test-Path -LiteralPath $dDst) -and (-not $mDst -or (Test-Path -LiteralPath $mDst))) { $skipped++; continue }
        $bmp = SS-RenderDyeBake $bk
        try { [SkinArt]::SaveLivePng($bmp, $dDst, $lg) } finally { $bmp.Dispose() }
        $lastSig[$bk.dLeaf] = $sig
        $written++
        $changedLeaves.Add($bk.dLeaf)
        LLog ('  {0}  <- {1}' -f $bk.dLeaf, (SS-DyePlanLabel $bk))
        if ($mDst) {
            [LiveBake]::BlankMask($mDst, 64)
            $changedLeaves.Add($bk.mLeaf)
            LLog ('  {0}  <- blank dye mask (the bake shows instead)' -f $bk.mLeaf)
        }
    }

    # An op removed from the design - or a texture the previous design edited and
    # this one does not - must go back to VANILLA PIXELS, not to a missing file.
    # Deleting it would leave the edit on screen in game for the rest of the
    # session (a null import is the "not edited" test, so the chain just skips
    # that slot and keeps what the MID already holds).
    $reverted = 0
    # '_' files are not textures: _panel.png is the in-game editor's own frame,
    # and treating it as a stale texture deleted it out from under the game
    foreach ($stale in @(Get-LiveFiles)) {
        $leaf = $stale.Name
        if ($seen.ContainsKey($leaf)) { continue }
        if ($vanillaLeaf.ContainsKey($leaf)) { continue }   # already vanilla, leave it
        if (Revert-LiveLeaf $leaf) {
            $reverted++
            $changedLeaves.Add($leaf)
            LLog ('  {0}  <- back to vanilla' -f $leaf)
        }
    }

    Write-LiveEntries $designPath 'live'
    $tail = if ($reverted) { ', {0} back to vanilla' -f $reverted } else { '' }
    LLog ('{0} texture(s) live, {1} unchanged{2}  ->  {3}' -f $written, $skipped, $tail, $LiveDir)
    foreach ($l in $changedLeaves) { $l }
}

# the texture PNGs in the live folder ('_' files are not textures: _panel.png
# is the in-game editor's own frame)
function Get-LiveFiles { @(Get-ChildItem -LiteralPath $LiveDir -Filter *.png -File | Where-Object { -not $_.Name.StartsWith('_') }) }

# one texture back to VANILLA PIXELS, in the watcher's books too; $false = no
# vanilla source, so the file was deleted instead
function Revert-LiveLeaf([string]$leaf) {
    $e = if ($known.ContainsKey($leaf)) { $known[$leaf] } else { @{ leaf = $leaf; skin = ''; rel = ''; src = ''; st = 'live' } }
    $lastSig.Remove($leaf)
    if (Restore-Vanilla $e) {
        $e.st = 'vanilla'
        $known[$leaf] = $e
        $vanillaLeaf[$leaf] = $true
        return $true
    }
    $known.Remove($leaf)
    $false
}

# every leaf the folder still holds, with its vanilla source, so -Clear can
# undo the lot from a cold process
function Write-LiveEntries([string]$designPath, [string]$state) {
    $entries = @()
    foreach ($f in @(Get-LiveFiles)) {
        $entries += if ($known.ContainsKey($f.Name)) { $known[$f.Name] } else { @{ leaf = $f.Name; skin = ''; rel = ''; src = ''; st = 'live' } }
    }
    Write-LiveList $designPath $state $entries
}

# LIVE PREVIEW off while watching: every texture still live goes back to
# vanilla pixels (what -Clear does from a cold process) and is returned, so the
# game can re-import them now - no F6 needed.
function Revert-AllLive {
    $leaves = New-Object System.Collections.Generic.List[string]
    foreach ($f in @(Get-LiveFiles)) {
        if ($vanillaLeaf.ContainsKey($f.Name)) { continue }
        if (Revert-LiveLeaf $f.Name) { $leaves.Add($f.Name) }
    }
    $lastSig.Clear()
    Reset-PakList
    Write-LiveEntries ([string]$script:Design) 'reverted'
    foreach ($l in $leaves) { $l }
}

# The one door every render goes through while watching: a desktop save, an
# in-game panel edit, or the panel switching designs. Keeps the watch loop's
# bookkeeping in step (so a design the panel just saved is not rendered twice)
# and flags whatever changed for the game to re-import.
$script:watchLastPath = ''
$script:watchLast = [long]0
$script:panelOn = $false
function Update-Live([string]$designPath) {
    # live preview off: remember the design, paint nothing (turning it on
    # renders whatever is newest then)
    if (-not $script:LiveOn) { if ($designPath) { $script:Design = $designPath }; return }
    if ($designPath -ne $script:watchLastPath -and $script:watchLastPath) {
        LLog ('switched to {0}' -f (Split-Path $designPath -Leaf))
        # a different design edits a different set of textures; whatever the
        # old one owned and this one does not gets reverted by the stale sweep
        $lastSig.Clear()
    }
    $script:Design = $designPath
    $script:watchLastPath = $designPath
    $script:watchLast = (Get-Item -LiteralPath $designPath).LastWriteTimeUtc.Ticks
    $changed = @(Export-Live $designPath)
    if ($script:panelOn) {
        if ($changed.Count -gt 0) { Pnl-FlagLeaves $changed }
        $script:Pnl.Dirty = $true
    }
    foreach ($l in $changed) { $l }
}

# LIVE PREVIEW on / off while watching - the in-game button, or the flag file
# flipped by the app. On: the newest design goes onto the hero, and the game is
# told Skin Studio listens again (it re-announces the hero, so the design picked
# for that skin paints it). Off: every live texture back to vanilla, re-imported
# by the game at once. Either way the flag file follows, so the app agrees.
function Set-LiveMode([bool]$on, [string]$why) {
    if ($on -eq $script:LiveOn) { return }
    $script:LiveOn = $on
    if ($script:LiveFlagPath) { LS-SetFlag $on $script:LiveFlagPath }
    if ($script:panelOn) { $script:Pnl.LiveOn = $on }
    if ($on) {
        LLog ('live preview ON ({0})' -f $why)
        $d = if ($WatchDesigns) { Newest-Design } else { $script:Design }
        if ($d) { $script:watchLastPath = ''; $null = Update-Live $d } else { LLog 'no design saved yet - nothing to paint' }
        if ($script:panelOn) { Pnl-LiveChanged $true }
    } else {
        LLog ('live preview OFF ({0})' -f $why)
        $leaves = @(Revert-AllLive)
        LLog ('{0} texture(s) back to vanilla' -f $leaves.Count)
        if ($script:panelOn) {
            if ($leaves.Count) { Pnl-FlagLeaves $leaves }
            Pnl-LiveChanged $false
        }
    }
}

if (($Watch -or $WatchDesigns) -and -not $NoPanel) {
    . "$PSScriptRoot\ingame\panel_server.ps1"
    if (-not $DesignDir) { $DesignDir = Join-Path $SS_Root 'designs' }
    $script:Pnl.LiveOn = $script:LiveOn
    $script:Pnl.LiveSet = { param([bool]$on, [string]$why) Set-LiveMode $on $why }
    Pnl-Init $SaveDir $LiveDir $DesignDir $FrameOut
    $script:panelOn = $true
}

if ($script:LiveOn) { $null = Update-Live $Design } else { LLog 'live preview is OFF - nothing painted; the in-game panel (F8) can turn it on' }

if ($Watch -or $WatchDesigns) {
    if ($WatchDesigns) {
        LLog 'watching every design - save any of them in Skin Studio and that one goes live. Ctrl+C to stop.'
    } else {
        LLog 'watching the design - save in Skin Studio, then refresh in game. Ctrl+C to stop.'
    }
    if ($script:panelOn) { LLog 'in-game editor ready - press F8 in a match' }
    if ($ExitWithGame) { LLog 'started for the game - stops when Rivals closes' }
    # The in-game panel wants answers in tens of milliseconds, the design check
    # is fine at 600: one loop, the panel inbox every tick, designs every 20th.
    $tick = 0
    $gameGone = 0
    while ($true) {
        Start-Sleep -Milliseconds 30
        if ($script:panelOn) {
            try { $null = Pnl-Poll } catch { LLog ('panel ERROR: ' + $_.Exception.Message) }
        }
        $tick++
        if ($tick % 20 -ne 0) { continue }
        # the app's LIVE PREVIEW button flips the flag file
        if ($script:LiveFlagPath) {
            $flagOn = LS-FlagOn $script:LiveFlagPath
            if ($flagOn -ne $script:LiveOn) { try { Set-LiveMode $flagOn 'Skin Studio app' } catch { LLog ('ERROR switching live preview: ' + $_.Exception.Message) } }
        }
        # the helper's watcher ends with the game (two checks in a row, ~5 s)
        if ($ExitWithGame -and $tick % 80 -eq 0) {
            if (LS-GameUp) { $gameGone = 0 } else { $gameGone++ }
            if ($gameGone -ge 2) {
                if ($script:panelOn) { Pnl-Unflag 'SkinLiveOn' }
                LLog 'Rivals closed - the watcher stops'
                break
            }
        }
        if (-not $script:LiveOn) { continue }
        # in -WatchDesigns the target itself can move: saving a different design
        # makes it the newest, which IS how you switch variants
        $want = $script:Design
        if ($WatchDesigns) {
            $want = Newest-Design
            if (-not $want) { continue }
        }
        if (-not (Test-Path -LiteralPath $want)) { continue }
        $now = (Get-Item -LiteralPath $want).LastWriteTimeUtc.Ticks
        if ($now -eq $script:watchLast -and $want -eq $script:watchLastPath) { continue }
        Start-Sleep -Milliseconds 250      # let the writer finish
        try { $null = Update-Live $want } catch { LLog ('ERROR: ' + $_.Exception.Message) }
    }
}

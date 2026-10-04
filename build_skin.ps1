# build_skin.ps1 - headless Skin Studio build: design json -> installed mod.
#   .\build_skin.ps1 -Design designs\MyMod.json [-Install] [-Zip] [-Version 1-0] [-Combined]
# A design that covers a costume AND its recolours always builds as one mod per
# skin (her standing rule, 2026-09-22). -Combined is the one exception, for the
# calibration meter - a throwaway measuring build, not a mod anyone keeps.
# Runs standalone (GUI shells out to it in its own window). Own work dir -
# no overlap with Theme Studio's build\, safe to run alongside it.
param(
    [Parameter(Mandatory)][string]$Design,
    [switch]$Install,
    [switch]$Zip,
    [switch]$DyeMeter,        # build the LIGHT METER: every recolor dye white
    [switch]$PerSkin,         # accepted for old callers - one mod per skin is now ALWAYS the rule
    [switch]$Combined,        # the one exception: build a costume + recolours as ONE mod (the meter)
    [string]$Version = '1-0',
    [int]$MaxWorkers = 0
)
$ErrorActionPreference = 'Stop'
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}
. "$PSScriptRoot\skinlib.ps1"
Add-Type -Path "$PSScriptRoot\SkinArt.cs" -ReferencedAssemblies System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
# "your texture edits win over the dye" (her call 2026-09-24): the same plan and
# bake the F6 live preview uses, so a mod looks like its preview
. "$PSScriptRoot\viewlib.ps1"
. "$PSScriptRoot\dyebake.ps1"
# Rivals running with Project Galacta: the new build is swapped in through its
# F7 unload / reload instead of waiting for a restart (galacta.ps1)
. "$PSScriptRoot\galacta.ps1"
# pin SkinArt's parallel pixel engine to the same cap as ddstools inject
if ($MaxWorkers -gt 0) { $script:SS_ArtWorkersFixed = $MaxWorkers }
# test seams for the install step: RS_SS_MODSDIR (where it installs) and
# RS_SS_GAMEPROC (a stand-in for the game's process)
$SS_ModsDir = if ($env:RS_SS_MODSDIR) { $env:RS_SS_MODSDIR } else { Join-Path $SS_Paks '~mods' }
# where the "press Galacta's F7" request for the in-game mod goes (RS_SS_SAVEDIR: tests)
$SS_SaveDir = if ($env:RS_SS_SAVEDIR) { $env:RS_SS_SAVEDIR } else { Join-Path $env:LOCALAPPDATA 'Marvel\Saved\SaveGames' }
function Test-GameUp { (SS-GamePids $env:RS_SS_GAMEPROC).Count -gt 0 }
function Test-GalactaSwap { $Install -and (Test-GameUp) -and (SS-GalactaInfo (SS-GalactaPaksDir $SS_ModsDir)).Installed }

$sw = [Diagnostics.Stopwatch]::StartNew()
$dj = Get-Content -LiteralPath $Design -Raw | ConvertFrom-Json

# One mod per skin, always (unless -Combined). Each piece is written to
# work\_split\ (not designs\, so they stay out of the Designs list) and built by
# a normal run of this script, so a split build is exactly N ordinary builds.
if (-not $Combined) {
    $parts = @(SS-SplitDesignBySkin $dj)
    if ($parts.Count -lt 2) {
        # a single skin: nothing to split, carry on as an ordinary build
    } else {
        $oldName = ($dj.modName -replace '[^A-Za-z0-9]', '') + '_9999999_P.utoc'
        $modsDir = Join-Path $SS_Paks '~mods'
        if (Test-Path -LiteralPath $modsDir) {
            $stale = @(Get-ChildItem -LiteralPath $modsDir -Recurse -File -Filter $oldName -ErrorAction SilentlyContinue)
            foreach ($s in $stale) {
                Write-Host ('!! an older COMBINED build of this design is installed: {0}' -f $s.DirectoryName)
                Write-Host '   it loads alongside the per-skin mods - disable or uninstall it (Vortex, or "uninstall all my mods")'
            }
        }
        $splitDir = Join-Path $SS_Root 'work\_split'
        New-Item -ItemType Directory -Force -Path $splitDir | Out-Null
        $fwd = @('-Version', $Version)
        # with Galacta the parts are built first and swapped in together at the
        # end - one F7 pair for the lot, not one per skin
        $galSplit = Test-GalactaSwap
        if ($Install -and -not $galSplit) { $fwd += '-Install' }
        if ($Zip)      { $fwd += '-Zip' }
        if ($DyeMeter) { $fwd += '-DyeMeter' }
        if ($MaxWorkers -gt 0) { $fwd += @('-MaxWorkers', $MaxWorkers) }
        $failed = @(); $i = 0
        foreach ($pt in $parts) {
            $i++
            $pp = Join-Path $splitDir ($pt.doc.modName + '.json')
            $pt.doc | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $pp -Encoding utf8
            Write-Host ''
            Write-Host ('###### {0} of {1}: {2} ({3} texture, {4} material edit(s)) ######' -f $i, $parts.Count, $pt.doc.displayName, $pt.doc.ops.Count, $pt.doc.colorOps.Count)
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Design $pp @fwd
            if ($LASTEXITCODE -ne 0) { $failed += $pt.doc.modName }
        }
        if ($failed.Count) { throw ('per-skin build failed for: ' + ($failed -join ', ')) }
        Write-Host ''
        Write-Host ('###### {0} mods built, one per skin: {1} ######' -f $parts.Count, (($parts | ForEach-Object { $_.doc.modName }) -join ', '))
        if ($galSplit) {
            $partMods = @($parts | ForEach-Object { [string]$_.doc.modName -replace '[^A-Za-z0-9]', '' } | Where-Object { $_ })
            $null = SS-GalSwapConsole $partMods $SS_ModsDir $env:RS_SS_GAMEPROC { param($m) Write-Host ('[{0}] {1}' -f (Get-Date -Format HH:mm:ss), $m) } $SS_SaveDir
        }
        exit 0
    }
}
$modName = ($dj.modName -replace '[^A-Za-z0-9]', '')
if (-not $modName) { throw 'design has no usable modName (letters/digits only)' }
$skin = [string]$dj.skin
$work = Join-Path $SS_Root "work\$modName"
$logF = Join-Path $work 'build.log'
New-Item -ItemType Directory -Force -Path $work | Out-Null
function BLog($msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format HH:mm:ss), $msg
    Write-Host $line
    Add-Content -LiteralPath $logF -Value $line -Encoding utf8
}
BLog "=== Skin Studio build: $modName (skin $skin) ==="

# A recolor's dyed zones render one flat colour each, and the colour sampled for
# them is an atlas average - diluted, because a region covers more than is ever
# on screen. -DyeMeter builds the measuring stick (every dye 1,1,1, so the
# recolor renders the LIGHTING); SS-SolveDyeCal reads it back off three
# screenshots into the design's dyeCal, and every later build applies it.
if ($DyeMeter) {
    $nm = SS-DyeMeterDesign $dj
    BLog ("  DYE METER build: {0} dye site(s) set to white - screenshot this, the costume and the recolor, then run Calibrate" -f $nm)
} elseif ($dj.PSObject.Properties['dyeCal']) {
    $nc = SS-ApplyDyeCal $dj
    BLog ("  recolor calibration applied to {0} dye site(s)" -f $nc)
}

$opProps = @($dj.ops.PSObject.Properties)
$colorProps = if ($dj.PSObject.Properties['colorOps']) { @($dj.colorOps.PSObject.Properties) } else { @() }
if ($opProps.Count -eq 0 -and $colorProps.Count -eq 0) { throw 'design has no texture or color edits - nothing to build' }

# 1) game-data index + fresh work dirs (texture and color stages share these)
$idx = SS-EnsureTexIndex { param($m) BLog $m }
$map = SS-LoadSkinMap $idx
# dyed materials whose D the design edits: the dye is baked into the vanilla D,
# the edits go on top, and the mod ships a blank dye mask (alpha 0 = undyed,
# proven in game 2026-09-24) so the game's dye no longer paints over them.
# Material colour edits are still patched into the MIs as before. The dye
# meter keeps the old behaviour - it exists to photograph the dye.
$dyePlans = if ($DyeMeter) { @{} } else { SS-DyePlans $dj $map $false { param($m) BLog $m } }
if ($dyePlans.Count) { BLog ("{0} dyed material(s) with texture edits: your edits will show over the dye" -f $dyePlans.Count) }
if (-not $map.skinLines.ContainsKey($skin)) { throw "skin $skin not found in the current game data" }
foreach ($sub in 'png', 'stage', 'out') {
    $d = Join-Path $work $sub
    if (Test-Path $d) { Remove-Item $d -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
$stageMod = Join-Path $work "stage\$modName"

# 2) TEXTURE stage - recolor PNGs, inject into vanilla uassets. Skipped whole
# for color-only mods.
#
# A design may edit the costume AND its recolor (chroma) skins - each op rel
# carries its own skin id, so group them by skin and run the cache + inject once
# per skin, merging every skin's staged assets into the SAME mod tree. One
# triplet then covers the costume and all of its recolors.
$rxOpSkin = [regex]'[\\/]Characters[\\/]\d{4}[\\/](\d{7})[\\/]'
# plain hashtable, NOT [ordered]@{}: an OrderedDictionary also has an integer
# indexer, and PowerShell picks that one for a numeric-looking key like
# "1064300" - "Argument types do not match". Order comes from $skinOrder below.
$opsBySkin = @{}
foreach ($prop in $opProps) {
    $m = $rxOpSkin.Match($prop.Name)
    $sid = if ($m.Success) { $m.Groups[1].Value } else { $skin }
    # plain arrays, NOT List[object]: in PS 5.1 @(<List[object]>) throws
    # "Argument types do not match", and every read of these goes through @()
    if (-not $opsBySkin.ContainsKey($sid)) { $opsBySkin[$sid] = @() }
    $opsBySkin[$sid] += $prop
}
# the design's own skin first, the recolors after (log reads in that order)
$skinOrder = @(@($opsBySkin.Keys | Where-Object { $_ -eq $skin }) + @($opsBySkin.Keys | Where-Object { $_ -ne $skin } | Sort-Object))
if ($skinOrder.Count -gt 1) {
    BLog ("design covers {0} skins: {1}" -f $skinOrder.Count, ($skinOrder -join ', '))
}
$done = 0
if ($opProps.Count -gt 0) {
    $mw = if ($MaxWorkers -gt 0) { $MaxWorkers } else { SS-Workers }
    foreach ($sid in $skinOrder) {
        if (-not $map.skinLines.ContainsKey($sid)) { BLog "  WARN: skin $sid is not in the current game data - its edits are skipped"; continue }
        if ($skinOrder.Count -gt 1) { BLog ("-- skin {0}" -f $sid) }
        $ck = SS-EnsureSkinCache $sid $map.skinLines[$sid] { param($m) BLog $m }
        $pngRoot = Join-Path $ck 'png\src'
        $sidProps = @($opsBySkin[$sid])
        $sidDone = 0
        foreach ($prop in $sidProps) {
            $rel = $prop.Name
            $srcPng = Join-Path $pngRoot $rel
            if (-not (Test-Path -LiteralPath $srcPng)) { BLog "  WARN: no cached PNG for '$rel' - skipped"; continue }
            $leafP = Split-Path $rel -Leaf
            if ($dyePlans.ContainsKey($leafP)) {
                # dye baked into the vanilla D, her edits on top; saved with the
                # VANILLA PNG's colour chunks so texconv converts nothing (Luna)
                $bmp = SS-RenderDyeBake $dyePlans[$leafP]
                try { [SkinArt]::SavePngLike($bmp, (Join-Path "$work\png" $rel), $srcPng) } finally { $bmp.Dispose() }
                BLog ("  {0}  <- {1}" -f $leafP, (SS-DyePlanLabel $dyePlans[$leafP]))
            } else {
                SS-ApplyOp $srcPng (Join-Path "$work\png" $rel) $prop.Value
                $modes = (SS-OpLayers $prop.Value | ForEach-Object { SS-OpVal $_ 'mode' '?' }) -join ' + '
                BLog ("  {0}  <- {1}" -f $leafP, $modes)
            }
            $sidDone++; $done++
        }
        # the blank dye masks: same size as the vanilla one (the inject keeps its
        # format, DXT5 - an all-zero alpha encodes exactly, verified on the probe)
        foreach ($plan in @($dyePlans.Values | Where-Object { $_.skin -eq $sid -and $_.mRel })) {
            $vm = [SkinArt]::Load($plan.mSrc); $mw2 = $vm.Width; $mh2 = $vm.Height; $vm.Dispose()
            $blank = [LiveBake]::Blank($mw2, $mh2)
            try { [SkinArt]::SavePngLike($blank, (Join-Path "$work\png" $plan.mRel), $plan.mSrc) } finally { $blank.Dispose() }
            $sidDone++; $done++
            BLog ("  {0}  <- blank dye mask (your texture edits show instead of the dye)" -f $plan.mLeaf)
        }
        if ($sidDone -eq 0) { BLog "  WARN: nothing applied for skin $sid"; continue }
        BLog "processed $sidDone texture(s)"

        # Half-changed-skin guard. Many skins ship the same map two or three times
        # under different names (a transformed form, a second costume state); edit
        # one and the rest stay vanilla in game. The studio offers to carry edits
        # across before building - a design built from the command line, or saved
        # before that existed, gets told here. Warn only: it is a legitimate choice.
        # rels shaped exactly like the design's op keys and thumbs.map: textures
        # only (a mesh named SK_..._Body would otherwise key to BODY and link to a
        # texture), backslashes, .png
        $edited = @($sidProps | ForEach-Object { $_.Name })
        $allRels = @()
        foreach ($ln in $map.skinLines[$sid]) {
            $r = SS-ManifestRel $ln
            if (-not ($r.Substring($r.LastIndexOf('/') + 1)).StartsWith('T_')) { continue }
            $allRels += (($r -replace '\.uasset$', '.png') -replace '/', '\')
        }
        $links = SS-LinkGroups $allRels
        $gaps = @()
        foreach ($rel in $edited) {
            $lk = $links[$rel]
            if (-not $lk -or -not $lk.Sure) { continue }     # only the certain ones
            foreach ($t in @($lk.Others)) {
                if ($t -and ($edited -notcontains $t) -and ($gaps -notcontains $t)) { $gaps += $t }
            }
        }
        if ($gaps.Count) {
            BLog ("  WARN: {0} map(s) you edited have another version in this skin that is still vanilla -" -f $gaps.Count)
            BLog '        the mod will only half-change in game. Open the design in Skin Studio and'
            BLog '        tick the "also apply to the other version" box, or answer Yes to the build prompt.'
            foreach ($gp in $gaps) { BLog ('          ' + [IO.Path]::GetFileNameWithoutExtension($gp)) }
        }

        # inject into vanilla uassets (UE 5.3, cubic mips). ddstools mirrors the
        # input folder leaf into save_folder, so stage\src -> rename to the mod name.
        # Per skin it goes to its own stage dir, then merges into the mod tree -
        # the paths inside carry the skin folder, so nothing can collide.
        BLog "injecting into uassets (x$mw workers)..."
        $injLog = Join-Path $work ('inject_{0}.log' -f $sid)
        $sidStage = Join-Path $work ('stage_{0}' -f $sid)
        if (Test-Path $sidStage) { Remove-Item $sidStage -Recurse -Force }
        $cl = '"{0}\python\python.exe" -E "{0}\src\main.py" "{1}" "{2}" --mode inject --version 5.3 "--save_folder={3}" --skip_non_texture --skip_missing_texture --image_filter=cubic --max_workers={5} > "{4}" 2>&1' -f $SS_Dds, "$ck\src", "$work\png", $sidStage, $injLog, $mw
        cmd /s /c " $cl "
        if (-not (Test-Path "$sidStage\src")) { throw "inject produced nothing for skin $sid (see work\$modName\inject_$sid.log)" }
        New-Item -ItemType Directory -Force -Path $stageMod | Out-Null
        $rc = robocopy "$sidStage\src" $stageMod /E /NJH /NJS /NP /NFL /NDL
        if ($LASTEXITCODE -gt 7) { throw "merging skin $sid into the mod tree failed (robocopy $LASTEXITCODE)" }
        Remove-Item $sidStage -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($done -eq 0) { throw 'no ops could be applied (cache mismatch?)' }
    $staged = @(Get-ChildItem $stageMod -Recurse -Filter *.uasset).Count
    if ($staged -lt $done) { BLog "  WARN: staged $staged of $done assets (check the inject logs)" }
    else { BLog "  staged $staged asset(s) across $($skinOrder.Count) skin(s)" }

    # verify texture encode fidelity (Luna gamma guard): roundtrip-export the
    # biggest staged textures, measure luminance drift. BC noise ~1-2; fail at 8.
    BLog '  verifying staged encode fidelity...'
    $vDir = Join-Path $work 'verify'
    if (Test-Path $vDir) { Remove-Item $vDir -Recurse -Force }
    $checkRels = @($opProps | ForEach-Object { $_.Name } | Where-Object { Test-Path -LiteralPath (Join-Path "$work\png" $_) } |
        Sort-Object { (Get-Item -LiteralPath (Join-Path "$work\png" $_)).Length } -Descending | Select-Object -First 3)
    foreach ($rel in $checkRels) {
        $stgAsset = Join-Path $stageMod ([IO.Path]::ChangeExtension($rel, 'uasset'))
        if (-not (Test-Path -LiteralPath $stgAsset)) { continue }
        $cl = '"{0}\python\python.exe" -E "{0}\src\main.py" "{1}" --mode export --export_as png --version 5.3 "--save_folder={2}" --skip_non_texture > "{3}" 2>&1' -f $SS_Dds, $stgAsset, $vDir, "$work\verify.log"
        cmd /s /c " $cl "
        $rtPng = Get-ChildItem $vDir -Recurse -Filter ([IO.Path]::GetFileName($rel)) -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $rtPng) { BLog "  WARN: could not roundtrip-export $rel for verification"; continue }
        $drift = [SkinArt]::AvgLumDiff($rtPng.FullName, (Join-Path "$work\png" $rel), 64)
        if ($drift -gt 8) { throw ("VERIFY FAILED: '{0}' shipped {1:0.0} luminance off from the intended art - encode is altering colors, not packing this. (see work\{2})" -f (Split-Path $rel -Leaf), $drift, $modName) }
        BLog ("  verify OK: {0} drift {1:0.00}" -f (Split-Path $rel -Leaf), $drift)
        Remove-Item $rtPng.FullName -Force
    }
}

# 2b) COLOR stage - patch FLinearColor material params and merge into the pack
# tree. Extracts fresh current-season MI_ vanilla, sets edited colors via
# SkinColorTool (byte-identical round-trip), verifies each write, then copies
# the patched uassets alongside the textures so one triplet carries both.
$colorDone = 0
if ($colorProps.Count -gt 0) {
    BLog ("color edits: {0} asset(s)..." -f $colorProps.Count)
    # a design may recolor materials (MI_) and/or particle systems (NS_) - map both
    # colour edits can belong to the costume AND to its recolor (chroma) skins -
    # each rel carries its skin id, so map every skin the design touches
    $relToLine = @{}
    $colorSkins = @(@($colorProps | ForEach-Object { $m2 = $rxOpSkin.Match($_.Name); if ($m2.Success) { $m2.Groups[1].Value } else { $skin } }) + @($skin) | Sort-Object -Unique)
    foreach ($cs in $colorSkins) {
        if (-not $map.skinLines.ContainsKey($cs)) { continue }
        foreach ($kind in 'mat', 'fx') {
            foreach ($ln in (SS-LoadColorMap $cs $kind)) { $relToLine[(SS-ManifestRel $ln)] = $ln }
        }
    }
    if ($colorSkins.Count -gt 1) { BLog ("  colour edits span {0} skins: {1}" -f $colorSkins.Count, ($colorSkins -join ', ')) }
    # effect materials (VFX/Materials/Characters/<hero>/...) live outside the skin
    # folder, so the skin's colour map never lists them - resolve those straight
    # from the game manifest. They are shared by every costume of the hero, the
    # same as the default costume's particle systems the others reuse.
    $unresolved = @($colorProps | Where-Object { -not $relToLine.ContainsKey($_.Name) })
    if ($unresolved.Count) {
        $want = @{}
        foreach ($cp in $unresolved) { $want['../../../' + $cp.Name] = $cp.Name }
        foreach ($raw in [IO.File]::ReadLines((Join-Path $SS_Cache 'char_manifest.txt'))) {
            $t = $raw.Trim([char]0xFEFF).Trim()
            if ($want.ContainsKey($t)) { $relToLine[$want[$t]] = $t }
        }
        $nVfx = @($unresolved | Where-Object { $relToLine.ContainsKey($_.Name) }).Count
        if ($nVfx) { BLog ("  {0} effect material(s) from outside the skin folder (shared by all of this hero's costumes)" -f $nVfx) }
    }
    $subset = @()
    foreach ($cp in $colorProps) {
        if ($relToLine.ContainsKey($cp.Name)) { $subset += $relToLine[$cp.Name] }
        else { BLog "  WARN: color asset '$($cp.Name)' not in current game data - skipped" }
    }
    if ($subset.Count -gt 0) {
        $csrc = Join-Path $work 'colorsrc'
        if (Test-Path $csrc) { Remove-Item $csrc -Recurse -Force }
        $null = SS-UnpackColorAssets $subset $csrc { }
        $editsArr = @()
        foreach ($cp in $colorProps) {
            if (-not $relToLine.ContainsKey($cp.Name)) { continue }
            $mrel = SS-ManifestRel $relToLine[$cp.Name]
            $full = Join-Path $csrc ($mrel -replace '/', '\')
            if (-not (Test-Path -LiteralPath $full)) { BLog "  WARN: '$($cp.Name)' not extracted - skipped"; continue }
            $edits = @()
            foreach ($e in @($cp.Value)) {
                $h = [ordered]@{ export = [int]$e.export; ordinal = [int]$e.ordinal; r = [double]$e.r; g = [double]$e.g; b = [double]$e.b }
                if ($e.PSObject.Properties['a'] -and $null -ne $e.a) { $h.a = [double]$e.a }
                if ($e.PSObject.Properties['kind'] -and $e.kind) { $h.kind = [string]$e.kind }
                $edits += $h
            }
            if ($edits.Count -eq 0) { continue }
            $editsArr += [ordered]@{ asset = $full; rel = $mrel; edits = $edits }
        }
        if ($editsArr.Count -gt 0) {
            $editsFile = Join-Path $work 'edits.json'
            $json = ConvertTo-Json -Depth 8 -InputObject $editsArr
            if (-not $json.TrimStart().StartsWith('[')) { $json = "[`n$json`n]" }
            Set-Content -LiteralPath $editsFile -Value $json -Encoding utf8
            $colorstage = Join-Path $work 'colorstage'
            if (Test-Path $colorstage) { Remove-Item $colorstage -Recurse -Force }
            # stderr goes to a file through cmd (a PS 2> under Stop = terminating
            # NativeCommandError). It is UAssetAPI's "Failed to parse export N" -
            # exports it can't read (Niagara IntVector2 data, 2026-09-25) are kept
            # byte-for-byte and never edited; the re-read below proves every edit.
            # In the console it read as a failed build when nothing had failed.
            $cWarn = Join-Path $work 'colortool_warnings.log'
            $cl = '"{0}" patch "{1}" "{2}" "{3}" 2> "{4}"' -f $SS_ColorTool, $SS_Usmap, $editsFile, $colorstage, $cWarn
            cmd /s /c " $cl " | ForEach-Object { BLog "  $_" }
            if ($LASTEXITCODE -ne 0) { throw "SkinColorTool patch failed (exit $LASTEXITCODE, see work\$modName\colortool_warnings.log)" }
            $patched = @(Get-ChildItem $colorstage -Recurse -Filter *.uasset -ErrorAction SilentlyContinue)
            if ($patched.Count -eq 0) { throw 'color patch produced no assets (see log above)' }
            # verify: re-dump patched assets, confirm every edit landed
            $vlist = Join-Path $work 'cverify_list.txt'
            [IO.File]::WriteAllLines($vlist, @($patched | ForEach-Object { $_.FullName }))
            $cverify = Join-Path $work 'colors_verify.json'
            $cl = '"{0}" dump "{1}" "{2}" colorstage "@{3}" > nul 2>> "{4}"' -f $SS_ColorTool, $SS_Usmap, $cverify, $vlist, $cWarn
            cmd /s /c " $cl "
            $nWarn = @(Get-Content -LiteralPath $cWarn -ErrorAction SilentlyContinue | Where-Object { $_ -match 'Failed to parse export' } | Sort-Object -Unique).Count
            if ($nWarn) { BLog ("  note: {0} asset part(s) the colour tool can't read were copied unchanged - harmless, your edits are checked next (work\{1}\colortool_warnings.log)" -f $nWarn, $modName) }
            $vmap = @{}
            foreach ($va in (Get-Content $cverify -Raw | ConvertFrom-Json)) {
                foreach ($vc in $va.colors) { $vmap[('{0}|{1}|{2}' -f $va.asset, $vc.export, $vc.ordinal)] = $vc }
            }
            foreach ($ea in $editsArr) {
                foreach ($e in $ea.edits) {
                    $got = $vmap[('{0}|{1}|{2}' -f $ea.rel, $e.export, $e.ordinal)]
                    if (-not $got) { throw ("color VERIFY: {0} @{1}/{2} missing after patch" -f $ea.rel, $e.export, $e.ordinal) }
                    # curve edits RETINT a gradient (per-sample brightness kept) so the
                    # re-dumped average won't equal the exact target - presence is enough.
                    if ($e.Contains('kind') -and $e['kind'] -eq 'curve') { continue }
                    $dr = [math]::Abs($got.r - $e.r) + [math]::Abs($got.g - $e.g) + [math]::Abs($got.b - $e.b)
                    if ($dr -gt 0.01) { throw ("color VERIFY FAILED: {0} @{1}/{2} wrote wrong value (drift {3:0.000})" -f $ea.rel, $e.export, $e.ordinal, $dr) }
                }
            }
            $nSites = ($editsArr | ForEach-Object { $_.edits.Count } | Measure-Object -Sum).Sum
            BLog ("  color verify OK: {0} site(s) across {1} material(s)" -f $nSites, $patched.Count)
            New-Item -ItemType Directory -Force -Path $stageMod | Out-Null
            Get-ChildItem $colorstage -Recurse -File | ForEach-Object {
                $rel2 = $_.FullName.Substring($colorstage.Length).TrimStart('\')
                $dst = Join-Path $stageMod $rel2
                New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
                Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
            }
            $colorDone = $patched.Count
        }
    }
}

if (-not (Test-Path $stageMod)) { throw 'nothing staged to pack' }
BLog ("staged: {0} texture(s) + {1} color asset(s)" -f $done, $colorDone)

# 4) pack
BLog '3/3 packing with retoc-rivals-cli...'
# --obfuscate sets the container's Encrypted bit. Without it the game mounts the
# container and then silently ignores ALL of it once it carries particle systems
# (DRCLRD 2026-09-25: no crash, no pak_invalid.txt, textures vanilla; the same
# build minus its NS_ edits showed, and encrypted WITH them showed too). Theme
# Studio learned the same about UI mods (generate.ps1, 1.1.3825464).
$cl = '"{0}" pack "{1}" --output "{2}" --game-paks-dir "{3}" --obfuscate > "{4}" 2>&1' -f $SS_Rr, "$work\stage\$modName", "$work\out", $SS_Paks, "$work\pack.log"
cmd /s /c " $cl "
$triplet = @(Get-ChildItem "$work\out" -File -ErrorAction SilentlyContinue)
if (-not ($triplet | Where-Object Extension -eq '.ucas')) { throw "pack failed - no .ucas (see work\$modName\pack.log)" }
BLog ('  produced: ' + (($triplet | ForEach-Object { '{0} ({1:n1} MB)' -f $_.Name, ($_.Length / 1MB) }) -join ', '))
# EIoContainerFlags at offset 80 of the .utoc: Compressed 1, Encrypted 2, Signed 4, Indexed 8
$utocOut = @($triplet | Where-Object Extension -eq '.utoc')[0]
$flags = [int]([IO.File]::ReadAllBytes($utocOut.FullName)[80])
if (-not ($flags -band 0x02)) { throw ("container flags 0x{0:x2} - NOT encrypted. The game ignores an unencrypted mod that ships particle systems; the pack call must pass --obfuscate." -f $flags) }
BLog ("  container encrypted (flags 0x{0:x2})" -f $flags)

# 5) install loose at ~mods root (S9: subfolders no longer mount)
$galSwap = $null
if ($Install) {
    if (Test-GalactaSwap) {
        # Rivals is running, so the old copy is mounted - Project Galacta's F7
        # unloads it, the new one goes in, a second F7 loads it (galacta.ps1)
        $galSwap = SS-GalSwapConsole @($modName) $SS_ModsDir $env:RS_SS_GAMEPROC { param($m) BLog $m } $SS_SaveDir
    } elseif (Test-GameUp) {
        BLog 'INSTALL SKIPPED: Marvel Rivals is running. Close it and re-run with -Install, or copy work\out\* into ~mods yourself.'
        BLog '  (With Project Galacta installed this would swap it in without a restart: Galacta''s F7 unloads and reloads mods.)'
    } else {
        $modsDir = $SS_ModsDir
        New-Item -ItemType Directory -Force -Path $modsDir | Out-Null
        foreach ($f in $triplet) {
            $dst = Join-Path $modsDir $f.Name
            if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
            Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
        }
        BLog "  installed loose at ~mods root: ${modName}_9999999_P (.pak/.utoc/.ucas)"
    }
}

# 6) zip for sharing / Vortex
if ($Zip) {
    $display = if ($dj.PSObject.Properties['displayName'] -and $dj.displayName) { [string]$dj.displayName } else { $modName }
    $display = $display -replace '[\\/:*?"<>|]', ''
    $zipStage = Join-Path $work 'zip'
    if (Test-Path $zipStage) { Remove-Item $zipStage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $zipStage | Out-Null
    foreach ($f in $triplet) { Copy-Item -LiteralPath $f.FullName -Destination $zipStage }
    @(
        "$display  (v$Version)"
        ''
        "Marvel Rivals character skin mod - built with Skin Studio."
        "Hero/skin: $skin   Textures changed: $done   Colors changed: $colorDone"
        ''
        'Install: drop the three files (.pak/.utoc/.ucas) loose into'
        '  ...\MarvelRivals\MarvelGame\Marvel\Content\Paks\~mods\'
        '(no subfolder - Season 9+ only mounts loose files at the ~mods root).'
    ) | Set-Content -LiteralPath (Join-Path $zipStage 'README.txt') -Encoding utf8
    $zipName = '{0}-{1}-{2}.zip' -f $display, $modName, $Version
    $zipOut = Join-Path (Join-Path $SS_Root 'output') $zipName
    New-Item -ItemType Directory -Force -Path (Split-Path $zipOut -Parent) | Out-Null
    if (Test-Path -LiteralPath $zipOut) { Remove-Item -LiteralPath $zipOut -Force }
    [IO.Compression.ZipFile]::CreateFromDirectory($zipStage, $zipOut)
    Copy-Item -LiteralPath $zipOut -Destination (Join-Path $env:USERPROFILE 'Downloads') -Force
    BLog "  zipped: output\$zipName (+ copy in Downloads)"
}

BLog ('=== DONE in {0:0.0} min ===' -f $sw.Elapsed.TotalMinutes)
# (a split part builds without -Install and a Galacta swap already said how it
# went, so this is only for an install the running game will not see)
if ($Install -and -not $galSwap -and (Test-GameUp)) { BLog 'NOTE: paks mount at game BOOT - restart Marvel Rivals to see the mod.' }

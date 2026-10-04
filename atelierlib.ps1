# atelierlib.ps1 - round-trip between Skin Studio designs and Atelier projects.
# Dot-sourced after skinlib.ps1, meshlib.ps1 ($SS_AtelierRoot) and viewlib.ps1
# ([ViewArt]).
#
# An Atelier project (%LOCALAPPDATA%\Atelier\assets\projects\<name>\) is a
# folder tree at game paths:
#   Characters\<hero>\<skin>\Textures\T_*.png           full replacement art
#   Characters\<hero>\<skin>\Materials\[Lobby\]MI_*.json  the whole MI as
#                                                   UAssetAPI JSON, edits applied
#   .atelier\project.json                           selection / export options
# Verified 2026-09-23: Atelier's PNGs hold the SAME bytes as Skin Studio's
# vanilla exports (within +-1 from two BC decoders); only the tag differs - ours
# say gAMA 1.0, theirs carry no colour chunk. GDI+ ignores gAMA on decode, so
# bytes move across untouched in both directions.
#
# We RUN Atelier's UAssetTool.exe (JSON <-> uasset) as an external program; no
# Atelier code is copied here.

$SS_AtelierProjects = Join-Path $SS_AtelierRoot 'assets\projects'
$SS_AtelierUat      = Join-Path $SS_AtelierRoot 'Tools\UAssetTool.exe'
$SS_ImportRoot      = Join-Path $SS_Root 'imports'

function SS-AtelierProjectList {
    if (-not (Test-Path -LiteralPath $SS_AtelierProjects)) { return @() }
    foreach ($d in (Get-ChildItem -LiteralPath $SS_AtelierProjects -Directory)) {
        $ch = Join-Path $d.FullName 'Characters'
        $png = @(Get-ChildItem -LiteralPath $ch -Recurse -File -Filter *.png -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\blender\\' })
        $mat = @(Get-ChildItem -LiteralPath $ch -Recurse -File -Filter 'MI_*.json' -ErrorAction SilentlyContinue)
        $skins = @(@($png) + @($mat) | ForEach-Object { if ($_.FullName -match '\\Characters\\\d{4}\\(\d{7})\\') { $Matches[1] } } | Sort-Object -Unique)
        [pscustomobject]@{ Name = $d.Name; Dir = $d.FullName; Skins = $skins; Textures = $png.Count; Materials = $mat.Count; Modified = $d.LastWriteTime }
    }
}

# project file -> Skin Studio rel ('Marvel\Content\Marvel\Characters\...')
function SS-AtelierRel([string]$projDir, [string]$file) {
    'Marvel\Content\Marvel\' + $file.Substring($projDir.TrimEnd('\').Length + 1)
}

# Run UAssetTool and collect its output as plain strings. It prints warnings
# ("Could not find 4 referenced assets on disk") on STDERR, and under
# ErrorActionPreference Stop a native stderr line is a TERMINATING
# NativeCommandError in PS 5.1 - so relax it for this one call.
function SS-RunUat([string[]]$argv) {
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { @(& $SS_AtelierUat @argv 2>&1 | ForEach-Object { [string]$_ }) }
    finally { $ErrorActionPreference = $eap }
}

# the vanilla colour sites of one material, from the skin's colors.json
function SS-VanillaColorSites([string]$skin, [string]$asset) {
    $cj = SS-EnsureColorCache $skin $null $null 'mat'
    $all = Get-Content -LiteralPath $cj -Raw | ConvertFrom-Json
    foreach ($a in $all) { if ([string]$a.asset -eq $asset) { return $a } }
    $null
}

# Atelier MI JSON -> its colour sites, via UAssetTool from_json + our own dump
# (the same reader that made colors.json, so export/ordinal line up exactly)
function SS-AtelierMatColors([string]$json, [string]$work) {
    $usmap = SS-BestUsmap
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $leaf = [IO.Path]::GetFileNameWithoutExtension($json)
    $ua = Join-Path $work "$leaf.uasset"
    $o = SS-RunUat @('from_json', $json, $ua, $usmap)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ua)) { throw ("UAssetTool from_json failed on {0}: {1}" -f $leaf, ((@($o) | Select-Object -Last 1) -join '')) }
    $list = Join-Path $work "$leaf.list"
    [IO.File]::WriteAllLines($list, @($ua))
    $dj = Join-Path $work "$leaf.colors.json"
    & $SS_ColorTool dump $usmap $dj '-' "@$list" | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $dj)) { throw "colour dump failed on $leaf" }
    $d = Get-Content -LiteralPath $dj -Raw | ConvertFrom-Json
    foreach ($a in $d) { return $a }
}

# Atelier project -> Skin Studio design (written to $OutDir\<ModName>.json).
# Only what actually differs from vanilla comes across:
#   * a PNG whose bytes match the vanilla texture (no byte off by more than 3)
#     is an untouched import and is skipped - "Jubilee Hair Replacement"
#     imported 43 maps of two skins and edited 10
#   * an edited PNG is snapshotted into imports\<ModName>\ and becomes a
#     'replace' layer (so later edits in Atelier do not change the design
#     behind her back - re-import to pick them up)
#   * material colours that differ become colorOps; a changed vector that is
#     NOT a colour (packed params, directions - FLinearColor is not always a
#     colour) is reported and skipped, never carried silently
# Returns a summary object. Never writes into Atelier's folder.
function SS-ImportAtelierProject([string]$projDir, [string]$modName, [string]$OutDir, [scriptblock]$Progress) {
    $say = { param($m) if ($Progress) { & $Progress $m | Out-Host } }
    if (-not (Test-Path -LiteralPath $projDir)) { throw "no Atelier project at $projDir" }
    $modName = $modName -replace '[^A-Za-z0-9]', ''
    if (-not $modName) { throw 'mod name must have letters or digits' }
    if (-not $OutDir) { $OutDir = Join-Path $SS_Root 'designs' }
    $ch = Join-Path $projDir 'Characters'
    $idx = SS-EnsureTexIndex $null
    $map = SS-LoadSkinMap $idx
    $snap = Join-Path $SS_ImportRoot $modName
    $work = Join-Path $SS_Root 'work\_atelier_import'
    if (Test-Path $work) { [IO.Directory]::Delete($work, $true) }
    New-Item -ItemType Directory -Force -Path $work | Out-Null

    $ops = [ordered]@{}
    $colorOps = [ordered]@{}
    $sum = [ordered]@{ project = (Split-Path $projDir -Leaf); texEdited = 0; texSame = 0; texNoVanilla = @(); colours = 0; skippedParams = @(); materialsRead = 0; skinsTouched = @{} }

    # -- textures ------------------------------------------------------------
    $pngs = @(Get-ChildItem -LiteralPath $ch -Recurse -File -Filter *.png -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\blender\\' })
    $bySkin = $pngs | Group-Object { if ($_.FullName -match '\\Characters\\\d{4}\\(\d{7})\\') { $Matches[1] } else { '' } }
    foreach ($g in $bySkin) {
        $skin = $g.Name
        if (-not $skin) { continue }
        if (-not $map.skinLines.ContainsKey($skin)) { & $say "skin $skin is not in the current game data - its $($g.Count) texture(s) skipped"; continue }
        & $say ("Atelier import: comparing {0} texture(s) of {1} against vanilla..." -f $g.Count, $skin)
        $ck = SS-EnsureSkinCache $skin $map.skinLines[$skin] $Progress $null
        foreach ($f in $g.Group) {
            $rel = SS-AtelierRel $projDir $f.FullName
            $van = Join-Path (Join-Path $ck 'png\src') $rel
            if (-not (Test-Path -LiteralPath $van)) { $sum.texNoVanilla += $rel; continue }
            # same art = no byte off by more than decoder rounding (max, not mean:
            # a small painted detail disappears into any average)
            $st = [ViewArt]::DiffStats($f.FullName, $van)
            if ($st[1] -ge 0 -and $st[1] -le 3) { $sum.texSame++; continue }
            New-Item -ItemType Directory -Force -Path $snap | Out-Null
            $copy = Join-Path $snap $f.Name
            Copy-Item -LiteralPath $f.FullName -Destination $copy -Force
            $ops[$rel] = @(@{ mode = 'replace'; file = $copy; strength = 1.0 })
            $sum.texEdited++
            $sum.skinsTouched[$skin] = $true
        }
    }

    # -- materials -----------------------------------------------------------
    if (Test-Path -LiteralPath $SS_AtelierUat) {
        foreach ($j in @(Get-ChildItem -LiteralPath $ch -Recurse -File -Filter 'MI_*.json' -ErrorAction SilentlyContinue)) {
            if ($j.FullName -notmatch '\\Characters\\\d{4}\\(\d{7})\\') { continue }
            $skin = $Matches[1]
            $asset = ((SS-AtelierRel $projDir $j.FullName) -replace '\.json$', '.uasset') -replace '\\', '/'
            $van = SS-VanillaColorSites $skin $asset
            if (-not $van) { & $say "  $asset is not a material Skin Studio knows - skipped"; continue }
            try { $got = SS-AtelierMatColors $j.FullName $work } catch { & $say "  $($_.Exception.Message)"; continue }
            $sum.materialsRead++
            $vm = @{}
            foreach ($c in $van.colors) { $vm['{0}_{1}' -f $c.export, $c.ordinal] = $c }
            $edits = @()
            foreach ($c in $got.colors) {
                if ([string]$c.kind -eq 'curve') { continue }
                $k = '{0}_{1}' -f $c.export, $c.ordinal
                $v = $vm[$k]
                if (-not $v -or [string]$v.name -ne [string]$c.name) { $sum.skippedParams += "$asset $k (layout differs from vanilla)"; continue }
                $dd = [Math]::Abs([double]$v.r - [double]$c.r) + [Math]::Abs([double]$v.g - [double]$c.g) + [Math]::Abs([double]$v.b - [double]$c.b)
                if ($dd -lt 1e-4) { continue }
                $isColour = (SS-IsRegionDye ([string]$c.name)) -or (SS-ColorIsPickable ([string]$c.name) ([double]$c.r) ([double]$c.g) ([double]$c.b)) -or ([string]$c.name -match '(?i)tint|color|colour')
                if ($c.name -match '(?i)param|direction|position|offset|range|power|fresnel|uv') { $isColour = $false }
                if (-not $isColour) {
                    $sum.skippedParams += ('{0} : {1} ({2:0.###},{3:0.###},{4:0.###} -> {5:0.###},{6:0.###},{7:0.###})' -f [IO.Path]::GetFileNameWithoutExtension($asset), $c.name, [double]$v.r, [double]$v.g, [double]$v.b, [double]$c.r, [double]$c.g, [double]$c.b)
                    continue
                }
                $edits += [ordered]@{ export = [int]$c.export; ordinal = [int]$c.ordinal; name = [string]$c.name; r = [double]$c.r; g = [double]$c.g; b = [double]$c.b }
            }
            if ($edits.Count) { $colorOps[$asset] = $edits; $sum.colours += $edits.Count; $sum.skinsTouched[$skin] = $true }
        }
    } elseif (@(Get-ChildItem -LiteralPath $ch -Recurse -File -Filter 'MI_*.json' -ErrorAction SilentlyContinue).Count) {
        & $say "material edits skipped: Atelier's UAssetTool.exe is missing ($SS_AtelierUat)"
    }

    if ($ops.Count -eq 0 -and $colorOps.Count -eq 0) { throw ("nothing to import - every texture in '{0}' matches vanilla and no material colour differs" -f $sum.project) }
    # the skin with the most edits is the design's skin; the rest ride along
    # (build_skin.ps1 splits them into one mod per skin anyway)
    $counts = @{}
    foreach ($r in @($ops.Keys) + @($colorOps.Keys)) { if ($r -match '[\\/]Characters[\\/]\d{4}[\\/](\d{7})[\\/]') { $counts[$Matches[1]] = 1 + [int]$counts[$Matches[1]] } }
    $main = ($counts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Name
    $doc = [ordered]@{
        modName     = $modName
        displayName = $sum.project
        hero        = $main.Substring(0, 4)
        skin        = $main
        chromaSkins = @($counts.Keys | Where-Object { $_ -ne $main } | Sort-Object)
        ops         = $ops
        colorOps    = $colorOps
        importedFrom = [ordered]@{ atelierProject = $sum.project; path = $projDir; at = (Get-Date).ToString('s') }
    }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $out = Join-Path $OutDir "$modName.json"
    $doc | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $out -Encoding utf8
    [IO.Directory]::Delete($work, $true)
    $sum.design = $out
    $sum.skins = @($counts.Keys | Sort-Object)
    [pscustomobject]$sum
}

# Skin Studio design -> new Atelier project (never overwrites one: an existing
# name is refused). Textures are rendered full-size with the design's layers
# and saved WITHOUT colour chunks, like Atelier's own; colour edits are patched
# into a fresh vanilla MI with our tool (the path build_skin.ps1 proves every
# build) and handed to Atelier as UAssetTool JSON.
function SS-ExportAtelierProject([string]$designPath, [string]$projName, [string]$ProjectsDir, [scriptblock]$Progress) {
    $say = { param($m) if ($Progress) { & $Progress $m | Out-Host } }
    if (-not $ProjectsDir) { $ProjectsDir = $SS_AtelierProjects }
    $projName = ($projName -replace '[\\/:*?"<>|]', '').Trim()
    if (-not $projName) { throw 'project name is empty' }
    $proj = Join-Path $ProjectsDir $projName
    if (Test-Path -LiteralPath $proj) { throw "an Atelier project called '$projName' already exists - pick another name (Skin Studio never overwrites Atelier projects)" }
    $dj = Get-Content -LiteralPath $designPath -Raw | ConvertFrom-Json
    $idx = SS-EnsureTexIndex $null
    $map = SS-LoadSkinMap $idx
    $rx = [regex]'[\\/]Characters[\\/]\d{4}[\\/](\d{7})[\\/]'
    $nTex = 0; $nMat = 0; $skipped = @()

    foreach ($p in @($dj.ops.PSObject.Properties)) {
        $rel = [string]$p.Name
        $m = $rx.Match($rel)
        if (-not $m.Success) { $skipped += $rel; continue }
        $skin = $m.Groups[1].Value
        if (-not $map.skinLines.ContainsKey($skin)) { $skipped += $rel; continue }
        $ck = SS-EnsureSkinCache $skin $map.skinLines[$skin] $Progress $null
        $src = Join-Path (Join-Path $ck 'png\src') $rel
        if (-not (Test-Path -LiteralPath $src)) { $skipped += $rel; continue }
        $dst = Join-Path $proj ($rel -replace '^Marvel\\Content\\Marvel\\', '')
        New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
        $bmp = SS-RenderStack $src @($p.Value)
        try { $bmp.Save($dst, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }
        [ViewArt]::StripColorChunks($dst)
        $nTex++
        if ($nTex % 4 -eq 0) { & $say "Atelier export: $nTex texture(s)..." }
    }

    $cprops = @()
    if ($dj.PSObject.Properties['colorOps'] -and $dj.colorOps) { $cprops = @($dj.colorOps.PSObject.Properties) }
    if ($cprops.Count) {
        if (-not (Test-Path -LiteralPath $SS_AtelierUat)) { throw "colour edits need Atelier's UAssetTool.exe ($SS_AtelierUat)" }
        $work = Join-Path $SS_Root 'work\_atelier_export'
        if (Test-Path $work) { [IO.Directory]::Delete($work, $true) }
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        $usmap = SS-BestUsmap
        # asset -> manifest line, for the skins the edits touch
        $relToLine = @{}
        foreach ($s in @($cprops | ForEach-Object { $mm = $rx.Match($_.Name); if ($mm.Success) { $mm.Groups[1].Value } } | Sort-Object -Unique)) {
            foreach ($ln in (SS-LoadColorMap $s 'mat')) { $relToLine[(SS-ManifestRel $ln)] = $ln }
        }
        $lines = @($cprops | Where-Object { $relToLine.ContainsKey($_.Name) } | ForEach-Object { $relToLine[$_.Name] })
        $csrc = Join-Path $work 'src'
        [void](SS-UnpackColorAssets $lines $csrc $null)
        $editsArr = @()
        foreach ($cp in $cprops) {
            if (-not $relToLine.ContainsKey($cp.Name)) { $skipped += [string]$cp.Name; continue }
            $mrel = SS-ManifestRel $relToLine[$cp.Name]
            $full = Join-Path $csrc ($mrel -replace '/', '\')
            if (-not (Test-Path -LiteralPath $full)) { $skipped += [string]$cp.Name; continue }
            $edits = @(foreach ($e in @($cp.Value)) {
                if ([string]$e.kind -eq 'curve') { continue }     # particle curves are not Atelier material edits
                $h = [ordered]@{ export = [int]$e.export; ordinal = [int]$e.ordinal; r = [double]$e.r; g = [double]$e.g; b = [double]$e.b }
                if ($e.PSObject.Properties['a'] -and $null -ne $e.a) { $h.a = [double]$e.a }
                $h
            })
            if ($edits.Count) { $editsArr += [ordered]@{ asset = $full; rel = $mrel; edits = $edits } }
        }
        if ($editsArr.Count) {
            $ef = Join-Path $work 'edits.json'
            $json = ConvertTo-Json -Depth 8 -InputObject $editsArr
            if (-not $json.TrimStart().StartsWith('[')) { $json = "[`n$json`n]" }
            Set-Content -LiteralPath $ef -Value $json -Encoding utf8
            $stage = Join-Path $work 'stage'
            & $SS_ColorTool patch $SS_Usmap $ef $stage | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "SkinColorTool patch failed (exit $LASTEXITCODE)" }
            foreach ($ua in @(Get-ChildItem -LiteralPath $stage -Recurse -Filter *.uasset)) {
                $relUa = $ua.FullName.Substring($stage.Length).TrimStart('\')          # Marvel\Content\Marvel\...
                $dst = Join-Path $proj (($relUa -replace '^Marvel\\Content\\Marvel\\', '') -replace '\.uasset$', '.json')
                $tmpOut = Join-Path $work ('json_' + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Force -Path $tmpOut | Out-Null
                $o = SS-RunUat @('to_json', $ua.FullName, $usmap, $tmpOut)
                $made = @(Get-ChildItem -LiteralPath $tmpOut -Recurse -Filter *.json)
                if ($LASTEXITCODE -ne 0 -or $made.Count -eq 0) { $skipped += $relUa; continue }
                New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
                Copy-Item -LiteralPath $made[0].FullName -Destination $dst
                $nMat++
            }
        }
        [IO.Directory]::Delete($work, $true)
    }
    if ($nTex -eq 0 -and $nMat -eq 0) {
        if (Test-Path -LiteralPath $proj) { [IO.Directory]::Delete($proj, $true) }   # only the empty tree we just made
        throw 'nothing exported - the design has no edits Atelier can hold'
    }
    [pscustomobject]@{ project = $proj; textures = $nTex; materials = $nMat; skipped = $skipped }
}

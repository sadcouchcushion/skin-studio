# design_sync.ps1 - named designs shared between the F8 colour panel and the
# Skin Studio app (her ask 2026-09-27: "name, save and load designs in the in
# game studio ... saves share between the in game mod and the app should it be
# installed").
#
# In game (no app needed) a design is a save slot SSD_<name>.sav holding the
# colour panel's string ("<MI>|<param>|r,g,b;..."), and SkinStudioDesigns.sav
# lists the names ("a;b;c"). Both are SkinStudioSave objects (GVAS, one String
# property "Data").
#
# The helper runs this every few seconds while it is up. It reconciles:
#   game SSD_<name> new/changed  -> designs\<name>.json colorOps (an app design
#                                   that also has texture ops keeps them)
#   designs\<name>.json changed  -> SSD_<name> (its colorOps; texture ops stay
#                                   in the app, the helper paints them when the
#                                   design is loaded in game)
#   either side deleted          -> the other side's copy is MOVED to
#                                   work\ingame\deleted_designs (never erased)
#   SkinStudioDesigns            <- every name, newest first
# State (what each side looked like last time) is work\ingame\design_sync.json,
# so a change is only ever carried one way.
#
# A GVAS file is written from a template: an existing SkinStudioSave file of
# the game's own (SkinStudioColors.sav) with its string swapped - the format
# has no checksum, only the property's size fields, which are rewritten.
#
#   .\design_sync.ps1                reconcile once
#   -SaveDir / -DesignDir / -StateFile / -TrashDir   test seams
#
# Keep this file ASCII: PS 5.1 reads a BOM-less script as Windows-1252.
param(
    [string]$SaveDir = (Join-Path $env:LOCALAPPDATA 'Marvel\Saved\SaveGames'),
    [string]$DesignDir = 'C:\rs\SkinStudio\designs',
    [string]$StateFile = 'C:\rs\SkinStudio\work\ingame\design_sync.json',
    [string]$TrashDir = 'C:\rs\SkinStudio\work\ingame\deleted_designs'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\skinlib.ps1')
function DLog([string]$m) { Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $m) }
$Latin = [Text.Encoding]::GetEncoding(28591)       # byte-for-byte, for the ASCII payload

# ---------------------------------------------------------------- GVAS
# the Data string of a SkinStudioSave file, or $null
function Read-SaveData([string]$path) {
    if (-not [IO.File]::Exists($path)) { return $null }
    $b = [IO.File]::ReadAllBytes($path)
    $key = $Latin.GetBytes("Data`0")
    $i = Find-Bytes $b $key
    if ($i -lt 0) { return $null }
    # Data\0 | int32 len "StrProperty\0" | int64 size | byte guid | int32 strlen | chars\0
    $p = $i + $key.Length + 4 + 12 + 8 + 1
    $n = [BitConverter]::ToInt32($b, $p)
    if ($n -le 0) { return '' }
    $Latin.GetString($b, $p + 4, $n - 1)
}
function Find-Bytes([byte[]]$hay, [byte[]]$needle) {
    for ($i = 0; $i -le $hay.Length - $needle.Length; $i++) {
        $ok = $true
        for ($k = 0; $k -lt $needle.Length; $k++) { if ($hay[$i + $k] -ne $needle[$k]) { $ok = $false; break } }
        if ($ok) { return $i }
    }
    -1
}
# write <path> as a SkinStudioSave holding $data, from the template's bytes
function Write-SaveData([string]$path, [string]$data, [byte[]]$tpl) {
    $key = $Latin.GetBytes("Data`0")
    $i = Find-Bytes $tpl $key
    if ($i -lt 0) { throw 'template has no Data property' }
    $sizeAt = $i + $key.Length + 4 + 12            # int64 property size
    $strAt = $sizeAt + 8 + 1                       # int32 string length
    $oldN = [BitConverter]::ToInt32($tpl, $strAt)
    $tailAt = $strAt + 4 + $oldN                   # "None" terminator and the rest
    $payload = $Latin.GetBytes($data + "`0")
    $ms = New-Object IO.MemoryStream
    $ms.Write($tpl, 0, $sizeAt)
    $ms.Write([BitConverter]::GetBytes([int64](4 + $payload.Length)), 0, 8)
    $ms.WriteByte(0)
    $ms.Write([BitConverter]::GetBytes([int32]$payload.Length), 0, 4)
    $ms.Write($payload, 0, $payload.Length)
    $ms.Write($tpl, $tailAt, $tpl.Length - $tailAt)
    $tmp = $path + '.tmp'
    [IO.File]::WriteAllBytes($tmp, $ms.ToArray())
    if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
    [IO.File]::Move($tmp, $path)
}

# ---------------------------------------------------------------- conversions
function Hash([string]$s) {
    $sha = [Security.Cryptography.SHA1]::Create()
    $h = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($s))) -replace '-', ''
    $sha.Dispose(); $h.Substring(0, 16)
}
function Safe-Name([string]$n) { (($n -replace '[^A-Za-z0-9 _-]', '').Trim()) }
$inv = [Globalization.CultureInfo]::InvariantCulture
function F([double]$v) { $v.ToString('0.######', $inv) }
# app design -> panel string (first stored colour of each name per MI)
function Design-ToData($doc) {
    if (-not $doc.PSObject.Properties['colorOps']) { return '' }
    $seen = @{}; $parts = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($doc.colorOps.PSObject.Properties)) {
        $mi = [IO.Path]::GetFileNameWithoutExtension([string]$p.Name)
        foreach ($e in @($p.Value)) {
            $k = $mi + '|' + [string]$e.name
            if ($seen.ContainsKey($k)) { continue }
            $seen[$k] = 1
            $parts.Add(('{0}|{1}|{2},{3},{4}' -f $mi, $e.name, (F $e.r), (F $e.g), (F $e.b)))
        }
    }
    ($parts | Sort-Object) -join ';'
}
# panel string -> colorOps (every material instance of that name) for the given
# skins only: an app design is one skin (the colour save holds every hero)
function Data-ToColorOps([string]$data, [string[]]$skins) {
    $bySkin = @{}
    foreach ($m in [regex]::Matches($data, '(MI_[A-Za-z0-9_]+)\|([^|;]+)\|([0-9.eE+-]+),([0-9.eE+-]+),([0-9.eE+-]+)')) {
        $sk = [regex]::Match($m.Groups[1].Value, '_(\d{7})(?:_|$)')
        if (-not $sk.Success) { continue }
        $sid = $sk.Groups[1].Value
        if ($skins -and $skins -notcontains $sid) { continue }
        if (-not $bySkin.ContainsKey($sid)) { $bySkin[$sid] = New-Object System.Collections.ArrayList }
        [void]$bySkin[$sid].Add(@{ Mi = $m.Groups[1].Value; Param = $m.Groups[2].Value
            R = [double]::Parse($m.Groups[3].Value, $inv); G = [double]::Parse($m.Groups[4].Value, $inv); B = [double]::Parse($m.Groups[5].Value, $inv) })
    }
    $ops = [ordered]@{}; $main = ''; $most = -1
    foreach ($sid in $bySkin.Keys) {
        if ($bySkin[$sid].Count -gt $most) { $most = $bySkin[$sid].Count; $main = $sid }
        $mats = @((Get-Content -LiteralPath (SS-EnsureColorCache $sid { param($x) }) -Raw | ConvertFrom-Json))
        foreach ($e in $bySkin[$sid]) {
            foreach ($mat in $mats) {
                if ([IO.Path]::GetFileNameWithoutExtension([string]$mat.asset) -ne $e.Mi) { continue }
                $c = @($mat.colors | Where-Object { $_.name -eq $e.Param })[0]
                if (-not $c) { continue }
                $a = [string]$mat.asset
                if (-not $ops.Contains($a)) { $ops[$a] = New-Object System.Collections.ArrayList }
                [void]$ops[$a].Add([ordered]@{ export = $c.export; ordinal = $c.ordinal; name = $e.Param; r = $e.R; g = $e.G; b = $e.B })
            }
        }
    }
    @{ ColorOps = $ops; Skin = $main }
}

# which skin an in-game design is for. The colour save holds every hero, so the
# design does too; the app shows one skin. Best guess, in order: the skin whose
# colours changed most recently (the hero on screen when it was saved), else
# the skin with the most colour edits in it.
function Skin-Counts([string]$data) {
    $c = @{}
    foreach ($m in [regex]::Matches($data, 'MI_[A-Za-z0-9_]*?_(\d{7})(?:_[A-Za-z0-9_]*)?\|')) { $c[$m.Groups[1].Value] = 1 + [int]$c[$m.Groups[1].Value] }
    $c
}
function Pick-Skin([string]$data, [string]$recent) {
    $c = Skin-Counts $data
    if ($recent -and $c.ContainsKey($recent)) { return $recent }
    if ($c.Count -eq 0) { return '' }
    ($c.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Name
}
# the colour save's entries per skin, to see which skin was edited last
function Entry-Map([string]$data) {
    $e = @{}
    foreach ($p in ($data -split ';')) { $m = [regex]::Match($p, '^(MI_[A-Za-z0-9_]*?_(\d{7})(?:_[A-Za-z0-9_]*)?\|[^|]+)\|(.*)$'); if ($m.Success) { $e[$m.Groups[1].Value] = $m.Groups[3].Value + '#' + $m.Groups[2].Value } }
    $e
}
# ---------------------------------------------------------------- state
$tplPath = Join-Path $SaveDir 'SkinStudioColors.sav'
if (-not [IO.File]::Exists($tplPath)) { DLog 'no SkinStudioColors.sav yet (the game writes it on the first colour edit) - nothing to sync'; return }
$tpl = [IO.File]::ReadAllBytes($tplPath)
$state = @{}
if (Test-Path -LiteralPath $StateFile) { foreach ($p in (Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json).PSObject.Properties) { $state[$p.Name] = @{ game = [string]$p.Value.game; app = [string]$p.Value.app } } }
# the skin edited last: compare the colour save with its copy from the last run
$snapFile = $StateFile + '.colours.txt'; $recentFile = $StateFile + '.recent.txt'
$nowData = Read-SaveData $tplPath
$recent = if (Test-Path -LiteralPath $recentFile) { (Get-Content -LiteralPath $recentFile -Raw).Trim() } else { '' }
if ($null -ne $nowData) {
    $prevData = if (Test-Path -LiteralPath $snapFile) { [IO.File]::ReadAllText($snapFile) } else { $null }
    if ($null -ne $prevData -and $prevData -ne $nowData) {
        $a0 = Entry-Map $prevData; $a1 = Entry-Map $nowData; $hits = @{}
        foreach ($k in $a1.Keys) { if ($a0[$k] -ne $a1[$k]) { $s = $a1[$k].Split('#')[-1]; $hits[$s] = 1 + [int]$hits[$s] } }
        foreach ($k in $a0.Keys) { if (-not $a1.ContainsKey($k)) { $s = $a0[$k].Split('#')[-1]; $hits[$s] = 1 + [int]$hits[$s] } }
        if ($hits.Count) { $recent = ($hits.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Name; [IO.File]::WriteAllText($recentFile, $recent) }
    }
    if ($prevData -ne $nowData) { [IO.File]::WriteAllText($snapFile, $nowData) }
}
New-Item -ItemType Directory -Force -Path $TrashDir, $DesignDir | Out-Null

# Designs pair up by KEY = the name's letters and digits: the app saves a design
# as designs\<modName>.json with modName letters/digits only, so a game name
# "Pink Snow" and the app's PinkSnow.json are the same design.
function Key([string]$n) { $n -replace '[^A-Za-z0-9]', '' }
$game = @{}      # key -> @{ Name; Data }
foreach ($f in [IO.Directory]::GetFiles($SaveDir, 'SSD_*.sav')) {
    $n = [IO.Path]::GetFileNameWithoutExtension($f).Substring(4)
    $d = Read-SaveData $f
    $k = Key $n
    if ($null -ne $d -and $k) { $game[$k] = @{ Name = $n; Data = $d } }
}
$app = @{}       # key -> @{ Path; Doc; Data }
foreach ($f in Get-ChildItem -LiteralPath $DesignDir -Filter *.json -File) {
    $k = Key $f.BaseName
    if (-not $k) { continue }
    try { $doc = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { continue }
    # an older sync named the file after the game name ("Pink Snow.json"): the app
    # would save it as PinkSnow.json and split the design in two - rename it once
    if ($f.BaseName -ne $k -and -not (Test-Path -LiteralPath (Join-Path $DesignDir ($k + '.json')))) {
        $to = Join-Path $DesignDir ($k + '.json'); Move-Item -LiteralPath $f.FullName -Destination $to; DLog ("renamed {0} -> {1}.json (the app's own name for it)" -f $f.Name, $k)
        $app[$k] = @{ Path = $to; Doc = $doc; Data = (Design-ToData $doc) }; continue
    }
    $app[$k] = @{ Path = $f.FullName; Doc = $doc; Data = (Design-ToData $doc) }
}
# state keys from before the rename
foreach ($sk in @($state.Keys)) { $k = Key $sk; if ($k -ne $sk) { if (-not $state.ContainsKey($k)) { $state[$k] = $state[$sk] }; $state.Remove($sk) } }

# the game's word on which hero a save was made on: SSHero_<name>__<MI>.sav,
# written with every in-game Save (panel builds from 2026-09-28). It beats the
# guess, is kept in <state>.skins.json, and re-files a design made in game.
$skinsFile = $StateFile + '.skins.json'
$heroSkin = @{}
if (Test-Path -LiteralPath $skinsFile) { foreach ($p in (Get-Content -LiteralPath $skinsFile -Raw | ConvertFrom-Json).PSObject.Properties) { $heroSkin[$p.Name] = [string]$p.Value } }
$heroNew = @{}
foreach ($f in [IO.Directory]::GetFiles($SaveDir, 'SSHero_*.sav')) {
    $leaf = [IO.Path]::GetFileNameWithoutExtension($f).Substring(7)
    $cut = $leaf.LastIndexOf('__')
    try { [IO.File]::Delete($f) } catch {}
    if ($cut -lt 1) { continue }
    $sk = [regex]::Match($leaf.Substring($cut + 2), '_(\d{7})(?:_|$)')
    if (-not $sk.Success) { continue }
    $k = Key $leaf.Substring(0, $cut)
    $heroSkin[$k] = $sk.Groups[1].Value; $heroNew[$k] = 1
    DLog ("{0} was saved on skin {1}" -f $leaf.Substring(0, $cut), $sk.Groups[1].Value)
}
if ($heroNew.Count) { [IO.File]::WriteAllText($skinsFile, ($heroSkin | ConvertTo-Json)) }
# a design the game made, now known to be for another skin: redo its app copy
foreach ($k in $heroNew.Keys) {
    if ($app.ContainsKey($k) -and $app[$k].Doc.PSObject.Properties['madeInGame'] -and [string]$app[$k].Doc.skin -ne $heroSkin[$k]) {
        $app[$k].Doc.skin = $heroSkin[$k]; $app[$k].Doc.hero = $heroSkin[$k].Substring(0, 4)
        if ($state.ContainsKey($k)) { $state[$k].game = '' }       # carry it over again
    }
}
$changed = $false
$names = @($game.Keys) + @($app.Keys) + @($state.Keys) | Sort-Object -Unique
foreach ($n in $names) {
    $st = if ($state.ContainsKey($n)) { $state[$n] } else { @{ game = ''; app = '' } }
    $g = if ($game.ContainsKey($n)) { Hash $game[$n].Data } else { '' }
    $a = if ($app.ContainsKey($n)) { Hash $app[$n].Data } else { '' }
    $gChanged = $g -ne $st.game
    $aChanged = $a -ne $st.app
    if (-not $gChanged -and -not $aChanged) { continue }
    if ($gChanged -and $g) {
        # game -> app: new, or edited in game (the game wins a tie - it is the newer act)
        $skins = if ($app.ContainsKey($n) -and [string]$app[$n].Doc.skin) { @([string]$app[$n].Doc.skin) + @($app[$n].Doc.chromaSkins | Where-Object { $_ }) } elseif ($heroSkin.ContainsKey($n)) { @($heroSkin[$n]) } else { @(Pick-Skin $game[$n].Data $recent) }
        $conv = Data-ToColorOps $game[$n].Data $skins
        if ($app.ContainsKey($n)) {
            $doc = $app[$n].Doc
            if ($doc.PSObject.Properties['colorOps']) { $doc.colorOps = $conv.ColorOps } else { $doc | Add-Member -NotePropertyName colorOps -NotePropertyValue $conv.ColorOps }
            $path = $app[$n].Path
        } else {
            $sid = if ($conv.Skin) { $conv.Skin } else { '' }
            $doc = [ordered]@{ modName = $n; displayName = $game[$n].Name; hero = $(if ($sid) { $sid.Substring(0, 4) } else { '' })
                               skin = $sid; chromaSkins = @(); madeInGame = $true; ops = [ordered]@{}; colorOps = $conv.ColorOps }
            $path = Join-Path $DesignDir ($n + '.json')
        }
        [IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
        $reread = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $a = Hash (Design-ToData $reread)
        DLog ("game -> app: {0}" -f $game[$n].Name); $changed = $true
    } elseif ($gChanged -and -not $g -and $app.ContainsKey($n)) {
        # deleted in game: the app copy goes to the trash folder
        Move-Item -LiteralPath $app[$n].Path -Destination (Join-Path $TrashDir ('{0}_{1:yyyyMMdd-HHmmss}.json' -f $n, (Get-Date))) -Force
        DLog ("deleted in game: {0} (app copy moved to {1})" -f $n, $TrashDir); $a = ''; $changed = $true
    } elseif ($aChanged -and $a) {
        # a texture-only design still goes in: loading it in game has the helper paint it
        if ($app[$n].Data -or @($app[$n].Doc.ops.PSObject.Properties).Count) {
            # the game keeps its own spelling of a name it made ("Pink Snow")
            $gname = if ($game.ContainsKey($n)) { $game[$n].Name } else {
                $dn = Safe-Name ([string]$app[$n].Doc.displayName); if ($dn -and (Key $dn) -eq $n) { $dn } else { $n } }
            Write-SaveData (Join-Path $SaveDir ('SSD_{0}.sav' -f $gname)) $app[$n].Data $tpl
            $g = Hash $app[$n].Data
            DLog ("app -> game: {0}" -f $gname); $changed = $true
        }
    } elseif ($aChanged -and -not $a -and $game.ContainsKey($n)) {
        $src = Join-Path $SaveDir ('SSD_{0}.sav' -f $game[$n].Name)
        Move-Item -LiteralPath $src -Destination (Join-Path $TrashDir ('SSD_{0}_{1:yyyyMMdd-HHmmss}.sav' -f $game[$n].Name, (Get-Date))) -Force
        DLog ("deleted in the app: {0} (game copy moved to {1})" -f $game[$n].Name, $TrashDir); $g = ''; $changed = $true
    }
    if ($g -or $a) { $state[$n] = @{ game = $g; app = $a } } else { $state.Remove($n) }
}

# the in-game list: every design the game holds, newest first
$have = @(Get-ChildItem -LiteralPath $SaveDir -Filter 'SSD_*.sav' -File | Sort-Object LastWriteTime -Descending | ForEach-Object { $_.BaseName.Substring(4) })
$idxPath = Join-Path $SaveDir 'SkinStudioDesigns.sav'
$want = $have -join ';'
if ((Read-SaveData $idxPath) -ne $want) { Write-SaveData $idxPath $want $tpl; DLog ("in-game list: {0} design(s)" -f $have.Count) }
if ($changed -or -not (Test-Path -LiteralPath $StateFile)) {
    $out = [ordered]@{}; foreach ($k in ($state.Keys | Sort-Object)) { $out[$k] = $state[$k] }
    [IO.File]::WriteAllText($StateFile, ($out | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
}

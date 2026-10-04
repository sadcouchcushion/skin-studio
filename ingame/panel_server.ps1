# panel_server.ps1 - the PC half of Skin Studio's in-game editor.
#
# Dot-sourced by live_preview.ps1 whenever it watches (the LIVE PREVIEW button),
# so the process that already renders designs into the game's drop folder is
# the one that serves the panel. One renderer, nothing to fight over the PNGs,
# and a design saved in the desktop app refreshes the hero on its own whenever
# the panel exists in game.
#
# The game side (WBP_SkinLiveEditor) is deliberately dumb: an Image showing
# <LiveDir>\_panel.png and a transparent Button reporting the mouse. Every pixel
# of the panel is drawn by SkinPanel.cs and every click is resolved here, so new
# screens and controls never need Unreal, a cook or a repack.
#
# ---- the protocol -----------------------------------------------------------
# Game -> PC. SaveGameToSlot writes a .sav whose NAME is the message; the
# content is irrelevant (it is the game's own HighlightSettings object):
#   SaveGames\SLC_<ms>_<verb>[_<args>].sav
#     open_<vw>_<vh>_<scale*100>  panel shown; viewport pixels and UMG DPI scale
#     t_<TextureName>             a BaseColor texture on the hero, one per slot
#     tend                        end of that list
#     d|m|u_<x>_<y>_<w>_<h>       mouse down / move / up over the panel, slate
#                                 units, with the panel's own size to scale by
#     wu | wd                     mouse wheel up / down
#     close                       panel hidden with F8 (F7 until 2026-09-26)
#     texok                       the game finished a texture refresh pass
#   <ms> is the game's real time in ms. Everything sent in one frame shares it,
#   which is what orders a batch without trusting file timestamps.
#
# PC -> game. Blueprint cannot read a file it has no class for, but it CAN ask
# whether a save slot exists - a stat, cheap enough to poll every frame:
#   SaveGames\SkinLiveFrame.sav   a new <LiveDir>\_panel.png is ready
#   SaveGames\SkinLiveTex.sav     run a refresh pass, which re-imports every
#   SaveGames\SLT_<Texture>.sav   texture whose SLT_ flag exists
#   SaveGames\SkinLiveClose.sav   hide the panel (its own close button)
#
# Keep this file ASCII: PS 5.1 reads a BOM-less script as Windows-1252.

Add-Type -Path (Join-Path $PSScriptRoot 'SkinPanel.cs') -ReferencedAssemblies System.Drawing
# the Build mod button's live refresh (Project Galacta's method: mount a pak
# while the game runs, load its assets from never-loaded paths)
. (Join-Path $PSScriptRoot 'livepak.ps1')
# ...and, when Project Galacta itself is installed, its F7 unload / reload
# swaps the real mod in instead; also the install that never half-replaces a mod
. (Join-Path $SS_Root 'galacta.ps1')
$script:PnlHome = $PSScriptRoot

$script:Pnl = @{
    SaveDir = ''; LiveDir = ''; DesignDir = ''; WorkDir = ''; FrameOut = ''
    FramePath = ''; FlagBytes = [byte[]]@()
    Open = $false; Vw = 1920; Vh = 1080; Scale = 1.0
    Ui = $null; PW = 0; PH = 0; PS = 0.0; Zoom = 1.25
    PendingColor = ''; PendingMode = ''; ImageUndo = ''
    MX = -1.0; MY = -1.0; Down = $false
    Screen = 'home'; Rel = ''; Layer = 0; Slot = 'color'
    Hsv = [double[]]@(0, 0, 1); HsvKey = ''; HsvHex = ''
    Gens = @{}; PartLeaves = @(); Parts = @(); SkinsLoaded = @{}; Drawing = $false; PendingPath = ''
    Info = @{}; Map = $null
    Doc = $null; DocPath = ''; DocStamp = [long]0
    Undo = (New-Object System.Collections.ArrayList); PreSnap = ''; UndoPath = ''
    Status = 'Ready'; Warn = $false
    LastHash = ''; FrameNo = 0
    Stuck = (New-Object 'System.Collections.Generic.HashSet[string]')
    Queue = (New-Object System.Collections.ArrayList)
    Recent = (New-Object System.Collections.ArrayList)
    DesignList = @(); ImageList = @()
    Confirm = $null
    Links = @{}
    # the Build mod button: the running/last job, the linked-map check, and the
    # install target (RS_PNL_MODSDIR / RS_PNL_GAMEPROC are test seams)
    Job = $null; BuildGaps = @(); BuildFill = $true; BuildGapsFor = ''; BuildMods = @()
    ModsDir = ''; GameProc = ''; Pending = @(); NextPendingCheck = [DateTime]::MinValue
    JobClock = [Diagnostics.Stopwatch]::StartNew(); JobShown = ''
    # a hero the game announced on its own (its pawn name), retries per pawn,
    # and what each design file covers (by mtime) for Pnl-PickDesign
    Auto = ''; AutoTries = @{}; DesignIndex = @{}
    # LIVE PREVIEW (live_preview.ps1 sets both): off = the hero wears the game's
    # own skin and the panel shows only its "Turn on" screen. LiveSet switches it
    # ({ param($on, $why) }); a test that loads the panel alone has none.
    LiveOn = $true; LiveSet = $null
}

# curated palette: brights, pastels, deeps, neutrals
$script:PnlPalette = [System.Drawing.Color[]]@(
    '#FF3B5C','#FF7A1A','#FFC61A','#3DDC5A','#1AC6FF','#2E6BFF','#8A3DFF','#FF4FC3',
    '#FFB3C1','#FFD3A8','#FFF1A8','#BFF2C4','#B3ECFF','#B8C9FF','#D9C2FF','#FFC2EA',
    '#7A0F22','#7A3300','#7A5A00','#0F5A22','#005A73','#102A7A','#3D1273','#73104F',
    '#FFFFFF','#D9D9D9','#A6A6A6','#737373','#4D4D4D','#262626','#0D0D0D','#9EBD94' |
    ForEach-Object { [SkinPanel]::Hex($_) })

$script:PnlModes = @(
    @{ id = 'tint';      label = 'Tint' },
    @{ id = 'paint';     label = 'Paint' },
    @{ id = 'hueshift';  label = 'Hue shift' },
    @{ id = 'huerange';  label = 'Colour family' },
    @{ id = 'hsl';       label = 'HSL' },
    @{ id = 'gradtint';  label = 'Gradient tint' },
    @{ id = 'gradpaint'; label = 'Gradient paint' },
    @{ id = 'gray';      label = 'Grayscale' },
    @{ id = 'invert';    label = 'Invert' },
    @{ id = 'replace';   label = 'Image' }
)
# her text-size setting: multiplies the 1080p-relative UI scale
$script:PnlZooms = @(
    @{ label = 'Small';  z = 1.0 },
    @{ label = 'Medium'; z = 1.25 },
    @{ label = 'Large';  z = 1.5 },
    @{ label = 'Huge';   z = 1.8 }
)
$script:PnlDirs = @(
    @{ id = 'v';       label = 'Top to bottom' },
    @{ id = 'h';       label = 'Left to right' },
    @{ id = 'diag';    label = 'Diagonal' },
    @{ id = 'radial';  label = 'Radial' },
    @{ id = 'corners'; label = '4 corners' }
)

function Pnl-Log([string]$msg) { Write-Host ('[{0}] panel: {1}' -f (Get-Date -Format HH:mm:ss), $msg) }

# ============================================================== setup / files
function Pnl-Init([string]$saveDir, [string]$liveDir, [string]$designDir, [string]$frameOut) {
    $st = $script:Pnl
    if (-not $saveDir) { $saveDir = Join-Path $env:LOCALAPPDATA 'Marvel\Saved\SaveGames' }
    $st.SaveDir = $saveDir; $st.LiveDir = $liveDir; $st.DesignDir = $designDir; $st.FrameOut = $frameOut
    $st.WorkDir = Join-Path $SS_Root 'work\ingame'
    foreach ($d in @($saveDir, $liveDir, $st.WorkDir, (Join-Path $st.WorkDir 'thumbs'), (Join-Path $st.WorkDir 'base'))) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
    if ($frameOut) { New-Item -ItemType Directory -Force -Path $frameOut | Out-Null }
    $st.FramePath = Join-Path $liveDir '_panel.png'
    # the flag files only have to EXIST, but give them valid save bytes anyway -
    # the game's own save system never sees a malformed .sav in its folder
    $hl = Join-Path $saveDir 'HighlightSettings.sav'
    $st.FlagBytes = if (Test-Path -LiteralPath $hl) { [IO.File]::ReadAllBytes($hl) } else { [Text.Encoding]::ASCII.GetBytes('SkinLive') }
    $recent = Join-Path $st.WorkDir 'recent_colors.txt'
    if (Test-Path -LiteralPath $recent) {
        foreach ($h in [IO.File]::ReadAllLines($recent)) { if ($h -match '^#[0-9A-Fa-f]{6}$') { [void]$st.Recent.Add($h.ToUpperInvariant()) } }
    }
    $zf = Join-Path $st.WorkDir 'panel_zoom.txt'
    if (Test-Path -LiteralPath $zf) {
        $z = 0.0
        if ([double]::TryParse(([IO.File]::ReadAllText($zf)).Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$z) -and $z -ge 0.5 -and $z -le 3) { $st.Zoom = $z }
    }
    # stale messages from a previous session would replay old clicks - except
    # the F8 that woke this watcher (the in-game helper starts it when the game
    # asks with nobody listening): a fresh open_ with no close after it stays,
    # with the hero announce that came along, and the first poll opens the panel
    $slc = @([IO.Directory]::GetFiles($saveDir, 'SLC_*.sav') | ForEach-Object { New-Object IO.FileInfo $_ })
    $fresh = @($slc | Where-Object { ([DateTime]::Now - $_.LastWriteTime).TotalSeconds -lt 30 })
    $ms = { param($fi) $v = [regex]::Match($fi.Name, '^SLC_(\d+)_').Groups[1].Value; if ($v) { [long]$v } else { [long]0 } }
    $opens = @($fresh | Where-Object { $_.Name -match '^SLC_\d+_open_' } | Sort-Object { & $ms $_ })
    $keep = $false
    if ($opens.Count) {
        $t = & $ms $opens[-1]
        $keep = (@($fresh | Where-Object { $_.Name -match '^SLC_\d+_close' -and (& $ms $_) -ge $t }).Count -eq 0)
    }
    foreach ($f in $slc) {
        if ($keep -and ($fresh -contains $f)) { continue }
        try { [IO.File]::Delete($f.FullName) } catch {}
    }
    if ($keep) { Pnl-Log 'F8 was pressed before this watcher started - opening the panel' }
    # the game's "already announced this hero" markers go too, so a watcher
    # started mid-match hears about the hero on screen within a second; and a
    # "press Galacta's F7" request nobody took must never fire later, unasked
    foreach ($f in @([IO.Directory]::GetFiles($saveDir, 'SLA_*.sav'))) { try { [IO.File]::Delete($f) } catch {} }
    foreach ($f in @('SkinLiveGalToggle.sav')) { $p = Join-Path $saveDir $f; if (Test-Path -LiteralPath $p) { try { [IO.File]::Delete($p) } catch {} } }
    # the Build mod button
    $st.ModsDir = if ($env:RS_PNL_MODSDIR) { $env:RS_PNL_MODSDIR } else { Join-Path $SS_Paks '~mods' }
    $st.GameProc = [string]$env:RS_PNL_GAMEPROC
    $script:LP.Log = { param($m) Pnl-Log $m }
    Pnl-LoadPending
    # a build only goes onto the hero through Project Galacta now, so nothing
    # loads from a live pak an older version left listed - even mid-game
    LP-Clear $liveDir
    if (-not (Pnl-GameRunning)) {
        # clear out the old paks while nothing holds them
        $n = LP-Sweep $liveDir ''
        if ($n) { Pnl-Log ('removed {0} old live pak file(s)' -f $n) }
        if ($st.Pending.Count) { Pnl-InstallPending }
    }
    # "Skin Studio is listening": only then does the in-game mod announce each
    # hero it spawns as (bootstrap AutoTick). The studio deletes it when it
    # stops the watcher, so a game played without the app writes nothing - and
    # with live preview off there is nothing to put on a hero, so it goes too.
    if ($st.LiveOn) { Pnl-Flag 'SkinLiveOn' } else { Pnl-Unflag 'SkinLiveOn' }
    Pnl-Log ('serving the in-game editor - commands from {0} (live preview {1})' -f $saveDir, $(if ($st.LiveOn) { 'on' } else { 'off' }))
}

function Pnl-Unflag([string]$name) {
    $p = Join-Path $script:Pnl.SaveDir ($name + '.sav')
    if (Test-Path -LiteralPath $p) { try { [IO.File]::Delete($p) } catch { Pnl-Log "could not remove flag $name" } }
}

# LIVE PREVIEW switched (live_preview's Set-LiveMode calls this after the
# textures are painted or reverted). On: tell the game Skin Studio listens
# again and drop its "already announced" markers, so it re-announces the hero
# on screen and the design for that skin goes on (Pnl-AutoApply). Off: the game
# stops announcing heroes.
function Pnl-LiveChanged([bool]$on) {
    $st = $script:Pnl
    $st.LiveOn = $on
    if ($on) {
        foreach ($f in @([IO.Directory]::GetFiles($st.SaveDir, 'SLA_*.sav'))) { try { [IO.File]::Delete($f) } catch {} }
        $st.AutoTries = @{}
        Pnl-Flag 'SkinLiveOn'
        $st.Status = 'Live preview on - your design is going onto your hero'
    } else {
        Pnl-Unflag 'SkinLiveOn'
        $st.Screen = 'home'
        $st.Status = 'Live preview off - your hero is back to the game''s own skin'
    }
    $st.Warn = $false; $st.Dirty = $true
}

# the in-game LIVE PREVIEW button; slow (it paints or reverts textures), so it
# runs after the frame, under a veil
function Pnl-SetLive([bool]$on) {
    $st = $script:Pnl
    Pnl-Veil $(if ($on) { 'Turning live preview on...' } else { 'Turning live preview off...' })
    if ($st.LiveSet) { & $st.LiveSet $on 'in game' } else { Pnl-LiveChanged $on }
}

function Pnl-Flag([string]$name) {
    $p = Join-Path $script:Pnl.SaveDir ($name + '.sav')
    for ($i = 0; $i -lt 20; $i++) {
        try { [IO.File]::WriteAllBytes($p, $script:Pnl.FlagBytes); return } catch { Start-Sleep -Milliseconds 10 }
    }
    Pnl-Log "could not write flag $name"
}

# Called by live_preview's Update-Live with every leaf it wrote or reverted -
# for a panel edit AND for a design saved in the desktop app.
function Pnl-FlagLeaves([string[]]$leaves) {
    # a texture the preview just repainted is newer than the last build, so the
    # game must take its PNG now, not the built copy in the live pak
    $null = LP-DropLeaves $script:Pnl.LiveDir $leaves
    $n = 0
    foreach ($leaf in @($leaves)) {
        if (-not $leaf) { continue }
        Pnl-Flag ('SLT_' + [IO.Path]::GetFileNameWithoutExtension($leaf))
        $n++
    }
    if ($n -gt 0) { Pnl-Flag 'SkinLiveTex' }
    # thumbnails of what changed are stale now
    $script:Pnl.Dirty = $true
}

# After a refresh pass: if the game consumed the newest request, every flag it
# could have acted on is spent. If a newer request is already waiting, keep them
# all - re-importing a texture twice is harmless, missing one is not.
function Pnl-TexOk {
    if (Test-Path -LiteralPath (Join-Path $script:Pnl.SaveDir 'SkinLiveTex.sav')) { return }
    foreach ($f in @([IO.Directory]::GetFiles($script:Pnl.SaveDir, 'SLT_*.sav'))) { try { [IO.File]::Delete($f) } catch {} }
}

# ============================================================== the inbox
function Pnl-Rank([string]$verb) {
    # one frame's batch in order: the mount answer, then the walk's pk_ proofs,
    # then the walk's texok (all carry the same <ms>)
    switch ($verb) { 'open' { 0 } 'auto' { 0 } 't' { 1 } 'tend' { 2 } 'mnt' { 2 } 'd' { 3 } 'm' { 4 } 'u' { 5 } 'wu' { 6 } 'wd' { 6 } 'close' { 7 } 'texok' { 9 } default { 8 } }
}

function Pnl-Poll {
    $st = $script:Pnl
    # the Build mod job runs whether or not the panel is open
    try { Pnl-BuildTick } catch { Pnl-Log ('build ERROR: ' + $_.Exception.Message); if ($st.Job) { Pnl-JobFail ('the watcher hit an error: ' + $_.Exception.Message) } }
    $files = @()
    try { $files = @([IO.Directory]::GetFiles($st.SaveDir, 'SLC_*.sav')) } catch { return $false }
    if ($files.Count -eq 0) {
        if ($st.Dirty -and $st.Open) { Pnl-Settle }
        return $false
    }
    $cmds = New-Object System.Collections.Generic.List[object]
    foreach ($f in $files) {
        $name = [IO.Path]::GetFileNameWithoutExtension($f)
        $gone = $false
        try { [IO.File]::Delete($f); $gone = $true } catch {}
        if (-not $gone) {
            # still being written, or locked: try again next poll, but never
            # act on the same message twice
            if ($st.Stuck.Contains($name)) { continue }
            [void]$st.Stuck.Add($name)
        }
        $m = [regex]::Match($name, '^SLC_(\d+)_([a-z]+)(?:_(.*))?$')
        if (-not $m.Success) { continue }
        $cmds.Add([pscustomobject]@{ T = [long]$m.Groups[1].Value; Verb = $m.Groups[2].Value; Arg = $m.Groups[3].Value; Rank = (Pnl-Rank $m.Groups[2].Value) })
    }
    if ($st.Stuck.Count -gt 200) { $st.Stuck.Clear() }
    $list = @($cmds | Sort-Object T, Rank)
    for ($i = 0; $i -lt $list.Count; $i++) {
        $c = $list[$i]
        # a run of moves collapses to its last one
        if ($c.Verb -eq 'm' -and ($i + 1) -lt $list.Count -and $list[$i + 1].Verb -eq 'm') { continue }
        try { Pnl-Handle $c } catch { Pnl-Log ('ERROR handling {0}: {1}' -f $c.Verb, $_.Exception.Message); $st.Status = 'Error: ' + $_.Exception.Message; $st.Warn = $true; $st.Dirty = $true }
    }
    if ($st.Dirty -and $st.Open) { Pnl-Settle }
    $true
}

function Pnl-Handle($c) {
    $st = $script:Pnl
    $a = @($c.Arg -split '_')
    switch ($c.Verb) {
        'open' {
            if ($a.Count -ge 3) {
                $st.Vw = [Math]::Max(640, [int]$a[0]); $st.Vh = [Math]::Max(480, [int]$a[1])
                $st.Scale = [Math]::Max(0.5, [Math]::Min(4.0, [int]$a[2] / 100.0))
            }
            $st.Open = $true
            $st.Gens = @{}            # a fresh announce follows every open
            # The mouse is handed over by MarvelHUD.NeedInputModeUINoBlock now
            # (confirmed in game 2026-09-24), so no Windows-key tip on open; the
            # home hint keeps it as the fallback if a game patch breaks that.
            $st.Status = 'Ready'; $st.Warn = $false
            Pnl-EnsureCanvas
            $st.Dirty = $true
            Pnl-Log ('opened ({0}x{1}, game UI scale {2}) - panel {3}x{4} px, text x{5:0.00}' -f $st.Vw, $st.Vh, $st.Scale, $st.PW, $st.PH, $st.PS)
        }
        't' {
            # every texture announced since the last 'open', not just the ones
            # sharing this message's timestamp: the game sends the whole list in
            # one frame, but a list that spanned two frames would otherwise be
            # thrown away and the panel would show no parts at all
            if (-not $st.Gens.ContainsKey('all')) { $st.Gens['all'] = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase) }
            [void]$st.Gens['all'].Add($c.Arg)
        }
        'auto' {
            # the game announcing a hero it just spawned as, on its own (the
            # bootstrap's AutoTick -> AutoStart): its t_ list and tend follow
            $st.Gens = @{}
            $st.Auto = [string]$c.Arg
        }
        'tend' {
            $leaves = @()
            if ($st.Gens.ContainsKey('all')) { $leaves = @($st.Gens['all']) }
            $st.Gens = @{}
            if ($leaves.Count -eq 0) {
                # an empty walk: keep what we had. An automatic one came too
                # early - the hero's mesh attaches a moment after the pawn
                if ($st.Auto) { Pnl-AutoRetry }
                return
            }
            $st.PartLeaves = $leaves
            Pnl-ResolveParts
            # spawned, not opened: put the design on the hero now (her ask,
            # 2026-09-26 - it used to stay vanilla until F6 or the panel)
            if ($st.Auto) { $null = Pnl-AutoApply }
            $st.Dirty = $true
        }
        # the in-game mod pressed Galacta's F7 for a swap: 1 = done, 0 = no
        # Galacta loader in this level
        'gal' {
            Pnl-Log ('Galacta F7 answer: ' + $c.Arg)
            if ($st.Job -and $st.Job.Swap) { $st.Job.Swap.GalAnswer = [string]$c.Arg }
        }
        { $_ -in @('d', 'm', 'u') } {
            if (-not $st.Open) { return }
            $x = -1.0; $y = -1.0
            if ($a.Count -ge 4 -and [double]$a[2] -gt 0 -and [double]$a[3] -gt 0) {
                $x = [double]$a[0] / [double]$a[2] * $st.PW
                $y = [double]$a[1] / [double]$a[3] * $st.PH
            }
            Pnl-Input $c.Verb $x $y 0
        }
        'wu' { if ($st.Open) { Pnl-Input 'w' $st.MX $st.MY 1 } }
        'wd' { if ($st.Open) { Pnl-Input 'w' $st.MX $st.MY -1 } }
        'close' { $st.Open = $false; Pnl-Log 'closed' }
        'texok' { Pnl-TexOk; Pnl-JobTexOk }
        # MountLive's answer: true / false / nofile
        'mnt'   { Pnl-MountAnswer ([string]$c.Arg) }
        # TrySwap's proof: this texture came out of the built mod, not a PNG
        'pk'    { Pnl-PakLoaded ([string]$c.Arg) }
    }
}

# ============================================================== frames
# The canvas is sized in VIEWPORT PIXELS. The game shows the PNG 1:1 on screen
# (SetDesiredSizeInViewport(texture px / GetViewportScale)), so the UMG DPI
# scale it reports has no say here: Rivals reports ~0.5 at 1080p, and when the
# canvas was multiplied by it the first in-game frame came out 215x470 with 6 px
# text. The UI scale is the viewport's height against 1080p times her own text
# size (Pnl-SetZoom); the height is a fixed share of the screen at every zoom.
function Pnl-EnsureCanvas {
    $st = $script:Pnl
    $s = [Math]::Max(0.6, [Math]::Min(4.0, $st.Vh / 1080.0)) * $st.Zoom
    $w = [int][Math]::Round([Math]::Max(300, [Math]::Min(440 * $s, $st.Vw * 0.45)))
    $h = [int][Math]::Round($st.Vh * 0.88)
    if ($st.Ui -and $st.PW -eq $w -and $st.PH -eq $h -and $st.PS -eq $s) { return }
    # never mid-draw: the draw is still writing to the old panel's bitmap. Only
    # Pnl-Render calls this, before its Begin(), and 'open' before any draw.
    if ($st.Drawing) { return }
    if ($st.Ui) { $st.Ui.Dispose() }
    $st.PW = $w; $st.PH = $h; $st.PS = $s
    $st.Ui = New-Object SkinPanel -ArgumentList $w, $h, ([single]$s)
    $st.LastHash = ''
}

# Takes effect on the next frame: the canvas is rebuilt at the start of the
# next render, never inside the draw that clicked the button.
function Pnl-SetZoom([double]$z) {
    $st = $script:Pnl
    $st.Zoom = $z
    try { [IO.File]::WriteAllText((Join-Path $st.WorkDir 'panel_zoom.txt'), $z.ToString([Globalization.CultureInfo]::InvariantCulture)) } catch {}
    $st.Dirty = $true
}

function Pnl-NewInput([double]$x, [double]$y) {
    $in = New-Object SkinPanelInput
    $in.X = [single]$x; $in.Y = [single]$y
    $in.Down = $script:Pnl.Down
    $in
}

function Pnl-Render($in, [string]$veil) {
    $st = $script:Pnl
    Pnl-EnsureCanvas
    $ui = $st.Ui
    $ui.Begin($in)
    $st.Drawing = $true
    try { Pnl-DrawScreen $ui }
    catch {
        $st.Status = 'panel error: ' + $_.Exception.Message; $st.Warn = $true
        Pnl-Log ('draw error: {0} @ {1}' -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber)
    } finally { $st.Drawing = $false }
    if ($veil) { $ui.Veil($veil) }
    $ui.End()
}

# Anything slow a button starts - a new design, a design switch, an undo, a
# copy - runs AFTER the frame, never inside the draw. Drawing is one Begin/End
# pair on one bitmap, so a veil frame raised mid-draw disposes the frame the
# draw is still writing to, and the outer End() then dies on a null Graphics.
function Pnl-Run([scriptblock]$block) { [void]$script:Pnl.Queue.Add(@{ kind = 'run'; block = $block }) }

function Pnl-Emit($bmp) {
    $st = $script:Pnl
    try {
        $ms = New-Object IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bytes = $ms.ToArray(); $ms.Dispose()
    } finally { $bmp.Dispose() }
    $md5 = [Security.Cryptography.MD5]::Create()
    $hash = [BitConverter]::ToString($md5.ComputeHash($bytes)); $md5.Dispose()
    if ($hash -eq $st.LastHash) { return }
    $st.LastHash = $hash
    $tmp = $st.FramePath + '.tmp'
    [IO.File]::WriteAllBytes($tmp, $bytes)
    $ok = $false
    for ($i = 0; $i -lt 40 -and -not $ok; $i++) {
        try {
            if (Test-Path -LiteralPath $st.FramePath) { [IO.File]::Delete($st.FramePath) }
            [IO.File]::Move($tmp, $st.FramePath); $ok = $true
        } catch { Start-Sleep -Milliseconds 10 }
    }
    if (-not $ok) { Pnl-Log 'could not replace _panel.png (game still reading it?)'; return }
    Pnl-Flag 'SkinLiveFrame'
    $st.FrameNo++
    if ($st.FrameOut) { [IO.File]::WriteAllBytes((Join-Path $st.FrameOut ('frame_{0:D4}.png' -f $st.FrameNo)), $bytes) }
}

# one frame with no edges at the last mouse position - the state as it now is
function Pnl-Settle {
    $st = $script:Pnl
    $st.Dirty = $false
    if (-not $st.Open) { return }
    Pnl-Emit (Pnl-Render (Pnl-NewInput $st.MX $st.MY) '')
}

function Pnl-Input([string]$verb, [double]$x, [double]$y, [int]$wheel) {
    $st = $script:Pnl
    $in = Pnl-NewInput $x $y
    if ($verb -eq 'd') {
        $in.Pressed = $true; $in.Down = $true; $st.Down = $true
        $st.PreSnap = Pnl-OpsSnap        # what an undo of this gesture returns to
    } elseif ($verb -eq 'u') {
        $in.Released = $true; $in.Down = $false; $st.Down = $false
    }
    $in.Wheel = $wheel
    $st.MX = $x; $st.MY = $y
    $bmp = Pnl-Render $in ''
    $cid = $st.Ui.LastCommitId
    if ($cid -and $cid.StartsWith('c:')) { [void]$st.Queue.Add(@{ kind = 'commit'; why = $cid }) }
    if ($verb -eq 'm' -and $st.Queue.Count -eq 0) { Pnl-Emit $bmp; return }
    $bmp.Dispose()
    Pnl-RunQueue
    Pnl-Settle
}

function Pnl-Queue([string]$kind, [string]$why) { [void]$script:Pnl.Queue.Add(@{ kind = $kind; why = $why }) }

function Pnl-RunQueue {
    $st = $script:Pnl
    # a queued action can queue more (add a layer -> commit); drain, don't recurse
    for ($guard = 0; $st.Queue.Count -gt 0 -and $guard -lt 8; $guard++) {
        $jobs = @($st.Queue); $st.Queue.Clear()
        $commit = @($jobs | Where-Object { $_.kind -eq 'commit' }).Count -gt 0
        foreach ($j in $jobs) { if ($j.kind -eq 'run' -and $j.block) { & $j.block } }
        if ($commit) { Pnl-Commit }
    }
}

# ============================================================== hero parts
function Pnl-SkinOf([string]$leaf) {
    if ($leaf -match '(?<!\d)(\d{7})(?!\d)') { return $Matches[1] }
    ''
}

function Pnl-Friendly([string]$leaf) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($leaf)
    $tok = @($stem.Split('_') | Where-Object { $_ })
    if ($tok.Count -gt 0 -and $tok[0] -eq 'T') { $tok = @($tok | Select-Object -Skip 1) }
    if ($tok.Count -gt 1) { $tok = @($tok | Select-Object -First ($tok.Count - 1)) }
    $prop = ($tok.Count -gt 0 -and $tok[0] -eq 'WP')
    $tok = @($tok | Where-Object { $_ -notmatch '^\d{4,}$' -and $_ -ne 'WP' })
    $name = ($tok -join ' ').Trim()
    if (-not $name) { $name = $stem }
    if ($prop) { $name = 'Prop: ' + $name }
    $name
}

function Pnl-RoleWord([string]$leaf) {
    $tok = ([IO.Path]::GetFileNameWithoutExtension($leaf)).Split('_')[-1].ToUpperInvariant()
    switch ($tok) { 'D' { 'Colour' } 'S' { 'Shine' } 'E' { 'Glow' } default { $tok } }
}

function Pnl-Veil([string]$text) {
    $st = $script:Pnl
    if (-not $st.Open -or $st.Drawing) { return }
    Pnl-Emit (Pnl-Render (Pnl-NewInput $st.MX $st.MY) $text)
}

function Pnl-EnsureSkinInfo([string]$sid) {
    $st = $script:Pnl
    if (-not $sid -or $st.SkinsLoaded.ContainsKey($sid)) { return }
    if (-not $st.Map) {
        $idx = SS-EnsureTexIndex { param($m) Pnl-Log $m }
        $st.Map = SS-LoadSkinMap $idx
    }
    if (-not $st.Map.skinLines.ContainsKey($sid)) { $st.SkinsLoaded[$sid] = ''; return }
    $ck = Join-Path $SS_Cache $sid
    if (-not (Test-Path -LiteralPath (Join-Path $ck 'thumbs.map'))) { Pnl-Veil 'Preparing this skin - first time only...' }
    $cache = SS-EnsureSkinCache $sid $st.Map.skinLines[$sid] { param($m) Pnl-Log $m } $null
    $tm = Join-Path $cache 'thumbs.map'
    if (-not (Test-Path -LiteralPath $tm)) { $st.SkinsLoaded[$sid] = ''; return }
    foreach ($line in [IO.File]::ReadAllLines($tm)) {
        $f = $line -split '\|'
        if ($f.Count -lt 4) { continue }
        $rel = $f[0]; $leaf = Split-Path $rel -Leaf
        $thumb = $f[1]
        $pv = Join-Path $cache ('pv\' + (Split-Path $thumb -Leaf))
        $st.Info[$rel.ToLowerInvariant()] = [pscustomobject]@{
            Leaf = $leaf; Rel = $rel; Skin = $sid; Thumb = $thumb
            Pv = $(if (Test-Path -LiteralPath $pv) { $pv } else { $thumb })
            Role = $f[3]; Src = (Join-Path $cache ('png\src\' + $rel)); Name = (Pnl-Friendly $leaf)
        }
    }
    $st.SkinsLoaded[$sid] = $cache
}

function Pnl-InfoByLeaf([string]$leaf) {
    $want = $leaf.ToLowerInvariant()
    foreach ($v in $script:Pnl.Info.Values) { if ($v.Leaf.ToLowerInvariant() -eq $want) { return $v } }
    $null
}
function Pnl-Info([string]$rel) {
    if (-not $rel) { return $null }
    $k = $rel.ToLowerInvariant()
    if ($script:Pnl.Info.ContainsKey($k)) { return $script:Pnl.Info[$k] }
    $null
}

function Pnl-ResolveParts {
    $st = $script:Pnl
    $skins = @{}
    foreach ($lf in $st.PartLeaves) { $sid = Pnl-SkinOf $lf; if ($sid) { $skins[$sid] = $true } }
    foreach ($sid in @($skins.Keys)) { Pnl-EnsureSkinInfo $sid }
    $parts = @()
    foreach ($lf in @($st.PartLeaves | Sort-Object -Unique)) {
        $i = Pnl-InfoByLeaf ($lf + '.png')
        if ($i) { $parts += $i }
    }
    $st.Parts = @($parts | Sort-Object { $_.Name.StartsWith('Prop') }, Name)
    Pnl-Log ('hero has {0} colour part(s): {1}' -f $st.Parts.Count, ((@($st.Parts) | ForEach-Object { $_.Name }) -join ', '))
    Pnl-PickDesign
}

# the D/S/E maps that belong together: T_x_Body_D, T_x_Body_S, T_x_Body_E
function Pnl-Siblings($part) {
    $out = @()
    $stem = [IO.Path]::GetFileNameWithoutExtension($part.Rel)
    $base = $stem.Substring(0, $stem.LastIndexOf('_'))
    $dir = [IO.Path]::GetDirectoryName($part.Rel)
    foreach ($r in @('D', 'S', 'E')) {
        $i = Pnl-Info (Join-Path $dir ($base + '_' + $r + '.png'))
        if ($i) { $out += $i }
    }
    if ($out.Count -eq 0) { $out = @($part) }
    $out
}

function Pnl-Main {
    # the hero's base BaseColor map - the one the part list was built from
    $st = $script:Pnl
    $p = Pnl-Info $st.Rel
    if (-not $p) { return $null }
    $sib = @(Pnl-Siblings $p)
    $sib[0]
}

# ============================================================== the design
# JSON -> editable dictionaries. The doc and its ops map stay [ordered] so the
# file keeps its shape; everything deeper - the layers - must be a plain
# [hashtable], because skinlib's SS-OpVal only recognises [hashtable] and reads
# an OrderedDictionary as "no such setting" (every layer then renders as a
# white tint and labels as '?').
function Pnl-ToHash($o, [int]$depth = 0) {
    if ($null -eq $o) { return $null }
    if ($o -is [System.Management.Automation.PSCustomObject]) {
        $h = if ($depth -lt 2) { [ordered]@{} } else { @{} }
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = Pnl-ToHash $p.Value ($depth + 1) }
        return $h
    }
    if (($o -is [System.Collections.IList]) -and -not ($o -is [string])) {
        $l = New-Object System.Collections.ArrayList
        foreach ($i in $o) { [void]$l.Add((Pnl-ToHash $i ($depth + 1))) }
        return ,$l
    }
    $o
}

# the live design - live_preview's $Design - reloaded when anything else saves it
function Pnl-Doc {
    $st = $script:Pnl
    $path = [string]$script:Design
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { $st.Doc = $null; $st.DocPath = ''; return $null }
    $stamp = (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
    if ($st.Doc -and $st.DocPath -eq $path -and $st.DocStamp -eq $stamp) { return $st.Doc }
    try {
        $doc = Pnl-ToHash (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
        if (-not $doc.Contains('ops') -or -not $doc['ops']) { $doc['ops'] = [ordered]@{} }
        $st.Doc = $doc; $st.DocPath = $path; $st.DocStamp = $stamp
        if ($st.Undo.Count -gt 0 -and $st.UndoPath -ne $path) { $st.Undo.Clear() }
        $st.UndoPath = $path
    } catch {
        $st.Status = 'Could not read ' + (Split-Path $path -Leaf) + ': ' + $_.Exception.Message; $st.Warn = $true
        $st.Doc = $null
    }
    $st.Doc
}

function Pnl-SaveDoc {
    $st = $script:Pnl
    if (-not $st.Doc -or -not $st.DocPath) { return }
    $json = $st.Doc | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($st.DocPath, $json, (New-Object System.Text.UTF8Encoding($true)))
    $st.DocStamp = (Get-Item -LiteralPath $st.DocPath).LastWriteTimeUtc.Ticks
}

function Pnl-OpsSnap {
    $doc = Pnl-Doc
    if (-not $doc) { return '' }
    $doc['ops'] | ConvertTo-Json -Depth 12 -Compress
}

# does the live design belong to the hero on screen?
function Pnl-DocMatches {
    $st = $script:Pnl
    $doc = Pnl-Doc
    if (-not $doc) { return $false }
    $skins = @($st.Parts | ForEach-Object { $_.Skin } | Sort-Object -Unique)
    if ($skins.Count -eq 0) { return $true }
    $heroes = @($skins | ForEach-Object { $_.Substring(0, 4) } | Sort-Object -Unique)
    if ($heroes -contains [string]$doc['hero']) { return $true }
    foreach ($k in @($doc['ops'].Keys)) { foreach ($s in $skins) { if ($k.Contains($s)) { return $true } } }
    $false
}

function Pnl-MainSkin {
    $st = $script:Pnl
    $counts = @{}
    foreach ($p in $st.Parts) { if ($p.Name -notlike 'Prop:*') { $counts[$p.Skin] = 1 + [int]$counts[$p.Skin] } }
    if ($counts.Count -eq 0) { foreach ($p in $st.Parts) { $counts[$p.Skin] = 1 + [int]$counts[$p.Skin] } }
    if ($counts.Count -eq 0) { return '' }
    (@($counts.GetEnumerator() | Sort-Object Value -Descending))[0].Key
}

function Pnl-HeroName([string]$hero) {
    $p = Join-Path $SS_Root 'heroes.json'
    try {
        $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
        $v = $j.PSObject.Properties[$hero]
        if ($v) { return [string]$v.Value }
    } catch {}
    'Hero ' + $hero
}

function Pnl-SkinTitle {
    $sid = Pnl-MainSkin
    if (-not $sid) { return 'no hero found yet' }
    $skinName = SS-SkinName $sid
    if (-not $skinName) { $skinName = $sid }
    '{0}  {1}  {2}' -f (Pnl-HeroName $sid.Substring(0, 4)), [char]0x00B7, $skinName
}

function Pnl-DocTitle {
    $doc = Pnl-Doc
    if (-not $doc) { return '(none)' }
    $n = [string]$doc['displayName']
    if (-not $n) { $n = [string]$doc['modName'] }
    $n
}

# Does a design paint any of these skins? Its own skin, or an edit filed under
# one of them (a costume design carries its recolours' edits too).
function Pnl-DesignCovers([string]$skin, [string[]]$keys, [string[]]$skins) {
    foreach ($s in $skins) {
        if (-not $s) { continue }
        if ($skin -eq $s) { return $true }
        foreach ($k in $keys) { if ($k.Contains('\' + $s + '\') -or $k.Contains('/' + $s + '/')) { return $true } }
    }
    $false
}

# what a design file covers, read once per save (60+ designs, every spawn)
function Pnl-DesignFacts([IO.FileInfo]$f) {
    $st = $script:Pnl
    $stamp = $f.LastWriteTimeUtc.Ticks
    $c = $st.DesignIndex[$f.FullName]
    if ($c -and $c.Stamp -eq $stamp) { return $c }
    $c = @{ Stamp = $stamp; Hero = ''; Skin = ''; Keys = @() }
    try {
        $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        $c.Hero = [string]$j.hero; $c.Skin = [string]$j.skin
        if ($j.ops) { $c.Keys = @($j.ops.PSObject.Properties | ForEach-Object { $_.Name }) }
    } catch {}
    $st.DesignIndex[$f.FullName] = $c
    $c
}

# When the hero arrives: follow the newest design saved for THIS SKIN; if there
# is none, keep a design for this hero, else take the newest for the hero.
# Never creates one - that waits for an edit. (It used to stop at "same hero",
# so a second skin of a hero stayed vanilla behind the first skin's design.)
function Pnl-PickDesign {
    $st = $script:Pnl
    # live preview off: nothing goes on the hero; turning it on re-announces
    if (-not $st.LiveOn) { return }
    $skins = @($st.Parts | ForEach-Object { $_.Skin } | Where-Object { $_ } | Sort-Object -Unique)
    $sid = Pnl-MainSkin
    if (-not $sid -or $skins.Count -eq 0) { return }
    $doc = Pnl-Doc
    if ($doc -and (Pnl-DesignCovers ([string]$doc['skin']) @($doc['ops'].Keys) $skins)) { return }
    $hero = $sid.Substring(0, 4)
    $bySkin = $null; $byHero = $null
    foreach ($f in @(Get-ChildItem -LiteralPath $st.DesignDir -Filter *.json -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)) {
        $c = Pnl-DesignFacts $f
        if (Pnl-DesignCovers $c.Skin $c.Keys $skins) { $bySkin = $f.FullName; break }
        if (-not $byHero -and $c.Hero -eq $hero) { $byHero = $f.FullName }
    }
    $best = $bySkin
    if (-not $best -and -not (Pnl-DocMatches)) { $best = $byHero }
    if ($best -and $best -ne $st.DocPath) {
        Pnl-Log ('following {0} for this {1}' -f (Split-Path $best -Leaf), $(if ($bySkin) { 'skin' } else { 'hero' }))
        Pnl-SwitchDesign $best
    }
}

# an automatic announce that found no hero mesh yet (it attaches a moment
# after the pawn spawns): drop the game's marker so it asks again next second
# - 15 times per pawn at most, so a pawn with no hero never loops for good
function Pnl-AutoRetry {
    $st = $script:Pnl
    $pawn = $st.Auto; $st.Auto = ''
    if (-not $pawn) { return }
    $n = 1 + [int]$st.AutoTries[$pawn]
    $st.AutoTries[$pawn] = $n
    if ($n -gt 15) { return }
    $f = Join-Path $st.SaveDir ('SLA_' + $pawn + '.sav')
    if (Test-Path -LiteralPath $f) { try { [IO.File]::Delete($f) } catch {} }
}

# A hero the game announced on its own - it just spawned: every texture the
# live design has live goes onto it now, the same set F6 loads, no key pressed.
# Pnl-PickDesign (in Pnl-ResolveParts) already moved to this hero's design.
function Pnl-AutoApply {
    $st = $script:Pnl
    $pawn = $st.Auto; $st.Auto = ''
    if (-not $st.LiveOn) { return 0 }
    $skins = @($st.Parts | ForEach-Object { $_.Skin } | Where-Object { $_ } | Sort-Object -Unique)
    $n = 0
    $lf = Join-Path $st.LiveDir '_live.txt'
    if ((Pnl-Doc) -and (Test-Path -LiteralPath $lf)) {
        foreach ($ln in [IO.File]::ReadAllLines($lf)) {
            if (-not $ln -or $ln.StartsWith('#')) { continue }
            $f = $ln -split '\|'
            if ($f.Count -lt 5 -or $f[4] -ne 'live') { continue }
            # only what this hero wears (column 2 = the texture's skin; '' = unknown, sent)
            if ($f[1] -and $skins.Count -and $skins -notcontains $f[1]) { continue }
            Pnl-Flag ('SLT_' + [IO.Path]::GetFileNameWithoutExtension($f[0])); $n++
        }
    }
    if ($n) {
        Pnl-Flag 'SkinLiveTex'
        Pnl-Log ('hero spawned ({0}): {1} texture(s) of {2} going on' -f $pawn, $n, (Pnl-DocTitle))
    } else {
        Pnl-Log ('hero spawned ({0}): no design paints {1} - it stays as it is' -f $pawn, ($skins -join ', '))
    }
    $n
}

function Pnl-SwitchDesign([string]$path) {
    $st = $script:Pnl
    (Get-Item -LiteralPath $path).LastWriteTimeUtc = [DateTime]::UtcNow     # newest wins in -WatchDesigns
    Pnl-Veil ('Loading ' + [IO.Path]::GetFileNameWithoutExtension($path) + '...')
    $null = Update-Live $path
    $st.Undo.Clear()
    $st.Status = 'Now editing ' + (Pnl-DocTitle); $st.Warn = $false
    $st.Dirty = $true
}

function Pnl-NewDesign {
    $st = $script:Pnl
    $sid = Pnl-MainSkin
    if (-not $sid) { $st.Status = 'No hero found - open the panel in a match or the practice range.'; $st.Warn = $true; return $false }
    $skinName = SS-SkinName $sid
    $clean = ($skinName -replace '[^A-Za-z0-9]', '')
    if (-not $clean) { $clean = $sid }
    $base = 'InGame' + $clean
    $name = $base; $n = 2
    while (Test-Path -LiteralPath (Join-Path $st.DesignDir ($name + '.json'))) { $name = $base + $n; $n++ }
    $doc = [ordered]@{
        modName = $name
        displayName = ('In-game ' + $(if ($skinName) { $skinName } else { $sid })) + $(if ($n -gt 2) { ' ' + ($n - 1) } else { '' })
        hero = $sid.Substring(0, 4)
        skin = $sid
        chromaSkins = @()
        ops = [ordered]@{}
        colorOps = [ordered]@{}
    }
    $path = Join-Path $st.DesignDir ($name + '.json')
    [IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($true)))
    Pnl-Log "new design $name"
    Pnl-SwitchDesign $path
    $st.Status = 'New design: designs\' + $name + '.json'
    $true
}

# every edit needs a design; the first edit on a hero without one makes it
function Pnl-EnsureDoc {
    if ((Pnl-Doc) -and (Pnl-DocMatches)) { return $true }
    Pnl-NewDesign
}

function Pnl-Layers([string]$rel) {
    $doc = Pnl-Doc
    if (-not $doc -or -not $rel) { return $null }
    $ops = $doc['ops']
    if (-not $ops.Contains($rel)) { return $null }
    $v = $ops[$rel]
    if ($v -is [System.Collections.IList]) { return ,$v }
    # legacy single-layer or {layers:[...]} form: normalise in place
    $l = New-Object System.Collections.ArrayList
    if ($v -is [System.Collections.IDictionary] -and $v.Contains('layers')) { foreach ($x in $v['layers']) { [void]$l.Add($x) } }
    else { [void]$l.Add($v) }
    $ops[$rel] = $l
    ,$l
}

function Pnl-EnsureLayers([string]$rel) {
    $l = Pnl-Layers $rel
    if ($null -ne $l) { return ,$l }
    $l = New-Object System.Collections.ArrayList
    (Pnl-Doc)['ops'][$rel] = $l
    ,$l
}

function Pnl-DropIfEmpty([string]$rel) {
    $l = Pnl-Layers $rel
    if ($null -ne $l -and $l.Count -eq 0) { (Pnl-Doc)['ops'].Remove($rel) }
}

function Pnl-LastColor {
    if ($script:Pnl.Recent.Count -gt 0) { return [string]$script:Pnl.Recent[0] }
    '#FF4FC3'
}

function Pnl-NewLayer([string]$mode) {
    $c = Pnl-LastColor
    @{ mode = $mode; color = $c; strength = 1.0; hueShift = 0.0; satMul = 1.0; lightMul = 1.0; protectSkin = $false }
}

function Pnl-FillMode($L, [string]$mode) {
    $L['mode'] = $mode
    if (-not $L.Contains('strength')) { $L['strength'] = 1.0 }
    if ($mode -in @('tint', 'paint', 'huerange', 'gradtint', 'gradpaint') -and -not $L['color']) { $L['color'] = Pnl-LastColor }
    if ($mode -in @('gradtint', 'gradpaint')) {
        if (-not $L['color2']) { $L['color2'] = '#FFFFFF' }
        if (-not $L['gradDir']) { $L['gradDir'] = 'v' }
        if ($L['gradDir'] -eq 'corners') {
            if (-not $L['color3']) { $L['color3'] = $L['color'] }
            if (-not $L['color4']) { $L['color4'] = $L['color2'] }
        }
    }
    if ($mode -eq 'hueshift' -and [double]$L['hueShift'] -eq 0) { $L['hueShift'] = 30.0 }
    if ($mode -eq 'hsl') { foreach ($k in @('satMul', 'lightMul')) { if (-not $L.Contains($k)) { $L[$k] = 1.0 } } }
    if ($mode -eq 'huerange') {
        if (-not $L.Contains('bandCenter')) { $L['bandCenter'] = -1.0 }
        if (-not $L.Contains('bandWidth')) { $L['bandWidth'] = 0.0 }
    }
}

function Pnl-CopyLayers($layers) {
    $l = New-Object System.Collections.ArrayList
    foreach ($x in $layers) {
        $c = @{}
        foreach ($k in $x.Keys) { $c[$k] = $x[$k] }
        [void]$l.Add($c)
    }
    ,$l
}

function Pnl-Remember([string]$hex) {
    $st = $script:Pnl
    if (-not $hex) { return }
    $hex = $hex.ToUpperInvariant()
    $st.Recent.Remove($hex)
    $st.Recent.Insert(0, $hex)
    # 16 = two rows: with the palette gone the history is the quick pick
    while ($st.Recent.Count -gt 16) { $st.Recent.RemoveAt(16) }
    try { [IO.File]::WriteAllLines((Join-Path $st.WorkDir 'recent_colors.txt'), [string[]]@($st.Recent)) } catch {}
}

# save -> render the textures that changed -> flag them for the game
function Pnl-Commit {
    $st = $script:Pnl
    if (-not $st.Doc) { return }
    if ($st.PreSnap -and $st.PreSnap -ne (Pnl-OpsSnap)) {
        [void]$st.Undo.Add($st.PreSnap)
        while ($st.Undo.Count -gt 50) { $st.Undo.RemoveAt(0) }
    }
    $st.PreSnap = Pnl-OpsSnap
    Pnl-SaveDoc
    Pnl-Veil 'Painting...'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $changed = @()
    try { $changed = @(Update-Live $st.DocPath) }
    catch { $st.Status = 'Could not paint: ' + $_.Exception.Message; $st.Warn = $true; Pnl-Log $st.Status; return }
    $sw.Stop()
    if ($changed.Count -gt 0) {
        $st.Status = 'Painted {0} texture(s) in {1:0.0} s - the hero updates by itself' -f $changed.Count, $sw.Elapsed.TotalSeconds
    } else {
        $st.Status = 'Saved - nothing needed repainting'
    }
    $st.Warn = $false
    $st.Dirty = $true
}
function Pnl-AllLayersOf([string]$rel) { $l = Pnl-Layers $rel; if ($null -eq $l) { return @() }; @($l) }

function Pnl-Undo {
    $st = $script:Pnl
    if ($st.Undo.Count -eq 0) { $st.Status = 'Nothing to undo'; $st.Warn = $false; return }
    $snap = [string]$st.Undo[$st.Undo.Count - 1]
    $st.Undo.RemoveAt($st.Undo.Count - 1)
    $doc = Pnl-Doc
    $ops = if ($snap) { Pnl-ToHash ($snap | ConvertFrom-Json) } else { [ordered]@{} }
    if ($null -eq $ops) { $ops = [ordered]@{} }
    $doc['ops'] = $ops
    $st.PreSnap = ''
    Pnl-SaveDoc
    Pnl-Veil 'Undoing...'
    $null = Update-Live $st.DocPath
    $st.Status = 'Undone ({0} more step(s) back)' -f $st.Undo.Count; $st.Warn = $false
    # the open layer may no longer exist (the part screen clamps it too)
    $l = Pnl-Layers $st.Rel
    $n = if ($null -eq $l) { 0 } else { $l.Count }
    if ($st.Layer -ge $n) { $st.Layer = [Math]::Max(0, $n - 1) }
    $st.HsvKey = ''
    $st.Dirty = $true
}

# ask the game to re-import every texture this design has live
function Pnl-ReloadAll {
    $st = $script:Pnl
    $leaves = @(Get-ChildItem -LiteralPath $st.LiveDir -Filter 'T_*.png' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    Pnl-FlagLeaves $leaves
    $st.Status = 'Asked the game to reload {0} texture(s)' -f $leaves.Count; $st.Warn = $false
}

function Pnl-CloseFromPanel {
    $st = $script:Pnl
    Pnl-Flag 'SkinLiveClose'
    $st.Open = $false
}

# ============================================================== previews
# a small working copy of the vanilla map, so the "yours" preview can be
# re-rendered on every drag step in a few milliseconds
function Pnl-BaseThumb($part) {
    $st = $script:Pnl
    $dst = Join-Path $st.WorkDir ('base\' + $part.Leaf)
    if (Test-Path -LiteralPath $dst) { return $dst }
    $srcImg = if (Test-Path -LiteralPath $part.Pv) { $part.Pv } else { $part.Thumb }
    if (-not (Test-Path -LiteralPath $srcImg)) { return '' }
    $b = [SkinArt]::Load($srcImg)
    try {
        $side = 200
        $sc = [Math]::Min(1.0, $side / [Math]::Max($b.Width, $b.Height))
        $w = [Math]::Max(1, [int]($b.Width * $sc)); $h = [Math]::Max(1, [int]($b.Height * $sc))
        $small = New-Object System.Drawing.Bitmap $w, $h
        $gfx = [System.Drawing.Graphics]::FromImage($small)
        $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gfx.DrawImage($b, 0, 0, $w, $h); $gfx.Dispose()
        $small.Save($dst, [System.Drawing.Imaging.ImageFormat]::Png); $small.Dispose()
    } finally { $b.Dispose() }
    $dst
}

function Pnl-AfterThumb($part) {
    $st = $script:Pnl
    $base = Pnl-BaseThumb $part
    if (-not $base) { return '' }
    $layers = Pnl-Layers $part.Rel
    if ($null -eq $layers -or $layers.Count -eq 0) { return $base }
    $sig = ($layers | ConvertTo-Json -Depth 8 -Compress)
    $md5 = [Security.Cryptography.MD5]::Create()
    $h = ([BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($sig + $part.Leaf))) -replace '-', '').Substring(0, 12)
    $md5.Dispose()
    $dst = Join-Path $st.WorkDir ('thumbs\' + $h + '.png')
    if (-not (Test-Path -LiteralPath $dst)) {
        try {
            $bmp = SS-RenderStack $base $layers
            try { $bmp.Save($dst, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }
        } catch { return $base }
        # keep the preview cache small
        $all = @(Get-ChildItem -LiteralPath (Join-Path $st.WorkDir 'thumbs') -File | Sort-Object LastWriteTimeUtc)
        if ($all.Count -gt 300) { foreach ($f in $all[0..($all.Count - 200)]) { $st.Ui.ForgetImage($f.FullName); Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue } }
    }
    $dst
}

function Pnl-LayerChip($L) {
    $mode = [string]$L['mode']
    if ($mode -in @('tint', 'paint', 'huerange', 'gradtint', 'gradpaint') -and $L['color']) { return [SkinPanel]::Hex([string]$L['color']) }
    [System.Drawing.Color]::Empty
}

function Pnl-PartChips($part) {
    $chips = New-Object System.Collections.Generic.List[System.Drawing.Color]
    foreach ($sib in @(Pnl-Siblings $part)) {
        foreach ($L in @(Pnl-AllLayersOf $sib.Rel)) {
            foreach ($k in @('color', 'color2', 'color3', 'color4')) {
                if ($L[$k] -and [string]$L['mode'] -in @('tint', 'paint', 'huerange', 'gradtint', 'gradpaint') -and $chips.Count -lt 4) {
                    $chips.Add([SkinPanel]::Hex([string]$L[$k]))
                }
            }
        }
    }
    , $chips.ToArray()
}

function Pnl-PartSummary($part) {
    $bits = @()
    foreach ($sib in @(Pnl-Siblings $part)) {
        $ls = @(Pnl-AllLayersOf $sib.Rel)
        if ($ls.Count -eq 0) { continue }
        $txt = ($ls | ForEach-Object { SS-OpLabel $_ }) -join ' + '
        if ($sib.Rel -ne $part.Rel) { $txt = (Pnl-RoleWord $sib.Leaf) + ': ' + $txt }
        $bits += $txt
    }
    if ($bits.Count -eq 0) { return 'vanilla' }
    $bits -join '   |   '
}

# ============================================================== navigation
function Pnl-Go([string]$screen) {
    $st = $script:Pnl
    $st.Screen = $screen
    $st.HsvKey = ''
    if ($screen -eq 'designs') { Pnl-LoadDesignList }
    if ($screen -eq 'images') { Pnl-LoadImageList }
    $st.Ui.ScrollTo($screen, 0)
}

# Two levels, not three: the part screen IS the editor. Its layers are tabs and
# the selected layer's controls sit right under them, so opening a part shows
# colours straight away. ('layer' is kept as an alias of 'part'.)
function Pnl-OpenPart([string]$rel) { $st = $script:Pnl; $st.Rel = $rel; $st.Layer = 0; $st.Slot = 'color'; Pnl-Go 'part' }
function Pnl-OpenLayer([int]$i) { $st = $script:Pnl; $st.Layer = $i; $st.Slot = 'color'; $st.HsvKey = ''; if ($st.Screen -ne 'part') { Pnl-Go 'part' } }

# the D/S/E maps of one part share this: <dir>\T_x_Body
function Pnl-PartBase([string]$rel) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($rel)
    $i = $stem.LastIndexOf('_')
    if ($i -gt 0) { $stem = $stem.Substring(0, $i) }
    (Join-Path ([IO.Path]::GetDirectoryName($rel)) $stem).ToLowerInvariant()
}

# Add a layer to the open map and select it. Runs after the frame (Pnl-Run):
# the first edit on a hero with no design creates one, which renders.
function Pnl-AddLayer([string]$mode, [string]$color) {
    $st = $script:Pnl
    if (-not (Pnl-EnsureDoc)) { return }
    # $stack and $lay, never $l and $L: PowerShell names are case-insensitive
    $stack = Pnl-EnsureLayers $st.Rel
    $lay = Pnl-NewLayer 'tint'
    if ($color) { $lay['color'] = $color; Pnl-Remember $color }
    Pnl-FillMode $lay $mode
    [void]$stack.Add($lay)
    Pnl-OpenLayer ($stack.Count - 1)
    # an image layer is not worth painting until it has an image (and backing
    # out of the picker removes it again - Pnl-ImageBack)
    if ($mode -eq 'replace') { $st.ImageUndo = ''; Pnl-Go 'images'; return }
    Pnl-Commit
}

function Pnl-Ask([string]$question, [string]$yes, [scriptblock]$action, [string]$back) {
    $script:Pnl.Confirm = @{ q = $question; yes = $yes; action = $action; back = $back }
    Pnl-Go 'confirm'
}

function Pnl-LoadDesignList {
    $st = $script:Pnl
    $sid = Pnl-MainSkin
    $hero = if ($sid) { $sid.Substring(0, 4) } else { '' }
    $list = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $st.DesignDir -Filter *.json -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)) {
        try { $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { continue }
        if ($hero -and [string]$j.hero -ne $hero) { continue }
        $n = 0; if ($j.ops) { $n = @($j.ops.PSObject.Properties).Count }
        $title = [string]$j.displayName; if (-not $title) { $title = [string]$j.modName }
        $chips = New-Object System.Collections.Generic.List[System.Drawing.Color]
        if ($j.ops) {
            foreach ($p in $j.ops.PSObject.Properties) {
                foreach ($L in @($p.Value)) {
                    if ($chips.Count -ge 5) { break }
                    if ($L.color -and [string]$L.mode -in @('tint', 'paint', 'huerange', 'gradtint', 'gradpaint')) { $chips.Add([SkinPanel]::Hex([string]$L.color)) }
                }
            }
        }
        $list += [pscustomobject]@{ Path = $f.FullName; Title = $title; Sub = ('{0} texture edit(s)  -  saved {1:d MMM, HH:mm}' -f $n, $f.LastWriteTime); Chips = $chips.ToArray() }
    }
    $st.DesignList = $list
}

function Pnl-LoadImageList {
    $st = $script:Pnl
    $sid = Pnl-MainSkin
    $dirs = @((Join-Path $SS_Root 'images'), (Join-Path $SS_Root ('work\edit\' + $sid)), (Join-Path $SS_Root ('work\chroma\' + $sid)))
    New-Item -ItemType Directory -Force -Path $dirs[0] | Out-Null
    $list = @()
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.png', '.jpg', '.jpeg', '.bmp') } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 60)) {
            $list += [pscustomobject]@{ Path = $f.FullName; Title = $f.Name; Sub = (Split-Path $d -Leaf) + ' folder' }
        }
    }
    $st.ImageList = $list
}

function Pnl-ImageThumb([string]$path) {
    $st = $script:Pnl
    $md5 = [Security.Cryptography.MD5]::Create()
    $h = ([BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($path))) -replace '-', '').Substring(0, 12)
    $md5.Dispose()
    $dst = Join-Path $st.WorkDir ('thumbs\img_' + $h + '.png')
    if (Test-Path -LiteralPath $dst) { return $dst }
    try {
        $b = [SkinArt]::Load($path)
        try {
            $sc = [Math]::Min(1.0, 96.0 / [Math]::Max($b.Width, $b.Height))
            $w = [Math]::Max(1, [int]($b.Width * $sc)); $hh = [Math]::Max(1, [int]($b.Height * $sc))
            $small = New-Object System.Drawing.Bitmap $w, $hh
            $gfx = [System.Drawing.Graphics]::FromImage($small)
            $gfx.DrawImage($b, 0, 0, $w, $hh); $gfx.Dispose()
            $small.Save($dst, [System.Drawing.Imaging.ImageFormat]::Png); $small.Dispose()
        } finally { $b.Dispose() }
    } catch { return '' }
    $dst
}

# linked maps: the same artwork shipped under another name (other forms, lobby
# copies). Sure = only ids differ; Maybe = a different prefix, maybe another object.
function Pnl-LinksFor($part) {
    $st = $script:Pnl
    if (-not $st.Links.ContainsKey($part.Skin)) {
        $rels = @($st.Info.Values | Where-Object { $_.Skin -eq $part.Skin -and $_.Role -ne 'tech' } | ForEach-Object { $_.Rel })
        $st.Links[$part.Skin] = SS-LinkGroups $rels
    }
    $g = $st.Links[$part.Skin]
    if ($g.ContainsKey($part.Rel)) { return $g[$part.Rel] }
    $null
}

function Pnl-CopyTo([string[]]$targets, [string]$what) {
    $st = $script:Pnl
    $src = Pnl-Layers $st.Rel
    if ($null -eq $src -or $src.Count -eq 0) { $st.Status = 'Nothing to copy - this map has no layers.'; $st.Warn = $true; return }
    $doc = Pnl-Doc
    $n = 0
    foreach ($t in $targets) {
        if (-not $t -or $t -eq $st.Rel) { continue }
        $doc['ops'][$t] = Pnl-CopyLayers $src
        $n++
    }
    $st.Status = 'Copied to {0} {1}' -f $n, $what
    Pnl-Queue 'commit' 'copy'
}

function Pnl-CopyToChromas {
    $st = $script:Pnl
    $part = Pnl-Info $st.Rel
    Pnl-Veil 'Finding the other colourways...'
    $ct = SS-ChromaTargets $part.Skin { param($m) Pnl-Log $m }
    $skins = @(@($ct.Sure) + @($ct.Maybe) | Where-Object { $_ } | Sort-Object -Unique)
    if ($skins.Count -eq 0) { $st.Status = 'This skin has no other colourways.'; $st.Warn = $false; return }
    $targets = @()
    foreach ($t in $skins) {
        Pnl-EnsureSkinInfo $t
        $rel2 = SS-RelForSkin $st.Rel $part.Skin $t
        if (Pnl-Info $rel2) { $targets += $rel2 }
    }
    $doc = Pnl-Doc
    $cs = New-Object System.Collections.ArrayList
    foreach ($x in @($doc['chromaSkins'])) { if ($x) { [void]$cs.Add([string]$x) } }
    foreach ($t in $skins) { if (-not $cs.Contains($t)) { [void]$cs.Add($t) } }
    $doc['chromaSkins'] = $cs
    Pnl-CopyTo $targets 'other colourway(s)'
}

# ============================================================== Build mod
# The in-game Build mod button. build_skin.ps1 runs in the background (a hidden
# window - a visible one would take focus from the game), then the mod goes in.
# Her rule (2026-09-27): a build replaces the skin in the RUNNING game only when
# Project Galacta is installed - its F7 unload / reload swaps the real mod in
# (galacta.ps1), phases building -> galacta -> done. Without Galacta it is
# installed for the next launch and the hero is left alone: building ->
# installing -> done. Either way it can end failed.
# The old no-Galacta live pak (livepak.ps1: the built textures renamed to fresh
# paths, mounted with NePatchUtility.MountPak) is no longer started; the
# 'mounting' / 'loading' handling below is its leftover, unused for now.

function Pnl-GameRunning {
    $st = $script:Pnl
    if ($st.GameProc) { return [bool](Get-Process -Name $st.GameProc -ErrorAction SilentlyContinue) }
    SS-GameRunning
}

# the mods one design builds into - one per skin (her rule), named exactly as
# build_skin.ps1 names them
function Pnl-ModsOf($dj) {
    $parts = @(SS-SplitDesignBySkin $dj)
    $names = if ($parts.Count -ge 2) { @($parts | ForEach-Object { [string]$_.doc.modName }) } else { @([string]$dj.modName) }
    @($names | ForEach-Object { $_ -replace '[^A-Za-z0-9]', '' } | Where-Object { $_ })
}

function Pnl-DocHasEdits($doc) {
    if (-not $doc) { return $false }
    $n = @($doc['ops'].Keys).Count
    if ($doc.Contains('colorOps') -and $doc['colorOps'] -is [System.Collections.IDictionary]) { $n += @($doc['colorOps'].Keys).Count }
    $n -gt 0
}

# installs waiting for the game to let go of the old copy. The file belongs to
# its install folder: a test run (RS_PNL_MODSDIR) shares work\ingame with the
# real studio, and its list must never be installed into the real ~mods.
function Pnl-PendingFile {
    $st = $script:Pnl
    if ($st.ModsDir -eq (Join-Path $SS_Paks '~mods')) { return Join-Path $st.WorkDir 'pending_install.txt' }
    $md5 = [Security.Cryptography.MD5]::Create()
    $h = ([BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($st.ModsDir.ToLowerInvariant()))) -replace '-', '').Substring(0, 8)
    $md5.Dispose()
    Join-Path $st.WorkDir ('pending_install_{0}.txt' -f $h)
}
function Pnl-LoadPending {
    $f = Pnl-PendingFile
    $script:Pnl.Pending = @()
    if (Test-Path -LiteralPath $f) { $script:Pnl.Pending = @([IO.File]::ReadAllLines($f) | Where-Object { $_ -match '^[A-Za-z0-9]+$' } | Sort-Object -Unique) }
}
function Pnl-SavePending {
    $f = Pnl-PendingFile
    $p = @($script:Pnl.Pending | Sort-Object -Unique)
    if ($p.Count) { [IO.File]::WriteAllLines($f, [string[]]$p) } elseif (Test-Path -LiteralPath $f) { [IO.File]::Delete($f) }
}

# Each built mod's triplet goes loose into ~mods, where build_skin installs. A
# mod the game mounted at boot is open, so busy: that one waits for
# Pnl-InstallPending, which installs it the moment the game is gone. Nothing is
# ever half-replaced (SS-SwapInstall, galacta.ps1: staged outside Paks, the old
# copy renamed aside - which fails, changing nothing, while the game holds it -
# then the new one renamed in; renames also never write through a hard link).
# It replaced an exclusive-open "is it locked?" probe, which could itself make
# the game's own open fail if it landed mid-mount.
function Pnl-InstallMods([string[]]$mods) {
    $st = $script:Pnl
    $r = @{ Now = @(); Pending = @(); Missing = @() }
    foreach ($mod in @($mods)) {
        switch (SS-SwapInstall $mod (Join-Path $SS_Root ('work\{0}\out' -f $mod)) $st.ModsDir) {
            'now'   { $r.Now += $mod }
            'busy'  { $r.Pending += $mod }
            default { $r.Missing += $mod }
        }
    }
    $r
}
function Pnl-InstallPending {
    $st = $script:Pnl
    if (@($st.Pending).Count -eq 0) { return }
    $r = Pnl-InstallMods $st.Pending
    if ($r.Now.Count) { Pnl-Log ('installed now that the game is closed: {0}' -f ($r.Now -join ', ')) }
    if ($r.Missing.Count) { Pnl-Log ('pending install dropped, no built files: {0}' -f ($r.Missing -join ', ')) }
    $st.Pending = @($r.Pending)
    Pnl-SavePending
    $j = $st.Job
    if ($j -and $j.Install -eq 'pending' -and @($j.Mods | Where-Object { $st.Pending -contains $_ }).Count -eq 0) {
        $j.Install = 'now'; $j.InstallNote = 'Installed once Rivals closed - it loads at every launch.'
        $st.Dirty = $true
    }
}

# Maps she edited whose certain twin (another form, the lobby copy) is still
# vanilla - the same last line of defence the desktop's BUILD MOD has, since
# the mod would only half-change in game. @{ From; To } pairs.
function Pnl-BuildGaps {
    $st = $script:Pnl
    $doc = Pnl-Doc
    $pairs = New-Object System.Collections.ArrayList
    if (-not $doc) { return ,$pairs }
    $ops = $doc['ops']
    foreach ($rel in @($ops.Keys)) {
        $sid = Pnl-SkinOf $rel
        if ($sid -and -not $st.SkinsLoaded.ContainsKey($sid)) { Pnl-EnsureSkinInfo $sid }
        $part = Pnl-Info $rel
        if (-not $part) { continue }
        $lk = Pnl-LinksFor $part
        if (-not $lk -or -not $lk.Sure) { continue }
        foreach ($t in @($lk.Others)) {
            if (-not $t -or $ops.Contains($t)) { continue }
            if (@($pairs | Where-Object { $_.To -eq $t }).Count) { continue }
            [void]$pairs.Add(@{ From = $rel; To = $t })
        }
    }
    ,$pairs
}

function Pnl-OpenBuild {
    Pnl-Go 'build'
    $j = $script:Pnl.Job
    if ($j -and $j.Phase -notin @('done', 'failed')) { return }
    # reading the design and checking linked maps can load a skin cache -
    # after the frame, never inside the draw
    Pnl-Run {
        $s = $script:Pnl
        $s.BuildMods = @()
        try { $s.BuildMods = @(Pnl-ModsOf (Get-Content -LiteralPath $s.DocPath -Raw | ConvertFrom-Json)) } catch {}
        # no @() round it: @(f) of a function returning ,$list is ONE element
        $s.BuildGaps = Pnl-BuildGaps; $s.BuildGapsFor = $s.DocPath
        $s.Dirty = $true
    }
}

function Pnl-StartBuild {
    $st = $script:Pnl
    $doc = Pnl-Doc
    if (-not $doc -or -not $st.DocPath -or -not (Pnl-DocHasEdits $doc)) { $st.Status = 'Nothing to build yet - make an edit first.'; $st.Warn = $true; return }
    if ($st.Job -and $st.Job.Phase -notin @('done', 'failed')) { return }
    # the desktop's BUILD MOD writes the same work folders: never two at once
    $busy = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { [string]$_.CommandLine -match 'build_skin\.ps1' })
    if ($busy.Count) { $st.Status = 'Skin Studio is already building a mod - wait for it to finish, then try again.'; $st.Warn = $true; return }
    # the linked-map twins, filled in the way the desktop's build prompt does
    if ($st.BuildFill -and $st.BuildGapsFor -eq $st.DocPath -and @($st.BuildGaps).Count) {
        $n = 0
        foreach ($p in @($st.BuildGaps)) {
            $src = Pnl-Layers $p.From
            if ($null -ne $src -and $src.Count) { $doc['ops'][$p.To] = Pnl-CopyLayers $src; $n++ }
        }
        $st.BuildGaps = @()
        if ($n) { Pnl-Commit; Pnl-Log "filled in $n linked map(s) before building" }
    }
    $mods = @()
    try { $mods = @(Pnl-ModsOf (Get-Content -LiteralPath $st.DocPath -Raw | ConvertFrom-Json)) } catch {}
    if ($mods.Count -eq 0) { $st.Status = 'This design has no usable mod name (letters and digits).'; $st.Warn = $true; return }
    $dir = Join-Path $st.WorkDir 'build'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $log = Join-Path $dir 'build.out'; $err = Join-Path $dir 'build.err'
    foreach ($f in @($log, $err)) { if (Test-Path -LiteralPath $f) { [IO.File]::Delete($f) } }
    # Start-Process joins -ArgumentList with bare spaces in PS 5.1: quote paths
    # -Zip: a shareable zip of each built mod lands in Downloads too (her ask,
    # 2026-09-27: build and get the file without leaving the game)
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f (Join-Path $SS_Root 'build_skin.ps1')), '-Design', ('"{0}"' -f $st.DocPath), '-Zip')
    $p = Start-Process powershell.exe -ArgumentList $argv -WorkingDirectory $SS_Root -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError $err -PassThru
    $null = $p.Handle      # PS 5.1: without holding the handle, ExitCode reads empty after exit
    $st.Job = @{
        Phase = 'building'; Title = (Pnl-DocTitle); Design = $st.DocPath; Mods = $mods; Proc = $p; Log = $log; Err = $err
        Started = [DateTime]::Now; Ended = [DateTime]::MinValue; BuiltIn = 0.0; LogPos = [long]0; Part = ''; Line = 'Starting'; Error = ''
        Install = ''; InstallNote = ''; Pak = $null; PakNote = ''; Mount = ''; MountAsked = [DateTime]::MinValue
        Loaded = (New-Object 'System.Collections.Generic.HashSet[string]'); TexOkSeen = $false
    }
    Pnl-Log ('build started: {0} -> {1} (pid {2})' -f (Split-Path $st.DocPath -Leaf), ($mods -join ', '), $p.Id)
    $st.Status = 'Building ' + $st.Job.Title + '...'; $st.Warn = $false
    $st.JobShown = ''; $st.Dirty = $true
}

function Pnl-CancelBuild {
    $j = $script:Pnl.Job
    if (-not $j -or $j.Phase -ne 'building') { return }
    # the whole tree: build_skin runs ddstools, rrcli and, for a split design,
    # one child build per skin. cmd swallows taskkill's output (a native
    # command's stderr is a terminating error under EAP Stop in PS 5.1).
    cmd /c ('taskkill /T /F /PID {0} >nul 2>&1' -f $j.Proc.Id)
    $j.Cancelled = $true
    Pnl-JobFail 'Cancelled - nothing was installed.'
}

function Pnl-JobFail([string]$msg) {
    $st = $script:Pnl; $j = $st.Job
    if (-not $j) { return }
    $j.Phase = 'failed'; $j.Error = $msg; $j.Ended = [DateTime]::Now
    $st.Status = 'Build failed: ' + $msg; $st.Warn = $true; $st.Dirty = $true
    Pnl-Log ('build failed: ' + $msg)
}

function Pnl-JobSeconds($j) {
    $end = if ($j.Ended -gt [DateTime]::MinValue) { $j.Ended } else { [DateTime]::Now }
    [Math]::Max(0, ($end - $j.Started).TotalSeconds)
}
function Pnl-Clock([double]$sec) { '{0}:{1:D2}' -f [int][Math]::Floor($sec / 60), ([int][Math]::Floor($sec) % 60) }

# build_skin's log lines, in her words; '' keeps the line shown before
function Pnl-JobLine([string]$ln) {
    $t = ($ln -replace '^\[\d\d:\d\d:\d\d\]\s*', '').Trim()
    if (-not $t) { return '' }
    if ($t -match '^###### (\d+) of (\d+): (.+?) \(\d') { return ('part:{0} of {1} - {2}' -f $Matches[1], $Matches[2], $Matches[3]) }
    if ($t -match '<-') { return 'Painting ' + (($t -replace '\s*<-.*$', '') -replace '\.png$', '') }
    if ($t -match '^injecting') { return 'Packing the textures into the game''s format' }
    if ($t -match '^verifying staged') { return 'Checking the colours came through' }
    if ($t -match '^color edits') { return 'Writing the material colours' }
    if ($t -match '^3/3 packing') { return 'Packing the mod' }
    if ($t -match '^(produced|container encrypted)') { return 'Packed' }
    if ($t -match '^Checking game patch') { return 'Checking the game data' }
    if ($t -match '^=== DONE') { return 'Built' }
    if ($t -match '^WARN') { return $t }
    ''
}

# new lines of the build's console, up to the last complete one
function Pnl-JobReadLog($j) {
    if (-not (Test-Path -LiteralPath $j.Log)) { return }
    $fs = $null
    try {
        $fs = [IO.File]::Open($j.Log, 'Open', 'Read', 'ReadWrite')
        if ($fs.Length -le $j.LogPos) { return }
        $fs.Position = $j.LogPos
        $buf = New-Object byte[] ([int][Math]::Min(262144, $fs.Length - $j.LogPos))
        $n = $fs.Read($buf, 0, $buf.Length)
        $cut = [Array]::LastIndexOf($buf, [byte]10, $n - 1)
        if ($cut -lt 0) { return }
        $j.LogPos += $cut + 1
        foreach ($ln in ([Text.Encoding]::UTF8.GetString($buf, 0, $cut + 1) -split "`r?`n")) {
            $f = Pnl-JobLine $ln
            if (-not $f) { continue }
            if ($f.StartsWith('part:')) { $j.Part = $f.Substring(5) } else { $j.Line = $f }
        }
    } catch {} finally { if ($fs) { $fs.Dispose() } }
}

# the error a failed build_skin.ps1 died with (its first line), or a pointer
function Pnl-JobErrorText($j) {
    $msg = ''
    if (Test-Path -LiteralPath $j.Err) {
        $raw = [IO.File]::ReadAllText($j.Err)
        if ($raw.StartsWith('#< CLIXML')) {
            $raw = (@([regex]::Matches($raw, '<S S="Error">([^<]*)</S>') | ForEach-Object { $_.Groups[1].Value }) -join '') -replace '_x000D__x000A_', "`n"
        }
        $lines = @($raw -split "`r?`n" | Where-Object { $_.Trim() })
        if ($lines.Count) { $msg = ($lines[0] -replace '^.*?\.ps1\s*:\s*', '').Trim() }
    }
    if (-not $msg) { $msg = 'build_skin.ps1 stopped (exit {0})' -f $j.Proc.ExitCode }
    $msg
}

function Pnl-BuildTick {
    $st = $script:Pnl
    if (@($st.Pending).Count -and [DateTime]::Now -ge $st.NextPendingCheck) {
        $st.NextPendingCheck = [DateTime]::Now.AddSeconds(3)
        if (-not (Pnl-GameRunning)) { Pnl-InstallPending }
    }
    $j = $st.Job
    if (-not $j -or $j.Phase -in @('done', 'failed')) { return }
    if ($st.JobClock.ElapsedMilliseconds -lt 250) { return }
    $st.JobClock.Restart()
    if ($j.Phase -eq 'building') {
        Pnl-JobReadLog $j
        if ($j.Proc.HasExited) {
            Pnl-JobReadLog $j
            if ($j.Proc.ExitCode -ne 0) { Pnl-JobFail (Pnl-JobErrorText $j) } else { Pnl-JobAfterBuild }
        }
    } elseif ($j.Phase -eq 'mounting') {
        # MountLive answers within a frame or two; a game running an in-game
        # mod from before this feature never answers at all
        if (([DateTime]::Now - $j.MountAsked).TotalSeconds -gt 12) { Pnl-MountAnswer 'timeout' }
    } elseif ($j.Phase -eq 'loading') {
        # the walk normally answers within a frame; an older in-game mod never
        # sends pk_, so a quiet walk still ends the job
        if (([DateTime]::Now - $j.LoadAsked).TotalSeconds -gt 6) { Pnl-JobDone }
    } elseif ($j.Phase -eq 'galacta') {
        # waiting on her F7 presses; no time limit - quitting Rivals installs it
        Pnl-GalactaTick
        if ($j.Phase -in @('done', 'failed')) { return }
    }
    # a frame whenever what the screen shows changes (the clock ticks too)
    $shown = '{0}|{1}|{2}|{3}|{4}' -f $j.Phase, $j.Line, $j.Part, [int](Pnl-JobSeconds $j), $j.GalLine
    if ($shown -ne $st.JobShown) {
        $st.JobShown = $shown
        if ($st.Open -and $st.Screen -in @('build', 'home')) { $st.Dirty = $true }
    }
}

function Pnl-JobAfterBuild {
    $st = $script:Pnl; $j = $st.Job
    # every mod the design makes needs a fresh triplet - an old one from an
    # earlier build must never pass for this one
    $stale = @($j.Mods | Where-Object {
        $u = @(Get-ChildItem -LiteralPath (Join-Path $SS_Root ('work\{0}\out' -f $_)) -Filter '*.ucas' -File -ErrorAction SilentlyContinue)[0]
        -not $u -or $u.LastWriteTime -lt $j.Started.AddSeconds(-2)
    })
    if ($stale.Count) { Pnl-JobFail ('the build ended without a fresh mod for ' + ($stale -join ', ')); return }
    $j.Line = 'Built'; $j.Part = ''; $j.BuiltIn = (Pnl-JobSeconds $j)
    # Rivals running with Project Galacta: Galacta's own documented way. Its F7
    # unloads every mod (the game lets go of the old copy), the new build goes
    # in, a second F7 reloads it, and a level change shows it - no restart, and
    # the whole mod comes along (materials and particles too). galacta.ps1.
    if ((Pnl-GameRunning) -and (Pnl-GalactaOn)) {
        # an older build's live pak must never win over the new mod after the
        # level change: nothing listed = the walk loads nothing from it
        LP-Clear $st.LiveDir
        $j.Swap = SS-GalSwapNew $j.Mods $st.ModsDir $st.GameProc $st.SaveDir
        if ($j.Swap.Missing.Count) { Pnl-JobFail ('no built files for ' + ($j.Swap.Missing -join ', ')); return }
        $j.Phase = 'galacta'; $j.Mount = 'galacta'; $j.Install = ''; $j.InstallNote = ''
        Pnl-Log ('Project Galacta swap for {0} (old copy in ~mods: {1}; {2} other mod(s) to watch)' -f ($j.Mods -join ', '), $(if ($j.Swap.HadOld.Count) { $j.Swap.HadOld -join ', ' } else { 'none' }), @($j.Swap.Refs).Count)
        Pnl-GalactaTick
        return
    }
    $j.Phase = 'installing'
    $r = Pnl-InstallMods $j.Mods
    if ($r.Missing.Count) { Pnl-JobFail ('no built files for ' + ($r.Missing -join ', ')); return }
    if ($r.Pending.Count) {
        $st.Pending = @(@($st.Pending) + @($r.Pending) | Sort-Object -Unique); Pnl-SavePending
        $j.Install = 'pending'
        $j.InstallNote = 'Goes in when you quit Rivals (the old copy is in use)'
    } else {
        $j.Install = 'now'; $j.InstallNote = 'In ~mods - it loads at every launch.'
    }
    Pnl-Log ('installed: {0}; after the game closes: {1}' -f ($(if ($r.Now.Count) { $r.Now -join ', ' } else { '-' })), ($(if ($r.Pending.Count) { $r.Pending -join ', ' } else { '-' })))
    # Without Project Galacta the build never goes onto the hero in a running
    # game (her rule, 2026-09-27): no live pak, no mount - it shows at the next
    # launch, and the live preview keeps showing the design until then. An older
    # build's live pak must not keep loading either: nothing listed = nothing.
    LP-Clear $st.LiveDir
    $j.Mount = if (Pnl-GameRunning) { 'nogalacta' } else { 'nogame' }
    Pnl-Log ('no Project Galacta: {0} shows at the next launch' -f ($j.Mods -join ', '))
    Pnl-JobDone
}

# where Galacta is looked for: the game's Paks, or the rig's test mods folder
function Pnl-GalactaOn { [bool](SS-GalactaInfo (SS-GalactaPaksDir $script:Pnl.ModsDir)).Installed }

# one step of the Galacta swap (every build tick, ~250 ms)
function Pnl-GalactaTick {
    $st = $script:Pnl; $j = $st.Job
    $gs = $j.Swap
    $before = $gs.Phase
    SS-GalSwapStep $gs
    $j.GalLine = SS-GalSwapText $gs
    if ($gs.Installed.Count -and (SS-GalSwapLeft $gs).Count -eq 0) { $j.Install = 'now'; $j.InstallNote = 'In ~mods - it loads at every launch.' }
    if ($gs.Phase -ne $before) {
        Pnl-Log ('galacta: {0} -> {1} (installed: {2})' -f $before, $gs.Phase, $(if ($gs.Installed.Count) { $gs.Installed -join ', ' } else { '-' }))
        $st.Dirty = $true
    }
    if ($gs.Phase -eq 'done') { Pnl-JobDone }
}

# "Stop waiting": whatever has not gone in yet installs when Rivals closes
function Pnl-StopGalacta {
    $st = $script:Pnl; $j = $st.Job
    if (-not $j -or $j.Phase -ne 'galacta') { return }
    $gs = $j.Swap
    $left = @(SS-GalSwapLeft $gs)
    SS-GalAskCancel $gs
    $gs.Stopped = $true; $gs.Phase = 'done'
    if ($left.Count) {
        $st.Pending = @(@($st.Pending) + $left | Sort-Object -Unique); Pnl-SavePending
        $j.Install = 'pending'; $j.InstallNote = 'Goes in when you quit Rivals (the old copy is in use)'
    }
    Pnl-Log ('stopped waiting for Galacta; after the game closes: {0}' -f $(if ($left.Count) { $left -join ', ' } else { '-' }))
    Pnl-JobDone
}

function Pnl-MountAnswer([string]$a) {
    $st = $script:Pnl; $j = $st.Job
    Pnl-Log ('mount answer: ' + $a)
    if (-not $j -or $j.Phase -ne 'mounting') { return }
    $j.Mount = $a
    # a pak that is not mounted cannot load anything: stop the walk trying
    if ($a -ne 'true') { LP-Clear $st.LiveDir; Pnl-JobDone; return }
    # mounted: the walk that follows reports each texture it loaded from the
    # pak (pk_) and ends with texok - that is when the hero really has it
    $j.Phase = 'loading'; $j.LoadAsked = [DateTime]::Now
    if ($j.TexOkSeen) { Pnl-JobDone }
}

function Pnl-PakLoaded([string]$tex) {
    $j = $script:Pnl.Job
    if (-not $j -or $j.Phase -notin @('mounting', 'loading')) { return }
    [void]$j.Loaded.Add($tex)
}

function Pnl-JobTexOk {
    $j = $script:Pnl.Job
    if (-not $j) { return }
    if ($j.Phase -eq 'loading') { Pnl-JobDone }
    elseif ($j.Phase -eq 'mounting') { $j.TexOkSeen = $true }
}

function Pnl-JobDone {
    $st = $script:Pnl; $j = $st.Job
    $j.Phase = 'done'; $j.Ended = [DateTime]::Now
    $n = $j.Loaded.Count
    $st.Status = switch ($j.Mount) {
        'true'    { if ($n -gt 0) { 'Built {0} - on your hero now: {1} texture(s) load from the mod itself' -f $j.Title, $n } else { 'Built {0} - mounted, but the game kept the live preview; it loads at the next launch' -f $j.Title } }
        'false'   { 'Built {0} - the game would not load it live; it loads at the next launch' -f $j.Title }
        'timeout' { 'Built {0} - no answer from the game; it loads at the next launch' -f $j.Title }
        'nofile'  { 'Built {0} - the game could not read the build list; it loads at the next launch' -f $j.Title }
        { $_ -in @('nogalacta', 'nogame') } {
            if ($j.Install -eq 'pending') { 'Built {0} - installs when you quit Rivals' -f $j.Title }
            else { 'Built {0} - installed; shows at your next launch' -f $j.Title }
        }
        'galacta' {
            $gs = $j.Swap
            if ($gs.Stopped -and $j.Install -eq 'pending') { 'Built {0} - it goes in when you quit Rivals' -f $j.Title }
            elseif ($gs.Stopped) { 'Built {0} - installed; press F7 twice in game to load it' -f $j.Title }
            elseif ($gs.NoGame) { 'Built {0} - installed; it loads at your next launch' -f $j.Title }
            elseif ($gs.Loaded -eq $true) { 'Built {0} - Galacta loaded it: enter or leave the Practice Range to see it' -f $j.Title }
            elseif ($gs.Loaded -eq $false) { 'Built {0} - installed; Galacta did not reload this new mod, it shows at your next launch' -f $j.Title }
            else { 'Built {0} - installed; press F7 twice in game, then change level' -f $j.Title }
        }
        default   { 'Built {0}' -f $j.Title }
    }
    $st.Warn = ($j.Mount -in @('false', 'timeout', 'nofile') -or ($j.Mount -eq 'true' -and $n -eq 0) -or ($j.Mount -eq 'galacta' -and ($j.Swap.Loaded -eq $false -or $j.Install -eq 'pending')))
    $st.Dirty = $true
    Pnl-Log ('build done in {0:0}s: {1} - install {2}, live {3}, {4} texture(s) confirmed loaded from the pak: {5}' -f (Pnl-JobSeconds $j), ($j.Mods -join ', '), $j.Install, $j.Mount, $n, (@($j.Loaded) -join ', '))
}

# one line for the home screen
function Pnl-JobHomeLine($j) {
    switch ($j.Phase) {
        'done'    { return [string]$script:Pnl.Status }
        'failed'  { return 'Last build failed: ' + $j.Error }
        'galacta' { return (Pnl-GalactaShort $j.Swap) }
        default  {
            $what = if ($j.Part) { $j.Part + ' - ' + $j.Line } else { $j.Line }
            return ('{0}  -  {1}' -f $what, (Pnl-Clock (Pnl-JobSeconds $j)))
        }
    }
}

# ============================================================== screens
function Pnl-DrawScreen($ui) {
    # live preview off: the one screen is the button that turns it on
    if (-not $script:Pnl.LiveOn) { Pnl-DrawLiveOff $ui; return }
    switch ($script:Pnl.Screen) {
        'part'    { Pnl-DrawPart $ui }
        'layer'   { Pnl-DrawPart $ui }
        'designs' { Pnl-DrawDesigns $ui }
        'images'  { Pnl-DrawImages $ui }
        'confirm' { Pnl-DrawConfirm $ui }
        'build'   { Pnl-DrawBuild $ui }
        default   { Pnl-DrawHome $ui }
    }
}

function Pnl-TitleNav($ui, [string]$title, [string]$sub, [string]$backTo) {
    $r = $ui.TitleBar($title, $sub, [bool]$backTo)
    if ($r -eq 1) { Pnl-Go $backTo; return $true }
    if ($r -eq 2) { Pnl-CloseFromPanel; return $true }
    $false
}

# LIVE PREVIEW is off (in game or in the app): the hero wears the game's own
# skin, and this is all the panel shows - the same button the app has.
function Pnl-DrawLiveOff($ui) {
    $st = $script:Pnl
    if (Pnl-TitleNav $ui 'Skin Studio' 'Live preview is off' '') { return }
    $ui.Footer($st.Status, $st.Warn)
    $ui.BeginScroll('liveoff')
    $ui.Section('Live preview')
    $ui.Label('Your hero is wearing the game''s own skin. Your designs are safe on disk.')
    $ui.Space(4)
    if ($ui.Button('liveon', 'Turn on live preview', 1)) { Pnl-Run { Pnl-SetLive $true } }
    $ui.Hint('Puts your design for this skin on your hero and opens the editor. It stays on - every match, and next time you play - until you turn it off, here or in the Skin Studio app.')
    $ui.Section('Text size')
    $zi = -1; for ($i = 0; $i -lt $script:PnlZooms.Count; $i++) { if ([Math]::Abs($script:PnlZooms[$i].z - $st.Zoom) -lt 0.01) { $zi = $i } }
    $hit = $ui.Pills('zoom', [string[]]@($script:PnlZooms | ForEach-Object { $_.label }), $zi)
    if ($hit -ge 0 -and $hit -ne $zi) { Pnl-SetZoom $script:PnlZooms[$hit].z }
    $ui.Hint('F8 hides this panel.')
    $ui.EndScroll()
}

function Pnl-DrawHome($ui) {
    $st = $script:Pnl
    if (Pnl-TitleNav $ui 'Skin Studio' (Pnl-SkinTitle) '') { return }
    $ui.Footer($st.Status, $st.Warn)
    $ui.BeginScroll('home')
    # the app's LIVE PREVIEW button, in game: off puts the game's own skin back
    if (-not $ui.Toggle('live', 'Live preview', $true, 'On: your design shows on your hero. Off puts the game''s own skin back.')) { Pnl-Run { Pnl-SetLive $false } }
    $doc = Pnl-Doc
    $ui.Section('Design')
    if ($doc -and (Pnl-DocMatches)) {
        $n = @($doc['ops'].Keys).Count
        if ($ui.ListItem('design', (Pnl-DocTitle), ('{0} texture edit(s)  -  switch or start another' -f $n), $null, $null, $false)) { Pnl-Go 'designs' }
        # the Build mod button, right under the design it builds: build,
        # install, and on the hero now - no restart
        $j = $st.Job
        if ($j -and $j.Phase -notin @('done', 'failed')) {
            $what = if ($j.Phase -eq 'galacta') { 'Swapping in ' + $j.Title } else { 'Building ' + $j.Title }
            if ($ui.ListItem('buildjob', $what, (Pnl-JobHomeLine $j), $null, $null, $true)) { Pnl-Go 'build' }
        } else {
            $can = (Pnl-DocHasEdits $doc)
            if ($ui.Button('buildmod', 'Build mod', $(if ($can) { 1 } else { 4 }))) { Pnl-OpenBuild }
            if ($j -and $j.Design -eq $st.DocPath) { $ui.Hint((Pnl-JobHomeLine $j)) }
            elseif ($can) { $ui.Hint('Turns this design into a real mod and installs it. With Project Galacta it swaps in now; without, at your next launch.') }
            else { $ui.Hint('Make an edit first - Build mod turns the design into a real mod.') }
        }
    } else {
        $ui.Hint('No design for this hero is live. Your first edit starts one, or pick a saved design.')
        $b = $ui.ButtonRow('d0', [string[]]@('New design', 'Saved designs'), 0)
        if ($b -eq 0) { Pnl-Run { $null = Pnl-NewDesign } } elseif ($b -eq 1) { Pnl-Go 'designs' }
    }
    if ($st.Parts.Count -eq 0) {
        $ui.Section('Your hero')
        $ui.Label('Looking for your hero...')
        $ui.Hint('Open the panel in a match or the practice range. The lobby hero lives in a separate preview world that the game does not let mods reach.')
    } else {
        $ui.Section('On your hero now')
        foreach ($part in $st.Parts) {
            if ($ui.ListItem('part:' + $part.Rel, $part.Name, (Pnl-PartSummary $part), $part.Thumb, (Pnl-PartChips $part), $false)) { Pnl-OpenPart $part.Rel }
        }
    }
    $ui.Section('Whole design')
    $undoTxt = if ($st.Undo.Count -gt 0) { 'Undo ({0})' -f $st.Undo.Count } else { 'Undo' }
    $b = $ui.ButtonRow('whole', [string[]]@($undoTxt, 'Reload hero'), -1)
    if ($b -eq 0) { Pnl-Run { Pnl-Undo } } elseif ($b -eq 1) { Pnl-ReloadAll }
    if ($doc -and (Pnl-DocMatches) -and @($doc['ops'].Keys).Count -gt 0) {
        if ($ui.Button('clearall', 'Clear every edit on this hero', 2)) {
            Pnl-Ask 'Clear every texture edit on the hero on screen? The design file keeps other heroes'' edits. Undo can bring it back.' 'Clear everything' {
                $d = Pnl-Doc
                foreach ($p in $script:Pnl.Parts) { foreach ($s in @(Pnl-Siblings $p)) { if ($d['ops'].Contains($s.Rel)) { $d['ops'].Remove($s.Rel) } } }
                Pnl-Queue 'commit' 'clearall'
            } 'home'
        }
    }
    $ui.Section('Text size')
    $zi = -1; for ($i = 0; $i -lt $script:PnlZooms.Count; $i++) { if ([Math]::Abs($script:PnlZooms[$i].z - $st.Zoom) -lt 0.01) { $zi = $i } }
    $hit = $ui.Pills('zoom', [string[]]@($script:PnlZooms | ForEach-Object { $_.label }), $zi)
    if ($hit -ge 0 -and $hit -ne $zi) { Pnl-SetZoom $script:PnlZooms[$hit].z }
    $ui.Hint('F8 hides this panel. F6 reloads every edited texture. If the mouse ever turns the camera instead of moving a cursor, tap the Windows key, then click the panel. Edits save to the design file as you go; Build mod (above) turns it into a real mod.')
    $ui.EndScroll()
}

function Pnl-DrawPart($ui) {
    $st = $script:Pnl
    $part = Pnl-Info $st.Rel
    if (-not $part) { Pnl-Go 'home'; return }
    $main = Pnl-Main
    if (Pnl-TitleNav $ui $main.Name ((Pnl-RoleWord $part.Leaf) + ' map  -  ' + $part.Leaf) 'home') { return }
    $ui.Footer($st.Status, $st.Warn)
    $ui.BeginScroll('part')

    # every part of the hero one tap away - no trip back to the list
    if ($st.Parts.Count -gt 1) {
        $base = Pnl-PartBase $st.Rel
        $cur = -1
        for ($i = 0; $i -lt $st.Parts.Count; $i++) { if ((Pnl-PartBase $st.Parts[$i].Rel) -eq $base) { $cur = $i } }
        $thumbs = [string[]]@($st.Parts | ForEach-Object { [string]$_.Thumb })
        $names = [string[]]@($st.Parts | ForEach-Object { [string]$_.Name })
        $hit = $ui.PartStrip('parts', $thumbs, $names, $cur, 'Parts on your hero - tap one to switch')
        if ($hit -ge 0 -and $hit -ne $cur) { Pnl-OpenPart $st.Parts[$hit].Rel; $st.Dirty = $true; $ui.EndScroll(); return }
    }

    # the part's colour / shine / glow maps
    $sibs = @(Pnl-Siblings $part)
    if ($sibs.Count -gt 1) {
        $mapNames = [string[]]@($sibs | ForEach-Object { Pnl-RoleWord $_.Leaf })
        $sel = 0; for ($i = 0; $i -lt $sibs.Count; $i++) { if ($sibs[$i].Rel -eq $part.Rel) { $sel = $i } }
        $hit = $ui.Pills('maps', $mapNames, $sel)
        if ($hit -ge 0 -and $hit -ne $sel) {
            $st.Rel = $sibs[$hit].Rel; $st.Layer = 0; $st.Slot = 'color'; $st.HsvKey = ''; $st.Dirty = $true
            $ui.EndScroll(); return
        }
    }
    $ui.Preview((Pnl-BaseThumb $part), (Pnl-AfterThumb $part), '')

    $layers = Pnl-Layers $part.Rel
    $n = if ($null -eq $layers) { 0 } else { $layers.Count }
    if ($st.Layer -ge $n) { $st.Layer = [Math]::Max(0, $n - 1) }
    if ($n -eq 0) {
        Pnl-DrawQuickStart $ui
        $ui.EndScroll(); return
    }

    $ui.Section('Layers  -  applied left to right')
    $labels = [string[]]@($layers | ForEach-Object { Pnl-ModeLabel ([string]$_['mode']) })
    $chips = [System.Drawing.Color[]]@($layers | ForEach-Object { Pnl-LayerChip $_ })
    $hit = $ui.LayerTabs('ltabs', $labels, $chips, $st.Layer, '+  Add')
    if ($hit -eq $n) { Pnl-Run { Pnl-AddLayer 'tint' '' }; $ui.EndScroll(); return }
    if ($hit -ge 0 -and $hit -ne $st.Layer) { Pnl-OpenLayer $hit; $st.Dirty = $true; $ui.EndScroll(); return }

    Pnl-DrawLayerEditor $ui $layers
    if ($st.Screen -ne 'part' -and $st.Screen -ne 'layer') { $ui.EndScroll(); return }

    $ui.Section('This map')
    $link = Pnl-LinksFor $part
    if ($link -and @($link.Others).Count -gt 0) {
        $ui.Hint($(if ($link.Sure) { 'The same artwork ships under other names (another form or the lobby copy). Recolour one and the other stays vanilla.' } else { 'Maps with a similar name - maybe the same artwork on another form, maybe a different object.' }))
        if ($ui.Button('copylinks', ('Copy these layers to {0} linked map(s)' -f @($link.Others).Count))) { Pnl-CopyTo ([string[]]@($link.Others)) 'linked map(s)' }
    }
    if ($ui.Button('copychroma', 'Copy to the other colourways of this skin')) { Pnl-Run { Pnl-CopyToChromas } }
    if ($ui.Button('clearpart', 'Clear this map - back to vanilla', 2)) {
        (Pnl-Doc)['ops'].Remove($part.Rel)
        $st.Layer = 0; $st.HsvKey = ''
        Pnl-Queue 'commit' 'clear'
    }
    $ui.EndScroll()
}

function Pnl-ModeIndex([string]$mode) {
    for ($i = 0; $i -lt $script:PnlModes.Count; $i++) { if ($script:PnlModes[$i].id -eq $mode) { return $i } }
    0
}

function Pnl-ModeLabel([string]$mode) {
    if ($mode -eq 'edited') { return 'Hand-edited' }
    foreach ($m in $script:PnlModes) { if ($m.id -eq $mode) { return $m.label } }
    $mode
}

# A vanilla map: the palette is right there, and one tap tints the map with it
# (a new tint layer, painted at once). Other kinds of layer start from the pills.
function Pnl-DrawQuickStart($ui) {
    $st = $script:Pnl
    # (the 32-colour palette went 2026-10-02, her call: colour history only)
    if ($st.Recent.Count -gt 0) {
        $ui.Section('Tint this map')
        $ui.Hint('Vanilla. Tap a colour from your history to tint it - then fine-tune, or add more layers.')
        $rc = [System.Drawing.Color[]]@($st.Recent | ForEach-Object { [SkinPanel]::Hex([string]$_) })
        $hit = $ui.Swatches('qrc', $rc, 8)
        if ($hit -ge 0) { $st.PendingColor = [string]$st.Recent[$hit]; Pnl-Run { Pnl-AddLayer 'tint' $script:Pnl.PendingColor } }
        $ui.Section('Or start with')
        $opts = @($script:PnlModes | Where-Object { $_.id -ne 'tint' })
    } else {
        # no history yet: Tint is a pill like the rest, its colour picked after
        $ui.Section('Start with')
        $opts = @($script:PnlModes)
    }
    $hit = $ui.Pills('qmode', [string[]]@($opts | ForEach-Object { $_.label }), -1)
    if ($hit -ge 0) { $st.PendingMode = $opts[$hit].id; Pnl-Run { Pnl-AddLayer $script:Pnl.PendingMode '' } }
}

# The selected layer's controls, under the layer tabs. Navigating away (the
# image picker) changes $st.Screen, which the caller checks.
function Pnl-DrawLayerEditor($ui, $layers) {
    $st = $script:Pnl
    $L = $layers[$st.Layer]
    $mode = [string]$L['mode']
    if ($mode -eq 'edited') {
        $ui.Label('Hand-edited PNG')
        $ui.Hint('This layer is your own painted file: ' + [string]$L['file'] + '. Change it in Photoshop and save - the watcher picks it up.')
    } else {
        $labels = [string[]]@($script:PnlModes | ForEach-Object { $_.label })
        $hit = $ui.Pills('mode', $labels, (Pnl-ModeIndex $mode))
        if ($hit -ge 0 -and $script:PnlModes[$hit].id -ne $mode) {
            $prev = $mode
            Pnl-FillMode $L $script:PnlModes[$hit].id
            $st.HsvKey = ''
            if ($script:PnlModes[$hit].id -eq 'replace' -and -not $L['file']) { $st.ImageUndo = $prev; Pnl-Go 'images'; return }
            Pnl-Queue 'commit' 'mode'
            $mode = [string]$L['mode']
        }
    }

    switch ($mode) {
        { $_ -in @('tint', 'paint') } {
            $ui.Hint($(if ($mode -eq 'tint') { 'Tint keeps the fabric''s own light and shade and moves its colour - pale areas stay pale. Use Paint for an exact colour.' } else { 'Paint lays the colour on flat, keeping only the shading.' }))
            Pnl-ColorSection $ui $L ([string[]]@('color')) ([string[]]@('Colour'))
        }
        'huerange' {
            $ui.Hint('Moves one family of colours and leaves the rest alone - the hue closest to your pick below, or the texture''s main colour when Auto is on.')
            $auto = ([double]$L['bandCenter'] -lt 0)
            $na = $ui.Toggle('auto', 'Auto-detect the colour family', $auto, '')
            if ($na -ne $auto) { $L['bandCenter'] = $(if ($na) { -1.0 } else { 0.0 }); Pnl-Queue 'commit' 'auto' }
            if (-not $na) {
                $v = $ui.Slider('c:band', 'Family to move (hue)', [double]$L['bandCenter'], 0, 359, ('{0:0} deg' -f [double]$L['bandCenter']))
                $L['bandCenter'] = [Math]::Round($v)
            }
            $bw = [double]$L['bandWidth']; if ($bw -le 0) { $bw = 34 }
            $v = $ui.Slider('c:bw', 'How wide a family', $bw, 5, 90, ('+/- {0:0} deg' -f $bw))
            $L['bandWidth'] = [Math]::Round($v)
            Pnl-ColorSection $ui $L ([string[]]@('color')) ([string[]]@('New colour'))
        }
        { $_ -in @('gradtint', 'gradpaint') } {
            $dl = [string[]]@($script:PnlDirs | ForEach-Object { $_.label })
            $di = 0; for ($i = 0; $i -lt $script:PnlDirs.Count; $i++) { if ($script:PnlDirs[$i].id -eq [string]$L['gradDir']) { $di = $i } }
            $h = $ui.Pills('dir', $dl, $di)
            if ($h -ge 0 -and $h -ne $di) { $L['gradDir'] = $script:PnlDirs[$h].id; Pnl-FillMode $L $mode; Pnl-Queue 'commit' 'dir' }
            if ([string]$L['gradDir'] -eq 'corners') {
                Pnl-ColorSection $ui $L ([string[]]@('color', 'color2', 'color3', 'color4')) ([string[]]@('Top left', 'Top right', 'Bottom left', 'Bottom right'))
            } else {
                Pnl-ColorSection $ui $L ([string[]]@('color', 'color2')) ([string[]]@('From', 'To'))
            }
        }
        'hueshift' {
            $v = $ui.Slider('c:hue', 'Hue shift', [double]$L['hueShift'], -180, 180, ('{0:+0;-0;0} deg' -f [double]$L['hueShift']))
            $L['hueShift'] = [Math]::Round($v)
        }
        'hsl' {
            $v = $ui.Slider('c:hue', 'Hue shift', [double]$L['hueShift'], -180, 180, ('{0:+0;-0;0} deg' -f [double]$L['hueShift']))
            $L['hueShift'] = [Math]::Round($v)
            $sm = if ($L.Contains('satMul')) { [double]$L['satMul'] } else { 1.0 }
            $v = $ui.Slider('c:sat', 'Saturation', $sm, 0, 2, ('x {0:0.00}' -f $sm))
            $L['satMul'] = [Math]::Round($v, 2)
            $lm = if ($L.Contains('lightMul')) { [double]$L['lightMul'] } else { 1.0 }
            $v = $ui.Slider('c:light', 'Lightness', $lm, 0, 2, ('x {0:0.00}' -f $lm))
            $L['lightMul'] = [Math]::Round($v, 2)
        }
        'replace' {
            $f = [string]$L['file']
            $ui.Label($(if ($f) { 'Image: ' + (Split-Path $f -Leaf) } else { 'No image picked yet' }))
            $ui.Hint('Stretched to the map''s canvas. Drop your own PNGs into SkinStudio\images to pick them here.')
            if ($ui.Button('pickimg', 'Pick an image', 1)) { $st.ImageUndo = 'replace'; Pnl-Go 'images'; return }
        }
        default { }
    }

    if ($mode -ne 'edited') {
        $ui.Section('Mix')
        $s0 = if ($L.Contains('strength')) { [double]$L['strength'] } else { 1.0 }
        $v = $ui.Slider('c:str', 'Strength', $s0, 0, 1, ('{0:0}%' -f ($s0 * 100)))
        $L['strength'] = [Math]::Round($v, 2)
        if ($mode -notin @('gray', 'invert', 'replace')) {
            $ps0 = [bool]$L['protectSkin']
            $ps1 = $ui.Toggle('skin', 'Protect skin tones', $ps0, 'Leaves warm skin colours alone - for maps that mix skin and costume.')
            if ($ps1 -ne $ps0) { $L['protectSkin'] = $ps1; Pnl-Queue 'commit' 'skin' }
        }
    }

    # this layer's place in the stack; the tabs above show the order
    $i = $st.Layer
    $styles = [int[]]@($(if ($i -gt 0) { 0 } else { 4 }), $(if ($i -lt $layers.Count - 1) { 0 } else { 4 }), 2)
    $b = $ui.ButtonRow('lay', [string[]]@('Move left', 'Move right', 'Delete layer'), $styles)
    if ($b -eq 0 -or $b -eq 1) {
        $j = if ($b -eq 0) { $i - 1 } else { $i + 1 }
        $tmp = $layers[$i]; $layers[$i] = $layers[$j]; $layers[$j] = $tmp
        $st.Layer = $j; $st.HsvKey = ''
        Pnl-Queue 'commit' 'reorder'
    } elseif ($b -eq 2) {
        $layers.RemoveAt($i); Pnl-DropIfEmpty $st.Rel
        $st.Layer = [Math]::Max(0, $i - 1); $st.HsvKey = ''
        Pnl-Queue 'commit' 'delete'
    }
}

# Colour controls: the palette FIRST, so a new colour is one tap from opening
# the part; the picker underneath is for fine-tuning.
function Pnl-ColorSection($ui, $L, [string[]]$slots, [string[]]$names) {
    $st = $script:Pnl
    if ($slots -notcontains $st.Slot) { $st.Slot = $slots[0]; $st.HsvKey = '' }
    if ($slots.Count -gt 1) {
        $ui.Section('Colours  -  tap one, then pick its colour')
        for ($i = 0; $i -lt $slots.Count; $i++) {
            $hx = [string]$L[$slots[$i]]; if (-not $hx) { $hx = '#FFFFFF' }
            if ($ui.ColorBar('slot' + $i, $names[$i], [SkinPanel]::Hex($hx), ($st.Slot -eq $slots[$i]))) { $st.Slot = $slots[$i]; $st.HsvKey = '' }
        }
    }
    $slot = $st.Slot
    $hex = [string]$L[$slot]
    if (-not $hex) { $hex = '#FFFFFF'; $L[$slot] = $hex }
    $key = '{0}|{1}|{2}' -f $st.Rel, $st.Layer, $slot
    if ($st.HsvKey -ne $key -or $st.HsvHex -ne $hex) {
        $st.Hsv = [SkinPanel]::ToHsv([SkinPanel]::Hex($hex)); $st.HsvKey = $key; $st.HsvHex = $hex
    }
    if ($slots.Count -eq 1) {
        $ui.Section($names[0])
        $null = $ui.ColorBar('slot0', 'Current', [SkinPanel]::Hex($hex), $false)
    }
    if ($st.Recent.Count -gt 0) {
        $ui.Section('Colour history')
        $rc = [System.Drawing.Color[]]@($st.Recent | ForEach-Object { [SkinPanel]::Hex([string]$_) })
        $hit = $ui.Swatches('rc', $rc, 8)
        if ($hit -ge 0) { $L[$slot] = [string]$st.Recent[$hit]; $st.HsvKey = ''; Pnl-Remember ([string]$L[$slot]); Pnl-Queue 'commit' 'recent' }
    }
    $ui.Section('Fine-tune')
    $h = [double]$st.Hsv[0]; $s = [double]$st.Hsv[1]; $v = [double]$st.Hsv[2]
    if ($ui.ColorPicker('c:pick', [ref]$h, [ref]$s, [ref]$v)) {
        $st.Hsv = [double[]]@($h, $s, $v)
        $new = [SkinPanel]::ToHex([SkinPanel]::FromHsv($h, $s, $v))
        $L[$slot] = $new; $st.HsvHex = $new
    }
    if ($ui.LastCommitId -eq 'c:pick') { Pnl-Remember ([string]$L[$slot]) }
}

function Pnl-DrawDesigns($ui) {
    $st = $script:Pnl
    $sid = Pnl-MainSkin
    $sub = if ($sid) { 'for ' + (Pnl-HeroName $sid.Substring(0, 4)) } else { '' }
    if (Pnl-TitleNav $ui 'Designs' $sub 'home') { return }
    $ui.Footer($st.Status, $st.Warn)
    $ui.BeginScroll('designs')
    if ($ui.Button('new', '+  New design for this skin', 1)) {
        Pnl-Run { if (Pnl-NewDesign) { Pnl-Go 'home' } }
        $ui.EndScroll(); return
    }
    $ui.Section('Saved designs')
    if ($st.DesignList.Count -eq 0) { $ui.Hint('None saved for this hero yet.') }
    $cur = [string]$script:Design
    foreach ($d in $st.DesignList) {
        if ($ui.ListItem('dz:' + $d.Path, $d.Title, $d.Sub, $null, $d.Chips, ($d.Path -eq $cur))) {
            # the path goes through state, not a closure: a scriptblock rebound
            # by GetNewClosure cannot see script-scope functions here
            $st.PendingPath = $(if ($d.Path -eq $cur) { '' } else { $d.Path })
            Pnl-Run { if ($script:Pnl.PendingPath) { Pnl-SwitchDesign $script:Pnl.PendingPath }; Pnl-Go 'home' }
            $ui.EndScroll(); return
        }
    }
    $ui.EndScroll()
}

# Leaving the picker without an image. An image layer with no file cannot be
# painted (SkinArt throws), so a layer added as Image goes away again, and one
# switched to Image goes back to the mode it had.
function Pnl-ImageBack {
    $st = $script:Pnl
    $layers = Pnl-Layers $st.Rel
    if ($null -ne $layers -and $st.Layer -lt $layers.Count) {
        $L = $layers[$st.Layer]
        if ([string]$L['mode'] -eq 'replace' -and -not $L['file']) {
            if ($st.ImageUndo -and $st.ImageUndo -ne 'replace') { $L['mode'] = $st.ImageUndo }
            else { $layers.RemoveAt($st.Layer); Pnl-DropIfEmpty $st.Rel; $st.Layer = [Math]::Max(0, $st.Layer - 1) }
        }
    }
    $st.ImageUndo = ''
    Pnl-Go 'part'
}

function Pnl-DrawImages($ui) {
    $st = $script:Pnl
    $r = $ui.TitleBar('Pick an image', 'stretched over the whole map', $true)
    if ($r -eq 1) { Pnl-ImageBack; return }
    if ($r -eq 2) { Pnl-ImageBack; Pnl-CloseFromPanel; return }
    $ui.Footer($st.Status, $st.Warn)
    $ui.BeginScroll('images')
    if ($st.ImageList.Count -eq 0) { $ui.Hint('No images found. Put PNG or JPG files in ' + (Join-Path $SS_Root 'images') + ' and reopen this screen.') }
    foreach ($im in $st.ImageList) {
        if ($ui.ListItem('im:' + $im.Path, $im.Title, $im.Sub, (Pnl-ImageThumb $im.Path), $null, $false)) {
            $layers = Pnl-Layers $st.Rel
            if ($null -ne $layers -and $st.Layer -lt $layers.Count) {
                $L = $layers[$st.Layer]; $L['mode'] = 'replace'; $L['file'] = $im.Path
                if (-not $L.Contains('strength')) { $L['strength'] = 1.0 }
                Pnl-Queue 'commit' 'image'
            }
            $st.ImageUndo = ''
            Pnl-Go 'part'; $ui.EndScroll(); return
        }
    }
    $ui.EndScroll()
}

# The Galacta route's steps after "Build the mod": swap it in (her first F7),
# reload it (the second F7), see it (a level change). The sentence under them
# says exactly what to press next.
# what to press next, short enough for one line (a step, the home screen)
function Pnl-GalactaShort($gs) {
    # while the in-game mod presses F7 for her, say so; if the game never
    # answers (an older in-game mod), it is her key again
    $auto = SS-GalAuto $gs
    if ($gs.Phase -eq 'unload') { return $(if ($auto) { 'Pressing F7 for you - Galacta unloads your mods' } else { 'Press F7 - Galacta unloads your mods' }) }
    $newOne = (@($gs.Installed | Where-Object { $gs.HadOld -notcontains $_ }).Count -gt 0)
    if ($newOne -and $gs.RefsUp -eq $true -and -not $gs.UnloadSeen) { return $(if ($auto) { 'New this session: trying F7 twice for you' } else { 'New this session: press F7 twice to try' }) }
    $(if ($auto) { 'Pressing F7 again for you - Galacta reloads' } else { 'Press F7 again - Galacta reloads your mods' })
}

function Pnl-DrawGalactaSteps($ui, $j) {
    $gs = $j.Swap
    $allIn = ($gs.Installed.Count -gt 0 -and (SS-GalSwapLeft $gs).Count -eq 0)
    if ($allIn) { $s1 = 2; $t1 = $(if ($gs.NoGame) { 'In ~mods - Rivals closed' } else { 'Swapped into ~mods' }) }
    elseif ($j.Install -eq 'pending') { $s1 = 1; $t1 = 'Goes in when you quit Rivals' }
    elseif ($gs.Phase -eq 'unload') { $s1 = 1; $t1 = Pnl-GalactaShort $gs }
    else { $s1 = 4; $t1 = 'Not installed' }
    $ui.Step('Swap it in', $t1, $s1)
    if ($gs.Phase -eq 'unload') { $s2 = 0; $t2 = $(if (SS-GalAuto $gs) { 'Then F7 again, pressed for you' } else { 'Then F7 again - Galacta reloads them' }) }
    elseif ($gs.Phase -eq 'reload') { $s2 = 1; $t2 = Pnl-GalactaShort $gs }
    elseif ($gs.Loaded -eq $true) { $s2 = 2; $t2 = 'Galacta reloaded it' }
    elseif ($gs.Loaded -eq $false) { $s2 = 3; $t2 = 'Not reloaded - it shows at your next launch' }
    elseif ($gs.NoGame) { $s2 = 4; $t2 = 'Loads at your next launch' }
    elseif ($gs.Stopped) { $s2 = 4; $t2 = 'Stopped waiting' }
    else { $s2 = 4; $t2 = 'Press F7 twice in game to load it' }
    $ui.Step('Reload it with Galacta', $t2, $s2)
    if ($gs.Loaded -eq $true) { $s3 = 1; $t3 = 'Enter or leave the Practice Range or a match' }
    elseif ($gs.Phase -in @('unload', 'reload')) { $s3 = 0; $t3 = 'After a level change: the Practice Range or a match' }
    else { $s3 = 4; $t3 = 'At your next launch' }
    $ui.Step('See it on your hero', $t3, $s3)
    if ($gs.Phase -ne 'done' -or $gs.Loaded -eq $true) { $ui.Space(4); $ui.Label([string]$j.GalLine) }
}

# The Build mod screen: what it will do and the linked-map check before a
# build, the three steps while it runs, the outcome after.
function Pnl-DrawBuild($ui) {
    $st = $script:Pnl
    $j = $st.Job
    $running = ($j -and $j.Phase -notin @('done', 'failed'))
    $showJob = ($j -and ($running -or $j.Design -eq $st.DocPath))
    $title = if (-not $showJob) { 'Build mod' } elseif ($running) { $(if ($j.Phase -eq 'galacta') { 'Swapping in...' } else { 'Building...' }) } elseif ($j.Cancelled) { 'Build cancelled' } elseif ($j.Phase -eq 'failed') { 'Build failed' } else { 'Built' }
    $sub = if ($showJob) { $j.Title } else { Pnl-DocTitle }
    if (Pnl-TitleNav $ui $title $sub 'home') { return }
    $ui.Footer($st.Status, $st.Warn)
    $ui.BeginScroll('build')

    if (-not $showJob) {
        $doc = Pnl-Doc
        if (-not $doc -or -not (Pnl-DocMatches) -or -not (Pnl-DocHasEdits $doc)) {
            $ui.Hint('Nothing to build yet. Make an edit on your hero first - the design saves as you go.')
            $ui.EndScroll(); return
        }
        # Rivals running with Project Galacta: the build goes in through its F7
        $galRoute = ((Pnl-GameRunning) -and (Pnl-GalactaOn))
        $ui.Section('What happens')
        if ($galRoute) {
            $ui.Label(('Builds {0} into a real mod and swaps it into the game with Project Galacta - no restart.' -f (Pnl-DocTitle)))
            $ui.Hint('After the build Skin Studio presses Galacta''s F7 for you - unload, swap, reload - then you enter or leave the Practice Range or a match. If the game does not answer, this screen asks you to press F7.')
        } else {
            $ui.Label(('Builds {0} into a real mod and installs it. It shows on your hero at your next launch.' -f (Pnl-DocTitle)))
            $ui.Hint('Only Project Galacta can swap a built mod into a running game. With Galacta installed, this swaps it in right away - no restart.')
        }
        $mods = @($st.BuildMods | Where-Object { $_ })
        if ($mods.Count -gt 1) { $ui.Hint(('Makes {0} mods, one per skin: {1}.' -f $mods.Count, ($mods -join ', '))) }
        $ui.Hint('About half a minute. Keep playing - this screen and the home screen show how it is going.')
        if ($st.BuildGapsFor -eq $st.DocPath -and $st.BuildGaps.Count -gt 0) {
            $ui.Section('Heads-up')
            $names = ($st.BuildGaps | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension([string]$_.To) }) -join ', '
            $ui.Hint(('{0} map(s) you edited have a twin that is still vanilla - another form, or the lobby copy - so in game the mod would only half-change: {1}' -f $st.BuildGaps.Count, $names))
            $st.BuildFill = $ui.Toggle('fill', 'Copy my layers onto them first', [bool]$st.BuildFill, 'Recommended. Off builds the design exactly as it is.')
        }
        $ui.Space(4)
        if ($ui.Button('go', 'Build mod', 1)) { Pnl-Run { Pnl-StartBuild } }
        if ($galRoute) { $ui.Hint('Galacta swaps the whole mod, so material and particle colours come along too - after the level change.') }
        else { $ui.Hint('Until then the live preview keeps your edits on the hero. Particle and effect colours show only in the built mod.') }
        $ui.EndScroll(); return
    }

    # the three steps
    $sec = Pnl-Clock (Pnl-JobSeconds $j)
    $failedAt = if ($j.Phase -eq 'failed') { if (-not $j.Install) { 'build' } else { 'load' } } else { '' }
    $bState = if ($j.Phase -eq 'building') { 1 } elseif ($failedAt -eq 'build') { 3 } else { 2 }
    $bSub = if ($j.Phase -eq 'building') { ($(if ($j.Part) { $j.Part + ' - ' } else { '' })) + $j.Line + '  -  ' + $sec }
            elseif ($failedAt -eq 'build') { $j.Error } else { 'Built in ' + (Pnl-Clock ([double]$j.BuiltIn)) + ' - zip copied to Downloads' }
    $ui.Section('Progress')
    $ui.Step('Build the mod', $bSub, $bState)
    if ($j.Mount -eq 'galacta' -and $j.Swap) {
        Pnl-DrawGalactaSteps $ui $j
    } else {
        $iState = switch ($j.Install) { 'now' { 2 } 'pending' { 1 } default { if ($failedAt) { 4 } else { 0 } } }
        $iSub = if ($j.InstallNote) { $j.InstallNote } elseif ($failedAt) { 'Not installed' } else { 'Into ~mods, so it loads at every launch' }
        $ui.Step('Install it', $iSub, $iState)
        $n = $j.Loaded.Count
        $kept = if ($j.Pak) { @($j.Pak.Skipped).Count } else { 0 }
        $lState = 0; $lSub = if ((Pnl-GameRunning) -and (Pnl-GalactaOn)) { 'Swapped in with Project Galacta - no restart' } else { 'At your next launch' }
        switch ($j.Mount) {
            'true'    {
                if ($j.Phase -eq 'loading') { $lState = 1; $lSub = 'Mounted - swapping the textures in...' }
                elseif ($n -gt 0) { $lState = 2; $lSub = ('The game confirms {0} texture(s) now load from the mod itself' -f $n) + $(if ($kept) { ', {0} stay on the preview' -f $kept } else { '' }) }
                else { $lState = 3; $lSub = 'Mounted, but no texture loaded from it - the live preview stays' }
            }
            'false'   { $lState = 3; $lSub = 'The game would not mount it - the live preview stays until the next launch' }
            'timeout' { $lState = 3; $lSub = 'No answer - the in-game mod needs its update first' }
            'nofile'  { $lState = 3; $lSub = 'The game could not read the build list' }
            'skipped' { $lState = 4; $lSub = if ($j.PakNote) { 'Nothing to swap live: ' + $j.PakNote } else { 'Nothing to swap live' } }
            'nogame'  { $lState = 4; $lSub = 'Rivals is not running - it loads at the next launch' }
            'nogalacta' { $lState = 4; $lSub = 'At your next launch - no Galacta to swap it in now' }
            default   { if ($j.Phase -in @('packing', 'mounting')) { $lState = 1; $lSub = 'Mounting it in the game...' } elseif ($failedAt) { $lState = 4; $lSub = 'Skipped' } }
        }
        $ui.Step('Put it on your hero', $lSub, $lState)
    }
    $ui.Space(6)
    if ($j.Phase -eq 'building') {
        if ($ui.Button('cancel', 'Cancel build', 2)) { Pnl-Run { Pnl-CancelBuild } }
    } elseif ($j.Phase -eq 'galacta') {
        if ($ui.Button('galstop', 'Stop waiting', 2)) { Pnl-Run { Pnl-StopGalacta } }
        $ui.Hint('Whatever has not gone in yet then installs when you quit Rivals.')
    } elseif (-not $running) {
        # a build failure is already under its step; anything later is not
        if ($j.Phase -eq 'failed' -and $failedAt -ne 'build') { $ui.Label($j.Error, [SkinPanel]::Amber) }
        if ($j.Mods.Count -gt 1) { $ui.Hint(('Mods: {0}' -f ($j.Mods -join ', '))) }
        $ui.Hint('Build log: work\ingame\build\build.out, and work\<mod>\build.log for each mod.')
        $b = $ui.ButtonRow('after', [string[]]@($(if ($j.Phase -eq 'failed') { 'Try again' } else { 'Build again' }), 'Back'), 0)
        if ($b -eq 0) { $st.Job = $null; Pnl-OpenBuild }
        elseif ($b -eq 1) { Pnl-Go 'home' }
    }
    $ui.EndScroll()
}

function Pnl-DrawConfirm($ui) {
    $st = $script:Pnl
    $c = $st.Confirm
    if (-not $c) { Pnl-Go 'home'; return }
    if (Pnl-TitleNav $ui 'Are you sure?' '' $c.back) { return }
    $ui.Footer($st.Status, $st.Warn)
    $ui.BeginScroll('confirm')
    $ui.Space(8)
    $ui.Label($c.q)
    $ui.Space(8)
    $b = $ui.ButtonRow('cf', [string[]]@($c.yes, 'Cancel'), -1)
    if ($b -eq 0) { $act = $c.action; $st.Confirm = $null; Pnl-Go $c.back; & $act }
    elseif ($b -eq 1) { $st.Confirm = $null; Pnl-Go $c.back }
    $ui.EndScroll()
}

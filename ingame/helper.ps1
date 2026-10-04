# helper.ps1 - lets the in-game Skin Studio work without opening the app.
# Her ask 2026-09-27: the LIVE PREVIEW button in game, so the mod is self
# contained.
#
# The in-game panel is drawn by the watcher (live_preview.ps1 -WatchDesigns) on
# this PC - the game only shows a picture - so something here has to start the
# watcher when the app is closed. That is all this does, with no window:
#   - Rivals not running: nothing (one process check every few seconds).
#   - Rivals running, no watcher, and LIVE PREVIEW on (work\live_preview.on):
#     start one, so the designs are on the hero with no app open.
#   - Rivals running, no watcher, LIVE PREVIEW off, and F8 pressed (the game's
#     open_ message waiting unread): start one, and the panel opens on its
#     "Turn on live preview" screen.
# The watcher it starts ends with the game (-ExitWithGame). A watcher the app
# started (visible window) counts too: the helper never starts a second.
#
# Started by the app when it opens (ingame\livestate.ps1 LS-StartHelper); the
# app does not add it to Windows sign-in. One copy at a time (a named mutex).
#
#   powershell -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File helper.ps1
#   -SaveDir / -LiveFlag / -LogDir / -WatcherArgs / -Once: test seams
#   (RS_SS_GAMEPROC fakes the game)
#
# Keep this file ASCII: PS 5.1 reads a BOM-less script as Windows-1252.
param(
    [string]$SaveDir,
    [string]$LiveFlag,
    [string]$LogDir,
    # extra watcher arguments as ONE string (a test's -DesignDir / -LiveDir ...)
    [string]$WatcherArgs = '',
    [switch]$Once,
    # test seam: where build_colours.ps1 writes its designs (default: its own choice)
    [string]$ColourDesignDir = '',
    # test seam: the live texture folder Protect skin paints into
    [string]$ProtectLiveDir = '',
    # test seams for the named designs sync
    [string]$AppDesignDir = '',
    [string]$SyncStateFile = '',
    [string]$OpenRequestFile = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'livestate.ps1')
if (-not $SaveDir) { $SaveDir = $script:LS_SaveDir }
if (-not $LiveFlag) { $LiveFlag = $script:LS_Flag }
if (-not $LogDir) { $LogDir = Join-Path $script:LS_Root 'work\ingame' }
if (-not [IO.Directory]::Exists($LogDir)) { [void][IO.Directory]::CreateDirectory($LogDir) }
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}

$log = Join-Path $LogDir 'helper.log'
function HLog([string]$m) {
    $ln = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Write-Host $ln
    try {
        # a small rolling log: the last ~200 lines
        $old = if ([IO.File]::Exists($log)) { @([IO.File]::ReadAllLines($log)) } else { @() }
        if ($old.Count -gt 200) { $old = $old[($old.Count - 200)..($old.Count - 1)] }
        [IO.File]::WriteAllLines($log, [string[]](@($old) + $ln))
    } catch {}
}

$created = $false
$helperName = $script:LS_HelperMutex + $(if ($SaveDir -ine $script:LS_SaveDir) { '_' + ((LS-MutexName $SaveDir) -replace '^.*_', '') } else { '' })
$script:HelperMutex = New-Object Threading.Mutex($true, $helperName, [ref]$created)
if (-not $created) { Write-Host 'the Skin Studio helper is already running'; return }

# F8 pressed with nobody listening: the game's open_ message is still waiting
function Test-OpenWaiting {
    try {
        foreach ($f in [IO.Directory]::GetFiles($SaveDir, 'SLC_*_open_*.sav')) {
            if (([DateTime]::Now - [IO.File]::GetLastWriteTime($f)).TotalSeconds -lt 30) { return $true }
        }
    } catch {}
    $false
}

# The F8 colour panel's Build mod button (standalone mod, 2026-09-27): the game
# leaves SSBuild_<MI name>.sav; build that skin's colours into a mod and put
# its zip in Downloads (standalone\build_colours.ps1, hidden, one at a time).
# SkinStudioHelper.sav tells the panel someone here will answer.
$script:BuildColours = Join-Path $script:LS_Root 'standalone\build_colours.ps1'
$script:ColourBuild = $null
$script:ColourSkin = ''
function Write-HelperFlag {
    try {
        $hl = Join-Path $SaveDir 'HighlightSettings.sav'
        $bytes = if ([IO.File]::Exists($hl)) { [IO.File]::ReadAllBytes($hl) } else { [Text.Encoding]::ASCII.GetBytes('SkinStudio') }
        [IO.File]::WriteAllBytes((Join-Path $SaveDir 'SkinStudioHelper.sav'), $bytes)
    } catch {}
}
function Test-BuildRequests {
    $b = $script:ColourBuild
    if ($b -and $b.HasExited) {
        HLog ('colour build for {0} finished (exit {1}) - see colourbuild.log' -f $script:ColourSkin, $b.ExitCode)
        $script:ColourBuild = $null
    }
    $reqs = @()
    try { $reqs = @([IO.Directory]::GetFiles($SaveDir, 'SSBuild_*.sav')) } catch { return }
    foreach ($f in $reqs) {
        $name = [IO.Path]::GetFileNameWithoutExtension($f).Substring(8)
        try { [IO.File]::Delete($f) } catch { continue }
        $m = [regex]::Match($name, '_(\d{7})(?:_|$)')
        if (-not $m.Success) { HLog ('build request for {0}: no skin id in the name - ignored' -f $name); continue }
        if ($script:ColourBuild) { HLog ('build request for {0} ignored: a colour build is already running' -f $m.Groups[1].Value); continue }
        $script:ColourSkin = $m.Groups[1].Value
        # with Protect skin on, the build carries the same skin-safe Tint the game shows
        $prot = [IO.File]::Exists((Join-Path $SaveDir 'SkinStudioProtect.sav'))
        $script:ColourBuild = Start-Colours @('-Skin', $script:ColourSkin) $prot 'colourbuild'
        HLog ('colour build started for skin {0}{1} (pid {2})' -f $script:ColourSkin, $(if ($prot) { ', Protect skin' } else { '' }), $script:ColourBuild.Id)
    }
}
function Start-Colours([string[]]$more, [bool]$protect, [string]$logName) {
    $argv = @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', ('"{0}"' -f $script:BuildColours), '-SaveDir', ('"{0}"' -f $SaveDir)) + $more
    if ($protect) { $argv += '-Protect' }
    if ($ColourDesignDir) { $argv += @('-DesignDir', ('"{0}"' -f $ColourDesignDir)) }
    $p = Start-Process powershell.exe -ArgumentList $argv -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $LogDir ($logName + '.log')) -RedirectStandardError (Join-Path $LogDir ($logName + '.err'))
    $null = $p.Handle      # PS 5.1: keep the handle so ExitCode reads after exit
    $p
}

# Protect skin (the panel's toggle, 2026-09-27): SkinStudioProtect.sav = on;
# SSProtect_<MI name>.sav names the hero. While on, the colour panel's Tint for
# the hero on screen is repainted into its textures with the app's skin guard
# and handed straight to the game (standalone\protect_live.ps1) - live preview
# and the app designs are left alone (her report: the first version switched
# live preview on, which did "the same thing as the live preview button").
# A colour save change repaints; a respawn re-flags (SkinLiveOn lets the game's
# AutoTick leave SLA_<pawn> markers); a new hero repaints for its skin;
# switching off paints that skin back to vanilla.
$script:ProtectLive = Join-Path $script:LS_Root 'standalone\protect_live.ps1'
$script:ProtectFile = Join-Path $LogDir 'protect_skin.txt'
$script:ProtectSkin = if ([IO.File]::Exists($script:ProtectFile)) { [IO.File]::ReadAllText($script:ProtectFile).Trim() } else { '' }
$script:ProtectWas = [IO.File]::Exists((Join-Path $SaveDir 'SkinStudioProtect.sav'))
$script:ProtectStamp = [DateTime]::MinValue
$script:ProtectJob = $null
$script:ProtectNext = ''            # 'paint' | 'off' | 'flag' - what to run when the job slot is free
$script:ProtectFlagAt = @()         # extra re-flags after a respawn (the mesh attaches late)
$script:ProtectSeen = New-Object 'System.Collections.Generic.HashSet[string]'
$script:ProtectOnWritten = $false
$script:ProtectRetryAt = [DateTime]::MaxValue
$script:SltClearAt = $null
$script:LiveDesign = ''            # an app design loaded from the panel's list (its json), else Protect paints
$script:DesignDirApp = if ($AppDesignDir) { $AppDesignDir } else { Join-Path $script:LS_Root 'designs' }
$script:DesignSync = Join-Path $script:LS_Root 'standalone\design_sync.ps1'
function Set-ProtectSkin([string]$sid, [string]$why) {
    $script:ProtectSkin = $sid
    try { [IO.File]::WriteAllText($script:ProtectFile, $sid) } catch {}
    HLog ('Protect skin: skin {0} ({1})' -f $sid, $why)
}
function Start-Protect([string[]]$more) {
    $argv = @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', ('"{0}"' -f $script:ProtectLive), '-Skin', $script:ProtectSkin, '-SaveDir', ('"{0}"' -f $SaveDir)) + @($more | Where-Object { $_ })
    if ($ColourDesignDir) { $argv += @('-ProtectDir', ('"{0}"' -f $ColourDesignDir)) }
    if ($ProtectLiveDir) { $argv += @('-LiveDir', ('"{0}"' -f $ProtectLiveDir)) }
    $p = Start-Process powershell.exe -ArgumentList $argv -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $LogDir 'protectlive.log') -RedirectStandardError (Join-Path $LogDir 'protectlive.err')
    $null = $p.Handle
    $p
}
# the skin of a hero the colour save has edits for (most edits wins)
function Skin-ForHero([string]$hero) {
    $cs = Join-Path $SaveDir 'SkinStudioColors.sav'
    if (-not [IO.File]::Exists($cs)) { return '' }
    $txt = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($cs))
    $count = @{}
    foreach ($m in [regex]::Matches($txt, 'MI_(?:[A-Za-z0-9]+_)*?(' + $hero + '\d{3})(?:_[A-Za-z0-9_]*)?\|')) { $count[$m.Groups[1].Value] = 1 + [int]$count[$m.Groups[1].Value] }
    if ($count.Count -eq 0) { return '' }
    ($count.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Name
}
function Write-HelperFlagAs([string]$slot) {
    try {
        $hl = Join-Path $SaveDir 'HighlightSettings.sav'
        $bytes = if ([IO.File]::Exists($hl)) { [IO.File]::ReadAllBytes($hl) } else { [Text.Encoding]::ASCII.GetBytes('SkinStudio') }
        [IO.File]::WriteAllBytes((Join-Path $SaveDir ($slot + '.sav')), $bytes)
    } catch {}
}
function Test-Protect {
    $j = $script:ProtectJob
    if ($j -and $j.HasExited) {
        # 3 = the app's live preview owned the textures: try again in a while
        if ($j.ExitCode -eq 3) { $script:ProtectRetryAt = [DateTime]::Now.AddSeconds(15) }
        elseif ($j.ExitCode -ne 0) { HLog ('in-game paint for {0} failed (exit {1}) - see protectlive.err' -f $script:ProtectSkin, $j.ExitCode) }
        $script:ProtectJob = $null
        $script:SltClearAt = [DateTime]::Now.AddSeconds(15)
    }
    $on = [IO.File]::Exists((Join-Path $SaveDir 'SkinStudioProtect.sav'))
    $reqs = @()
    try { $reqs = @([IO.Directory]::GetFiles($SaveDir, 'SSProtect_*.sav')) } catch { return }
    foreach ($f in $reqs) {
        $name = [IO.Path]::GetFileNameWithoutExtension($f).Substring(10)
        try { [IO.File]::Delete($f) } catch { continue }
        $m = [regex]::Match($name, '_(\d{7})(?:_|$)')
        if (-not $m.Success) { HLog ('protect request for {0}: no skin id in the name - ignored' -f $name); continue }
        $script:LiveDesign = ''
        Set-ProtectSkin $m.Groups[1].Value 'turned on in game'
        $script:ProtectNext = 'paint'
    }
    # a design picked from the panel's list (SSLoad_<name>.sav): paint the app
    # design's textures as the app would; its colours the panel loads itself
    $loads = @()
    try { $loads = @([IO.Directory]::GetFiles($SaveDir, 'SSLoad_*.sav')) } catch {}
    foreach ($f in $loads) {
        $name = [IO.Path]::GetFileNameWithoutExtension($f).Substring(7)
        try { [IO.File]::Delete($f) } catch { continue }
        $dp = Join-Path $script:DesignDirApp ($name + '.json')
        if (-not [IO.File]::Exists($dp)) { HLog ('design {0} loaded in game - no app design of that name' -f $name); continue }
        try { $sk = [string](Get-Content -LiteralPath $dp -Raw | ConvertFrom-Json).skin } catch { $sk = '' }
        if (-not $sk) { HLog ('design {0} loaded in game - it names no skin, nothing to paint' -f $name); continue }
        $script:LiveDesign = $dp
        Set-ProtectSkin $sk ('design {0} loaded in game' -f $name)
        $script:ProtectNext = 'paint'
    }
    $painting = $on -or $script:LiveDesign
    # SkinLiveOn makes the game's AutoTick mark each new hero (SLA_<pawn>.sav);
    # the app's watcher owns it whenever it runs
    $watcher = LS-WatcherAlive $SaveDir
    $onFile = Join-Path $SaveDir 'SkinLiveOn.sav'
    if ($painting -and -not $watcher -and -not [IO.File]::Exists($onFile)) { Write-HelperFlagAs 'SkinLiveOn'; $script:ProtectOnWritten = $true }
    # nobody painting and no watcher: a SkinLiveOn left behind would keep the game's AutoTick announcing every hero
    if (-not $painting -and -not $watcher -and [IO.File]::Exists($onFile)) { try { [IO.File]::Delete($onFile) } catch {}; $script:ProtectOnWritten = $false }
    # the game has swapped the flagged textures (SkinLiveTex consumed): clear the SLT_ flags, or every later walk re-imports them
    if ($script:SltClearAt -and [DateTime]::Now -ge $script:SltClearAt -and -not [IO.File]::Exists((Join-Path $SaveDir 'SkinLiveTex.sav')) -and -not $watcher) {
        $script:SltClearAt = $null
        try { foreach ($s in [IO.Directory]::GetFiles($SaveDir, 'SLT_*.sav')) { [IO.File]::Delete($s) } } catch {}
    }
    if ($script:ProtectWas -and -not $on -and $script:ProtectSkin -and -not $script:LiveDesign) { HLog ('Protect skin off - {0} back to vanilla' -f $script:ProtectSkin); $script:ProtectNext = 'off' }
    $script:ProtectWas = $on
    if ($painting) {
        # a new hero on screen: SLA_<hero>_CharacterBP_...
        $marks = @()
        try { $marks = @([IO.Directory]::GetFiles($SaveDir, 'SLA_*.sav')) } catch {}
        foreach ($mk in $marks) {
            $leaf = [IO.Path]::GetFileNameWithoutExtension($mk)
            if (-not $script:ProtectSeen.Add($leaf)) { continue }
            $hm = [regex]::Match($leaf, '^SLA_(\d{4})_')
            if (-not $hm.Success) { continue }
            $hero = $hm.Groups[1].Value
            if ($script:ProtectSkin -and $script:ProtectSkin.StartsWith($hero)) {
                if (-not $script:ProtectNext) { $script:ProtectNext = 'flag' }
            } elseif ($on -and -not $script:LiveDesign) {
                $sid = Skin-ForHero $hero
                if ($sid) { Set-ProtectSkin $sid ('hero {0} spawned' -f $hero); $script:ProtectNext = 'paint' }
            }
            $script:ProtectFlagAt = @([DateTime]::Now.AddSeconds(4), [DateTime]::Now.AddSeconds(10))
        }
        $cs = Join-Path $SaveDir 'SkinStudioColors.sav'
        $t = if ([IO.File]::Exists($cs)) { [IO.File]::GetLastWriteTimeUtc($cs) } else { [DateTime]::MinValue }
        if ($t -ne $script:ProtectStamp) { $script:ProtectStamp = $t; if ($on -and $script:ProtectSkin -and -not $script:LiveDesign) { $script:ProtectNext = 'paint' } }
        if (-not $script:ProtectNext -and [DateTime]::Now -ge $script:ProtectRetryAt) { $script:ProtectRetryAt = [DateTime]::MaxValue; $script:ProtectNext = 'paint' }
        if (-not $script:ProtectNext -and @($script:ProtectFlagAt).Count -and [DateTime]::Now -ge $script:ProtectFlagAt[0]) {
            $script:ProtectFlagAt = @($script:ProtectFlagAt | Select-Object -Skip 1); $script:ProtectNext = 'flag'
        }
    }
    if (-not $script:ProtectNext -or $script:ProtectJob -or -not $script:ProtectSkin) { return }
    $what = $script:ProtectNext; $script:ProtectNext = ''
    $more = @(switch ($what) { 'off' { '-Off' } 'flag' { '-FlagOnly' } })
    if ($script:LiveDesign -and $what -ne 'off') { $more += @('-Design', ('"{0}"' -f $script:LiveDesign)) }
    $script:ProtectJob = Start-Protect $more
}

# Named designs (2026-09-27): standalone\design_sync.ps1 keeps the game's
# SSD_<name> slots and designs\<name>.json in step both ways. It runs when
# either side has changed (a cheap signature of both folders), one at a time.
$script:SyncJob = $null
$script:SyncSig = ''
$script:SyncNext = [DateTime]::MinValue
function Test-DesignSync {
    if ([DateTime]::Now -lt $script:SyncNext) { return }
    $script:SyncNext = [DateTime]::Now.AddSeconds(5)
    $j = $script:SyncJob
    if ($j) {
        if (-not $j.HasExited) { return }
        if ($j.ExitCode -ne 0) { HLog ('design sync failed (exit {0}) - see designsync.err' -f $j.ExitCode); $script:SyncSig = '' }
        $script:SyncJob = $null
    }
    $sig = ''
    try {
        $a = @([IO.Directory]::GetFiles($script:DesignDirApp, '*.json'))
        $g = @([IO.Directory]::GetFiles($SaveDir, 'SSD_*.sav'))
        $ta = ($a | ForEach-Object { [IO.File]::GetLastWriteTimeUtc($_).Ticks } | Measure-Object -Maximum).Maximum
        $tg = ($g | ForEach-Object { [IO.File]::GetLastWriteTimeUtc($_).Ticks } | Measure-Object -Maximum).Maximum
        $sig = '{0}|{1}|{2}|{3}' -f $a.Count, $ta, $g.Count, $tg
    } catch { return }
    if ($sig -eq $script:SyncSig) { return }
    $script:SyncSig = $sig
    $argv = @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', ('"{0}"' -f $script:DesignSync), '-SaveDir', ('"{0}"' -f $SaveDir), '-DesignDir', ('"{0}"' -f $script:DesignDirApp))
    if ($SyncStateFile) { $argv += @('-StateFile', ('"{0}"' -f $SyncStateFile), '-TrashDir', ('"{0}"' -f (Join-Path $LogDir 'trash'))) }
    $script:SyncJob = Start-Process powershell.exe -ArgumentList $argv -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $LogDir 'designsync.log') -RedirectStandardError (Join-Path $LogDir 'designsync.err')
    $null = $script:SyncJob.Handle
}

# "Open in App" (F8 panel, 2026-09-28): SSOpenApp_<name>.sav. Sync first (the
# design has just been saved in game), then hand the name to the app - a
# running one polls work\ingame\open_request.txt, a closed one is started with
# RS_SS_OPEN and loads it when its window shows.
function Test-OpenApp {
    $reqs = @()
    try { $reqs = @([IO.Directory]::GetFiles($SaveDir, 'SSOpenApp_*.sav')) } catch { return }
    foreach ($f in $reqs) {
        $name = [IO.Path]::GetFileNameWithoutExtension($f).Substring(10)
        try { [IO.File]::Delete($f) } catch { continue }
        $key = $name -replace '[^A-Za-z0-9]', ''
        if (-not $key) { continue }
        # the sync, now and to the end (a running one is let finish first)
        if ($script:SyncJob -and -not $script:SyncJob.HasExited) { $null = $script:SyncJob.WaitForExit(60000) }
        $argv = @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', ('"{0}"' -f $script:DesignSync), '-SaveDir', ('"{0}"' -f $SaveDir), '-DesignDir', ('"{0}"' -f $script:DesignDirApp))
        if ($SyncStateFile) { $argv += @('-StateFile', ('"{0}"' -f $SyncStateFile), '-TrashDir', ('"{0}"' -f (Join-Path $LogDir 'trash'))) }
        $p = Start-Process powershell.exe -ArgumentList $argv -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput (Join-Path $LogDir 'designsync.log') -RedirectStandardError (Join-Path $LogDir 'designsync.err')
        $null = $p.WaitForExit(120000)
        $script:SyncSig = ''
        $app = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'SkinStudio\.ps1' })
        if ($app.Count) {
            [IO.File]::WriteAllText($script:OpenRequestFile, $key)
            HLog ('Open in App: {0} -> the running app' -f $name)
        } else {
            $env:RS_SS_OPEN = $key
            Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', ('"{0}"' -f (Join-Path $script:LS_Root 'SkinStudio.ps1')))
            $env:RS_SS_OPEN = ''
            HLog ('Open in App: {0} -> started the app' -f $name)
        }
    }
}
$script:OpenRequestFile = if ($OpenRequestFile) { $OpenRequestFile } else { Join-Path $script:LS_Root 'work\ingame\open_request.txt' }
HLog ('helper up (pid {0}) - watching for Rivals' -f $PID)
$lastStart = [DateTime]::MinValue
$fails = 0
$wasUp = $false
$lastModCheck = [DateTime]::MinValue
while ($true) {
    $up = LS-GameUp
    if ($up -ne $wasUp) { HLog $(if ($up) { 'Rivals is running' } else { 'Rivals closed' }); $wasUp = $up; if ($up) { Write-HelperFlag } }
    # a Vortex install or update can land the in-game mod in a folder that
    # loads after other mods: check about once a minute while the game is closed
    if (-not $up -and ([DateTime]::Now - $lastModCheck).TotalSeconds -ge 60) {
        $lastModCheck = [DateTime]::Now
        try { $m = LS-EnsureLiveModAtRoot; if ($m) { HLog $m } } catch {}
    }
    Test-BuildRequests
    Test-Protect
    Test-DesignSync
    Test-OpenApp
    if ($up -and -not (LS-WatcherAlive $SaveDir)) {
        $on = LS-FlagOn $LiveFlag
        $why = if ($on) { 'live preview is on' } elseif (Test-OpenWaiting) { 'F8 pressed' } else { '' }
        # a watcher that died at once is not restarted in a tight loop
        $wait = if ($fails -ge 3) { 300 } else { 20 }
        if ($why -and ([DateTime]::Now - $lastStart).TotalSeconds -ge $wait) {
            $extra = @(); if ($WatcherArgs) { $extra += $WatcherArgs }
            if ($SaveDir -ine $script:LS_SaveDir) { $extra += @('-SaveDir', ('"{0}"' -f $SaveDir)) }
            if ($LiveFlag -ine $script:LS_Flag) { $extra += @('-LiveFlag', ('"{0}"' -f $LiveFlag)) }
            $p = LS-StartHiddenWatcher $extra $LogDir
            $lastStart = [DateTime]::Now
            HLog ('started the watcher (pid {0}): {1}' -f $p.Id, $why)
            # it has a few seconds to take its mutex; one that is gone by then failed
            for ($i = 0; $i -lt 40 -and -not $p.HasExited -and -not (LS-WatcherAlive $SaveDir); $i++) { Start-Sleep -Milliseconds 250 }
            if ($p.HasExited) { $fails++; HLog ('the watcher stopped at once (exit {0}) - see watcher.err beside this log' -f $p.ExitCode) } else { $fails = 0 }
        }
    }
    if ($Once) { break }
    Start-Sleep -Seconds $(if ($up) { 1 } else { 4 })
}

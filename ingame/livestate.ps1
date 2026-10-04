# livestate.ps1 - LIVE PREVIEW's on/off state, shared by the desktop app
# (SkinStudio.ps1), the watcher (live_preview.ps1) and the in-game helper
# (ingame\helper.ps1). Her ask 2026-09-27: the LIVE PREVIEW button in game too,
# so the in-game mod works without opening the app.
#
# One truth for "on": the file work\live_preview.on (the desktop's sticky flag
# since 2026-09-22). Whoever flips it - the app's button or the in-game one -
# every other part follows it.
# One watcher at a time: it holds a named mutex while it runs, so the helper
# and the app can both see it, whoever started it. A test watcher (its own
# -SaveDir) gets a mutex of its own and never blocks the real one.
#
# Light on purpose: the helper dot-sources this and nothing else, so no
# skinlib, no Add-Type. Keep this file ASCII (PS 5.1 reads a BOM-less script
# as Windows-1252).

$script:LS_Root = Split-Path $PSScriptRoot -Parent
$script:LS_Flag = Join-Path $script:LS_Root 'work\live_preview.on'
$script:LS_SaveDir = Join-Path $env:LOCALAPPDATA 'Marvel\Saved\SaveGames'

# the watcher's mutex: '' = the real game folder, else one per test folder
function LS-MutexName([string]$saveDir) {
    $base = 'Local\ChicorySkinStudioWatcher'
    if (-not $saveDir -or $saveDir.TrimEnd('\') -ieq $script:LS_SaveDir) { return $base }
    $md5 = [Security.Cryptography.MD5]::Create()
    $h = ([BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($saveDir.TrimEnd('\').ToLowerInvariant()))) -replace '-', '').Substring(0, 8)
    $md5.Dispose()
    $base + '_' + $h
}

# is a watcher running for this save folder (whoever started it)?
function LS-WatcherAlive([string]$saveDir) {
    $m = $null
    if ([Threading.Mutex]::TryOpenExisting((LS-MutexName $saveDir), [ref]$m)) { $m.Dispose(); return $true }
    $false
}

# the watcher takes its mutex; $null = another watcher already has it
function LS-TakeWatcherMutex([string]$saveDir) {
    $created = $false
    $m = New-Object Threading.Mutex($true, (LS-MutexName $saveDir), [ref]$created)
    if (-not $created) { $m.Dispose(); return $null }
    $m
}

function LS-FlagOn([string]$flag = $script:LS_Flag) { [IO.File]::Exists($flag) }
function LS-SetFlag([bool]$on, [string]$flag = $script:LS_Flag) {
    if ($on) {
        $dir = Split-Path $flag -Parent
        if (-not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }
        [IO.File]::WriteAllText($flag, (Get-Date -Format s))
    } elseif ([IO.File]::Exists($flag)) {
        [IO.File]::Delete($flag)
    }
}

# Rivals itself or its launcher (RS_SS_GAMEPROC = a stand-in process for tests)
function LS-GameUp {
    $names = if ($env:RS_SS_GAMEPROC) { @($env:RS_SS_GAMEPROC) } else { @('Marvel-Win64-Shipping', 'MarvelRivals') }
    [bool](Get-Process -Name $names -ErrorAction SilentlyContinue)
}

# the in-game helper (ingame\helper.ps1): running? start it (no window)
$script:LS_HelperMutex = 'Local\ChicorySkinStudioHelper'
function LS-HelperAlive {
    $m = $null
    if ([Threading.Mutex]::TryOpenExisting($script:LS_HelperMutex, [ref]$m)) { $m.Dispose(); return $true }
    $false
}
function LS-StartHelper {
    if (LS-HelperAlive) { return $false }
    $argv = @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f (Join-Path $PSScriptRoot 'helper.ps1')))
    Start-Process powershell.exe -ArgumentList $argv -WorkingDirectory $script:LS_Root -WindowStyle Hidden | Out-Null
    $true
}

# The watcher for the game, with no window (a window would take focus from
# Rivals): live preview on or off comes from the flag, and it ends when the game
# does. Its console goes to work\ingame\watcher.out / .err (or $logDir).
function LS-StartHiddenWatcher([string[]]$extra = @(), [string]$logDir = '') {
    $dir = if ($logDir) { $logDir } else { Join-Path $script:LS_Root 'work\ingame' }
    if (-not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }
    $out = Join-Path $dir 'watcher.out'; $err = Join-Path $dir 'watcher.err'
    foreach ($f in @($out, $err)) {
        # keep the previous run's log beside the new one
        if ([IO.File]::Exists($f)) { try { [IO.File]::Copy($f, $f + '.prev', $true); [IO.File]::Delete($f) } catch {} }
    }
    # Start-Process joins -ArgumentList with bare spaces in PS 5.1: quote paths
    $argv = @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', ('"{0}"' -f (Join-Path $script:LS_Root 'live_preview.ps1')), '-WatchDesigns', '-ExitWithGame') + @($extra)
    $p = Start-Process powershell.exe -ArgumentList $argv -WorkingDirectory $script:LS_Root -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    $null = $p.Handle      # PS 5.1: without holding the handle, ExitCode reads empty after exit
    $p
}

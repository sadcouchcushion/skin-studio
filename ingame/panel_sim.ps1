# panel_sim.ps1 - the in-game panel, on the desktop.
#
# Stands in for the game: shows <LiveDir>\_panel.png in a window and sends the
# same SLC_ messages the Blueprint sends - mouse down / move / up, the wheel,
# the hero's texture list, and the texture-refresh handshake. So the whole panel
# can be used and judged before any of it exists in Unreal, and afterwards it is
# still the fastest way to try a change without launching Rivals.
#
#   ingame\panel_sim.ps1                       the game's own folders
#   ingame\panel_sim.ps1 -Skin 1064300         pretend that skin is on screen
#   ingame\panel_sim.ps1 -SaveDir <d> -LiveDir <d>   a test rig's folders
#
# live_preview.ps1 must be watching (the LIVE PREVIEW button) - it is what
# draws the frames.
param(
    [string]$SaveDir,
    [string]$LiveDir,
    [string]$Skin,
    [string[]]$Textures = @(),
    # what Rivals itself reports at 1080p: a UMG DPI scale of ~0.5. The panel
    # must not care (it sizes from the pixels), and this keeps that tested.
    [int]$Vw = 1920, [int]$Vh = 1080, [int]$Scale = 50
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\skinlib.ps1"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

if (-not $SaveDir) { $SaveDir = Join-Path $env:LOCALAPPDATA 'Marvel\Saved\SaveGames' }
if (-not $LiveDir) { $LiveDir = Join-Path (Split-Path $SS_Paks -Parent) 'SkinStudioLive' }
New-Item -ItemType Directory -Force -Path $SaveDir, $LiveDir | Out-Null
$framePath = Join-Path $LiveDir '_panel.png'

# --- the hero's textures. The game announces one BaseColor name per material
# slot; here they come from the skin cache, or from -Textures.
if ($Textures.Count -eq 0 -and $Skin) {
    $tm = Join-Path $SS_Cache (Join-Path $Skin 'thumbs.map')
    if (Test-Path -LiteralPath $tm) {
        $Textures = @(foreach ($line in [IO.File]::ReadAllLines($tm)) {
            $f = $line -split '\|'
            if ($f.Count -ge 4 -and $f[3] -eq 'color') {
                $leaf = [IO.Path]::GetFileNameWithoutExtension((Split-Path $f[0] -Leaf))
                if ($leaf -match '_D$') { $leaf }
            }
        })
    } else {
        Write-Warning "no cache for skin $Skin yet - open it once in Skin Studio, or pass -Textures"
    }
}
if ($Textures.Count -eq 0) {
    # whatever is live in the drop folder is a fair guess at what is on screen
    $Textures = @(Get-ChildItem -LiteralPath $LiveDir -Filter 'T_*_D.png' -File -ErrorAction SilentlyContinue |
                  ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) })
}

$flagBytes = [byte[]]@(83, 75, 76, 86)
$hl = Join-Path $SaveDir 'HighlightSettings.sav'
if (Test-Path -LiteralPath $hl) { $flagBytes = [IO.File]::ReadAllBytes($hl) }
$script:T0 = [DateTime]::UtcNow

function Send-Cmd([string[]]$cmds) {
    $ms = [long]([DateTime]::UtcNow - $script:T0).TotalMilliseconds
    foreach ($c in $cmds) {
        $p = Join-Path $SaveDir ('SLC_{0}_{1}.sav' -f $ms, $c)
        try { [IO.File]::WriteAllBytes($p, $flagBytes) } catch {}
    }
}

# --- window
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Skin Studio - in-game panel (desktop stand-in)'
$form.StartPosition = 'Manual'
$scr = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.ClientSize = New-Object System.Drawing.Size 430, 929
$form.Location = New-Object System.Drawing.Point ($scr.Right - 470), ($scr.Top + 20)
$form.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 24)
$form.TopMost = $true
$pic = New-Object System.Windows.Forms.PictureBox
$pic.Dock = 'Fill'
$pic.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 24)
$pic.SizeMode = 'Normal'
$form.Controls.Add($pic)

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = "waiting for the first frame...`r`n(is LIVE PREVIEW on?)"
$lbl.ForeColor = [System.Drawing.Color]::FromArgb(190, 214, 182)
$lbl.BackColor = [System.Drawing.Color]::Transparent
$lbl.AutoSize = $true
$lbl.Location = New-Object System.Drawing.Point 18, 18
$pic.Controls.Add($lbl)

# a frame is a file the server rewrites; read a COPY so nothing is ever locked
function Load-Frame {
    try {
        $bytes = [IO.File]::ReadAllBytes($framePath)
        $ms = New-Object IO.MemoryStream (, $bytes)
        $img = [System.Drawing.Image]::FromStream($ms)
        $bmp = New-Object System.Drawing.Bitmap $img
        $img.Dispose(); $ms.Dispose()
        $old = $pic.Image
        $pic.Image = $bmp
        if ($old) { $old.Dispose() }
        if ($form.ClientSize.Width -ne $bmp.Width -or $form.ClientSize.Height -ne $bmp.Height) {
            $form.ClientSize = New-Object System.Drawing.Size $bmp.Width, $bmp.Height
        }
        $lbl.Visible = $false
        $true
    } catch { $false }
}

function Size-Text { '{0}_{1}' -f $pic.ClientSize.Width, $pic.ClientSize.Height }

$script:lastMove = [DateTime]::MinValue
$pic.Add_MouseDown({ Send-Cmd @(('d_{0}_{1}_{2}' -f $_.X, $_.Y, (Size-Text))) })
$pic.Add_MouseUp({ Send-Cmd @(('u_{0}_{1}_{2}' -f $_.X, $_.Y, (Size-Text))) })
$pic.Add_MouseMove({
    # the game sends moves at 15 Hz; match it so the server sees the same load
    if (([DateTime]::UtcNow - $script:lastMove).TotalMilliseconds -lt 66) { return }
    $script:lastMove = [DateTime]::UtcNow
    Send-Cmd @(('m_{0}_{1}_{2}' -f $_.X, $_.Y, (Size-Text)))
})
$pic.Add_MouseWheel({ Send-Cmd @($(if ($_.Delta -gt 0) { 'wu' } else { 'wd' })) })

# the game's side of the handshake: consume the flags, then say so
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 80
$timer.Add_Tick({
    $f = Join-Path $SaveDir 'SkinLiveFrame.sav'
    if (Test-Path -LiteralPath $f) {
        try { [IO.File]::Delete($f) } catch {}
        [void](Load-Frame)
    }
    $t = Join-Path $SaveDir 'SkinLiveTex.sav'
    if (Test-Path -LiteralPath $t) {
        try { [IO.File]::Delete($t) } catch {}
        Send-Cmd @('texok')
    }
    $c = Join-Path $SaveDir 'SkinLiveClose.sav'
    if (Test-Path -LiteralPath $c) {
        try { [IO.File]::Delete($c) } catch {}
        $form.Close()
    }
})

$form.Add_Shown({
    Send-Cmd @(('open_{0}_{1}_{2}' -f $Vw, $Vh, $Scale))
    if ($Textures.Count -gt 0) { Send-Cmd @($Textures | ForEach-Object { 't_' + $_ }) }
    Send-Cmd @('tend')
    $timer.Start()
    $pic.Focus()
})
$form.Add_FormClosing({ $timer.Stop(); Send-Cmd @('close') })

# a throw inside a WinForms handler otherwise leaves a modal .NET box nobody
# can answer, re-raising on every repaint
[System.Windows.Forms.Application]::add_ThreadException({
    param($s, $e)
    Write-Host ('panel_sim ERROR: ' + $e.Exception.Message)
})
Write-Host ('panel stand-in: {0} texture(s) announced, save dir {1}' -f $Textures.Count, $SaveDir)
[System.Windows.Forms.Application]::Run($form)

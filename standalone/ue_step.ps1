param([string]$File, [string]$Win = 'WBP_SkinStudioPanel', [switch]$NoPaste, [int]$Wait = 6)
$d = 'C:\rs\SkinStudio\ingame\ue_drive.ps1'; $log = 'D:\SkinStudioProbeUE\Saved\Logs\SkinProbe.log'
$before = (Get-Content $log).Count
if (-not $NoPaste) {
    & $d -Do click -X 700 -Y 560 -WinMatch $Win | Out-Null
    & $d -Do paste -File $File -WinMatch $Win
    Start-Sleep -Seconds ([Math]::Max(4, [int]((Get-Item $File).Length / 150000)))
}
& $d -Do click -X 344 -Y 252 -WinMatch $Win | Out-Null
Start-Sleep -Seconds $Wait
$new = @(Get-Content $log | Select-Object -Skip $before)
$msgs = @($new | Where-Object { $_ -match '\[Compiler\]' } | ForEach-Object { ($_ -replace '^.*\[Compiler\]\s*', '') } | Sort-Object -Unique)
'compiler lines: {0}' -f $msgs.Count
$msgs | Select-Object -First 25
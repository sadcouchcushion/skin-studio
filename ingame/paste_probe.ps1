# paste_probe.ps1 - paste a T3D file into the open Blueprint graph and report how
# many nodes actually landed, by copying the graph back out and counting blocks.
#
# UE rejects a whole paste silently when any part of it will not parse, so this
# is the bisection tool: feed it a subset of blocks and see whether they arrive.
#
#   paste_probe.ps1 -File D:\SkinLiveUE\paste\editor_1.txt [-KeepExisting]
#   paste_probe.ps1 -File ... -First 10        only the first 10 node blocks
#   paste_probe.ps1 -Clear                     empty the graph and report
param(
    [string]$File,
    [int]$First = 0,
    [int]$Skip = 0,
    [switch]$KeepExisting,
    [switch]$Clear,
    [int]$X = 1300, [int]$Y = 700
)
$ErrorActionPreference = 'Stop'
$drive = Join-Path $PSScriptRoot 'ue_drive.ps1'

function Send([string]$do, [hashtable]$extra) {
    $a = @{ Do = $do; NoFocus = $true }
    foreach ($k in $extra.Keys) { $a[$k] = $extra[$k] }
    & $drive @a | Out-Null
}
function Graph-Nodes {
    # copy whatever is in the graph and count the node blocks
    Set-Clipboard -Value '<empty>'
    Start-Sleep -Milliseconds 150
    Send 'click' @{ X = $X; Y = $Y }
    Send 'keys' @{ Text = 'ctrl+a'; Settle = 300 }
    Send 'keys' @{ Text = 'ctrl+c'; Settle = 600 }
    $c = Get-Clipboard -Raw
    if (-not $c -or $c -eq '<empty>') { return 0 }
    ([regex]::Matches($c, '(?m)^Begin Object Class=')).Count
}

$null = & $drive -Do focus
if (-not $KeepExisting) {
    Send 'click' @{ X = $X; Y = $Y }
    Send 'keys' @{ Text = 'ctrl+a'; Settle = 300 }
    Send 'keys' @{ Text = 'delete'; Settle = 700 }
}
if ($Clear) { "graph now holds {0} node(s)" -f (Graph-Nodes); return }

if (-not $File) { throw 'give me -File' }
$src = [IO.File]::ReadAllText($File)
$blocks = @([regex]::Matches($src, '(?s)Begin Object Class=.*?\r?\nEnd Object\r?\n?') | ForEach-Object { $_.Value })
$use = $blocks
if ($Skip -gt 0) { $use = @($use | Select-Object -Skip $Skip) }
if ($First -gt 0) { $use = @($use | Select-Object -First $First) }
$tmp = Join-Path $env:TEMP ('_paste_probe_{0}.txt' -f [Guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.File]::WriteAllText($tmp, ($use -join ''))

Send 'click' @{ X = $X; Y = $Y }
Send 'paste' @{ File = $tmp }
Start-Sleep -Milliseconds 600
$n = Graph-Nodes
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
"{0}: offered {1} of {2} block(s) -> graph holds {3}" -f (Split-Path $File -Leaf), $use.Count, $blocks.Count, $n

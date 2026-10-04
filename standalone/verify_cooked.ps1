# verify_cooked.ps1 - what a cooked Blueprint class really calls: final/static
# calls by import (StackNode) and virtual calls by name ("virtual ..."). A wire
# that did not survive a paste prunes its node without a word, so count.
param([Parameter(Mandatory)][string]$Asset)
$ErrorActionPreference = 'Stop'
$uat = Join-Path $env:LOCALAPPDATA 'Atelier\Tools\UAssetTool.exe'
$usmap = [string](Get-Content (Join-Path $env:LOCALAPPDATA 'Atelier\mr_config.json') -Raw | ConvertFrom-Json).usmap
$tmp = Join-Path $env:TEMP ('_vc_' + [IO.Path]::GetFileNameWithoutExtension($Asset))
New-Item -ItemType Directory -Force $tmp | Out-Null
$eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$null = & $uat to_json $Asset $usmap $tmp 2>&1
$ErrorActionPreference = $eap
$j = Get-Content (Join-Path $tmp ([IO.Path]::GetFileNameWithoutExtension($Asset) + '.json')) -Raw | ConvertFrom-Json
$calls = New-Object System.Collections.ArrayList
function Walk-Node($n) {
    if ($null -eq $n) { return }
    if ($n -is [System.Management.Automation.PSCustomObject]) {
        if ($n.PSObject.Properties['StackNode'] -and $n.PSObject.Properties['Parameters']) {
            $idx = [int]$n.StackNode
            $nm = if ($idx -lt 0) { [string]$j.Imports[-$idx - 1].ObjectName } else { "export$idx" }
            [void]$calls.Add($nm)
        }
        if ($n.PSObject.Properties['VirtualFunctionName'] -and $n.PSObject.Properties['Parameters']) { [void]$calls.Add('virtual ' + [string]$n.VirtualFunctionName) }
        foreach ($p in $n.PSObject.Properties) { if ($p.Value -is [System.Management.Automation.PSCustomObject] -or ($p.Value -is [System.Collections.IList] -and $p.Value -isnot [string])) { Walk-Node $p.Value } }
    } elseif ($n -is [System.Collections.IList] -and $n -isnot [string]) { foreach ($x in $n) { Walk-Node $x } }
}
Walk-Node $j.Exports
$calls | Group-Object | Sort-Object Name | ForEach-Object { [pscustomobject]@{ Call = $_.Name; N = $_.Count } }
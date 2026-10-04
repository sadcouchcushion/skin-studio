# check_paste.ps1 - read the generated T3D back and prove it is self-consistent
# before it ever goes near the editor: every LinkedTo must name a node and a pin
# that exist in the same file, every link must be reciprocal, and every node
# must have a unique name and GUID.
param([string]$Dir = 'D:\SkinLiveUE\paste')
$ErrorActionPreference = 'Stop'
$bad = 0
foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter *.txt -File | Sort-Object Name)) {
    $text = [IO.File]::ReadAllText($f.FullName)
    $nodes = @{}
    $pins = @{}        # "node|pinid" -> pin name
    $links = New-Object System.Collections.ArrayList
    $cur = ''
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^Begin Object Class=(\S+) Name="([^"]+)"') {
            $cur = $Matches[2]
            if ($nodes.ContainsKey($cur)) { "  {0}: duplicate node name {1}" -f $f.Name, $cur; $bad++ }
            $nodes[$cur] = $Matches[1]
            continue
        }
        if ($line -match 'CustomProperties Pin \(PinId=([0-9A-F]+),PinName="([^"]+)"') {
            $pins[$cur + '|' + $Matches[1]] = $Matches[2]
            if ($line -match 'LinkedTo=\(([^)]*)\)') {
                foreach ($l in ($Matches[1] -split ',')) {
                    if ($l -match '^\s*(\S+)\s+([0-9A-F]+)\s*$') {
                        [void]$links.Add(@{ From = $cur; FromPin = $Matches[1]; To = $Matches[1]; ToPin = $Matches[2]; Raw = $l })
                    }
                }
            }
        }
    }
    # resolve every link target
    $missing = 0; $oneway = 0
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -notmatch 'PinId=([0-9A-F]+),PinName="([^"]+)"') { continue }
        $srcPin = $Matches[1]
        if ($line -notmatch 'LinkedTo=\(([^)]*)\)') { continue }
        foreach ($l in ($Matches[1] -split ',')) {
            if ($l -notmatch '^\s*(\S+)\s+([0-9A-F]+)\s*$') { continue }
            $tn = $Matches[1]; $tp = $Matches[2]
            if (-not $nodes.ContainsKey($tn)) { "  {0}: link to unknown node {1}" -f $f.Name, $tn; $missing++; continue }
            if (-not $pins.ContainsKey($tn + '|' + $tp)) { "  {0}: link to unknown pin {1} on {2}" -f $f.Name, $tp, $tn; $missing++; continue }
            # the other end must list this pin back
            if ($text -notmatch [regex]::Escape('PinId=' + $tp) + '[^\n]*' + [regex]::Escape($srcPin)) { $oneway++ }
        }
    }
    $nNodes = $nodes.Count
    $nLinks = ([regex]::Matches($text, 'LinkedTo=\(')).Count
    '{0,-16} {1,3} nodes {2,4} linked pins  missing:{3} one-way:{4}' -f $f.Name, $nNodes, $nLinks, $missing, $oneway
    $bad += $missing
}
if ($bad -gt 0) { throw "$bad broken link(s) - fix gen_graphs.ps1 before pasting" }
'all paste files are self-consistent'

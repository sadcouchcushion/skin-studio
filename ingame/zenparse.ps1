# zenparse.ps1 - minimal UE5.3 Zen package header reader.
# Reads the summary, name map, export map and dependency bundles of a raw
# Zen package chunk (as produced by "retoc get" / "retoc unpack-raw").
param([Parameter(Mandatory)][string]$Path)

$b = [System.IO.File]::ReadAllBytes($Path)
function U32([int]$o) { [System.BitConverter]::ToUInt32($b, $o) }
function I32([int]$o) { [System.BitConverter]::ToInt32($b, $o) }
function U64([int]$o) { [System.BitConverter]::ToUInt64($b, $o) }

$sum = [ordered]@{
    HasVersioningInfo             = U32 0
    HeaderSize                    = U32 4
    NameIndex                     = U32 8
    NameNumber                    = U32 12
    PackageFlags                  = U32 16
    CookedHeaderSize              = U32 20
    ImportedPublicExportHashesOff = I32 24
    ImportMapOff                  = I32 28
    ExportMapOff                  = I32 32
    ExportBundleEntriesOff        = I32 36
    DependencyBundleHeadersOff    = I32 40
    DependencyBundleEntriesOff    = I32 44
    ImportedPackageNamesOff       = I32 48
}

# ---- name map (starts right after the 52-byte FZenPackageSummary) ----
$p    = 52
$nNum = U32 $p; $p += 4
$nStr = U32 $p; $p += 4
$p += 8                      # hash version
$p += $nNum * 8              # hashes
$hdrAt = $p
$p += $nNum * 2              # FSerializedNameHeader[]
$names = New-Object string[] $nNum
for ($i = 0; $i -lt $nNum; $i++) {
    $h0 = $b[$hdrAt + $i * 2]; $h1 = $b[$hdrAt + $i * 2 + 1]
    $utf16 = ($h0 -band 0x80) -ne 0
    $len   = ((($h0 -band 0x7F) -shl 8) -bor $h1)
    if ($utf16) { $names[$i] = [System.Text.Encoding]::Unicode.GetString($b, $p, $len * 2); $p += $len * 2 }
    else        { $names[$i] = [System.Text.Encoding]::ASCII.GetString($b, $p, $len);       $p += $len }
}

function NameOf([uint32]$idx, [uint32]$num) {
    $i = $idx -band 0x3FFFFFFF
    $s = if ($i -lt $names.Count) { $names[$i] } else { "<oob:$i>" }
    if ($num -gt 0) { "$s`_$($num - 1)" } else { $s }
}

# ---- export map ----
$expOff = $sum.ExportMapOff
$expCnt = [int](($sum.ExportBundleEntriesOff - $expOff) / 72)
$exports = @()
for ($i = 0; $i -lt $expCnt; $i++) {
    $e = $expOff + $i * 72
    $exports += [pscustomobject]@{
        Idx      = $i
        Offset   = U64 $e
        Size     = U64 ($e + 8)
        Name     = NameOf (U32 ($e + 16)) (U32 ($e + 20))
        Outer    = ("0x{0:X16}" -f (U64 ($e + 24)))
        Class    = ("0x{0:X16}" -f (U64 ($e + 32)))
        Super    = ("0x{0:X16}" -f (U64 ($e + 40)))
        Template = ("0x{0:X16}" -f (U64 ($e + 48)))
        Flags    = ("0x{0:X8}"  -f (U32 ($e + 64)))
    }
}

# ---- dependency bundles ----
$dhOff = $sum.DependencyBundleHeadersOff
$deOff = $sum.DependencyBundleEntriesOff
$deEnd = $sum.ImportedPackageNamesOff
$bundles = @()
for ($i = 0; $i -lt $expCnt; $i++) {
    $h = $dhOff + $i * 20
    $first = I32 $h
    $c = @( (I32 ($h + 4)), (I32 ($h + 8)), (I32 ($h + 12)), (I32 ($h + 16)) )
    $ents = @()
    $k = $first
    foreach ($n in $c) {
        $grp = @()
        for ($j = 0; $j -lt $n; $j++) { $grp += (I32 ($deOff + $k * 4)); $k++ }
        $ents += ,$grp
    }
    $bundles += [pscustomobject]@{ Idx = $i; First = $first; Counts = $c; Entries = $ents }
}

[pscustomobject]@{
    Summary     = [pscustomobject]$sum
    Names       = $names
    Exports     = $exports
    Bundles     = $bundles
    DepEntCount = [int](($deEnd - $deOff) / 4)
}

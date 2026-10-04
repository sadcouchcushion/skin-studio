# Repairs FModel's Marvel Rivals settings in AppSettings.json (run while FModel
# is CLOSED - it rewrites the file on exit). Raw text surgery, no JSON
# roundtrip (PS 5.1 ConvertTo-Json mangles dates/structure).
$ErrorActionPreference = 'Stop'
$cfg = Join-Path $env:APPDATA 'FModel\AppSettings.json'
$txt = [IO.File]::ReadAllText($cfg)
$changes = @()

# 1) AES key (the only empty mainKey is the Rivals entry)
$aesOld = '"mainKey": ""'
$aesNew = '"mainKey": "0x0C263D8C22DCB085894899C3A3796383E9BF9DE0CBFB08C9BF2DEF2E84F29D74"'
if ($txt.Contains($aesOld)) { $txt = $txt.Replace($aesOld, $aesNew); $changes += 'AES key set' }
elseif ($txt.Contains('0C263D8C22DCB085')) { $changes += 'AES key already set' }

# 2) mesh export format -> glTF 2.0 (enum 1; 3 = UEFormat which Blender cannot read)
if ($txt -match '"MeshExportFormat": \d+') {
    $txt = $txt -replace '"MeshExportFormat": \d+', '"MeshExportFormat": 1'
    $changes += 'mesh format = glTF 2.0'
}

# 2a) UeVersion must be GAME_MarvelRivals (84082689 = UE5_3+1), not plain UE5_3
# (84082688) - the NetEase mesh serialization overrides are gated on it.
# Fortnite's entry is 84410368 so the bare value is unique to the Rivals entry.
if ($txt.Contains('"UeVersion": 84082688')) {
    $txt = $txt.Replace('"UeVersion": 84082688', '"UeVersion": 84082689')
    $changes += 'UeVersion -> GAME_MarvelRivals'
}

# 2b) classic asset explorer: the experimental one has no "Save Model" in its
# right-click menu, which dead-ends the mesh export flow
if ($txt -match '"FeaturePreviewNewAssetExplorer": true') {
    $txt = $txt -replace '"FeaturePreviewNewAssetExplorer": true', '"FeaturePreviewNewAssetExplorer": false'
    $changes += 'classic asset explorer restored'
}

# 2c) morph targets crash FModel's glTF writer on Rivals skeletal meshes -
# viewing/painting does not need them
if ($txt -match '"SaveMorphTargets": true') {
    $txt = $txt -replace '"SaveMorphTargets": true', '"SaveMorphTargets": false'
    $changes += 'morph targets off'
}

# 3) model exports -> the folder Skin Studio watches
$txt = $txt -replace '"ModelDirectory": "[^"]*"', '"ModelDirectory": "C:\\rs\\SkinStudio\\blender\\fmodel_out\\Exports"'
$changes += 'model dir = fmodel_out\Exports'

# 4) local mapping file: the Rivals entry has two identical null endpoints;
#    the SECOND is the mappings endpoint - point it at our usmap
$nullEp = @'
        {
          "Url": null,
          "Path": null,
          "Overwrite": false,
          "FilePath": null,
          "IsValid": false
        }
'@.Replace("`r`n", "`n").Trim()
$mapEp = @'
        {
          "Url": null,
          "Path": null,
          "Overwrite": true,
          "FilePath": "C:\\rs\\SkinStudio\\blender\\Marvel.usmap",
          "IsValid": false
        }
'@.Replace("`r`n", "`n").Trim()
$norm = $txt.Replace("`r`n", "`n")
$first = $norm.IndexOf($nullEp)
if ($first -ge 0) {
    $second = $norm.IndexOf($nullEp, $first + $nullEp.Length)
    if ($second -ge 0) {
        $norm = $norm.Substring(0, $second) + $mapEp + $norm.Substring($second + $nullEp.Length)
        $changes += 'local mappings file set'
    } else {
        # only one null endpoint left (aes already filled by FModel?) - it is the mappings one
        $norm = $norm.Substring(0, $first) + $mapEp + $norm.Substring($first + $nullEp.Length)
        $changes += 'local mappings file set (single null endpoint)'
    }
} elseif ($norm.Contains('Marvel.usmap')) { $changes += 'mappings already set' }
else { $changes += 'WARN: mappings endpoint pattern not found - set Local Mapping File by hand in FModel settings' }
$txt = $norm.Replace("`n", "`r`n")

[IO.File]::WriteAllText($cfg, $txt)
Write-Output ("fixed: " + ($changes -join '; '))

$ErrorActionPreference = 'Stop'
$sourceRoot = Join-Path $PSScriptRoot 'KnoxNavigator'
$userModsRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid\mods'
$destinationRoot = Join-Path $userModsRoot 'KnoxNavigator'
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot '42\mod.info'))) {
    throw 'KnoxNavigator/42/mod.info is missing.'
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot '42\media\textures\KnoxNavigator\iso_high'))) {
    throw 'Map textures are missing. Download KnoxNavigatorSetup.exe from https://github.com/BlessedsCode/KnoxNavigator/releases/latest instead of the GitHub source ZIP.'
}
New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
Get-ChildItem -LiteralPath $sourceRoot -Force | Copy-Item -Destination $destinationRoot -Recurse -Force
Write-Output "Installed Knox Navigator: $destinationRoot"
Write-Output 'Enable Knox Navigator for your single-player save, then reload that save.'

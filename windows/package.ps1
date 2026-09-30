$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $PSScriptRoot 'build'
$stageRoot = Join-Path $buildRoot 'stage'
$luaRoot = Join-Path $stageRoot 'lua'
$dllPath = Join-Path $PSScriptRoot 'Build/Release/x64/luaoutbreaktracker.dll'
$zipPath = Join-Path $buildRoot 'OutbreakTracker-Windows-x64.zip'

if (-not (Test-Path $dllPath -PathType Leaf)) {
    throw "Windows tracker DLL not found: $dllPath"
}

if (Test-Path $stageRoot) {
    Remove-Item $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $luaRoot | Out-Null

Copy-Item (Join-Path $repoRoot 'sources/*.lua') $luaRoot
Copy-Item (Join-Path $repoRoot 'assets') $luaRoot -Recurse
Copy-Item (Join-Path $PSScriptRoot 'overrides/language.lua') (Join-Path $luaRoot 'language.lua') -Force
Copy-Item $dllPath (Join-Path $luaRoot 'luaoutbreaktracker.dll') -Force

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}
Compress-Archive -Path $luaRoot -DestinationPath $zipPath
Write-Output "Built Windows LÖVE package: $zipPath"

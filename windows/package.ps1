param(
    [string]$LoveRuntimeDirectory = $env:LOVE_WINDOWS_DIR
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $PSScriptRoot 'build'
$stageRoot = Join-Path $buildRoot 'stage'
$gameRoot = Join-Path $stageRoot 'game'
$distributionRoot = Join-Path $stageRoot 'distribution'
$dllPath = Join-Path $PSScriptRoot 'Build/Release/x64/luaoutbreaktracker.dll'
$gameZipPath = Join-Path $stageRoot 'game.zip'
$loveArchivePath = Join-Path $buildRoot 'OutbreakTracker-Windows-x64.love'

if ([string]::IsNullOrWhiteSpace($LoveRuntimeDirectory)) {
    throw 'Pass -LoveRuntimeDirectory or set LOVE_WINDOWS_DIR to an extracted LÖVE 11.5 x64 distribution.'
}

$loveExePath = Join-Path $LoveRuntimeDirectory 'love.exe'
$exePath = Join-Path $distributionRoot 'OutbreakTracker.exe'
$zipPath = Join-Path $buildRoot 'OutbreakTracker-Windows-x64.zip'

if (-not (Test-Path $dllPath -PathType Leaf)) {
    throw "Windows tracker DLL not found: $dllPath"
}

if (-not (Test-Path $loveExePath -PathType Leaf)) {
    throw "LÖVE executable not found: $loveExePath"
}

$requiredLoveFiles = @(
    'love.dll',
    'lua51.dll',
    'SDL2.dll',
    'OpenAL32.dll',
    'mpg123.dll',
    'license.txt'
)
foreach ($file in $requiredLoveFiles) {
    $path = Join-Path $LoveRuntimeDirectory $file
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Required LÖVE runtime file not found: $path"
    }
}

if (Test-Path $stageRoot) {
    Remove-Item $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
New-Item -ItemType Directory -Force -Path $gameRoot, $distributionRoot | Out-Null

Copy-Item (Join-Path $repoRoot 'sources/*.lua') $gameRoot
Copy-Item (Join-Path $repoRoot 'assets') $gameRoot -Recurse
Copy-Item (Join-Path $PSScriptRoot 'overrides/language.lua') (Join-Path $gameRoot 'language.lua') -Force

if (-not (Test-Path (Join-Path $gameRoot 'main.lua') -PathType Leaf)) {
    throw 'The packaged LÖVE game is missing its root main.lua.'
}

Move-Item (Join-Path $gameRoot 'main.lua') (Join-Path $gameRoot 'tracker-main.lua')
Copy-Item (Join-Path $PSScriptRoot 'overrides/main.lua') (Join-Path $gameRoot 'main.lua') -Force

foreach ($path in @($gameZipPath, $loveArchivePath, $zipPath)) {
    if (Test-Path $path) {
        Remove-Item $path -Force
    }
}

# LÖVE expects main.lua at the root of the .love archive, so archive the
# contents of the game directory rather than the directory itself.
Compress-Archive -Path (Join-Path $gameRoot '*') -DestinationPath $gameZipPath -CompressionLevel Optimal
Move-Item -LiteralPath $gameZipPath -Destination $loveArchivePath

Add-Type -AssemblyName System.IO.Compression.FileSystem
$gameArchive = [System.IO.Compression.ZipFile]::OpenRead($loveArchivePath)
try {
    if (-not ($gameArchive.Entries.FullName -contains 'main.lua')) {
        throw 'The generated .love archive does not contain main.lua at its root.'
    }
}
finally {
    $gameArchive.Dispose()
}

# A fused LÖVE executable is the official LÖVE launcher followed by the .love
# archive. Keep the native reader beside the executable so require can load it.
$exeStream = [System.IO.File]::Create($exePath)
try {
    foreach ($sourcePath in @($loveExePath, $loveArchivePath)) {
        $sourceStream = [System.IO.File]::OpenRead($sourcePath)
        try {
            $sourceStream.CopyTo($exeStream)
        }
        finally {
            $sourceStream.Dispose()
        }
    }
}
finally {
    $exeStream.Dispose()
}

Copy-Item $dllPath (Join-Path $distributionRoot 'luaoutbreaktracker.dll') -Force
Get-ChildItem -LiteralPath $LoveRuntimeDirectory -Filter '*.dll' -File |
    Copy-Item -Destination $distributionRoot -Force
Copy-Item (Join-Path $LoveRuntimeDirectory 'license.txt') $distributionRoot -Force

if (-not (Test-Path $exePath -PathType Leaf) -or (Get-Item $exePath).Length -le (Get-Item $loveExePath).Length) {
    throw 'The fused Windows executable was not created correctly.'
}

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}
Compress-Archive -Path (Join-Path $distributionRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
Write-Output "Built Windows executable package: $zipPath"

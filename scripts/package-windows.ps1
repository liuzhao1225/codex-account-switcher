param(
    [string]$OutputDirectory,
    [string]$Dotnet = 'dotnet',
    [string]$Swift = 'swift',
    [string]$SwiftRuntimeDirectory
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$windowsRoot = Join-Path $projectRoot 'windows'
$macLockPath = Join-Path $projectRoot 'Package.resolved'
$macLockBytes = if (Test-Path -LiteralPath $macLockPath) { [IO.File]::ReadAllBytes($macLockPath) } else { $null }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $windowsRoot 'artifacts' }
$artifactRoot = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

# A fresh staging directory prevents stale files from leaking into the deliverable.
$staging = Join-Path $artifactRoot ('publish-' + [Guid]::NewGuid().ToString('N'))
$runtimeStaging = Join-Path $artifactRoot ('runtime-' + [Guid]::NewGuid().ToString('N'))
try {
    & $Swift build --package-path $projectRoot -c release --product SwitcherHost
    if ($LASTEXITCODE -ne 0) { throw 'Shared Swift core build failed.' }
    $swiftBin = & $Swift build --package-path $projectRoot -c release --show-bin-path
    if ($LASTEXITCODE -ne 0) { throw 'Could not locate shared Swift host.' }
    if (-not $SwiftRuntimeDirectory) {
        $targetInfo = (& $Swift -print-target-info | ConvertFrom-Json)
        $SwiftRuntimeDirectory = $targetInfo.paths.runtimeLibraryPaths |
            Where-Object { Test-Path -LiteralPath (Join-Path $_ 'swiftCore.dll') } | Select-Object -First 1
    }
    if (-not $SwiftRuntimeDirectory -or -not (Test-Path -LiteralPath (Join-Path $SwiftRuntimeDirectory 'Foundation.dll'))) {
        throw 'Pass -SwiftRuntimeDirectory pointing to the installed Swift x64 runtime DLL directory.'
    }
    New-Item -ItemType Directory -Path $runtimeStaging -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $swiftBin 'SwitcherHost.exe') -Destination $runtimeStaging
    Get-ChildItem -LiteralPath $SwiftRuntimeDirectory -Filter '*.dll' -File |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $runtimeStaging }
    Get-ChildItem -LiteralPath (Join-Path $windowsRoot 'licenses') -Filter '*.txt' -File |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $runtimeStaging }
    $runtimeZip = Join-Path $artifactRoot 'SwiftRuntime.zip'
    if (Test-Path -LiteralPath $runtimeZip) { Remove-Item -LiteralPath $runtimeZip }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($runtimeStaging, $runtimeZip)
    & $Dotnet publish (Join-Path $windowsRoot 'CodexAccountSwitcher/CodexAccountSwitcher.csproj') `
        -c Release -r win-x64 --self-contained true -o $staging `
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:EnableCompressionInSingleFile=true -p:DebugType=None -p:DebugSymbols=false `
        "-p:SwiftRuntimeArchive=$runtimeZip" --nologo
    if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
    $filename = 'Codex-Account-Switcher-windows-x64.exe'
    $builtExe = Join-Path $staging $filename
    if (-not (Test-Path -LiteralPath $builtExe -PathType Leaf)) { throw 'Published EXE is missing.' }
    $expectedVersion = ([xml](Get-Content -Raw (Join-Path $windowsRoot 'Directory.Build.props'))).Project.PropertyGroup.Version
    $packageVersion = ([Version](Get-Item -LiteralPath $builtExe).VersionInfo.FileVersion).ToString(3)
    if ($packageVersion -ne $expectedVersion) { throw "EXE version $packageVersion does not match $expectedVersion." }
    $unexpectedFiles = @(Get-ChildItem -LiteralPath $staging -File | Where-Object { $_.Name -ne $filename })
    if ($unexpectedFiles.Count -ne 0) { throw 'Single-file publish left unexpected runtime files.' }
    $artifact = Join-Path $artifactRoot $filename
    Copy-Item -LiteralPath $builtExe -Destination $artifact -Force
    $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($artifact + '.sha256', "$hash  $filename`n", [Text.UTF8Encoding]::new($false))
    Write-Output $artifact
} finally {
    # SwiftPM removes a lockfile when this platform has no external package dependencies.
    # Keep the existing macOS Sparkle pin intact in a shared working tree.
    if ($null -ne $macLockBytes) { [IO.File]::WriteAllBytes($macLockPath, $macLockBytes) }
    $expectedRoot = $artifactRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    foreach ($directory in @($staging, $runtimeStaging)) {
        $resolvedStaging = [IO.Path]::GetFullPath($directory)
        if (-not $resolvedStaging.StartsWith($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Staging cleanup escaped the artifact directory.'
        }
        if (Test-Path -LiteralPath $resolvedStaging) { Remove-Item -LiteralPath $resolvedStaging -Recurse -Force }
    }
}

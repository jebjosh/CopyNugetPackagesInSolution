$ErrorActionPreference = 'Stop'

$destination = Join-Path $PSScriptRoot 'offline-packages'
$assetsFiles = @(Get-ChildItem $PSScriptRoot -Recurse -File -Filter 'project.assets.json')

if ($assetsFiles.Count -eq 0) {
    throw "No restored packages found. Run 'dotnet restore' while online first."
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null

foreach ($file in $assetsFiles) {
    $assets = Get-Content $file.FullName -Raw | ConvertFrom-Json
    $cache = $assets.packageFolders.PSObject.Properties.Name | Select-Object -First 1

    foreach ($package in $assets.libraries.PSObject.Properties) {
        if ($package.Value.type -ne 'package') { continue }

        $packageDir = Join-Path $cache $package.Value.path
        $archive = Get-ChildItem -LiteralPath $packageDir -Filter '*.nupkg' -File | Select-Object -First 1
        if (-not $archive) { throw "Package archive missing: $($package.Name)" }

        Copy-Item -LiteralPath $archive.FullName -Destination $destination -Force
    }
}

$count = @(Get-ChildItem $destination -File -Filter '*.nupkg').Count
Write-Host "Done! $count packages in offline-packages."

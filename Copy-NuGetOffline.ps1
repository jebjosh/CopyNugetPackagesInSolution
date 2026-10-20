# Put this script next to your .sln file and run it on the computer that has the packages.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$destination = Join-Path $root 'offline-packages'
$archives = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$missing = New-Object 'System.Collections.Generic.List[string]'
$references = 0

function Add-PackageArchive($description, $directories) {
    foreach ($directory in $directories) {
        if (-not $directory -or -not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        $archive = Get-ChildItem -LiteralPath $directory -File -Filter '*.nupkg' |
            Select-Object -First 1
        if ($archive) {
            [void]$script:archives.Add($archive.FullName)
            return
        }
    }
    $script:missing.Add($description)
}

# Modern projects: project.assets.json lists direct AND transitive NuGet packages.
Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'project.assets.json' |
    Where-Object { $_.FullName -notmatch '[\\/]offline-packages[\\/]' } |
    ForEach-Object {
        $assets = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
        $cacheFolders = @($assets.packageFolders.PSObject.Properties.Name)
        foreach ($entry in $assets.libraries.PSObject.Properties) {
            if ($entry.Value.type -ne 'package') { continue }
            $references++
            $dirs = foreach ($cache in $cacheFolders) {
                Join-Path $cache $entry.Value.path
            }
            Add-PackageArchive $entry.Name $dirs
        }
    }

# Older .NET Framework projects: packages.config lists the installed packages.
Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'packages.config' |
    Where-Object { $_.FullName -notmatch '[\\/](bin|obj|offline-packages)[\\/]' } |
    ForEach-Object {
        $config = $_
        [xml]$xml = Get-Content -LiteralPath $config.FullName -Raw
        foreach ($package in @($xml.packages.package)) {
            if (-not $package) { continue }
            $id = [string]$package.id
            $version = [string]$package.version
            if (-not $id -or -not $version) { continue }
            $references++
            $dirs = @(
                (Join-Path $root "packages\$id.$version"),
                (Join-Path $config.DirectoryName "packages\$id.$version")
            )
            if ($env:NUGET_PACKAGES) {
                $dirs += Join-Path $env:NUGET_PACKAGES "$id\$version"
            }
            if ($env:USERPROFILE) {
                $dirs += Join-Path $env:USERPROFILE ".nuget\packages\$id\$version"
            }
            Add-PackageArchive "$id/$version" $dirs
        }
    }

if ($references -eq 0) {
    throw "No NuGet package references found. The project may not use NuGet, or it hasn't been restored. Build/restore it on this computer first."
}
if ($missing.Count -gt 0) {
    $names = ($missing | Select-Object -Unique) -join ', '
    throw "Found $references package references, but couldn't find these .nupkg files: $names. Restore the solution while ONLINE and run this script again."
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null
# Keep only the archives needed for the current solution.
Get-ChildItem -LiteralPath $destination -File -Filter '*.nupkg' | Remove-Item -Force
foreach ($archive in $archives) {
    Copy-Item -LiteralPath $archive -Destination $destination -Force
}
Write-Host "Done! Copied $($archives.Count) NuGet packages into offline-packages." -ForegroundColor Green

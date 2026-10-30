<#
.SYNOPSIS
    Builds the installation package that is attached to a GitHub release.

.DESCRIPTION
    Run from anywhere in the repo, on Windows or Linux (PowerShell 7):

        .github/scripts/build-release-assets.ps1 -Version 1.0.1 [-OutDir <dir>] [-SkipSPFxBuild]

    The version must match VERSION and the first three parts of each SPFx solution's
    package-solution.json - a tag that disagrees with them would publish a package
    stamped with another version than the release.

    Produces, in -OutDir (default: release-assets/ in the repo root):

        bestillingsportalen-<version>.zip   What an installation needs, and nothing else:
                                            the scripts, templates, ARM templates, runbooks,
                                            assets, the Power Automate solution and the
                                            documentation, with the built .sppkg and the
                                            Teams app zip in place under
                                            Source/SharePointFramework/<solution>/sharepoint/solution/,
                                            where deploy.ps1 looks for them. Unpack it and
                                            run deploy.ps1 - no Node.js needed.
        SHA256SUMS.txt                      Checksum of the package, in sha256sum format.

    and release-notes.md (the version's CHANGELOG.md section) next to -OutDir.

    Left out of the package: the SPFx source (the built .sppkg replaces it; building
    needs a clone of the repo), the documentation images, and the GitHub and editor
    settings.

.PARAMETER Version
    The version to build, MAJOR.MINOR.PATCH - the tag without its 'v'.

.PARAMETER OutDir
    Where the files go. Emptied first. Default: release-assets/ in the repo root.

.PARAMETER SkipSPFxBuild
    Package the .sppkg files that are already built instead of running npm ci and
    npm run build.
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string]$OutDir,
    [switch]$SkipSPFxBuild
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Fail([string]$Message) {
    # '::error::' makes the message stand out in a GitHub Actions log, and is harmless elsewhere
    Write-Host "::error::$Message"
    exit 1
}

function WriteUtf8([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') { Fail "Version '$Version' is not MAJOR.MINOR.PATCH" }

# git prints paths as UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = (git rev-parse --show-toplevel 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $root) { Fail "Not inside a git repository" }
$root = (Resolve-Path $root).Path
if (-not $OutDir) { $OutDir = Join-Path $root 'release-assets' }
$out = [System.IO.Path]::GetFullPath($OutDir)
$notes = Join-Path (Split-Path $out -Parent) 'release-notes.md'

$fileVersion = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
if ($fileVersion -ne $Version) { Fail "VERSION is '$fileVersion', not '$Version'" }

# Each subfolder with config/package-solution.json is a solution, as in deploy.ps1
$spfxRoot = Join-Path $root 'Source/SharePointFramework'
$solutions = @(Get-ChildItem -Path $spfxRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
        Test-Path (Join-Path $_.FullName 'config/package-solution.json')
    })
if ($solutions.Count -eq 0) { Fail "No SPFx solutions under Source/SharePointFramework" }

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null
$staging = Join-Path ([System.IO.Path]::GetTempPath()) "bp-release-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $staging | Out-Null

try {
    $packageName = "bestillingsportalen-$Version"
    $package = Join-Path $staging $packageName
    New-Item -ItemType Directory -Path $package | Out-Null

    # --- The committed files an installation needs ---
    # git ls-files sees the checkout as it is - in the workflow that is the tag.
    # The SPFx source is left out: only the solution's package-solution.json (deploy.ps1
    # and Test-Installation.ps1 read the version from it) and its teams/ folder (the
    # Teams app manifest and icons) go in, next to the built files below.
    $spfxPrefix = 'Source/SharePointFramework/'
    $excluded = @('^Images/', '^\.github/', '^\.vscode/', '^\.gitignore$', '^\.claude/')
    $files = @(git -C $root -c core.quotepath=false ls-files | Where-Object { $_ })
    if ($LASTEXITCODE -ne 0) { Fail "git ls-files failed" }
    $copied = 0
    foreach ($file in $files) {
        if (@($excluded | Where-Object { $file -match $_ }).Count -gt 0) { continue }
        if ($file.StartsWith($spfxPrefix) -and $file -notmatch '^Source/SharePointFramework/[^/]+/(config/package-solution\.json$|teams/)') { continue }
        $source = Join-Path $root $file
        if (-not (Test-Path $source -PathType Leaf)) { Fail "$file is in git but not in the checkout" }
        $destination = Join-Path $package $file
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item $source -Destination $destination
        $copied++
    }
    Write-Host "Copied $copied committed files"

    # --- The built files, per solution ---
    foreach ($solution in $solutions) {
        $name = $solution.Name
        $config = Get-Content (Join-Path $solution.FullName 'config/package-solution.json') -Raw | ConvertFrom-Json
        $solutionVersion = ("$($config.solution.version)" -split '\.')[0..2] -join '.'
        if ($solutionVersion -ne $Version) { Fail "${name}: package-solution.json has version $solutionVersion, not $Version" }

        if (-not $SkipSPFxBuild) {
            Write-Host "Building $name"
            Push-Location $solution.FullName
            try {
                npm ci --no-audit --no-fund
                if ($LASTEXITCODE -ne 0) { Fail "${name}: npm ci failed" }
                npm run build
                if ($LASTEXITCODE -ne 0) { Fail "${name}: npm run build failed" }
            }
            finally {
                Pop-Location
            }
        }

        # zippedPackage is relative to sharepoint/, e.g. solution/bp-provision-web-parts.sppkg
        $zippedPackage = "$($config.paths.zippedPackage)" -replace '\\', '/'
        $sppkg = Join-Path $solution.FullName "sharepoint/$zippedPackage"
        if (-not (Test-Path $sppkg -PathType Leaf)) { Fail "${name}: $sppkg was not built" }

        # Where deploy.ps1 looks for the prebuilt package, and writes the Teams app zip
        $relative = [System.IO.Path]::GetRelativePath($root, $solution.FullName) -replace '\\', '/'
        $target = Join-Path $package "$relative/sharepoint/$(Split-Path $zippedPackage -Parent)"
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Copy-Item $sppkg -Destination $target
        Write-Host "Packaged $relative/sharepoint/$zippedPackage"

        # Teams app: icons + manifest stamped with the version, zipped flat - as
        # PublishTeamsApp in deploy.ps1 does it, under the same name
        $teamsFolder = Join-Path $solution.FullName 'teams'
        $manifestPath = Join-Path $teamsFolder 'manifest.json'
        if (Test-Path $manifestPath -PathType Leaf) {
            $teamsStaging = Join-Path $staging "teams-$name"
            New-Item -ItemType Directory -Path $teamsStaging | Out-Null
            Get-ChildItem $teamsFolder -File | Where-Object Name -ne 'manifest.json' | Copy-Item -Destination $teamsStaging
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            $manifest.version = $Version
            WriteUtf8 (Join-Path $teamsStaging 'manifest.json') ($manifest | ConvertTo-Json -Depth 10)
            $teamsZip = Join-Path $target 'bestillingsportalen-teams-app.zip'
            [System.IO.Compression.ZipFile]::CreateFromDirectory($teamsStaging, $teamsZip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
            Write-Host "Packaged the Teams app $Version"
        }
    }

    # --- The package ---
    # One folder inside the zip, so unpacking it never spills files into the current folder
    $zip = Join-Path $out "$packageName.zip"
    [System.IO.Compression.ZipFile]::CreateFromDirectory($package, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)

    # sha256sum format, so 'sha256sum -c SHA256SUMS.txt' verifies the download
    $sums = @(Get-ChildItem $out -File | Sort-Object Name | ForEach-Object {
            "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)"
        })
    WriteUtf8 (Join-Path $out 'SHA256SUMS.txt') (($sums -join "`n") + "`n")

    # --- Release notes: the version's section in CHANGELOG.md, without its heading ---
    $section = [System.Collections.Generic.List[string]]::new()
    $inSection = $false
    foreach ($line in (Get-Content (Join-Path $root 'CHANGELOG.md'))) {
        if ($line -match '^## ') {
            if ($inSection) { break }
            if ($line -eq "## $Version" -or $line.StartsWith("## $Version ")) { $inSection = $true }
            continue
        }
        if ($inSection) { $section.Add($line) }
    }
    $text = ($section -join "`n").Trim()
    if (-not $text) { Fail "CHANGELOG.md has no section for $Version" }
    WriteUtf8 $notes ($text + "`n")

    Write-Host ""
    Write-Host "Release files in ${out}:"
    Get-ChildItem $out -File | ForEach-Object { Write-Host ("  {0,12:N0}  {1}" -f $_.Length, $_.Name) }
    Write-Host "Release notes in $notes"
}
finally {
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
}

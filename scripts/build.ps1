<#
.SYNOPSIS
    Build an RPM package for Azure Linux 3.0 using Docker.

.DESCRIPTION
    This script orchestrates the RPM build pipeline by:
    1. Building a Docker image from docker/Dockerfile.builder that
       runs rpmbuild inside an Azure Linux 3.0 environment.
    2. Creating a temporary container from the built image.
    3. Extracting the resulting RPM and SRPM files to the local dist\
       directory.
    4. Cleaning up the temporary container.

    This is the Windows (PowerShell) equivalent of scripts/build.sh.

.PARAMETER Version
    Semantic version string. Defaults to the contents of the VERSION file.

.PARAMETER Release
    RPM release counter. Defaults to 1.

.OUTPUTS
    dist\hello-azurelinux-<version>-<release>.azl3.noarch.rpm
    dist\hello-azurelinux-<version>-<release>.azl3.src.rpm

.EXAMPLE
    .\scripts\build.ps1
    Builds using the version from the VERSION file with release 1.

.EXAMPLE
    .\scripts\build.ps1 -Version "2.1.0" -Release "3"
    Builds version 2.1.0, release 3.

.NOTES
    Prerequisites: Docker must be installed and running.
#>
param(
    [string]$Version,
    [string]$Release = "1"
)

$ErrorActionPreference = "Stop"

# Resolve the repository root relative to this script's location.
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

# Read version from the VERSION file if not provided via parameter.
if (-not $Version) {
    $Version = (Get-Content "$RepoRoot\VERSION" -Raw).Trim()
}

# Package name — must match the Name: field in the RPM spec.
$Name = "hello-azurelinux"

# Docker image tag — unique per version-release to enable caching.
$ImageTag = "${Name}-builder:${Version}-${Release}"

Write-Host "==> Building RPM: version=${Version}, release=${Release}..."

# Step 1: Build the Docker image.
# The Dockerfile.builder runs rpmbuild at image-build time, so the
# resulting image already contains the finished RPMs in /output/.
docker build `
    -f "$RepoRoot\docker\Dockerfile.builder" `
    --build-arg "NAME=$Name" `
    --build-arg "VERSION=$Version" `
    --build-arg "RELEASE=$Release" `
    -t $ImageTag `
    $RepoRoot

if ($LASTEXITCODE -ne 0) { throw "Docker build failed." }

# Step 2: Extract RPMs from the image.
# We create a stopped container (no CMD needed), copy /output/ contents
# to the host, then remove the container.
New-Item -ItemType Directory -Force -Path "$RepoRoot\dist" | Out-Null
$ContainerId = (docker create $ImageTag).Trim()
docker cp "${ContainerId}:/output/." "$RepoRoot\dist\"
docker rm $ContainerId | Out-Null

Write-Host "==> Build complete. Packages written to dist\"
Get-ChildItem "$RepoRoot\dist\*.rpm" | ForEach-Object { Write-Host $_.Name }

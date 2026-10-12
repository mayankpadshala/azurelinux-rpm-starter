#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# build.sh — Build an RPM package for Azure Linux 3.0 using Docker
# ─────────────────────────────────────────────────────────────────────
#
# Description:
#   This script orchestrates the RPM build pipeline by:
#   1. Building a Docker image from docker/Dockerfile.builder that
#      runs rpmbuild inside an Azure Linux 3.0 environment.
#   2. Creating a temporary container from the built image.
#   3. Extracting the resulting RPM and SRPM files to the local dist/
#      directory.
#   4. Cleaning up the temporary container.
#
# Usage:
#   ./scripts/build.sh [<version>] [<release>]
#
# Arguments:
#   version   Semantic version string (default: read from VERSION file)
#   release   RPM release counter    (default: 1)
#
# Examples:
#   ./scripts/build.sh              # Build with version from VERSION file
#   ./scripts/build.sh 2.1.0 3     # Build version 2.1.0, release 3
#
# Output:
#   dist/hello-azurelinux-<version>-<release>.azl3.noarch.rpm
#   dist/hello-azurelinux-<version>-<release>.azl3.src.rpm
#
# Prerequisites:
#   - Docker must be installed and running
# ─────────────────────────────────────────────────────────────────────

set -euo pipefail

# Resolve the repository root relative to this script's location.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Ensure docker is accessible in PATH (handles common macOS/Linux locations)
if ! command -v docker &>/dev/null; then
    for docker_dir in "$HOME/.docker/bin" /usr/local/bin /opt/homebrew/bin /Applications/Docker.app/Contents/Resources/bin; do
        if [[ -x "$docker_dir/docker" ]]; then
            export PATH="$docker_dir:$PATH"
            break
        fi
    done
fi

if ! command -v docker &>/dev/null; then
    echo "ERROR: 'docker' command not found. Please ensure Docker is installed and running." >&2
    exit 1
fi

# Read version from the first CLI argument, falling back to the VERSION file.
VERSION="${1:-$(cat "${REPO_ROOT}/VERSION")}"

# Read release from the second CLI argument, defaulting to 1.
RELEASE="${2:-1}"

# Package name — must match the Name: field in the RPM spec.
NAME="hello-azurelinux"

# Docker image tag — unique per version-release to enable caching.
IMAGE_TAG="${NAME}-builder:${VERSION}-${RELEASE}"

echo "==> Building RPM: version=${VERSION}, release=${RELEASE}..."

# Step 1: Build the Docker image.
# The Dockerfile.builder runs rpmbuild at image-build time, so the
# resulting image already contains the finished RPMs in /output/.
docker build \
    -f "${REPO_ROOT}/docker/Dockerfile.builder" \
    --build-arg NAME="${NAME}" \
    --build-arg VERSION="${VERSION}" \
    --build-arg RELEASE="${RELEASE}" \
    -t "${IMAGE_TAG}" \
    "${REPO_ROOT}"

# Step 2: Extract RPMs from the image.
# We create a stopped container (no CMD needed), copy /output/ contents
# to the host, then remove the container.
mkdir -p "${REPO_ROOT}/dist"
CONTAINER_ID=$(docker create "${IMAGE_TAG}")
docker cp "${CONTAINER_ID}:/output/." "${REPO_ROOT}/dist/"
docker rm "${CONTAINER_ID}" > /dev/null

echo "==> Build complete. Packages written to dist/"
ls -1 "${REPO_ROOT}/dist/"*.rpm 2>/dev/null || true

#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# test-lifecycle.sh — Automated RPM lifecycle tests for hello-azurelinux
# ─────────────────────────────────────────────────────────────────────
#
# Description:
#   Validates the full operational lifecycle of the hello-azurelinux
#   RPM package inside a clean Azure Linux 3.0 container:
#
#   Phase 1 — Build:
#     Compiles two RPMs: a baseline version (1.0.0-1) and an upgrade
#     version (1.0.1-1) using the build.sh script.
#
#   Phase 2 — Prepare:
#     Builds the tester Docker image (docker/Dockerfile.tester), a
#     minimal Azure Linux 3.0 environment without dev tools.
#
#   Phase 3 — Test (5 steps in an ephemeral container):
#     1. Install the baseline RPM via tdnf install
#     2. Run the binary and assert version + message output
#     3. Upgrade to the new RPM via tdnf upgrade
#     4. Run the binary and assert the upgraded version appears
#     5. Remove the package via tdnf remove and assert cleanup
#
# Expected output:
#   === Phase 1: Build baseline and upgrade RPMs ===
#   ==> Building RPM: version=1.0.0, release=1...
#   ==> Building RPM: version=1.0.1, release=1...
#   === Phase 2: Build tester image ===
#   === Phase 3: Execute Lifecycle Test inside Azure Linux ===
#   [TEST 1/5] Installing base RPM...
#   [TEST 2/5] Validating installation output...
#   [hello-azurelinux] Version: 1.0.0-1
#   [hello-azurelinux] Message: Welcome to Azure Linux!
#   [TEST 3/5] Updating to upgraded RPM...
#   [TEST 4/5] Validating upgrade output...
#   [hello-azurelinux] Version: 1.0.1-1
#   [hello-azurelinux] Message: Welcome to Azure Linux!
#   [TEST 5/5] Removing package...
#   SUCCESS: All installation, upgrade, and removal validations passed!
#
# Exit codes:
#   0 — All tests passed
#   1 — A test assertion failed (version mismatch, binary not removed, etc.)
#
# Prerequisites:
#   - Docker must be installed and running
#   - scripts/build.sh must be executable
# ─────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────

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

# Package name — must match the Name: field in the RPM spec.
NAME="hello-azurelinux"

# Baseline version: the initially installed package.
BASE_VERSION="1.0.0"

# Upgrade version: a newer release used to test in-place upgrades.
UPGRADE_VERSION="1.0.1"

# RPM release counter (shared by both baseline and upgrade builds).
RELEASE="1"

# Docker image tag for the tester container.
TESTER_IMAGE="${NAME}-tester:latest"

# Helper: print failure message to stderr and exit.
fail() { echo "FAIL: $1" >&2; exit 1; }

# ── Phase 1: Build baseline and upgrade RPMs ─────────────────────────
# Uses scripts/build.sh to produce two RPM versions. Output is
# suppressed to keep the test log clean; build errors will still
# cause a non-zero exit thanks to set -e.
echo "=== Phase 1: Build baseline and upgrade RPMs ==="

echo "==> Building RPM: version=${BASE_VERSION}, release=${RELEASE}..."
"${REPO_ROOT}/scripts/build.sh" "${BASE_VERSION}" "${RELEASE}" > /dev/null 2>&1

echo "==> Building RPM: version=${UPGRADE_VERSION}, release=${RELEASE}..."
"${REPO_ROOT}/scripts/build.sh" "${UPGRADE_VERSION}" "${RELEASE}" > /dev/null 2>&1

# ── Phase 2: Build tester image ──────────────────────────────────────
# Builds a clean Azure Linux 3.0 image (no dev tools) to simulate
# a production-like target environment.
echo "=== Phase 2: Build tester image ==="

docker build \
    -f "${REPO_ROOT}/docker/Dockerfile.tester" \
    -t "${TESTER_IMAGE}" \
    "${REPO_ROOT}" > /dev/null 2>&1

# ── Phase 3: Execute Lifecycle Test inside Azure Linux ───────────────
# Launches an ephemeral container (--rm) with the dist/ directory
# bind-mounted read-only at /rpms. The container runs a bash script
# that performs all 5 test steps sequentially.
echo "=== Phase 3: Execute Lifecycle Test inside Azure Linux ==="

# Compute expected RPM filenames (includes the .azl3 dist suffix).
BASE_RPM="${NAME}-${BASE_VERSION}-${RELEASE}.azl3.noarch.rpm"
UPGRADE_RPM="${NAME}-${UPGRADE_VERSION}-${RELEASE}.azl3.noarch.rpm"

docker run --rm \
    -v "${REPO_ROOT}/dist:/rpms:ro" \
    "${TESTER_IMAGE}" \
    /bin/bash -c "
set -e

# Test 1: Install the baseline RPM using tdnf.
echo '[TEST 1/5] Installing base RPM...'
tdnf install -y /rpms/${BASE_RPM} > /dev/null 2>&1

# Test 2: Run the installed binary and verify its output.
echo '[TEST 2/5] Validating installation output...'
OUTPUT=\$(hello-azurelinux)
echo \"\${OUTPUT}\"

# Assert: version string must match the baseline version.
echo \"\${OUTPUT}\" | grep -q 'Version: ${BASE_VERSION}-${RELEASE}' \
    || { echo 'FAIL: Version mismatch after install'; exit 1; }
# Assert: default message must be present.
echo \"\${OUTPUT}\" | grep -q 'Message: Welcome to Azure Linux!' \
    || { echo 'FAIL: Message mismatch after install'; exit 1; }

# Test 3: Upgrade to the newer RPM version using tdnf install (which upgrades existing packages when given a local RPM file).
echo '[TEST 3/5] Updating to upgraded RPM...'
tdnf install -y /rpms/${UPGRADE_RPM} > /dev/null 2>&1

# Test 4: Run the binary again and verify the upgraded version.
echo '[TEST 4/5] Validating upgrade output...'
OUTPUT=\$(hello-azurelinux)
echo \"\${OUTPUT}\"

# Assert: version string must now match the upgrade version.
echo \"\${OUTPUT}\" | grep -q 'Version: ${UPGRADE_VERSION}-${RELEASE}' \
    || { echo 'FAIL: Version mismatch after upgrade'; exit 1; }
# Assert: default message must still be present after upgrade.
echo \"\${OUTPUT}\" | grep -q 'Message: Welcome to Azure Linux!' \
    || { echo 'FAIL: Message mismatch after upgrade'; exit 1; }

# Test 5: Uninstall the package and verify clean removal.
echo '[TEST 5/5] Removing package...'
tdnf remove -y ${NAME} > /dev/null 2>&1

# Assert: the binary must no longer be on the PATH.
if command -v hello-azurelinux &>/dev/null; then
    echo 'FAIL: Binary still present after removal'
    exit 1
fi

echo 'SUCCESS: All installation, upgrade, and removal validations passed!'
"

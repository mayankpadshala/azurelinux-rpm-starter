<#
.SYNOPSIS
    Run automated lifecycle tests for hello-azurelinux.

.DESCRIPTION
    Validates the full operational lifecycle of the hello-azurelinux
    RPM package inside a clean Azure Linux 3.0 container.

    This is the Windows (PowerShell) equivalent of scripts/test-lifecycle.sh.

    Phase 1 — Build:
      Compiles two RPMs: a baseline version (1.0.0-1) and an upgrade
      version (1.0.1-1) using build.ps1.

    Phase 2 — Prepare:
      Builds the tester Docker image (docker/Dockerfile.tester), a
      minimal Azure Linux 3.0 environment without dev tools.

    Phase 3 — Test (5 steps in an ephemeral container):
      1. Install the baseline RPM via tdnf install
      2. Run the binary and assert version + message output
      3. Upgrade to the new RPM via tdnf upgrade
      4. Run the binary and assert the upgraded version appears
      5. Remove the package via tdnf remove and assert cleanup

.NOTES
    Prerequisites: Docker must be installed and running.

    The inner test logic runs as a bash script inside the Linux container.
    A single-quoted PowerShell here-string (@'...'@) is used to define
    the bash script without PowerShell variable expansion conflicts.
    Placeholders (__BASE_RPM__, etc.) are replaced via .Replace() before
    passing the script to docker run.

    Exit codes:
      0 — All tests passed
      Non-zero — A test assertion failed
#>

$ErrorActionPreference = "Stop"

# ── Configuration ────────────────────────────────────────────────────

# Resolve the repository root relative to this script's location.
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

# Package name — must match the Name: field in the RPM spec.
$Name = "hello-azurelinux"

# Baseline version: the initially installed package.
$BaseVersion = "1.0.0"

# Upgrade version: a newer release used to test in-place upgrades.
$UpgradeVersion = "1.0.1"

# RPM release counter (shared by both baseline and upgrade builds).
$Release = "1"

# Docker image tag for the tester container.
$TesterImage = "${Name}-tester:latest"

# ── Phase 1: Build baseline and upgrade RPMs ─────────────────────────
# Uses scripts/build.ps1 to produce two RPM versions. Output is
# suppressed to keep the test log clean; build errors will still
# cause a terminating error thanks to $ErrorActionPreference = "Stop".
Write-Host "=== Phase 1: Build baseline and upgrade RPMs ==="

Write-Host "==> Building RPM: version=${BaseVersion}, release=${Release}..."
& "$RepoRoot\scripts\build.ps1" -Version $BaseVersion -Release $Release *> $null

Write-Host "==> Building RPM: version=${UpgradeVersion}, release=${Release}..."
& "$RepoRoot\scripts\build.ps1" -Version $UpgradeVersion -Release $Release *> $null

# ── Phase 2: Build tester image ──────────────────────────────────────
# Builds a clean Azure Linux 3.0 image (no dev tools) to simulate
# a production-like target environment.
Write-Host "=== Phase 2: Build tester image ==="

docker build `
    -f "$RepoRoot\docker\Dockerfile.tester" `
    -t $TesterImage `
    $RepoRoot *> $null

# ── Phase 3: Execute Lifecycle Test inside Azure Linux ───────────────
# Launches an ephemeral container (--rm) with the dist\ directory
# bind-mounted read-only at /rpms. The container runs a bash script
# that performs all 5 test steps sequentially.
Write-Host "=== Phase 3: Execute Lifecycle Test inside Azure Linux ==="

# Compute expected RPM filenames (includes the .azl3 dist suffix).
$BaseRpm = "${Name}-${BaseVersion}-${Release}.azl3.noarch.rpm"
$UpgradeRpm = "${Name}-${UpgradeVersion}-${Release}.azl3.noarch.rpm"

# The bash test script is defined as a single-quoted here-string to
# avoid PowerShell interpreting $(...) as subexpressions. Placeholders
# prefixed/suffixed with __ are replaced with actual values below.
$TestScript = @'
set -e

# Test 1: Install the baseline RPM using tdnf.
echo '[TEST 1/5] Installing base RPM...'
tdnf install -y /rpms/__BASE_RPM__ > /dev/null 2>&1

# Test 2: Run the installed binary and verify its output.
echo '[TEST 2/5] Validating installation output...'
OUTPUT=$(hello-azurelinux)
echo "${OUTPUT}"

# Assert: version string must match the baseline version.
echo "${OUTPUT}" | grep -q 'Version: __BASE_VERSION__-__RELEASE__' \
    || { echo 'FAIL: Version mismatch after install'; exit 1; }
# Assert: default message must be present.
echo "${OUTPUT}" | grep -q 'Message: Welcome to Azure Linux!' \
    || { echo 'FAIL: Message mismatch after install'; exit 1; }

# Test 3: Upgrade to the newer RPM version using tdnf install (which upgrades existing packages when given a local RPM file).
echo '[TEST 3/5] Updating to upgraded RPM...'
tdnf install -y /rpms/__UPGRADE_RPM__ > /dev/null 2>&1

# Test 4: Run the binary again and verify the upgraded version.
echo '[TEST 4/5] Validating upgrade output...'
OUTPUT=$(hello-azurelinux)
echo "${OUTPUT}"

# Assert: version string must now match the upgrade version.
echo "${OUTPUT}" | grep -q 'Version: __UPGRADE_VERSION__-__RELEASE__' \
    || { echo 'FAIL: Version mismatch after upgrade'; exit 1; }
# Assert: default message must still be present after upgrade.
echo "${OUTPUT}" | grep -q 'Message: Welcome to Azure Linux!' \
    || { echo 'FAIL: Message mismatch after upgrade'; exit 1; }

# Test 5: Uninstall the package and verify clean removal.
echo '[TEST 5/5] Removing package...'
tdnf remove -y __NAME__ > /dev/null 2>&1

# Assert: the binary must no longer be on the PATH.
if command -v hello-azurelinux &>/dev/null; then
    echo 'FAIL: Binary still present after removal'
    exit 1
fi

echo 'SUCCESS: All installation, upgrade, and removal validations passed!'
'@

# Replace placeholders in the bash script with actual values.
$TestScript = $TestScript.Replace("__BASE_RPM__", $BaseRpm)
$TestScript = $TestScript.Replace("__UPGRADE_RPM__", $UpgradeRpm)
$TestScript = $TestScript.Replace("__BASE_VERSION__", $BaseVersion)
$TestScript = $TestScript.Replace("__UPGRADE_VERSION__", $UpgradeVersion)
$TestScript = $TestScript.Replace("__RELEASE__", $Release)
$TestScript = $TestScript.Replace("__NAME__", $Name)

# Run the test script inside an ephemeral Azure Linux container.
docker run --rm `
    -v "${RepoRoot}\dist:/rpms:ro" `
    $TesterImage `
    /bin/bash -c $TestScript

if ($LASTEXITCODE -ne 0) {
    throw "Lifecycle tests failed."
}

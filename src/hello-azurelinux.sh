#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# hello-azurelinux — Sample application for Azure Linux 3.0
# ─────────────────────────────────────────────────────────────────────
#
# Description:
#   This is the main executable installed by the hello-azurelinux RPM
#   package. It prints the installed package version and a configurable
#   greeting message.
#
# Configuration:
#   /etc/hello-azurelinux/hello-azurelinux.conf
#     The script sources this file if it exists. Users can override the
#     MESSAGE variable to change the greeting without modifying the
#     script itself. The config file is marked %config(noreplace) in
#     the RPM spec, so user edits survive package upgrades.
#
# Output format:
#   [hello-azurelinux] Version: <version>-<release>
#   [hello-azurelinux] Message: <message>
#
# Dependencies:
#   - bash (required)
#   - rpm  (used to query installed package version; falls back to
#           "dev" when RPM metadata is unavailable, e.g. during local
#           development outside a packaged installation)
#
# Exit codes:
#   0 — Success
#   Non-zero — Unexpected failure (set -euo pipefail is active)
# ─────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────

# Path to the user-editable configuration file installed by the RPM.
CONFIG_FILE="/etc/hello-azurelinux/hello-azurelinux.conf"

# Default greeting — overridden if CONFIG_FILE exists and defines MESSAGE.
MESSAGE="Welcome to Azure Linux!"

# Source the configuration file to pick up user overrides (e.g. MESSAGE).
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
fi

# ── Version detection ────────────────────────────────────────────────

# Query the RPM database for the installed package version and release.
# The release tag on Azure Linux includes a ".azl3" dist suffix
# (e.g. "1.azl3"), which we strip to produce a clean "X.Y.Z-R" string.
# If the package is not installed via RPM (local dev), fall back to "dev".
if rpm -q hello-azurelinux &>/dev/null; then
    PKG_VERSION=$(rpm -q --qf '%{VERSION}-%{RELEASE}' hello-azurelinux | sed 's/\.azl3$//')
else
    PKG_VERSION="dev"
fi

# ── Output ───────────────────────────────────────────────────────────

echo "[hello-azurelinux] Version: ${PKG_VERSION}"
echo "[hello-azurelinux] Message: ${MESSAGE}"

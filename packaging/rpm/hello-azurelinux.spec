# ─────────────────────────────────────────────────────────────────────
# hello-azurelinux.spec — RPM package definition
# ─────────────────────────────────────────────────────────────────────
#
# This spec file defines how rpmbuild creates the hello-azurelinux RPM.
#
# Key design decisions:
#   • Version and Release are NOT hardcoded. They are injected at build
#     time via rpmbuild --define "pkg_version X.Y.Z" --define "pkg_release R".
#     This allows the build scripts to control versioning from the
#     VERSION file or CLI arguments without editing this spec.
#   • BuildArch is "noarch" because the payload is a shell script.
#   • The config file uses %config(noreplace) so that user edits to
#     /etc/hello-azurelinux/hello-azurelinux.conf are preserved during
#     package upgrades.
#   • %%{?dist} appends the distribution suffix (e.g. ".azl3" on Azure
#     Linux 3.0) to the Release tag automatically.
#
# Build command (typically invoked by scripts/build.sh via Docker):
#   rpmbuild -ba hello-azurelinux.spec \
#       --define "pkg_version 1.0.0" \
#       --define "pkg_release 1" \
#       --define "_topdir /root/rpmbuild"
# ─────────────────────────────────────────────────────────────────────

# ── Package metadata ─────────────────────────────────────────────────
# Name:    The package name used by tdnf/rpm commands.
# Version: Pulled from the pkg_version macro defined at build time.
# Release: Pulled from pkg_release + the dist suffix (e.g. "1.azl3").
Name:           hello-azurelinux
Version:        %{pkg_version}
Release:        %{pkg_release}%{?dist}
Summary:        Sample application for Azure Linux 3.0
License:        MIT
URL:            https://github.com/azurelinux-rpm-starter

# Source0: The tarball containing application sources.
# rpmbuild expects this file in the SOURCES/ directory and will unpack
# it during %prep using the %setup macro.
Source0:        %{name}-%{version}.tar.gz

# BuildArch: "noarch" means this package is architecture-independent
# (shell scripts only — no compiled binaries).
BuildArch:      noarch

# Requires: Runtime dependencies. The application needs bash to execute.
Requires:       bash

# ── Description ──────────────────────────────────────────────────────
%description
A sample "hello world" application demonstrating RPM packaging
for Azure Linux 3.0 (formerly CBL-Mariner).

# ── Prep ─────────────────────────────────────────────────────────────
# %setup -q unpacks Source0 and cd's into the resulting directory.
# The tarball must contain a top-level directory named <name>-<version>/.
%prep
%setup -q

# ── Install ──────────────────────────────────────────────────────────
# Copies files from the unpacked source tree into the build root,
# which mirrors the target filesystem layout.
#   %%{_bindir}       → /usr/bin        (executable scripts)
#   %%{_sysconfdir}   → /etc            (configuration files)
%install
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_sysconfdir}/%{name}

# Install the main executable with 0755 permissions.
install -m 0755 src/hello-azurelinux.sh %{buildroot}%{_bindir}/hello-azurelinux

# Install the default configuration with 0644 permissions.
install -m 0644 src/hello-azurelinux.conf %{buildroot}%{_sysconfdir}/%{name}/hello-azurelinux.conf

# ── Files ────────────────────────────────────────────────────────────
# Declares which files are owned by this package.
#   %dir       — the directory itself is owned by this package and will
#                be removed on uninstall (if empty).
#   %config(noreplace) — marks the file as a config file; if the user
#                has modified it, rpm will NOT overwrite it on upgrade
#                (it installs the new default as .rpmnew instead).
%files
%{_bindir}/hello-azurelinux
%dir %{_sysconfdir}/%{name}
%config(noreplace) %{_sysconfdir}/%{name}/hello-azurelinux.conf

# ── Changelog ────────────────────────────────────────────────────────
%changelog
* Mon Oct 12 2026 Azure Linux RPM Starter <noreply@example.com> - 1.0.0-1
- Initial package

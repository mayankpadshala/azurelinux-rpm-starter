# azurelinux-rpm-starter

A cross-platform template to build, version, and lifecycle-test RPM packages targeted for **Azure Linux 3.0** (formerly CBL-Mariner) using Docker on macOS, Windows, and Linux.

---

## Quick Reference

> **Prerequisites**: [Docker](https://docs.docker.com/) must be running. On Windows, run `git config core.autocrlf input` to ensure UNIX line endings.

| Task | macOS / Linux | Windows (PowerShell) |
| :--- | :--- | :--- |
| **Default Build** *(reads `VERSION`)* | `./scripts/build.sh` *(or `make build`)* | `.\scripts\build.ps1` |
| **Custom Version Build** | `./scripts/build.sh 2.1.0 3` | `.\scripts\build.ps1 -Version "2.1.0" -Release "3"` |
| **Run Lifecycle Tests** | `./scripts/test-lifecycle.sh` *(or `make test`)* | `.\scripts\test-lifecycle.ps1` |
| **Interactive Debug Shell** | `make shell` | `docker run -it --rm -v "${PWD}/dist:/rpms" mcr.microsoft.com/azurelinux/base/core:3.0 /bin/bash` |

*Built packages are exported to `dist/` as both Binary (`.noarch.rpm`) and Source (`.src.rpm`) packages.*

---

## Repository Structure

```text
├── .github/workflows/
│   ├── pre-merge.yml           # PR check: RPM lifecycle test & script syntax validation
│   └── post-merge.yml          # Release: build RPM, compute SHA256, publish release & artifacts
├── docker/
│   ├── Dockerfile.builder      # Azure Linux build image with rpm-build toolchain
│   └── Dockerfile.tester       # Clean Azure Linux runtime for lifecycle testing
├── packaging/rpm/              # RPM spec definitions (hello-azurelinux.spec)
├── scripts/                    # Cross-platform build & test scripts (.sh / .ps1)
├── src/                        # Application source code & configuration files
├── Makefile                    # Shortcuts for UNIX environments
└── VERSION                     # Package version source of truth
```

---

## Lifecycle Validation

The test suite runs inside an ephemeral, clean Azure Linux 3.0 container across 5 stages:

1. **Install**: Baseline RPM (`1.0.0-1`) installs cleanly via `tdnf install`.
2. **Execute**: Binary executes and validates expected output and exit code.
3. **In-Place Upgrade**: Upgraded RPM (`1.0.1-1`) installs in-place via `tdnf install`.
4. **Verify Upgrade**: Binary verifies updated version while preserving `%config(noreplace)` config edits.
5. **Clean Removal**: `tdnf remove` removes the package and asserts no orphaned binaries remain.

---

## Package Inspection

Inspect packages in `dist/` without installing them on your host:

```bash
# List files inside the package
docker run --rm -v "$(pwd)/dist:/rpms:ro" mcr.microsoft.com/azurelinux/base/core:3.0 \
  rpm -qlp /rpms/hello-azurelinux-1.0.0-1.azl3.noarch.rpm

# View metadata, version, and architecture
docker run --rm -v "$(pwd)/dist:/rpms:ro" mcr.microsoft.com/azurelinux/base/core:3.0 \
  rpm -qip /rpms/hello-azurelinux-1.0.0-1.azl3.noarch.rpm
```

---

## CI/CD Workflows & Downloading Built Packages

The repository includes two automated GitHub Actions workflows:

1. **Pre-Merge Validation (`pre-merge.yml`)**:
   - Triggered on all pull requests targeting `main`.
   - Runs the full 5-stage lifecycle tests (`scripts/test-lifecycle.sh`: install → execute → upgrade → verify → remove) inside Azure Linux 3.0.
   - Validates PowerShell scripts syntax using `pwsh` AST parsing.
   - Gating check that must pass before merging.

2. **Post-Merge Release (`post-merge.yml`)**:
   - Triggered automatically when code is merged to `main`.
   - Compiles both binary (`.noarch.rpm`) and source (`.src.rpm`) packages and generates SHA256 checksums (`SHA256SUMS`).
   - **Always uploads to GitHub Actions Workflow Artifacts** (persisted for 90 days with every run).
   - **Publishes a GitHub Release ONLY when `VERSION` is updated in the PR/merge** (preventing unintentional releases for routine PRs).

---

## Using This Template as an Installer for Your Applications & Scripts

Azure Linux uses **RPM** as its native package and installer format, managed by **`tdnf`** (Tiny DNF). Packaging your shell scripts, daemons, or applications as an RPM gives you a production-grade installer that provides:
- **Standard System Placement**: Automatically deploys executables to `/usr/bin/`, configs to `/etc/<app>/`, and systemd units to `/usr/lib/systemd/system/`.
- **Automatic Dependency Resolution**: Declaring `Requires:` ensures `tdnf` automatically installs all required dependencies (e.g., `python3`, `curl`, `jq`) on target machines.
- **Safe In-Place Upgrades**: Config files marked `%config(noreplace)` prevent user configuration from being overwritten during upgrades.
- **Lifecycle Hooks**: Run custom pre/post install and uninstall actions (create users, enable systemd units, run migrations) via RPM scriptlets.
- **Transactional & Clean Uninstallation**: `tdnf remove` cleanly removes all package files and directories with zero orphaned artifacts.

Follow the step-by-step guide below to adapt this repository for your application:

---

### Step 1: Set Package Identity & Version

1. **Set Version**: Set your initial semantic version in [`VERSION`](VERSION) (e.g., `1.0.0` or `0.1.0`).
2. **Rename Spec File**: Rename `packaging/rpm/hello-azurelinux.spec` to match your package name:
   ```bash
   git mv packaging/rpm/hello-azurelinux.spec packaging/rpm/<your-app-name>.spec
   ```
3. **Update Package Name Variables**:
   Update the package name string across the build and test scripts:
   - **`docker/Dockerfile.builder`**: Change `ARG NAME=hello-azurelinux` to `ARG NAME=<your-app-name>`.
   - **`scripts/build.sh`**: Change `NAME="hello-azurelinux"` to `NAME="<your-app-name>"`.
   - **`scripts/build.ps1`**: Change `$Name = "hello-azurelinux"` to `$Name = "<your-app-name>"`.
   - **`scripts/test-lifecycle.sh`**: Change `NAME="hello-azurelinux"` to `NAME="<your-app-name>"`.
   - **`scripts/test-lifecycle.ps1`**: Change `$Name = "hello-azurelinux"` to `$Name = "<your-app-name>"`.

---

### Step 2: Add Your Scripts & Application Files to `src/`

Place your application files in [`src/`](src/). You can organize them into subdirectories as needed:

```text
src/
├── bin/
│   └── my-tool.sh               # Main executable or shell script
├── conf/
│   └── my-tool.conf             # Default configuration file
└── systemd/
    └── my-tool.service          # Optional systemd background service
```

> **Tip**: All files inside `src/` are automatically packaged into a source tarball by `docker/Dockerfile.builder` during the build process and unpacked into the build root for rpmbuild.

---

### Step 3: Configure the RPM Spec File (`packaging/rpm/<your-app-name>.spec`)

Edit your spec file to configure package metadata, dependencies, file installation, and installer lifecycle hooks.

#### 1. Package Metadata & Dependencies
```spec
Name:           my-tool
Version:        %{pkg_version}
Release:        %{pkg_release}%{?dist}
Summary:        My Automation CLI and Service for Azure Linux 3.0
License:        MIT
URL:            https://github.com/your-org/my-tool

# Source tarball generated automatically by Dockerfile.builder
Source0:        %{name}-%{version}.tar.gz

# Use "noarch" for architecture-independent packages (shell scripts, Python, etc.)
# Omit BuildArch if compiling native C/C++/Go/Rust binaries.
BuildArch:      noarch

# Runtime dependencies resolved and installed by tdnf on target systems:
Requires:       bash >= 5.0
Requires:       curl
Requires:       jq
```

#### 2. Install Layout (`%install`)
Copy files from the unpacked source tree into the target build root (`%{buildroot}`). Standard macros include:
- `%{_bindir}` $\rightarrow$ `/usr/bin` (executables and shell scripts)
- `%{_sysconfdir}` $\rightarrow$ `/etc` (configuration files)
- `%{_unitdir}` $\rightarrow$ `/usr/lib/systemd/system` (systemd service units)
- `%{_datadir}` $\rightarrow$ `/usr/share` (shared data and documentation)

```spec
%install
# Create destination directories
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_sysconfdir}/%{name}
mkdir -p %{buildroot}%{_unitdir}

# Install executable script with 0755 permissions
install -m 0755 src/bin/my-tool.sh %{buildroot}%{_bindir}/my-tool

# Install configuration file with 0644 permissions
install -m 0644 src/conf/my-tool.conf %{buildroot}%{_sysconfdir}/%{name}/my-tool.conf

# Install optional systemd unit
install -m 0644 src/systemd/my-tool.service %{buildroot}%{_unitdir}/my-tool.service
```

#### 3. Installer Lifecycle Hooks (Scriptlets)
RPM scriptlets execute bash commands at distinct points during package installation, upgrade, and uninstallation:

```spec
%pre
# Runs BEFORE package installation (e.g., create service account)
getent group mytool >/dev/null || groupadd -r mytool
getent passwd mytool >/dev/null || useradd -r -g mytool -s /sbin/nologin -d /var/empty mytool

%post
# Runs AFTER package installation (e.g., reload systemd daemon)
systemctl daemon-reload >/dev/null 2>&1 || true

%preun
# Runs BEFORE package removal ($1 == 0 means uninstallation, $1 == 1 means upgrade)
if [ $1 -eq 0 ]; then
    systemctl stop my-tool.service >/dev/null 2>&1 || true
    systemctl disable my-tool.service >/dev/null 2>&1 || true
fi

%postun
# Runs AFTER package removal
systemctl daemon-reload >/dev/null 2>&1 || true
```

#### 4. Files Manifest (`%files`)
Declare every file and directory installed by the package:
```spec
%files
# Binary on system PATH
%{_bindir}/my-tool

# Directory owned by this package (cleaned up on uninstall)
%dir %{_sysconfdir}/%{name}

# %config(noreplace) ensures existing user edits are NOT overwritten during upgrades
%config(noreplace) %{_sysconfdir}/%{name}/my-tool.conf

# Optional systemd unit
%{_unitdir}/my-tool.service
```

---

### Step 4: Update Automated Lifecycle Tests

Update the smoke test assertions in [`scripts/test-lifecycle.sh`](scripts/test-lifecycle.sh) (and [`scripts/test-lifecycle.ps1`](scripts/test-lifecycle.ps1)) to test your actual application:

1. **Test 2 (Post-Install Validation)**: Change `hello-azurelinux` to `my-tool` and assert your CLI flags (e.g. `my-tool --version`).
2. **Test 4 (Post-Upgrade Validation)**: Verify the upgraded version output and that custom modifications in `/etc/my-tool/my-tool.conf` were retained.
3. **Test 5 (Uninstall Validation)**: Change `hello-azurelinux` to `my-tool` to assert that `tdnf remove` cleanly removes the executable from `PATH`.

---

### Step 5: Build and Validate Locally

Build your RPM package and test it inside a fresh Azure Linux 3.0 container:

```bash
# 1. Build binary and source RPMs (outputs to dist/)
./scripts/build.sh          # Linux/macOS (or 'make build')
.\scripts\build.ps1         # Windows (PowerShell with Docker Desktop)

# 2. Run the 5-stage automated lifecycle test suite
./scripts/test-lifecycle.sh # Linux/macOS (or 'make test')
.\scripts\test-lifecycle.ps1 # Windows (PowerShell)

# 3. Inspect package metadata and file list without installing
docker run --rm -v "$(pwd)/dist:/rpms:ro" mcr.microsoft.com/azurelinux/base/core:3.0 \
  rpm -qlp /rpms/my-tool-1.0.0-1.azl3.noarch.rpm

# 4. Open an interactive debug shell in Azure Linux 3.0
make shell
```

---

### Step 6: Installing on Target Azure Linux Systems

Distribute your built `.rpm` file to Azure Linux VMs, physical hosts, or container base images. Target users can install, upgrade, and remove it with native commands:

```bash
# ── Install ──────────────────────────────────────────────────────────
# Installs package and automatically resolves runtime dependencies via tdnf:
sudo tdnf install -y ./my-tool-1.0.0-1.azl3.noarch.rpm

# Verify installation:
my-tool --version
rpm -qi my-tool             # View package metadata & description
rpm -ql my-tool             # List all installed files

# ── In-Place Upgrade ─────────────────────────────────────────────────
# Upgrades package in-place, preserving any user modifications to config files:
sudo tdnf install -y ./my-tool-1.1.0-1.azl3.noarch.rpm

# ── Clean Uninstallation ─────────────────────────────────────────────
# Cleanly removes all package files, services, and directories:
sudo tdnf remove -y my-tool
```

---

### Step 7: Automated Release & CI/CD

This repository provides two built-in GitHub Actions workflows:

1. **Pre-Merge Validation ([`pre-merge.yml`](.github/workflows/pre-merge.yml))**:
   - Runs on every Pull Request targeting `main`.
   - Boots a clean Azure Linux 3.0 container and validates install $\rightarrow$ execute $\rightarrow$ upgrade $\rightarrow$ config preservation $\rightarrow$ uninstall.
   - Gating check: prevents broken scripts or invalid spec configurations from merging.

2. **Post-Merge Release ([`post-merge.yml`](.github/workflows/post-merge.yml))**:
   - Runs when a PR is merged into `main`.
   - Always builds the RPMs and uploads them as downloadable **GitHub Actions Workflow Artifacts** (kept for 90 days).
   - **Automated Releases**: When you bump [`VERSION`](VERSION) in a PR (e.g. `1.0.0` $\rightarrow$ `1.1.0`), merging the PR automatically creates a **GitHub Release** tagged `v1.1.0` with direct download URLs for your RPM, SRPM, and `SHA256SUMS`. Routine merges that do not bump the `VERSION` file skip release creation to prevent release churn.

---

## Troubleshooting

| Problem | Cause | Solution |
| :--- | :--- | :--- |
| `\r: command not found` | Windows `CRLF` line endings. | Run `git config core.autocrlf input` and re-checkout, or run `dos2unix scripts/*.sh`. |
| `Cannot connect to Docker` | Docker daemon is stopped. | Start Docker Desktop or the system Docker service. |
| `Permission denied` on `.sh` | Missing execute permission in Git. | Run `chmod +x scripts/*.sh` and `git update-index --chmod=+x scripts/*.sh`. |
| Architecture mismatch | Package contains architecture-specific code. | Change `BuildArch: noarch` to target arch, or pass `--platform linux/amd64` to Docker. |
| `image operating system "linux" cannot be used` | Docker on Windows is in Windows container mode. | Switch Docker Desktop to Linux containers (Settings → General → Use the WSL 2 based engine). |

---

## License

MIT
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

## Using as a Template

To use this repository as a template to build an RPM installer for your own shell scripts or applications:

1. Click [**Use this template**](https://github.com/new?template_name=azurelinux-rpm-starter&template_owner=mayankpadshala) > **Create a new repository** on GitHub.
2. Update the following files to configure your package:

| File | What to Change | Description |
| :--- | :--- | :--- |
| [`VERSION`](VERSION) | Version string | Set initial semver (e.g., `0.1.0` or `1.0.0`) |
| `packaging/rpm/*.spec` | Rename & edit spec | Rename to `<name>.spec`. Set `Name:`, `Summary:`, dependencies (`Requires:`), and install paths in `%install` / `%files` |
| [`src/`](src/) | Replace payload | Place your shell scripts, binaries, or config files here |
| [`docker/Dockerfile.builder`](docker/Dockerfile.builder) | `ARG NAME=...` | Set package name to match your spec file |
| `scripts/build.sh` & `.ps1` | `NAME="..."` | Set your package name |
| `scripts/test-lifecycle.sh` & `.ps1` | `NAME="..."` | Set your package name and update CLI verification assertions |

3. Test locally with `./scripts/build.sh` and `./scripts/test-lifecycle.sh` (or `make build` / `make test`).
4. Commit and push:
   - PRs automatically run the 5-stage lifecycle tests via `pre-merge.yml`.
   - Merging with a bumped `VERSION` automatically publishes a GitHub Release with pre-built RPMs via `post-merge.yml`.

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
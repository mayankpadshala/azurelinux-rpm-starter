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
├── .github/workflows/ci.yml    # GitHub Actions CI matrix (Ubuntu & Windows)
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

## Customizing for Your Application

To adapt this template for your own project:

1. **Set Version**: Update `VERSION` with your initial semver (e.g., `0.1.0`).
2. **Add Sources**: Replace files in `src/` with your application code, configs, or systemd units.
3. **Configure Spec**: Update `packaging/rpm/*.spec` with your package `Name:`, `Summary:`, and installation paths under `%install` and `%files`.
4. **Update Builder**: Update `ARG NAME=your-package-name` in `docker/Dockerfile.builder`.
5. **Update Test Runner**: Update the binary name and assertions in `scripts/test-lifecycle.sh` and `scripts/test-lifecycle.ps1`.

---

## Troubleshooting

| Problem | Cause | Solution |
| :--- | :--- | :--- |
| `\r: command not found` | Windows `CRLF` line endings. | Run `git config core.autocrlf input` and re-checkout, or run `dos2unix scripts/*.sh`. |
| `Cannot connect to Docker` | Docker daemon is stopped. | Start Docker Desktop or the system Docker service. |
| `Permission denied` on `.sh` | Missing execute permission in Git. | Run `chmod +x scripts/*.sh` and `git update-index --chmod=+x scripts/*.sh`. |
| Architecture mismatch | Package contains architecture-specific code. | Change `BuildArch: noarch` to target arch, or pass `--platform linux/amd64` to Docker. |

---

## License

MIT
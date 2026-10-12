# ─────────────────────────────────────────────────────────────────────
# Makefile — Developer shortcuts for azurelinux-rpm-starter
# ─────────────────────────────────────────────────────────────────────
#
# Convenience targets for building, testing, and debugging RPM
# packages on macOS and Linux. All heavy lifting is delegated to
# the scripts/ directory, which in turn uses Docker.
#
# Usage:
#   make build                   # Build with default version from VERSION
#   make build VERSION=2.0.0     # Build with custom version
#   make test                    # Run the full lifecycle test suite
#   make clean                   # Remove built artifacts in dist/
#   make shell                   # Launch an interactive Azure Linux shell
#
# Variables:
#   VERSION — Semantic version (default: contents of VERSION file)
#   RELEASE — RPM release counter (default: 1)
# ─────────────────────────────────────────────────────────────────────

.PHONY: build test clean shell

# Read the default version from the VERSION file at the repo root.
# Both can be overridden on the command line (e.g. make build VERSION=2.0.0).
VERSION ?= $(shell cat VERSION)
RELEASE ?= 1

## build: Build the RPM package using Docker (see scripts/build.sh).
build:
	./scripts/build.sh $(VERSION) $(RELEASE)

## test: Run the full install → upgrade → uninstall lifecycle test suite.
test:
	./scripts/test-lifecycle.sh

## clean: Remove all built artifacts from the dist/ directory.
clean:
	rm -rf dist/

## shell: Launch an interactive Azure Linux 3.0 shell with dist/ mounted
##        at /rpms for ad-hoc debugging and package inspection.
shell:
	docker run -it --rm -v "$$(pwd)/dist:/rpms" mcr.microsoft.com/azurelinux/base/core:3.0 /bin/bash

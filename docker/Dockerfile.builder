# ─────────────────────────────────────────────────────────────────────
# Dockerfile.builder — RPM build environment for Azure Linux 3.0
# ─────────────────────────────────────────────────────────────────────
#
# Purpose:
#   Creates a Docker image that compiles RPM and SRPM packages from the
#   application sources. The build happens entirely at image-build time
#   (via RUN rpmbuild), so the resulting image contains the finished
#   packages in /output/.
#
# How the host build script uses this image:
#   1. docker build --build-arg VERSION=X.Y.Z --build-arg RELEASE=R ...
#   2. docker create <image>   → creates a stopped container
#   3. docker cp <cid>:/output/. dist/   → extracts RPMs to host
#   4. docker rm <cid>         → cleans up the container
#
# Build arguments:
#   NAME    — package name (default: hello-azurelinux)
#   VERSION — semantic version string (default: 1.0.0)
#   RELEASE — RPM release counter (default: 1)
# ─────────────────────────────────────────────────────────────────────

# Base image: Azure Linux 3.0 (formerly CBL-Mariner)
FROM mcr.microsoft.com/azurelinux/base/core:3.0

# Install the RPM build toolchain:
#   rpm-build — provides rpmbuild, the core RPM packaging tool
#   tar       — needed to create the source tarball expected by rpmbuild
#   python3   — required by Azure Linux rpm-build scripts (gen-ld-script.sh)
RUN tdnf install -y rpm-build tar python3 && tdnf clean all

# Build arguments passed in from the host build script.
# These control the package version embedded in the RPM metadata.
ARG NAME=hello-azurelinux
ARG VERSION=1.0.0
ARG RELEASE=1

# Set up the standard rpmbuild directory tree:
#   BUILD/   — rpmbuild unpacks and builds sources here
#   RPMS/    — binary RPMs are written here
#   SOURCES/ — source tarball goes here
#   SPECS/   — spec file goes here
#   SRPMS/   — source RPMs are written here
RUN mkdir -p /root/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Copy the RPM spec file into the SPECS directory.
COPY packaging/rpm/${NAME}.spec /root/rpmbuild/SPECS/${NAME}.spec

# Create the source tarball that rpmbuild's %setup macro expects.
# The tarball must contain a top-level directory named <name>-<version>/
# with the src/ folder inside it, matching the paths used in %install.
COPY src/ /tmp/${NAME}-${VERSION}/src/
RUN cd /tmp && tar czf /root/rpmbuild/SOURCES/${NAME}-${VERSION}.tar.gz ${NAME}-${VERSION}

# Run rpmbuild to produce both binary and source RPMs.
# --define injects the pkg_version and pkg_release macros referenced
# in the spec file's Version: and Release: tags.
RUN rpmbuild -ba /root/rpmbuild/SPECS/${NAME}.spec \
    --define "pkg_version ${VERSION}" \
    --define "pkg_release ${RELEASE}" \
    --define "_topdir /root/rpmbuild"

# Collect all built packages into a single /output directory so the
# host build script can extract them with a single docker cp command.
RUN mkdir -p /output && \
    cp /root/rpmbuild/RPMS/noarch/*.rpm /output/ && \
    cp /root/rpmbuild/SRPMS/*.rpm /output/

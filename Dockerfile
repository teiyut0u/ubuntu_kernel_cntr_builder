# syntax=docker/dockerfile:1
#
# Ubuntu 26.04 "resolute" kernel build environment.
#
# The kernel source tree is NOT baked into this image. Mount it at runtime:
#
#   docker build -t kernel-build:resolute .
#
#   mkdir -p /path/to/out
#   docker run --rm -it \
#     -v /path/to/resolute:/build/linux \
#     -v /path/to/out:/out \
#     kernel-build:resolute
#
# The UID/GID is detected from the owner of /build/linux.  It can be
# overridden with -e USER_UID=$(id -u) -e USER_GID=$(id -g).
#
# Then, inside the container:
#
#   # clean also generates debian/control and debian/changelog
#   debian/rules clean
#   DEB_BUILD_OPTIONS="parallel=$(nproc)" debian/rules binary-generic
#   cp -v /build/*.deb /out/
#
# The binary-generic target builds only the packages for the generic flavour
# (image, modules, buildinfo, headers, rust lib).  For a full dpkg-buildpackage
# run, additionally pass do_tools=false do_source_package=false.
#
# Notes:
#   - The source tree must be mounted at /build/linux (not at /build), because
#     debhelper writes the resulting .deb files into the parent directory of
#     the source tree (/build).
#   - The container starts as root only to create/reuse a user matching the
#     owner of the mounted source tree, then drops privileges with gosu. The
#     kernel build itself always runs as a non-root user.
#   - USER_UID/USER_GID can be passed with -e to override the auto-detected
#     UID/GID. Do not use "docker run --user": the entrypoint needs root in
#     order to create the matching user.
#   - This image follows the Build-Depends of debian.master/control.stub.in
#     for amd64 and pins the toolchain versions expected by the resolute kernel
#     annotations (gcc 15.2, rustc 1.93, pahole 1.31, clang/LLVM 21).
#
FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    # --- C/C++ toolchain ------------------------------------------------
    build-essential \
    # --- kernel build core ----------------------------------------------
    bc \
    bison \
    flex \
    gawk \
    libelf-dev \
    libssl-dev \
    libncurses-dev \
    liblzma-dev \
    libzstd-dev \
    zlib1g-dev \
    # --- kernel features / tools dependencies ---------------------------
    libudev-dev \
    libpci-dev \
    libnl-3-dev \
    libnl-genl-3-dev \
    libnuma-dev \
    libaudit-dev \
    libcap-dev \
    libnewt-dev \
    libtraceevent-dev \
    libtracefs-dev \
    libbpf-dev \
    libdw-dev \
    libunwind-dev \
    libdebuginfod-dev \
    libiberty-dev \
    uuid-dev \
    libpython3-dev \
    python3 \
    python3-dev \
    python3-setuptools \
    python3-docutils \
    pkg-config \
    autoconf \
    automake \
    libtool \
    cpio \
    kmod \
    rsync \
    zstd \
    xz-utils \
    bzip2 \
    gzip \
    perl \
    pahole \
    makedumpfile \
    bpftool \
    # --- Rust for Linux -------------------------------------------------
    clang-21 \
    llvm-21-dev \
    libclang-dev \
    libclang-21-dev \
    rustc \
    rust-src \
    rustfmt \
    bindgen \
    # --- packaging ------------------------------------------------------
    dpkg-dev \
    debhelper \
    dkms \
    dh-python \
    fakeroot \
    gosu \
    passwd \
    # --- docs / perf / misc ---------------------------------------------
    default-jdk-headless \
    java-common \
    asciidoc \
    xmlto \
    sharutils \
    ca-certificates \
    curl \
    git \
    wget \
    openssl \
 && rm -rf /var/lib/apt/lists/*

# The entrypoint creates/reuses a user matching the mounted source tree's
# owner, sets RUST_LIB_SRC at runtime, and then drops privileges with gosu.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh \
 && install -d -m 0777 /build /build/linux /out

WORKDIR /build/linux

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]

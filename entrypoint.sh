#!/bin/bash
set -euo pipefail

log() {
    printf '[entrypoint] %s\n' "$*" >&2
}

# The kernel's rust/Makefile needs the Rust core sources.  The location
# depends on how rustc/rust-src are packaged, so derive it at runtime instead
# of hard-coding it in the image.
setup_rust_lib_src() {
    command -v rustc >/dev/null 2>&1 || return 0

    local sysroot libsrc rustver

    sysroot="$(rustc --print sysroot)"
    libsrc="${sysroot}/lib/rustlib/src/rust/library"
    if [ -f "${libsrc}/core/src/lib.rs" ]; then
        export RUST_LIB_SRC="$libsrc"
        return 0
    fi

    # Ubuntu also ships the sources under /usr/src/rustc-<version>/library.
    rustver="$(rustc --version | awk '{print $2}')"
    libsrc="/usr/src/rustc-${rustver}/library"
    if [ -f "${libsrc}/core/src/lib.rs" ]; then
        export RUST_LIB_SRC="$libsrc"
        return 0
    fi

    # Last-resort fallback for the Debian/Ubuntu rust-src symlink layout.
    libsrc="/usr/lib/rustlib/src/rust/library"
    if [ -f "${libsrc}/core/src/lib.rs" ]; then
        export RUST_LIB_SRC="$libsrc"
        return 0
    fi

    log "warning: could not find the Rust core sources; RUST_LIB_SRC is unset"
}

setup_rust_lib_src

# If the container was started with --user, there is nothing to set up.
# In that case the caller is responsible for /build permissions.
if [ "$(id -u)" -ne 0 ]; then
    if [ -z "${HOME:-}" ] || [ ! -w "${HOME:-/nonexistent}" ]; then
        export HOME=/tmp
    fi
    exec "$@"
fi

# Default to the owner of the bind-mounted source tree.  This makes the image
# work on machines whose UID/GID is not 1000 without rebuilding it.
DEFAULT_UID="$(stat -c '%u' /build/linux 2>/dev/null || echo 1000)"
DEFAULT_GID="$(stat -c '%g' /build/linux 2>/dev/null || echo 1000)"
[ "$DEFAULT_UID" = "0" ] && DEFAULT_UID=1000
[ "$DEFAULT_GID" = "0" ] && DEFAULT_GID=1000

TARGET_UID="${USER_UID:-$DEFAULT_UID}"
TARGET_GID="${USER_GID:-$DEFAULT_GID}"

if [ "$TARGET_UID" = "0" ]; then
    export HOME=/root
    exec "$@"
fi

# Find or create the group.
if getent group "$TARGET_GID" >/dev/null 2>&1; then
    TARGET_GROUP="$(getent group "$TARGET_GID" | cut -d: -f1)"
else
    TARGET_GROUP="builder"
    if getent group "$TARGET_GROUP" >/dev/null 2>&1; then
        TARGET_GROUP="builder-${TARGET_GID}"
    fi
    groupadd -g "$TARGET_GID" "$TARGET_GROUP"
fi

# Find or create the user.
if getent passwd "$TARGET_UID" >/dev/null 2>&1; then
    TARGET_USER="$(getent passwd "$TARGET_UID" | cut -d: -f1)"
    # Make sure the primary group matches the source tree's group.
    if [ "$(id -g "$TARGET_USER")" != "$TARGET_GID" ]; then
        usermod -g "$TARGET_GROUP" "$TARGET_USER"
    fi
else
    TARGET_USER="builder"
    if getent passwd "$TARGET_USER" >/dev/null 2>&1; then
        TARGET_USER="builder-${TARGET_UID}"
    fi
    useradd -m -u "$TARGET_UID" -g "$TARGET_GROUP" -s /bin/bash "$TARGET_USER"
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [ -z "$TARGET_HOME" ] || [ "$TARGET_HOME" = "/" ]; then
    TARGET_HOME="/home/${TARGET_USER}"
    mkdir -p "$TARGET_HOME"
    chown "${TARGET_UID}:${TARGET_GID}" "$TARGET_HOME"
fi

export HOME="$TARGET_HOME"
export USER="$TARGET_USER"
export LOGNAME="$TARGET_USER"

log "building as ${TARGET_USER} (uid=${TARGET_UID} gid=${TARGET_GID}), HOME=${HOME}"
if [ -n "${RUST_LIB_SRC:-}" ]; then
    log "RUST_LIB_SRC=${RUST_LIB_SRC}"
fi

exec gosu "$TARGET_USER" "$@"

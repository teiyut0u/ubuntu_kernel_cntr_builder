#!/usr/bin/env bash
#
# Build the kernel build image described by a rendered Dockerfile.
#
# Usage:
#   ./image_builder.sh [Dockerfile] [docker build options...]
#
# With no argument, ./Dockerfile in the current directory is used. If it does
# not exist the script exits; it never generates one implicitly.
# The Ubuntu release is read from the Dockerfile's FROM line and the kernel
# release from its
#   ARG KERNEL_RELEASE=<value>
# line, giving the image tag:
#   ubuntu_kernel_builder:<ubuntu-release>-<kernel-release>

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: image_builder.sh [Dockerfile] [docker build options...]

Build ubuntu_kernel_builder:<ubuntu-release>-<kernel-release> from a Dockerfile
rendered by generate_Dockerfile.sh. The Ubuntu release comes from the FROM
line, the kernel release from ARG KERNEL_RELEASE.

Arguments:
  [Dockerfile]        Path to the Dockerfile, or to a directory containing one.
                      Default: ./Dockerfile in the current directory.
  [build options...]  Extra options forwarded to `docker build`.

Environment:
  DOCKER              Container engine to use (default: docker).

Examples:
  ./image_builder.sh
  ./image_builder.sh Dockerfile.resolute --pull
EOF
}

docker_bin=${DOCKER:-docker}

if [ $# -gt 0 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
    usage
    exit 0
fi

# First argument is the Dockerfile, unless it is an option, in which case the
# default ./Dockerfile is used and the option is forwarded to docker build.
if [ $# -gt 0 ] && [[ "$1" == -* ]]; then
    dockerfile=Dockerfile
    extra_args=("$@")
else
    dockerfile=${1:-Dockerfile}
    [ $# -eq 0 ] || shift
    extra_args=("$@")
fi

if [ -d "$dockerfile" ]; then
    dockerfile="${dockerfile%/}/Dockerfile"
fi

if [ ! -f "$dockerfile" ]; then
    printf 'error: Dockerfile not found: %s\n' "$dockerfile" >&2
    printf 'hint: render one first, e.g. ./generate_Dockerfile.sh 6.8.0-45-generic\n' >&2
    exit 1
fi

kernel_release=$(
    sed -nE 's/^[[:space:]]*ARG[[:space:]]+KERNEL_RELEASE=(.*)$/\1/p' "$dockerfile" |
        head -n1 | tr -d '[:space:]\r'
)

if [ -z "$kernel_release" ]; then
    die "cannot find 'ARG KERNEL_RELEASE=<kernel-release>' in $dockerfile"
fi
if ! [[ "$kernel_release" =~ ^[0-9][A-Za-z0-9.+~_-]*$ ]]; then
    die "invalid kernel release '$kernel_release' in $dockerfile; re-render it with generate_Dockerfile.sh"
fi

command -v "$docker_bin" >/dev/null 2>&1 ||
    die "container engine not found: $docker_bin (set DOCKER=... to override)"

# Determine the Ubuntu release from the (rendered) FROM line, ignoring
# optional --platform=... flags and @sha256:... digests.
base_image=$(
    awk '/^[[:space:]]*FROM[[:space:]]/ {
             for (i = 2; i <= NF; i++)
                 if ($i !~ /^--/) { print $i; exit }
         }' "$dockerfile"
)
[ -n "$base_image" ] || die "cannot find a FROM line in $dockerfile"

image_ref=${base_image%%@*}
ubuntu_release=${image_ref#*:}
if [ "$ubuntu_release" = "$image_ref" ] || [ -z "$ubuntu_release" ]; then
    die "cannot determine the Ubuntu release from 'FROM $base_image' in $dockerfile"
fi
if ! [[ "$ubuntu_release" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    die "invalid Ubuntu release '$ubuntu_release' in $dockerfile"
fi

image_tag="${ubuntu_release}-${kernel_release}"
if [ ${#image_tag} -gt 128 ]; then
    die "image tag is longer than 128 characters: $image_tag"
fi
image="ubuntu_kernel_builder:${image_tag}"
context=$(cd -- "$(dirname -- "$dockerfile")" && pwd)
dockerfile=${context}/$(basename -- "$dockerfile")

# Dockerfile.template copies build_kernel_in_container.sh into the image.  It
# must be in the build context; stage a copy when the Dockerfile was rendered
# somewhere else.
helper=build_kernel_in_container.sh
staged_helper=""
cleanup() { [ -z "$staged_helper" ] || rm -f -- "$staged_helper"; }
trap cleanup EXIT

if [ ! -f "$context/$helper" ]; then
    [ -f "$script_dir/$helper" ] || die "build script not found: $script_dir/$helper"
    cp -- "$script_dir/$helper" "$context/$helper"
    staged_helper="$context/$helper"
fi

printf 'Dockerfile : %s\n' "$dockerfile"
printf 'context    : %s\n' "$context"
if [ -n "$staged_helper" ]; then
    printf 'staged     : %s\n' "$staged_helper"
fi
printf 'ubuntu     : %s\n' "$ubuntu_release"
printf 'kernel     : %s\n' "$kernel_release"
printf 'image      : %s\n' "$image"
printf '\n'

# Forward any extra options after the fixed ones.
"$docker_bin" build -t "$image" -f "$dockerfile" \
    ${extra_args[@]+"${extra_args[@]}"} "$context"

printf '\nbuilt %s\n' "$image"

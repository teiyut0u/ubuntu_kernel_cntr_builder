#!/usr/bin/env bash
#
# Render Dockerfile.template for a given Ubuntu kernel release.
#
# Usage:
#   ./generate_Dockerfile.sh <kernel-release> [-r <ubuntu-release>] [-o <file>]
#
# <kernel-release> is mandatory and is substituted for __KERNEL_RELEASE__ in
# the template (it is the value `uname -r` prints on the target machine).

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
template="${script_dir}/Dockerfile.template"

usage() {
    cat <<'EOF'
Usage: generate_Dockerfile.sh <kernel-release> [options]

Render Dockerfile.template for one Ubuntu kernel release. The kernel source is
not downloaded; the resulting image only contains the build environment.

Arguments:
  <kernel-release>          Required. e.g. 6.8.0-45-generic, 7.0.0-14-generic

Options:
  -r, --ubuntu-release REL  Ubuntu release or codename whose archive carries
                            that kernel (e.g. noble, 24.04, resolute).
                            Default: inferred from the kernel version.
  -o, --output FILE         Output file (default: ./Dockerfile).
  -h, --help                Show this help and exit.

Examples:
  ./generate_Dockerfile.sh 6.8.0-45-generic
  ./generate_Dockerfile.sh 7.0.0-14-generic -r resolute -o Dockerfile.resolute
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

# Best-effort mapping of a kernel version to the Ubuntu release that ships it.
ubuntu_release_for_kernel() {
    local kernel_release=$1
    local major minor
    major=${kernel_release%%.*}
    minor=${kernel_release#*.}
    minor=${minor%%.*}

    case "${major}.${minor}" in
        6.8)  echo noble ;;      # 24.04 LTS
        6.11) echo oracular ;;   # 24.10
        6.14) echo plucky ;;     # 25.04
        6.17) echo questing ;;   # 25.10
        7.0)  echo resolute ;;   # 26.04 LTS
        *)    return 1 ;;
    esac
}

kernel_release=""
ubuntu_release=""
output="./Dockerfile"

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -r|--ubuntu-release)
            [ $# -ge 2 ] || die "$1 requires one argument"
            ubuntu_release=$2
            shift 2
            ;;
        -o|--output)
            [ $# -ge 2 ] || die "$1 requires one argument"
            output=$2
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "unknown option: $1 (see --help)"
            ;;
        *)
            [ -z "$kernel_release" ] || die "unexpected extra argument: $1"
            kernel_release=$1
            shift
            ;;
    esac
done

[ -n "$kernel_release" ] || {
    usage >&2
    die "the target kernel release is required"
}
[ $# -eq 0 ] || die "unexpected extra argument: $1"

# Keep the value safe for sed and for use inside the Dockerfile.
if ! [[ "$kernel_release" =~ ^[0-9][A-Za-z0-9.+~_-]*$ ]]; then
    die "invalid kernel release: '$kernel_release' (expected e.g. 6.8.0-45-generic)"
fi

[ -f "$template" ] || die "template not found: $template"
grep -q '__KERNEL_RELEASE__' "$template" ||
    die "template has no __KERNEL_RELEASE__ placeholder: $template"

if [ -z "$ubuntu_release" ]; then
    ubuntu_release=$(ubuntu_release_for_kernel "$kernel_release") || {
        die "cannot infer the Ubuntu release for kernel '$kernel_release'; pass it explicitly with -r <codename|version>"
    }
fi

if ! [[ "$ubuntu_release" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    die "invalid Ubuntu release: '$ubuntu_release'"
fi

output_dir=$(dirname -- "$output")
mkdir -p -- "$output_dir"
output_dir=$(cd -- "$output_dir" && pwd)
output="${output_dir}/$(basename -- "$output")"

tmp=$(mktemp "${output}.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT

sed -e "s|__KERNEL_RELEASE__|${kernel_release}|g" \
    -e "s|__UBUNTU_RELEASE__|${ubuntu_release}|g" \
    "$template" >"$tmp"

if grep -q '__[A-Z_]*__' "$tmp"; then
    die "unsubstituted placeholder left in output: $(grep -o '__[A-Z_]*__' "$tmp" | sort -u | tr '\n' ' ')"
fi

chmod 0644 "$tmp"
mv -f -- "$tmp" "$output"
trap - EXIT

printf 'wrote %s\n' "$output"
printf '  kernel release : %s\n' "$kernel_release"
printf '  ubuntu release : %s\n' "$ubuntu_release"
printf '  image tag      : ubuntu_kernel_builder:%s-%s\n' "$ubuntu_release" "$kernel_release"

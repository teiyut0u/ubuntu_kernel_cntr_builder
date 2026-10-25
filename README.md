# Ubuntu kernel build container

Containerised version of the Ubuntu guide
[How to build an Ubuntu Linux kernel](https://ubuntu.com/kernel/docs/how-to/develop-customise/build-kernel/).

The image only provides the build environment (`apt build-dep` for the target
kernel release plus the extra packages from the guide). Kernel sources are
**not** downloaded at image build time:

* `kernel_builder.sh <src-dir>` bind-mounts an existing source tree at
  `/build/linux`. `<src-dir>` must be the extracted tree itself (e.g.
  `.../linux-7.0.0`, the directory containing `debian/`), not the directory
  that holds the `.dsc`/tarballs.
* `kernel_builder.sh` without a source directory runs
  `apt source linux-image-unsigned-<kernel-release>` inside the container.

## Files

| File | Purpose |
| --- | --- |
| `Dockerfile.template` | Image template with `__KERNEL_RELEASE__` / `__UBUNTU_RELEASE__` placeholders |
| `generate_Dockerfile.sh` | Renders the template for a kernel release (required argument) |
| `image_builder.sh` | Builds `ubuntu_kernel_builder:<ubuntu-release>-<kernel-release>` from a rendered Dockerfile |
| `build_kernel_in_container.sh` | In-container build logic, baked into the image as `/usr/local/bin/ubuntu-kernel-build.sh` |
| `kernel_builder.sh` | Runs the build and copies the `.deb` files back to the host |

## Quick start

```bash
# 1. Render a Dockerfile for the target kernel (e.g. the server's `uname -r`)
./generate_Dockerfile.sh 6.8.0-45-generic

# 2. Build the image -> ubuntu_kernel_builder:noble-6.8.0-45-generic
./image_builder.sh                  # uses ./Dockerfile
# or: ./image_builder.sh path/to/Dockerfile

# 3a. Build an existing source tree (mounted at /build/linux)
./kernel_builder.sh ~/src/linux -k 6.8.0-45-generic

# 3b. Or let the container fetch the source with apt source
./kernel_builder.sh -k 6.8.0-45-generic
```

The image tag combines the Ubuntu release from the Dockerfile's `FROM` line
and the kernel release from `ARG KERNEL_RELEASE=...`. `kernel_builder.sh`
looks up the matching local image automatically; pass `-r noble` if several
Ubuntu releases carry the same kernel release.

The `.deb` files are collected in `./debs/<kernel-release>/` by default
(`-o/--output` to change it).

## Choosing the Ubuntu release

`generate_Dockerfile.sh` infers the base image from the kernel version:

| Kernel | Ubuntu |
| --- | --- |
| 6.8 | noble (24.04 LTS) |
| 6.11 | oracular (24.10) |
| 6.14 | plucky (25.04) |
| 6.17 | questing (25.10) |
| 7.0 | resolute (26.04 LTS) |

For HWE kernels or anything not in the table, pass the archive explicitly,
e.g. a 6.17 kernel installed on 24.04:

```bash
./generate_Dockerfile.sh 6.17.0-14-generic -r noble   # -> ubuntu_kernel_builder:noble-6.17.0-14-generic
```

## Notes

* The image installs `apt build-dep` for the target kernel plus only
  `build-essential` and the four packages from the guide
  (`fakeroot llvm libncurses-dev dwarves`). Everything else is already covered
  by the kernel's own `Build-Depends`.
* The in-container steps live in `build_kernel_in_container.sh` and are
  `COPY`ed into the image as `/usr/local/bin/ubuntu-kernel-build.sh`, so
  `kernel_builder.sh` only passes mounts and environment variables. Changing
  that script requires rebuilding the image (the apt layers stay cached). If
  the Dockerfile was rendered outside this directory, `image_builder.sh`
  stages a copy of the script into the build context for the build and removes
  it afterwards.
* In `apt source` mode the container unpacks the tree into `/build`
  (`/build/linux-<version>`) and creates a symlink `/build/linux` to it, so
  the layout is the same as with a bind-mounted source directory. Note that
  `apt source` uses the source version currently in the archive, which can be
  newer than the ABI in the requested kernel release.
* With a mounted source tree the container starts as root, changes the owner
  of `/build/linux` (only if some entries do not match) and `/output` to
  `HOST_UID:HOST_GID`, then re-executes the build with `setpriv` as that user.
  This also fixes trees that were created by a previous root container, so the
  source tree and the `.deb` files end up owned by the caller. Use `--root` to
  skip the ownership fix and build as root. With a rootless engine (e.g.
  rootless podman) use `--root` as well, since uid mapping makes the chown
  meaningless.
* In `apt source` mode the build runs as root inside the container (it needs
  to install packages and fetch the source); `/output` is chown'ed to
  `HOST_UID:HOST_GID` after the `.deb` files are copied.
* `do_linux_main_modules_depends=false` is exported, as recommended for
  development builds (zfs / v4l2loopback modules are skipped).
* To avoid clashing with Canonical's packages, bump the ABI in the changelog
  (`debian.master/changelog` for the generic kernel) before building, e.g.
  `linux (6.8.0-999.48) noble; urgency=medium`.
* `CONCURRENCY_LEVEL` / `DEB_BUILD_OPTIONS=parallel=N` are set from `-j`
  (default: `nproc`).
* Extra options for `docker build` can be appended to `image_builder.sh`;
  set `DOCKER=podman` to use another engine.

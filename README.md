# scripts
A place to keep various scripts and things.

chroot.sh - A script that helps set up a chroot build environment using an overlayfs. The rootfs stays on the lower directory in a pristine state, while all changes and packages are built on the upper directory. Once a build is done, purge the upper directory to reset to a pristine state for a fresh build.

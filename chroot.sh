#!/bin/bash
#
# chroot.sh 
#
# This script will set up bind mounts and an overlayfs for a chroot environment, and then start the chroot.
# 
# When you exit the chroot, this script will also clean up the binds and overlayfs for you.
#
# This is useful for making build environments that can be reset easily: After building, exit the chroot 
# and take what you need from the 'changes' directory. When you need a fresh build environment, just remove
# the changes directory run chroot.sh to start with a fresh build.
#
# You will need to make the 'rootfs' directory yourself by installing a valid OS there. For example, I use 
# a local copy of the slackware-current tree and install slackware using:
#
# installpkg --root /root/chroot-builds/rootfs /mnt/mirror/slackware64-current/slackware64/*.t?z
#
# Written by Bob Funk. 2020, updated 2022.
#

BASEDIR="$(pwd)"
ROOTFS="$BASEDIR/rootfs" # The read-only base system 
CHANGES="$BASEDIR/changes" # All work will be saved here
WORKDIR="$BASEDIR/.work" # overlayfs requires a writable, empty work directory
CHROOT="$BASEDIR/chroot" # Location where we mount the overlayfs, for chrooting in to

# Make the directories if needed:
for dir in ${BASEDIR} ${ROOTFS} ${CHANGES} ${WORKDIR} ${CHROOT}
do
  [ ! -d $dir ] && mkdir $dir
done

# Exit if the root filesystem isnt installed properly for chroot.
if [ ! -d "$ROOTFS" -o ! -d "$ROOTFS/dev" -o ! -d "$ROOTFS/sys" -o ! -d "$ROOTFS/proc" ]; then
  printf "The root filesystem directory doesn't appear to be valid.\nPlease 'installpkg --root' to install a proper filesystem into:\n $ROOTFS\n"
  exit 1
fi

# Set up the overlayfs:
mount -t overlay overlay -o lowerdir=${ROOTFS},upperdir=${CHANGES},workdir=${WORKDIR} ${CHROOT}

# Set up bind mounts:
mount -o bind /proc ${CHROOT}/proc
mount -o bind /sys ${CHROOT}/sys
mount -o bind /dev ${CHROOT}/dev
mount -o bind /etc/resolv.conf ${CHROOT}/etc/resolv.conf

# Enter the chroot environment:
printf "You are now in the chroot build environment.\nType 'exit' or 'ctrl+d' to leave.\n"
printf "If this is a fresh chroot, you will probably want to run 'update-ca-certificates -f'.\n"
chroot ${CHROOT}

# Unmount overlay and bind mounts after exiting chroot:
umount ${CHROOT}/proc
umount ${CHROOT}/sys
umount ${CHROOT}/dev
umount ${CHROOT}/etc/resolv.conf
umount ${CHROOT}

# All done. Grab packages from the changes/tmp directory, or wherever they are built under
# the changes directory, clean up 'changes' and start fresh again as needed.

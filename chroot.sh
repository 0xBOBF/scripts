#!/bin/bash

# This script will setup the bind mounts and overlayfs
# for the chroot environment and chroot you in.
# When you exit the chroot this script will also clean
# up the binds and overlayfs.
#
# Starting with a fresh build environment is as simple as wiping the
# "changes" directory and starting over.
#
# Added functionality to auto check and update the rootfs layer, if 
# an update is available on the mirror (at the user's prompting). This
# eases maintenance of the clean base layer, leaving just the changes 
# layer for the user to manage manually.
#
# Added functionality to use a common/shared home directory for root.
# This shared directory is called "root-home", and gets bind mounted
# to the chroot directory. This allows keeping a persistent home dir
# for root between wipes of the changes directory.

SLACK_TYPE="slackware64"
SLACK_VERSION="15.0"
SLACK_STRING="$SLACK_TYPE-$SLACK_VERSION"

# A local slackware mirror for initializing the slackware rootfs
# and keeping the rootfs updated:
SLACK_MIRROR=${SLACK_MIRROR:-"/mnt/netdrive/mirror/$SLACK_STRING"}

# The base directory where we keep the overlayfs structure:
BASEDIR="$(pwd)"

# The read-only base system, containing a pristine Slackware install:
ROOTFS="$BASEDIR/$SLACK_STRING-rootfs"

# All modifications (home directories, packages and builds, etc) are here:
CHANGES="$BASEDIR/$SLACK_STRING-changes"

# Overlayfs requires a writable, empty work directory:
WORKDIR="$BASEDIR/.$SLACK_STRING-work"

# Location where we mount the overlayfs layers, and then chroot to:
CHROOT="$BASEDIR/.$SLACK_STRING-chroot"

# Location to bind the local mirror, so we can access it from in the chroot:
LOCAL_MIRROR="/mnt/local-mirror" 

# Use a shared home directory for root user (/root):
SHARED_ROOT_HOME_DIR="$BASEDIR/root-home"

# Make the directories if needed:
for dir in "$BASEDIR" "$ROOTFS" "$CHANGES" "$WORKDIR" "$CHROOT" "$CHANGES/root" "$SHARED_ROOT_HOME_DIR"
do
  [ ! -d $dir ] && mkdir $dir
done

# Check if rootfs is empty, offer help to set one up if we can:
if [ -z "$(ls -A "$ROOTFS")" ]; then
  echo "The root filesystem '$ROOTFS' is empty."
  if [ -d "$SLACK_MIRROR" ]; then
    echo "You have a local mirror set to: '$SLACK_MIRROR'"
    echo "It's contents are:"
    ls "$SLACK_MIRROR"
    echo "If this is a valid mirror, we can attempt to run the following from it:"
    echo "/sbin/installpkg --root \"$ROOTFS\" \"$SLACK_MIRROR/slackware*/*/*.t?z\""
    echo "(y/n)?"
    read -p "> " ANSWER
    if [ "$ANSWER" = "y" -o "$ANSWER" = "Y" ]; then
      /sbin/installpkg --terse --root "$ROOTFS" "$SLACK_MIRROR/slackware*/*/*.t?z"
    else
      exit 0
    fi
  else
    # Empty rootfs and no mirror...
    echo "Slackware mirror: '$SLACK_MIRROR' not found."
    echo "Please set up a valid mirror at: '$SLACK_MIRROR'"
    echo "Alternatively, pass a custom SLACK_MIRROR= to this script."
    exit 1
  fi
fi

# Exit if the root filesystem isnt installed properly for chroot:
if [ ! -d "$ROOTFS" -o ! -d "$ROOTFS/dev" -o ! -d "$ROOTFS/sys" -o ! -d "$ROOTFS/proc" ]; then
  printf "The root filesystem directory doesn't appear to be valid.\n\
    Please 'installpkg --root' to install a proper filesystem into:\n\
    $ROOTFS\n"
  exit 1
fi

# Ensure the local-mirror mount point exists:
[ ! -d "$ROOTFS$LOCAL_MIRROR" ] && mkdir -p "$ROOTFS$LOCAL_MIRROR"

# Run some update checks against the local-mirror:
echo "Checking for rootfs updates."
mount -B "$SLACK_MIRROR" "$ROOTFS$LOCAL_MIRROR"

# If there are packages in the /patches directory on the mirror, check if any patches should be applied:
# i.e. keep a slackware-stable rootfs up to date
if [ -d "$SLACK_MIRROR/patches/packages" ]; then
  cat << EOF > "$ROOTFS/upgradepkg.sh"
#!/bin/bash
/sbin/upgradepkg --dry-run $LOCAL_MIRROR/patches/packages/*.t?z | grep -v 'already installed' | wc -l
EOF
  UPGRADE_COUNT=$(chroot "$ROOTFS" /bin/bash /upgradepkg.sh)
  if [ "$UPGRADE_COUNT" -gt "0" ]; then
    echo "There are $UPGRADE_COUNT packages with available patches."
    echo "Should we update the rootfs to the latest patches with:"
    echo "/sbin/upgradepkg  \"$LOCAL_MIRROR/patches/packages/*.t?z\""
    echo "(y/n)?"
    read -p "> " ANSWER
    if [ "$ANSWER" = "y" -o "$ANSWER" = "Y" ]; then
      cat << EOF > "$ROOTFS/upgradepkg.sh"
#!/bin/bash
/sbin/upgradepkg --install-new --terse $LOCAL_MIRROR/patches/packages/*.t?z
EOF
      chroot "$ROOTFS" /bin/bash /upgradepkg.sh
    fi
  else
    echo "No updates found."
  fi
fi

# Also check if upgradepkg can update anything against the main package tree:
# i.e. keep slackware-current rootfs up to date:
if [ "$SLACK_VERSION" = "current" ]; then
  cat << EOF > "$ROOTFS/upgradepkg.sh"
#!/bin/bash
/sbin/upgradepkg --install-new --dry-run $LOCAL_MIRROR/$SLACK_TYPE/*/*.t?z | grep -v 'already installed' | wc -l
EOF
  UPGRADE_COUNT=$(chroot "$ROOTFS" /bin/bash /upgradepkg.sh)
  if [ "$UPGRADE_COUNT" -gt "0" ]; then
    echo "There are $UPGRADE_COUNT packages available to upgrade."
    echo "Should we update the rootfs to the latest packages using:"
    echo "/sbin/upgradepkg  \"$LOCAL_MIRROR/$SLACK_TYPE/*/*.t?z\""
    echo "(y/n)?"
    read -p "> " ANSWER
    if [ "$ANSWER" = "y" -o "$ANSWER" = "Y" ]; then
      cat << EOF > "$ROOTFS/upgradepkg.sh"
#!/bin/bash
/sbin/upgradepkg --install-new --terse $LOCAL_MIRROR/$SLACK_TYPE/*/*.t?z
EOF
      chroot "$ROOTFS" /bin/bash /upgradepkg.sh
    fi
  else
    echo "No updates found."
  fi
fi
rm -f "$ROOTFS/upgradepkg.sh"
umount "$ROOTFS$LOCAL_MIRROR"

# Set up the overlayfs:
mount -t overlay overlay -o lowerdir="$ROOTFS",upperdir="$CHANGES",workdir="$WORKDIR" "$CHROOT"

# Set up bind mounts:
mount -B /proc "$CHROOT/proc"
mount -B /sys "$CHROOT/sys"
mount -B /dev "$CHROOT/dev"
mount -B /dev/pts "$CHROOT/dev/pts"
mount -B /etc/resolv.conf "$CHROOT/etc/resolv.conf"
mount -B "$SLACK_MIRROR" "$CHROOT$LOCAL_MIRROR"
mount -B "$SHARED_ROOT_HOME_DIR" "$CHROOT/root"

# Enter the chroot environment:
printf "You are now in the chroot build environment.\nType 'exit' when you are done.\n"

env -i HOME=/root TERM=$TERM chroot "$CHROOT" /bin/bash -l

# Unmount overlay and bind mounts after exiting chroot:
umount "$CHROOT/proc"
umount "$CHROOT/sys"
umount "$CHROOT/dev/pts"
umount "$CHROOT/dev"
umount "$CHROOT/etc/resolv.conf"
umount "$CHROOT$LOCAL_MIRROR"
umount "$CHROOT/root"
umount "$CHROOT"

# All done. Grab packages from the changes/tmp directory, or wherever they are built under
# the changes directory, clean up 'changes' and start fresh again as needed.

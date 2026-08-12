#!/usr/bin/env bash
# Create a fixed-size ext4 loop-image and mount it at
# deployment/.volumes/<instance>, so that instance's home dir can never grow
# past the given size -- regardless of how much free space the host disk has.
#
# Must run as root (needs losetup/mount). Run from anywhere; paths are
# resolved relative to this script's own location (deployment/), so it also
# works as `sudo ./setup-quota.sh` from inside deployment/ or
# `sudo deployment/setup-quota.sh` from the repo root.
#
# Usage:
#   sudo ./setup-quota.sh <INSTANCE> <SIZE>
#
# Both are required -- always name the folder AND the cap explicitly, so
# there's no ambiguity about which container's home dir gets how much space.
#
# Examples:
#   sudo ./setup-quota.sh main 10G
#   sudo ./setup-quota.sh alice 5G
#
# Idempotent: if the mount point is already mounted, it's left alone. The
# image file is only created (and formatted) once -- re-running with the
# same INSTANCE does not touch existing data.
#
# To undo: `sudo umount deployment/.volumes/<instance>` and remove
# deployment/.quota-images/<instance>.img.
#
# To persist across host reboots, add the printed /etc/fstab line yourself
# (this script does not edit /etc/fstab).

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: must run as root (needs losetup/mount). Try: sudo $0 $*" >&2
  exit 1
fi

if [ $# -lt 2 ]; then
  echo "ERROR: INSTANCE (folder name) and SIZE are both required." >&2
  echo "Usage: sudo $0 <instance> <size>" >&2
  echo "Example: sudo $0 alice 5G" >&2
  exit 1
fi

INSTANCE="$1"
SIZE="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG_DIR="$SCRIPT_DIR/.quota-images"
IMG="$IMG_DIR/$INSTANCE.img"
MOUNT_POINT="$SCRIPT_DIR/.volumes/$INSTANCE"

mkdir -p "$IMG_DIR" "$MOUNT_POINT"

if mountpoint -q "$MOUNT_POINT"; then
  echo "Already mounted: $MOUNT_POINT -- nothing to do."
  exit 0
fi

if [ ! -f "$IMG" ]; then
  echo "Creating $SIZE image: $IMG"
  if ! fallocate -l "$SIZE" "$IMG" 2>/dev/null; then
    echo "fallocate unavailable on this filesystem, falling back to dd (slower)..."
    SIZE_MB=$(( $(numfmt --from=iec "$SIZE") / 1024 / 1024 ))
    dd if=/dev/zero of="$IMG" bs=1M count="$SIZE_MB" status=progress
  fi
  echo "Formatting as ext4..."
  mkfs.ext4 -q "$IMG"
else
  echo "Reusing existing image: $IMG"
fi

echo "Mounting $IMG -> $MOUNT_POINT"
mount -o loop "$IMG" "$MOUNT_POINT"

echo "Setting ownership to uid:gid 1000:1000 (the container's 'user' account)"
chown 1000:1000 "$MOUNT_POINT"

echo ""
echo "Done. $MOUNT_POINT is now capped at $SIZE."
df -h "$MOUNT_POINT"
echo ""
echo "To persist across host reboots, add this line to /etc/fstab:"
echo "  $IMG  $MOUNT_POINT  ext4  loop,defaults  0  0"

#!/bin/bash

DEVICE=/dev/mmcblk0
PARTNR=14
ROOTFS_DEV="/dev/disk/by-partlabel/rootfs"
FLAG_FILE="/var/lib/resize-rootfs.done"

# 1. Check marker file
if [ -f "$FLAG_FILE" ]; then
    echo "Marker file exists ($FLAG_FILE), skipping resize."
    exit 0
fi

echo "[1/4] Using parted to expand ${DEVICE}p${PARTNR} to maximum size..."
parted --script ${DEVICE} resizepart ${PARTNR} 100% Yes
echo "[done]"

echo "[2/4] Detecting filesystem type of $ROOTFS_DEV..."
FSTYPE=$(/sbin/blkid -o value -s TYPE "$ROOTFS_DEV")
echo "Detected filesystem type: $FSTYPE"

echo "[3/4] Expanding filesystem..."
case "$FSTYPE" in
    ext4)
        echo "Expanding ext4 filesystem..."
        resize2fs "$ROOTFS_DEV"
        ;;
    btrfs)
        echo "Expanding btrfs filesystem..."
        mountpoint=$(findmnt -n -o TARGET "$ROOTFS_DEV")
        if [[ -z "$mountpoint" ]]; then
            echo "btrfs not mounted, attempting to mount..."
            mount "$ROOTFS_DEV" /mnt
            btrfs filesystem resize max /mnt
            umount /mnt
        else
            btrfs filesystem resize max "$mountpoint"
        fi
        ;;
    *)
        echo "Unsupported filesystem type: $FSTYPE"
        exit 1
        ;;
esac

echo "[4/4] Creating marker file..."
mkdir -p "$(dirname "$FLAG_FILE")"
touch "$FLAG_FILE"

echo "✅ Partition and filesystem resize completed, marker file created at $FLAG_FILE"
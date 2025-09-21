#!/bin/sh
set -e

PART_DEV="/dev/mmcblk0"
PART_NUM="14"
ROOTFS_DEV="/dev/disk/by-partlabel/rootfs"
FLAG_FILE="/var/lib/resize-rootfs.done"

# 1. 检查标记文件
if [ -f "$FLAG_FILE" ]; then
    echo "标记文件已存在 ($FLAG_FILE)，跳过扩容。"
    exit 0
fi

echo "[1/4] 使用 parted 扩展 ${PART_DEV}p${PART_NUM} 到最大..."
parted -s "$PART_DEV" resizepart "$PART_NUM" 100%

echo "[2/4] 检测 $ROOTFS_DEV 文件系统类型..."
FSTYPE=$(blkid -o value -s TYPE "$ROOTFS_DEV")
echo "检测到文件系统类型: $FSTYPE"

echo "[3/4] 扩展文件系统..."
case "$FSTYPE" in
    ext4)
        echo "扩展 ext4 文件系统..."
        e2fsck -f "$ROOTFS_DEV"
        resize2fs "$ROOTFS_DEV"
        ;;
    btrfs)
        echo "扩展 btrfs 文件系统..."
        mountpoint=$(findmnt -n -o TARGET "$ROOTFS_DEV")
        if [ -z "$mountpoint" ]; then
            echo "未挂载 btrfs，尝试挂载..."
            mount "$ROOTFS_DEV" /mnt
            btrfs filesystem resize max /mnt
            umount /mnt
        else
            btrfs filesystem resize max "$mountpoint"
        fi
        ;;
    *)
        echo "不支持的文件系统类型: $FSTYPE"
        exit 1
        ;;
esac

echo "[4/4] 创建标记文件..."
mkdir -p "$(dirname "$FLAG_FILE")"
touch "$FLAG_FILE"

echo "✅ 分区与文件系统扩容完成，并已创建标记文件 $FLAG_FILE"

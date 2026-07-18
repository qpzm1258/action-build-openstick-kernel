#!/bin/bash
# Script to resize rootfs partition and filesystem
# Supports: ext4, btrfs
# Note: f2fs resize is handled by initramfs scripts (offline resize)
# Error handling: set -euo pipefail for strict error checking

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Configuration variables (can be overridden via environment)
readonly DEVICE="${DEVICE:-/dev/mmcblk0}"
readonly PARTNR="${PARTNR:-14}"
readonly ROOTFS_DEV="${ROOTFS_DEV:-/dev/disk/by-partlabel/rootfs}"
readonly FLAG_FILE="${FLAG_FILE:-/var/lib/resize-rootfs.done}"
readonly TEMP_MOUNT="${TEMP_MOUNT:-/tmp/rootfs_mount_$$}"

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

# Cleanup on exit
cleanup() {
    local exit_code=$?
    if [[ -d "$TEMP_MOUNT" ]]; then
        if mountpoint -q "$TEMP_MOUNT" 2>/dev/null; then
            log "Unmounting temporary mount point: $TEMP_MOUNT"
            umount "$TEMP_MOUNT" || warn "Failed to unmount $TEMP_MOUNT"
        fi
        rmdir "$TEMP_MOUNT" || warn "Failed to remove directory $TEMP_MOUNT"
    fi
    return $exit_code
}

trap cleanup EXIT

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

# Check if resize has already been done
check_marker() {
    if [[ -f "$FLAG_FILE" ]]; then
        log "Marker file exists ($FLAG_FILE), skipping resize."
        exit 0
    fi
}

# Verify required commands exist
check_commands() {
    local commands=("parted" "blkid" "findmnt")
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command not found: $cmd"
        fi
    done
}

# Verify device and partition exist
check_device() {
    if [[ ! -e "$DEVICE" ]]; then
        error "Device not found: $DEVICE"
    fi
    
    if [[ ! -e "${DEVICE}p${PARTNR}" ]]; then
        error "Partition not found: ${DEVICE}p${PARTNR}"
    fi
    
    if [[ ! -e "$ROOTFS_DEV" ]]; then
        error "Rootfs device not found: $ROOTFS_DEV"
    fi
}

# Resize partition
resize_partition() {
    log "[1/3] Expanding partition ${DEVICE}p${PARTNR} to maximum size..."
    
    if ! echo "Yes" | parted --align=optimal --pretend-input-tty "$DEVICE" resizepart "$PARTNR" 100% 2>/dev/null; then
        warn "parted failed with --pretend-input-tty, attempting without it"
        echo "Yes" | parted --align=optimal "$DEVICE" resizepart "$PARTNR" 100% || error "Failed to resize partition"
    fi
    
    log "Partition resized successfully"
}

# Detect filesystem type
detect_fstype() {
    log "[2/3] Detecting filesystem type of $ROOTFS_DEV..."
    
    local fstype
    if ! fstype=$(/sbin/blkid -o value -s TYPE "$ROOTFS_DEV" 2>/dev/null); then
        error "Failed to detect filesystem type for $ROOTFS_DEV"
    fi
    
    if [[ -z "$fstype" ]]; then
        error "Could not determine filesystem type for $ROOTFS_DEV"
    fi
    
    log "Detected filesystem type: $fstype"
    echo "$fstype"
}

# Resize ext4 filesystem
resize_ext4() {
    log "Expanding ext4 filesystem..."
    
    if ! resize2fs "$ROOTFS_DEV"; then
        error "Failed to resize ext4 filesystem"
    fi
    
    log "ext4 filesystem resized successfully"
}

# Resize btrfs filesystem
resize_btrfs() {
    log "Expanding btrfs filesystem..."
    
    local mountpoint
    mountpoint=$(findmnt -n -o TARGET "$ROOTFS_DEV" 2>/dev/null || true)
    
    if [[ -z "$mountpoint" ]]; then
        log "btrfs not mounted, attempting to mount..."
        
        mkdir -p "$TEMP_MOUNT"
        if ! mount "$ROOTFS_DEV" "$TEMP_MOUNT"; then
            error "Failed to mount $ROOTFS_DEV"
        fi
        mountpoint="$TEMP_MOUNT"
    fi
    
    if ! btrfs filesystem resize max "$mountpoint"; then
        error "Failed to resize btrfs filesystem"
    fi
    
    log "btrfs filesystem resized successfully"
}

# Resize filesystem based on type
resize_filesystem() {
    local fstype="$1"
    
    log "[3/3] Expanding filesystem..."
    
    case "$fstype" in
        ext4)
            resize_ext4
            ;;
        btrfs)
            resize_btrfs
            ;;
        f2fs)
            warn "f2fs filesystem detected. Online resize is not supported."
            warn "f2fs resize should be handled by initramfs scripts (offline resize)."
            exit 0
            ;;
        *)
            error "Unsupported filesystem type: $fstype"
            ;;
    esac
}

# Create marker file to prevent re-running
create_marker() {
    log "Creating marker file to prevent re-running..."
    
    local marker_dir
    marker_dir=$(dirname "$FLAG_FILE")
    
    if ! mkdir -p "$marker_dir"; then
        warn "Failed to create directory for marker file: $marker_dir"
        return 1
    fi
    
    if ! touch "$FLAG_FILE"; then
        warn "Failed to create marker file: $FLAG_FILE"
        return 1
    fi
    
    log "Marker file created at $FLAG_FILE"
}

# Main function
main() {
    log "Starting rootfs resize process..."
    
    check_root
    check_marker
    check_commands
    check_device
    
    resize_partition
    local fstype
    fstype=$(detect_fstype)
    resize_filesystem "$fstype"
    create_marker
    
    echo -e "${GREEN}✅ Partition and filesystem resize completed successfully${NC}"
}

# Run main function
main "$@"

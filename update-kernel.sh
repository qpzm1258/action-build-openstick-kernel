#!/bin/sh
# Automatically detect the current source version and update to the latest patch level
# Usage: Run ./update-kernel.sh inside the kernel source directory


# Read the current source version (must be executed inside the kernel source directory)
CUR=$(make kernelversion)
echo "Current source version: $CUR"

# Split major and minor version
MAJOR=$(echo $CUR | cut -d. -f1)
MINOR=$(echo $CUR | cut -d. -f2)
SUBLEVEL=$(echo $CUR | cut -d. -f3)

# Extract only the mainline version (e.g. 6.12.1 -> 6.12)
VERSION="$MAJOR.$MINOR"

BASE_URL="https://cdn.kernel.org/pub/linux/kernel/v$MAJOR.x"

# Get the latest patch version
LATEST=$(curl -s https://www.kernel.org/ \
    | grep -o "linux-$VERSION\.[0-9]\+\.tar" \
    | sed "s/linux-$VERSION\.//;s/\.tar//" \
    | sort -n | tail -1)

if [ -z "$LATEST" ]; then
    echo "No latest patch found for $VERSION"
    exit 0
fi

echo "Latest version: $VERSION.$LATEST"

# Exit if the current version is already the latest
CUR_PATCH=$(echo $CUR | cut -d. -f3)
if [ "$CUR_PATCH" = "$LATEST" ]; then
    echo "Current version is already the latest ($CUR)"
    exit 0
fi

if [ "${SUBLEVEL:-0}" -ne 0 ]; then
    echo "Revert patch to mainline"
    wget -c "$BASE_URL/patch-$VERSION.$SUBLEVEL.xz"
    unxz -f "patch-$VERSION.$SUBLEVEL.xz"
    patch -p1 -R < "patch-$VERSION.$SUBLEVEL"
fi

# Download patch
PATCH="patch-$VERSION.$LATEST.xz"
URL="$BASE_URL/$PATCH"

echo "Downloading $URL ..."
wget -c "$URL"

# Decompress patch
unxz -f "$PATCH"

# Apply patch
PATCHFILE="${PATCH%.xz}"
echo "Applying patch $PATCHFILE ..."
patch -p1 --batch < "$PATCHFILE"

echo "Done: Updated to Linux $VERSION.$LATEST"

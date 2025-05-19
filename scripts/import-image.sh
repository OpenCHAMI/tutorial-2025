#!/bin/bash
set -euo pipefail

### Documentation
# This script is used to convert a system image stored in an OCI registry for use to boot HPC nodes.
# 1. Pull the container image using podman
# 2. Mount the container image
# 3. Copy the kernel and initramfs
# 4. Create a squashfs image of the root filesystem
# 5. Unmount the container image
# Usage: image-import.sh <container-image> <output-dir>


# Flag to detect if we're already in the unshare environment
if [ "${PODMAN_UNSHARE:-}" != "1" ]; then
    # Check if unshare is necessary
    if ! podman image mount busybox &>/dev/null; then
        echo "Entering podman unshare environment..."
        export PODMAN_UNSHARE=1
        exec podman unshare bash "$0" "$@"
    else
        podman image unmount busybox &>/dev/null
    fi
fi

# Main script logic
# Check if an argument is provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <container-image> <output-dir>"
    exit 1
fi
IMAGE="$1"
OUTPUT_DIR="$2"
REPLACE="false"

if [ "$#" -eq 3 ]; then
    if [ "$3" = "--replace" ]; then
        REPLACE="true"
    else
        echo "Unknown flag: $3"
        echo "Usage: $0 <container-image> <output-dir> [--replace]"
        exit 1
    fi
fi

# Verify that the output directory exists and is empty
if [ -d "$OUTPUT_DIR" ]; then
    if [ -n "$(ls -A "$OUTPUT_DIR")" ]; then
        if [ "$REPLACE" = "true" ]; then
            echo "Replacing existing files in '$OUTPUT_DIR'"
            rm -rf "$OUTPUT_DIR/*"
        else
            echo "Output directory '$OUTPUT_DIR' is not empty"
            echo "Use the --replace flag to overwrite existing files."
            echo "Usage: $0 <container-image> <output-dir> [--replace]"
            exit 1
        fi
    fi
else
    mkdir -p "$OUTPUT_DIR"
fi

# Pull the container image
podman pull --tls-verify=false $IMAGE

# Mount the container image
MNAME=$(podman image mount "$IMAGE")

# Set the kernel version
KVER=$(ls "$MNAME/lib/modules" | sort -V | head -n 1)

# Copy kernel and initramfs
cp "$MNAME/boot/initramfs-$KVER.img" "$OUTPUT_DIR"
chmod o+r "$OUTPUT_DIR/initramfs-$KVER.img"
cp "$MNAME/boot/vmlinuz-$KVER" "$OUTPUT_DIR"

# Create squashfs
mksquashfs "$MNAME" "$OUTPUT_DIR/rootfs-$KVER.squashfs" -noappend -no-progress -no-exports -comp lzo -b 512K -no-fragments -no-xattrs

# Cleanup
podman image unmount "$IMAGE"
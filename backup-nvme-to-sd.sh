#!/bin/bash

# This script performs a full backup from NVMe SSD to SD card on a Raspberry Pi 5.
# It mirrors the boot and root partitions using rsync with --delete for a true backup.
# WARNING: This will overwrite the contents of the SD card!

# Check for --yes or -y flag
AUTO_CONFIRM=false
for arg in "$@"; do
    [[ "$arg" == "--yes" || "$arg" == "-y" ]] && AUTO_CONFIRM=true
done

# Check if we are booted from NVMe root filesystem
CURRENT_ROOT=$(findmnt -n -o SOURCE /)
echo "Current root device: $CURRENT_ROOT"

if [[ "$CURRENT_ROOT" != /dev/nvme* ]]; then
    echo "This script can only be run when booted from NVMe. Current root is: $CURRENT_ROOT"
    exit 1
fi

# Confirm before continuing
if ! $AUTO_CONFIRM; then
    read -p "WARNING: This will completely overwrite the contents of the SD card with the current NVMe system. Continue? (y/n): " confirm < /dev/tty
    if [[ "${confirm,,}" != "y" ]]; then
        echo "Aborted."
        exit 1
    fi
else
    echo "--yes flag detected, proceeding without prompt..."
fi

# Define devices (change these if needed)
SD_BOOT=/dev/mmcblk0p1
SD_ROOT=/dev/mmcblk0p2
NVME_BOOT=/dev/nvme0n1p1
NVME_ROOT=/dev/nvme0n1p2

# Mount SD card partitions
sudo mkdir -p /mnt/sd-boot /mnt/sd-root
sudo mount $SD_BOOT /mnt/sd-boot
sudo mount $SD_ROOT /mnt/sd-root

# Rsync NVMe → SD card with identical progress display
echo "Backing up root filesystem..."
sudo rsync -aAXvh --delete --info=progress2 \
    --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
    / /mnt/sd-root/

echo "Backing up boot partition..."
sudo rsync -aAXvh --delete --info=progress2 /boot/firmware/ /mnt/sd-boot/

# Get updated PARTUUIDs for the SD card
BOOT_PARTUUID=$(blkid -s PARTUUID -o value $SD_BOOT)
ROOT_PARTUUID=$(blkid -s PARTUUID -o value $SD_ROOT)

echo "SD Boot PARTUUID: $BOOT_PARTUUID"
echo "SD Root PARTUUID: $ROOT_PARTUUID"

# Backup and update config files
sudo cp /mnt/sd-boot/cmdline.txt /mnt/sd-boot/cmdline.txt.bak
sudo cp /mnt/sd-root/etc/fstab /mnt/sd-root/etc/fstab.bak

sudo sed -i "s|root=PARTUUID=[^ ]*|root=PARTUUID=$ROOT_PARTUUID|" /mnt/sd-boot/cmdline.txt
sudo sed -i "s|PARTUUID=[^ ]*  /boot/firmware  vfat|PARTUUID=$BOOT_PARTUUID  /boot/firmware  vfat|" /mnt/sd-root/etc/fstab
sudo sed -i "s|PARTUUID=[^ ]*  /               ext4|PARTUUID=$ROOT_PARTUUID  /               ext4|" /mnt/sd-root/etc/fstab

# Unmount SD card
sudo umount /mnt/sd-boot /mnt/sd-root
sudo rmdir /mnt/sd-boot /mnt/sd-root

echo "Backup complete. SD card now contains a bootable copy of the NVMe system."

# Self-delete the script
SCRIPT_PATH="$(realpath "$0")"
if [[ -f "$SCRIPT_PATH" ]]; then
    echo "Deleting script: $SCRIPT_PATH"
    rm -f "$SCRIPT_PATH"
fi

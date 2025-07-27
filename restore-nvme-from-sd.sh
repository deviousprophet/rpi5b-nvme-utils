#!/bin/bash

# This script performs a full restoration from SD card to NVMe SSD on a Raspberry Pi 5.
# It mirrors the boot and root partitions using rsync with --delete for a true restoration.
# WARNING: This will overwrite the contents of the NVMe SSD!

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
    read -p "WARNING: This will completely overwrite the contents of / and /boot/firmware from the SD card. Continue? (y/n): " confirm < /dev/tty
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
sudo mkdir -p /mnt/sd-boot
sudo mkdir -p /mnt/sd-root
sudo mount $SD_BOOT /mnt/sd-boot
sudo mount $SD_ROOT /mnt/sd-root

# OPTIONAL: Format NVMe partitions (uncomment if needed)
# echo "Formatting NVMe partitions..."
# sudo mkfs.vfat -F32 $NVME_BOOT
# sudo mkfs.ext4 $NVME_ROOT

# Mount NVMe partitions (assuming they are already mounted by the system)
# If not mounted, you may mount them manually here (optional step)

# Rsync SD card contents to NVMe (true mirror)
echo "Restoring root filesystem..."
sudo rsync -aAXv --delete --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} /mnt/sd-root/ /

echo "Restoring boot partition..."
sudo rsync -aAXv --delete /mnt/sd-boot/ /boot/firmware/

# Get updated PARTUUIDs
BOOT_PARTUUID=$(blkid -s PARTUUID -o value $NVME_BOOT)
ROOT_PARTUUID=$(blkid -s PARTUUID -o value $NVME_ROOT)

# Show found PARTUUIDs
echo "Boot PARTUUID: $BOOT_PARTUUID"
echo "Root PARTUUID: $ROOT_PARTUUID"

# Backup existing config files
sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.bak
sudo cp /etc/fstab /etc/fstab.bak

# Update cmdline.txt
echo "Updating cmdline.txt..."
sudo sed -i "s|root=PARTUUID=[^ ]*|root=PARTUUID=$ROOT_PARTUUID|" /boot/firmware/cmdline.txt

# Update fstab
echo "Updating fstab..."
sudo sed -i "s|PARTUUID=[^ ]*  /boot/firmware  vfat|PARTUUID=$BOOT_PARTUUID  /boot/firmware  vfat|" /etc/fstab
sudo sed -i "s|PARTUUID=[^ ]*  /               ext4|PARTUUID=$ROOT_PARTUUID  /               ext4|" /etc/fstab

# Unmount SD card
sudo umount /mnt/sd-boot
sudo umount /mnt/sd-root
sudo rmdir /mnt/sd-boot
sudo rmdir /mnt/sd-root

# Show updated files for verification
echo "Updated cmdline.txt:"
sudo cat /boot/firmware/cmdline.txt

echo "Updated fstab:"
sudo cat /etc/fstab

# Prompt for reboot (if not auto-confirmed)
if $AUTO_CONFIRM; then
    REBOOT=true
else
    read -p "Restore complete. A reboot is required to apply changes. Reboot now? (y/n): " reboot_confirm < /dev/tty
    if [[ "${reboot_confirm,,}" == "y" ]]; then
        REBOOT=true
    else
        REBOOT=false
        echo "Reboot skipped. Please remember to reboot later to apply the changes."
    fi
fi

# Self-delete the script before rebooting or exiting
SCRIPT_PATH="$(realpath "$0")"
if [[ -f "$SCRIPT_PATH" ]]; then
    echo "Deleting script: $SCRIPT_PATH"
    rm -f "$SCRIPT_PATH"
fi

# Reboot if confirmed or auto-approved
if [[ "$REBOOT" == true ]]; then
    sudo reboot
else
    echo "Reboot skipped. Please remember to reboot later to apply the changes."
fi

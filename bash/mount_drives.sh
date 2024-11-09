#!/bin/bash

# Find unmounted drives
UNMOUNTED_DRIVE=$(lsblk -ln -o NAME,MOUNTPOINT | awk '$2 == "" && $1 != "sda" {print $1}')

if [ -z "$UNMOUNTED_DRIVE" ]; then
    echo "No unmounted drives found."
    exit 1
fi

# Determine mount point suffix
MOUNT_INDEX=0
while [ -d "/mnt/data$MOUNT_INDEX" ]; do
    MOUNT_INDEX=$((MOUNT_INDEX + 1))
done

# Mount the unmounted drive to /mnt/data
if [ $MOUNT_INDEX -eq 0 ]; then
    MOUNT_POINT="/mnt/data"
else
    MOUNT_POINT="/mnt/data$MOUNT_INDEX"
fi
DRIVE="/dev/$UNMOUNTED_DRIVE"

# Create mount point directory if it doesn't exist
if [ ! -d "$MOUNT_POINT" ]; then
    sudo mkdir -p "$MOUNT_POINT"
fi

# Confirm drive before formatting
lsblk
read -p "Is $DRIVE the correct drive to mount? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Aborting operation."
    exit 1
fi

# Format the drive if it is not formatted
if [ -z "$(blkid $DRIVE)" ]; then
    echo "Formatting drive $DRIVE with ext4 filesystem..."
    sudo mkfs.ext4 "$DRIVE"
fi

# Mount the drive
sudo mount "$DRIVE" "$MOUNT_POINT" || { echo "Failed to mount the drive."; exit 1; }

# Get UUID of the drive
UUID=$(blkid -s UUID -o value "$DRIVE")

# Add to /etc/fstab if not already present
if ! grep -qs "$UUID" /etc/fstab; then
    echo "Adding $DRIVE to /etc/fstab..."
    echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 2" | sudo tee -a /etc/fstab
fi

echo "Drive $DRIVE successfully mounted to $MOUNT_POINT and added to /etc/fstab."

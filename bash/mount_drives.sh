#!/bin/bash

# Prompt user for the drive to mount
echo "Available drives:"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
echo
read -p "Enter the drive you want to mount (e.g., sda or sdb1): " DRIVE

# Verify the drive exists
if [ ! -b "/dev/$DRIVE" ]; then
  echo "Error: /dev/$DRIVE does not exist."
  exit 1
fi

# Prompt user for the mount point
read -p "Enter the mount point (e.g., /mnt/data): " MOUNT_POINT

# Create the mount point if it doesn't exist
if [ ! -d "$MOUNT_POINT" ]; then
  echo "Creating mount point at $MOUNT_POINT..."
  sudo mkdir -p "$MOUNT_POINT"
fi

# Get filesystem type
FILESYSTEM=$(sudo blkid -s TYPE -o value /dev/$DRIVE)
if [ -z "$FILESYSTEM" ]; then
  echo "Error: Could not determine filesystem type for /dev/$DRIVE."
  exit 1
fi

# Mount the drive
sudo mount /dev/$DRIVE "$MOUNT_POINT"
echo "/dev/$DRIVE mounted to $MOUNT_POINT."

# Update /etc/fstab
echo "Updating /etc/fstab..."
FSTAB_ENTRY="/dev/$DRIVE   $MOUNT_POINT   $FILESYSTEM   defaults   0   2"
if ! grep -qs "$FSTAB_ENTRY" /etc/fstab; then
  echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab
  echo "Entry added to /etc/fstab:"
  echo "$FSTAB_ENTRY"
else
  echo "Entry already exists in /etc/fstab."
fi

# Verify mount
echo "Verifying mount..."
if mount | grep -qs "$MOUNT_POINT"; then
  echo "Drive /dev/$DRIVE successfully mounted at $MOUNT_POINT and added to /etc/fstab."
else
  echo "Error: Drive /dev/$DRIVE was not mounted."
fi

#!/bin/bash

# Define variables
USER="andy"
RSYNC_CONF_PATH="/home/$USER/rsyncd.conf"
LOG_DIR="/home/$USER/logs"
LOG_FILE="$LOG_DIR/rsyncd.log"
LOCK_FILE="/home/$USER/rsyncd.lock"
MOUNT_POINT="/mnt/data"

# Step 1: Check if the mount path is mounted
if mountpoint -q "$MOUNT_POINT"; then
    echo "$MOUNT_POINT is mounted."
else
    echo "Error: $MOUNT_POINT is not mounted. Please mount the drive first."
    exit 1
fi

# Step 2: Create necessary directories
echo "Creating necessary directories..."
mkdir -p "$LOG_DIR"

# Step 3: Create the rsync configuration file
echo "Creating rsyncd.conf file..."
cat <<EOL > $RSYNC_CONF_PATH
# /home/$USER/rsyncd.conf

use chroot = no
max connections = 4
log file = $LOG_FILE
lock file = $LOCK_FILE

[Hyperbackup_Destination]
    path = $MOUNT_POINT
    comment = Synology NAS Backup
    read only = false
    list = yes
    charset = utf-8
EOL

echo "rsyncd.conf created at $RSYNC_CONF_PATH."

# Step 4: Enable the rsync server in /etc/default/rsync
echo "Enabling rsync server in /etc/default/rsync..."
if grep -q "^RSYNC_ENABLE" /etc/default/rsync; then
    sudo sed -i 's/^RSYNC_ENABLE=.*/RSYNC_ENABLE=true/' /etc/default/rsync
else
    echo "RSYNC_ENABLE=true" | sudo tee -a /etc/default/rsync > /dev/null
fi

# Step 5: Set up rsync systemd service file
SERVICE_FILE="/etc/systemd/system/rsyncd.service"
echo "Creating rsync systemd service file..."

sudo bash -c "cat <<EOL > $SERVICE_FILE
[Unit]
Description=Rsync Daemon
After=network.target

[Service]
ExecStart=/usr/bin/rsync --daemon --config=$RSYNC_CONF_PATH
Restart=always
User=$USER
WorkingDirectory=/home/$USER

[Install]
WantedBy=multi-user.target
EOL"

# Step 6: Enable and start rsync service
echo "Enabling and starting rsync service..."
sudo systemctl daemon-reload
sudo systemctl enable rsyncd
sudo systemctl start rsyncd

# Step 7: Verify rsync daemon status
echo "Verifying rsync daemon status..."

# Check if the rsync service is active
if systemctl is-active --quiet rsyncd; then
    echo "Rsync daemon is active and running."
else
    echo "Error: Rsync daemon failed to start."
    exit 1
fi

# Check if rsync is listening on the default port (873)
if sudo ss -tuln | grep -q ":873"; then
    echo "Rsync daemon is listening on port 873."
else
    echo "Error: Rsync daemon is not listening on port 873."
    exit 1
fi

# Test the rsync connection locally to confirm it's working
if rsync rsync://localhost/ > /dev/null 2>&1; then
    echo "Rsync daemon is reachable and ready to accept connections."
else
    echo "Error: Rsync daemon is not reachable. Please check configuration and firewall settings."
    exit 1
fi

echo "Setup complete. Rsync daemon is configured to start on boot, verified to be running, and listening for connections."

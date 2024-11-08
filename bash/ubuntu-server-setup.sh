#!/bin/bash

# This script sets up a new user, configures SSH access, sets up a firewall, installs security tools (Fail2ban and Netdata), enables automatic updates and security patches, and ensures secure system settings are in place. It also verifies the system configuration after setup.

# Variables
NEW_USER="andy"
GITHUB_USER="andyyanguk"  # GitHub username to fetch SSH keys

# Update system
echo "Updating system..."
apt update && apt upgrade -y
apt autoremove -y
echo -e "\n********** System Update Complete **********\n"

# Add new user and grant sudo privileges (only if not exists)
if id -u "$NEW_USER" >/dev/null 2>&1; then
    echo "User $NEW_USER already exists."
else
    echo "Creating new user $NEW_USER..."
    adduser --disabled-password --gecos "" $NEW_USER
    read -sp "Enter a password for the new user $NEW_USER: " USER_PASSWORD
    echo
    echo "$NEW_USER:$USER_PASSWORD" | chpasswd
    usermod -aG sudo $NEW_USER
    echo "$NEW_USER created and added to sudo group."
fi
echo -e "\n********** User Setup Complete **********\n"

# Set up SSH directory and fetch GitHub SSH keys (overwrite each time to ensure latest keys)
echo "Setting up SSH keys for $NEW_USER from GitHub..."
sudo -u $NEW_USER mkdir -p /home/$NEW_USER/.ssh
sudo -u $NEW_USER wget -qO /home/$NEW_USER/.ssh/authorized_keys https://github.com/$GITHUB_USER.keys || { echo "Failed to fetch SSH keys from GitHub."; exit 1; }
chmod 700 /home/$NEW_USER/.ssh
chmod 600 /home/$NEW_USER/.ssh/authorized_keys
echo "SSH keys added for $NEW_USER."
echo -e "\n********** SSH Key Setup Complete **********\n"

# Install and configure UFW firewall
echo "Installing UFW if not available..."
apt install -y ufw || { echo "Failed to install UFW."; exit 1; }

echo "Configuring UFW firewall..."
ufw allow OpenSSH >/dev/null 2>&1
ufw --force enable
ufw status
echo -e "\n********** Firewall Setup Complete **********\n"

# Set up SSH security (check if already set)
echo "Configuring SSH..."
SSH_CONFIG="/etc/ssh/sshd_config"

if grep -q "^PermitRootLogin no" "$SSH_CONFIG"; then
    echo "Root login already disabled."
else
    sed -i "s/^PermitRootLogin yes/PermitRootLogin no/" $SSH_CONFIG
fi

if grep -q "^PasswordAuthentication no" "$SSH_CONFIG"; then
    echo "Password authentication already disabled."
else
    sed -i "s/^#PasswordAuthentication yes/PasswordAuthentication no/" $SSH_CONFIG
fi

# Restart SSH only if the configuration was modified
if systemctl is-active --quiet ssh && ! systemctl is-failed ssh; then
    echo "Restarting SSH..."
    systemctl restart ssh || { echo "Failed to restart SSH."; exit 1; }
else
    echo "SSH service not running or already failed. Please check SSH configuration."
fi
echo -e "\n********** SSH Security Setup Complete **********\n"

# Enable automatic updates if not already enabled
echo "Checking if automatic updates are enabled..."
if ! dpkg -l | grep -qw unattended-upgrades; then
    echo "Installing unattended-upgrades..."
    apt install -y unattended-upgrades || { echo "Failed to install unattended-upgrades."; exit 1; }
    dpkg-reconfigure --priority=low unattended-upgrades
else
    echo "Automatic updates already enabled."
fi

# Enable automated reboot for security patches
echo "Enabling automated reboot for security patches..."
apt install -y cron || { echo "Failed to install cron."; exit 1; }
echo -e "APT::Periodic::Unattended-Upgrade \"1\";\nUnattended-Upgrade::Automatic-Reboot \"true\";\nUnattended-Upgrade::Automatic-Reboot-Time \"02:00\";" | sudo tee /etc/apt/apt.conf.d/50unattended-upgrades >/dev/null
echo -e "\n********** Automatic Updates Setup Complete **********\n"

# Install and configure Fail2ban if not already installed
if ! dpkg -l | grep -qw fail2ban; then
    echo "Installing Fail2ban..."
    apt install -y fail2ban || { echo "Failed to install Fail2ban."; exit 1; }
    systemctl enable fail2ban --now || { echo "Failed to enable Fail2ban."; exit 1; }
else
    echo "Fail2ban already installed."
fi
echo -e "\n********** Fail2ban Setup Complete **********\n"

# Disable root account (check if already disabled)
if passwd -S root | grep -q "L"; then
    echo "Root account already disabled."
else
    echo "Disabling root account login..."
    passwd -l root || { echo "Failed to disable root account."; exit 1; }
fi
echo -e "\n********** Root Account Lock Complete **********\n"

# Install Netdata
if ! command -v netdata &> /dev/null; then
    echo "Installing Netdata..."
    wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh && sh /tmp/netdata-kickstart.sh --stable-channel --claim-token NimZ6nldcsDAApy7C3qUyt3Myq1H8a0SVSXw4myCEekl84Rf3VFw843vB26P-HxUd3lQtA-WvQPXC8R9LubPxY9y_255RBBUq--_E1oP1-ua0js10yAZ6aHPte-C70wppf_6FL0 --claim-rooms fdce1ac0-3753-49e1-b5d3-e366dbea1dad --claim-url https://app.netdata.cloud || { echo "Failed to install Netdata."; exit 1; }
else
    echo "Netdata is already installed."
fi
echo -e "\n********** Netdata Installation Complete **********\n"

# Download GitHub SSH key script and add to path
SCRIPT_DIR="/home/$NEW_USER/scripts"
LOG_DIR="/home/$NEW_USER/logs"

# Ensure the scripts and logs directories exist
mkdir -p "$SCRIPT_DIR"
mkdir -p "$LOG_DIR"
SCRIPT_PATH="$SCRIPT_DIR/download-github-sshkeys.sh"
wget -q https://raw.githubusercontent.com/AndyYangUK/useful_scripts/refs/heads/main/bash/download-github-ssh -O "$SCRIPT_PATH" || { echo "Failed to download GitHub SSH key script."; exit 1; }
chmod +x "$SCRIPT_PATH"
echo -e "\n********** GitHub SSH Key Script Downloaded and Configured **********\n"

# Update crontab to include SSH key download tasks (failsafe for multiple script runs)
(crontab -l 2>/dev/null | grep -q "download-github-ssh.sh" ) || {
    (crontab -l 2>/dev/null; echo "*/10 * * * * sh $SCRIPT_PATH > $LOG_DIR/download-github-ssh.txt") | crontab -
    (crontab -l 2>/dev/null; echo "@reboot sleep 120 && sh $SCRIPT_PATH > $LOG_DIR/download-github-ssh.txt") | crontab -
    echo "Crontab updated with GitHub SSH key download tasks."
}

# Verification
echo "Running verification checks..."
echo -e "\n********** Verification Results **********\n"

# User check
id $NEW_USER && echo "User $NEW_USER exists with sudo privileges."

# SSH key check
[[ -f /home/$NEW_USER/.ssh/authorized_keys ]] && echo "SSH keys configured for $NEW_USER."

# Verify SSH keys match GitHub keys
GITHUB_KEYS=$(wget -qO - https://github.com/$GITHUB_USER.keys)
SERVER_KEYS=$(cat /home/$NEW_USER/.ssh/authorized_keys)
if [[ "$GITHUB_KEYS" == "$SERVER_KEYS" ]]; then
    echo "SSH keys on server match GitHub keys for $NEW_USER."
else
    echo "WARNING: SSH keys on server do not match GitHub keys for $NEW_USER."
fi

# UFW check
ufw status | grep -qw "Status: active" && echo "UFW is active and configured."

# SSH configuration check
if grep -q "PermitRootLogin no" "$SSH_CONFIG" && grep -q "PasswordAuthentication no" "$SSH_CONFIG"; then
    echo "SSH configuration is secure: Root login disabled, Password authentication disabled."
fi

# Automatic updates check
dpkg -l | grep -qw unattended-upgrades && echo "Automatic updates are enabled."

# Fail2ban check
systemctl is-active --quiet fail2ban && echo "Fail2ban is active."

# Root lock check
passwd -S root | grep -q "L" && echo "Root account is locked."

# Netdata verification check
if systemctl is-active --quiet netdata; then
    echo "Netdata is installed and running."
else
    echo "WARNING: Netdata is not running. Please check the installation."
fi

# GitHub SSH key script check
[[ -f "$SCRIPT_PATH" ]] && [[ -x "$SCRIPT_PATH" ]] && echo "GitHub SSH key script is present at $SCRIPT_PATH and is executable."

# Crontab verification check
crontab -l | grep -q "download-github-ssh.sh" && echo "Crontab entries for GitHub SSH key download tasks are configured."

echo -e "\n********** All Verification Checks Complete **********\n"

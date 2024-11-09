#!/bin/bash

# To download this script from GitHub and run it:
# wget -q https://raw.githubusercontent.com/AndyYangUK/useful_scripts/refs/heads/main/bash/ubuntu-server-setup.sh -O ubuntu-server-setup.sh && sudo bash ubuntu-server-setup.sh

# Variables
NEW_USER="andy"
GITHUB_USER="andyyanguk"  # GitHub username to fetch SSH keys

# Prompt for any required input at the start
read -p "Enter the Zerotier network ID: " ZEROTIER_NETWORK_ID
echo
read -sp "Enter a password for the new user $NEW_USER: " USER_PASSWORD
echo
read -sp "Enter your Netdata claim token: " NETDATA_CLAIM_TOKEN
echo
read -p "Enter your Netdata claim room ID: " NETDATA_CLAIM_ROOMS

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
    echo "$NEW_USER:$USER_PASSWORD" | chpasswd
    usermod -aG sudo $NEW_USER
    echo "$NEW_USER created and added to sudo group."
fi
echo -e "\n********** User Setup Complete **********\n"

# Install Zerotier and join network
if command -v zerotier-cli &> /dev/null && zerotier-cli info >/dev/null 2>&1; then
    echo "Zerotier is already installed and active."
else
    echo "Installing Zerotier..."
    curl -s https://install.zerotier.com | sudo bash || { echo "Failed to install Zerotier."; exit 1; }
    echo "Joining Zerotier network $ZEROTIER_NETWORK_ID..."
    zerotier-cli join $ZEROTIER_NETWORK_ID || { echo "Failed to join Zerotier network."; exit 1; }
    while true; do
        read -p "Have you accepted this server on the Zerotier portal? (y/n): " yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) echo "Please accept the server on the Zerotier portal to proceed.";;
            * ) echo "Please answer yes or no.";;
        esac
    done
fi
echo -e "\n********** Zerotier Installation and Network Join Complete **********\n"

# Download GitHub SSH key script and add to path
SCRIPT_DIR="/home/$NEW_USER/scripts"
LOG_DIR="/home/$NEW_USER/logs"

# Ensure the scripts and logs directories exist
mkdir -p "$SCRIPT_DIR"
chown $NEW_USER:$NEW_USER "$SCRIPT_DIR"
mkdir -p "$LOG_DIR"
chown $NEW_USER:$NEW_USER "$LOG_DIR"
SCRIPT_PATH="$SCRIPT_DIR/download-github-sshkeys.sh"
wget -q https://raw.githubusercontent.com/AndyYangUK/useful_scripts/refs/heads/main/bash/download-github-ssh.sh -O "$SCRIPT_PATH" || { echo "Failed to download GitHub SSH key script."; exit 1; }
chmod +x "$SCRIPT_PATH"
echo -e "\n********** GitHub SSH Key Script Downloaded and Configured **********\n"

# Update crontab to include SSH key download tasks 
(crontab -l 2>/dev/null | grep -q "download-github-sshkeys.sh") || {
    (crontab -l 2>/dev/null; echo "*/10 * * * * sh $SCRIPT_PATH > $LOG_DIR/download-github-ssh.txt"; echo "@reboot sleep 120 && sh $SCRIPT_PATH > $LOG_DIR/download-github-ssh.txt") | crontab -
    echo "Crontab updated with GitHub SSH key download tasks."
}

# Run the GitHub SSH key script
echo "Running GitHub SSH key script to ensure latest SSH keys are active..."
sudo -u $NEW_USER sh $SCRIPT_PATH || { echo "Failed to run GitHub SSH key script."; exit 1; }
echo -e "\n********** GitHub SSH Key Script Run Complete **********\n"

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

# Install and configure UFW firewall
echo "Installing UFW if not available..."
apt install -y ufw || { echo "Failed to install UFW."; exit 1; }

echo "Configuring UFW firewall..."
ufw allow OpenSSH >/dev/null 2>&1
ufw --force enable
ufw status
echo -e "\n********** Firewall Setup Complete **********\n"

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

# Restart SSH only if the configuration was modified
if systemctl is-active --quiet ssh && ! systemctl is-failed ssh; then
    echo "Restarting SSH..."
    systemctl restart ssh || { echo "Failed to restart SSH."; exit 1; }
else
    echo "SSH service not running or already failed. Please check SSH configuration."
fi
echo -e "\n********** SSH Security Setup Complete **********\n"

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
crontab -l | grep -q "download-github-sshkeys.sh" && echo "Crontab entries for GitHub SSH key download tasks are configured."

echo -e "\n********** All Verification Checks Complete **********\n"

#!/bin/bash

# To download this script from GitHub and run it:
# wget -q https://raw.githubusercontent.com/AndyYangUK/useful_scripts/refs/heads/main/bash/ubuntu-server-setup.sh -O ubuntu-server-setup.sh && bash ubuntu-server-setup.sh

# Ensure required tools are installed
apt update
apt install -y curl sudo

# Load environment variables from .env file if it exists
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Variables
if [ -z "$NEW_USER" ]; then
  read -p "Enter the new username to be created: " NEW_USER
  echo "NEW_USER=$NEW_USER" >> .env
fi

if [ -z "$USER_PASSWORD" ]; then
  read -sp "Enter a password for the new user $NEW_USER: " USER_PASSWORD
  echo
  echo "USER_PASSWORD=$USER_PASSWORD" >> .env
fi

if [ -z "$GITHUB_USER" ]; then
  read -p "Enter your GitHub username (for SSH keys): " GITHUB_USER
  echo "GITHUB_USER=$GITHUB_USER" >> .env
fi

# Prompt for any required input at the start
if [ -z "$ZEROTIER_NETWORK_ID" ]; then
  read -p "Enter the Zerotier network ID: " ZEROTIER_NETWORK_ID
  echo "ZEROTIER_NETWORK_ID=$ZEROTIER_NETWORK_ID" >> .env
fi
echo

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

# Update system
echo "Updating system..."
apt update && apt upgrade -y
apt autoremove -y
echo -e "\n********** System Update Complete **********\n"

# Install Zerotier and join network
if command -v zerotier-cli &> /dev/null && zerotier-cli info >/dev/null 2>&1; then
    echo "Zerotier is already installed and active."
else
    echo "Installing Zerotier..."
    curl -s https://install.zerotier.com | bash || { echo "Failed to install Zerotier."; exit 1; }
    echo "Joining Zerotier network $ZEROTIER_NETWORK_ID..."
    zerotier-cli join $ZEROTIER_NETWORK_ID || { echo "Failed to join Zerotier network."; exit 1; }
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
curl -s https://raw.githubusercontent.com/AndyYangUK/useful_scripts/refs/heads/main/bash/download-github-ssh.sh -o "$SCRIPT_PATH" || { echo "Failed to download GitHub SSH key script."; exit 1; }
chmod +x "$SCRIPT_PATH"
echo -e "\n********** GitHub SSH Key Script Downloaded and Configured **********\n"

# Update crontab to include SSH key download tasks
(crontab -l 2>/dev/null | grep -q "download-github-sshkeys.sh") || {
    (crontab -l 2>/dev/null; echo "*/10 * * * * bash $SCRIPT_PATH >> $LOG_DIR/download-github-ssh.txt 2>&1"; echo "@reboot sleep 120 && sh $SCRIPT_PATH >> $LOG_DIR/download-github-ssh.txt 2>&1") | crontab -
    echo "Crontab updated with GitHub SSH key download tasks."
}

# Run the GitHub SSH key script
echo "Running GitHub SSH key script to ensure latest SSH keys are active..."
su -c "sh $SCRIPT_PATH" -s /bin/bash $NEW_USER || { echo "Failed to run GitHub SSH key script."; exit 1; }
echo -e "\n********** GitHub SSH Key Script Run Complete **********\n"

# Set up SSH security (check if already set)
echo "Configuring SSH..."
SSH_CONFIG="/etc/ssh/sshd_config"

sed -i "s/^#*PermitRootLogin .*/PermitRootLogin no/" "$SSH_CONFIG"

sed -i "s/^#*PasswordAuthentication .*/PasswordAuthentication no/" "$SSH_CONFIG"

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
echo -e "APT::Periodic::Unattended-Upgrade \"1\";\nUnattended-Upgrade::Automatic-Reboot \"true\";\nUnattended-Upgrade::Automatic-Reboot-Time \"02:00\";" | tee /etc/apt/apt.conf.d/50unattended-upgrades >/dev/null
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
    echo "Testing SSH configuration..."
    sshd -t && systemctl restart ssh || { echo "Failed to restart SSH."; exit 1; }
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
GITHUB_KEYS=$(curl -s https://github.com/$GITHUB_USER.keys | sort)
SERVER_KEYS=$(sort /home/$NEW_USER/.ssh/authorized_keys)
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

# Automatic reboot for security patches check
if grep -q 'Unattended-Upgrade::Automatic-Reboot "true";' /etc/apt/apt.conf.d/50unattended-upgrades; then
    echo "Automatic reboot for security patches is enabled."
else
    echo "WARNING: Automatic reboot for security patches is not enabled."
fi

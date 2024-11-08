#!/bin/bash

# Set variables
github_username="andyyanguk"
zerotier_network="UPDATE_ID_HERE"
user_name="andy"

# Logging
log_file="/var/log/vps_setup.log"
exec > >(tee -a ${log_file} )
exec 2>&1

echo "********************"
echo "Updating Server"
echo "********************"

# 1. Update package list and install required tools
apt update
apt install -y curl ufw wget

echo "********************"
echo "Setting Timezone"
echo "********************"

# 2. Set server timezone to Europe/London
timedatectl set-timezone Europe/London

echo "********************"
echo "Installing ZeroTier"
echo "********************"

# 3. Install ZeroTier
if ! command -v zerotier-cli &> /dev/null; then
    curl -s https://install.zerotier.com | sudo bash
else
    echo "ZeroTier is already installed. Skipping installation."
fi

# Check if already joined ZeroTier network
if zerotier-cli info | grep -q '200 info'; then
    echo "Already joined ZeroTier network. Skipping join process."
else
    # Join the ZeroTier network
    sudo zerotier-cli join ${zerotier_network}
fi

echo "********************"
echo "Upgrading Packages"
echo "********************"

# 4. Upgrade installed packages
apt upgrade -y

echo "********************"
echo "Adding User"
echo "********************"

# Check if 'andy' user already exists
if id "${user_name}" &>/dev/null; then
    echo "User '${user_name}' already exists. Skipping user creation."
else
    # Add user 'andy' with the prompted password
    read -sp "Enter password for new user: " user_password
    echo
    adduser --gecos "" --disabled-password --home /home/${user_name} ${user_name}
    echo "${user_name}:${user_password}" | chpasswd
fi

echo "********************"
echo "Configuring Firewall"
echo "********************"

# 6. Enable sudo access for user 'andy'
usermod -aG sudo ${user_name}

# 7. Configure firewall rules
if [ -x "$(command -v ufw)" ]; then
    # Reset existing rules
    ufw --force reset

    # Set default policies
    ufw default deny incoming
    ufw default deny outgoing

    # Allow incoming traffic from specific IP range
    ufw allow from 192.168.194.0/24

    # Allow ZeroTier (adjust the port if necessary)
    ufw allow 9993/udp

    # Allow SSH from anywhere
    ufw allow 22

    # Allow outgoing DNS traffic (port 53)
    ufw allow out 53
fi

echo "********************"
echo "Downloading SSH Keys"
echo "********************"

# Check if the .ssh folder exists for user 'andy', if not, create it
if [ ! -d /home/${user_name}/.ssh ]; then
    mkdir -p /home/${user_name}/.ssh
    chown ${user_name}:${user_name} /home/${user_name}/.ssh
    chmod 700 /home/${user_name}/.ssh
fi

# Download SSH keys from GitHub for user 'andy'
su -c "curl -sSf https://github.com/${github_username}.keys | grep -vE '^#' > /home/${user_name}/.ssh/authorized_keys" -s /bin/bash ${user_name}

echo "********************"
echo "Configuring Cronjob"
echo "********************"

# 9. Create a recurring cronjob to download SSH keys every 30 minutes for user 'andy'
(crontab -u ${user_name} -l ; echo "*/30 * * * * curl -sSf https://github.com/${github_username}.keys | grep -vE '^#' > /home/${user_name}/.ssh/authorized_keys") | crontab -u ${user_name} -

echo "********************"
echo "Configuring SSH"
echo "********************"

# 10. Disable password-based SSH access, allow SSH keys only
echo "PasswordAuthentication no" >> /etc/ssh/sshd_config

echo "********************"
echo "Disabling Root User"
echo "********************"

# 11. Optionally, disable the root user (comment out if you prefer to keep root access)
passwd -l root

echo "********************"
echo "Enabling UFW"
echo "********************"

# Check if UFW is enabled
if ufw status | grep -q "Status: active"; then
    echo "UFW is already enabled. Skipping UFW enable process."
else
    # Prompt to check ZeroTier connectivity before enabling UFW
    read -p "Have you checked ZeroTier connectivity? (y/n): " check_zerotier
    if [ "${check_zerotier}" == "y" ]; then
        # Enable UFW
        ufw --force enable
    else
        echo "Please check ZeroTier connectivity before enabling UFW."
        exit 1
    fi
fi

echo "********************"
echo "Restarting SSH"
echo "********************"

# Check if SSH is already restarted
if systemctl is-active --quiet ssh; then
    echo "SSH is already restarted. Skipping SSH restart process."
else
    # Prompt to check ZeroTier connectivity before restarting SSH
    read -p "Have you checked ZeroTier connectivity? (y/n): " check_zerotier
    if [ "${check_zerotier}" == "y" ]; then
        # Restart SSH
        systemctl restart ssh
    else
        echo "Please check ZeroTier connectivity before restarting SSH."
        exit 1
    fi
fi

echo "********************"
echo "Setup Completed"
echo "********************"

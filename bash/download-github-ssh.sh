#!/bin/bash

# Define the GitHub username from which to fetch SSH keys
GITHUB_USER="andyyanguk"

# Print the current date and time
date

# Check for internet connectivity, with a maximum of 3 retries
echo "Checking internet connectivity..."
RETRIES=3  # Number of attempts to check connectivity
counter=1  # Initialize retry counter
while [ $counter -le $RETRIES ]; do
    # Ping GitHub to check if there is an active internet connection, with a timeout of 5 seconds
    ping -c 1 -w 5 -q github.com &>/dev/null && break
    # If ping fails, notify and retry
    echo "Attempt $counter: Internet connectivity check failed, retrying..."
    if [ $counter -eq $RETRIES ]; then
        # Exit if all retry attempts fail
        echo "Internet is down after $RETRIES attempts!"; exit 1
    fi
    counter=$((counter + 1))  # Increment the counter
    sleep 1  # Wait for 1 second before retrying

done

# Notify that internet connectivity is fine
echo "Internet is fine!"
echo " "

# Download the latest SSH keys from GitHub
echo "Downloading latest SSH keys from Github..."

# Create the .ssh directory if it doesn't exist
echo "Creating .ssh directory if it doesn't exist..."
mkdir -p ~/.ssh || { echo "Failed to create .ssh directory."; exit 1; }

# Check if the permissions for the .ssh directory are secure (700)
if [ $(stat -c %a ~/.ssh) -ne 700 ]; then
    echo "Setting permissions for .ssh directory..."
    chmod 700 ~/.ssh || { echo "Failed to set permissions for .ssh directory."; exit 1; }
fi

# Download the SSH keys from GitHub to the authorized_keys file
echo "Attempting to download SSH keys..."
wget https://github.com/$GITHUB_USER.keys -O ~/.ssh/authorized_keys || { echo "Failed to download SSH keys."; exit 1; }

# Verify that the downloaded file is not empty
if [ ! -s ~/.ssh/authorized_keys ]; then
    echo "Downloaded SSH keys file is empty. Aborting."; exit 1
fi

# Check if the permissions for the authorized_keys file are secure (600)
if [ $(stat -c %a ~/.ssh/authorized_keys) -ne 600 ]; then
    echo "Setting permissions for authorized_keys file..."
    chmod 600 ~/.ssh/authorized_keys || { echo "Failed to set permissions for authorized_keys file."; exit 1; }
fi

# Notify that SSH keys have been successfully configured
echo "SSH keys have been successfully downloaded and configured."
exit 0

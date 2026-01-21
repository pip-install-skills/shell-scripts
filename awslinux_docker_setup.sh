#!/bin/bash

# 1. Update the installed packages
echo "Updating system packages..."
sudo yum update -y

# 2. Install Docker
echo "Installing Docker..."
sudo amazon-linux-extras install docker -y

# 3. Start and Enable Docker Service
echo "Starting Docker service..."
sudo service docker start
sudo systemctl enable docker

# 4. Add the current user to the docker group
# ${SUDO_USER:-$USER} grabs the username of the person who ran 'sudo'
# If sudo wasn't used, it falls back to the current user.
CURRENT_USER="${SUDO_USER:-$USER}"
echo "Adding user '$CURRENT_USER' to the docker group..."
sudo usermod -a -G docker "$CURRENT_USER"

# 5. Install Docker Compose (V2 Plugin)
# We download the official binary to the system-wide CLI plugins directory
echo "Installing Docker Compose..."

# Create the directory for Docker CLI plugins
sudo mkdir -p /usr/local/lib/docker/cli-plugins

# Fetch the latest version tag from GitHub
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d '"' -f 4)

# Download the binary
sudo curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" -o /usr/local/lib/docker/cli-plugins/docker-compose

# Make it executable
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# 6. Verification
echo "------------------------------------------------"
echo "Installation Complete!"
echo "Docker Version: $(docker --version)"
echo "Docker Compose Version: $(docker compose version)"
echo "------------------------------------------------"
echo "IMPORTANT: You must log out and log back in for the group changes to take effect."
echo "           (Or run 'newgrp docker' to apply changes in this terminal session)"

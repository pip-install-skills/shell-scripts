#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

echo "Installing required dependencies..."
sudo apt install -y software-properties-common

echo "Adding deadsnakes PPA for Python versions..."
sudo add-apt-repository ppa:deadsnakes/ppa -y

echo "Updating package lists after adding PPA..."
sudo apt update

echo "Installing Nginx and Certbot..."
sudo apt install -y nginx certbot python3-certbot-nginx

echo "Installing Python 3.11 and 3.12..."
sudo apt install -y python3.11 python3.12 python3.11-venv python3.12-venv python3.11-dev python3.12-dev

echo "Verifying Python installations..."
python3.11 --version
python3.12 --version

echo "Configuring UV Package Manager"
sudo snap install astral-uv --classic
uv python pin --global 3.12

echo "Python setup complete!"

# Install git
sudo apt install git -y

# Install crontab
sudo apt install cron -y
sudo systemctl start cron
sudo systemctl enable cron

echo "Setup complete!"

#!/bin/bash

# Exit on any error
set -e

echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

echo "Installing build essentials and DKMS..."
sudo apt install -y build-essential dkms

echo "Adding NVIDIA graphics drivers PPA..."
sudo add-apt-repository -y ppa:graphics-drivers/ppa
sudo apt update

echo "Installing ubuntu-drivers-common..."
sudo apt install -y ubuntu-drivers-common

echo "Auto-installing NVIDIA drivers..."
sudo ubuntu-drivers autoinstall

echo "Adding NVIDIA Container Toolkit GPG key..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

echo "Adding NVIDIA Container Toolkit repository..."
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

echo "Updating package lists..."
sudo apt update

echo "Installing NVIDIA Container Toolkit..."
sudo apt install -y nvidia-container-toolkit

echo "Configuring NVIDIA runtime for Docker..."
sudo nvidia-ctk runtime configure --runtime=docker

echo "Restarting Docker service..."
sudo systemctl restart docker

echo "✅ NVIDIA drivers and container toolkit installation complete."

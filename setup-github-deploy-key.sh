#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- 1. Validation & Parsing ---
if [ -z "$1" ]; then
    echo "Usage: $0 <github-repo-url>"
    echo "Example: $0 https://github.com/username/repository.git"
    exit 1
fi

REPO_URL=$1

# Ensure git is installed
if ! command -v git &> /dev/null; then
    echo "Error: 'git' is not installed. Please install git for your distribution first."
    exit 1
fi

# Extract the username and repository name using basic string manipulation
# Removes trailing .git if present
CLEAN_URL=$(echo "$REPO_URL" | sed 's/\.git$//')

if [[ "$CLEAN_URL" == https://github.com/* ]]; then
    USER_REPO=$(echo "$CLEAN_URL" | awk -F'github.com/' '{print $2}')
elif [[ "$CLEAN_URL" == git@github.com:* ]]; then
    USER_REPO=$(echo "$CLEAN_URL" | awk -F':' '{print $2}')
else
    echo "Error: Unrecognized GitHub URL format. Please use standard HTTPS or SSH URLs."
    exit 1
fi

GITHUB_USER=$(echo "$USER_REPO" | cut -d'/' -f1)
GITHUB_REPO=$(echo "$USER_REPO" | cut -d'/' -f2)

# Define unique key names based on the repo to prevent overwriting existing keys
KEY_NAME="deploy_key_${GITHUB_USER}_${GITHUB_REPO}"
KEY_PATH="$HOME/.ssh/$KEY_NAME"
SSH_ALIAS="github.com-${GITHUB_REPO}"

echo "================================================="
echo " Configuring Deploy Key for: $GITHUB_USER/$GITHUB_REPO"
echo "================================================="

# --- 2. VM Configuration: Generate SSH Key ---
# Ensure .ssh directory exists with correct permissions
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -f "$KEY_PATH" ]; then
    echo "Notice: An SSH key already exists at $KEY_PATH."
else
    echo "Generating new Ed25519 SSH key..."
    ssh-keygen -t ed25519 -C "deploy@$GITHUB_REPO" -f "$KEY_PATH" -N "" -q
    echo "Key generated successfully."
fi

# --- 3. VM Configuration: Update SSH Config ---
SSH_CONFIG_PATH="$HOME/.ssh/config"
touch "$SSH_CONFIG_PATH"
chmod 600 "$SSH_CONFIG_PATH"

# Check if the alias already exists to prevent duplicate entries
if ! grep -q "Host $SSH_ALIAS" "$SSH_CONFIG_PATH"; then
    echo -e "\nHost $SSH_ALIAS\n    HostName github.com\n    User git\n    IdentityFile $KEY_PATH\n    IdentitiesOnly yes\n" >> "$SSH_CONFIG_PATH"
    echo "Added SSH alias configuration to $SSH_CONFIG_PATH"
else
    echo "SSH alias for $SSH_ALIAS already exists in config. Skipping."
fi

# --- 4. GitHub UI Instructions ---
echo "================================================="
echo " ACTION REQUIRED ON GITHUB"
echo "================================================="
echo "1. Go to: https://github.com/$GITHUB_USER/$GITHUB_REPO/settings/keys"
echo "2. Click on 'Add deploy key'."
echo "3. Give it a title (e.g., 'VM Deploy Key - $HOSTNAME')."
echo "4. Copy and paste the following public key into the 'Key' field:"
echo ""
echo "-------------------------------------------------"
cat "${KEY_PATH}.pub"
echo "-------------------------------------------------"
echo ""
echo "5. (Optional) Check 'Allow write access' if your VM needs to push code."
echo "6. Click 'Add key'."
echo "================================================="

# --- 5. Pause for User Action ---
read -p "Press [Enter] ONLY AFTER you have added the key to GitHub..."

# --- 6. VM Action: Clone the Repository ---
echo "Testing connection and cloning repository..."

# Use ssh-keyscan to add github.com to known_hosts to prevent the interactive prompt
if ! grep -q "github.com" "$HOME/.ssh/known_hosts" 2>/dev/null; then
    ssh-keyscan -t ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
fi

# We use the custom alias defined in the SSH config to force git to use the specific deploy key
CLONE_URL="git@${SSH_ALIAS}:${GITHUB_USER}/${GITHUB_REPO}.git"

if [ -d "$GITHUB_REPO" ]; then
    echo "Directory '$GITHUB_REPO' already exists. Skipping clone."
else
    git clone "$CLONE_URL"
    echo "Repository cloned successfully into ./$GITHUB_REPO"
fi

echo "================================================="
echo " Setup Complete! "
echo " You can now pull/fetch inside the $GITHUB_REPO directory."
echo "================================================="

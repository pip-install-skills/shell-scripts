#!/usr/bin/env bash

# Configure a repository-specific GitHub deploy key.
#
# Usage:
#   ./setup-github-deploy-key.sh https://github.com/username/repository.git
#   ./setup-github-deploy-key.sh git@github.com:username/repository.git
#
# Behavior:
#   - If run inside an existing Git repository, configure/update its origin.
#   - Otherwise, clone the GitHub repository into ./<repository>.
#   - Never overwrites an existing origin without asking.
#   - Never pushes automatically.

set -e

# --- 1. Validation & Parsing ---
if [ -z "${1:-}" ]; then
    echo "Usage: $0 <github-repo-url>"
    echo "Example: $0 https://github.com/username/repository.git"
    exit 1
fi

REPO_URL="$1"

# Ensure git is installed
if ! command -v git &> /dev/null; then
    echo "Error: 'git' is not installed. Please install git for your distribution first."
    exit 1
fi

# Remove a trailing .git if present.
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

if [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_REPO" ] || [ "$USER_REPO" = "$GITHUB_USER" ]; then
    echo "Error: Could not parse GitHub owner/repository from '$REPO_URL'."
    exit 1
fi

# Define unique key names based on the repo to prevent overwriting existing keys.
KEY_NAME="deploy_key_${GITHUB_USER}_${GITHUB_REPO}"
KEY_PATH="$HOME/.ssh/$KEY_NAME"
SSH_ALIAS="github.com-${GITHUB_REPO}"
REMOTE_URL="git@${SSH_ALIAS}:${GITHUB_USER}/${GITHUB_REPO}.git"

# Determine whether we were launched from an existing Git worktree.
IN_EXISTING_REPO=false
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    IN_EXISTING_REPO=true
fi

echo "================================================="
echo " Configuring Deploy Key for: $GITHUB_USER/$GITHUB_REPO"
echo "================================================="

if [ "$IN_EXISTING_REPO" = true ]; then
    echo "Detected an existing Git repository: $(git rev-parse --show-toplevel)"
else
    echo "No existing Git repository detected in the current directory."
    echo "The repository will be cloned into: ./$GITHUB_REPO"
fi

# --- 2. VM Configuration: Generate SSH Key ---
# Ensure .ssh directory exists with correct permissions.
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

# Check if the alias already exists to prevent duplicate entries.
if ! grep -qE "^[[:space:]]*Host[[:space:]]+$SSH_ALIAS([[:space:]]|$)" "$SSH_CONFIG_PATH"; then
    {
        echo ""

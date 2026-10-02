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

set -Eeuo pipefail

# --- 1. Validation & Parsing ---
if [[ -z "${1:-}" ]]; then
    echo "Usage: $0 <github-repo-url>"
    echo "Example: $0 https://github.com/username/repository.git"
    exit 1
fi

REPO_URL="$1"

if ! command -v git >/dev/null 2>&1; then
    echo "Error: 'git' is not installed. Please install git first."
    exit 1
fi

if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "Error: 'ssh-keygen' is not installed."
    exit 1
fi

# Remove a trailing .git if present.
CLEAN_URL="${REPO_URL%.git}"

case "$CLEAN_URL" in
    https://github.com/*)
        USER_REPO="${CLEAN_URL#https://github.com/}"
        ;;
    git@github.com:*)
        USER_REPO="${CLEAN_URL#git@github.com:}"
        ;;
    *)
        echo "Error: Unrecognized GitHub URL format."
        echo "Please use: https://github.com/OWNER/REPO.git or git@github.com:OWNER/REPO.git"
        exit 1
        ;;
esac

# Reject paths containing more than OWNER/REPO.
if [[ "$USER_REPO" != */* || "$USER_REPO" == */*/* ]]; then
    echo "Error: Expected a GitHub repository in OWNER/REPO format."
    exit 1
fi

GITHUB_USER="${USER_REPO%%/*}"
GITHUB_REPO="${USER_REPO#*/}"

if [[ -z "$GITHUB_USER" || -z "$GITHUB_REPO" ]]; then
    echo "Error: Could not parse GitHub owner/repository from '$REPO_URL'."
    exit 1
fi

# Define unique key names based on the repo to prevent overwriting existing keys.
KEY_NAME="deploy_key_${GITHUB_USER}_${GITHUB_REPO}"
KEY_PATH="$HOME/.ssh/$KEY_NAME"
SSH_ALIAS="github.com-${GITHUB_REPO}"
REMOTE_URL="git@${SSH_ALIAS}:${GITHUB_USER}/${GITHUB_REPO}.git"
SSH_CONFIG_PATH="$HOME/.ssh/config"

# Determine whether we were launched from an existing Git worktree.
IN_EXISTING_REPO=false
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    IN_EXISTING_REPO=true
fi

REPO_ROOT=""
if [[ "$IN_EXISTING_REPO" == true ]]; then
    REPO_ROOT="$(git rev-parse --show-toplevel)"
fi

echo "================================================="
echo " Configuring Deploy Key for: $GITHUB_USER/$GITHUB_REPO"
echo "================================================="

if [[ "$IN_EXISTING_REPO" == true ]]; then
    echo "Detected an existing Git repository: $REPO_ROOT"
else
    echo "No existing Git repository detected in the current directory."
    echo "The repository will be cloned into: ./$GITHUB_REPO"
fi

# --- 2. Generate/reuse SSH key ---
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ -f "$KEY_PATH" ]]; then
    echo "Notice: An SSH key already exists at $KEY_PATH."
else
    echo "Generating new Ed25519 SSH key..."
    ssh-keygen -t ed25519 -C "deploy@$GITHUB_REPO" -f "$KEY_PATH" -N "" -q
    echo "Key generated successfully."
fi

# --- 3. Update SSH config ---
touch "$SSH_CONFIG_PATH"
chmod 600 "$SSH_CONFIG_PATH"

if ! grep -qE "^[[:space:]]*Host[[:space:]]+$SSH_ALIAS([[:space:]]|$)" "$SSH_CONFIG_PATH"; then
    {
        echo ""
        echo "Host $SSH_ALIAS"
        echo "    HostName github.com"
        echo "    User git"
        echo "    IdentityFile $KEY_PATH"
        echo "    IdentitiesOnly yes"
        echo ""
    } >> "$SSH_CONFIG_PATH"
    echo "Added SSH alias configuration to $SSH_CONFIG_PATH"
else
    echo "SSH alias for $SSH_ALIAS already exists in config. Skipping."
fi

# --- 4. GitHub UI instructions ---
echo "================================================="
echo " ACTION REQUIRED ON GITHUB"
echo "================================================="
echo "1. Go to: https://github.com/$GITHUB_USER/$GITHUB_REPO/settings/keys"
echo "2. Click on 'Add deploy key'."
echo "3. Give it a title (for example: 'VM Deploy Key - $HOSTNAME')."
echo "4. Copy and paste the following public key into the 'Key' field:"
echo ""
echo "-------------------------------------------------"
cat "${KEY_PATH}.pub"
echo "-------------------------------------------------"
echo ""
echo "5. Check 'Allow write access' if this VM needs to push code."
echo "6. Click 'Add key'."
echo "================================================="

read -r -p "Press [Enter] ONLY AFTER you have added the key to GitHub..."
echo ""

# --- 5. known_hosts ---
if ! ssh-keygen -F github.com >/dev/null 2>&1; then
    echo "Adding github.com to $HOME/.ssh/known_hosts..."
    mkdir -p "$HOME/.ssh"
    touch "$HOME/.ssh/known_hosts"
    chmod 600 "$HOME/.ssh/known_hosts"
    ssh-keyscan -t ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
fi

# --- 6. Verify GitHub access using the configured deploy key ---
echo "Testing GitHub access with the deploy key..."
if git ls-remote "$REMOTE_URL" HEAD >/dev/null 2>&1; then
    echo "GitHub authentication and repository access verified."
else
    echo "Error: Could not access $REMOTE_URL using the configured deploy key."
    echo "Check that the deploy key was added to the correct repository."
    echo "For push access, also make sure 'Allow write access' is enabled."
    exit 1
fi

# --- 7. Configure existing repository or clone ---
if [[ "$IN_EXISTING_REPO" == true ]]; then
    echo "================================================="
    echo " Configuring existing Git repository"
    echo "================================================="

    if git remote get-url origin >/dev/null 2>&1; then
        CURRENT_ORIGIN="$(git remote get-url origin)"

        if [[ "$CURRENT_ORIGIN" == "$REMOTE_URL" ]]; then
            echo "Remote 'origin' already points to:"
            echo "  $REMOTE_URL"
        else
            echo "An existing 'origin' remote was found:"
            echo "  $CURRENT_ORIGIN"
            echo ""
            echo "Requested 'origin':"
            echo "  $REMOTE_URL"
            echo ""
            read -r -p "Replace the existing 'origin' with the requested URL? [y/N] " REPLACE_ORIGIN

            case "$REPLACE_ORIGIN" in
                [yY]|[yY][eE][sS])
                    git remote set-url origin "$REMOTE_URL"
                    echo "Updated remote 'origin'."
                    ;;
                *)
                    echo "Leaving existing 'origin' unchanged."
                    echo "The deploy key was configured successfully."
                    exit 0
                    ;;
            esac
        fi
    else
        git remote add origin "$REMOTE_URL"
        echo "Added remote 'origin':"
        echo "  $REMOTE_URL"
    fi

    CURRENT_BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"

    echo ""
    echo "================================================="
    echo " Setup Complete!"
    echo "================================================="
    echo "Deploy key configured and remote 'origin' is ready."
    echo ""
    echo "Remote:"
    echo "  $REMOTE_URL"

    if [[ -n "$CURRENT_BRANCH" ]]; then
        echo ""
        echo "Current branch: $CURRENT_BRANCH"
        echo ""
        echo "To push this existing repository:"
        echo "  git push -u origin $CURRENT_BRANCH"
    else
        echo ""
        echo "The repository is currently in a detached HEAD state."
        echo "Set/check the branch before pushing."
    fi
else
    echo "Testing connection and cloning repository..."

    if [[ -e "$GITHUB_REPO" ]]; then
        if [[ -d "$GITHUB_REPO/.git" ]] || git -C "$GITHUB_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            echo "Directory '$GITHUB_REPO' already contains a Git repository."
            echo "Skipping clone."
            echo "Run this script from inside that repository to configure its origin."
        else
            echo "Error: Directory '$GITHUB_REPO' already exists and is not a Git repository."
            echo "Refusing to clone into an existing directory."
            exit 1
        fi
    else
        git clone "$REMOTE_URL"
        echo "Repository cloned successfully into ./$GITHUB_REPO"
    fi

    echo "================================================="
    echo " Setup Complete!"
    echo " You can now pull/fetch inside the $GITHUB_REPO directory."
    echo "================================================="
fi

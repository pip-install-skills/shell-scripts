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

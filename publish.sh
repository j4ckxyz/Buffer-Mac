#!/bin/bash

# --- Buffer-Mac Git & GitHub Deployer ---
# Initializes git repository, commits workspace, and pushes to a new public repo called Buffer-Mac.

set -e

REPO_NAME="Buffer-Mac"
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================="
echo "   Deploying ${REPO_NAME} to GitHub"
echo "============================================="

# Configure standard user details if not set (to prevent commit warnings/errors)
if [ -z "$(git config --global user.name)" ]; then
    git config --global user.name "Jack"
fi
if [ -z "$(git config --global user.email)" ]; then
    git config --global user.email "jack@example.com"
fi

# 1. Initialize git if not already initialized
if [ ! -d "${WORKSPACE_DIR}/.git" ]; then
    echo "🗂 Step 1: Initializing git repository..."
    git init
    git checkout -b main
else
    echo "🗂 Step 1: Git repository already exists."
fi

# 2. Add and commit all untracked files
echo "📝 Step 2: Staging files and creating initial commit..."
git add .
git commit -m "Initial commit: Overhaul preference pane, add GitHub update checker, build DMG system and premium README"

# 3. Use GitHub CLI to create the repository
echo "🌐 Step 3: Creating GitHub repository 'j4ckxyz/${REPO_NAME}'..."
if gh repo view "j4ckxyz/${REPO_NAME}" &>/dev/null; then
    echo "⚠️ Repository already exists on GitHub. Linking remote origin..."
    git remote remove origin 2>/dev/null || true
    git remote add origin "https://github.com/j4ckxyz/${REPO_NAME}.git"
else
    echo "🚀 Creating new public GitHub repository..."
    gh repo create "j4ckxyz/${REPO_NAME}" --public --source="${WORKSPACE_DIR}" --push
    echo "✅ Created and pushed repository to GitHub successfully!"
    exit 0
fi

# 4. Push main branch if repo existed but was not fully synced
echo "🚀 Step 4: Pushing local main branch to GitHub..."
git push -u origin main --force

echo "============================================="
echo "   🎉 ${REPO_NAME} successfully pushed to GitHub!"
echo "============================================="
echo "URL: https://github.com/j4ckxyz/${REPO_NAME}"
echo "============================================="

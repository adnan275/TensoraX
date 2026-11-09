#!/bin/bash
# ==============================================================================
# Script: auto_sync.sh
# Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
# Description: Lightweight background daemon to automatically sync (pull) latest
#              commits made by team members on GitHub (origin/main) into local repo.
# ==============================================================================

INTERVAL=25 # Check every 25 seconds
BRANCH="main"
REPO_DIR="/Users/adnanrizvi/Desktop/MCA_project"

cd "$REPO_DIR" || exit 1

echo "================================================================"
echo " [TensoraX Auto-Sync] Started background sync daemon"
echo " Monitoring branch: origin/$BRANCH every $INTERVAL seconds"
echo " Repo directory: $REPO_DIR"
echo "================================================================"

while true; do
    # Fetch latest remote changes silently
    git fetch origin "$BRANCH" >/dev/null 2>&1

    LOCAL=$(git rev-parse HEAD 2>/dev/null)
    REMOTE=$(git rev-parse "origin/$BRANCH" 2>/dev/null)

    if [ -n "$LOCAL" ] && [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
        echo "[$(date '+%H:%M:%S')] New changes detected on GitHub ($REMOTE). Syncing..."
        
        # Check if local working tree has unstaged modifications
        CHANGES=$(git status --porcelain)
        
        if [ -n "$CHANGES" ]; then
            echo "[$(date '+%H:%M:%S')] Local changes detected. Stashing before pull..."
            git stash push -u -m "auto-sync-temp-$(date +%s)" >/dev/null 2>&1
            git pull --rebase origin "$BRANCH"
            git stash pop >/dev/null 2>&1
        else
            git pull --ff-only origin "$BRANCH"
        fi
        
        echo "[$(date '+%H:%M:%S')] [SUCCESS] Local workspace updated to latest commit $(git rev-parse --short HEAD)!"
    fi

    sleep "$INTERVAL"
done

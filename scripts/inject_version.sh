#!/bin/bash
# FD-234: Inject git hash into project.godot version string for local development.

set -e

PROJECT_GODOT="project.godot"

if [ ! -f "$PROJECT_GODOT" ]; then
    echo "Error: project.godot not found in current directory."
    exit 1
fi

# Get current version from project.godot (e.g., v0.3.2)
CURRENT_VERSION=$(grep -E "^config/version=" "$PROJECT_GODOT" | cut -d'"' -f2)

if [ -z "$CURRENT_VERSION" ]; then
    echo "Error: Could not find config/version in $PROJECT_GODOT"
    exit 1
fi

# If it already has a hash, strip it to get the base version
BASE_VERSION=$(echo "$CURRENT_VERSION" | cut -d'+' -f1)

# Get short git hash and date
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
BUILD_DATE=$(date -u +%Y-%m-%d 2>/dev/null || echo "unknown")

NEW_VERSION="${BASE_VERSION}+${GIT_SHA} (${BUILD_DATE})"

echo "Updating version: $CURRENT_VERSION -> $NEW_VERSION"

# Use sed to update the file. Mac sed needs an empty string for -i.
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i "" "s|config/version=\"$CURRENT_VERSION\"|config/version=\"$NEW_VERSION\"|" "$PROJECT_GODOT"
else
    sed -i "s|config/version=\"$CURRENT_VERSION\"|config/version=\"$NEW_VERSION\"|" "$PROJECT_GODOT"
fi

echo "Done."

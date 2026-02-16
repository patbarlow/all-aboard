#!/bin/bash
set -euo pipefail

# This script builds a new release and generates/updates the Sparkle appcast.
# After running, commit and push the appcast.xml + DMG to your repo.

SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData/All_Aboard-*/SourcePackages/artifacts/sparkle/Sparkle/bin -name generate_appcast -print -quit 2>/dev/null)"

if [ -z "${SPARKLE_BIN}" ]; then
    echo "Error: Sparkle generate_appcast not found. Build the project in Xcode first."
    exit 1
fi

SPARKLE_DIR="$(dirname "${SPARKLE_BIN}")"

# Step 1: Build the DMG
echo "==> Building DMG..."
./scripts/build-dmg.sh

# Step 2: Create releases directory for appcast
RELEASES_DIR="$(pwd)/releases"
mkdir -p "${RELEASES_DIR}"

# Copy the DMG to releases
cp "build/All Aboard.dmg" "${RELEASES_DIR}/"

# Step 3: Generate/update the appcast
echo "==> Generating appcast..."
"${SPARKLE_DIR}/generate_appcast" "${RELEASES_DIR}" \
    --download-url-prefix "https://github.com/patbarlow/all-aboard/releases/latest/download/"

# Copy appcast to repo root for GitHub hosting
cp "${RELEASES_DIR}/appcast.xml" "$(pwd)/appcast.xml"

echo "==> Done!"
echo ""
echo "Next steps:"
echo "  1. Commit appcast.xml"
echo "  2. Create a GitHub release and upload: releases/All Aboard.dmg"
echo "  3. Users will be notified of the update automatically"

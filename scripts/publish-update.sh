#!/bin/bash
set -euo pipefail

# This script builds a new release and generates/updates a Sparkle appcast.
# Use --channel stable (default) or --channel beta.
# After running, commit and push the appcast + DMG to your repo.

CHANNEL="stable"
if [ "${1:-}" = "--channel" ] && [ -n "${2:-}" ]; then
    CHANNEL="${2}"
fi

if [ "${CHANNEL}" != "stable" ] && [ "${CHANNEL}" != "beta" ]; then
    echo "Error: unsupported channel '${CHANNEL}'. Use stable or beta."
    exit 1
fi

SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData/All_Aboard-*/SourcePackages/artifacts/sparkle/Sparkle/bin -name generate_appcast -print -quit 2>/dev/null)"

if [ -z "${SPARKLE_BIN}" ]; then
    echo "Error: Sparkle generate_appcast not found. Build the project in Xcode first."
    exit 1
fi

SPARKLE_DIR="$(dirname "${SPARKLE_BIN}")"

# Step 1: Build the DMG
echo "==> Building DMG..."
./scripts/build-dmg.sh

# Step 2: Create channel-specific releases directory for appcast
# Stable and beta use separate subdirs so generate_appcast never sees both
# DMGs at once (it errors on duplicate bundle versions).
if [ "${CHANNEL}" = "beta" ]; then
    DMG_BASENAME="All.Aboard.Beta.dmg"
    APPCAST_FILE="appcast-beta.xml"
    DOWNLOAD_URL_PREFIX="https://github.com/patbarlow/all-aboard/releases/download/beta/"
else
    DMG_BASENAME="All Aboard.dmg"
    APPCAST_FILE="appcast.xml"
    DOWNLOAD_URL_PREFIX="https://github.com/patbarlow/all-aboard/releases/latest/download/"
fi

RELEASES_DIR="$(pwd)/releases/${CHANNEL}"
mkdir -p "${RELEASES_DIR}"

cp "${TMPDIR}allaboard-build/All Aboard.dmg" "${RELEASES_DIR}/${DMG_BASENAME}"

# Step 3: Generate/update the appcast
echo "==> Generating appcast..."
"${SPARKLE_DIR}/generate_appcast" "${RELEASES_DIR}" \
    --download-url-prefix "${DOWNLOAD_URL_PREFIX}"

# Copy appcast to repo root for GitHub hosting
cp "${RELEASES_DIR}/appcast.xml" "$(pwd)/${APPCAST_FILE}"

# Step 4: Ensure the enclosure has an EdDSA signature.
# generate_appcast can skip signing when its Keychain lookup fails.
# Fall back to sign_update directly if the signature is missing.
DMG_FILE="${RELEASES_DIR}/${DMG_BASENAME}"
if ! grep -q 'sparkle:edSignature' "$(pwd)/${APPCAST_FILE}"; then
    echo "==> generate_appcast did not sign the enclosure — running sign_update directly..."
    SIGNATURE=$("${SPARKLE_DIR}/sign_update" "${DMG_FILE}" 2>/dev/null | grep -o 'sparkle:edSignature="[^"]*"')
    DMG_SIZE=$(stat -f "%z" "${DMG_FILE}")
    if [ -n "${SIGNATURE}" ]; then
        # Patch the length and inject the signature into the enclosure element
        sed -i '' \
            "s|<enclosure url=\"\([^\"]*\)\" length=\"[0-9]*\"|<enclosure url=\"\1\" ${SIGNATURE} length=\"${DMG_SIZE}\"|g" \
            "$(pwd)/${APPCAST_FILE}"
        echo "==> Signature injected successfully."
    else
        echo "Warning: sign_update also failed. Update will not be installable until signed."
    fi
fi

echo "==> Done!"
echo ""
echo "Next steps:"
echo "  1. Commit ${APPCAST_FILE}"
echo "  2. Upload: releases/${DMG_BASENAME}"
if [ "${CHANNEL}" = "beta" ]; then
    echo "  3. Ensure the asset is in GitHub release tag 'beta'"
else
    echo "  3. Create a GitHub stable release"
fi
echo "  4. Users on that channel will be notified automatically"

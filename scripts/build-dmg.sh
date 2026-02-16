#!/bin/bash
set -euo pipefail

# Configuration
APP_NAME="All Aboard"
SCHEME="All Aboard"
BUILD_DIR="$(pwd)/build"
APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
VOLUME_NAME="${APP_NAME}"

SIGN_IDENTITY="Developer ID Application: Pat Barlow (T544U3WVL6)"

echo "==> Cleaning build directory..."
rm -rf "${BUILD_DIR}"

echo "==> Building ${APP_NAME} (Release)..."
xcodebuild \
    -project "All Aboard.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    -arch arm64 -arch x86_64 \
    ONLY_ACTIVE_ARCH=NO \
    clean build

if [ ! -d "${APP_PATH}" ]; then
    echo "Error: Build failed — ${APP_PATH} not found"
    exit 1
fi

echo "==> Build succeeded: ${APP_PATH}"

# Code sign if identity is set
if [ -n "${SIGN_IDENTITY}" ]; then
    echo "==> Signing with: ${SIGN_IDENTITY}"
    codesign --force --deep --options runtime \
        --sign "${SIGN_IDENTITY}" \
        "${APP_PATH}"
else
    echo "==> Skipping code signing (set SIGN_IDENTITY to enable)"
fi

# Create DMG
echo "==> Creating DMG..."
TEMP_DMG="${BUILD_DIR}/temp.dmg"
hdiutil create -size 50m -fs HFS+ -volname "${VOLUME_NAME}" "${TEMP_DMG}"
MOUNT_DIR="/Volumes/${VOLUME_NAME}"
hdiutil attach "${TEMP_DMG}" -mountpoint "${MOUNT_DIR}" -nobrowse
cp -R "${APP_PATH}" "${MOUNT_DIR}/"
ln -s /Applications "${MOUNT_DIR}/Applications"
hdiutil detach "${MOUNT_DIR}" -force
hdiutil convert "${TEMP_DMG}" -format UDZO -o "${DMG_PATH}"
rm "${TEMP_DMG}"

# Sign DMG
if [ -n "${SIGN_IDENTITY}" ]; then
    echo "==> Signing DMG..."
    codesign --force --sign "${SIGN_IDENTITY}" "${DMG_PATH}"
fi

echo "==> DMG created: ${DMG_PATH}"

# Notarize if identity is set
if [ -n "${SIGN_IDENTITY}" ]; then
    echo "==> Submitting for notarization..."
    echo "    (Requires: xcrun notarytool store-credentials 'allaboard-notary' --apple-id YOUR_APPLE_ID)"
    xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "allaboard-notary" \
        --wait

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "${DMG_PATH}"
    echo "==> Notarization complete!"
fi

echo "==> Done! Output: ${DMG_PATH}"

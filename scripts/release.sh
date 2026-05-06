#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release.sh 1.5.0
# One-time machine setup required (see README):
#   - Developer ID cert in Keychain
#   - xcrun notarytool store-credentials "allaboard-notary" ...
#   - Sparkle EdDSA private key in Keychain
#   - gh CLI authenticated

VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
    echo "Usage: $0 <version>  e.g. $0 1.5.0"
    exit 1
fi

if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: version must be x.y.z"
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "Error: working tree is dirty. Commit or stash changes first."
    exit 1
fi

PBXPROJ="All Aboard.xcodeproj/project.pbxproj"
BUILD_NUMBER=$(( $(git rev-list --count HEAD) + 1 ))

echo "==> Releasing v${VERSION} (build ${BUILD_NUMBER})"

# Bump version in xcodeproj (both Debug and Release configs)
sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = ${VERSION};/g" "${PBXPROJ}"
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};/g" "${PBXPROJ}"

echo "==> Version bumped to ${VERSION} (${BUILD_NUMBER})"

# Build DMG + notarize + generate appcast
./scripts/publish-update.sh

DMG_SRC="${TMPDIR}allaboard-build/All Aboard.dmg"
DMG_DEST="releases/stable/AllAboard.dmg"

# Commit, tag, push
git add "${PBXPROJ}" appcast.xml
git commit -m "Release v${VERSION} (build ${BUILD_NUMBER})"
git tag "v${VERSION}"
git push origin main
git push origin "v${VERSION}"

# Create GitHub release and upload artifacts
echo "==> Creating GitHub release..."
gh release create "v${VERSION}" \
    "${DMG_DEST}#AllAboard.dmg" \
    --title "v${VERSION}" \
    --notes "All Aboard v${VERSION}"

echo ""
echo "==> Done! v${VERSION} is live."
echo "    Sparkle will notify existing users automatically."

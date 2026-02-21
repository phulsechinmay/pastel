#!/bin/bash
set -euo pipefail

# Pastel DMG Build, Sign, Notarize, and Staple Script
# Usage: ./scripts/build-dmg.sh [keychain-profile]
#
# Prerequisites:
#   1. Run `xcrun notarytool store-credentials pastel-notarize` once
#   2. Run Sparkle's generate_keys once (EdDSA keypair in Keychain)
#   3. Update SUPublicEDKey in Info.plist with the public key
#   4. Set DEVELOPER_ID below to your "Developer ID Application" identity

APP_NAME="Pastel"
SCHEME="Pastel Sparkle"
CONFIGURATION="Release-Sparkle"
BUILD_DIR="build"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
KEYCHAIN_PROFILE="${1:-pastel-notarize}"
DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application}"

echo "=== Building ${APP_NAME} (${CONFIGURATION}) ==="
xcodebuild -scheme "${SCHEME}" -configuration "${CONFIGURATION}" \
  -derivedDataPath "${BUILD_DIR}/DerivedData" \
  -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
  archive

echo "=== Exporting archive ==="
# Create export options plist
cat > "${BUILD_DIR}/ExportOptions.plist" << 'EXPORTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
</dict>
</plist>
EXPORTEOF

xcodebuild -exportArchive \
  -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
  -exportPath "${BUILD_DIR}" \
  -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist"

echo "=== Creating DMG ==="
rm -f "${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_PATH}" \
  -ov -format UDZO "${DMG_PATH}"

echo "=== Signing DMG ==="
codesign --force --sign "${DEVELOPER_ID}" --options runtime "${DMG_PATH}"

echo "=== Notarizing DMG ==="
xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile "${KEYCHAIN_PROFILE}" --wait

echo "=== Stapling ==="
xcrun stapler staple "${DMG_PATH}"

echo "=== Verifying ==="
xcrun stapler validate "${DMG_PATH}"

echo "=== Generating Appcast ==="
# generate_appcast is bundled in the Sparkle SPM artifact
GENERATE_APPCAST=$(find "${BUILD_DIR}/DerivedData" -name "generate_appcast" -type f 2>/dev/null | head -1)
if [ -n "${GENERATE_APPCAST}" ]; then
    "${GENERATE_APPCAST}" "${BUILD_DIR}" --download-url-prefix "${DOWNLOAD_URL_PREFIX:-https://github.com/pulsechinmay/pastel-updates/releases/download/latest/}"
    echo "Appcast generated at ${BUILD_DIR}/appcast.xml"
else
    echo "WARNING: generate_appcast not found. Run manually after build."
    echo "  Usage: generate_appcast ${BUILD_DIR}/ --download-url-prefix <url>"
fi

echo ""
echo "SUCCESS: ${DMG_PATH} is ready for distribution"
echo ""
echo "Next steps:"
echo "  1. Upload ${DMG_PATH} and ${BUILD_DIR}/appcast.xml to your updates repository"

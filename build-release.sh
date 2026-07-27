#!/bin/bash
set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────
SCHEME="Pastel Sparkle"
TEAM_ID="QLSJ39DRSH"
SIGNING_IDENTITY="Developer ID Application: Chinmay Phulse ($TEAM_ID)"
NOTARY_PROFILE="notary-pastel"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/Pastel.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"

# ─── Resolve version from Xcode project ──────────────────────────────────────
VERSION=$(xcodebuild -scheme "$SCHEME" -configuration Release-Sparkle -showBuildSettings 2>/dev/null \
    | grep MARKETING_VERSION | head -1 | awk '{print $NF}')

if [ -z "$VERSION" ]; then
    echo "Error: Could not determine MARKETING_VERSION from Xcode project"
    exit 1
fi

DMG_NAME="Pastel.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
TAG="v${VERSION}"

echo "==> Building Pastel $TAG"

# ─── Preflight checks ────────────────────────────────────────────────────────
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "Error: No Developer ID Application certificate found in keychain"
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Error: Notarization credentials not found. Run:"
    echo "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <email> --team-id $TEAM_ID"
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "Error: gh CLI not installed. Run: brew install gh"
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "Error: gh not authenticated. Run: gh auth login"
    exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Error: xcodegen not installed. Run: brew install xcodegen"
    exit 1
fi

if git tag -l "$TAG" | grep -q "$TAG"; then
    echo "Error: Tag $TAG already exists. Bump MARKETING_VERSION in Xcode first."
    exit 1
fi

# ─── Auto-increment build number ─────────────────────────────────────────────
echo "==> Incrementing CURRENT_PROJECT_VERSION"
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed 's/.*"\(.*\)"/\1/')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CURRENT_BUILD\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" project.yml
echo "    Build number: $CURRENT_BUILD -> $NEW_BUILD"

# Regenerate the Xcode project so the committed pbxproj matches project.yml.
# Without this the pbxproj keeps the old build number and disagrees with what
# was actually released (the archive below takes the value from the CLI).
xcodegen generate >/dev/null
git add project.yml Pastel.xcodeproj/project.pbxproj
git commit -m "build: bump CURRENT_PROJECT_VERSION to $NEW_BUILD"

# ─── Clean previous build artifacts ──────────────────────────────────────────
echo "==> Cleaning build directory"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$BUILD_DIR/dmg-staging" "$DMG_PATH"

# ─── Archive ──────────────────────────────────────────────────────────────────
echo "==> Archiving ($SCHEME, Release-Sparkle, hardened runtime)"
xcodebuild -scheme "$SCHEME" \
    -configuration Release-Sparkle \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ENABLE_HARDENED_RUNTIME=YES \
    CURRENT_PROJECT_VERSION="$NEW_BUILD" \
    | tail -3

# ─── Export with Developer ID signing ─────────────────────────────────────────
echo "==> Exporting with Developer ID signing"
cat > "$EXPORT_OPTIONS" << 'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>QLSJ39DRSH</string>
</dict>
</plist>
PLISTEOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates \
    | tail -3

# ─── Verify signing ──────────────────────────────────────────────────────────
echo "==> Verifying code signature"
codesign -dv --verbose=2 "$EXPORT_PATH/Pastel.app" 2>&1 | grep -E "(Authority|flags|Runtime)"

# ─── Create DMG ───────────────────────────────────────────────────────────────
echo "==> Creating DMG"
mkdir -p "$BUILD_DIR/dmg-staging"
cp -R "$EXPORT_PATH/Pastel.app" "$BUILD_DIR/dmg-staging/"
ln -sf /Applications "$BUILD_DIR/dmg-staging/Applications"

hdiutil create \
    -volname "Pastel" \
    -srcfolder "$BUILD_DIR/dmg-staging" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"

# ─── Notarize ─────────────────────────────────────────────────────────────────
echo "==> Submitting for notarization (this may take a few minutes)"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"

# ─── Verify final DMG ────────────────────────────────────────────────────────
echo "==> Verifying notarization"
spctl -a -t open --context context:primary-signature -v "$DMG_PATH" 2>&1

# ─── Generate Sparkle Appcast ────────────────────────────────────────────────
echo "==> Generating Sparkle appcast"
GENERATE_APPCAST=$(find "$BUILD_DIR" -name "generate_appcast" -type f 2>/dev/null | head -1)
if [ -z "$GENERATE_APPCAST" ]; then
    GENERATE_APPCAST=$(find ~/Library/Developer/Xcode/DerivedData -name "generate_appcast" -type f 2>/dev/null | head -1)
fi
if [ -n "$GENERATE_APPCAST" ]; then
    REPO_URL=$(gh repo view --json url -q .url)
    # Use a staging directory with only the current DMG to avoid duplicate version errors
    APPCAST_DIR="$BUILD_DIR/appcast-staging"
    rm -rf "$APPCAST_DIR"
    mkdir -p "$APPCAST_DIR"
    cp "$DMG_PATH" "$APPCAST_DIR/"
    "$GENERATE_APPCAST" "$APPCAST_DIR" \
        --download-url-prefix "${REPO_URL}/releases/download/${TAG}/"
    cp "$APPCAST_DIR/appcast.xml" "$BUILD_DIR/appcast.xml"
    rm -rf "$APPCAST_DIR"
    echo "    Appcast: $BUILD_DIR/appcast.xml"
else
    echo "WARNING: generate_appcast not found. Run manually after release."
fi

# ─── GitHub Release ───────────────────────────────────────────────────────────
echo "==> Creating GitHub release $TAG"
git tag "$TAG"
git push origin "$TAG"

RELEASE_ASSETS=("$DMG_PATH")
if [ -f "$BUILD_DIR/appcast.xml" ]; then
    RELEASE_ASSETS+=("$BUILD_DIR/appcast.xml")
fi
gh release create "$TAG" "${RELEASE_ASSETS[@]}" \
    --title "Pastel $TAG" \
    --generate-notes

DMG_SIZE=$(du -h "$DMG_PATH" | awk '{print $1}')
RELEASE_URL=$(gh release view "$TAG" --json url -q .url)

# ─── Deploy Appcast to Feed Branch ───────────────────────────────────────────
if [ -f "$BUILD_DIR/appcast.xml" ]; then
    echo "==> Deploying appcast to appcast branch"
    FEED_DIR="$BUILD_DIR/appcast-deploy"
    rm -rf "$FEED_DIR"
    git worktree add "$FEED_DIR" appcast 2>/dev/null || {
        # Create orphan appcast branch if it doesn't exist
        git worktree add --detach "$FEED_DIR"
        git -C "$FEED_DIR" checkout --orphan appcast
        git -C "$FEED_DIR" rm -rf . 2>/dev/null || true
    }
    cp "$BUILD_DIR/appcast.xml" "$FEED_DIR/appcast.xml"
    git -C "$FEED_DIR" add appcast.xml
    git -C "$FEED_DIR" commit -m "Update appcast for $TAG"
    git -C "$FEED_DIR" push origin appcast
    git worktree remove "$FEED_DIR" --force
    echo "    Feed updated: https://raw.githubusercontent.com/phulsechinmay/pastel/appcast/appcast.xml"
fi

echo ""
echo "==> Done!"
echo "    Version:  $TAG"
echo "    DMG:      $DMG_PATH ($DMG_SIZE)"
echo "    Release:  $RELEASE_URL"

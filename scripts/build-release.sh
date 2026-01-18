#!/bin/bash

# Build script for Tunnelflare release
# Creates an unsigned .app and .zip for distribution
# Based on Rectangle's build approach: https://github.com/rxhanson/Rectangle

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Tunnelflare Release Build ===${NC}"

# Configuration
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Tunnelflare"
SCHEME="Tunnelflare"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"

# Clean build directory
echo -e "${YELLOW}Cleaning build directory...${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Archive the app (unsigned, with release entitlements, arm64 only)
echo -e "${YELLOW}Archiving $APP_NAME...${NC}"
xcodebuild -project "$PROJECT_DIR/Tunnelflare.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_ENTITLEMENTS="$PROJECT_DIR/Tunnelflare/TunnelflareRelease.entitlements" \
    archive

# Extract app from archive
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: Could not find built app at $APP_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}Found app at: $APP_PATH${NC}"

# Copy to build directory
cp -R "$APP_PATH" "$BUILD_DIR/$APP_NAME.app"

# Ad-hoc sign (optional, reduces some warnings)
echo -e "${YELLOW}Ad-hoc signing...${NC}"
codesign --force --deep --sign - "$BUILD_DIR/$APP_NAME.app" 2>/dev/null || true

# Create zip
echo -e "${YELLOW}Creating zip archive...${NC}"
cd "$BUILD_DIR"
zip -r -y "$APP_NAME.zip" "$APP_NAME.app"

# Get version from Info.plist
VERSION=$(defaults read "$BUILD_DIR/$APP_NAME.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
BUILD=$(defaults read "$BUILD_DIR/$APP_NAME.app/Contents/Info" CFBundleVersion 2>/dev/null || echo "0")

# Rename with version
RELEASE_NAME="${APP_NAME}-${VERSION}-${BUILD}"
mv "$APP_NAME.zip" "${RELEASE_NAME}.zip"

echo ""
echo -e "${GREEN}=== Build Complete ===${NC}"
echo -e "App:     $BUILD_DIR/$APP_NAME.app"
echo -e "Release: $BUILD_DIR/${RELEASE_NAME}.zip"
echo -e "Version: $VERSION ($BUILD)"
echo ""
echo -e "${YELLOW}To create a GitHub release:${NC}"
echo "  gh release create v$VERSION '$BUILD_DIR/${RELEASE_NAME}.zip' --title 'v$VERSION' --notes 'Release notes here'"

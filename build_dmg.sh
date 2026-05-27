#!/bin/bash

# --- Buffer-Mac DMG Builder ---
# Compiles the release binary, creates the .app bundle, and packages it into a native .dmg.

set -e

APP_NAME="BufferMenubar"
DMG_NAME="Buffer-Mac"
WORKSPACE_DIR="/Users/jack/code/buffer-menubar"
BUILD_DIR="${WORKSPACE_DIR}/build"
DMG_STAGING_DIR="${BUILD_DIR}/dmg_staging"
OUTPUT_DMG="${WORKSPACE_DIR}/${DMG_NAME}.dmg"

echo "============================================="
echo "   Building Native DMG for ${DMG_NAME}"
echo "============================================="

# 1. Run the existing build app script to compile & package the app bundle
echo "📦 Step 1: Building ${APP_NAME}.app..."
chmod +x ./build_app.sh
./build_app.sh

# 2. Verify .app bundle exists
APP_BUNDLE="${WORKSPACE_DIR}/${APP_NAME}.app"
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "❌ Error: App bundle not found at ${APP_BUNDLE}"
    exit 1
fi

# 3. Create DMG staging area
echo "📁 Step 2: Creating DMG staging environment..."
rm -rf "${BUILD_DIR}"
mkdir -p "${DMG_STAGING_DIR}"

# 4. Copy app bundle and create Applications link
echo "🔗 Step 3: Copying app bundle and creating system Applications symlink..."
cp -R "${APP_BUNDLE}" "${DMG_STAGING_DIR}/"
ln -s /Applications "${DMG_STAGING_DIR}/Applications"

# 5. Build the DMG natively via hdiutil
echo "📀 Step 4: Generating native macOS DMG file: ${DMG_NAME}.dmg..."
rm -f "${OUTPUT_DMG}"
hdiutil create -volname "${DMG_NAME}" -srcfolder "${DMG_STAGING_DIR}" -ov -format UDZO "${OUTPUT_DMG}"

# 6. Clean up temporary files
echo "🧹 Step 5: Cleaning up build directories..."
rm -rf "${BUILD_DIR}"

echo "============================================="
echo "   🎉 ${DMG_NAME}.dmg successfully generated!"
echo "============================================="
echo "Path: ${OUTPUT_DMG}"
echo "You can double click this DMG to install the application."
echo "============================================="

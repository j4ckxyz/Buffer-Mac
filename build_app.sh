#!/bin/bash

# --- Buffer macOS Menu Bar App Builder ---
# Compiles and packages the application into a native, standalone .app bundle.

set -e

APP_NAME="BufferMenubar"
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_VERSION="$(cat "${WORKSPACE_DIR}/VERSION" | xargs)"
APP_BUNDLE="${WORKSPACE_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "============================================="
echo "   Building ${APP_NAME} for macOS"
echo "============================================="

# 1. Compile the SPM project for both Apple Silicon and Intel architectures
echo "📦 Compiling Swift project for Apple Silicon (arm64)..."
swift build -c release --triple arm64-apple-macosx

echo "📦 Compiling Swift project for Intel (x86_64)..."
swift build -c release --triple x86_64-apple-macosx

# 2. Combine both architectures into a single Universal Binary using lipo
echo "🔗 Combining binaries into a native Universal 2 Binary..."
mkdir -p "${WORKSPACE_DIR}/.build/release"
lipo -create -output "${WORKSPACE_DIR}/.build/release/${APP_NAME}" \
    "${WORKSPACE_DIR}/.build/arm64-apple-macosx/release/${APP_NAME}" \
    "${WORKSPACE_DIR}/.build/x86_64-apple-macosx/release/${APP_NAME}"

# 3. Check compiled binary
BINARY_PATH="${WORKSPACE_DIR}/.build/release/${APP_NAME}"
if [ ! -f "${BINARY_PATH}" ]; then
    echo "❌ Error: Compiled binary not found at ${BINARY_PATH}"
    exit 1
fi
echo "✅ Universal compilation successful!"

# 3. Create .app bundle structure
echo "📁 Packaging application bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 3b. Compile AppIcon.icns natively using sips and iconutil
SRC_ICON="${WORKSPACE_DIR}/AppIcon.png"
if [ -f "${SRC_ICON}" ]; then
    echo "🎨 Compiling custom macOS-native AppIcon.icns..."
    ICONSET_DIR="${WORKSPACE_DIR}/.build/AppIcon.iconset"
    rm -rf "${ICONSET_DIR}"
    mkdir -p "${ICONSET_DIR}"
    
    sips -z 16 16     "${SRC_ICON}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null 2>&1
    sips -z 32 32     "${SRC_ICON}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null 2>&1
    sips -z 32 32     "${SRC_ICON}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null 2>&1
    sips -z 64 64     "${SRC_ICON}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null 2>&1
    sips -z 128 128   "${SRC_ICON}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null 2>&1
    sips -z 256 256   "${SRC_ICON}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null 2>&1
    sips -z 256 256   "${SRC_ICON}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null 2>&1
    sips -z 512 512   "${SRC_ICON}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null 2>&1
    sips -z 512 512   "${SRC_ICON}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null 2>&1
    sips -z 1024 1024 "${SRC_ICON}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null 2>&1
    
    iconutil -c icns "${ICONSET_DIR}" --o "${RESOURCES_DIR}/AppIcon.icns"
    rm -rf "${ICONSET_DIR}"
    echo "✅ AppIcon.icns successfully compiled and bundled!"
else
    echo "⚠️ Warning: Sources/AppIcon.png not found, skipping icon compilation."
fi

# 4. Copy the binary
cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# 4b. Copy the macOS Tahoe .icon bundle into Resources
TAHOE_ICON_SRC="${WORKSPACE_DIR}/Buffer Mac - App Icon.icon"
if [ -d "${TAHOE_ICON_SRC}" ]; then
    echo "💎 Bundling macOS Tahoe layered Liquid Glass AppIcon.icon..."
    cp -R "${TAHOE_ICON_SRC}" "${RESOURCES_DIR}/AppIcon.icon"
    echo "✅ macOS Tahoe Liquid Glass AppIcon.icon bundled!"
else
    echo "⚠️ Warning: Buffer Mac - App Icon.icon directory not found, skipping Tahoe layered icon bundling."
fi


# 5. Create Info.plist (Enabling LSUIElement to run as a native menu bar agent)
echo "📝 Writing Info.plist metadata..."
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.jack.buffermenubar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "============================================="
echo "   🎉 ${APP_NAME}.app successfully built!"
echo "============================================="
echo "Path: ${APP_BUNDLE}"
echo ""
echo "🚀 Skipping copy to /Applications (Local testing mode active!)"
echo ""
echo "To launch the app locally:"
echo "  1. Double-click '${APP_BUNDLE}' in Finder"
echo "  2. Or run: open '${APP_BUNDLE}'"
echo "============================================="

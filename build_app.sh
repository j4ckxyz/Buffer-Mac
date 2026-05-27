#!/bin/bash

# --- Buffer macOS Menu Bar App Builder ---
# Compiles and packages the application into a native, standalone .app bundle.

set -e

APP_NAME="BufferMenubar"
WORKSPACE_DIR="/Users/jack/code/buffer-menubar"
APP_BUNDLE="${WORKSPACE_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "============================================="
echo "   Building ${APP_NAME} for macOS"
echo "============================================="

# 1. Compile the SPM project
echo "📦 Compiling Swift project in Release mode..."
swift build -c release

# 2. Check compiled binary
BINARY_PATH="${WORKSPACE_DIR}/.build/release/${APP_NAME}"
if [ ! -f "${BINARY_PATH}" ]; then
    echo "❌ Error: Compiled binary not found at ${BINARY_PATH}"
    exit 1
fi
echo "✅ Compilation successful!"

# 3. Create .app bundle structure
echo "📁 Packaging application bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 4. Copy the binary
cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

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
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
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
echo "🚀 Copying ${APP_NAME}.app to /Applications..."
rm -rf "/Applications/${APP_NAME}.app"
cp -R "${APP_BUNDLE}" "/Applications/"
echo "✅ Copied to /Applications successfully!"
echo ""
echo "To launch the app:"
echo "  1. Double-click '/Applications/${APP_NAME}.app' in Finder or your Applications folder"
echo "  2. Or run: open '/Applications/${APP_NAME}.app'"
echo "============================================="

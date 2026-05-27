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

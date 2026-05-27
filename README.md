# Buffer for Mac

[![Download Buffer-Mac](https://img.shields.io/badge/Download-Buffer--Mac.dmg-blue?style=for-the-badge&logo=apple)](https://github.com/j4ckxyz/Buffer-Mac/releases/download/latest/Buffer-Mac.dmg)

Buffer for Mac is a high-fidelity, premium macOS menu bar application designed for instant, distraction-free social media publishing. It acts as an ultra-fast global composer that links directly to your Buffer account.

Designed specifically for power users, creators, and developers, it stays out of your way in the macOS menu bar and pops open instantly with a globally registered keyboard shortcut.

> **Latest Installer**: [Download Buffer-Mac.dmg (Universal 2)](https://github.com/j4ckxyz/Buffer-Mac/releases/download/latest/Buffer-Mac.dmg) | [View Latest Release Page](https://github.com/j4ckxyz/Buffer-Mac/releases/tag/latest)

---

## System Requirements

To ensure high performance and compliance with modern macOS standards, Buffer for Mac satisfies the following operational criteria:

* **Supported Operating Systems**: macOS 13.0 (Ventura), macOS 14 (Sonoma), macOS 15 (Sequoia), or newer.
* **Supported Architectures**: Native **Universal 2** binary supporting both **Apple Silicon** (M1/M2/M3/M4/Ultra) and **Intel** (64-bit) Macs.
* **Network Credentials**: A free or paid Buffer account with a secure Personal Access Token (Bearer Token) generated from your [Buffer Settings Dashboard](https://publish.buffer.com/settings/api).
* **Storage Footprint**: Light-weight background footprint under 15MB RAM.

---

## Key Features

- **Global Shortcut & Hyperkey Support**: Open the composer instantly from anywhere using your choice of custom hotkey bindings, including full support for "Hyperkey ⌘⌥⌃⇧" remappers (Karabiner, Caps Lock remaps, etc.).
- **Smart Adaptive Posting**: Integrates smart layout switches that automatically set defaults depending on your posting frequency, with standard toggles for "Post Now" and "Add to Buffer Schedule" to prevent workflow confusion.
- **Clipboard & Media Drag-and-Drop**: Easily copy and paste image/video files directly into your draft, or drag-and-drop files directly from Finder, Safari, or Photoshop.
- **Fully Accessible Native Interface**: Clean, right-aligned preference grid with crisp high-contrast typography that beautifully adapts to native macOS Light Mode and Dark Mode system-wide.
- **Smart Emoji Autocomplete**: Type :emojiname: inside the composer to get instant emoji autocompletion suggestions. Type : to see your most recently used emojis.
- **Automatic Threading**: Exceeding character limits? The composer automatically splits and threads posts based on platform-specific rules (280 for X, 300 for Bluesky, 500 for Mastodon & Threads).
- **GitHub Auto-Updates**: Features a native update check panel that automatically queries GitHub Releases and lets you download the latest installer with a single click.

---

## How It Works with the Buffer API

Buffer for Mac connects directly to your Buffer account using a Personal Access Token. 

### How to obtain your token:
1. Log in to your Buffer Dashboard at publish.buffer.com.
2. Go to the Buffer Developer Center at https://buffer.com/developers.
3. Create a new personal API application.
4. Copy the generated Access Token (OAuth Bearer Token).
5. Open Buffer-Mac Preferences > Accounts, paste your token, and click Verify.

*Your token is securely stored on your machine using the macOS Keychain, ensuring your login credentials remain encrypted and safe at all times.*

---

## Installation & Setup

Since this application is developed as an open-source utility and is not signed using a paid Apple Developer certificate, macOS Gatekeeper will show a warning upon first run. Installing and running is simple:

### Step 1: Download & Install the DMG
1. Download the latest `Buffer-Mac.dmg` using the link above.
2. Double-click the downloaded `.dmg` file to mount it.
3. Drag the BufferMenubar app icon into your Applications folder.

### Step 2: Authorise Gatekeeper
Because the app is unsigned, macOS will block double-clicking it for the first time. To launch:
1. Open your /Applications folder in Finder.
2. **Right-click (or Control-click)** the BufferMenubar application and select Open.
3. A confirmation dialogue will appear. Click Open to authorise it permanently.
4. *Alternatively*, open System Settings > Privacy & Security, scroll down to the Security section, and click "Open Anyway" to authorise launch.

---

## Contributing & Local Development

This project is built using Swift and SwiftUI in a modern Swift Package Manager (SPM) layout.

### Compiling manually:
```bash
# Clone the repository
git clone https://github.com/j4ckxyz/Buffer-Mac.git
cd Buffer-Mac

# Compile the project
swift build -c release

# Compile the package and copy to /Applications
./build_app.sh

# Or generate a native installer DMG
./build_dmg.sh
```

---

## Licence

This project is released under the [MIT Licence](LICENSE).

# QuIt

A macOS menu bar app for quickly quitting multiple applications with smart auto-quit functionality.

## Screenshots
<img width="392" height="400" alt="CleanShot 2568-12-06 at 15 54 10" src="https://github.com/user-attachments/assets/a8479da3-a3ad-4e94-ba1b-2cc2f8820c12" />
<img width="1824" height="1688" alt="CleanShot 2568-12-07 at 00 44 57@2x" src="https://github.com/user-attachments/assets/dfc75a3d-c4de-4634-8cad-b84c9a5bc8d0" />
<img width="1824" height="1688" alt="CleanShot 2568-12-07 at 00 45 06@2x" src="https://github.com/user-attachments/assets/cef6e720-ba5e-4294-aad3-3723b706925c" />
<img width="1824" height="1688" alt="CleanShot 2568-12-07 at 00 45 13@2x" src="https://github.com/user-attachments/assets/46174b47-9b19-414c-a41d-e9f628a832f4" />
<img width="1824" height="1688" alt="CleanShot 2568-12-07 at 00 45 57@2x" src="https://github.com/user-attachments/assets/baaf0b48-17fe-4436-be6b-a04f110feab2" />
<img width="1824" height="1688" alt="CleanShot 2568-12-07 at 00 45 35@2x" src="https://github.com/user-attachments/assets/0436cc15-d615-49e4-9b5d-843e5810a48a" />

## Updates

QuIt automatically checks for updates via GitHub Releases:
- **Auto-check**: Optional daily update checking
- **Manual check**: Settings → About → Check for Updates
- **GitHub Releases**: Download latest version from [releases page](https://github.com/moseiei132/QuIt/releases)

## Features

### Core Features
- **Quick Quit**: Select and quit multiple apps at once from the menu bar
- **Profile System**: Create and switch between different exclusion profiles
- **Menu Bar Integration**: Lightweight menu bar app with native macOS design

### Auto-Quit System
- **Automatic App Quitting**: Quit inactive apps after a configurable timeout
- **Default Timeout**: Set a global timeout for all apps (minimum 1 minute)
- **Per-App Custom Timeouts**: Configure individual timeouts for specific apps
- **Never Quit Option**: Set timeout to 0 to never quit specific apps
- **Only Custom Timeouts Mode**: Auto-quit only apps with custom timeout settings
- **Respect Exclude Apps**: Honor exclusion profiles when auto-quitting
- **Time Countdown**: See time remaining before apps are auto-quit
- **Notifications**: Get notified when apps are automatically quit

### Exclusion Management
- **Multiple Profiles**: Create unlimited exclusion profiles
- **Quick Profile Switching**: Switch profiles from the menu bar
- **Profile Duplication**: Clone existing profiles

## Building from Source

### Prerequisites

1. **Install Xcode** from the Mac App Store
2. **Install Command Line Tools**:
   ```bash
   xcode-select --install
   ```

### Build Steps

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd QuIt
   ```

2. **Open the project**:
   ```bash
   open QuIt.xcodeproj
   ```

3. **Build and run**:
   - Select the "QuIt" scheme in Xcode
   - Press `Cmd + R` to build and run
   - Or use the menu: **Product** → **Run**

### Command Line Build

Build from terminal:
```bash
xcodebuild -project QuIt.xcodeproj -scheme QuIt -configuration Release build
```

The built app will be in:
```
build/Release/QuIt.app
```

## Releasing

Releases are automated via GitHub Actions. The workflow builds, signs, and creates distribution files.

### Creating a Release

```bash
# 1. Update version
xcrun agvtool new-marketing-version 1.0.6

# 2. Commit and tag
git add .
git commit -m "Release v1.0.6"
git tag v1.0.6
git push origin main --tags
```

### Release Artifacts

| File | Purpose |
|------|---------|
| `QuIt_X.X.X.dmg` | Installer with Applications shortcut |
| `QuIt.app.zip` | For in-app OTA updates |

## Usage

1. **Launch QuIt** - The app appears in your menu bar
2. **Click the menu bar icon** to see running apps
3. **Select apps** to quit and click "Quit Apps"
4. **Open Settings** to configure auto-quit and exclusions
5. **Create profiles** to manage different exclusion sets

## Permissions

QuIt requires the following permissions:
- **Accessibility**: To monitor and quit applications
- **Notifications**: To show auto-quit alerts

Grant these in **System Settings** → **Privacy & Security**.


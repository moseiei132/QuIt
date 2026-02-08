# QuIt

A macOS menu bar app for quickly quitting multiple applications with smart auto-quit functionality.

## Screenshots

<img width="392" height="400" alt="CleanShot 2568-12-06 at 15 54 10" src="https://github.com/user-attachments/assets/a8479da3-a3ad-4e94-ba1b-2cc2f8820c12" />
<img width="1824" height="1688" alt="CleanShot 2568-12-07 at 00 44 57@2x" src="https://github.com/user-attachments/assets/dfc75a3d-c4de-4634-8cad-b84c9a5bc8d0" />
<img width="1824" height="1688" alt="CleanShot 2568-12-07 at 00 45 06@2x" src="https://github.com/user-attachments/assets/cef6e720-ba5e-4294-aad3-3723b706925c" />
<img width="1824" height="1688" alt="CleanShot 2568-12-07 at 00 45 13@2x" src="https://github.com/user-attachments/assets/46174b47-9b19-414c-a41d-e9f628a832f4" />
<img width="1824" height="1688" alt="CleanShot 2568-12-07 at 00 45 57@2x" src="https://github.com/user-attachments/assets/baaf0b48-17fe-4436-be6b-a04f110feab2" />
<img width="1824" height="1688" alt="CleanShot 2568-12-07 at 00 45 35@2x" src="https://github.com/user-attachments/assets/0436cc15-d615-49e4-9b5d-843e5810a48a" />

## Features

- **Quick Quit**: Select and quit multiple apps at once from the menu bar
- **Profile System**: Create and switch between different exclusion profiles
- **Scheduled Profiles & Templates**: Auto-switch profiles or launch app templates at specific times
- **Auto-Quit System**: Automatically quit inactive apps after configurable timeout
  - Global or per-app timeout settings
  - "Only Custom Timeouts" mode for selective auto-quit
  - Never quit specific apps (timeout = 0)
- **Menu Bar Integration**: Lightweight native macOS design

## Installation

### Option 1: Download Release (Recommended)

1. Download the latest `QuIt_X.X.X.dmg` from [Releases](https://github.com/moseiei132/QuIt/releases)
2. Open the DMG and drag QuIt to Applications
3. **First launch**: Right-click QuIt → **Open** (since the app is not notarized)
4. Click **Open** when macOS warns about unverified developer

> **Why this warning?** QuIt is not notarized with Apple. This is safe - the source code is available for inspection. Future releases may include notarization.

### Option 2: Build from Source

1. Install Xcode and Command Line Tools:
   ```bash
   xcode-select --install
   ```

2. Clone and build:
   ```bash
   git clone <repository-url>
   cd QuIt
   open QuIt.xcodeproj
   ```

3. Press `Cmd + R` to build and run

## Usage

1. **Launch QuIt** - Icon appears in menu bar
2. **Click icon** to see running apps
3. **Select apps** and click "Quit Apps"
4. **Settings** → Configure auto-quit, profiles, and alarms
5. **Alarms tab** → Schedule profile switches or template launches

## Permissions Required

Grant these in **System Settings** → **Privacy & Security**:
- **Accessibility**: Monitor and quit applications
- **Notifications**: Auto-quit alerts and alarm notifications

## Updates

QuIt checks for updates automatically (optional):
- **Auto-check**: Daily (configurable in Settings → About)
- **Manual check**: Settings → About → Check for Updates

## License

MIT License - see [LICENSE](LICENSE) file for details.

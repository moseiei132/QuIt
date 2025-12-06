# QuIt

A macOS menu bar app for quickly quitting multiple applications with smart auto-quit functionality.

## Screenshots
<img width="392" height="400" alt="CleanShot 2568-12-06 at 15 54 10" src="https://github.com/user-attachments/assets/a8479da3-a3ad-4e94-ba1b-2cc2f8820c12" />
<img width="1824" height="1688" alt="CleanShot 2568-12-06 at 15 55 04@2x" src="https://github.com/user-attachments/assets/9f649eeb-19fd-41db-8bb5-1d54246feaec" />
<img width="1824" height="1688" alt="CleanShot 2568-12-06 at 15 55 17@2x" src="https://github.com/user-attachments/assets/d682e3fc-f2ee-4080-ad07-bf0d20f69c00" />
<img width="1824" height="1688" alt="CleanShot 2568-12-06 at 15 55 53@2x" src="https://github.com/user-attachments/assets/84c3c571-222e-4fab-870c-30622779a8d5" />
<img width="1824" height="1688" alt="CleanShot 2568-12-06 at 15 56 11@2x" src="https://github.com/user-attachments/assets/49e6cb70-20a7-4df0-8da2-ef2a207b42fd" />
<img width="792" height="404" alt="CleanShot 2568-12-06 at 16 37 23@2x" src="https://github.com/user-attachments/assets/6e04dc26-8ca7-4dea-aa84-8f8850cef005" />


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


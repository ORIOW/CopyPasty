# CopyPasty

English | [简体中文](README.md)

A lightweight macOS clipboard history tool that lives in your menu bar, so you can always get back what you just copied.

![platform](https://img.shields.io/badge/platform-macOS%2026+-lightgrey) ![framework](https://img.shields.io/badge/framework-SwiftUI%20%2B%20AppKit-blue) ![dependencies](https://img.shields.io/badge/dependencies-none-success)

## Features

### Clipboard History
- Lives in the menu bar and automatically records **text, links, images, and files** you copy
- Keeps up to 20 items — click to copy back, right-click to delete, one-click clear
- Panel height adapts to content with scrolling overflow; light/dark mode follows the system

### Media Previews
- **Images**: thumbnail preview, click to copy the original
- **Audio** (mp3 / wav / m4a / aac / flac / aiff / caf): full waveform + file name
- **Video** (mp4 / mov / m4v / avi / mkv / webm, etc.): frame thumbnail with a play button

### Sensitive Info Protection
- Automatically detects **passwords, API keys, and bank card numbers** (including `KEY=sk-xxx` config lines, JWTs, long hex strings, high-entropy tokens, etc.)
- Matching records are **masked automatically**, and the original text is stored **AES-GCM encrypted** with the key kept in the system Keychain
- A "?" button on each record unmasks after confirmation; a 🔒 button re-masks
- Encryption can be toggled globally in Settings, applying to existing records as well
- Clicking a masked record still copies the original text

### Also
- Launch at login (toggle in Settings), clear history on quit, in-app restart
- First-launch onboarding (re-openable from Settings)

## Installation

Download the latest DMG from [Releases](https://github.com/ORIOW/CopyPasty/releases), open it, and drag CopyPasty into Applications.

**First launch**: if macOS says the developer can't be verified, **right-click the app → Open** (or go to System Settings → Privacy & Security → "Open Anyway"). The app is not notarized (no Apple Developer Program) — this is expected and only needs to be done once.

**Keychain prompt**: with encryption enabled, macOS may show a Keychain authorization dialog (once or twice) on first use — click "Always Allow".

## Privacy

- **All data stays on your machine**: history in local preferences, images/waveforms in the local app directory, the encryption key in your local Keychain
- **Zero network access**: the app runs fully offline
- The Keychain authorization only covers the single encryption-key item CopyPasty creates — nothing else in your Keychain is touched

## Building from Source

Requirements: macOS 26+, Xcode (with the macOS 26 SDK).

```bash
git clone https://github.com/ORIOW/CopyPasty.git
open CopyPasty.xcodeproj   # Cmd+R in Xcode to run
```

To build a DMG (version is read from the project automatically, output goes to `build/`):

```bash
./Scripts/make_dmg.sh
```

Tech stack: SwiftUI + AppKit + AVFoundation + CryptoKit, with **zero third-party dependencies**.

## Project Structure

```
CopyPasty/
├── CopyPastyApp.swift      # App entry point & lifecycle
├── ClipboardMonitor.swift  # Pasteboard polling, media preview generation
├── ClipboardHistory.swift  # Data model, history manager, on-disk image store
├── SensitiveDetector.swift # Sensitive string detector + AES-GCM crypto
├── StatusBarManager.swift  # Menu bar UI: history / settings / about
└── OnboardingView.swift    # First-launch onboarding
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md). Version format: `major.minor.patch.YYMMDD_stage`.

## License

[MIT](LICENSE) © 2026 Deng Jiawei

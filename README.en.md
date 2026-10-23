<p align="center"><img src="resources/branding/shark.png" width="110" alt="L99 for Mac shark logo"></p>

# AULA L99 for Mac

**Configure your AULA L99 keyboard on macOS.** An independent, free, open-source Mac app for key assignments, macros, RGB lighting, screen images, GIFs, and live system data over USB.

[English](README.md) · [Русский](README.ru.md) · [简体中文](README.zh-Hans.md)

[![Release](https://img.shields.io/github/v/release/AxiraDev/L99ForMac?include_prereleases&label=release)](https://github.com/AxiraDev/L99ForMac/releases/tag/v0.10.1)
[![License: GPLv3](https://img.shields.io/badge/license-GPLv3-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black)](#compatibility)
[![Apple Silicon](https://img.shields.io/badge/Apple-Silicon-00b8df)](#compatibility)
[![Downloads](https://img.shields.io/github/downloads/AxiraDev/L99ForMac/total?label=asset%20downloads)](https://github.com/AxiraDev/L99ForMac/releases)
[![Stars](https://img.shields.io/github/stars/AxiraDev/L99ForMac?style=flat)](https://github.com/AxiraDev/L99ForMac/stargazers)

## Download for macOS

### [Download L99 for Mac — Apple Silicon DMG](https://github.com/AxiraDev/L99ForMac/releases/download/v0.10.1/L99-for-Mac-macOS-arm64.dmg)

[Release notes and checksums](https://github.com/AxiraDev/L99ForMac/releases/tag/v0.10.1) · [Project website](https://axiradev.github.io/L99ForMac/) · [Report a problem](https://github.com/AxiraDev/L99ForMac/issues/new/choose)

This is **public beta 0.10.1**. The app has been tested with a real AULA L99, but broader hardware and macOS testing is still needed. No Apple Developer subscription is required to use it.

1. Download and open the DMG.
2. Drag **L99 for Mac** into **Applications**.
3. Open it and connect the keyboard with a USB data cable in wired mode.
4. The app reads the keyboard configuration. Make changes, then click **Apply to keyboard**.

The app is ad-hoc signed and is **not Apple-notarized**. If macOS blocks the first launch and you trust the download, use **System Settings → Privacy & Security → Open Anyway** for this app. [Apple's instructions](https://support.apple.com/en-us/102445). Your Mac's organization policy may restrict this option.

## What you can do

| Feature | What it does |
|---|---|
| Key assignments | Configure main and Fn layers, combinations, media actions, disabled keys, and macro bindings. |
| Macros | Record keys in the app, edit press/release actions, add delays and repetitions, and write macros to keyboard memory. |
| RGB lighting | Set effects, colors, brightness, speed, direction, and individual key colors. |
| IPS display | Upload PNG/JPEG images and GIF animations of up to 200 frames; fit, fill, stretch, or rotate them. |
| Real-time Data | Send Mac time/date, CPU/GPU load, CPU temperature when available, and humidity fixed at 0. |
| Music visualization | React to Mac system audio with the keyboard lighting and the wave in the L99 Play screen. |
| Profiles | Save and restore local profiles, import/export JSON, and verify written settings by reading them back. |
| Languages | Switch between English, Russian, and Simplified Chinese, or follow macOS. |

After an image or GIF upload, leave and reopen the corresponding page on the keyboard screen. Keep the app open for real-time data and music visualization.

## Compatibility

- **Keyboard:** AULA L99, connected in wired USB mode.
- **Mac:** Apple Silicon. No Intel build is provided.
- **System:** macOS 14 or later; music visualization needs **macOS 14.2 or later** and permission to capture system audio.
- **Confirmed on hardware:** Photo Frame, GIF playback, live metrics, audio-reactive lighting and screen wave, Play controls, F12 macros/repeats, and an Fn+F12 macro with Shift and a delay.
- **Still needs wider testing:** other assignments/effects, per-key colors, wallpaper, settings persistence, unplugging during transfers, sleep/wake, and other keyboard firmware/Mac models.
- **Not supported:** firmware flashing, Bluetooth configuration, and configuration through the 2.4 GHz receiver.

This is a configuration app using macOS USB interfaces; it does not install a kernel extension. It is not affiliated with or endorsed by AULA. [Detailed verification](VERIFICATION.md) · [Roadmap](ROADMAP.md).

## FAQ

**Is there an AULA L99 driver for Mac?**

This project provides an unofficial macOS alternative for configuring the AULA L99. It implements USB configuration in Rust and SwiftUI; it does not run or bundle the Windows driver.

**Does this work with an AULA F75, F99, or another keyboard?**

Only the **L99** is supported. Do not assume other AULA models use the same protocol.

**Can I update the keyboard or screen firmware?**

No. Firmware updates are outside this beta's scope.

**Does the app record my audio or keystrokes?**

Music audio is processed locally and is not saved. Macro recording and the input test work only in the active app window. There is no usage telemetry or analytics SDK. The support button opens Boosty in your browser.

**Why does macOS block the app?**

The current release has a local signature, without a paid Developer ID certificate or notarization. See the first-launch instructions above; do not disable Gatekeeper globally.

## Help improve it

[Report a reproducible bug](https://github.com/AxiraDev/L99ForMac/issues/new?template=bug_report.yml), [suggest a feature](https://github.com/AxiraDev/L99ForMac/issues/new?template=feature_request.yml), or contribute a pull request. Include your Mac model, macOS version, and L99 firmware version if available. Please distinguish a keyboard acknowledgement from a visually confirmed result.

If the app helps you, a **GitHub star** makes it easier for other Mac owners to discover it. Feedback about what works on your setup is especially useful.

[Contributing](CONTRIBUTING.md) · [Maintainer guide](MAINTAINING.md) · [Code provenance](PROVENANCE.md).

## Support development

### [Support Axira Dev on Boosty](https://boosty.to/axira_dev/donate)

Donations are voluntary. Every app feature remains free. Payments take place on Boosty, outside the app.

## Build from source

Install Rust, Xcode Command Line Tools, and Python 3 for source checks and packaging. From the repository folder:

```sh
python3 scripts/check_localization.py
bash scripts/build.sh
bash scripts/test_configuration.sh
bash scripts/test_audio.sh
python3 scripts/package.py
```

For a DMG, install the build-only packages `ds-store==1.3.3` and `mac-alias==2.2.2`, then run `python3 scripts/package_dmg.py`. No Rust or Python installation is needed to run the downloaded app.

The source checkout keeps user profiles in `local-state/`; a standalone installation uses its own `Application Support/L99 for Mac` folder. Profiles and private research material are excluded from source and binary distributions.

## License

Copyright (C) 2026 L99 for Mac contributors.

**GNU General Public License v3.0 only** (`GPL-3.0-only`). You may use, modify, and redistribute the program under GPLv3. The program comes **without any warranty**. See [LICENSE](LICENSE).

Publish the corresponding source for the same release alongside any distributed app binary, without an additional charge. The release includes `L99-for-Mac-source.zip`; modified distributed versions must retain GPLv3 and provide their corresponding source. Previously granted rights on already distributed copies under another license are not revoked.

The release source does not include the manufacturer's executable code, firmware, artwork, fonts, or language files. [Provenance and limitations](PROVENANCE.md).

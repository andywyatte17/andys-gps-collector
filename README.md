# Flutter Dev Setup Guide (Mac, No Admin)

## 1. Install Flutter SDK

No admin needed — installs to your home directory.

```bash
# Download and extract to home directory
cd ~
curl -LO https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.29.2-stable.zip
unzip flutter_macos_arm64_3.29.2-stable.zip
rm flutter_macos_arm64_3.29.2-stable.zip
```

Add Flutter to your PATH. Add this to `~/.zshrc`:

```bash
export PATH="$HOME/flutter/bin:$PATH"
```

Then reload:

```bash
source ~/.zshrc
```

## 2. Install Android Studio

Download from https://developer.android.com/studio and drag to your
`~/Applications` folder (not `/Applications` — no admin needed).

Open Android Studio and go through the setup wizard. It will install:
- Android SDK
- Android SDK Command-line Tools
- Android SDK Build-Tools

The SDK installs to `~/Library/Android/sdk` by default (no admin needed).

Add to `~/.zshrc`:

```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
```

## 3. Accept Android Licenses

```bash
flutter doctor --android-licenses
```

Say `y` to all.

## 4. IDE Setup

Install the **Flutter** and **Dart** plugins in Android Studio:
- Android Studio > Settings > Plugins > search "Flutter" > Install

Alternatively, use **VS Code** with the Flutter extension.

## 5. Set Up a Physical Android Device

Since emulators can be slow and you're building a GPS app:

1. On your Android phone: Settings > About Phone > tap "Build number" 7 times
2. Settings > Developer Options > enable **USB Debugging**
3. Connect via USB and accept the debugging prompt on the phone

## 6. Verify Setup

```bash
flutter doctor
```

This will flag anything still missing. Common issues:
- **CocoaPods not installed**: Only needed for iOS, ignore for now
- **Chrome not installed**: Only needed for web, ignore for now
- **Xcode not installed**: Only needed for iOS, ignore for now

The key items to have green are **Flutter**, **Android toolchain**, and
**Connected device** (if your phone is plugged in).

## 7. Test It Works

```bash
flutter create test_app
cd test_app
flutter run
```

This should build and launch a demo app on your connected phone. Delete the
`test_app` folder afterwards.
# README

A simple Flutter (Android) app for doing some GPS recording. This is partly
a practical app I need, and partly an experiment in using Claude to write me
a useful app.

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

### Required Android SDK/NDK Versions

After the setup wizard, open **Android Studio > Settings > Languages &
Frameworks > Android SDK** and ensure the following are installed:

- **SDK Manager > SDK Platforms tab**: Install the latest Android API level
  (the project uses `flutter.compileSdkVersion` which tracks Flutter's default)
- **SDK Manager > SDK Tools tab**:
  - Android SDK Build-Tools (latest)
  - Android SDK Command-line Tools (latest)
  - **NDK (Side by side)**: version **27.0.12077973** (required by sqflite and
    path_provider plugins)

To install the NDK from the command line instead:

```bash
sdkmanager "ndk;27.0.12077973"
```

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

## Android Version Compatibility

The app uses Flutter's default Android SDK settings (via Flutter 3.29.2):

- **Minimum SDK**: 21 (Android 5.0 Lollipop)
- **Target SDK**: 35 (Android 15)
- **Compile SDK**: 35

The app should run on any Android device running **Android 5.0 (API 21) or higher**.
However, some features have higher effective requirements:

- **Background location** (`ACCESS_BACKGROUND_LOCATION`): requires API 29+ (Android 10).
  On older devices, foreground location still works.
- **Altitude/speed accuracy fields**: requires API 26+ (Android 8.0).
  On older devices these fields report 0.

# Flutter Dev (General)

## To Run

Ensure an emulator is running or device attached (USB).

```bash
cd gps_collector
flutter pub get
# or flutter pub update
flutter run
# or
flutter run --release
```

## To Build a Release APK

```bash
cd gps_collector
flutter build apk --release
```

The signed APK is output to `build/app/outputs/flutter-apk/app-release.apk`.

To build a split-per-ABI set (smaller per-device APKs):

```bash
flutter build apk --split-per-abi
```

This produces separate APKs for `arm64-v8a`, `armeabi-v7a`, and `x86_64`
under the same output directory.

## To Build an App Bundle (for Google Play)

```bash
flutter build appbundle --release
```

The `.aab` is output to `build/app/outputs/bundle/release/app-release.aab`.

## To Install a Release APK Directly

```bash
flutter install --release
# or manually:
adb install build/app/outputs/flutter-apk/app-release.apk
```

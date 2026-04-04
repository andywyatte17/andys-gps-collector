# gps_collector

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## ADB Wireless Debugging (Android)

To deploy and debug on an Android device over Wi-Fi (no USB cable needed):

### One-time setup (requires USB)

1. Connect phone via USB
2. Enable **Developer Options** on the phone (tap Build Number 7 times in Settings > About)
3. Enable **USB Debugging** in Developer Options
4. Enable **Wireless Debugging** in Developer Options
5. Run:
   ```bash
   adb tcpip 5555
   ```
6. Disconnect USB

### Connect wirelessly

1. Find phone's IP address: Settings > Wi-Fi > tap your network > IP address
2. Connect:
   ```bash
   adb connect <phone-ip>:5555
   ```
3. Verify:
   ```bash
   adb devices
   flutter devices
   ```

### Deploy and run

```bash
flutter run
```

### Reconnect after reboot

If the phone or Mac restarts, just reconnect:
```bash
adb connect <phone-ip>:5555
```

If that fails, you'll need USB again to run `adb tcpip 5555`.

### Android 11+ alternative (no USB needed)

On Android 11+, **Wireless Debugging** has a built-in pairing flow:

1. Enable **Wireless Debugging** in Developer Options
2. Tap **Pair device with pairing code** — note the IP:port and code
3. Run:
   ```bash
   adb pair <ip>:<pairing-port> <pairing-code>
   ```
4. Then connect using the IP:port shown under Wireless Debugging (different from the pairing port):
   ```bash
   adb connect <ip>:<port>
   ```

---

## Running Tests

Unit tests are located in the `test/` directory.

```bash
# Run all tests
flutter test

# Run a specific test file
flutter test test/y_label_values_test.dart

# Run with verbose output
flutter test --reporter expanded
```

### Test files

- `test/y_label_values_test.dart` — Tests for the speedometer y-axis label
  computation (`pickYStep` and `buildYLabelValues`). Covers boundary values,
  intermediate spacing, overlap prevention, inverted min/km axis, and
  various chart heights.

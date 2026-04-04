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

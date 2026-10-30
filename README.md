# DataFlow / Cross Processing Lab

Flutter demo for **Concurrency and Background Processing in Flutter: Isolates,
Event Loops, and Responsive Applications**. The same data-processing pipeline
runs on the main isolate, a one-shot isolate, or one reusable worker isolate.

## Clone and run

Use **Flutter 3.47.0 / Dart 3.13.0**, with Chrome for the web demo or an Android
SDK and a configured Android emulator/device for all three processing modes.

```sh
git clone https://github.com/pmhieu1801/Cross_platform.git
cd Cross_platform/midterm_crossplatform
flutter pub get
flutter devices
```

For Chrome (Main mode only):

```sh
flutter run -d chrome
```

For Android, replace `ANDROID_DEVICE_ID` with the ID shown by `flutter devices`:

```sh
flutter run -d ANDROID_DEVICE_ID
```

No account, API key, server, or external dataset is required. Generate data in
the app, or import the included CSV/JSON samples. See the
[project README](midterm_crossplatform/README.md) for tests, release builds,
architecture, and platform limits.

This repository contains application source, platform configuration, locked
dependencies, samples, tests, experiment data, and captured technical evidence.
Local recording scripts, packaging helpers, report drafts, and separately
prepared submission packages are kept outside version control.

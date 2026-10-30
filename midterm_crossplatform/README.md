# DataFlow / Cross Processing Lab

A Flutter demo comparing the same CPU-bound analysis on the main isolate,
a one-shot isolate (`Isolate.run()`), and one reusable worker (`Isolate.spawn()`).

## Requirements and setup

- Validated toolchain: **Flutter 3.47.0 / Dart 3.13.0**. The project requires
  Dart `^3.13.0`; an older Flutter SDK that bundles older Dart will not resolve it.
- Chrome for web, or Android Studio/Android SDK and an emulator or device for Android.
- Internet access on first setup to download Flutter/Gradle dependencies.
- On Windows, enable Developer Mode if Flutter reports that plugins require
  symlink support.

Run these commands **inside `midterm_crossplatform`**, not the repository root:

```sh
flutter --version
flutter doctor
flutter pub get
flutter devices
```

Keep `pubspec.lock` so dependencies resolve from the committed lock file.
There is no backend, login, API key, or machine-specific configuration to copy.
Flutter generates local SDK paths and Android Gradle wrapper files when needed.
Build directories and tool caches are intentionally excluded from Git.

## Run

Android: replace `ANDROID_DEVICE_ID` with the ID from `flutter devices`.

```sh
flutter run -d ANDROID_DEVICE_ID
```

For Android performance observations, use profile mode:

```sh
flutter run --profile -d ANDROID_DEVICE_ID
```

Chrome functional demo:

```sh
flutter run -d chrome
```

Android supports **Main, One-shot, and Persistent**. Chrome supports **Main
only**: isolate mode controls and benchmarks are disabled on web. `compute()`
also runs on the browser main thread, so generation, parsing, and processing
can delay browser input and animation. Start with the web default of 1,000 records.
Use Android for isolate comparisons. Do not compare debug timings with profile
or release timings.

Other platform folders are included as Flutter source scaffolding; their presence
alone does not establish that those platforms have been built or tested.

## Demo steps

1. Enter seed `42` and a record count such as `1000`, then select **Generate**.
2. Select **Main** and process the dataset.
3. On Android, process the same data with **One-shot** and **Persistent**;
   compare business results separately from timing metrics.
4. Select **Import CSV / JSON** and choose `assets/sample_data/sample.csv` or
   `assets/sample_data/sample.json` from the device/browser file picker.
5. Use the benchmark mode selectors, sizes, repetitions, and warm-up controls
   to run a sweep. Export actual records as CSV or JSON.
6. Check error recovery with an invalid record count or malformed import.

The sample files are file-picker fixtures, not bundled Flutter assets. Copy
one onto the Android device if you want to import it there. Generation works
without importing any file.

## Architecture and processing

```text
AnalyzerPage
  -> AnalyzerController (ChangeNotifier)
  -> BenchmarkRunner / ProcessingEngine
  -> MainIsolateEngine / OneShotIsolateEngine / PersistentIsolateEngine
  -> DataProcessor
  -> ProcessingResult + ProcessingMetrics
```

The page listens to controller notifications and rebuilds its UI. All three
engines use one shared pipeline:

```text
Validate -> filter Completed -> group by category -> aggregate
         -> sort by revenue descending -> statistics
```

Revenue is `quantity * price`. Main processes synchronously; One-shot uses
`Isolate.run()`; Persistent reuses one worker and exchanges requests/results
through ports with request IDs and completers. The persistent worker processes
requests sequentially and cleans up its ports on disposal.

CSV requires the following columns (order may vary); JSON accepts a root
array or an object containing a `records` array:

| Field | Value |
| --- | --- |
| `id` | Integer |
| `timestamp` | ISO-8601 date/time |
| `category`, `region`, `status` | Non-empty strings |
| `quantity` | Non-negative integer |
| `price`, `processingTime` | Non-negative finite numbers |

`processingTime` in an input record is a data attribute, not a measured runtime.
Empty datasets and malformed records are rejected.

Packages: `csv` parses CSV, `file_picker` handles import/export dialogs, and
`device_info_plus` supplies benchmark device metadata. Exact versions are in
`pubspec.lock`.

## Checks

```sh
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

The default suite includes native isolate tests. For focused browser coverage:

```sh
flutter test --platform chrome test/web_platform_flow_test.dart
```

The integration flow requires an Android target:

```sh
flutter test integration_test/analyzer_flow_test.dart -d ANDROID_DEVICE_ID
```

Automated tests do not replace manual file-picker/download checks or device
performance measurements.

## Android release APK

```sh
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`. Build output is not
committed. Install it with the device's package installer or Android SDK tools:

```sh
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The application ID is `com.example.midterm_crossplatform`; its launcher label is
**midterm_crossplatform**, and its screen title is **Cross Processing Lab**.
The release build uses the development signing key for the classroom sideloaded demo.

## Experiment data and evidence

The submission evidence is included in `experiments/` and `evidence/`:

- [Raw CSV exports](experiments/raw/README.md): the size sweep and a separate
  repeated-workload experiment.
- [Measured comparison](experiments/results/MEASURED_RESULTS.md): conditions,
  timing definitions, derived tables, source hashes, and interpretation limits.
- [Collection protocol](experiments/protocol.md): setup and reproduction steps.
- [Profiler captures](evidence/profiler/README.md) and
  [Android/Chrome screenshots](evidence/screenshots/README.md).
- [Source validation summary](evidence/tests/VALIDATION.md).

To repeat the size sweep on Android, use profile mode, seed 42, sizes
`25000,50000,100000,250000`, five recorded repetitions, one warm-up per
mode/size, and all three modes. Export the resulting CSV. For the separate
repeated-workload experiment, select One-shot and Persistent only, size
`100000`, ten repetitions, and one warm-up. Keep the exports separate and
record the actual device, SDK, build mode, app revision, and run conditions.

The existing timing exports were collected on an Android emulator, not a
physical phone. Original capture dates and exact committed experiment revisions
were not preserved. New runs can differ; do not relabel existing captures as
results from a new run or from today's validation.

## Scope and limitations

There is one persistent worker, no worker pool, streaming/chunking, task
cancellation, database, or OS-managed background service. Isolates do not
ensure work survives app suspension or termination. UI heartbeat values are
observations; use a profiler for frame timing. Report drafts, video scripts,
and packaging helpers are excluded from this repository. Captured experiments
support the report but are not application runtime dependencies.

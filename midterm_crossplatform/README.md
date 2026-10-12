# DataFlow: Concurrent Large Data Analyzer in Flutter

DataFlow is a three-week Midterm project for studying concurrency and background processing in Flutter. It runs one deterministic data-analysis pipeline in three execution modes so their responsiveness and runtime overhead can be compared without changing the business algorithm.

No benchmark or profiler claims are included in this repository unless they are backed by captured experiment artifacts.

## Course topic and Midterm scope

The course topic is **Concurrency and Background Processing in Flutter: Isolates, Event Loops, and Responsive Applications**.

The Midterm covers a synchronous main-isolate baseline, a one-shot isolate, one reusable persistent isolate, deterministic dataset generation, CSV/JSON import, raw benchmark export, UI responsiveness observation, and a reproducible evidence protocol. It intentionally excludes worker pools, multiple parallel workers, priorities, scheduling systems, backpressure, chunking, streaming huge files, advanced cancellation, database persistence, WorkManager, BGTaskScheduler, and other OS background-service integrations.

## Research questions

1. How does CPU-heavy work on the main isolate affect UI responsiveness?
2. How much responsiveness improvement and overhead does `Isolate.run()` introduce?
3. How does a persistent worker compare with a one-shot isolate for repeated workloads?
4. How do workload size and isolate message passing affect execution?
5. When are `async`/`await`, one-shot isolates, persistent isolates, and platform-managed background services appropriate?

## Architecture

```text
AnalyzerPage
  -> AnalyzerController / BenchmarkRunner
  -> ProcessingEngine
  -> MainIsolateEngine / OneShotIsolateEngine / PersistentIsolateEngine
  -> shared DataProcessor
  -> ProcessingResult
  -> ProcessingMetrics
  -> UI
```

`AnalyzerController` owns presentation state, loaded data, engine lifecycle, processing actions, and benchmark coordination. `BenchmarkRunner` adds reproducibility metadata and raw timing records. Every engine delegates business work to the same `DataProcessor`; timing metadata is kept separate from business-result equality.

## Processing pipeline

All modes execute the same locked pipeline:

```text
Validate
  -> Filter status == "Completed"
  -> Group by category
  -> Aggregate
  -> Sort by total revenue descending
  -> Statistics
```

Revenue is calculated as `quantity * price`. It is not stored as a `DataRecord` field.

## DataRecord schema

| Field | Type |
| --- | --- |
| `id` | `int` |
| `timestamp` | `DateTime` / ISO-8601 text when imported |
| `category` | `String` |
| `region` | `String` |
| `status` | `String` |
| `quantity` | `int` |
| `price` | `double` |
| `processingTime` | `double` |

Repository samples are available in [`assets/sample_data`](assets/sample_data). They are file-picker fixtures and are not registered as bundled Flutter assets.

## Processing modes

- **Main Isolate:** `MainIsolateEngine` calls the shared processor synchronously on Flutter's UI isolate. Its blocking behavior is deliberate and provides the jank baseline.
- **One-shot isolate:** `OneShotIsolateEngine` uses `Isolate.run()`. A temporary isolate performs one request and terminates, allowing one-shot startup and message-passing overhead to be studied.
- **Persistent isolate:** `PersistentIsolateEngine` creates exactly one reusable worker with `Isolate.spawn()` and communicates through `SendPort` and `ReceivePort`. It handles initialization, sequential requests, processing errors, unexpected exit, and idempotent cleanup.

`async`/`await` alone does not provide parallel CPU execution. A Dart isolate also is not an OS-managed background service and does not guarantee continued work after the operating system suspends or terminates the app.

## Prerequisites

- Flutter stable SDK and a supported target toolchain.
- Android Studio/Android SDK for Android development.
- macOS with Xcode for iOS builds and physical-iPhone performance collection.
- A connected device or configured emulator/simulator for platform runs.

The repository currently targets Dart `^3.13.0` in `pubspec.yaml`. The validated development toolchain for this revision is Flutter 3.47.0 with Dart 3.13.0. Confirm the active installation with:

```sh
flutter --version
dart --version
flutter doctor
```

## Setup and running

Install locked dependencies without removing `pubspec.lock`:

```sh
flutter pub get
```

Run in normal debug mode:

```sh
flutter run
```

Run a profile build for performance evidence:

```sh
flutter run --profile
```

Run an optimized release build:

```sh
flutter run --release
```

Use `flutter devices` and add `-d <device-id>` when more than one target is available. Debug timings must not be compared with profile or release timings.

## Dataset generation and import

To generate deterministic data in the application:

1. Enter a whole-number seed, such as `42`.
2. Enter the record count or select one of the preset sizes.
3. Select **Generate**.

The same seed and record count produce the same records in the same order. Keep both values unchanged across compared processing modes.

To test file import, select **Import CSV / JSON** and choose [`sample.csv`](assets/sample_data/sample.csv), [`sample.json`](assets/sample_data/sample.json), or another file that uses exactly the documented schema. JSON may be a root array or an object containing a `records` array; the included sample uses a root array.

## Tests and analysis

Run formatting, static analysis, and all unit/widget tests:

```sh
dart format .
flutter analyze
flutter test
```

List devices and run the integration flow on a selected target:

```sh
flutter devices
flutter test integration_test/analyzer_flow_test.dart -d <device-id>
```

Integration tests require a runnable target and are separate from the default `flutter test` suite.

## Android APK

Build a release APK with:

```sh
flutter build apk --release
```

Flutter writes the APK under `build/app/outputs/flutter-apk/`. Build output is intentionally ignored by Git.

## Reproducing benchmarks

Follow [`experiments/protocol.md`](experiments/protocol.md) before collecting any measurements. In summary:

1. Use the same physical device, Flutter build mode, app revision, seed, dataset size, configuration, warm-up policy, and recorded run count for each comparison.
2. Record Flutter/Dart versions, platform/device, OS, build mode, seed, workload size, repetitions, and warm-up policy.
3. Use the benchmark sweep to run controlled warm-ups and recorded executions. Warm-ups are not exported as result rows.
4. Export untouched CSV or JSON output from the app.
5. Collect Performance Timeline, Frame Chart, CPU Profile, and memory evidence from Flutter DevTools where required.

Store untouched benchmark exports and their session notes in [`experiments/raw`](experiments/raw). Store derived tables or charts in [`experiments/results`](experiments/results). Place genuine profiler captures, screenshots, and captured test logs under [`evidence`](evidence). Do not add fabricated measurements, screenshots, memory values, FPS values, or profiler output.

## Known Midterm limitations

- Only one persistent worker is used; there is no worker pool or parallel task scheduler.
- Processing is in-memory and does not stream or chunk very large files.
- There is no database persistence, advanced cancellation, pause/resume, or backpressure.
- The UI heartbeat is observational; formal frame evidence must be captured with DevTools.
- Performance varies by device, OS, build mode, workload, and thermal state. Results cannot be generalized without real evidence.
- iOS Simulator runs may support functional validation but must not be presented as iPhone performance evidence.
- Isolates are process-internal concurrency tools, not WorkManager/BGTaskScheduler-style background services. Work is not guaranteed to survive application suspension or termination.

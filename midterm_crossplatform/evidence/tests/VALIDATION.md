# Source validation summary

Date: 30 October 2026 (Asia/Bangkok). Host: Windows. Toolchain: Flutter 3.47.0,
Dart 3.13.0. These checks used an isolated clone populated with the application
source selected for this submission commit. Local packaging/video scripts,
report drafts, and captured benchmark artifacts were not needed for the checks.

| Check | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test integration_test` | Passed: 26 files checked, 0 changed. |
| `flutter --no-version-check analyze --no-pub` | Passed: no issues found. |
| `flutter --no-version-check test --no-pub` | Passed: 41 tests. |
| `flutter --no-version-check build apk --debug --no-pub` | Passed: debug APK built. |
| `flutter --no-version-check build web --no-pub` | Passed: web output built. |

Dependency resolution used the committed lock file and already cached packages.
On this Windows host, `flutter pub get --offline` resolved dependencies but
reported that plugin symlinks require Developer Mode. Subsequent checks above
used `--no-pub`; setup instructions document that prerequisite.

This note summarizes observed command results; raw console logs were not saved.
The Android device integration test and the focused test suite in an actual
Chrome browser were not rerun during this validation. The web build is a
compilation check, not proof of browser interaction or file-picker behavior.
No new release APK, benchmark, memory measurement, or physical-phone test was
produced by these checks. Earlier screenshots and measurements are separate
evidence and must not be relabelled with this validation date.

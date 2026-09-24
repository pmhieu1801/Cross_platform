# Concurrency Lab — Topic 6: Flutter Midterm Demo

> **Course:** Cross-Platform Development  
> **Topic:** Concurrency and Background Processing in Flutter: Isolates, Event Loops, and Responsive Applications  
> **Member (this repo):** Flutter UI · App States · Persistent Isolate · Worker Lifecycle · UI Heartbeat

---

## 📋 Requirements

| Tool | Version |
|---|---|
| Flutter | 3.47.0 (stable) |
| Dart | 3.7.x |
| macOS | 12+ (primary target) |
| Android SDK | 36.0.0 (optional) |
| Xcode | 16+ (for macOS/iOS build) |

---

## 🚀 Quick Start

### 1. Clone & Install dependencies
```bash
git clone <your-repo-url>
cd Midterm
flutter pub get
```

### 2. Run on macOS (recommended for demo)
```bash
flutter run -d macos
```

### 3. Run on Android
```bash
flutter run -d android
```

### 4. Run on Chrome (Web)
```bash
flutter run -d chrome
```

> ⚠️ **Note for macOS:** If you encounter a code-signing error (iCloud Drive / path with spaces),
> copy the project to `~/Developer/` first:
> ```bash
> cp -R . ~/Developer/midterm_flutter
> cd ~/Developer/midterm_flutter
> flutter run -d macos
> ```

---

## 🧪 Demo Scenarios (Reproduce in Order)

### Scenario A — Import Dataset
1. Launch the app
2. Observe **UI Thread Monitor** (left sidebar) — FPS should show ~60, sparkline green
3. Click **"Import Mock Data"**
4. Observe: status changes `loading → ready`, log shows `compute() isolate spawned`
5. FPS stays ~60 throughout (dataset generated in a one-shot isolate, not main thread)

### Scenario B — Run with Isolate (Responsive UI)
1. After import, click **"Run with Isolate"**
2. Observe:
   - FPS stays at **~60 (SMOOTH)** throughout all 5 pipeline steps
   - Worker Lifecycle panel: `Spawn → Processing → Complete`
   - Log shows timestamped progress messages from the background isolate
3. Pipeline finishes in ~5 seconds with results

### Scenario C — Cancel Mid-Pipeline
1. Click **"Run with Isolate"**
2. During step 2 or 3, click **"Halt Isolate"**
3. Observe: log shows `ABORT: CancelCommand sent via SendPort`
4. App state transitions to `cancelled`

> **Teaching moment:** If cancel is pressed during a busy-wait step, the cancellation
> takes effect at the *next checkpoint* — demonstrating that Dart isolates process
> messages only when their event loop is free.

### Scenario D — Run on UI Thread (Jank Demo)
1. Click **Reset**, then click **"Run on UI Thread"**
2. Observe **immediately**:
   - UI **freezes** for ~5 seconds (buttons unresponsive, no frame updates)
   - FPS drops to **0 (FROZEN)** — sparkline shows a red dip
3. After 5 seconds, UI unfreezes and FPS recovers to ~60
4. Compare results panel: `mode: Main Thread (Blocked), jank_duration_ms: 5000`

> Take a screenshot of the sparkline **within 30 seconds** of the freeze to capture
> the red dip before it scrolls out of the 30-sample history window.

---

## 🏗️ Architecture Overview

```
lib/
├── main.dart                    # App entry point
├── ui/
│   ├── dashboard_screen.dart    # Main screen + DashboardState machine
│   └── ui_heartbeat.dart        # Real-time FPS counter (SchedulerBinding)
├── workers/
│   └── data_analyzer_worker.dart # Persistent Isolate wrapper
└── models/
    └── worker_message.dart      # Typed message protocol (sealed classes)
```

### Key Design Decisions

| Decision | Rationale |
|---|---|
| `Isolate.spawn()` (persistent) | Avoids spawn overhead for repeated tasks; supports cancel |
| `compute()` for dataset generation | One-shot, no progress needed; simpler API |
| `sealed class` messages | Type-safe IPC without dynamic dispatch |
| `SchedulerBinding.addPersistentFrameCallback` | Measures real rendered FPS, not estimated |
| `AnimationController.repeat()` in heartbeat | Keeps Flutter's rendering pipeline active for accurate FPS measurement |
| `DashboardState` enum | Single source of truth; eliminates inconsistent boolean combinations |

---

## 🔬 Running Tests

```bash
flutter test
```

---

## 📦 Build Release Artifact

### macOS `.app`
```bash
flutter build macos --release
# Output: build/macos/Build/Products/Release/ex1.app
```

### Android APK
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## ⚠️ Known Limitations

- **Cancel checkpoint delay:** `CancelCommand` is only processed between pipeline steps. If a step is executing a busy-wait, cancellation is deferred until the next checkpoint.
- **Sparkline window:** FPS history shows last 30 seconds. The 5-second jank dip will scroll out of view after ~25 seconds of recovery.
- **Web platform:** `Isolate.spawn()` is not supported on Flutter Web; `compute()` falls back to a microtask. The jank demo on Web will not freeze the UI since the browser uses Web Workers.
- **Mock pipeline:** Steps 1–5 simulate work with busy-wait delays rather than real data transformations. Real computation is handled by the teammate's `DataProcessor` module.

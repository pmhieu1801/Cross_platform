# DataFlow Midterm Benchmark Protocol

This protocol defines how to collect reproducible evidence for the Midterm research questions. It does not contain measured results. Only measurements produced by an actual run may be placed in `raw/`, `results/`, or `evidence/`.

## 1. Session record

Before each experiment session, create a plain-text or Markdown session note beside the raw export and record:

- date and a unique session ID;
- Flutter version (`flutter --version`);
- Dart version (`dart --version`);
- target platform and exact physical device model;
- OS name and version;
- Flutter build mode (`profile` is recommended for performance evidence);
- deterministic dataset seed;
- workload size or ordered list of sizes;
- number of recorded repetitions;
- number of non-recorded warm-up runs;
- app revision (`git rev-parse HEAD`);
- any relevant configuration, such as power mode or whether the device was connected to a charger.

Do not compare timings collected with different session settings as though they came from one controlled experiment.

## 2. Controlled variables

Within one comparison, keep all of the following identical:

- the generated dataset, deterministic seed, and dataset size;
- the shared `DataProcessor` business algorithm and application revision;
- the physical device and OS configuration;
- the Flutter build mode;
- the application configuration;
- the recorded run count;
- the warm-up policy.

Close unrelated high-load applications, allow the device to reach a stable temperature, and use the same power conditions for every compared mode. Change only the processing mode or the workload size required by the experiment.

The locked business pipeline is Validate -> Completed filter -> category group -> aggregate -> revenue-descending sort -> statistics. Never add artificial busy-wait work to one processing mode. Every mode must process the same records through the shared `DataProcessor`.

## 3. Warm-up and run numbering

The benchmark screen exposes `Warm-up runs`. A controlled warmed comparison should use at least one warm-up per processing mode and dataset size. Warm-up executions use the same generated records and engine as recorded executions, but are discarded: they do not create export rows and do not consume run numbers. Recorded run numbers therefore start at 1 for each mode and remain consecutive across the configured sizes.

The exported `warmUpRuns` column identifies the policy applied to every recorded row. Use `0` only for a clearly labelled cold-start series. Do not mix cold and warmed rows in the same comparison. Because a warm-up initializes the persistent worker, collect a separate zero-warm-up cold-start series when persistent-isolate startup cost is required; use the warmed series for steady-state repeated-task comparisons.

## 4. Common collection procedure

1. Check out and record the exact Git revision. Confirm tests and static analysis pass.
2. Record the session metadata listed above.
3. Build and run the app in the selected mode. Use the same build mode for the entire comparison.
4. Enter the fixed seed, sizes, repetitions, and warm-up count. Do not regenerate with different settings between compared modes.
5. Start DevTools before the measured sequence when profiler evidence is required.
6. Run the benchmark sweep without interacting with unrelated applications.
7. Export raw CSV or JSON directly from the app into `experiments/raw/`. Do not edit raw exports.
8. Save DevTools exports or screenshots with the session ID under the matching `evidence/` folder.
9. Verify the export contains the expected mode, seed, size, build mode, warm-up count, and consecutive run numbers.
10. Derive any later tables from the preserved raw files. Median and P95 are optional and must be calculated only from real data.

Suggested artifact names use `<session>-<experiment>-<platform>-<mode>-<size>`, for example `2026-10-12-exp1-android-main-100000.csv`. A filename is only an example, not a measurement.

## 5. Experiment 1: main isolate vs `Isolate.run`

Compare `MainIsolateEngine` with `OneShotIsolateEngine` on the same dataset.

For each mode, record:

- total wall-clock execution time;
- processing time;
- isolate startup/message-passing overhead where applicable;
- UI responsiveness during processing;
- Performance Timeline and Frame Chart evidence, including janky frames;
- memory evidence where practical.

Use the same seed, workload size, warm-up count, and recorded repetition count for both modes. The main-isolate implementation must remain synchronous because it is the blocking baseline.

## 6. Experiment 2: workload scaling

Start with these candidate sizes:

- 25,000
- 50,000
- 100,000
- 250,000

Run every selected processing mode with the same seed, repetitions, warm-up policy, build, and device. Compare raw timing and UI-responsiveness evidence as workload size increases.

After a real pilot, the sizes may be increased if the main isolate does not visibly produce jank. Record the revised sizes before collection and apply them to every compared mode. Do not manufacture a stronger effect with mode-specific delays or artificial busy-wait work.

## 7. Experiment 3: repeated workload

Compare `OneShotIsolateEngine` (`Isolate.run`) with `PersistentIsolateEngine` using the same dataset repeatedly. Use 10 recorded tasks per mode unless the session record declares another equal count.

Collect and compare:

- total time across all repeated tasks;
- per-run processing time;
- one-shot startup/message-passing overhead;
- persistent-worker startup and its amortization across repeated tasks;
- memory evidence;
- UI responsiveness.

The persistent mode must reuse one worker throughout its recorded sequence. For startup analysis, preserve a separately labelled cold series with zero warm-ups. For steady state, use the same non-zero warm-up policy for both modes.

## 8. Experiment 4: cross-platform functional validation

Validate dataset generation/import, all three processing modes, business-result equivalence, repeat processing, benchmark export, and safe shutdown on Android and iOS when hardware is available. Record the device and OS for each validation.

An iOS Simulator may be used for functional checks only. Do not claim iPhone performance, responsiveness, memory, or comparative timing from Simulator measurements. If physical iOS hardware is unavailable, report that limitation explicitly instead of inferring results.

## 9. DevTools evidence collection

Use a profile build on the target device and connect Flutter DevTools.

### Performance Timeline and Frame Chart

1. Open **Performance** and clear existing events.
2. Enable frame recording, then run exactly the configured workload.
3. Stop recording immediately after completion.
4. Preserve the timeline export when available and capture the Frame Chart showing UI/raster frame durations and any janky frames.
5. Label the artifact with mode, size, run, device, and session ID.

### CPU Profile

1. Open **CPU Profiler**, clear prior samples, and begin recording.
2. Run one declared workload without unrelated interaction.
3. Stop recording and preserve the profile/export or screenshot.
4. Confirm the label distinguishes main-isolate, one-shot, and persistent runs.

### Memory

1. Open **Memory** and allow the baseline to stabilize.
2. Note or capture memory immediately before the workload.
3. Run the declared workload and capture peak/after-run evidence where practical.
4. Repeat under the same conditions for the comparison mode.

DevTools screenshots, profiler exports, memory values, FPS claims, and result tables must come from actual collection. Empty evidence folders are placeholders, not evidence.

## 10. Interpretation boundaries

`async`/`await` schedules asynchronous continuations but does not move CPU-heavy work off the UI isolate. A Dart isolate is not an OS background service, and isolate use does not guarantee execution after OS suspension or termination. Conclusions must stay within the measured device, build, dataset, and run configuration.

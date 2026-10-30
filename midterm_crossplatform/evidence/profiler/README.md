# Profiler evidence

Preserved Flutter DevTools captures from the Android emulator in profile mode,
with a 250,000-record workload. Filenames identify Main, One-shot, or Persistent.

- `*-frames.png` and `*-timeline.json`: frame chart images and performance exports.
- `*-cpu.png` and `*-cpu.json`: Main and Persistent CPU profiler evidence.

CPU captures support identifying where `DataProcessor` executes. Their durations
and sampling settings differ, so sample durations are not comparable execution
benchmarks. Frame recording windows also differ; do not directly rank their
average FPS or jank counts. No quantitative memory measurement is included.
The original capture date and exact committed capture revision were not recorded.
See `../../experiments/results/MEASURED_RESULTS.md` for timing results and limits.

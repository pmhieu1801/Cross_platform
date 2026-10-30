# Measured comparison notes

These results are calculated from genuine preserved CSV exports, not new experiments. Use these notes for the demonstration video and later report.

## Conditions and metric definitions

Android 17/API 37 x86_64 emulator (sdk_gphone16k_x86_64), Flutter 3.47.0, Dart 3.13.0, profile mode, seed 42, one warm-up per mode and size. Host CPU/RAM, load, thermal/power state and a committed experiment revision were not preserved in session notes; the working tree contains local changes. These gaps limit reproducibility and generalization.

Processing time measures the shared processor in its execution isolate. Total time measures the engine call, including applicable scheduling and transfer costs. Generation, import, warm-ups and UI rendering are outside these timing columns. Source microseconds are divided by 1,000 to obtain milliseconds. Medians are calculated separately for each mode and workload size.

## Workload scaling

| Records | Mode | Runs | Median processing (ms) | Median total (ms) |
| ---: | --- | ---: | ---: | ---: |
| 25,000 | Main | 5 | 8.722 | 8.748 |
| 25,000 | One-shot | 5 | 22.967 | 78.721 |
| 25,000 | Persistent | 5 | 7.689 | 38.555 |
| 50,000 | Main | 5 | 19.607 | 19.625 |
| 50,000 | One-shot | 5 | 43.132 | 84.052 |
| 50,000 | Persistent | 5 | 23.634 | 84.974 |
| 100,000 | Main | 5 | 30.761 | 30.783 |
| 100,000 | One-shot | 5 | 109.635 | 254.942 |
| 100,000 | Persistent | 5 | 76.320 | 230.978 |
| 250,000 | Main | 5 | 90.735 | 90.778 |
| 250,000 | One-shot | 5 | 195.648 | 685.140 |
| 250,000 | Persistent | 5 | 215.963 | 618.456 |

## Repeated 100,000-record workload

Ten recorded tasks per mode after one warm-up. The sum below is the sum of exported per-task total times, not independently timed whole-session wall time. Persistent startup during warm-up is excluded; this is a warmed comparison, not a cold-start comparison.

| Mode | Tasks | Median processing (ms) | Median total (ms) | Sum of task totals (ms) |
| --- | ---: | ---: | ---: | ---: |
| One-shot | 10 | 89.747 | 282.686 | 2851.587 |
| Persistent | 10 | 90.300 | 255.987 | 2598.064 |

## Interpretation boundaries

- The size-sweep median total is lower for Main than either isolate mode at all four sizes. Offloading does not establish faster completion for this implementation and emulator.
- Responsiveness is a separate question. The main baseline performs CPU work synchronously on main. The existing CPU profiles show DataProcessor on main for Main mode and on dataflow-persistent-worker for Persistent mode. This supports execution placement; it does not quantify a responsiveness improvement.
- Frame capture windows differ. Do not rank their average FPS or jank counts as a controlled comparison or attribute raster jank to the business processor without supporting tracing.
- The One-shot isolateStartupTimeMicros field is total minus processing time, so it includes more than spawn time. Persistent zero startup in warmed runs does not mean workers cost nothing to start. Do not compare these fields as isolated startup measurements.
- CPU profiles have different durations and sampling settings. Their sample times are not comparable engine completion times. Memory was not measured. All timings are emulator observations, not physical-phone performance or evidence of OS background execution.
- Compare the modes within each recorded experiment; do not merge the size-sweep and repeated-workload rows as if they were one controlled session.

## Raw source provenance

- `../raw/cross_processing_benchmarks_android.csv`: 60 rows; SHA-256 `7a985c4c90015954b586c05c902ae1fb6238708b079fd3d209a759ebc90115cd`.
- `../raw/cross_processing_benchmarks_xmain.csv`: 20 rows; SHA-256 `148b29951767992df22993c92b3e8d42820c7e7a11a55277401fd9bcb0360ec5`.
- To reproduce the tables without helper scripts, group CSV rows by `processingMode` and `datasetSize`; divide `processingTimeMicros` and `totalExecutionTimeMicros` by 1,000; calculate each column's median within the group. For the separate repeated-workload export, also sum `totalExecutionTimeMicros` within each mode before dividing by 1,000. Do not combine the two exports into one session.

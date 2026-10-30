# Raw benchmark exports

Original app exports, retained without editing:

- `cross_processing_benchmarks_android.csv`: 60 rows; three modes, four sizes
  (25,000 / 50,000 / 100,000 / 250,000), five recorded runs per mode and size.
- `cross_processing_benchmarks_xmain.csv`: 20 rows; a separate repeated-workload
  experiment, ten tasks per mode for One-shot and Persistent at 100,000 records.

Both exports identify profile mode, seed 42, and one warm-up per mode/size.
The device was an Android 17/API 37 x86_64 emulator (`sdk_gphone16k_x86_64`).
Original session dates, host resource conditions, and exact committed experiment
revisions were not preserved. Do not infer them from file modification times.
Do not merge the two experiments as one controlled session.

See `../results/MEASURED_RESULTS.md` for derived tables, SHA-256 hashes, and
interpretation limits; see `../protocol.md` for future collection procedures.

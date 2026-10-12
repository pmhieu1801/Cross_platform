# Contributing

## Branches

- `main` contains reviewed, working Midterm code.
- `develop` is the integration branch for coordinated work.
- Use a focused `feature/<short-description>` branch for each change and merge it into `develop` after review.

Do not force-push shared branches or rewrite their history without explicit team agreement.

## Commits and merging

- Make small, meaningful commits with messages that describe the change.
- Keep unrelated formatting or generated-file churn out of feature commits.
- Run `dart format .`, `flutter analyze`, and `flutter test` before merge.
- Run the relevant integration test on a target device when the changed flow requires it.
- Resolve merge conflicts by preserving validated work from both sides and rerun tests afterward.

## Architecture rule

All processing modes must use the shared `DataProcessor` business pipeline. Do not duplicate, simulate, or special-case the business algorithm inside an engine or worker. Timing metadata must remain separate from business-result equality.

## Repository hygiene

- Do not commit build output, tool caches, IDE metadata, environment files, signing keys, or other secrets.
- Keep `pubspec.lock` committed for reproducible application dependencies.
- Commit benchmark results or evidence only when they were captured from a real documented experiment.
- Never present fabricated CSV rows, screenshots, profiler captures, memory values, FPS values, or derived tables as evidence.

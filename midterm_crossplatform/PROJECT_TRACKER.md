# DataFlow Midterm Project Tracker

This is the lightweight ownership map for the three-week Midterm. It identifies the primary owner of each area; changes that cross an ownership boundary should be reviewed by the affected member.

## Ownership

| Member | Primary responsibilities |
| --- | --- |
| Member 1 | Concurrency theory; shared architecture and domain contracts; `MainIsolateEngine`; `OneShotIsolateEngine`; methodology, results analysis, and integration |
| Member 2 | UI and state; `PersistentIsolateEngine`; heartbeat visualization; worker lifecycle and error UX |
| Member 3 | `DataRecord`, deterministic generator, and import; benchmark instrumentation; automated tests; DevTools, cross-platform validation, and evidence |

## Midterm delivery status

- Shared `DataProcessor` pipeline and three processing modes: implemented.
- Persistent-worker lifecycle and presentation-state separation: implemented.
- Controlled benchmark runner, warm-up behavior, and protocol: implemented.
- Sample CSV/JSON data and reproducibility documentation: implemented.
- Real device benchmark results, DevTools captures, and cross-platform evidence: pending manual collection according to `experiments/protocol.md`.

Final performance conclusions remain pending until the corresponding raw data and evidence are collected on target devices.

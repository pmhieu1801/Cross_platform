import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midterm_crossplatform/features/analyzer/data/data_record.dart';
import 'package:midterm_crossplatform/features/analyzer/data/dataset_generator.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/benchmark_record.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/benchmark_runner.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/data_processor.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/processing_engine.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/processing_metrics.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/processing_mode.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/processing_result.dart';
import 'package:midterm_crossplatform/features/analyzer/presentation/analyzer_controller.dart';
import 'package:midterm_crossplatform/features/analyzer/presentation/analyzer_page.dart';

void main() {
  test('default benchmark selection contains all three modes', () {
    final controller = AnalyzerController(deviceInfo: 'test device');
    addTearDown(() async {
      await controller.close();
      controller.dispose();
    });

    expect(controller.benchmarkModes, ProcessingMode.values.toSet());
  });

  test(
    'benchmark sweep passes only the supplied modes to BenchmarkRunner',
    () async {
      final runner = _RecordingBenchmarkRunner();
      final controller = AnalyzerController(
        benchmarkRunner: runner,
        deviceInfo: 'test device',
      );
      addTearDown(() async {
        await controller.close();
        controller.dispose();
      });
      final modes = [ProcessingMode.mainIsolate, ProcessingMode.oneShotIsolate];

      await controller.runBenchmarkSweep(
        sizes: const [1],
        repetitions: 1,
        seed: 42,
        modes: modes,
      );

      expect(runner.calls, 1);
      expect(identical(runner.lastModes, modes), isTrue);
    },
  );

  testWidgets('selecting Main and One-shot excludes Persistent', (
    tester,
  ) async {
    final runner = _RecordingBenchmarkRunner();
    final controller = _controllerWith(runner);
    addTearDown(() async {
      await controller.close();
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(home: AnalyzerPage(controller: controller)),
    );

    await _tapBenchmarkMode(tester, ProcessingMode.persistentIsolate);
    await _runSweep(tester);

    expect(runner.lastModes, [
      ProcessingMode.mainIsolate,
      ProcessingMode.oneShotIsolate,
    ]);
  });

  testWidgets('selecting One-shot and Persistent excludes Main', (
    tester,
  ) async {
    final runner = _RecordingBenchmarkRunner();
    final controller = _controllerWith(runner);
    addTearDown(() async {
      await controller.close();
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(home: AnalyzerPage(controller: controller)),
    );

    await _tapBenchmarkMode(tester, ProcessingMode.mainIsolate);
    await _runSweep(tester);

    expect(runner.lastModes, [
      ProcessingMode.oneShotIsolate,
      ProcessingMode.persistentIsolate,
    ]);
  });

  testWidgets('zero selected modes reports validation error without running', (
    tester,
  ) async {
    final runner = _RecordingBenchmarkRunner();
    final controller = _controllerWith(runner);
    addTearDown(() async {
      await controller.close();
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(home: AnalyzerPage(controller: controller)),
    );

    for (final mode in ProcessingMode.values) {
      await _tapBenchmarkMode(tester, mode);
    }
    await _runSweep(tester);

    expect(runner.calls, 0);
    expect(controller.state, AnalyzerState.error);
    expect(
      controller.errorMessage,
      contains('Select at least one benchmark mode.'),
    );
  });

  testWidgets('benchmark mode controls are disabled during Processing', (
    tester,
  ) async {
    final runner = _RecordingBenchmarkRunner(controlled: true);
    final controller = _controllerWith(runner);
    addTearDown(() async {
      if (!runner.release.isCompleted) {
        runner.release.complete();
      }
      await controller.close();
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(home: AnalyzerPage(controller: controller)),
    );

    await _runSweep(tester, waitForCompletion: false);
    await _pumpUntil(tester, () => runner.started.isCompleted);

    expect(controller.state, AnalyzerState.processing);
    for (final mode in ProcessingMode.values) {
      final chip = tester.widget<FilterChip>(
        find.byKey(_benchmarkModeKey(mode)),
      );
      expect(chip.onSelected, isNull);
    }

    runner.release.complete();
    await _pumpUntil(tester, () => controller.state == AnalyzerState.success);
  });

  test(
    'single Process dataset mode is unaffected by benchmark selection',
    () async {
      final runner = _RecordingBenchmarkRunner();
      ProcessingMode? processedMode;
      final controller = AnalyzerController(
        benchmarkRunner: runner,
        engineFactory: (mode) {
          processedMode = mode;
          return _ImmediateEngine(mode);
        },
        datasetGenerationCallback: (seed, count) async => [_record()],
        deviceInfo: 'test device',
      );
      addTearDown(() async {
        await controller.close();
        controller.dispose();
      });

      controller.setBenchmarkModeSelected(ProcessingMode.oneShotIsolate, false);
      controller.selectMode(ProcessingMode.oneShotIsolate);
      await controller.generateDataset(seed: 42, count: 1);
      await controller.processDataset(seed: 42);

      expect(processedMode, ProcessingMode.oneShotIsolate);
      expect(controller.result?.metrics?.mode, ProcessingMode.oneShotIsolate);
      expect(runner.calls, 0);
    },
  );
}

AnalyzerController _controllerWith(_RecordingBenchmarkRunner runner) {
  return AnalyzerController(benchmarkRunner: runner, deviceInfo: 'test device');
}

Key _benchmarkModeKey(ProcessingMode mode) {
  return Key('benchmark-mode-${mode.name}');
}

Future<void> _tapBenchmarkMode(WidgetTester tester, ProcessingMode mode) async {
  final finder = find.byKey(_benchmarkModeKey(mode));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _runSweep(
  WidgetTester tester, {
  bool waitForCompletion = true,
}) async {
  final finder = find.byKey(const Key('run-sweep'));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  if (waitForCompletion) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

class _RecordingBenchmarkRunner extends BenchmarkRunner {
  _RecordingBenchmarkRunner({this.controlled = false});

  final bool controlled;
  final started = Completer<void>();
  final release = Completer<void>();
  int calls = 0;
  List<ProcessingMode>? lastModes;

  @override
  Future<List<BenchmarkRecord>> runProtocol({
    required List<int> datasetSizes,
    required int repetitions,
    int warmUpRuns = 0,
    int seed = DatasetGenerator.defaultSeed,
    List<ProcessingMode> modes = ProcessingMode.values,
    String? deviceInfo,
    String? buildMode,
    BenchmarkProgress? onProgress,
  }) async {
    calls++;
    lastModes = modes;
    if (!started.isCompleted) {
      started.complete();
    }
    if (controlled) {
      await release.future;
    }
    return const [];
  }
}

class _ImmediateEngine implements ProcessingEngine {
  const _ImmediateEngine(this.mode);

  @override
  final ProcessingMode mode;

  @override
  Future<ProcessingResult> process(List<DataRecord> records) async {
    return const DataProcessor()
        .process(records)
        .copyWith(
          metrics: ProcessingMetrics(
            mode: mode,
            inputRecordCount: records.length,
            processingDuration: Duration.zero,
            totalDuration: Duration.zero,
          ),
        );
  }
}

DataRecord _record() {
  return DataRecord(
    id: 1,
    timestamp: DateTime.utc(2026),
    category: 'Books',
    region: 'North',
    status: 'Completed',
    quantity: 1,
    price: 1,
    processingTime: 1,
  );
}

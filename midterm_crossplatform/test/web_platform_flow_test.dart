import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/data_processor.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/processing_mode.dart';
import 'package:midterm_crossplatform/features/analyzer/presentation/analyzer_controller.dart';
import 'package:midterm_crossplatform/features/analyzer/presentation/analyzer_page.dart';

void main() {
  test('web rejects isolate benchmarks before running any worker', () async {
    final controller = AnalyzerController(isWeb: true, deviceInfo: 'web test');
    addTearDown(controller.dispose);

    controller.selectMode(ProcessingMode.oneShotIsolate);
    controller.setBenchmarkModeSelected(ProcessingMode.persistentIsolate, true);
    expect(controller.selectedMode, ProcessingMode.mainIsolate);
    expect(controller.benchmarkModes, {ProcessingMode.mainIsolate});

    await controller.runBenchmarkSweep(
      sizes: [128],
      repetitions: 1,
      seed: 42,
      modes: [ProcessingMode.mainIsolate, ProcessingMode.oneShotIsolate],
    );
    expect(controller.state, AnalyzerState.error);
    expect(controller.errorMessage, contains('Select Main only'));
    expect(controller.benchmarks, isEmpty);

    await controller.runBenchmarkSweep(
      sizes: [128],
      repetitions: 1,
      seed: 42,
      modes: controller.benchmarkModes.toList(),
    );
    expect(controller.state, AnalyzerState.success);
    expect(
      controller.benchmarks.single.metrics.mode,
      ProcessingMode.mainIsolate,
    );
  });

  testWidgets('web generates and processes with disabled isolate controls', (
    tester,
  ) async {
    final controller = AnalyzerController(isWeb: true, deviceInfo: 'web test');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: AnalyzerPage(controller: controller)),
    );

    expect(find.byKey(const Key('web-platform-notice')), findsOneWidget);
    final modes = tester.widget<SegmentedButton<ProcessingMode>>(
      find.byKey(const Key('processing-mode')),
    );
    expect(
      modes.segments
          .where((segment) => segment.enabled)
          .map((segment) => segment.value),
      [ProcessingMode.mainIsolate],
    );
    for (final mode in [
      ProcessingMode.oneShotIsolate,
      ProcessingMode.persistentIsolate,
    ]) {
      final chip = tester.widget<FilterChip>(
        find.byKey(Key('benchmark-mode-${mode.name}')),
      );
      expect(chip.onSelected, isNull);
      expect(chip.selected, isFalse);
    }

    await tester.enterText(find.byKey(const Key('dataset-size-input')), '0');
    await tester.tap(find.byKey(const Key('generate-dataset')));
    await tester.pump();
    expect(controller.state, AnalyzerState.error);

    await tester.enterText(find.byKey(const Key('dataset-size-input')), '128');
    await tester.tap(find.byKey(const Key('generate-dataset')));
    await _pumpUntil(tester, () => controller.state == AnalyzerState.ready);
    expect(controller.records, hasLength(128));
    final expected = const DataProcessor().process(controller.records);

    final process = find.byKey(const Key('process-dataset'));
    await tester.ensureVisible(process);
    await tester.pump();
    await tester.tap(process);
    await _pumpUntil(tester, () => controller.state == AnalyzerState.success);
    expect(controller.result!.statistics, expected.statistics);
    expect(controller.result!.categories, expected.categories);
    expect(controller.result!.metrics!.mode, ProcessingMode.mainIsolate);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
}

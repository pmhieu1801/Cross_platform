import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midterm_crossplatform/main.dart';
import 'package:midterm_crossplatform/features/analyzer/data/data_record.dart';
import 'package:midterm_crossplatform/features/analyzer/data/dataset_generator.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/data_processor.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/processing_engine.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/processing_metrics.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/processing_mode.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/processing_result.dart';
import 'package:midterm_crossplatform/features/analyzer/presentation/analyzer_page.dart';

void main() {
  testWidgets('app launches on the analyzer idle state', (tester) async {
    await tester.pumpWidget(const CrossProcessingApp());

    expect(find.text('Cross Processing Lab'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);
  });

  testWidgets('shows idle and completes generate-process-result flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AnalyzerPage(
          engineFactory: (_) => _ImmediateEngine(),
          datasetGenerationCallback: _generateInTest,
          deviceInfo: 'test device',
        ),
      ),
    );

    expect(find.text('Idle'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('dataset-size-input')), '8');
    await tester.tap(find.byKey(const Key('generate-dataset')));
    await _pumpUntilFound(tester, find.text('8 records loaded'));
    expect(find.text('8 records loaded'), findsOneWidget);

    await tester.tap(find.text('One-shot'));
    await tester.ensureVisible(find.byKey(const Key('process-dataset')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('process-dataset')));
    await _pumpUntilFound(tester, find.text('Completed'));

    expect(find.text('Success'), findsWidgets);
    expect(
      find.text('One-shot isolate  ·  run 1  ·  8 records  ·  seed 42'),
      findsOneWidget,
    );
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('shows processing state until engine completes', (tester) async {
    final engine = _ControlledEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: AnalyzerPage(
          engineFactory: (_) => engine,
          datasetGenerationCallback: _generateInTest,
          deviceInfo: 'test device',
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('dataset-size-input')), '2');
    await tester.tap(find.byKey(const Key('generate-dataset')));
    await _pumpUntilFound(tester, find.text('2 records loaded'));
    await tester.ensureVisible(find.byKey(const Key('process-dataset')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('process-dataset')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Processing'), findsWidgets);

    await _pumpUntil(tester, () => engine.started.isCompleted);
    engine.complete();
    await _pumpUntilFound(tester, find.text('Completed'));
    expect(find.text('Success'), findsWidgets);
  });

  testWidgets('shows error state when processing has no dataset', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AnalyzerPage()));
    await tester.ensureVisible(find.byKey(const Key('process-dataset')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('process-dataset')));
    await tester.pump();

    expect(find.text('Error'), findsWidgets);
    expect(
      find.textContaining('Generate or import a dataset first.'),
      findsOneWidget,
    );
  });
}

class _ImmediateEngine implements ProcessingEngine {
  @override
  ProcessingMode get mode => ProcessingMode.oneShotIsolate;

  @override
  Future<ProcessingResult> process(List<DataRecord> records) async {
    return const DataProcessor()
        .process(records)
        .copyWith(
          metrics: ProcessingMetrics(
            mode: mode,
            inputRecordCount: records.length,
            processingDuration: const Duration(milliseconds: 3),
            totalDuration: const Duration(milliseconds: 5),
          ),
        );
  }
}

class _ControlledEngine extends _ImmediateEngine {
  final started = Completer<void>();
  final _completion = Completer<ProcessingResult>();

  @override
  Future<ProcessingResult> process(List<DataRecord> records) {
    started.complete();
    return _completion.future;
  }

  void complete() {
    _completion.complete(
      const DataProcessor()
          .process([
            DataRecord(
              id: 1,
              timestamp: DateTime.utc(2024),
              category: 'Books',
              region: 'North',
              status: 'Completed',
              quantity: 1,
              price: 4,
              processingTime: 1,
            ),
          ])
          .copyWith(
            metrics: const ProcessingMetrics(
              mode: ProcessingMode.oneShotIsolate,
              inputRecordCount: 2,
              processingDuration: Duration.zero,
              totalDuration: Duration.zero,
            ),
          ),
    );
  }
}

Future<List<DataRecord>> _generateInTest(int seed, int count) async {
  return const DatasetGenerator().generate(seed: seed, numberOfRecords: count);
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  await _pumpUntil(tester, () => finder.evaluate().isNotEmpty);
  expect(finder, findsOneWidget);
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue);
}

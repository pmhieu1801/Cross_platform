import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midterm_crossplatform/features/analyzer/data/data_record.dart';
import 'package:midterm_crossplatform/features/analyzer/data/dataset_generator.dart';
import 'package:midterm_crossplatform/features/analyzer/presentation/analyzer_page.dart';

void main() {
  testWidgets('generates, selects an isolate mode, and displays results', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AnalyzerPage(datasetGenerationCallback: _generateInTest),
      ),
    );

    await tester.enterText(find.byKey(const Key('dataset-size-input')), '128');
    await tester.tap(find.byKey(const Key('generate-dataset')));
    await _pumpUntilFound(tester, find.text('128 records loaded'));
    expect(find.text('128 records loaded'), findsOneWidget);

    await tester.tap(find.text('One-shot'));
    await tester.ensureVisible(find.byKey(const Key('process-dataset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('process-dataset')));
    await _pumpUntilFound(tester, find.text('Completed'));

    expect(find.text('Success'), findsWidgets);
    expect(find.textContaining('One-shot isolate'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });
}

Future<List<DataRecord>> _generateInTest(int seed, int count) async {
  return const DatasetGenerator().generate(seed: seed, numberOfRecords: count);
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

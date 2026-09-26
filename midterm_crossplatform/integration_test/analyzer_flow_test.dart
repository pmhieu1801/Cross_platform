import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:midterm_crossplatform/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('generate, select processing mode, and display results', (
    tester,
  ) async {
    await tester.pumpWidget(const CrossProcessingApp());

    await tester.enterText(find.byKey(const Key('dataset-size-input')), '128');
    await tester.tap(find.byKey(const Key('generate-dataset')));
    await tester.pumpAndSettle();
    expect(find.text('128 records loaded'), findsOneWidget);

    await tester.tap(find.text('One-shot'));
    await tester.ensureVisible(find.byKey(const Key('process-dataset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('process-dataset')));
    await tester.pumpAndSettle();

    expect(find.text('Success'), findsWidgets);
    expect(find.textContaining('128 records'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });
}

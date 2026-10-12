import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:midterm_crossplatform/features/analyzer/data/data_record.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/data_processor.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/processing_engine.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/processing_mode.dart';
import 'package:midterm_crossplatform/features/analyzer/workers/main_isolate_engine.dart';
import 'package:midterm_crossplatform/features/analyzer/workers/one_shot_isolate_engine.dart';
import 'package:midterm_crossplatform/features/analyzer/workers/persistent_isolate_engine.dart';

void main() {
  final records = [
    _record(id: 1, category: 'A', quantity: 2, price: 10),
    _record(id: 2, category: 'B', quantity: 3, price: 20),
    _record(id: 3, category: 'A', quantity: 5, price: 5),
    _record(id: 4, category: 'B', status: 'Failed', quantity: 100, price: 100),
  ];
  final expected = const DataProcessor().process(records);

  group('processing engines', () {
    test('MainIsolateEngine returns the expected business result', () async {
      final result = await const MainIsolateEngine().process(records);

      expect(result, expected);
      expect(result.metrics, isNotNull);
      expect(result.metrics!.mode, ProcessingMode.mainIsolate);
      expect(result.metrics!.inputRecordCount, records.length);
      expect(
        result.metrics!.totalDuration,
        greaterThanOrEqualTo(result.metrics!.processingDuration),
      );
    });

    test('OneShotIsolateEngine returns the expected business result', () async {
      final result = await const OneShotIsolateEngine().process(records);

      expect(result, expected);
      expect(result.metrics, isNotNull);
      expect(result.metrics!.mode, ProcessingMode.oneShotIsolate);
      expect(result.metrics!.inputRecordCount, records.length);
      expect(
        result.metrics!.totalDuration,
        greaterThanOrEqualTo(result.metrics!.processingDuration),
      );
    });

    test(
      'PersistentIsolateEngine returns the expected business result',
      () async {
        final engine = PersistentIsolateEngine();
        addTearDown(engine.dispose);

        final result = await engine.process(records);

        expect(result, expected);
        expect(result.metrics, isNotNull);
        expect(result.metrics!.mode, ProcessingMode.persistentIsolate);
        expect(result.metrics!.inputRecordCount, records.length);
        expect(
          result.metrics!.totalDuration,
          greaterThanOrEqualTo(result.metrics!.processingDuration),
        );
      },
    );

    test('main and one-shot modes have identical business output', () async {
      final mainResult = await const MainIsolateEngine().process(records);
      final oneShotResult = await const OneShotIsolateEngine().process(records);

      expect(mainResult.hasSameBusinessResult(oneShotResult), isTrue);
      expect(mainResult, oneShotResult);
      expect(mainResult.metrics!.mode, isNot(oneShotResult.metrics!.mode));
    });

    test('main and persistent modes have identical business output', () async {
      final persistentEngine = PersistentIsolateEngine();
      addTearDown(persistentEngine.dispose);

      final mainResult = await const MainIsolateEngine().process(records);
      final persistentResult = await persistentEngine.process(records);

      expect(mainResult.hasSameBusinessResult(persistentResult), isTrue);
      expect(mainResult, persistentResult);
      expect(mainResult.metrics!.mode, isNot(persistentResult.metrics!.mode));
    });

    test('persistent worker reuses one isolate for sequential tasks', () async {
      final engine = PersistentIsolateEngine();
      addTearDown(engine.dispose);

      final firstResult = await engine.process(records);
      final secondRecords = [
        _record(id: 10, category: 'C', quantity: 4, price: 7),
        _record(id: 11, category: 'D', quantity: 2, price: 3),
      ];
      final secondExpected = const DataProcessor().process(secondRecords);
      final secondResult = await engine.process(secondRecords);

      expect(firstResult, expected);
      expect(secondResult, secondExpected);
      expect(firstResult.metrics!.mode, ProcessingMode.persistentIsolate);
      expect(secondResult.metrics!.mode, ProcessingMode.persistentIsolate);
      expect(firstResult.metrics!.runNumber, 1);
      expect(secondResult.metrics!.runNumber, 2);
      expect(secondResult.metrics!.isolateStartupDuration, Duration.zero);
      expect(engine.debugWorkerSpawnCount, 1);
    });

    test('persistent worker close and dispose are idempotent', () async {
      final engine = PersistentIsolateEngine();

      await engine.process(records);
      await engine.close();
      await engine.close();
      await engine.dispose();
      await engine.dispose();

      expect(engine.debugWorkerSpawnCount, 1);
      await expectLater(
        engine.process(records),
        throwsA(
          isA<ProcessingEngineException>().having(
            (exception) => exception.cause,
            'cause',
            isA<StateError>(),
          ),
        ),
      );
    });

    test('persistent worker survives DataProcessor errors', () async {
      final engine = PersistentIsolateEngine();
      addTearDown(engine.dispose);

      await expectLater(
        engine.process([_record(id: 1, quantity: -1)]),
        throwsA(
          isA<ProcessingEngineException>().having(
            (exception) => exception.cause,
            'cause',
            isA<DataProcessingException>(),
          ),
        ),
      );

      final result = await engine.process(records);
      expect(result, expected);
      expect(engine.debugWorkerSpawnCount, 1);
    });

    test('unexpected worker exit completes pending requests', () async {
      final engine = PersistentIsolateEngine.withWorkerEntrypoint(
        _exitWhenRequestArrives,
      );
      addTearDown(engine.dispose);

      for (var attempt = 1; attempt <= 2; attempt++) {
        await expectLater(
          engine.process(records).timeout(const Duration(seconds: 2)),
          throwsA(
            isA<ProcessingEngineException>().having(
              (exception) => exception.cause,
              'cause',
              isA<StateError>(),
            ),
          ),
        );
        expect(engine.debugWorkerSpawnCount, attempt);
      }
    });

    test('engines expose validation failures predictably', () async {
      final invalidRecords = [_record(id: 1, quantity: -1)];

      final persistentEngine = PersistentIsolateEngine();
      addTearDown(persistentEngine.dispose);

      for (final engine in <ProcessingEngine>[
        const MainIsolateEngine(),
        const OneShotIsolateEngine(),
        persistentEngine,
      ]) {
        await expectLater(
          engine.process(invalidRecords),
          throwsA(
            isA<ProcessingEngineException>().having(
              (exception) => exception.cause,
              'cause',
              isA<DataProcessingException>(),
            ),
          ),
        );
      }
    });
  });
}

void _exitWhenRequestArrives(SendPort hostPort) {
  final commands = ReceivePort();
  hostPort.send(commands.sendPort);
  commands.listen((_) {
    commands.close();
    Isolate.exit();
  });
}

DataRecord _record({
  required int id,
  String category = 'Default',
  String status = 'Completed',
  int quantity = 1,
  double price = 1,
}) {
  return DataRecord(
    id: id,
    timestamp: DateTime.utc(2026, 1, 1),
    category: category,
    region: 'North',
    status: status,
    quantity: quantity,
    price: price,
    processingTime: 1,
  );
}

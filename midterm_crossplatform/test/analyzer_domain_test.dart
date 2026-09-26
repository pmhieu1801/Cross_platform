import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:midterm_crossplatform/features/analyzer/data/data_record.dart';
import 'package:midterm_crossplatform/features/analyzer/data/dataset_generator.dart';
import 'package:midterm_crossplatform/features/analyzer/data/dataset_importer.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/benchmark_record.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/data_processor.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/processing_metrics.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/processing_mode.dart';
import 'package:midterm_crossplatform/features/analyzer/workers/main_isolate_engine.dart';
import 'package:midterm_crossplatform/features/analyzer/workers/one_shot_isolate_engine.dart';
import 'package:midterm_crossplatform/features/analyzer/workers/persistent_isolate_engine.dart';

void main() {
  group('DatasetGenerator', () {
    test('seed 42 generates the same 100000 records in the same order', () {
      const generator = DatasetGenerator();
      final first = generator.generate(seed: 42, numberOfRecords: 100000);
      final second = generator.generate(seed: 42, numberOfRecords: 100000);

      expect(first, hasLength(100000));
      expect(first, second);
    });
  });

  group('DatasetImporter', () {
    test('normalizes CSV columns into DataRecord values', () {
      const csv =
          'category,id,timestamp,region,status,quantity,price,processingTime\n'
          'Books,7,2024-01-02T03:04:05.000Z,North,Completed,2,12.5,1.25';

      final records = const DatasetImporter().fromCsv(csv);

      expect(records, [
        _record(
          id: 7,
          timestamp: DateTime.utc(2024, 1, 2, 3, 4, 5),
          category: 'Books',
          quantity: 2,
          price: 12.5,
          processingTime: 1.25,
        ),
      ]);
    });

    test('normalizes JSON arrays and rejects malformed structures', () {
      final record = _record(id: 9, category: 'Home');
      final importer = const DatasetImporter();

      expect(importer.fromJson('[${_jsonRecord(record)}]'), [record]);
      expect(
        () => importer.fromJson('[{"id": "bad"}]'),
        throwsA(isA<DatasetImportException>()),
      );
      expect(
        () => importer.fromCsv('id,category\n1,Books'),
        throwsA(isA<DatasetImportException>()),
      );
      expect(
        () => importer.fromCsv('"unterminated'),
        throwsA(isA<DatasetImportException>()),
      );
    });
  });

  group('DataProcessor', () {
    test(
      'validates, filters, groups, aggregates, sorts, and computes stats',
      () {
        final records = [
          _record(category: 'A', quantity: 2, price: 10, processingTime: 1),
          _record(
            id: 2,
            category: 'A',
            quantity: 1,
            price: 10,
            processingTime: 3,
          ),
          _record(
            id: 3,
            category: 'B',
            quantity: 2,
            price: 20,
            processingTime: 2,
          ),
          _record(
            id: 4,
            category: 'C',
            quantity: 2,
            price: 15,
            processingTime: 4,
          ),
          _record(id: 5, category: 'Z', status: 'Pending', price: 1000),
        ];

        const processor = DataProcessor();
        final result = processor.process(records);

        expect(() => processor.validate(records), returnsNormally);
        expect(result.categories.map((category) => category.category), [
          'B',
          'A',
          'C',
        ]);
        expect(result.categories[1].recordCount, 2);
        expect(result.categories[1].totalQuantity, 3);
        expect(result.categories[1].totalRevenue, 30);
        expect(result.categories[1].averageValue, 15);
        expect(result.categories[1].averageProcessingTime, 2);
        expect(result.statistics.inputRecordCount, 5);
        expect(result.statistics.completedRecordCount, 4);
        expect(result.statistics.categoryCount, 3);
        expect(result.statistics.totalQuantity, 7);
        expect(result.statistics.totalRevenue, 100);
        expect(result.statistics.averageValue, 25);
        expect(result.statistics.averageProcessingTime, 2.5);
      },
    );

    test('rejects invalid record values', () {
      expect(
        () => const DataProcessor().validate([_record(id: -1)]),
        throwsA(isA<DataProcessingException>()),
      );
      expect(
        () => const DataProcessor().validate([_record(category: '  ')]),
        throwsA(isA<DataProcessingException>()),
      );
    });
  });

  test('all processing engines return identical business results', () async {
    final records = const DatasetGenerator().generate(
      seed: 42,
      numberOfRecords: 512,
    );
    final persistent = PersistentIsolateEngine();

    try {
      final mainResult = await const MainIsolateEngine().process(records);
      final oneShotResult = await const OneShotIsolateEngine().process(records);
      final persistentResult = await persistent.process(records);

      expect(oneShotResult, mainResult);
      expect(persistentResult, mainResult);
      expect(
        oneShotResult.metrics!.totalDuration,
        greaterThanOrEqualTo(oneShotResult.metrics!.processingDuration),
      );
      expect(
        persistentResult.metrics!.totalDuration,
        greaterThanOrEqualTo(persistentResult.metrics!.processingDuration),
      );
    } finally {
      await persistent.close();
    }
  });

  test('benchmark exports timing metadata for charting', () {
    const record = BenchmarkRecord(
      metrics: ProcessingMetrics(
        mode: ProcessingMode.persistentIsolate,
        inputRecordCount: 25000,
        processingDuration: Duration(microseconds: 12),
        totalDuration: Duration(microseconds: 30),
        isolateStartupDuration: Duration(microseconds: 8),
        runNumber: 3,
        seed: 42,
        deviceInfo: 'test device',
        buildMode: 'profile',
      ),
    );

    expect(BenchmarkRecord.encodeJson([record]), contains('persistentIsolate'));
    expect(
      BenchmarkRecord.encodeCsv([record]),
      contains('isolateStartupTimeMicros'),
    );
    expect(BenchmarkRecord.encodeCsv([record]), contains('test device'));
  });
}

DataRecord _record({
  int id = 1,
  DateTime? timestamp,
  String category = 'Books',
  String region = 'North',
  String status = 'Completed',
  int quantity = 1,
  double price = 4,
  double processingTime = 1,
}) {
  return DataRecord(
    id: id,
    timestamp: timestamp ?? DateTime.utc(2024),
    category: category,
    region: region,
    status: status,
    quantity: quantity,
    price: price,
    processingTime: processingTime,
  );
}

String _jsonRecord(DataRecord record) {
  return jsonEncode(record.toJson());
}

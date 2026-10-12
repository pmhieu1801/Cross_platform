import 'package:flutter_test/flutter_test.dart';
import 'package:midterm_crossplatform/features/analyzer/data/data_record.dart';
import 'package:midterm_crossplatform/features/analyzer/domain/data_processor.dart';

void main() {
  const processor = DataProcessor();

  group('DataProcessor', () {
    test('filters, groups, aggregates, calculates revenue, and sorts', () {
      final result = processor.process(_records());

      expect(result.categories.map((result) => result.category), [
        'Books',
        'Electronics',
        'Clothing',
      ]);

      final electronics = result.categories[1];
      expect(electronics.recordCount, 2);
      expect(electronics.totalQuantity, 3);
      expect(electronics.totalRevenue, 25);
      expect(electronics.averageValue, 12.5);
      expect(electronics.averageProcessingTime, 5);

      // The pending record has deliberately large values and must be excluded.
      expect(result.statistics.completedRecordCount, 4);
      expect(result.statistics.totalQuantity, 7);
      expect(result.statistics.totalRevenue, 90);
    });

    test('produces the expected overall statistics', () {
      final statistics = processor.process(_records()).statistics;

      expect(statistics.inputRecordCount, 5);
      expect(statistics.completedRecordCount, 4);
      expect(statistics.categoryCount, 3);
      expect(statistics.totalQuantity, 7);
      expect(statistics.totalRevenue, 90);
      expect(statistics.averageValue, 22.5);
      expect(statistics.averageProcessingTime, 5);
    });

    test('uses category name as a deterministic tie breaker', () {
      final records = [
        _record(id: 1, category: 'Zulu', quantity: 1, price: 10),
        _record(id: 2, category: 'Alpha', quantity: 2, price: 5),
      ];

      final result = processor.process(records);

      expect(result.categories.map((result) => result.category), [
        'Alpha',
        'Zulu',
      ]);
    });

    test('returns zeroed statistics for an empty dataset', () {
      final result = processor.process(const []);

      expect(result.categories, isEmpty);
      expect(result.statistics.inputRecordCount, 0);
      expect(result.statistics.completedRecordCount, 0);
      expect(result.statistics.categoryCount, 0);
      expect(result.statistics.totalQuantity, 0);
      expect(result.statistics.totalRevenue, 0);
      expect(result.statistics.averageValue, 0);
      expect(result.statistics.averageProcessingTime, 0);
    });

    test('returns zeroed aggregates when no records pass the filter', () {
      final result = processor.process([
        _record(id: 1, status: 'Pending', quantity: 10, price: 20),
      ]);

      expect(result.categories, isEmpty);
      expect(result.statistics.inputRecordCount, 1);
      expect(result.statistics.completedRecordCount, 0);
      expect(result.statistics.totalRevenue, 0);
    });

    test('rejects invalid records before filtering', () {
      final invalidRecords = <DataRecord>[
        _record(id: -1),
        _record(id: 1, category: ' '),
        _record(id: 1, region: ''),
        _record(id: 1, status: ''),
        _record(id: 1, quantity: -1),
        _record(id: 1, price: double.nan),
        _record(id: 1, processingTime: double.infinity),
      ];

      for (final record in invalidRecords) {
        expect(
          () => processor.process([record]),
          throwsA(isA<DataProcessingException>()),
        );
      }
    });
  });
}

List<DataRecord> _records() {
  return [
    _record(
      id: 1,
      category: 'Electronics',
      quantity: 2,
      price: 10,
      processingTime: 4,
    ),
    _record(
      id: 2,
      category: 'Electronics',
      status: 'Pending',
      quantity: 100,
      price: 100,
      processingTime: 100,
    ),
    _record(
      id: 3,
      category: 'Books',
      quantity: 3,
      price: 20,
      processingTime: 2,
    ),
    _record(
      id: 4,
      category: 'Electronics',
      quantity: 1,
      price: 5,
      processingTime: 6,
    ),
    _record(
      id: 5,
      category: 'Clothing',
      quantity: 1,
      price: 5,
      processingTime: 8,
    ),
  ];
}

DataRecord _record({
  required int id,
  String category = 'Default',
  String region = 'North',
  String status = 'Completed',
  int quantity = 1,
  double price = 1,
  double processingTime = 1,
}) {
  return DataRecord(
    id: id,
    timestamp: DateTime.utc(2026, 1, 1),
    category: category,
    region: region,
    status: status,
    quantity: quantity,
    price: price,
    processingTime: processingTime,
  );
}

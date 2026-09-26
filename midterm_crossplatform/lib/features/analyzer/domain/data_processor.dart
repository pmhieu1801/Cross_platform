import '../data/data_record.dart';
import 'processing_result.dart';

class DataProcessingException implements Exception {
  const DataProcessingException(this.message);

  final String message;

  @override
  String toString() => 'DataProcessingException: $message';
}

/// The single deterministic business pipeline used by every processing engine.
class DataProcessor {
  const DataProcessor();

  ProcessingResult process(List<DataRecord> records) {
    validate(records);

    final completedRecords = records
        .where((record) => record.status == 'Completed')
        .toList(growable: false);
    final groupedRecords = <String, _CategoryAccumulator>{};

    for (final record in completedRecords) {
      groupedRecords
          .putIfAbsent(record.category, _CategoryAccumulator.new)
          .add(record);
    }

    final categories = groupedRecords.entries
        .map((entry) => entry.value.toResult(entry.key))
        .toList();
    categories.sort((left, right) {
      final revenueComparison = right.totalRevenue.compareTo(left.totalRevenue);
      return revenueComparison != 0
          ? revenueComparison
          : left.category.compareTo(right.category);
    });

    final totalQuantity = completedRecords.fold<int>(
      0,
      (sum, record) => sum + record.quantity,
    );
    final totalRevenue = completedRecords.fold<double>(
      0,
      (sum, record) => sum + (record.quantity * record.price),
    );
    final totalProcessingTime = completedRecords.fold<double>(
      0,
      (sum, record) => sum + record.processingTime,
    );
    final completedCount = completedRecords.length;

    return ProcessingResult(
      categories: categories,
      statistics: OverallStatistics(
        inputRecordCount: records.length,
        completedRecordCount: completedCount,
        categoryCount: categories.length,
        totalQuantity: totalQuantity,
        totalRevenue: totalRevenue,
        averageValue: completedCount == 0 ? 0 : totalRevenue / completedCount,
        averageProcessingTime: completedCount == 0
            ? 0
            : totalProcessingTime / completedCount,
      ),
    );
  }

  void validate(List<DataRecord> records) {
    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      final prefix = 'Record at index $index (id ${record.id})';

      if (record.id < 0) {
        throw DataProcessingException('$prefix has a negative id.');
      }
      if (record.category.trim().isEmpty) {
        throw DataProcessingException('$prefix has an empty category.');
      }
      if (record.region.trim().isEmpty) {
        throw DataProcessingException('$prefix has an empty region.');
      }
      if (record.status.trim().isEmpty) {
        throw DataProcessingException('$prefix has an empty status.');
      }
      if (record.quantity < 0) {
        throw DataProcessingException('$prefix has a negative quantity.');
      }
      if (!record.price.isFinite || record.price < 0) {
        throw DataProcessingException('$prefix has an invalid price.');
      }
      if (!record.processingTime.isFinite || record.processingTime < 0) {
        throw DataProcessingException(
          '$prefix has an invalid processing time.',
        );
      }
    }
  }
}

class _CategoryAccumulator {
  int recordCount = 0;
  int totalQuantity = 0;
  double totalRevenue = 0;
  double totalProcessingTime = 0;

  void add(DataRecord record) {
    recordCount++;
    totalQuantity += record.quantity;
    totalRevenue += record.quantity * record.price;
    totalProcessingTime += record.processingTime;
  }

  CategoryResult toResult(String category) {
    return CategoryResult(
      category: category,
      recordCount: recordCount,
      totalQuantity: totalQuantity,
      totalRevenue: totalRevenue,
      averageValue: totalRevenue / recordCount,
      averageProcessingTime: totalProcessingTime / recordCount,
    );
  }
}

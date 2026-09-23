import 'processing_metrics.dart';

class CategoryResult {
  const CategoryResult({
    required this.category,
    required this.recordCount,
    required this.totalQuantity,
    required this.totalRevenue,
    required this.averageValue,
    required this.averageProcessingTime,
  });

  final String category;
  final int recordCount;
  final int totalQuantity;
  final double totalRevenue;
  final double averageValue;
  final double averageProcessingTime;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CategoryResult &&
            category == other.category &&
            recordCount == other.recordCount &&
            totalQuantity == other.totalQuantity &&
            totalRevenue == other.totalRevenue &&
            averageValue == other.averageValue &&
            averageProcessingTime == other.averageProcessingTime;
  }

  @override
  int get hashCode => Object.hash(
    category,
    recordCount,
    totalQuantity,
    totalRevenue,
    averageValue,
    averageProcessingTime,
  );
}

class OverallStatistics {
  const OverallStatistics({
    required this.inputRecordCount,
    required this.completedRecordCount,
    required this.categoryCount,
    required this.totalQuantity,
    required this.totalRevenue,
    required this.averageValue,
    required this.averageProcessingTime,
  });

  const OverallStatistics.empty()
    : inputRecordCount = 0,
      completedRecordCount = 0,
      categoryCount = 0,
      totalQuantity = 0,
      totalRevenue = 0,
      averageValue = 0,
      averageProcessingTime = 0;

  final int inputRecordCount;
  final int completedRecordCount;
  final int categoryCount;
  final int totalQuantity;
  final double totalRevenue;
  final double averageValue;
  final double averageProcessingTime;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is OverallStatistics &&
            inputRecordCount == other.inputRecordCount &&
            completedRecordCount == other.completedRecordCount &&
            categoryCount == other.categoryCount &&
            totalQuantity == other.totalQuantity &&
            totalRevenue == other.totalRevenue &&
            averageValue == other.averageValue &&
            averageProcessingTime == other.averageProcessingTime;
  }

  @override
  int get hashCode => Object.hash(
    inputRecordCount,
    completedRecordCount,
    categoryCount,
    totalQuantity,
    totalRevenue,
    averageValue,
    averageProcessingTime,
  );
}

/// Business output from the shared processor, with optional runtime metadata.
///
/// Equality intentionally compares only business output. Timings naturally vary
/// between processing modes and must not affect equivalence checks.
class ProcessingResult {
  ProcessingResult({
    required List<CategoryResult> categories,
    required this.statistics,
    this.metrics,
  }) : categories = List<CategoryResult>.unmodifiable(categories);

  final List<CategoryResult> categories;
  final OverallStatistics statistics;
  final ProcessingMetrics? metrics;

  ProcessingResult copyWith({ProcessingMetrics? metrics}) {
    return ProcessingResult(
      categories: categories,
      statistics: statistics,
      metrics: metrics ?? this.metrics,
    );
  }

  bool hasSameBusinessResult(ProcessingResult other) {
    if (statistics != other.statistics ||
        categories.length != other.categories.length) {
      return false;
    }

    for (var index = 0; index < categories.length; index++) {
      if (categories[index] != other.categories[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ProcessingResult && hasSameBusinessResult(other);
  }

  @override
  int get hashCode => Object.hash(statistics, Object.hashAll(categories));
}

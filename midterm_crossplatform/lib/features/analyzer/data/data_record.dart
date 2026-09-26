/// A normalized record accepted by every analyzer processing mode.
class DataRecord {
  const DataRecord({
    required this.id,
    required this.timestamp,
    required this.category,
    required this.region,
    required this.status,
    required this.quantity,
    required this.price,
    required this.processingTime,
  });

  final int id;
  final DateTime timestamp;
  final String category;
  final String region;
  final String status;
  final int quantity;
  final double price;
  final double processingTime;

  factory DataRecord.fromJson(Map<String, dynamic> json) {
    int integer(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
      throw FormatException('Field "$key" must be an integer.');
    }

    double decimal(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed;
      }
      throw FormatException('Field "$key" must be numeric.');
    }

    String text(String key) {
      final value = json[key];
      if (value is String && value.isNotEmpty) return value;
      throw FormatException('Field "$key" must be a non-empty string.');
    }

    return DataRecord(
      id: integer('id'),
      timestamp: DateTime.parse(text('timestamp')),
      category: text('category'),
      region: text('region'),
      status: text('status'),
      quantity: integer('quantity'),
      price: decimal('price'),
      processingTime: decimal('processingTime'),
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'category': category,
    'region': region,
    'status': status,
    'quantity': quantity,
    'price': price,
    'processingTime': processingTime,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DataRecord &&
            id == other.id &&
            timestamp == other.timestamp &&
            category == other.category &&
            region == other.region &&
            status == other.status &&
            quantity == other.quantity &&
            price == other.price &&
            processingTime == other.processingTime;
  }

  @override
  int get hashCode => Object.hash(
    id,
    timestamp,
    category,
    region,
    status,
    quantity,
    price,
    processingTime,
  );
}

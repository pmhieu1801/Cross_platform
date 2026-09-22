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

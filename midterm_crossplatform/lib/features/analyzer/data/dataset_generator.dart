import 'data_record.dart';

class DatasetGenerator {
  const DatasetGenerator();

  static const defaultSeed = 42;
  static const defaultRecordCount = 100000;
  static const _categories = ['Electronics', 'Home', 'Books', 'Clothing'];
  static const _regions = ['North', 'South', 'East', 'West'];
  static const _statuses = ['Completed', 'Pending', 'Cancelled'];

  List<DataRecord> generate({
    int seed = defaultSeed,
    int numberOfRecords = defaultRecordCount,
  }) {
    if (numberOfRecords < 0) {
      throw ArgumentError.value(numberOfRecords, 'numberOfRecords');
    }

    final random = _DeterministicRandom(seed);
    final start = DateTime.utc(2024);

    return List<DataRecord>.generate(numberOfRecords, (index) {
      return DataRecord(
        id: index + 1,
        timestamp: start.add(Duration(seconds: random.nextInt(31536000))),
        category: _categories[random.nextInt(_categories.length)],
        region: _regions[random.nextInt(_regions.length)],
        status: _statuses[random.nextInt(_statuses.length)],
        quantity: 1 + random.nextInt(20),
        price: 1 + random.nextInt(100000) / 100,
        processingTime: random.nextInt(10000) / 100,
      );
    }, growable: false);
  }
}

class _DeterministicRandom {
  _DeterministicRandom(int seed) : _state = seed & 0x7fffffff;

  int _state;

  int nextInt(int max) {
    _state = (1103515245 * _state + 12345) & 0x7fffffff;
    return _state % max;
  }
}
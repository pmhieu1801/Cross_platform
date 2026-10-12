import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../data/data_record.dart';
import '../data/dataset_generator.dart';
import '../workers/main_isolate_engine.dart';
import '../workers/one_shot_isolate_engine.dart';
import '../workers/persistent_isolate_engine.dart';
import 'benchmark_record.dart';
import 'processing_engine.dart';
import 'processing_mode.dart';
import 'processing_result.dart';

typedef BenchmarkProgress = void Function(
  ProcessingMode mode,
  int size,
  int run,
);

class BenchmarkRunner {
  const BenchmarkRunner({this.generator = const DatasetGenerator()});

  static Future<String>? _deviceInfoFuture;

  final DatasetGenerator generator;

  Future<ProcessingResult> process({
    required List<DataRecord> records,
    required ProcessingEngine engine,
    required int seed,
    required int runNumber,
    String? deviceInfo,
    String? buildMode,
  }) async {
    final resolvedDeviceInfo = deviceInfo ?? await _deviceInfo();
    final result = await engine.process(records);
    final metrics = result.metrics;
    if (metrics == null) {
      throw StateError('Processing engine did not return benchmark metrics.');
    }
    return result.copyWith(
      metrics: metrics.copyWith(
        runNumber: runNumber,
        seed: seed,
        deviceInfo: resolvedDeviceInfo,
        buildMode: buildMode ?? _buildMode,
      ),
    );
  }

  Future<List<BenchmarkRecord>> runProtocol({
    required List<int> datasetSizes,
    required int repetitions,
    int seed = DatasetGenerator.defaultSeed,
    List<ProcessingMode> modes = ProcessingMode.values,
    String? deviceInfo,
    String? buildMode,
    BenchmarkProgress? onProgress,
  }) async {
    if (datasetSizes.any((size) => size < 0)) {
      throw ArgumentError.value(datasetSizes, 'datasetSizes');
    }
    if (repetitions < 1) {
      throw ArgumentError.value(repetitions, 'repetitions');
    }

    final entries = <BenchmarkRecord>[];
    for (final mode in modes) {
      final engine = _createEngine(mode);
      var runNumber = 0;
      try {
        for (final size in datasetSizes) {
          final records = generator.generate(seed: seed, numberOfRecords: size);
          for (var run = 1; run <= repetitions; run++) {
            onProgress?.call(mode, size, run);
            final result = await process(
              records: records,
              engine: engine,
              seed: seed,
              runNumber: ++runNumber,
              deviceInfo: deviceInfo,
              buildMode: buildMode,
            );
            entries.add(BenchmarkRecord(metrics: result.metrics!));
          }
        }
      } finally {
        if (engine is PersistentIsolateEngine) await engine.close();
      }
    }
    return List.unmodifiable(entries);
  }

  static ProcessingEngine _createEngine(ProcessingMode mode) {
    return switch (mode) {
      ProcessingMode.mainIsolate => const MainIsolateEngine(),
      ProcessingMode.oneShotIsolate => const OneShotIsolateEngine(),
      ProcessingMode.persistentIsolate => PersistentIsolateEngine(),
    };
  }

  static String get _buildMode {
    if (kReleaseMode) return 'release';
    if (kProfileMode) return 'profile';
    return 'debug';
  }

  static Future<String> _deviceInfo() {
    return _deviceInfoFuture ??= _readDeviceInfo();
  }

  static Future<String> _readDeviceInfo() async {
    try {
      final info = await DeviceInfoPlugin().deviceInfo;
      return '${defaultTargetPlatform.name}: ${jsonEncode(info.data)}';
    } catch (_) {
      return defaultTargetPlatform.name;
    }
  }
}

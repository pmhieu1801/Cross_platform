import 'dart:isolate';

import '../data/data_record.dart';
import '../domain/data_processor.dart';
import '../domain/processing_engine.dart';
import '../domain/processing_metrics.dart';
import '../domain/processing_mode.dart';
import '../domain/processing_result.dart';

class OneShotIsolateEngine implements ProcessingEngine {
  const OneShotIsolateEngine();

  @override
  ProcessingMode get mode => ProcessingMode.oneShotIsolate;

  @override
  Future<ProcessingResult> process(List<DataRecord> records) async {
    final totalStopwatch = Stopwatch()..start();

    try {
      // Only the sendable record list is captured by the isolate callback.
      final workerResult = await Isolate.run(() => _processRecords(records));
      totalStopwatch.stop();

      return workerResult.copyWith(
        metrics: workerResult.metrics!.copyWith(
          totalDuration: totalStopwatch.elapsed,
        ),
      );
    } catch (error, stackTrace) {
      totalStopwatch.stop();
      throw ProcessingEngineException(
        mode: mode,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}

ProcessingResult _processRecords(List<DataRecord> records) {
  final processingStopwatch = Stopwatch()..start();
  final result = const DataProcessor().process(records);
  processingStopwatch.stop();

  return result.copyWith(
    metrics: ProcessingMetrics(
      mode: ProcessingMode.oneShotIsolate,
      inputRecordCount: records.length,
      processingDuration: processingStopwatch.elapsed,
      totalDuration: processingStopwatch.elapsed,
    ),
  );
}

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
      final workerResult = await Isolate.run(() => _processRecords(records));
      totalStopwatch.stop();
      final oneShotOverhead =
          totalStopwatch.elapsed - workerResult.processingDuration;

      return workerResult.result.copyWith(
        metrics: ProcessingMetrics(
          mode: mode,
          inputRecordCount: records.length,
          processingDuration: workerResult.processingDuration,
          totalDuration: totalStopwatch.elapsed,
          // Isolate.run does not expose startup separately. This is the
          // closest observable startup and message-passing overhead.
          isolateStartupDuration: oneShotOverhead.isNegative
              ? Duration.zero
              : oneShotOverhead,
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

class _OneShotWorkerResult {
  const _OneShotWorkerResult(this.result, this.processingDuration);

  final ProcessingResult result;
  final Duration processingDuration;
}

_OneShotWorkerResult _processRecords(List<DataRecord> records) {
  final processingStopwatch = Stopwatch()..start();
  final result = const DataProcessor().process(records);
  processingStopwatch.stop();

  return _OneShotWorkerResult(result, processingStopwatch.elapsed);
}

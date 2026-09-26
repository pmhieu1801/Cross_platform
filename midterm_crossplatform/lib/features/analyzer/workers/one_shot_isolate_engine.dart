import '../data/data_record.dart';
import '../domain/processing_engine.dart';
import '../domain/processing_metrics.dart';
import '../domain/processing_mode.dart';
import '../domain/processing_result.dart';
import 'isolate_worker.dart';

class OneShotIsolateEngine implements ProcessingEngine {
  const OneShotIsolateEngine();

  @override
  ProcessingMode get mode => ProcessingMode.oneShotIsolate;

  @override
  Future<ProcessingResult> process(List<DataRecord> records) async {
    final totalStopwatch = Stopwatch()..start();
    IsolateWorkerConnection? worker;

    try {
      worker = await IsolateWorkerConnection.start();
      final reply = await worker.process(records);
      totalStopwatch.stop();

      return reply.result.copyWith(
        metrics: ProcessingMetrics(
          mode: mode,
          inputRecordCount: records.length,
          processingDuration: reply.processingDuration,
          totalDuration: totalStopwatch.elapsed,
          isolateStartupDuration: worker.startupDuration,
        ),
      );
    } catch (error, stackTrace) {
      totalStopwatch.stop();
      throw ProcessingEngineException(
        mode: mode,
        cause: error,
        stackTrace: stackTrace,
      );
    } finally {
      worker?.close();
    }
  }
}

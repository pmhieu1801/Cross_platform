import '../data/data_record.dart';
import '../domain/data_processor.dart';
import '../domain/processing_engine.dart';
import '../domain/processing_metrics.dart';
import '../domain/processing_mode.dart';
import '../domain/processing_result.dart';

class MainIsolateEngine implements ProcessingEngine {
  const MainIsolateEngine();

  @override
  ProcessingMode get mode => ProcessingMode.mainIsolate;

  @override
  Future<ProcessingResult> process(List<DataRecord> records) {
    final totalStopwatch = Stopwatch()..start();
    final processingStopwatch = Stopwatch()..start();

    try {
      // Deliberately synchronous: this engine is the UI-blocking baseline.
      final result = const DataProcessor().process(records);
      processingStopwatch.stop();
      totalStopwatch.stop();

      return Future<ProcessingResult>.value(
        result.copyWith(
          metrics: ProcessingMetrics(
            mode: mode,
            inputRecordCount: records.length,
            processingDuration: processingStopwatch.elapsed,
            totalDuration: totalStopwatch.elapsed,
          ),
        ),
      );
    } catch (error, stackTrace) {
      totalStopwatch.stop();
      return Future<ProcessingResult>.error(
        ProcessingEngineException(
          mode: mode,
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }
}

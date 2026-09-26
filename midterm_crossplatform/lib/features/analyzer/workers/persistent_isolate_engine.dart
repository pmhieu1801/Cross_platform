import '../data/data_record.dart';
import '../domain/processing_engine.dart';
import '../domain/processing_metrics.dart';
import '../domain/processing_mode.dart';
import '../domain/processing_result.dart';
import 'isolate_worker.dart';

class PersistentIsolateEngine implements ProcessingEngine {
  PersistentIsolateEngine();

  Future<IsolateWorkerConnection>? _connectionFuture;
  var _runNumber = 0;
  var _startupPending = true;

  @override
  ProcessingMode get mode => ProcessingMode.persistentIsolate;

  Future<IsolateWorkerConnection> _connection() {
    return _connectionFuture ??= IsolateWorkerConnection.start();
  }

  @override
  Future<ProcessingResult> process(List<DataRecord> records) async {
    final totalStopwatch = Stopwatch()..start();
    try {
      final worker = await _connection();
      final startupDuration = _startupPending
          ? worker.startupDuration
          : Duration.zero;
      _startupPending = false;
      final reply = await worker.process(records);
      totalStopwatch.stop();
      _runNumber++;
      return reply.result.copyWith(
        metrics: ProcessingMetrics(
          mode: mode,
          inputRecordCount: records.length,
          processingDuration: reply.processingDuration,
          totalDuration: totalStopwatch.elapsed,
          isolateStartupDuration: startupDuration,
          runNumber: _runNumber,
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

  Future<void> close() async {
    final started = _connectionFuture;
    if (started == null) return;
    try {
      (await started).close();
    } finally {
      _connectionFuture = null;
      _startupPending = true;
      _runNumber = 0;
    }
  }
}
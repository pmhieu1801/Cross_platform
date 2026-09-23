import '../data/data_record.dart';
import 'processing_mode.dart';
import 'processing_result.dart';

abstract class ProcessingEngine {
  ProcessingMode get mode;

  Future<ProcessingResult> process(List<DataRecord> records);
}

class ProcessingEngineException implements Exception {
  const ProcessingEngineException({
    required this.mode,
    required this.cause,
    required this.stackTrace,
  });

  final ProcessingMode mode;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() => 'Processing failed in ${mode.name}: $cause';
}

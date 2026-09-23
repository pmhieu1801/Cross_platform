import 'processing_mode.dart';

/// Runtime metadata kept separate from the analyzer's business output.
class ProcessingMetrics {
  const ProcessingMetrics({
    required this.mode,
    required this.inputRecordCount,
    required this.processingDuration,
    required this.totalDuration,
  });

  final ProcessingMode mode;
  final int inputRecordCount;
  final Duration processingDuration;

  /// Wall-clock duration, including isolate startup and data transfer overhead.
  final Duration totalDuration;

  Duration get overhead {
    final difference = totalDuration - processingDuration;
    return difference.isNegative ? Duration.zero : difference;
  }

  ProcessingMetrics copyWith({
    ProcessingMode? mode,
    int? inputRecordCount,
    Duration? processingDuration,
    Duration? totalDuration,
  }) {
    return ProcessingMetrics(
      mode: mode ?? this.mode,
      inputRecordCount: inputRecordCount ?? this.inputRecordCount,
      processingDuration: processingDuration ?? this.processingDuration,
      totalDuration: totalDuration ?? this.totalDuration,
    );
  }
}

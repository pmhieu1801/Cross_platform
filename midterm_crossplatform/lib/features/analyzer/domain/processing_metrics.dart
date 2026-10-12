import 'processing_mode.dart';

/// Runtime metadata kept separate from the analyzer's business output.
class ProcessingMetrics {
  const ProcessingMetrics({
    required this.mode,
    required this.inputRecordCount,
    required this.processingDuration,
    required this.totalDuration,
    this.isolateStartupDuration = Duration.zero,
    this.runNumber = 1,
    this.seed = 42,
    this.deviceInfo = 'unknown',
    this.buildMode = 'unknown',
  });

  final ProcessingMode mode;
  final int inputRecordCount;
  final Duration processingDuration;

  /// Wall-clock duration, including isolate startup and data transfer overhead.
  final Duration totalDuration;
  final Duration isolateStartupDuration;
  final int runNumber;
  final int seed;
  final String deviceInfo;
  final String buildMode;

  Duration get overhead {
    final difference = totalDuration - processingDuration;
    return difference.isNegative ? Duration.zero : difference;
  }

  ProcessingMetrics copyWith({
    ProcessingMode? mode,
    int? inputRecordCount,
    Duration? processingDuration,
    Duration? totalDuration,
    Duration? isolateStartupDuration,
    int? runNumber,
    int? seed,
    String? deviceInfo,
    String? buildMode,
  }) {
    return ProcessingMetrics(
      mode: mode ?? this.mode,
      inputRecordCount: inputRecordCount ?? this.inputRecordCount,
      processingDuration: processingDuration ?? this.processingDuration,
      totalDuration: totalDuration ?? this.totalDuration,
      isolateStartupDuration:
          isolateStartupDuration ?? this.isolateStartupDuration,
      runNumber: runNumber ?? this.runNumber,
      seed: seed ?? this.seed,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      buildMode: buildMode ?? this.buildMode,
    );
  }
}

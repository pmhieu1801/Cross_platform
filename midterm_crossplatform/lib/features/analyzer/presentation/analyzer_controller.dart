import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../data/data_record.dart';
import '../data/dataset_generator.dart';
import '../data/dataset_importer.dart';
import '../domain/benchmark_record.dart';
import '../domain/benchmark_runner.dart';
import '../domain/processing_engine.dart';
import '../domain/processing_mode.dart';
import '../domain/processing_result.dart';
import '../workers/main_isolate_engine.dart';
import '../workers/one_shot_isolate_engine.dart';
import '../workers/persistent_isolate_engine.dart';

enum AnalyzerState { idle, loadingFile, ready, processing, success, error }

typedef ProcessingEngineFactory = ProcessingEngine Function(
  ProcessingMode mode,
);
typedef DatasetGenerationCallback = Future<List<DataRecord>> Function(
  int seed,
  int count,
);

class AnalyzerController extends ChangeNotifier {
  AnalyzerController({
    this.benchmarkRunner = const BenchmarkRunner(),
    this.engineFactory,
    this.datasetGenerationCallback,
    this.deviceInfo,
  });

  final BenchmarkRunner benchmarkRunner;
  final ProcessingEngineFactory? engineFactory;
  final DatasetGenerationCallback? datasetGenerationCallback;
  final String? deviceInfo;
  final Map<ProcessingMode, ProcessingEngine> _engines = {};
  final Map<ProcessingMode, int> _modeRuns = {};

  List<DataRecord> _records = const [];
  List<BenchmarkRecord> _benchmarks = const [];
  List<String> _liveLogs = const [];
  ProcessingResult? _result;
  ProcessingMode _selectedMode = ProcessingMode.mainIsolate;
  AnalyzerState _state = AnalyzerState.idle;
  String _sourceLabel = 'No dataset loaded';
  String? _errorMessage;
  String? _progressMessage;
  Future<void>? _closeFuture;
  bool _disposed = false;

  List<DataRecord> get records => _records;
  List<BenchmarkRecord> get benchmarks => _benchmarks;
  List<String> get liveLogs => _liveLogs;
  ProcessingResult? get result => _result;
  ProcessingMode get selectedMode => _selectedMode;
  AnalyzerState get state => _state;
  String get sourceLabel => _sourceLabel;
  String? get errorMessage => _errorMessage;
  String? get progressMessage => _progressMessage;
  bool get busy =>
      _state == AnalyzerState.loadingFile || _state == AnalyzerState.processing;

  void selectMode(ProcessingMode mode) {
    if (busy || mode == _selectedMode) {
      return;
    }
    _selectedMode = mode;
    _notify();
  }

  Future<void> generateDataset({required int seed, required int count}) async {
    if (count < 1) {
      reportError(
        const FormatException('Record count must be a positive whole number.'),
      );
      return;
    }

    _beginLoading('Generating dataset…');
    _appendLog('Generating dataset…');
    _appendLog('Spawning compute isolate — seed=$seed, count=$count');
    _notify();

    try {
      final generated = datasetGenerationCallback != null
          ? await datasetGenerationCallback!(seed, count)
          : await compute<(int, int), List<DataRecord>>(_generateRecords, (
              seed,
              count,
            ));
      if (_disposed) {
        return;
      }

      _records = List<DataRecord>.unmodifiable(generated);
      _sourceLabel = 'Generated dataset';
      _result = null;
      _state = AnalyzerState.ready;
      _progressMessage = null;
      _appendLog('✓ Dataset ready — ${generated.length} records generated');
      _notify();
    } catch (error) {
      reportError(error);
    }
  }

  Future<void> importDataset() async {
    final previousState = _state;
    _beginLoading('Choose a CSV or JSON dataset');
    _appendLog('Opening dataset picker…');
    _notify();

    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'json'],
      );
      if (_disposed) {
        return;
      }
      if (selection.isEmpty) {
        _state = previousState;
        _progressMessage = null;
        _notify();
        return;
      }

      final file = selection.single;
      final content = utf8.decode(await file.xFile.readAsBytes());
      final format = file.extension?.toLowerCase();
      if (format != 'csv' && format != 'json') {
        throw const DatasetImportException('Choose a .csv or .json file.');
      }

      final imported = await compute<(String, String), List<DataRecord>>(
        _parseDataset,
        (format!, content),
      );
      if (_disposed) {
        return;
      }

      _records = List<DataRecord>.unmodifiable(imported);
      _sourceLabel = file.name;
      _result = null;
      _state = AnalyzerState.ready;
      _progressMessage = null;
      _appendLog('✓ Dataset ready — ${imported.length} records imported');
      _notify();
    } catch (error) {
      reportError(error);
    }
  }

  Future<void> processDataset({required int seed}) async {
    if (_records.isEmpty) {
      reportError(const FormatException('Generate or import a dataset first.'));
      return;
    }

    final mode = _selectedMode;
    final runNumber = (_modeRuns[mode] ?? 0) + 1;
    _state = AnalyzerState.processing;
    _errorMessage = null;
    _progressMessage = 'Processing ${_records.length} records';
    _appendLog(
      '▶ Starting ${_modeLabel(mode)} — ${_records.length} records, '
      'run #$runNumber',
    );
    _notify();

    await Future<void>.delayed(Duration.zero);
    try {
      final result = await benchmarkRunner.process(
        records: _records,
        engine: _engineFor(mode),
        seed: seed,
        runNumber: runNumber,
        deviceInfo: deviceInfo,
      );
      if (_disposed) {
        return;
      }

      final metrics = result.metrics!;
      _modeRuns[mode] = runNumber;
      _result = result;
      _benchmarks = List<BenchmarkRecord>.unmodifiable([
        ..._benchmarks,
        BenchmarkRecord(metrics: metrics),
      ]);
      _state = AnalyzerState.success;
      _progressMessage = null;
      _appendLog(
        '✓ Done — processing: ${_formatDuration(metrics.processingDuration)}, '
        'total: ${_formatDuration(metrics.totalDuration)}, '
        '${result.statistics.completedRecordCount} completed records',
      );
      _notify();
    } catch (error) {
      reportError(error);
    }
  }

  Future<void> runBenchmarkSweep({
    required List<int> sizes,
    required int repetitions,
    required int seed,
  }) async {
    if (sizes.isEmpty || sizes.any((size) => size < 1)) {
      reportError(
        const FormatException('Enter comma-separated positive sizes.'),
      );
      return;
    }
    if (repetitions < 1) {
      reportError(
        const FormatException('Repetitions must be a positive whole number.'),
      );
      return;
    }

    _state = AnalyzerState.processing;
    _errorMessage = null;
    _progressMessage = 'Preparing benchmark sweep';
    _notify();

    await Future<void>.delayed(Duration.zero);
    try {
      final entries = await benchmarkRunner.runProtocol(
        datasetSizes: sizes,
        repetitions: repetitions,
        seed: seed,
        deviceInfo: deviceInfo,
        onProgress: (mode, size, run) {
          if (_disposed) {
            return;
          }
          _progressMessage =
              '${_modeLabel(mode)} · $size records · run $run/$repetitions';
          _notify();
        },
      );
      if (_disposed) {
        return;
      }

      _benchmarks = List<BenchmarkRecord>.unmodifiable([
        ..._benchmarks,
        ...entries,
      ]);
      _result = null;
      _state = AnalyzerState.success;
      _progressMessage = '${entries.length} benchmark runs completed';
      _notify();
    } catch (error) {
      reportError(error);
    }
  }

  Future<void> exportBenchmarks({required bool asJson}) async {
    if (_benchmarks.isEmpty) {
      reportError(const FormatException('Run a benchmark before exporting.'));
      return;
    }

    try {
      final content = asJson
          ? BenchmarkRecord.encodeJson(_benchmarks)
          : BenchmarkRecord.encodeCsv(_benchmarks);
      final extension = asJson ? 'json' : 'csv';
      await FilePicker.saveFile(
        fileName: 'cross_processing_benchmarks.$extension',
        bytes: Uint8List.fromList(utf8.encode(content)),
        mimeType: asJson ? 'application/json' : 'text/csv',
        type: FileType.custom,
        allowedExtensions: [extension],
      );
    } catch (error) {
      reportError(error);
    }
  }

  void reportError(Object error) {
    if (_disposed) {
      return;
    }
    _appendLog('✗ Error: $error');
    _state = AnalyzerState.error;
    _errorMessage = error.toString();
    _progressMessage = null;
    _notify();
  }

  void clearLog() {
    if (_liveLogs.isEmpty) {
      return;
    }
    _liveLogs = const [];
    _notify();
  }

  ProcessingEngine _engineFor(ProcessingMode mode) {
    return _engines.putIfAbsent(mode, () {
      return engineFactory?.call(mode) ??
          switch (mode) {
            ProcessingMode.mainIsolate => const MainIsolateEngine(),
            ProcessingMode.oneShotIsolate => const OneShotIsolateEngine(),
            ProcessingMode.persistentIsolate => PersistentIsolateEngine(),
          };
    });
  }

  void _beginLoading(String progressMessage) {
    _state = AnalyzerState.loadingFile;
    _errorMessage = null;
    _progressMessage = progressMessage;
  }

  void _appendLog(String message) {
    final entries = [..._liveLogs, '[${_timestamp()}] $message'];
    if (entries.length > 100) {
      entries.removeAt(0);
    }
    _liveLogs = List<String>.unmodifiable(entries);
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> close() {
    return _closeFuture ??= _closeEngines();
  }

  Future<void> _closeEngines() async {
    final persistentEngines = _engines.values
        .whereType<PersistentIsolateEngine>()
        .toList(growable: false);
    _engines.clear();
    await Future.wait(persistentEngines.map((engine) => engine.close()));
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}

List<DataRecord> _generateRecords((int, int) input) {
  return const DatasetGenerator().generate(
    seed: input.$1,
    numberOfRecords: input.$2,
  );
}

List<DataRecord> _parseDataset((String, String) input) {
  const importer = DatasetImporter();
  return input.$1 == 'csv'
      ? importer.fromCsv(input.$2)
      : importer.fromJson(input.$2);
}

String _modeLabel(ProcessingMode mode) => switch (mode) {
  ProcessingMode.mainIsolate => 'Main isolate',
  ProcessingMode.oneShotIsolate => 'One-shot isolate',
  ProcessingMode.persistentIsolate => 'Persistent isolate',
};

String _formatDuration(Duration duration) {
  if (duration.inMilliseconds > 0) {
    return '${duration.inMilliseconds} ms';
  }
  return '${duration.inMicroseconds} µs';
}

String _timestamp() {
  final now = DateTime.now();
  return '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}';
}

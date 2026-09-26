import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

enum AnalyzerViewState { idle, processing, success, error }

typedef ProcessingEngineFactory = ProcessingEngine Function(ProcessingMode mode);
typedef DatasetGenerationCallback = Future<List<DataRecord>> Function(
  int seed,
  int count,
);

class AnalyzerPage extends StatefulWidget {
  const AnalyzerPage({
    super.key,
    this.engineFactory,
    this.datasetGenerationCallback,
  });

  final ProcessingEngineFactory? engineFactory;
  final DatasetGenerationCallback? datasetGenerationCallback;

  @override
  State<AnalyzerPage> createState() => _AnalyzerPageState();
}

class _AnalyzerPageState extends State<AnalyzerPage> {
  final _datasetSizeController = TextEditingController(text: '100000');
  final _seedController = TextEditingController(text: '42');
  final _sizesController = TextEditingController(
    text: '25000,50000,100000,250000',
  );
  final _repetitionsController = TextEditingController(text: '1');
  final _runner = const BenchmarkRunner();
  final _engines = <ProcessingMode, ProcessingEngine>{};

  List<DataRecord> _records = const [];
  List<BenchmarkRecord> _benchmarks = const [];
  ProcessingResult? _result;
  ProcessingMode _selectedMode = ProcessingMode.mainIsolate;
  AnalyzerViewState _viewState = AnalyzerViewState.idle;
  String _sourceLabel = 'No dataset loaded';
  String? _errorMessage;
  String? _progressMessage;
  bool _loadingDataset = false;
  final _modeRuns = <ProcessingMode, int>{};

  @override
  void dispose() {
    for (final engine in _engines.values) {
      if (engine is PersistentIsolateEngine) unawaited(engine.close());
    }
    _datasetSizeController.dispose();
    _seedController.dispose();
    _sizesController.dispose();
    _repetitionsController.dispose();
    super.dispose();
  }

  ProcessingEngine _engineFor(ProcessingMode mode) {
    return _engines.putIfAbsent(mode, () {
      return widget.engineFactory?.call(mode) ?? switch (mode) {
        ProcessingMode.mainIsolate => const MainIsolateEngine(),
        ProcessingMode.oneShotIsolate => const OneShotIsolateEngine(),
        ProcessingMode.persistentIsolate => PersistentIsolateEngine(),
      };
    });
  }

  int _readPositiveInt(TextEditingController controller, String label) {
    final value = int.tryParse(controller.text.trim());
    if (value == null || value < 1) {
      throw FormatException('$label must be a positive whole number.');
    }
    return value;
  }

  int _readSeed() {
    final value = int.tryParse(_seedController.text.trim());
    if (value == null) throw const FormatException('Seed must be a whole number.');
    return value;
  }

  Future<void> _generateDataset() async {
    setState(() {
      _loadingDataset = true;
      _errorMessage = null;
    });
    try {
      final count = _readPositiveInt(_datasetSizeController, 'Record count');
      final seed = _readSeed();
      final generated = widget.datasetGenerationCallback != null
          ? await widget.datasetGenerationCallback!(seed, count)
          : await compute<(int, int), List<DataRecord>>(
              _generateRecords,
              (seed, count),
            );
      if (!mounted) return;
      setState(() {
        _records = generated;
        _sourceLabel = 'Generated dataset';
        _result = null;
        _viewState = AnalyzerViewState.idle;
        _loadingDataset = false;
      });
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> _importDataset() async {
    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'json'],
      );
      if (selection.isEmpty) return;
      setState(() {
        _loadingDataset = true;
        _errorMessage = null;
      });
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
      if (!mounted) return;
      setState(() {
        _records = imported;
        _sourceLabel = file.name;
        _result = null;
        _viewState = AnalyzerViewState.idle;
        _loadingDataset = false;
      });
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> _processDataset() async {
    if (_records.isEmpty) {
      _setError(const FormatException('Generate or import a dataset first.'));
      return;
    }
    final int seed;
    try {
      seed = _readSeed();
    } catch (error) {
      _setError(error);
      return;
    }

    final mode = _selectedMode;
    final runNumber = (_modeRuns[mode] ?? 0) + 1;
    setState(() {
      _viewState = AnalyzerViewState.processing;
      _errorMessage = null;
      _progressMessage = 'Processing ${_records.length} records';
    });
    await Future<void>.delayed(Duration.zero);
    try {
      final result = await _runner.process(
        records: _records,
        engine: _engineFor(mode),
        seed: seed,
        runNumber: runNumber,
      );
      if (!mounted) return;
      setState(() {
        _modeRuns[mode] = runNumber;
        _result = result;
        _benchmarks = [..._benchmarks, BenchmarkRecord(metrics: result.metrics!)];
        _viewState = AnalyzerViewState.success;
        _progressMessage = null;
      });
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> _runBenchmarkSweep() async {
    try {
      final sizes = _sizesController.text
          .split(',')
          .map((value) => int.parse(value.trim()))
          .toList(growable: false);
      if (sizes.isEmpty || sizes.any((size) => size < 1)) {
        throw const FormatException('Enter comma-separated positive sizes.');
      }
      final repetitions = _readPositiveInt(
        _repetitionsController,
        'Repetitions',
      );
      final seed = _readSeed();
      setState(() {
        _viewState = AnalyzerViewState.processing;
        _errorMessage = null;
        _progressMessage = 'Preparing benchmark sweep';
      });
      await Future<void>.delayed(Duration.zero);
      final entries = await _runner.runProtocol(
        datasetSizes: sizes,
        repetitions: repetitions,
        seed: seed,
        onProgress: (mode, size, run) {
          if (!mounted) return;
          setState(() {
            _progressMessage =
                '${_modeLabel(mode)} · $size records · run $run/$repetitions';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _benchmarks = [..._benchmarks, ...entries];
        _result = null;
        _viewState = AnalyzerViewState.success;
        _progressMessage = '${entries.length} benchmark runs completed';
      });
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> _exportBenchmarks({required bool asJson}) async {
    if (_benchmarks.isEmpty) {
      _setError(const FormatException('Run a benchmark before exporting.'));
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
      _setError(error);
    }
  }

  void _setError(Object error) {
    if (!mounted) return;
    setState(() {
      _viewState = AnalyzerViewState.error;
      _errorMessage = error.toString();
      _progressMessage = null;
      _loadingDataset = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = _viewState == AnalyzerViewState.processing || _loadingDataset;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(
          children: [
            Icon(Icons.multiple_stop_rounded, color: Color(0xFF167C70)),
            SizedBox(width: 10),
            Text(
              'Cross Processing Lab',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Export benchmark CSV',
            onPressed: busy ? null : () => _exportBenchmarks(asJson: false),
            icon: const Icon(Icons.download_outlined),
          ),
          PopupMenuButton<bool>(
            tooltip: 'Export format',
            onSelected: (asJson) => _exportBenchmarks(asJson: asJson),
            itemBuilder: (context) => const [
              PopupMenuItem(value: false, child: Text('Export CSV')),
              PopupMenuItem(value: true, child: Text('Export JSON')),
            ],
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _buildHeading(),
                const SizedBox(height: 20),
                _buildDatasetPanel(busy),
                const SizedBox(height: 14),
                _buildExecutionPanel(busy),
                const SizedBox(height: 14),
                if (busy) _buildStatusPanel(),
                if (_viewState == AnalyzerViewState.error) _buildErrorPanel(),
                if (_result != null) _buildResultPanel(_result!),
                if (_benchmarks.isNotEmpty) _buildBenchmarkPanel(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ISOLATES / EVENT LOOP / FRAME TIME',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: const Color(0xFF167C70),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Measure the work, not the guess.',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF183A36),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Run one aggregation pipeline across the UI isolate and background workers.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF53655F),
          ),
        ),
      ],
    );
  }

  Widget _buildDatasetPanel(bool busy) {
    return _Panel(
      title: '01  Dataset',
      trailing: Text(
        _sourceLabel,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFF53655F), fontSize: 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final count in [25000, 50000, 100000, 250000])
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _datasetSizeController.text = '$count',
                  child: Text('${count ~/ 1000}K'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final countField = _numberField(
                key: const Key('dataset-size-input'),
                label: 'Record count',
                controller: _datasetSizeController,
                enabled: !busy,
              );
              final seedField = _numberField(
                key: const Key('seed-input'),
                label: 'Seed',
                controller: _seedController,
                enabled: !busy,
              );
              return constraints.maxWidth < 650
                  ? Column(
                      children: [
                        countField,
                        const SizedBox(height: 10),
                        seedField,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: countField),
                        const SizedBox(width: 12),
                        Expanded(child: seedField),
                      ],
                    );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                key: const Key('generate-dataset'),
                onPressed: busy ? null : _generateDataset,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Generate'),
              ),
              OutlinedButton.icon(
                key: const Key('import-dataset'),
                onPressed: busy ? null : _importDataset,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Import CSV / JSON'),
              ),
              Text('${_records.length} records loaded'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required Key key,
    required String label,
    required TextEditingController controller,
    required bool enabled,
  }) {
    return TextField(
      key: key,
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _buildExecutionPanel(bool busy) {
    return _Panel(
      title: '02  Execution',
      trailing: _StateBadge(state: _viewState),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<ProcessingMode>(
            key: const Key('processing-mode'),
            segments: const [
              ButtonSegment(
                value: ProcessingMode.mainIsolate,
                label: Text('Main'),
                icon: Icon(Icons.phone_android_outlined),
              ),
              ButtonSegment(
                value: ProcessingMode.oneShotIsolate,
                label: Text('One-shot'),
                icon: Icon(Icons.rocket_launch_outlined),
              ),
              ButtonSegment(
                value: ProcessingMode.persistentIsolate,
                label: Text('Persistent'),
                icon: Icon(Icons.all_inclusive),
              ),
            ],
            selected: {_selectedMode},
            onSelectionChanged: busy
                ? null
                : (selection) => setState(() => _selectedMode = selection.first),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                key: const Key('process-dataset'),
                onPressed: busy ? null : _processDataset,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: const Text('Process dataset'),
              ),
              OutlinedButton.icon(
                key: const Key('run-sweep'),
                onPressed: busy ? null : _runBenchmarkSweep,
                icon: const Icon(Icons.stacked_line_chart),
                label: const Text('Run benchmark sweep'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final sizesField = TextField(
                controller: _sizesController,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Protocol sizes',
                  hintText: '25000,50000,100000,250000',
                ),
              );
              final repetitionsField = _numberField(
                key: const Key('repetitions-input'),
                label: 'Repetitions',
                controller: _repetitionsController,
                enabled: !busy,
              );
              return constraints.maxWidth < 650
                  ? Column(
                      children: [
                        sizesField,
                        const SizedBox(height: 10),
                        repetitionsField,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(flex: 3, child: sizesField),
                        const SizedBox(width: 12),
                        Expanded(child: repetitionsField),
                      ],
                    );
            },
          ),
          const SizedBox(height: 10),
          Text(
            'Device: ${defaultTargetPlatform.name}  ·  Build: $_currentBuildMode',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF53655F),
            ),
          ),
        ],
      ),
    );
  }

  String get _currentBuildMode {
    if (kReleaseMode) return 'release';
    if (kProfileMode) return 'profile';
    return 'debug';
  }

  Widget _buildStatusPanel() {
    return _Panel(
      title: _loadingDataset ? 'Loading dataset' : 'Processing',
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(_progressMessage ?? 'Working')),
        ],
      ),
    );
  }

  Widget _buildErrorPanel() {
    return _Panel(
      title: 'Error',
      titleColor: const Color(0xFF9E3D32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFF9E3D32)),
          const SizedBox(width: 10),
          Expanded(child: Text(_errorMessage ?? 'The operation failed.')),
        ],
      ),
    );
  }

  Widget _buildResultPanel(ProcessingResult result) {
    final metrics = result.metrics!;
    final stats = result.statistics;
    return _Panel(
      title: '03  Result',
      trailing: _StateBadge(state: _viewState),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Metric(label: 'Completed', value: '${stats.completedRecordCount}'),
              _Metric(label: 'Categories', value: '${stats.categoryCount}'),
              _Metric(label: 'Revenue', value: stats.totalRevenue.toStringAsFixed(2)),
              _Metric(label: 'Processing', value: _formatDuration(metrics.processingDuration)),
              _Metric(label: 'Isolate startup', value: _formatDuration(metrics.isolateStartupDuration)),
              _Metric(label: 'Total execution', value: _formatDuration(metrics.totalDuration)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${_modeLabel(metrics.mode)}  ·  run ${metrics.runNumber}  ·  '
            '${metrics.inputRecordCount} records  ·  seed ${metrics.seed}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF53655F),
            ),
          ),
          const Divider(height: 24),
          if (result.categories.isEmpty)
            const Text('No completed records to group.')
          else
            for (final category in result.categories)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        category.category,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text('${category.recordCount} records'),
                    const SizedBox(width: 18),
                    Text(category.totalRevenue.toStringAsFixed(2)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildBenchmarkPanel() {
    return _Panel(
      title: '04  Benchmark log',
      trailing: Text('${_benchmarks.length} runs'),
      child: Column(
        children: [
          for (final entry in _benchmarks.reversed.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_modeLabel(entry.metrics.mode)} · '
                      '${entry.metrics.inputRecordCount} records · '
                      'run ${entry.metrics.runNumber}',
                    ),
                  ),
                  Text(_formatDuration(entry.metrics.totalDuration)),
                ],
              ),
            ),
        ],
      ),
    );
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
  if (duration.inMilliseconds > 0) return '${duration.inMilliseconds} ms';
  return '${duration.inMicroseconds} µs';
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.trailing,
    this.titleColor,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: titleColor ?? const Color(0xFF183A36),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 118),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF2F6F2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 3),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final AnalyzerViewState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      AnalyzerViewState.idle => ('Idle', const Color(0xFF53655F)),
      AnalyzerViewState.processing => ('Processing', const Color(0xFF9A6710)),
      AnalyzerViewState.success => ('Success', const Color(0xFF167C70)),
      AnalyzerViewState.error => ('Error', const Color(0xFF9E3D32)),
    };
    return Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700));
  }
}
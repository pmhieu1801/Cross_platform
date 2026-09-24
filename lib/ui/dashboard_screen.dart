// lib/ui/dashboard_screen.dart
//
// DataFlowDashboard — Main demonstration screen for Topic 6.
//
// ARCHITECTURE NOTE (for report):
//   This screen is the single source of truth for UI state. It owns:
//     1. A persistent [DataAnalyzerWorker] (Isolate lifecycle management)
//     2. A [DashboardState] enum that drives every UI element deterministically
//     3. A live-log panel that surfaces internal Isolate ↔ Main messages
//     4. A [UIHeartbeat] widget that measures real FPS via SchedulerBinding,
//        providing visual proof that offloading to an Isolate keeps the UI
//        thread free (FPS stays ~60), while main-thread blocking drops FPS to 0.
//
// STATE MACHINE:
//   idle ──[import]──► loading ──[done]──► ready
//   ready ──[execute isolate]──► processingIsolate ──[result]──► complete
//   ready ──[execute main]────► processingMain ──[done]──────► complete
//   processingIsolate ──[cancel]──► cancelled
//   any ──[error]──────────────► error
//   complete / cancelled / error ──[execute]──► processingIsolate / processingMain

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import '../workers/data_analyzer_worker.dart';
import '../models/worker_message.dart';
import 'ui_heartbeat.dart';

// ── State Machine ─────────────────────────────────────────────────────────────
enum DashboardState {
  idle,               // No dataset loaded yet
  loading,            // Dataset being generated (async, non-blocking)
  ready,              // Dataset ready, awaiting user action
  processingIsolate,  // Background isolate is running
  processingMain,     // Main thread intentionally blocked (jank demo)
  complete,           // Pipeline finished successfully
  cancelled,          // User cancelled the isolate task
  error,              // An error occurred
}

// ── Dataset generator — runs inside compute() isolate ────────────────────────
// Must be a top-level or static function for compute() to send it.
List<Map<String, dynamic>> _buildDataset(int count) {
  final brands = ['Mini GT', 'Hot Wheels', 'Tarmac Works', 'Tomica'];
  return List.generate(count, (i) => {
    'id': 'CAR-${100000 + i}',
    'brand': brands[i % brands.length],
    'casting_flaw': i % 15 == 0,
    'price': 250000 + (i % 5) * 50000,
  });
}

// ── Widget ────────────────────────────────────────────────────────────────────
class DataFlowDashboard extends StatefulWidget {
  const DataFlowDashboard({super.key});

  @override
  State<DataFlowDashboard> createState() => _DataFlowDashboardState();
}

class _DataFlowDashboardState extends State<DataFlowDashboard> {
  // ── Worker (persistent isolate) ───────────────────────────────────────────
  final DataAnalyzerWorker _worker = DataAnalyzerWorker();
  bool _workerReady = false;

  // ── UI State Machine ──────────────────────────────────────────────────────
  DashboardState _state = DashboardState.idle;
  double _progress = 0.0;
  String _statusMessage = 'No dataset loaded. Click "Import Mock Data" to begin.';

  // ── Data ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _mockDataset = [];
  Map<String, dynamic>? _finalStats;

  // ── Live log ──────────────────────────────────────────────────────────────
  final List<String> _liveLogs = [];
  final ScrollController _logScrollController = ScrollController();

  // ── Derived helpers ───────────────────────────────────────────────────────
  bool get _isProcessing =>
      _state == DashboardState.processingIsolate ||
      _state == DashboardState.processingMain ||
      _state == DashboardState.loading;

  bool get _hasDataset => _mockDataset.isNotEmpty;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initWorker();
  }

  Future<void> _initWorker() async {
    await _worker.initialize();
    if (!mounted) return;
    setState(() => _workerReady = true);
    _addLog('✓ Persistent Isolate spawned and handshake complete.');

    _worker.events.listen((event) {
      if (!mounted) return;
      setState(() {
        switch (event) {
          case ProgressEvent():
            _progress = event.progress;
            _statusMessage = event.stepName;
            _addLog('▶ ${event.stepName} (${(event.progress * 100).toInt()}%)');

          case ResultEvent():
            _state = DashboardState.complete;
            _progress = 1.0;
            _finalStats = event.statistics;
            _statusMessage = 'Pipeline complete — ${event.statistics['total_processed']} records processed.';
            _addLog('✓ SUCCESS: Pipeline finished. Results ready.');

          case ErrorEvent():
            _state = DashboardState.error;
            _statusMessage = 'Error: ${event.message}';
            _addLog('✗ ERROR: ${event.message}');
        }
      });
    });
  }

  @override
  void dispose() {
    _worker.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Generate 500,000 records using compute() — runs in a one-shot isolate,
  /// keeping the main/UI thread fully free during generation.
  Future<void> _generateDataset() async {
    setState(() {
      _state = DashboardState.loading;
      _statusMessage = 'Generating 500,000 records via compute() isolate...';
      _finalStats = null;
      _liveLogs.clear();
    });
    _addLog('⚙ compute() isolate spawned for dataset generation...');

    // compute() is Flutter's convenience wrapper around Isolate.run().
    // It automatically: spawns isolate → sends fn+arg → receives result → kills isolate.
    // Use for one-shot CPU-bound tasks. Our persistent worker is better for
    // multi-step pipelines where we need progress updates.
    final dataset = await compute(_buildDataset, 500000);

    if (!mounted) return;
    setState(() {
      _mockDataset = dataset;
      _state = DashboardState.ready;
      _statusMessage = 'Dataset ready: ${dataset.length} records loaded.';
    });
    _addLog('✓ Dataset loaded: ${dataset.length} records (compute() isolate exited).');
  }


  void _startIsolateAnalysis() {
    if (!_hasDataset) {
      _generateDataset().then((_) => _startIsolateAnalysis());
      return;
    }
    setState(() {
      _state = DashboardState.processingIsolate;
      _progress = 0.0;
      _finalStats = null;
      _liveLogs.clear();
      _statusMessage = 'Sending data to persistent Isolate worker...';
    });
    _addLog('⚙ StartProcessingCommand sent to Isolate via SendPort.');
    _worker.execute(_mockDataset);
  }

  /// Intentionally blocks the main thread to demonstrate UI jank.
  /// The FPS counter will drop to 0 (FROZEN) while this runs.
  void _runMainThreadJank() {
    setState(() {
      _state = DashboardState.processingMain;
      _progress = 0.0;
      _finalStats = null;
      _liveLogs.clear();
      _statusMessage = '⚠ Blocking main thread — UI will FREEZE for 5 seconds...';
    });
    _addLog('⚠ WARNING: Heavy work starting on UI isolate. Watch FPS counter drop!');

    // Synchronous busy-wait — blocks the event loop entirely.
    // No setState, no frame scheduling, no gesture events will be processed
    // until this loop exits. This is the "before" in our before/after comparison.
    final endTime = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(endTime)) {}

    setState(() {
      _state = DashboardState.complete;
      _progress = 1.0;
      _finalStats = {
        'total_processed': _mockDataset.length,
        'mode': 'Main Thread (Blocked)',
        'jank_duration_ms': 5000,
      };
      _statusMessage = 'Main-thread run complete — UI was frozen for 5s. Check FPS history.';
    });
    _addLog('✓ Main thread unblocked. FPS should recover to ~60 now.');
    _addLog('  Observe the FPS sparkline: it shows the 5s freeze window clearly.');
  }

  void _cancelAnalysis() {
    _worker.cancel();
    setState(() {
      _state = DashboardState.cancelled;
      _statusMessage = 'Cancellation signal sent to Isolate. Task aborted.';
    });
    _addLog('✗ ABORT: CancelCommand sent via SendPort → Isolate will stop at next checkpoint.');
  }

  void _reset() {
    setState(() {
      _state = _hasDataset ? DashboardState.ready : DashboardState.idle;
      _progress = 0.0;
      _finalStats = null;
      _liveLogs.clear();
      _statusMessage = _hasDataset
          ? 'Dataset ready. Choose engine and execute.'
          : 'No dataset loaded.';
    });
  }

  void _addLog(String message) {
    final time = DateTime.now().toString().substring(11, 19);
    _liveLogs.add('[$time] $message');
    if (_liveLogs.length > 60) _liveLogs.removeAt(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(
          _logScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  Color get _stateColor => switch (_state) {
    DashboardState.idle           => Colors.blueGrey,
    DashboardState.loading        => const Color(0xFF6366F1),
    DashboardState.ready          => const Color(0xFF0EA5E9),
    DashboardState.processingIsolate => const Color(0xFF2563EB),
    DashboardState.processingMain => const Color(0xFFF59E0B),
    DashboardState.complete       => const Color(0xFF10B981),
    DashboardState.cancelled      => const Color(0xFFF97316),
    DashboardState.error          => const Color(0xFFEF4444),
  };

  IconData get _stateIcon => switch (_state) {
    DashboardState.idle           => Icons.inbox,
    DashboardState.loading        => Icons.downloading,
    DashboardState.ready          => Icons.check_circle_outline,
    DashboardState.processingIsolate => Icons.memory,
    DashboardState.processingMain => Icons.warning_amber,
    DashboardState.complete       => Icons.task_alt,
    DashboardState.cancelled      => Icons.cancel_outlined,
    DashboardState.error          => Icons.error_outline,
  };

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text(
          'DataFlow Analyzer — Topic 6: Concurrency Lab',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Worker status badge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _workerReady
                    ? const Color(0xFF10B981).withAlpha((255 * 0.2).round())
                    : const Color(0xFFEF4444).withAlpha((255 * 0.2).round()),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _workerReady
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _workerReady ? Icons.circle : Icons.circle_outlined,
                    size: 8,
                    color: _workerReady
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _workerReady ? 'Isolate: ALIVE' : 'Isolate: INIT...',
                    style: TextStyle(
                      fontSize: 11,
                      color: _workerReady
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                      fontFamily: 'Courier',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left Sidebar ──────────────────────────────────────────────────
          _buildSidebar(),

          // ── Main Panel ────────────────────────────────────────────────────
          Expanded(child: _buildMainPanel()),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── FPS Monitor ───────────────────────────────────────────────────
          const _SectionHeader('UI THREAD MONITOR'),
          const SizedBox(height: 16),
          const Center(child: UIHeartbeat()),
          const SizedBox(height: 24),

          // ── Worker Lifecycle ──────────────────────────────────────────────
          const _SectionHeader('WORKER LIFECYCLE'),
          const SizedBox(height: 8),
          _WorkerLifecyclePanel(state: _state, workerReady: _workerReady),
          const SizedBox(height: 24),

          // ── App State Display ─────────────────────────────────────────────
          const _SectionHeader('APP STATE'),
          const SizedBox(height: 8),
          _AppStateChip(state: _state, color: _stateColor, icon: _stateIcon),

          const Spacer(),

          // ── Data Import ───────────────────────────────────────────────────
          const _SectionHeader('DATA SOURCE'),
          const SizedBox(height: 8),
          Text(
            _hasDataset
                ? '✓ ${_mockDataset.length} records loaded'
                : 'No dataset',
            style: TextStyle(
              fontSize: 11,
              color: _hasDataset ? const Color(0xFF10B981) : Colors.blueGrey,
              fontFamily: 'Courier',
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _state == DashboardState.loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download, size: 16),
              label: Text(
                _state == DashboardState.loading
                    ? 'Generating...'
                    : 'Import Mock Data',
                style: const TextStyle(fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
              ),
              onPressed: _isProcessing ? null : _generateDataset,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainPanel() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Action Bar ────────────────────────────────────────────────────
          _buildActionBar(),
          const SizedBox(height: 20),

          // ── Status Banner ─────────────────────────────────────────────────
          _buildStatusBanner(),
          const SizedBox(height: 16),

          // ── Progress Bar ──────────────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _isProcessing && _state != DashboardState.processingMain
                  ? _progress
                  : (_state == DashboardState.processingMain ? null : _progress),
              minHeight: 10,
              backgroundColor: const Color(0xFFE2E8F0),
              color: _stateColor,
            ),
          ),
          const SizedBox(height: 24),

          // ── Data + Log Split ──────────────────────────────────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildDataPanel()),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: _buildLogPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Data Pipeline Execution',
          style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A)),
        ),
        Row(
          children: [
            // Reset
            if (!_isProcessing &&
                _state != DashboardState.idle &&
                _state != DashboardState.ready)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reset'),
                  onPressed: _reset,
                ),
              ),

            // Halt (only during isolate processing)
            OutlinedButton.icon(
              icon: const Icon(Icons.stop, size: 16),
              label: const Text('Halt Isolate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                side: const BorderSide(color: Color(0xFFEF4444)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              onPressed: _state == DashboardState.processingIsolate
                  ? _cancelAnalysis
                  : null,
            ),
            const SizedBox(width: 10),

            // Execute with Isolate
            ElevatedButton.icon(
              icon: const Icon(Icons.memory, size: 16),
              label: const Text('Run with Isolate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              onPressed: _isProcessing ? null : _startIsolateAnalysis,
            ),
            const SizedBox(width: 10),

            // Execute on Main Thread (jank demo)
            ElevatedButton.icon(
              icon: const Icon(Icons.warning_amber, size: 16),
              label: const Text('Run on UI Thread'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              onPressed: _isProcessing ? null : _runMainThreadJank,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusBanner() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _stateColor.withAlpha((255 * 0.08).round()),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _stateColor.withAlpha((255 * 0.3).round())),
      ),
      child: Row(
        children: [
          Icon(_stateIcon, color: _stateColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(
                  color: _stateColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('RAW DATA PREVIEW (First 5 records)'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: _mockDataset.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.inbox, size: 40, color: Colors.blueGrey),
                        SizedBox(height: 8),
                        Text('No data imported yet.',
                            style: TextStyle(color: Colors.blueGrey)),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 5,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, i) {
                    final item = _mockDataset[i];
                    final hasFlaws = item['casting_flaw'] as bool;
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            hasFlaws ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                        child: Icon(
                          Icons.directions_car,
                          size: 16,
                          color: hasFlaws
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF10B981),
                        ),
                      ),
                      title: Text('${item['brand']} · ${item['id']}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          'Price: ${item['price']} VNĐ  |  Flaw: $hasFlaws',
                          style: const TextStyle(fontSize: 11)),
                    );
                  },
                ),
        ),
        const SizedBox(height: 20),

        // ── Results ───────────────────────────────────────────────────────
        if (_finalStats != null) _buildResultsCard(),
      ],
    );
  }

  Widget _buildResultsCard() {
    final stats = _finalStats!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('PIPELINE RESULTS'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _stateColor.withAlpha((255 * 0.06).round()),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _stateColor.withAlpha((255 * 0.25).round())),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: stats.entries.map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Text(
                      '${e.key}: ',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151)),
                    ),
                    Text(
                      '${e.value}',
                      style: TextStyle(fontSize: 13, color: _stateColor),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildLogPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('ISOLATE MESSAGE LOG'),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _liveLogs.isEmpty
                ? const Center(
                    child: Text('Awaiting messages...',
                        style: TextStyle(color: Color(0xFF475569), fontSize: 12)))
                : ListView.builder(
                    controller: _logScrollController,
                    itemCount: _liveLogs.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        _liveLogs[i],
                        style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 11,
                          color: _liveLogs[i].contains('✗') || _liveLogs[i].contains('ERROR')
                              ? const Color(0xFFF87171)
                              : _liveLogs[i].contains('⚠') || _liveLogs[i].contains('WARNING')
                                  ? const Color(0xFFFBBF24)
                                  : const Color(0xFF4ADE80),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// ── Reusable sub-widgets ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey,
          letterSpacing: 1.1),
    );
  }
}

/// Visualizes the Worker Lifecycle state machine.
class _WorkerLifecyclePanel extends StatelessWidget {
  final DashboardState state;
  final bool workerReady;

  const _WorkerLifecyclePanel({
    required this.state,
    required this.workerReady,
  });

  @override
  Widget build(BuildContext context) {
    final stages = [
      _LifecycleStage('Spawn', workerReady, const Color(0xFF6366F1)),
      _LifecycleStage('Idle', workerReady && state == DashboardState.ready, const Color(0xFF0EA5E9)),
      _LifecycleStage(
          'Processing',
          state == DashboardState.processingIsolate,
          const Color(0xFF2563EB)),
      _LifecycleStage(
          'Complete',
          state == DashboardState.complete,
          const Color(0xFF10B981)),
    ];

    return Column(
      children: stages.map((s) {
        return Row(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: s.active ? s.color : const Color(0xFFE2E8F0),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              s.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: s.active ? FontWeight.bold : FontWeight.normal,
                color: s.active ? s.color : Colors.blueGrey,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _LifecycleStage {
  final String label;
  final bool active;
  final Color color;
  const _LifecycleStage(this.label, this.active, this.color);
}

/// Displays the current DashboardState as a colored chip.
class _AppStateChip extends StatelessWidget {
  final DashboardState state;
  final Color color;
  final IconData icon;

  const _AppStateChip({
    required this.state,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha((255 * 0.1).round()),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha((255 * 0.4).round())),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            state.name.replaceAllMapped(
              RegExp(r'(?<=[a-z])(?=[A-Z])'),
              (m) => ' ',
            ),
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
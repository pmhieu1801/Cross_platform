// lib/ui/ui_heartbeat.dart
//
// UIHeartbeat — Real-time FPS counter using SchedulerBinding.
//
// HOW IT WORKS:
//   Flutter's rendering engine only schedules frames when something needs
//   to be drawn (lazy rendering). To measure FPS accurately we must keep
//   the engine producing frames continuously. We do this with an
//   AnimationController set to repeat — it acts as a "heartbeat" that
//   forces the engine to render at the display refresh rate (~60 Hz).
//   SchedulerBinding.addPersistentFrameCallback fires on every frame;
//   we count callbacks per second to compute real FPS.
//
// WHY THIS PROVES ISOLATE RESPONSIVENESS:
//   • Isolate mode  → AnimationController keeps ticking → FPS ~60 throughout
//   • Main-thread mode → busy-wait blocks the event loop → AnimationController
//     cannot tick → FPS drops to 0 for the duration of the block → recovers
//   The sparkline makes this before/after contrast directly observable.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class UIHeartbeat extends StatefulWidget {
  const UIHeartbeat({super.key});

  @override
  State<UIHeartbeat> createState() => _UIHeartbeatState();
}

class _UIHeartbeatState extends State<UIHeartbeat>
    with SingleTickerProviderStateMixin {
  // ── Animation controller — keeps Flutter's rendering pipeline active ──────
  // Without this, Flutter stops scheduling frames when nothing changes,
  // causing the FPS counter to read 0 even when the UI is "fine".
  late AnimationController _ticker;

  // ── FPS measurement state ─────────────────────────────────────────────────
  int _frameCount = 0;
  double _fps = 60.0;
  Duration _lastTick = Duration.zero;

  // ── 30-sample sparkline history ───────────────────────────────────────────
  final List<double> _history = List.filled(30, 60.0);

  @override
  void initState() {
    super.initState();

    // This controller runs forever and forces a new frame every ~16ms.
    // vsync ensures it is tied to the display refresh rate.
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    // Register our per-frame counter.
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  /// Fires once per rendered frame. [timeStamp] is a monotonic duration.
  void _onFrame(Duration timeStamp) {
    _frameCount++;

    if (_lastTick == Duration.zero) {
      _lastTick = timeStamp;
      return;
    }

    final elapsed = timeStamp - _lastTick;
    if (elapsed.inMilliseconds >= 1000) {
      // Compute FPS for the elapsed window (not always exactly 1000ms).
      final measured = _frameCount * 1000 / elapsed.inMilliseconds;

      if (mounted) {
        setState(() {
          _fps = measured;
          _history
            ..removeAt(0)
            ..add(_fps.clamp(0, 120));
          _frameCount = 0;
          _lastTick = timeStamp;
        });
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // ── Computed display properties ───────────────────────────────────────────

  Color get _fpsColor {
    if (_fps >= 50) return const Color(0xFF22C55E); // green  — smooth
    if (_fps >= 25) return const Color(0xFFF59E0B); // amber  — degraded
    return const Color(0xFFEF4444);                 // red    — jank/frozen
  }

  String get _fpsLabel {
    if (_fps >= 50) return 'SMOOTH';
    if (_fps >= 25) return 'DEGRADED';
    if (_fps > 1)   return 'JANK';
    return 'FROZEN';
  }

  @override
  Widget build(BuildContext context) {
    final maxH =
        _history.reduce((a, b) => a > b ? a : b).clamp(1.0, 120.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── FPS Circle Badge ──────────────────────────────────────────────
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _fpsColor, width: 3),
            color: _fpsColor.withAlpha(20),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _fps.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: _fpsColor,
                ),
              ),
              Text('FPS',
                  style: TextStyle(fontSize: 11, color: _fpsColor)),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // ── Status label ──────────────────────────────────────────────────
        Text(
          _fpsLabel,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: _fpsColor,
          ),
        ),
        const SizedBox(height: 10),

        // ── Sparkline — 30-second FPS history ────────────────────────────
        SizedBox(
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: _history.map((val) {
              final h = ((val / maxH) * 40).clamp(2.0, 40.0);
              final c = val >= 50
                  ? const Color(0xFF22C55E)
                  : val >= 25
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFFEF4444);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  width: 5,
                  height: h,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'UI Thread FPS (last 30s)',
          style: TextStyle(fontSize: 9, color: Colors.blueGrey),
        ),
      ],
    );
  }
}
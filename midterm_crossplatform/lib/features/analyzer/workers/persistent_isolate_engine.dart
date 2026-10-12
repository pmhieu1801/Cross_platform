import 'dart:async';
import 'dart:isolate';

import '../data/data_record.dart';
import '../domain/data_processor.dart';
import '../domain/processing_engine.dart';
import '../domain/processing_metrics.dart';
import '../domain/processing_mode.dart';
import '../domain/processing_result.dart';

/// A single long-lived worker isolate that processes requests sequentially.
class PersistentIsolateEngine implements ProcessingEngine {
  PersistentIsolateEngine();

  final Map<int, Completer<_WorkerSuccess>> _pendingRequests = {};

  _WorkerSession? _session;
  Future<void>? _initialization;
  int _nextRequestId = 0;
  int _runNumber = 0;
  bool _disposed = false;

  @override
  ProcessingMode get mode => ProcessingMode.persistentIsolate;

  @override
  Future<ProcessingResult> process(List<DataRecord> records) async {
    final totalStopwatch = Stopwatch()..start();

    try {
      await _ensureInitialized();

      final session = _session;
      if (_disposed || session == null || session.commandPort == null) {
        throw StateError('PersistentIsolateEngine is not available.');
      }

      final requestId = _nextRequestId++;
      final response = Completer<_WorkerSuccess>();
      _pendingRequests[requestId] = response;
      session.commandPort!.send(_ProcessRequest(requestId, records));

      final workerResult = await response.future;
      totalStopwatch.stop();
      _runNumber++;

      return workerResult.result.copyWith(
        metrics: ProcessingMetrics(
          mode: mode,
          inputRecordCount: records.length,
          processingDuration: workerResult.processingDuration,
          totalDuration: totalStopwatch.elapsed,
          isolateStartupDuration: session.takeStartupDuration(),
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

  Future<void> _ensureInitialized() async {
    if (_disposed) {
      throw StateError('PersistentIsolateEngine has been disposed.');
    }
    if (_session?.commandPort != null) {
      return;
    }

    final existingInitialization = _initialization;
    if (existingInitialization != null) {
      await existingInitialization;
      return;
    }

    final initialization = _startWorker();
    _initialization = initialization;
    try {
      await initialization;
    } finally {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
    }
  }

  Future<void> _startWorker() async {
    final startupStopwatch = Stopwatch()..start();
    final session = _WorkerSession();
    _session = session;

    session.responseSubscription = session.responses.listen(
      (message) => _handleWorkerMessage(session, message),
    );
    session.errorSubscription = session.errors.listen(
      (message) => _handleWorkerError(session, message),
    );
    session.exitSubscription = session.exits.listen(
      (_) => _handleWorkerExit(session),
    );

    try {
      final isolate = await Isolate.spawn<SendPort>(
        _persistentWorkerMain,
        session.responses.sendPort,
        onError: session.errors.sendPort,
        onExit: session.exits.sendPort,
        errorsAreFatal: true,
        debugName: 'dataflow-persistent-worker',
      );
      session.isolate = isolate;

      if (session.terminated) {
        isolate.kill(priority: Isolate.immediate);
      }

      await session.ready.future;
      startupStopwatch.stop();
      session.startupDuration = startupStopwatch.elapsed;
      if (_disposed) {
        throw StateError(
          'PersistentIsolateEngine was disposed during initialization.',
        );
      }
    } catch (_) {
      _closeSession(session, killWorker: true);
      rethrow;
    }
  }

  void _handleWorkerMessage(_WorkerSession session, Object? message) {
    if (session.terminated || !identical(_session, session)) {
      return;
    }

    if (message is SendPort) {
      if (session.commandPort != null) {
        _failSession(
          session,
          StateError('Persistent worker initialized more than once.'),
          StackTrace.current,
        );
        return;
      }
      session.commandPort = message;
      session.ready.complete();
      return;
    }

    if (message is _WorkerSuccess) {
      _pendingRequests.remove(message.requestId)?.complete(message);
      return;
    }

    if (message is _WorkerFailure) {
      _pendingRequests
          .remove(message.requestId)
          ?.completeError(
            message.error,
            StackTrace.fromString(message.stackTrace),
          );
      return;
    }

    _failSession(
      session,
      StateError('Persistent worker sent an unsupported response.'),
      StackTrace.current,
    );
  }

  void _handleWorkerError(_WorkerSession session, Object? message) {
    Object error = StateError('Persistent worker failed unexpectedly.');
    var stackTrace = StackTrace.current;

    if (message is List && message.isNotEmpty) {
      error = StateError('Persistent worker failed: ${message.first}');
      if (message.length > 1) {
        stackTrace = StackTrace.fromString(message[1].toString());
      }
    }

    _failSession(session, error, stackTrace);
  }

  void _handleWorkerExit(_WorkerSession session) {
    if (session.terminated) {
      return;
    }

    if (session.closing) {
      _closeSession(session);
      return;
    }

    _failSession(
      session,
      StateError('Persistent worker terminated unexpectedly.'),
      StackTrace.current,
    );
  }

  void _failSession(
    _WorkerSession session,
    Object error,
    StackTrace stackTrace,
  ) {
    if (session.terminated) {
      return;
    }
    if (!session.ready.isCompleted) {
      session.ready.completeError(error, stackTrace);
    }
    _failPendingRequests(error, stackTrace);
    _closeSession(session, killWorker: true);
  }

  void _failPendingRequests(Object error, StackTrace stackTrace) {
    final requests = _pendingRequests.values.toList(growable: false);
    _pendingRequests.clear();
    for (final request in requests) {
      request.completeError(error, stackTrace);
    }
  }

  void _closeSession(_WorkerSession session, {bool killWorker = false}) {
    if (session.terminated) {
      return;
    }
    session.terminated = true;

    if (killWorker) {
      session.isolate?.kill(priority: Isolate.immediate);
    }
    if (identical(_session, session)) {
      _session = null;
    }
    if (!session.exited.isCompleted) {
      session.exited.complete();
    }

    unawaited(session.responseSubscription?.cancel());
    unawaited(session.errorSubscription?.cancel());
    unawaited(session.exitSubscription?.cancel());
    session.responses.close();
    session.errors.close();
    session.exits.close();
  }

  /// Stops the worker and releases its ports. The engine cannot be reused.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    final initialization = _initialization;
    if (initialization != null) {
      try {
        await initialization;
      } catch (_) {
        // Initialization already cleaned up its failed session.
      }
    }

    final session = _session;
    if (session == null) {
      return;
    }

    session.closing = true;
    _failPendingRequests(
      StateError('PersistentIsolateEngine was disposed.'),
      StackTrace.current,
    );
    session.commandPort?.send(const _ShutdownRequest());

    try {
      await session.exited.future.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      _closeSession(session, killWorker: true);
    }
  }

  /// Compatibility alias used by the UI and benchmark runner for cleanup.
  Future<void> close() => dispose();
}

class _WorkerSession {
  final ReceivePort responses = ReceivePort();
  final ReceivePort errors = ReceivePort();
  final ReceivePort exits = ReceivePort();
  final Completer<void> ready = Completer<void>();
  final Completer<void> exited = Completer<void>();

  Isolate? isolate;
  SendPort? commandPort;
  StreamSubscription<Object?>? responseSubscription;
  StreamSubscription<Object?>? errorSubscription;
  StreamSubscription<Object?>? exitSubscription;
  Duration startupDuration = Duration.zero;
  bool startupDurationPending = true;
  bool closing = false;
  bool terminated = false;

  Duration takeStartupDuration() {
    if (!startupDurationPending) {
      return Duration.zero;
    }
    startupDurationPending = false;
    return startupDuration;
  }
}

class _ProcessRequest {
  const _ProcessRequest(this.requestId, this.records);

  final int requestId;
  final List<DataRecord> records;
}

class _ShutdownRequest {
  const _ShutdownRequest();
}

class _WorkerSuccess {
  const _WorkerSuccess(this.requestId, this.result, this.processingDuration);

  final int requestId;
  final ProcessingResult result;
  final Duration processingDuration;
}

class _WorkerFailure {
  const _WorkerFailure(this.requestId, this.error, this.stackTrace);

  final int requestId;
  final Object error;
  final String stackTrace;
}

void _persistentWorkerMain(SendPort hostPort) {
  final commands = ReceivePort();
  hostPort.send(commands.sendPort);

  commands.listen((message) {
    if (message is _ProcessRequest) {
      final processingStopwatch = Stopwatch()..start();
      try {
        final result = const DataProcessor().process(message.records);
        processingStopwatch.stop();
        hostPort.send(
          _WorkerSuccess(
            message.requestId,
            result,
            processingStopwatch.elapsed,
          ),
        );
      } catch (error, stackTrace) {
        processingStopwatch.stop();
        hostPort.send(
          _WorkerFailure(message.requestId, error, stackTrace.toString()),
        );
      }
      return;
    }

    if (message is _ShutdownRequest) {
      commands.close();
      Isolate.exit();
    }
  });
}

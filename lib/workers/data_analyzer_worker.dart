// lib/workers/data_analyzer_worker.dart
import 'dart:async';
import 'dart:isolate';
import '../models/worker_message.dart';

class DataAnalyzerWorker {
  Isolate? _isolate;
  SendPort? _workerSendPort;
  final ReceivePort _mainReceivePort = ReceivePort();
  final StreamController<WorkerEvent> _eventStream = StreamController<WorkerEvent>.broadcast();

  Stream<WorkerEvent> get events => _eventStream.stream;

  Future<void> initialize() async {
    if (_isolate != null) return;
    
    _isolate = await Isolate.spawn(_workerEntrypoint, _mainReceivePort.sendPort);
    
    _mainReceivePort.listen((message) {
      if (message is SendPort) {
        _workerSendPort = message; 
      } else if (message is WorkerEvent) {
        _eventStream.add(message);
      }
    });
  }

  void execute(List<Map<String, dynamic>> data) {
    _workerSendPort?.send(StartProcessingCommand(data));
  }

  void cancel() {
    _workerSendPort?.send(CancelCommand());
  }

  void dispose() {
    _mainReceivePort.close();
    _eventStream.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  static void _workerEntrypoint(SendPort mainSendPort) {
    final workerReceivePort = ReceivePort();
    mainSendPort.send(workerReceivePort.sendPort); 

    bool isCancelled = false;

    workerReceivePort.listen((message) {
      if (message is CancelCommand) {
        isCancelled = true;
      } else if (message is StartProcessingCommand) {
        isCancelled = false;
        _runHeavyPipeline(message.rawData, mainSendPort, () => isCancelled);
      }
    });
  }

  static void _runHeavyPipeline(
      List<Map<String, dynamic>> data, 
      SendPort sendPort, 
      bool Function() isCancelled) {
    
    try {
      if (isCancelled()) return;
      sendPort.send(ProgressEvent('Step 1: Parsing Raw Data', 0.1));
      _simulateWorkDelay(500);

      if (isCancelled()) return;
      sendPort.send(ProgressEvent('Step 2: Validating Data Integrity', 0.3));
      _simulateWorkDelay(500);

      if (isCancelled()) return;
      sendPort.send(ProgressEvent('Step 3: Filtering Missing Values', 0.5));
      _simulateWorkDelay(500);

      if (isCancelled()) return;
      sendPort.send(ProgressEvent('Step 4: Grouping & Aggregating', 0.7));
      _simulateWorkDelay(500);
      
      if (isCancelled()) return;
      sendPort.send(ProgressEvent('Step 5: Sorting & Generating Statistics', 0.9));
      _simulateWorkDelay(500);

      if (isCancelled()) return;
      sendPort.send(ResultEvent({
        'total_processed': data.length, 
        'status': 'success'
      }));
    } catch (e) {
      sendPort.send(ErrorEvent(e.toString()));
    }
  }

  static void _simulateWorkDelay(int milliseconds) {
    final endTime = DateTime.now().add(Duration(milliseconds: milliseconds));
    while (DateTime.now().isBefore(endTime)) {}
  }
}
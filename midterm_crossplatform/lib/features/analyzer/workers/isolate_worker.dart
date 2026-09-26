import 'dart:isolate';

import '../data/data_record.dart';
import '../domain/data_processor.dart';
import '../domain/processing_result.dart';

class IsolateWorkerConnection {
  IsolateWorkerConnection._({
    required this.isolate,
    required this.commandPort,
    required this.startupDuration,
  });

  final Isolate isolate;
  final SendPort commandPort;
  final Duration startupDuration;

  static Future<IsolateWorkerConnection> start() async {
    final stopwatch = Stopwatch()..start();
    final readyPort = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, readyPort.sendPort);
    final commandPort = await readyPort.first as SendPort;
    readyPort.close();
    stopwatch.stop();
    return IsolateWorkerConnection._(
      isolate: isolate,
      commandPort: commandPort,
      startupDuration: stopwatch.elapsed,
    );
  }

  Future<IsolateWorkerReply> process(List<DataRecord> records) async {
    final replyPort = ReceivePort();
    commandPort.send([replyPort.sendPort, records]);
    try {
      final message = await replyPort.first as Map<String, Object?>;
      final error = message['error'];
      if (error != null) throw StateError(error.toString());
      return IsolateWorkerReply(
        result: message['result']! as ProcessingResult,
        processingDuration: Duration(
          microseconds: message['processingMicros']! as int,
        ),
      );
    } finally {
      replyPort.close();
    }
  }

  void close() => isolate.kill(priority: Isolate.immediate);
}

class IsolateWorkerReply {
  const IsolateWorkerReply({
    required this.result,
    required this.processingDuration,
  });

  final ProcessingResult result;
  final Duration processingDuration;
}

void _workerMain(SendPort bootstrapPort) {
  final commands = ReceivePort();
  bootstrapPort.send(commands.sendPort);
  commands.listen((dynamic message) {
    final parts = message as List<dynamic>;
    final replyPort = parts[0] as SendPort;
    final records = (parts[1] as List<dynamic>).cast<DataRecord>();
    final stopwatch = Stopwatch()..start();
    try {
      final result = const DataProcessor().process(records);
      stopwatch.stop();
      replyPort.send({
        'result': result,
        'processingMicros': stopwatch.elapsedMicroseconds,
      });
    } catch (error) {
      stopwatch.stop();
      replyPort.send({'error': error.toString()});
    }
  });
}
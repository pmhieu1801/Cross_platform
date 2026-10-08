// lib/models/worker_message.dart
sealed class WorkerCommand {}

class StartProcessingCommand extends WorkerCommand {
  final List<Map<String, dynamic>> rawData;
  StartProcessingCommand(this.rawData);
}

class CancelCommand extends WorkerCommand {}

sealed class WorkerEvent {}

class ProgressEvent extends WorkerEvent {
  final String stepName;
  final double progress;
  ProgressEvent(this.stepName, this.progress);
}

class ResultEvent extends WorkerEvent {
  final Map<String, dynamic> statistics;
  ResultEvent(this.statistics);
}

class ErrorEvent extends WorkerEvent {
  final String message;
  ErrorEvent(this.message);
}

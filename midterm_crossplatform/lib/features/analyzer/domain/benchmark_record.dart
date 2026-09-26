import 'dart:convert';

import 'processing_metrics.dart';

class BenchmarkRecord {
  const BenchmarkRecord({required this.metrics});

  final ProcessingMetrics metrics;

  Map<String, Object> toJson() => {
    'processingMode': metrics.mode.name,
    'runNumber': metrics.runNumber,
    'datasetSize': metrics.inputRecordCount,
    'seed': metrics.seed,
    'processingTimeMicros': metrics.processingDuration.inMicroseconds,
    'isolateStartupTimeMicros':
        metrics.isolateStartupDuration.inMicroseconds,
    'totalExecutionTimeMicros': metrics.totalDuration.inMicroseconds,
    'deviceInfo': metrics.deviceInfo,
    'buildMode': metrics.buildMode,
  };

  static String encodeJson(Iterable<BenchmarkRecord> records) {
    return const JsonEncoder.withIndent('  ').convert(
      records.map((record) => record.toJson()).toList(growable: false),
    );
  }

  static String encodeCsv(Iterable<BenchmarkRecord> records) {
    const headers = [
      'processingMode',
      'runNumber',
      'datasetSize',
      'seed',
      'processingTimeMicros',
      'isolateStartupTimeMicros',
      'totalExecutionTimeMicros',
      'deviceInfo',
      'buildMode',
    ];
    final rows = <List<Object>>[headers];
    for (final record in records) {
      final row = record.toJson();
      rows.add(headers.map((header) => row[header]!).toList(growable: false));
    }
    return rows
        .map((row) => row.map(_csvCell).join(','))
        .join('\r\n');
  }

  static String _csvCell(Object value) {
    final text = value.toString();
    if (!text.contains(',') && !text.contains('"') && !text.contains('\n')) {
      return text;
    }
    return '"${text.replaceAll('"', '""')}"';
  }
}
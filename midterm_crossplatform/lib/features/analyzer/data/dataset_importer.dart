import 'dart:convert';

import 'package:csv/csv.dart';

import '../domain/data_processor.dart';
import 'data_record.dart';

class DatasetImporter {
  const DatasetImporter();

  static const fields = [
    'id',
    'timestamp',
    'category',
    'region',
    'status',
    'quantity',
    'price',
    'processingTime',
  ];

  List<DataRecord> fromCsv(String source) {
    try {
      final rows = Csv(
        fieldDelimiter: ',',
        autoDetect: false,
        skipEmptyLines: true,
      ).decode(source.replaceFirst('\uFEFF', ''));
      if (rows.isEmpty) throw const FormatException('CSV file is empty.');

      final headers = rows.first
          .map((value) => value.toString().trim())
          .toList(growable: false);
      if (headers.toSet().length != headers.length ||
          !headers.toSet().containsAll(fields) ||
          headers.length != fields.length) {
        throw const FormatException(
          'CSV header must contain each required field exactly once.',
        );
      }

      final records = <DataRecord>[];
      for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
        final row = rows[rowIndex];
        if (row.length != headers.length) {
          throw FormatException(
            'CSV row ${rowIndex + 1} has ${row.length} columns; '
            '${headers.length} expected.',
          );
        }
        records.add(
          DataRecord.fromJson({
            for (var column = 0; column < headers.length; column++)
              headers[column]: row[column].toString(),
          }),
        );
      }
      const DataProcessor().validate(records);
      return List.unmodifiable(records);
    } on FormatException catch (error) {
      throw DatasetImportException('Malformed CSV: ${error.message}');
    } catch (error) {
      throw DatasetImportException('Malformed CSV: $error');
    }
  }

  List<DataRecord> fromJson(String source) {
    try {
      final decoded = jsonDecode(source);
      final rows = switch (decoded) {
        List<dynamic> list => list,
        Map<String, dynamic> map when map['records'] is List =>
          map['records'] as List<dynamic>,
        _ => throw const FormatException(
          'JSON root must be an array or an object with a records array.',
        ),
      };
      final records = <DataRecord>[];
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        if (row is! Map<String, dynamic>) {
          throw FormatException('JSON record ${index + 1} must be an object.');
        }
        records.add(DataRecord.fromJson(row));
      }
      const DataProcessor().validate(records);
      return List.unmodifiable(records);
    } on FormatException catch (error) {
      throw DatasetImportException('Malformed JSON: ${error.message}');
    } catch (error) {
      throw DatasetImportException('Malformed JSON: $error');
    }
  }
}

class DatasetImportException implements Exception {
  const DatasetImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
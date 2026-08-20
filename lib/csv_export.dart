import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'constants.dart';
import 'db.dart';

/// Writes every transaction to a CSV file and returns its full path.
/// This is the backup story for the app — there is no cloud sync.
Future<String> exportTransactionsToCsv(AppDatabase db) async {
  final StringBuffer buffer = StringBuffer()
    ..writeln(AppDatabase.exportHeader.join(','));
  for (final List<Object?> row in db.exportRows()) {
    buffer.writeln(row.map(_csvCell).join(','));
  }

  final Directory dir = await _exportDirectory();
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final DateTime now = DateTime.now();
  final String stamp = '${isoDate(now)}-'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}';
  final File file = File(p.join(dir.path, 'dailyledger-$stamp.csv'));
  await file.writeAsString(buffer.toString());
  return file.path;
}

Future<Directory> _exportDirectory() async {
  try {
    return await getApplicationDocumentsDirectory();
  } catch (_) {
    // Documents folder is not guaranteed to exist on a bare Linux install.
    return getApplicationSupportDirectory();
  }
}

String _csvCell(Object? value) {
  if (value == null) return '';
  final String text = value is double
      ? value.toStringAsFixed(2)
      : value.toString();
  if (text.contains(',') || text.contains('"') || text.contains('\n')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'constants.dart';
import 'store.dart';

Future<Directory> backupDirectory() async {
  try {
    return await getApplicationDocumentsDirectory();
  } catch (_) {
    return getApplicationSupportDirectory();
  }
}

/// Writes a shareable `.db` snapshot. This is the whole app, not just CSV.
Future<String> exportDatabaseBackup(AppStore store) async {
  final Directory dir = await backupDirectory();
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final DateTime now = DateTime.now();
  final String stamp = '${isoDate(now)}-'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}';
  final String dest = p.join(dir.path, 'dailyledger-backup-$stamp.db');
  store.writeBackupTo(dest);
  return dest;
}

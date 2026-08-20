import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';

/// Whole-file internet sync. Not a row-level online database: the same SQLite
/// file is gzipped and stored in one Firebase Realtime Database slot, then
/// pulled on the other device over any network. Same replace-not-merge rule
/// as Wi-Fi sync. No Firebase SDK and no login — only HTTPS REST.
class CloudSyncSettings {
  CloudSyncSettings({this.url = '', this.code = ''});

  String url;
  String code;

  bool get isReady =>
      normalizeDatabaseUrl(url).isNotEmpty && normalizeSyncCode(code).length >= 8;

  static Future<File> _file() async {
    final Directory dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, 'cloud_sync.json'));
  }

  static Future<CloudSyncSettings> load() async {
    final File file = await _file();
    if (!file.existsSync()) return CloudSyncSettings();
    try {
      final Map<String, dynamic> json =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return CloudSyncSettings(
        url: (json['url'] as String?) ?? '',
        code: (json['code'] as String?) ?? '',
      );
    } catch (_) {
      return CloudSyncSettings();
    }
  }

  Future<void> save() async {
    final File file = await _file();
    file.writeAsStringSync(
      jsonEncode(<String, String>{'url': url.trim(), 'code': normalizeSyncCode(code)}),
    );
  }
}

/// Letters/digits that are hard to mix up when typing on a phone.
const String kSyncCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String generateSyncCode() {
  final Random rng = Random.secure();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < 8; i++) {
    buffer.write(kSyncCodeAlphabet[rng.nextInt(kSyncCodeAlphabet.length)]);
  }
  return buffer.toString();
}

String normalizeSyncCode(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

String formatSyncCode(String value) {
  final String id = normalizeSyncCode(value);
  if (id.length == 8) return '${id.substring(0, 4)}-${id.substring(4)}';
  return id;
}

String normalizeDatabaseUrl(String value) {
  String url = value.trim();
  if (url.endsWith('/')) url = url.substring(0, url.length - 1);
  return url;
}

/// `https://PROJECT-default-rtdb.REGION.firebasedatabase.app/dailyledger/CODE.json`
String cloudSlotUrl(String databaseUrl, String code) {
  final String root = normalizeDatabaseUrl(databaseUrl);
  final String id = normalizeSyncCode(code);
  if (!root.startsWith('https://')) {
    throw StateError('The database URL must start with https://');
  }
  if (!root.contains('firebasedatabase.app') && !root.contains('firebaseio.com')) {
    throw StateError(
      'Paste the Realtime Database URL from Firebase '
      '(it ends with firebasedatabase.app or firebaseio.com).',
    );
  }
  if (id.length < 8 || id.length > 16) {
    throw StateError('Enter the 8-character sync code from the other device.');
  }
  if (!RegExp(r'^[A-Z0-9]+$').hasMatch(id)) {
    throw StateError('The sync code can only contain letters and numbers.');
  }
  return '$root/dailyledger/$id.json';
}

Future<void> uploadDatabaseToCloud({
  required AppDatabase db,
  required CloudSyncSettings settings,
}) async {
  final String url = cloudSlotUrl(settings.url, settings.code);
  final String tmp = p.join(Directory.systemTemp.path, 'dailyledger-cloud.db');
  db.writeCopy(tmp);
  final List<int> raw = File(tmp).readAsBytesSync();
  final List<int> gz = gzip.encode(raw);
  if (gz.length > 8 * 1024 * 1024) {
    throw StateError('Backup is too large for this sync slot.');
  }
  final Map<String, Object> body = <String, Object>{
    'v': 1,
    'updated': DateTime.now().toUtc().toIso8601String(),
    'bytes': raw.length,
    'data': base64Encode(gz),
  };
  final http.Response response = await http
      .put(
        Uri.parse(url),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
      .timeout(const Duration(seconds: 30));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError(_httpError(response));
  }
}

/// Writes the downloaded SQLite file to a temp path and returns it.
Future<String> downloadDatabaseFromCloud(CloudSyncSettings settings) async {
  final String url = cloudSlotUrl(settings.url, settings.code);
  final http.Response response = await http
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 30));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError(_httpError(response));
  }
  final String text = response.body.trim();
  if (text.isEmpty || text == 'null') {
    throw StateError('Nothing in that slot yet. Upload from the other device first.');
  }
  final Object? decoded = jsonDecode(text);
  if (decoded is! Map) {
    throw StateError('That slot does not contain a DailyLedger backup.');
  }
  final String? data = decoded['data'] as String?;
  if (data == null || data.isEmpty) {
    throw StateError('That slot does not contain a DailyLedger backup.');
  }
  final List<int> gz = base64Decode(data);
  final List<int> raw = gzip.decode(gz);
  final String dest = p.join(Directory.systemTemp.path, 'dailyledger-cloud-in.db');
  File(dest).writeAsBytesSync(raw);
  AppDatabase.assertValidBackup(dest);
  return dest;
}

String _httpError(http.Response response) {
  if (response.statusCode == 401 || response.statusCode == 403) {
    return 'Firebase refused the write. In Realtime Database → Rules, allow '
        'read/write on dailyledger (test mode is fine for a private code).';
  }
  return 'Cloud sync failed (${response.statusCode}). Check the database URL.';
}

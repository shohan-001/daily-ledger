import 'dart:io';
import 'dart:math';

import 'constants.dart';
import 'db.dart';

/// Hosts the live database on the local Wi-Fi so the other device can pull it.
/// No internet, no account — both devices must be on the same network.
class LanSyncHost {
  LanSyncHost._(this.server, this.pin, this.ip);

  final HttpServer server;
  final String pin;
  final String ip;

  static Future<LanSyncHost> start(AppDatabase db) async {
    final String? ip = await localIPv4();
    if (ip == null) {
      throw StateError(
        'No Wi-Fi address found. Connect both devices to the same network.',
      );
    }
    final String pin = (1000 + Random().nextInt(9000)).toString();
    final HttpServer server =
        await HttpServer.bind(InternetAddress.anyIPv4, kSyncPort);
    server.listen((HttpRequest request) async {
      try {
        if (request.method == 'GET' && request.uri.path == '/backup') {
          if (request.uri.queryParameters['pin'] != pin) {
            request.response.statusCode = HttpStatus.forbidden;
            await request.response.close();
            return;
          }
          final String tmp = '${Directory.systemTemp.path}/dailyledger-sync.db';
          db.writeCopy(tmp);
          final File file = File(tmp);
          request.response.headers.contentType = ContentType.binary;
          request.response.headers.set('Content-Length', file.lengthSync());
          await request.response.addStream(file.openRead());
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      } catch (_) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    });
    return LanSyncHost._(server, pin, ip);
  }

  Future<void> stop() => server.close(force: true);
}

Future<String> downloadBackupFromHost({
  required String ip,
  required String pin,
}) async {
  final String trimmedIp = ip.trim();
  final String trimmedPin = pin.trim();
  if (trimmedIp.isEmpty || trimmedPin.length != 4) {
    throw StateError('Enter the IP address and 4-digit PIN shown on the other device.');
  }
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  try {
    final Uri url = Uri(
      scheme: 'http',
      host: trimmedIp,
      port: kSyncPort,
      path: '/backup',
      queryParameters: <String, String>{'pin': trimmedPin},
    );
    final HttpClientRequest request = await client.getUrl(url);
    final HttpClientResponse response = await request.close().timeout(
          const Duration(seconds: 20),
        );
    if (response.statusCode == HttpStatus.forbidden) {
      throw StateError('Wrong PIN.');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Could not fetch the backup (HTTP ${response.statusCode}).');
    }
    final String tmp =
        '${Directory.systemTemp.path}/dailyledger-received.db';
    final List<int> bytes = await response.fold<List<int>>(
      <int>[],
      (List<int> acc, List<int> chunk) => acc..addAll(chunk),
    );
    await File(tmp).writeAsBytes(bytes, flush: true);
    AppDatabase.assertValidBackup(tmp);
    return tmp;
  } on SocketException {
    throw StateError(
      'Could not reach $trimmedIp. Same Wi-Fi? Is the other device still sending?',
    );
  } finally {
    client.close(force: true);
  }
}

Future<String?> localIPv4() async {
  final List<NetworkInterface> interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLinkLocal: false,
  );
  String? fallback;
  for (final NetworkInterface ni in interfaces) {
    final String name = ni.name.toLowerCase();
    if (name.startsWith('docker') ||
        name.startsWith('br-') ||
        name.startsWith('veth') ||
        name.startsWith('virbr')) {
      continue;
    }
    for (final InternetAddress addr in ni.addresses) {
      if (addr.isLoopback) continue;
      final String ip = addr.address;
      if (ip.startsWith('192.168.') || ip.startsWith('10.')) return ip;
      fallback ??= ip;
    }
  }
  return fallback;
}

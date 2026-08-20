import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../backup.dart';
import '../constants.dart';
import '../db.dart';
import '../lan_sync.dart';
import '../store.dart';

Future<bool> confirmReplaceDialog(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Replace all data on this device?', style: TextStyle(fontSize: 16)),
        content: const Text(
          'Everything here (accounts, transactions, budgets, rules) will be '
          'replaced by the other copy. There is no undo.',
          style: TextStyle(color: kTextMuted, fontSize: 13),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    ) ??
    false;

Future<void> showSendWifiDialog(BuildContext context) async {
  final AppStore store = context.read<AppStore>();
  LanSyncHost? host;
  try {
    host = await LanSyncHost.start(store.db);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: kSurfaceAlt, content: Text('$error')),
      );
    }
    return;
  }
  if (!context.mounted) {
    await host.stop();
    return;
  }
  final LanSyncHost running = host;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => AlertDialog(
      backgroundColor: kSurface,
      title: const Text('Send over Wi-Fi', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'On the other device tap Receive over Wi-Fi and type:',
              style: TextStyle(color: kTextMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            const Text('IP address', style: TextStyle(color: kTextMuted, fontSize: 12)),
            SelectableText(running.ip, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            const Text('PIN', style: TextStyle(color: kTextMuted, fontSize: 12)),
            SelectableText(running.pin, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            const Text(
              'Keep this open until the other device finishes. Same Wi-Fi, '
              'no internet required.',
              style: TextStyle(color: kTextMuted, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
  await running.stop();
}

Future<void> showReceiveWifiDialog(BuildContext parent) async {
  final TextEditingController ip = TextEditingController();
  final TextEditingController pin = TextEditingController();
  final String? hint = await localIPv4();
  if (!parent.mounted) return;
  if (hint != null) {
    final List<String> parts = hint.split('.');
    if (parts.length == 4) {
      ip.text = '${parts[0]}.${parts[1]}.${parts[2]}.';
    }
  }

  await showDialog<void>(
    context: parent,
    builder: (BuildContext context) => _ReceiveDialog(
      parent: parent,
      ip: ip,
      pin: pin,
    ),
  );
  ip.dispose();
  pin.dispose();
}

class _ReceiveDialog extends StatefulWidget {
  const _ReceiveDialog({
    required this.parent,
    required this.ip,
    required this.pin,
  });

  final BuildContext parent;
  final TextEditingController ip;
  final TextEditingController pin;

  @override
  State<_ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<_ReceiveDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String tmp = await downloadBackupFromHost(
        ip: widget.ip.text,
        pin: widget.pin.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (!widget.parent.mounted) return;
      final bool ok = await confirmReplaceDialog(widget.parent);
      if (!ok) return;
      if (!widget.parent.mounted) return;
      await widget.parent.read<AppStore>().importBackup(tmp);
      if (!widget.parent.mounted) return;
      ScaffoldMessenger.of(widget.parent).showSnackBar(
        const SnackBar(
          backgroundColor: kSurfaceAlt,
          content: Text('This device now has the other copy.'),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Receive over Wi-Fi', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: widget.ip,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: fieldDecoration('IP address', hint: '192.168.1.23'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.pin,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onSubmitted: (_) => _go(),
                decoration: fieldDecoration('PIN'),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: kExpense, fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _go,
            child: Text(_busy ? 'Receiving…' : 'Receive'),
          ),
        ],
      );
}

Future<void> exportAndMaybeShare(BuildContext context) async {
  final AppStore store = context.read<AppStore>();
  final String path = await exportDatabaseBackup(store);
  if (!context.mounted) return;
  if (kIsMobile) {
    await Share.shareXFiles(<XFile>[XFile(path)], text: 'DailyLedger backup');
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: kSurfaceAlt,
        content: Text('Backup saved to $path'),
      ),
    );
  }
}

Future<void> pickAndImportBackup(BuildContext context) async {
  const XTypeGroup group = XTypeGroup(
    label: 'DailyLedger backup',
    extensions: <String>['db', 'sqlite'],
    mimeTypes: <String>[
      'application/octet-stream',
      'application/vnd.sqlite3',
      'application/x-sqlite3',
      '*/*',
    ],
  );
  final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
  if (file == null) return;
  if (!context.mounted) return;
  AppDatabase.assertValidBackup(file.path);
  final bool ok = await confirmReplaceDialog(context);
  if (!ok) return;
  if (!context.mounted) return;
  await context.read<AppStore>().importBackup(file.path);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      backgroundColor: kSurfaceAlt,
      content: Text('Backup imported. This device now matches that file.'),
    ),
  );
}

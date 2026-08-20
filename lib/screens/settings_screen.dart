import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_lock.dart';
import '../constants.dart';
import '../csv_export.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/common.dart';
import 'settings_dialogs.dart';
import 'sync_dialogs.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppStore store = context.watch<AppStore>();

    return ListView(
      padding: pagePadding(),
      children: <Widget>[
        const Text(
          'Settings',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 18),
        _Section(
          title: 'Accounts',
          onAdd: () => showAccountDialog(context),
          addLabel: 'Add account',
          children: store.accounts
              .map(
                (Account account) => _SettingRow(
                  icon: Icons.account_balance_wallet,
                  title: account.name,
                  subtitle:
                      'Starting ${formatMoney(account.startingBalance)} · now '
                      '${formatMoney(account.currentBalance)}',
                  onTap: () => showAccountDialog(context, account: account),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Categories',
          onAdd: () => showCategoryDialog(context),
          addLabel: 'Add category',
          children: store.categories
              .map<Widget>(
                (Category category) => _SettingRow(
                  icon: iconForKey(category.iconKey),
                  title: category.name,
                  subtitle: category.type.label,
                  onTap: () => showCategoryDialog(context, category: category),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Quick add presets',
          onAdd: () => showPresetDialog(context),
          addLabel: 'Add preset',
          emptyHint: 'Presets pre-fill the Add Transaction form in one tap.',
          children: store.presets
              .map(
                (Preset preset) => _SettingRow(
                  icon: Icons.bolt,
                  title: '${preset.label} · ${formatMoney(preset.amount)}',
                  subtitle: <String>[
                    preset.type.label,
                    if (preset.accountId != null)
                      store.accountName(preset.accountId),
                    if (preset.categoryId != null)
                      store.categoryName(preset.categoryId),
                  ].join(' · '),
                  onTap: () => showPresetDialog(context, preset: preset),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Monthly recurring rules',
          onAdd: () => showRuleDialog(context),
          addLabel: 'Add rule',
          emptyHint:
              'Rules are checked once when the app starts and always ask before '
              'creating a transaction.',
          children: store.rules
              .map(
                (RecurringRule rule) => _SettingRow(
                  icon: Icons.repeat,
                  title:
                      '${formatMoney(rule.amount)} · ${store.categoryName(rule.categoryId)}',
                  subtitle: rule.active
                      ? 'Day ${rule.dayOfMonth} · next ${formatDate(rule.nextDueDate)} · '
                          '${store.accountName(rule.accountId)}'
                      : 'Paused',
                  trailing: Switch(
                    value: rule.active,
                    onChanged: (bool value) =>
                        store.saveRule(rule.copyWith(active: value)),
                  ),
                  onTap: () => showRuleDialog(context, rule: rule),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        if (kIsMobile) ...<Widget>[
          const _LockSection(),
          const SizedBox(height: 14),
        ],
        const _DataSection(),
        const SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const PanelTitle('About'),
              const SizedBox(height: 10),
              Text(
                '$kAppName $kAppVersion',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const _AboutLine(label: 'Developer', value: kDeveloperName),
              const _AboutLine(label: 'GitHub', value: kGitHubProfileUrl),
              const _AboutLine(label: 'Repository', value: kRepoUrl),
              const _AboutLine(label: 'Clone', value: kRepoCloneUrl),
              const SizedBox(height: 10),
              const Text(
                'Offline only. No accounts, no cloud login, no telemetry. '
                'Currency is fixed at "$kCurrencySymbol". Source, issues and '
                'releases live on GitHub.',
                style: TextStyle(color: kTextMuted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: kRepoUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: kSurfaceAlt,
                          content: Text('Repository URL copied'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 15),
                    label: const Text('Copy repo URL'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: kRepoCloneUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: kSurfaceAlt,
                          content: Text('Clone URL copied'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.terminal, size: 15),
                    label: const Text('Copy clone URL'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AboutLine extends StatelessWidget {
  const _AboutLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: const TextStyle(color: kTextMuted, fontSize: 11)),
            const SizedBox(height: 2),
            SelectableText(value, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}

class _LockSection extends StatelessWidget {
  const _LockSection();

  @override
  Widget build(BuildContext context) {
    final AppLock lock = context.watch<AppLock>();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const PanelTitle('App lock'),
          const SizedBox(height: 4),
          const Text(
            'When you leave DailyLedger, unlock again with fingerprint, face, '
            'or the phone PIN. This stays on this phone — it is not part of '
            'the backup file.',
            style: TextStyle(color: kTextMuted, fontSize: 12),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lock with biometrics / PIN', style: TextStyle(fontSize: 14)),
            value: lock.enabled,
            activeThumbColor: kAccent,
            onChanged: lock.busy
                ? null
                : (bool value) async {
                    final String? error = await lock.setEnabled(value);
                    if (!context.mounted) return;
                    if (error != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: kSurfaceAlt,
                          content: Text(error),
                        ),
                      );
                    }
                  },
          ),
        ],
      ),
    );
  }
}

class _DataSection extends StatefulWidget {
  const _DataSection();

  @override
  State<_DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends State<_DataSection> {
  String? _lastExport;
  bool _busy = false;

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    final AppStore store = context.read<AppStore>();
    try {
      final String path = await exportTransactionsToCsv(store.db);
      if (!mounted) return;
      setState(() => _lastExport = path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kSurfaceAlt,
          content: Text('Export failed: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kSurfaceAlt,
          content: Text('$error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStore store = context.read<AppStore>();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const PanelTitle('Sync Linux ↔ phone'),
          const SizedBox(height: 8),
          Text(
            '${store.transactionCount} transactions on this device. Copy a '
            'backup file, send over the same Wi-Fi, or use a cloud slot over '
            'any internet. The receiving device is fully replaced, so always '
            'send from the copy you last used.',
            style: const TextStyle(color: kTextMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() => exportAndMaybeShare(context)),
                icon: const Icon(Icons.phone_android, size: 18),
                label: Text(kIsMobile ? 'Share backup .db' : 'Save backup .db'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() => pickAndImportBackup(context)),
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('Import backup .db'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => showSendWifiDialog(context),
                icon: const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('Send over Wi-Fi'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => showReceiveWifiDialog(context),
                icon: const Icon(Icons.wifi, size: 18),
                label: const Text('Receive over Wi-Fi'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => showCloudSyncDialog(context),
                icon: const Icon(Icons.cloud_outlined, size: 18),
                label: const Text('Sync over internet'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const PanelTitle('CSV / file location'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _busy ? null : _exportCsv,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Export transactions to CSV'),
              ),
              if (_lastExport != null)
                TextButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: _lastExport!),
                  ),
                  icon: const Icon(Icons.copy, size: 15),
                  label: const Text('Copy path'),
                ),
            ],
          ),
          if (_lastExport != null) ...<Widget>[
            const SizedBox(height: 8),
            SelectableText(
              'Saved to $_lastExport',
              style: const TextStyle(color: kTextMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Database file',
            style: TextStyle(color: kTextMuted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          SelectableText(
            store.db.filePath,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          const Text(
            'Copying the .db file (or using Wi-Fi send) is a full backup of everything.',
            style: TextStyle(color: kTextMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    required this.onAdd,
    required this.addLabel,
    this.emptyHint,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onAdd;
  final String addLabel;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            PanelTitle(
              title,
              trailing: TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 16),
                label: Text(addLabel),
              ),
            ),
            if (emptyHint != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                emptyHint!,
                style: const TextStyle(color: kTextMuted, fontSize: 11),
              ),
            ],
            const SizedBox(height: 6),
            if (children.isEmpty)
              const EmptyHint('Nothing here yet.')
            else
              ...children,
          ],
        ),
      );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 17, color: kTextMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: kTextMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 16, color: kTextMuted),
            ],
          ),
        ),
      );
}

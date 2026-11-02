import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../import/fints/fints_client.dart' show fintsProductId;
import '../l10n/strings.dart';
import '../net/net_gate.dart';
import '../platform.dart';
import '../state/app_state.dart';
import 'ledger.dart';

const sourceUrl = 'https://github.com/Dania201032/saldo';

/// "1,2 KB" in the app language.
String formatBytes(int n) {
  if (n < 1024) return '$n ${tr('pv_b')}';
  final f = NumberFormat('0.0', intlLocale);
  if (n < 1024 * 1024) return '${f.format(n / 1024)} ${tr('pv_kb')}';
  return '${f.format(n / 1024 / 1024)} ${tr('pv_mb')}';
}

String netPurposeName(NetPurpose p) => switch (p) {
      NetPurpose.rates => tr('rates'),
      NetPurpose.bunq => 'bunq',
      NetPurpose.fints => 'FinTS',
    };

/// Settings → Privacy and internet: every address the app may connect to and what goes there,
/// the log of what it actually sent (lib/net/net_gate.dart), the switch to stay offline, Android's
/// own byte count for the app, and how to check all this with tools that are not ours.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  static const _shown = 100;
  ({int sent, int received, DateTime since})? _traffic;
  bool _trafficLoaded = false;

  bool get _android => !appIsDesktop && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    netGate.reload();
    if (_android) _loadTraffic();
  }

  Future<void> _loadTraffic() async {
    final t = await context.read<AppState>().capture.trafficStats();
    if (mounted) {
      setState(() {
        _traffic = t;
        _trafficLoaded = true;
      });
    }
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('about_link_copied', [url]))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = Ledger.mutedOf(context);
    Widget para(String text, {bool small = false}) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(text, style: small ? theme.textTheme.bodySmall?.copyWith(color: muted) : theme.textTheme.bodyMedium),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('pv_title')),
        actions: [
          IconButton(tooltip: tr('pv_log_clear'), icon: const Icon(Icons.delete_sweep_outlined), onPressed: netGate.clearLog),
        ],
      ),
      body: ListenableBuilder(
        listenable: netGate,
        builder: (context, _) {
          final entries = netGate.entries;
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(tr('pv_intro'), style: theme.textTheme.bodyMedium)),
            LedgerTile(
              tr('pv_offline'),
              hint: tr('pv_offline_sub', [tr('rates')]),
              trailing: LedgerSwitch(value: netGate.off, onChanged: (v) => netGate.setOff(v)),
              onTap: () => netGate.setOff(!netGate.off),
            ),

            LedgerSection(tr('pv_where')),
            _Destination(
              title: tr('rates'),
              hosts: tr('pv_hosts', [netDestinations[NetPurpose.rates]!.join(', ')]),
              when: tr('pv_rates_when'),
              what: tr('pv_rates_what'),
            ),
            _Destination(
              title: tr('pv_bunq_t'),
              hosts: tr('pv_hosts', [netDestinations[NetPurpose.bunq]!.join(', ')]),
              when: tr('pv_bank_when'),
              what: tr('pv_bunq_what'),
            ),
            _Destination(
              title: tr('pv_fints_t'),
              hosts: tr('pv_fints_host'),
              when: fintsProductId.isEmpty ? '${tr('pv_bank_when')} ${tr('pv_fints_pending')}' : tr('pv_bank_when'),
              what: tr('pv_fints_what'),
            ),
            para(tr('pv_never')),

            LedgerSection(tr('pv_others')),
            para(tr('pv_sync')),
            if (_android) ...[para(tr('pv_mlkit')), para(tr('pv_android_backup'))],

            LedgerSection(tr('pv_log'), trailing: '${entries.length}'),
            para(tr('pv_log_sub'), small: true),
            if (entries.isEmpty) para(tr('pv_log_empty')),
            for (final e in entries.take(_shown)) _LogRow(e),
            if (entries.length > _shown) para(tr('pv_more', [entries.length - _shown]), small: true),

            if (_android && _trafficLoaded) ...[
              LedgerSection(tr('pv_counter')),
              if (_traffic case final t?) ...[
                para(tr('pv_counter_val', [
                  DateFormat('d MMM, HH:mm', intlLocale).format(t.since),
                  formatBytes(t.sent),
                  formatBytes(t.received),
                ])),
                () {
                  final (count, bytes) = netGate.totalSince(t.since);
                  return para(tr('pv_counter_log', [count, formatBytes(bytes)]));
                }(),
                para(tr('pv_counter_note'), small: true),
              ] else
                para(tr('pv_counter_na')),
            ],

            LedgerSection(tr('pv_check')),
            para(tr('pv_check_air')),
            if (_android) ...[
              para(tr('pv_check_usage')),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: context.read<AppState>().capture.openAppInfo, child: Text(tr('pv_open_app_info'))),
                ),
              ),
              para(tr('pv_check_firewall')),
              para(tr('pv_check_trackers')),
            ] else
              para(tr('pv_check_windows')),
            para(tr('pv_check_code')),
            para(tr('pv_check_build')),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: () => _copy(sourceUrl), child: Text(tr('pv_copy_repo'))),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// One place the app may connect to: name, addresses, when, what goes there.
class _Destination extends StatelessWidget {
  const _Destination({required this.title, required this.hosts, required this.when, required this.what});

  final String title;
  final String hosts;
  final String when;
  final String what;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = Ledger.mutedOf(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Ledger.ruleOf(context)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15)),
        const SizedBox(height: 2),
        Text(hosts, style: mono(size: 12, weight: FontWeight.w400, color: muted)),
        const SizedBox(height: 4),
        Text(when, style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(what, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
      ]),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow(this.e);

  final NetEntry e;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = Ledger.mutedOf(context);
    final time = DateFormat('d MMM, HH:mm:ss', intlLocale).format(e.time);
    final String result;
    Color? color;
    if (e.blocked != null) {
      result = tr(e.blocked == 'off' ? 'pv_blocked_off' : 'pv_blocked_host');
      color = Ledger.goodOf(context);
    } else if (e.error != null) {
      result = tr('pv_failed', [e.error]);
      color = Ledger.badOf(context);
    } else if (e.status == null) {
      result = tr('pv_no_answer');
    } else {
      result = '↑ ${formatBytes(e.sent)}  ↓ ${formatBytes(e.received)}${e.status == 200 ? '' : '  HTTP ${e.status}'}';
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Ledger.ruleOf(context)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(e.host, style: mono(size: 13, weight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
          Text(time, style: mono(size: 11, weight: FontWeight.w400, color: muted)),
        ]),
        Text('${netPurposeName(e.purpose)} · ${e.method} ${e.path}',
            style: theme.textTheme.bodySmall?.copyWith(color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(result, style: mono(size: 12, weight: FontWeight.w400, color: color ?? muted)),
      ]),
    );
  }
}

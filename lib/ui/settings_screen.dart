import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../domain/currencies.dart';
import '../domain/money.dart';
import '../io/home_widgets.dart';
import '../l10n/strings.dart';
import '../net/net_gate.dart';
import '../platform.dart';
import '../state/app_state.dart';
import '../version.dart';
import 'bank_log_screen.dart';
import 'data_screens.dart';
import 'envelopes_screen.dart';
import 'home_screen.dart';
import 'household_screen.dart';
import 'ledger.dart';
import 'lock_screen.dart';
import 'onboarding.dart';
import 'plus_screen.dart';
import 'privacy_screen.dart';
import 'recurring_screen.dart';
import 'statement_import_screen.dart';
import 'sync_screen.dart';
import 'tax_screen.dart';
import 'widgets.dart';

/// Currency name in the app language (full names exist in Russian; other languages show the code).
String currencyLabel(String code) {
  final c = currencyByCode[code];
  if (c == null) return code;
  return intlLocale == 'ru' ? '${c.name} ($code)' : '$code ${c.symbol}';
}

/// Settings, short: what most people need on one screen, the rest one tap deeper
/// ("More features", "Import and export", the help). Every feature is still a tap or two away.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final budget = state.rawMonthBudget(DateTime.now());

    Future<void> toggleBudget(bool on) async {
      if (on && budget == 0) {
        await editBudgetDialog(context);
      } else {
        await state.setBudgetEnabled(on);
      }
    }

    final good = Ledger.goodOf(context);
    final bad = Ledger.badOf(context);
    final backupValue = state.backupConfigured
        ? (state.backupLast == null ? tr('never') : DateFormat('dd.MM HH:mm', intlLocale).format(state.backupLast!))
        : tr('lock_value_off');
    final code = state.baseCurrency;
    final featuresOn = moreFeaturesOn(state);

    return Scaffold(
      appBar: AppBar(title: Text(tr('settings'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        // Automatic recording reads the phone's notifications and screens: not on the computer.
        if (!appIsDesktop)
          LedgerTile(
            tr('capture'),
            hint: state.captureReady ? null : tr('capture_setup_needed'),
            value: state.captureReady ? tr('capture_on') : '!',
            valueColor: state.captureReady ? good : bad,
            onTap: () => push(const CaptureSetupScreen()),
          ),
        LedgerSection(tr('budget'), padding: const EdgeInsets.fromLTRB(16, 18, 16, 0)),
        // One row for the budget: the switch turns it on or off, a tap changes the amount.
        LedgerTile(
          tr('budget_on_switch'),
          hint: state.budgetEnabled ? null : tr('budget_off_sub'),
          value: state.budgetEnabled ? formatMoney(budget, code) : null,
          valueColor: Ledger.accentOf(context),
          trailing: LedgerSwitch(value: state.budgetEnabled, onChanged: toggleBudget),
          onTap: () => state.budgetEnabled ? editBudgetDialog(context) : toggleBudget(true),
        ),
        if (state.budgetEnabled)
          LedgerTile(
            tr('daily_limit_mode'),
            value: tr(state.fixedDailyLimit ? 'daily_limit_fixed_short' : 'daily_limit_even_short'),
            onTap: () => chooseDailyLimitMode(context),
          ),
        LedgerTile(
          tr('categories'),
          value: '${state.categoriesOf(TxnKind.expense).length} + ${state.categoriesOf(TxnKind.income).length}',
          onTap: () => push(const CategoriesScreen()),
        ),
        LedgerTile(
          tr('recurring'),
          hint: tr('recurring_sub'),
          value: state.recurring.isEmpty ? null : '${state.recurring.length}',
          onTap: () => push(const RecurringScreen()),
        ),
        LedgerTile(
          tr('base_currency'),
          value: '$code ${currencySymbol(code)}',
          onTap: () async {
            final picked = await pickCurrency(context, selected: code);
            if (picked != null) await state.setBaseCurrency(picked);
          },
        ),
        LedgerSection(tr('settings_data')),
        // The computer keeps its copy through sync; backups to a folder are the phone's.
        if (!appIsDesktop)
          LedgerTile(
            tr('backup'),
            // Off: a short value, the explanation under the label (it doesn't fit as a value).
            hint: state.backupConfigured ? null : tr('backup_off'),
            value: backupValue,
            valueColor: state.backupConfigured ? good : bad,
            onTap: () => push(const BackupScreen()),
          ),
        LedgerTile(
          tr('sync'),
          hint: tr(appIsDesktop ? 'sync_sub_desktop' : 'sync_sub_phone'),
          value: tr(state.sync.enabled ? 'lock_value_on' : 'lock_value_off'),
          valueColor: state.sync.enabled ? good : null,
          onTap: () => push(const SyncScreen()),
        ),
        LedgerTile(tr('ux_io'), hint: tr('ux_io_sub'), onTap: () => push(const ImportExportScreen())),
        LedgerSection(tr('ux_sec_features')),
        // What is switched on shows here, so nobody has to remember where it went.
        LedgerTile(
          tr('ux_more'),
          hint: featuresOn.isEmpty ? tr('ux_more_sub') : tr('ux_more_on', [featuresOn.join(', ')]),
          onTap: () => push(const MoreFeaturesScreen()),
        ),
        LedgerTile(
          tr('plus_title'),
          hint: plusTileHint(state.plusStatus),
          value: tr(state.isPlus ? 'on_m' : 'off_m'),
          valueColor: state.isPlus ? Ledger.accentOf(context) : null,
          onTap: () => push(const PlusScreen()),
        ),
        LedgerSection(tr('settings_general')),
        ListenableBuilder(
          listenable: appLock,
          builder: (context, _) => LedgerTile(
            tr('lock'),
            hint: tr('lock_sub'),
            value: appLock.enabled ? tr('lock_value_on') : tr('lock_value_off'),
            onTap: () => push(const LockSettingsScreen()),
          ),
        ),
        // Privacy, next to the app lock: what goes to the internet, and the switch to stop it.
        ListenableBuilder(
          listenable: netGate,
          builder: (context, _) => LedgerTile(
            tr('pv_title'),
            hint: tr('pv_tile_sub'),
            value: netGate.off ? tr('pv_offline_short') : null,
            onTap: () => push(const PrivacyScreen()),
          ),
        ),
        LedgerTile(tr('language'), value: languageNames[currentLanguage] ?? currentLanguage, onTap: () => chooseLanguage(context)),
        LedgerTile(
          tr('country'),
          value: '${countryFlags[state.country] ?? ''} ${tr('country_${state.country}')}',
          onTap: () => chooseCountry(context),
        ),
        LedgerTile(tr('help'), onTap: () => push(const HelpScreen())),
        // The version, and where new ones are: the link goes to the clipboard (no browser plugin).
        LedgerTile(
          tr('about_app'),
          hint: tr('about_app_sub'),
          value: appVersion,
          onTap: () async {
            await Clipboard.setData(const ClipboardData(text: releasesUrl));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('about_link_copied', [releasesUrl]))));
            }
          },
        ),
      ]),
    );
  }
}

/// The optional features that are switched on, by name (for the "More features" row).
List<String> moreFeaturesOn(AppState state) => [
      if (state.envelopes.on) tr('env_title'),
      if (state.householdOn) tr('hh_title'),
    ];

/// Features most people never need, kept off the main Settings screen.
class MoreFeaturesScreen extends StatelessWidget {
  const MoreFeaturesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final good = Ledger.goodOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('ux_more'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        LedgerSection(tr('ux_sec_planning'), padding: const EdgeInsets.fromLTRB(16, 18, 16, 0)),
        LedgerTile(
          tr('env_title'),
          hint: tr('env_tile_sub'),
          value: tr(state.envelopes.on ? 'on_pl' : 'off_pl'),
          valueColor: state.envelopes.on ? good : null,
          onTap: () => push(const EnvelopesScreen()),
        ),
        LedgerTile(
          tr('hh_title'),
          hint: tr('hh_tile_sub'),
          value: state.householdOn ? state.people.map((p) => p.name).join(', ') : tr('off_m'),
          valueColor: state.householdOn ? good : null,
          onTap: () => push(const HouseholdScreen()),
        ),
        LedgerTile(tr('tax_title'), hint: tr('tax_tile_sub'), onTap: () => push(const TaxScreen())),
        LedgerSection(tr('ux_sec_currencies')),
        LedgerTile(tr('rates'), hint: tr('rates_sub'), onTap: () => push(const RatesScreen())),
        // The phone reminds and has the widgets; the computer has neither.
        if (!appIsDesktop) ...[
          LedgerSection(tr('ux_sec_reminders')),
          LedgerTile(
            tr('evening_setting'),
            hint: tr('evening_setting_sub'),
            value: state.eveningReminder == 'off' ? tr('off_n') : state.eveningReminder,
            onTap: () => _chooseEvening(context, state),
          ),
          if (Platform.isAndroid) LedgerTile(tr('w_add'), hint: tr('w_add_sub'), onTap: () => _addWidgetSheet(context)),
        ],
      ]),
    );
  }
}

/// Getting data in (bank statements, a spreadsheet) and out (Excel or CSV).
class ImportExportScreen extends StatelessWidget {
  const ImportExportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: Text(tr('ux_io'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        LedgerSection(tr('ux_sec_import'), padding: const EdgeInsets.fromLTRB(16, 18, 16, 0)),
        LedgerTile(tr('stmt_title'), hint: tr('stmt_tile_sub'), onTap: () => push(const StatementImportScreen())),
        LedgerTile(tr('import_excel'), hint: tr('import_excel_sub'), onTap: () => push(const SheetImportScreen())),
        LedgerSection(tr('ux_sec_export')),
        LedgerTile(tr('export'), value: tr('export_sub'), onTap: () => showExportSheet(context)),
      ]),
    );
  }
}

Future<void> chooseCountry(BuildContext context) async {
  final state = context.read<AppState>();
  final c = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(tr('country')),
      children: [
        for (final code in countries)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, code),
            child: Row(children: [
              Text(countryFlags[code]!, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Text(tr('country_$code')),
              if (code == state.country) ...[const Spacer(), const Icon(Icons.check)],
            ]),
          ),
      ],
    ),
  );
  if (c == null || c == state.country || !context.mounted) return;
  await state.setCountry(c);
  final currency = AppState.countryCurrency[c]!;
  if (currency == state.baseCurrency || !context.mounted) return;
  final change = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('change_currency_q', [currencyLabel(currency)])),
      content: Text(tr('change_currency_sub')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('keep'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('change'))),
      ],
    ),
  );
  if (change == true) await state.setBaseCurrency(currency);
}

Future<void> chooseLanguage(BuildContext context) async {
  final state = context.read<AppState>();
  final l = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(tr('language')),
      children: [
        for (final e in languageNames.entries)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, e.key),
            child: Row(children: [
              Text(e.value),
              if (e.key == currentLanguage) ...[const Spacer(), const Icon(Icons.check)],
            ]),
          ),
      ],
    ),
  );
  if (l != null) await state.setLanguage(l);
}

/// Searchable currency list; returns the chosen ISO code.
Future<String?> pickCurrency(BuildContext context, {String? selected}) => Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _CurrencyPicker(selected: selected)),
    );

class _CurrencyPicker extends StatefulWidget {
  final String? selected;
  const _CurrencyPicker({this.selected});

  @override
  State<_CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<_CurrencyPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final list = currencies
        .where((c) => q.isEmpty || c.code.toLowerCase().contains(q) || c.name.toLowerCase().contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: InputDecoration(hintText: tr('search_currency'), border: InputBorder.none),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) {
          final c = list[i];
          return ListTile(
            leading: SizedBox(width: 44, child: Center(child: Text(c.symbol, style: const TextStyle(fontSize: 18)))),
            title: Text(intlLocale == 'ru' ? c.name : c.code),
            subtitle: intlLocale == 'ru' ? Text(c.code) : null,
            trailing: c.code == widget.selected ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, c.code),
          );
        },
      ),
    );
  }
}

class RatesScreen extends StatelessWidget {
  const RatesScreen({super.key});

  Future<void> _edit(BuildContext context, String quote) async {
    final state = context.read<AppState>();
    final base = state.baseCurrency;
    final current = state.rates.latest(quote);
    final controller = TextEditingController(text: current == null ? '' : formatRate(current));
    final result = await showDialog<Object>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('rate_title', [quote])),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(prefixText: '1 ${currencySymbol(base)} = ', suffixText: currencySymbol(quote)),
        ),
        actions: [
          if (state.rates.isManual(quote))
            TextButton(onPressed: () => Navigator.pop(c, 'auto'), child: Text(tr('rate_auto'))),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('cancel'))),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'));
              if (v != null && v > 0) Navigator.pop(c, v);
            },
            child: Text(tr('save')),
          ),
        ],
      ),
    );
    if (result == 'auto') await state.setManualRate(quote, null);
    if (result is double) await state.setManualRate(quote, result);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final base = state.baseCurrency;
    final quotes = state.foreignCurrencies.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text(tr('rates'))),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(tr('rates_explain', [currencyLabel(base)]), style: Theme.of(context).textTheme.bodySmall),
        ),
        if (netGate.off)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(tr('pv_rates_offline'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Ledger.badOf(context))),
          ),
        if (quotes.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr('no_other_currencies'))),
        for (final q in quotes)
          ListTile(
            leading: SizedBox(width: 44, child: Center(child: Text(currencySymbol(q), style: const TextStyle(fontSize: 18)))),
            title: Text(switch (state.rates.latest(q)) {
              null => '1 ${currencySymbol(base)} = ? ${currencySymbol(q)}',
              final r => '1 ${currencySymbol(base)} = ${formatRate(r)} ${currencySymbol(q)}',
            }),
            subtitle: Text(state.rates.isManual(q)
                ? tr('rate_manual')
                : state.rates.latest(q) == null
                    ? tr('rate_not_loaded')
                    : tr('rate_auto')),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _edit(context, q),
          ),
      ]),
    );
  }
}

/// Name + currency of an account; returns null when cancelled.
Future<(String, String)?> accountDialog(BuildContext context, {String name = '', String currency = 'CNY', required String title}) {
  final nameCtrl = TextEditingController(text: name);
  var cur = currency;
  return showDialog<(String, String)>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            autofocus: name.isEmpty,
            decoration: InputDecoration(labelText: tr('account_name_hint')),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('currency')),
            trailing: Text('${currencySymbol(cur)}  $cur'),
            onTap: () async {
              final code = await pickCurrency(c, selected: cur);
              if (code != null) setState(() => cur = code);
            },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('cancel'))),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) Navigator.pop(c, (nameCtrl.text.trim(), cur));
            },
            child: Text(tr('save')),
          ),
        ],
      ),
    ),
  );
}

/// The in-app disclosure Google Play requires before an app turns on an accessibility service for
/// something other than accessibility: what is read, what is not, where it is kept. Asked once;
/// true when the user agreed (now or before).
Future<bool> confirmCaptureDisclosure(BuildContext context) async {
  final state = context.read<AppState>();
  if (state.captureConsent) return true;
  final theme = Theme.of(context);
  Widget point(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ]),
      );
  final agreed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(tr('disclosure_t')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          point(Icons.visibility_outlined, tr('disclosure_reads')),
          point(Icons.visibility_off_outlined, tr('disclosure_not')),
          point(Icons.phone_android, tr('disclosure_keeps')),
          point(Icons.toggle_off_outlined, tr('disclosure_off')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('disclosure_later'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('disclosure_agree'))),
      ],
    ),
  );
  if (agreed != true) return false;
  await state.acceptCaptureConsent();
  return true;
}

/// One thing to switch on for automatic recording.
class _CaptureStep {
  final String title;
  final String subtitle;
  final bool done;

  /// The main button's label while this is the next step, and a line under it (or null).
  final String button;
  final String? hint;
  final Future<void> Function() open;

  /// A special access (Android settings screen) — the kind Android locks for apps from a file.
  final bool special;
  const _CaptureStep(this.title, this.subtitle, this.done, this.button, this.hint, this.open, {this.special = false});
}

/// Automatic recording: what it reads in one line, the steps as a checklist and one button that
/// always does the next thing. Android's lock for apps installed from a file is handled in place.
class CaptureSetupScreen extends StatefulWidget {
  /// Opened right after the first run: "Later" in the bar, "Done" at the end goes to the app.
  final bool firstRun;
  const CaptureSetupScreen({super.key, this.firstRun = false});

  @override
  State<CaptureSetupScreen> createState() => _CaptureSetupScreenState();
}

class _CaptureSetupScreenState extends State<CaptureSetupScreen> with WidgetsBindingObserver {
  /// "The switch won't turn on?" was tapped: the unlock walkthrough shows without detection.
  bool _unlockOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) context.read<AppState>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final st = state.captureStatus;
    final capture = state.capture;
    final needsScreen = state.captureNeedsScreen;
    final ready = state.captureReady;

    // Both special accesses open only after the in-app disclosure was accepted (Google Play policy).
    Future<void> withConsent(Future<void> Function() open) async {
      if (await confirmCaptureDisclosure(context)) await open();
    }

    // The notifications first: with bank cards they are all it takes. The screen reading is a
    // step only where it is needed (or already on); elsewhere it is offered once recording works.
    final steps = [
      _CaptureStep(tr('capture_step2'), tr('ux_step_notif_sub'), st.notifications, tr('ux_btn_on'), tr('ux_hint_switch'),
          () => withConsent(capture.openNotificationAccess),
          special: true),
      _CaptureStep(tr('capture_step3'), tr('ux_step_post_sub'), st.postNotifications, tr('ux_btn_post'), null,
          capture.requestPostNotifications),
      if (needsScreen || st.accessibility)
        _CaptureStep(tr('capture_step1'), tr('ux_step_screen_sub'), st.accessibility, tr('ux_btn_screen'), tr('ux_hint_list'),
            () => withConsent(capture.openAccessibility),
            special: true),
    ];
    final next = steps.where((s) => !s.done).firstOrNull;
    final special = next != null && next.special;
    // Locked by Android (installed from a file; or so the user says, as Android 13+ does not always
    // tell the app): lifting that is the next step, in place of the button.
    final locked = special && (st.restricted || (_unlockOpen && st.sdk >= 33));
    final unlock = _RestrictedGuide(onTry: () => next!.open(), onAppInfo: capture.openAppInfo);

    Widget stepRow(int n, _CaptureStep s) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 16,
            // Done: a green tick; the next step stands out; the later ones are pale.
            backgroundColor: s.done
                ? Colors.green
                : identical(s, next)
                    ? theme.colorScheme.primary
                    : theme.colorScheme.primaryContainer,
            child: s.done
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : Text('$n', style: identical(s, next) ? TextStyle(color: theme.colorScheme.onPrimary) : null),
          ),
          title: Text(s.title),
          subtitle: Text(s.subtitle),
          onTap: s.done ? null : s.open,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('capture')),
        automaticallyImplyLeading: !widget.firstRun,
        actions: [
          if (widget.firstRun && !ready) TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ux_later'))),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
        Row(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: ready ? Colors.green : theme.colorScheme.primaryContainer,
            child: Icon(ready ? Icons.check : Icons.auto_awesome, color: ready ? Colors.white : theme.colorScheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(tr(ready ? 'ux_cap_done_t' : 'ux_cap_t'), style: theme.textTheme.titleLarge)),
        ]),
        const SizedBox(height: 12),
        Text(tr(ready ? 'ux_cap_done_b' : (needsScreen ? 'ux_cap_b_screen' : 'ux_cap_b'))),
        const SizedBox(height: 12),
        // Locked: lifting the lock comes before the steps (its text points down to them).
        if (locked) ...[unlock, const SizedBox(height: 8)],
        for (var i = 0; i < steps.length; i++) stepRow(i + 1, steps[i]),
        const SizedBox(height: 12),
        if (locked)
          const SizedBox.shrink()
        else if (next != null) ...[
          FilledButton(onPressed: next.open, child: Text(next.button)),
          if (next.hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(next.hint!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ),
          // Android 13+ may lock the switch without saying so to the app: the walkthrough on request.
          if (special && st.sdk >= 33)
            TextButton(onPressed: () => setState(() => _unlockOpen = true), child: Text(tr('ux_cant_switch'))),
        ] else if (widget.firstRun)
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('done'))),
        // Bank cards work without reading the screen; those who also pay with Alipay or WeChat add it.
        if (ready && !st.accessibility)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.qr_code_2),
            title: Text(tr('ux_screen_offer_t')),
            subtitle: Text(tr('ux_screen_offer_b')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => withConsent(capture.openAccessibility),
          ),
        if (st.notifications) ...[
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_balance_outlined),
            title: Text(tr('bank_log')),
            subtitle: Text(tr('bank_log_sub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BankLogScreen())),
          ),
          Text(tr('bank_history_hint'), style: theme.textTheme.bodySmall),
        ],
      ]),
    );
  }
}

/// Android's lock on special accesses for an app installed from a file, lifted in two moves:
/// try the switch (Android then says "Restricted setting" and only after that offers the way
/// out), then App info → ⋮ → "Allow restricted settings". The screen notices when it is done.
class _RestrictedGuide extends StatefulWidget {
  final VoidCallback onTry;
  final VoidCallback onAppInfo;
  const _RestrictedGuide({required this.onTry, required this.onAppInfo});

  @override
  State<_RestrictedGuide> createState() => _RestrictedGuideState();
}

class _RestrictedGuideState extends State<_RestrictedGuide> {
  bool _tried = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget move(int n, String text, String button, VoidCallback onTap, {bool done = false, bool primary = false}) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: done ? Colors.green : theme.colorScheme.primary,
              child: done
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text('$n', style: TextStyle(fontSize: 13, color: theme.colorScheme.onPrimary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text),
                const SizedBox(height: 8),
                primary
                    ? FilledButton(onPressed: onTap, child: Text(button))
                    : FilledButton.tonal(onPressed: onTap, child: Text(button)),
              ]),
            ),
          ]),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.lock_outline, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('rs_title'), style: theme.textTheme.titleSmall)),
          ]),
          const SizedBox(height: 6),
          Text(tr('rs_why'), style: theme.textTheme.bodySmall),
          move(1, tr('rs_a'), tr('rs_a_btn'), () {
            setState(() => _tried = true);
            widget.onTry();
          }, done: _tried, primary: !_tried),
          move(2, tr('rs_b'), tr('rs_b_btn'), widget.onAppInfo, primary: _tried),
          const SizedBox(height: 10),
          Text(tr('rs_after'), style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    Widget section(String title, TxnKind kind) {
      final cats = state.categoriesOf(kind);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        for (final c in cats)
          ListTile(
            leading: CategoryAvatar(c, size: 36),
            title: Text(state.categoryName(c)),
            onTap: () async {
              final r = await showCategoryDialog(context,
                  title: tr('category'), name: state.categoryName(c), icon: c.icon, color: c.color);
              if (r != null) await state.updateCategory(c, name: r.$1, icon: r.$2, color: r.$3);
            },
            trailing: IconButton(
              icon: const Icon(Icons.archive_outlined),
              tooltip: tr('hide'),
              onPressed: () => state.archiveCategory(c),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.add),
          title: Text(tr('add')),
          onTap: () async {
            final r = await showCategoryDialog(context,
                title: tr('new_category'), color: categoryColors[cats.length % categoryColors.length]);
            if (r != null) await state.addCategory(r.$1, kind, r.$2, r.$3);
          },
        ),
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('categories'))),
      body: ListView(children: [
        section(tr('expense_categories'), TxnKind.expense),
        section(tr('income_categories'), TxnKind.income),
      ]),
    );
  }
}

/// One explanation per feature.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _topics = [
    ('help_budget', Icons.account_balance_wallet_outlined),
    ('help_capture', Icons.auto_awesome),
    ('help_review', Icons.bolt),
    ('help_overview', Icons.insights),
    ('help_analytics', Icons.query_stats),
    ('help_split', Icons.call_split),
    ('help_money', Icons.savings_outlined),
    ('help_currency', Icons.currency_exchange),
    ('help_backup', Icons.cloud_outlined),
    ('help_sync', Icons.devices_outlined),
    ('help_household', Icons.people_outline),
    ('help_statements', Icons.upload_file_outlined),
    ('help_envelopes', Icons.mail_outline),
    ('help_networth', Icons.trending_up),
    ('help_taxes', Icons.receipt_long_outlined),
    ('help_plus', Icons.workspace_premium_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('help'))),
      body: ListView(children: [
        // The swipeable intro (no longer part of the first run), for whoever wants the tour.
        ListTile(
          leading: const Icon(Icons.slideshow_outlined),
          title: Text(tr('show_guide')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuideScreen(closeOnFinish: true))),
        ),
        for (final (key, icon) in _topics)
          ExpansionTile(
            leading: Icon(icon),
            title: Text(tr('${key}_t')),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [Text(tr('${key}_b'))],
          ),
      ]),
    );
  }
}

/// The five home-screen widgets; a tap asks the launcher to place one (it shows its own dialog).
Future<void> _addWidgetSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          LedgerSection(tr('w_add'), padding: const EdgeInsets.fromLTRB(16, 0, 16, 4)),
          for (final (kind, name, size) in [
            ('CALENDAR', 'w_calendar', '4×2'),
            ('SUMMARY', 'w_summary', '2×2'),
            ('TODAY', 'w_today', '2×1'),
            ('RUNWAY', 'w_runway', '2×1'),
            ('QUICK', 'w_quick', '4×1'),
          ])
            LedgerTile(
              tr(name),
              value: size,
              trailing: Icon(Icons.add, color: Ledger.accentOf(c)),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(c);
                if (!await HomeWidgetsBridge.pin(kind)) {
                  messenger.showSnackBar(SnackBar(content: Text(tr('w_pin_unsupported'))));
                }
              },
            ),
        ]),
      ),
    );

/// The evening "nothing recorded today" reminder: a time, or off.
Future<void> _chooseEvening(BuildContext context, AppState state) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(tr('evening_setting'), style: Theme.of(sheet).textTheme.titleMedium),
        ),
        ListTile(leading: const Icon(Icons.schedule), title: Text(tr('evening_pick_time')), onTap: () => Navigator.pop(sheet, 'time')),
        ListTile(leading: const Icon(Icons.notifications_off_outlined), title: Text(tr('off_n')), onTap: () => Navigator.pop(sheet, 'off')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'off') return state.setEveningReminder('off');
  final parts = state.eveningReminder.split(':');
  final initial = parts.length == 2
      ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 21, minute: int.tryParse(parts[1]) ?? 0)
      : const TimeOfDay(hour: 21, minute: 0);
  final t = await showTimePicker(context: context, initialTime: initial);
  if (t == null) return;
  await state.setEveningReminder('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
  await state.capture.requestPostNotifications();
}

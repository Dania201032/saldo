import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../domain/currencies.dart';
import '../l10n/strings.dart';
import '../platform.dart';
import '../state/app_state.dart';
import 'data_screens.dart';
import 'sync_screen.dart';

/// Countries offered at the first start and in Settings, in this order.
const countries = ['CN', 'RU', 'KZ', 'DE', 'NL', 'KR'];
const countryFlags = {'CN': '🇨🇳', 'RU': '🇷🇺', 'KZ': '🇰🇿', 'DE': '🇩🇪', 'NL': '🇳🇱', 'KR': '🇰🇷'};

/// First start, kept short: language -> country -> monthly budget. On the phone the recording
/// setup follows on top of the home screen (Shell). The app lock and the intro guide stay in
/// Settings; a first run with more pages lost people before they reached the app.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  int _step = 0;
  String _country = 'CN';
  late String _lang;

  @override
  void initState() {
    super.initState();
    _lang = currentLanguage;
    _country = context.read<AppState>().country;
  }

  void _setLang(String l) => setState(() {
        _lang = l;
        currentLanguage = l;
      });

  /// [budgetMinor] null: no budget, only spending and income are counted.
  Future<void> _finish(int? budgetMinor) async {
    final state = context.read<AppState>();
    state.captureIntroPending = !appIsDesktop;
    await state.completeOnboarding(country: _country, lang: _lang, budgetMinor: budgetMinor, budgetOn: budgetMinor != null);
  }

  /// The computer: joins the phone's sync folder and opens with its data.
  Future<void> _joinPhone() async {
    final state = context.read<AppState>();
    final joined = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const SyncScreen(closeWhenJoined: true)));
    if (joined == true) await state.completeOnboarding(country: state.country, lang: _lang);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      // The language first, with its title in every language, so anyone can read the start.
      0 => _ChoicePage(
          title: tr('choose_language'),
          subtitle: 'Language · Язык · 语言 · Тіл · Sprache · Taal',
          options: [for (final e in languageNames.entries) (e.key, e.value)],
          selected: _lang,
          onSelect: _setLang,
          onNext: () => setState(() => _step = 1),
        ),
      1 => _ChoicePage(
          title: tr('choose_country'),
          subtitle: tr('choose_country_sub'),
          options: [for (final c in countries) (c, '${countryFlags[c]}  ${tr('country_$c')}')],
          selected: _country,
          onSelect: (c) => setState(() => _country = c),
          onBack: () => setState(() => _step = 0),
          onNext: () => setState(() => _step = 2),
          // The computer starts from the phone's data (sync); the phone from a backup file.
          footer: appIsDesktop
              ? TextButton.icon(
                  icon: const Icon(Icons.phone_android),
                  label: Text(tr('sync_have_phone')),
                  onPressed: _joinPhone,
                )
              : TextButton.icon(
                  icon: const Icon(Icons.restore),
                  label: Text(tr('have_backup')),
                  onPressed: () => restoreFromBackupFile(context),
                ),
        ),
      _ => _BudgetPage(
          // A new page per country: its currency and starting amount.
          key: ValueKey(_country),
          country: _country,
          onBack: () => setState(() => _step = 1),
          onDone: _finish,
        ),
    };
  }
}

class _ChoicePage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<(String, String)> options;
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final Widget? footer;

  const _ChoicePage({
    required this.title,
    this.subtitle,
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.onNext,
    this.onBack,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(leading: onBack == null ? null : BackButton(onPressed: onBack)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('welcome'), style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.headlineSmall),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 24),
            // Scrolls on small screens: six countries, seven languages.
            Expanded(
              child: ListView(children: [
                for (final (value, label) in options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      color: value == selected ? theme.colorScheme.primaryContainer : null,
                      child: ListTile(
                        title: Text(label, style: theme.textTheme.titleMedium),
                        trailing: value == selected ? const Icon(Icons.check_circle) : null,
                        onTap: () => onSelect(value),
                      ),
                    ),
                  ),
              ]),
            ),
            ?footer,
            FilledButton(onPressed: onNext, child: Text(tr('next'))),
          ]),
        ),
      ),
    );
  }
}


/// "How much to spend a month?": the figure behind "You can still spend today", prefilled with
/// the country's usual amount, or no budget at all.
class _BudgetPage extends StatefulWidget {
  final String country;
  final VoidCallback onBack;
  final Future<void> Function(int? budgetMinor) onDone;
  const _BudgetPage({super.key, required this.country, required this.onBack, required this.onDone});

  @override
  State<_BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<_BudgetPage> {
  late final _amount = TextEditingController(text: '${Repository.countryPreset(widget.country).$3 ~/ 100}');
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _done(bool withBudget) async {
    final v = double.tryParse(_amount.text.replaceAll(RegExp(r'[s ]'), '').replaceAll(',', '.'));
    if (withBudget && (v == null || v <= 0)) return;
    setState(() => _busy = true);
    await widget.onDone(withBudget ? (v! * 100).round() : null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = Repository.countryPreset(widget.country).$1;
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: widget.onBack)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('welcome'), style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 8),
            Text(tr('ux_budget_t'), style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(tr('ux_budget_b'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9s.,]'))],
              style: theme.textTheme.headlineMedium,
              decoration: InputDecoration(suffixText: currencySymbol(currency)),
              onSubmitted: (_) => _done(true),
            ),
            const Spacer(),
            FilledButton(onPressed: _busy ? null : () => _done(true), child: Text(tr('next'))),
            const SizedBox(height: 8),
            TextButton(onPressed: _busy ? null : () => _done(false), child: Text(tr('ux_budget_none'))),
          ]),
        ),
      ),
    );
  }
}

/// Up to 5 swipeable steps. From onboarding: [onFinish]; from settings: [closeOnFinish].
class GuideScreen extends StatefulWidget {
  final Future<void> Function()? onFinish;
  final bool closeOnFinish;
  const GuideScreen({super.key, this.onFinish, this.closeOnFinish = false});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  final _pages = PageController();
  int _index = 0;

  static const _steps = [
    ('guide1', Icons.today),
    ('guide2', Icons.auto_awesome),
    ('guide3', Icons.call_split),
    ('guide4', Icons.savings_outlined),
    ('guide5', Icons.cloud_done_outlined),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    if (widget.onFinish != null) await widget.onFinish!();
    if (widget.closeOnFinish && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _index == _steps.length - 1;
    return Scaffold(
      appBar: AppBar(actions: [if (!last) TextButton(onPressed: _done, child: Text(tr('skip')))]),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _index = i),
              children: [
                for (final (key, icon) in _steps)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(icon, size: 48, color: theme.colorScheme.primary),
                      ),
                      const SizedBox(height: 32),
                      Text(tr('${key}_t'), style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      Text(tr('${key}_b'), style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
                    ]),
                  ),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _steps.length; i++)
              Container(
                margin: const EdgeInsets.all(4),
                width: i == _index ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _index ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: last
                    ? _done
                    : () => _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: Text(last ? tr('start') : tr('next')),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

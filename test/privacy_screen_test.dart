import 'package:budget_app/l10n/strings.dart';
import 'package:budget_app/net/net_gate.dart';
import 'package:budget_app/ui/ledger.dart' show LedgerSwitch;
import 'package:budget_app/ui/privacy_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  testWidgets('the privacy screen lists the addresses, shows the log and switches the internet off', (tester) async {
    await initializeDateFormatting();
    currentLanguage = 'ru';
    final store = <String, String>{};
    await netGate.attach(read: (k) async => store[k], write: (k, v) async => store[k] = v);
    await netGate.client(NetPurpose.rates, inner: MockClient((_) async => http.Response('{}', 200)))
        .get(Uri.parse('https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/cny.json'));
    await netGate.flush();

    await tester.pumpWidget(const MaterialApp(home: PrivacyScreen()));
    await tester.pumpAndSettle();
    expect(find.text(tr('pv_title')), findsOneWidget);
    expect(find.textContaining('cdn.jsdelivr.net, *.currency-api.pages.dev'), findsOneWidget);
    expect(find.textContaining('api.bunq.com'), findsOneWidget);

    await tester.tap(find.byType(LedgerSwitch));
    await tester.pumpAndSettle();
    expect(netGate.off, isTrue);
    expect(store['net_off'], '1');

    await tester.scrollUntilVisible(find.text('cdn.jsdelivr.net'), 300);
    expect(find.text('cdn.jsdelivr.net'), findsOneWidget, reason: 'the logged request');

    await tester.tap(find.byTooltip(tr('pv_log_clear')));
    await tester.pumpAndSettle();
    expect(netGate.entries, isEmpty);
    await netGate.setOff(false);
  });
}

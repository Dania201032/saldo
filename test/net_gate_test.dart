import 'dart:convert';

import 'package:budget_app/data/database.dart';
import 'package:budget_app/data/rates.dart';
import 'package:budget_app/net/net_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The settings table, as the gate sees it.
class _Store {
  final values = <String, String>{};
  Future<String?> read(String k) async => values[k];
  Future<void> write(String k, String v) async => values[k] = v;
}

Future<NetGate> _gate(_Store store) async {
  final g = NetGate();
  await g.attach(read: store.read, write: store.write);
  return g;
}

const _ratesUrl = 'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/cny.json';

void main() {
  test('every request is logged: host, path, bytes, answer; nothing of the body or query is kept', () async {
    final store = _Store();
    final gate = await _gate(store);
    final c = gate.client(NetPurpose.rates, inner: MockClient((_) async => http.Response('hello', 200)));
    final res = await c.get(Uri.parse('$_ratesUrl?secret=1'));
    expect(res.body, 'hello');
    await gate.flush();

    final e = gate.entries.single;
    expect((e.purpose, e.host, e.method, e.path, e.status, e.received), (
      NetPurpose.rates,
      'cdn.jsdelivr.net',
      'GET',
      '/npm/@fawazahmed0/currency-api@latest/v1/currencies/cny.json',
      200,
      5,
    ));
    expect(e.sent, greaterThan(0));
    expect(store.values['net_log'], isNot(contains('secret')));
    expect((jsonDecode(store.values['net_log']!) as List).single['h'], 'cdn.jsdelivr.net');
  });

  test('switched off: nothing reaches the network, the attempt is logged as blocked', () async {
    final store = _Store();
    final gate = await _gate(store);
    var calls = 0;
    final c = gate.client(NetPurpose.bunq, inner: MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    }));
    await gate.setOff(true);
    expect(store.values['net_off'], '1');
    await expectLater(c.get(Uri.parse('https://api.bunq.com/v1/user')), throwsA(isA<NetBlocked>()));
    expect(calls, 0);
    expect(gate.entries.single.blocked, 'off');

    // The switch survives a restart.
    expect((await _gate(store)).off, isTrue);
    await gate.setOff(false);
    await c.get(Uri.parse('https://api.bunq.com/v1/user'));
    expect(calls, 1);
  });

  test('only the listed addresses, only over https', () async {
    final gate = await _gate(_Store());
    final ok = MockClient((_) async => http.Response('', 200));
    final rates = gate.client(NetPurpose.rates, inner: ok);
    await rates.get(Uri.parse('https://2026-10-01.currency-api.pages.dev/v1/currencies/cny.json'));
    for (final url in [
      'https://example.com/v1/currencies/cny.json',
      'https://cdn.jsdelivr.net/npm/other-package/x.json',
      'http://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/cny.json',
    ]) {
      await expectLater(rates.get(Uri.parse(url)), throwsA(isA<NetBlocked>()), reason: url);
    }
    await expectLater(gate.client(NetPurpose.bunq, inner: ok).get(Uri.parse('https://evil.example/v1')), throwsA(isA<NetBlocked>()));
    // FinTS goes to the bank the user picked; it still has to be https.
    await gate.client(NetPurpose.fints, inner: ok).post(Uri.parse('https://fints.example.test/fints'));
    await expectLater(gate.client(NetPurpose.fints, inner: ok).post(Uri.parse('http://fints.example.test/')), throwsA(isA<NetBlocked>()));
    expect(gate.entries.where((e) => e.blocked == 'host'), hasLength(5));
    expect(NetPurpose.values.every(netDestinations.containsKey), isTrue);
  });

  test('a failed request is logged with its error and still fails', () async {
    final gate = await _gate(_Store());
    final c = gate.client(NetPurpose.rates, inner: MockClient((_) async => throw http.ClientException('no route')));
    await expectLater(c.get(Uri.parse(_ratesUrl)), throwsA(isA<http.ClientException>()));
    expect(gate.entries.single.error, 'no route');
  });

  test('two engines (app + widgets in the background) write one log; clearing empties it', () async {
    final store = _Store();
    final app = await _gate(store), background = await _gate(store);
    final ok = MockClient((_) async => http.Response('x', 200));
    await app.client(NetPurpose.rates, inner: ok).get(Uri.parse(_ratesUrl));
    await app.flush();
    await background.client(NetPurpose.rates, inner: ok).get(Uri.parse(_ratesUrl.replaceFirst('latest', '2026-10-01')));
    await background.flush();
    await app.reload();
    expect(app.entries, hasLength(2));
    expect((jsonDecode(store.values['net_log']!) as List), hasLength(2));

    await app.clearLog();
    await app.reload();
    expect(app.entries, isEmpty);
    expect(store.values['net_log'], '[]');
  });

  test('the log keeps the last ${NetGate.keep}', () async {
    final store = _Store();
    final gate = await _gate(store);
    final c = gate.client(NetPurpose.rates, inner: MockClient((_) async => http.Response('', 200)));
    for (var i = 0; i < NetGate.keep + 5; i++) {
      await c.get(Uri.parse(_ratesUrl));
    }
    await gate.flush();
    expect(gate.entries, hasLength(NetGate.keep));
    expect((jsonDecode(store.values['net_log']!) as List), hasLength(NetGate.keep));
    expect(gate.totalSince(DateTime(2000)).$1, NetGate.keep);
  });

  group('exchange rates', () {
    sqfliteFfiInit();
    late Database db;
    setUp(() async => db = await openAppDatabase(path: inMemoryDatabasePath, factory: databaseFactoryFfi));
    tearDown(() async {
      await netGate.setOff(false);
      await db.close();
    });

    test('go through the gate, and ask for nothing while offline', () async {
      final store = _Store();
      await netGate.attach(read: store.read, write: store.write);
      final asked = <Uri>[];
      final r = RatesService(db, client: MockClient((req) async {
        asked.add(req.url);
        return http.Response(jsonEncode({'date': '2026-10-01', 'cny': {'rub': 12.5}}), 200);
      }));
      await r.load('CNY');

      await netGate.setOff(true);
      await r.ensure([DateTime(2026, 10, 1)], {'RUB'});
      expect(asked, isEmpty);
      expect(netGate.entries, isEmpty, reason: 'no blocked entry per refresh either');
      expect(r.rate('RUB', DateTime(2026, 10, 1)), isNull);

      await netGate.setOff(false);
      await r.ensure([DateTime(2026, 10, 1)], {'RUB'});
      expect(asked, hasLength(1));
      expect(netGate.entries.single.purpose, NetPurpose.rates);
      expect(r.rate('RUB', DateTime(2026, 10, 1)), 12.5);
    });
  });
}

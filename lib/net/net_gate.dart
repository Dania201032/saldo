import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:http/http.dart' as http;

/// The one door of the app to the internet. Every request the app itself makes goes through
/// [NetGate.client]: it is checked against the list below, written to the log the user sees
/// (Settings → Privacy and internet), and refused while the user has switched the internet off.
///
/// test/net_guard_test.dart fails if any other file opens a connection (http.Client(), HttpClient,
/// sockets…), so this file and [netDestinations] stay the complete list.

/// Why the app goes online. Each one has its fixed addresses ([NetGate.refusal]).
enum NetPurpose { rates, bunq, fints }

/// Where the app may connect, for the privacy screen (texts in lib/l10n/strings_privacy.dart).
const netDestinations = <NetPurpose, List<String>>{
  // Exchange rates: fawazahmed0/exchange-api on jsDelivr, its Cloudflare mirror as fallback (lib/data/rates.dart).
  NetPurpose.rates: ['cdn.jsdelivr.net', '*.currency-api.pages.dev'],
  // bunq's API, only when the user downloads a statement (lib/import/bunq.dart).
  NetPurpose.bunq: ['api.bunq.com', 'public-api.sandbox.bunq.com'],
  // The user's German bank (FinTS), the address from lib/import/fints/fints_banks.dart or typed in.
  NetPurpose.fints: [],
};

/// One request: what, where, how much. No headers, bodies or query strings are kept.
class NetEntry {
  NetEntry({
    required this.time,
    required this.purpose,
    required this.method,
    required this.host,
    required this.path,
    this.sent = 0,
    this.received = 0,
    this.status,
    this.error,
    this.blocked,
    this.done = false,
  });

  final DateTime time;
  final NetPurpose purpose;
  final String method;
  final String host;
  final String path;

  /// About how many bytes went out: the request line, the headers set here and the body.
  int sent;

  /// Bytes of the answer's body as read (encryption and compression come on top or off).
  int received;
  int? status;
  String? error;

  /// Not sent: 'off' (the internet is switched off) or 'host' (an address not in the list).
  String? blocked;
  bool done;

  String get _id => '${time.microsecondsSinceEpoch}|$host|$path';

  Map<String, Object?> toJson() => {
        't': time.microsecondsSinceEpoch,
        'p': purpose.name,
        'm': method,
        'h': host,
        'u': path,
        's': sent,
        'r': received,
        if (status != null) 'c': status,
        if (error != null) 'e': error,
        if (blocked != null) 'b': blocked,
      };

  static NetEntry? fromJson(Map<String, dynamic> j) {
    final purpose = NetPurpose.values.asNameMap()[j['p']];
    if (purpose == null) return null;
    return NetEntry(
      time: DateTime.fromMicrosecondsSinceEpoch((j['t'] as num).toInt()),
      purpose: purpose,
      method: j['m'] as String? ?? 'GET',
      host: j['h'] as String? ?? '',
      path: j['u'] as String? ?? '',
      sent: (j['s'] as num?)?.toInt() ?? 0,
      received: (j['r'] as num?)?.toInt() ?? 0,
      status: (j['c'] as num?)?.toInt(),
      error: j['e'] as String?,
      blocked: j['b'] as String?,
      done: true,
    );
  }
}

/// Thrown instead of connecting; a [http.ClientException], like a failed connection.
class NetBlocked extends http.ClientException {
  NetBlocked(this.reason, Uri url) : super('not sent ($reason)', url);

  /// 'off' or 'host', as in [NetEntry.blocked].
  final String reason;
}

class NetGate extends ChangeNotifier {
  /// How many requests the log keeps.
  static const keep = 300;

  bool _off = false;
  final _entries = <NetEntry>[];
  Future<String?> Function(String key)? _read;
  Future<void> Function(String key, String value)? _write;
  Future<void> _saving = Future.value();

  /// Entries older than this are not merged back from the database after "Clear".
  DateTime? _clearedAt;

  /// The user's "don't go online" switch: nothing is sent while it is on.
  bool get off => _off;

  /// The log, newest first.
  List<NetEntry> get entries => List.unmodifiable(_entries);

  /// Keeps the switch and the log in the app's settings (the encrypted database, this device
  /// only). Also called by the background engine that refreshes the widgets.
  Future<void> attach({required Future<String?> Function(String key) read, required Future<void> Function(String key, String value) write}) async {
    _read = read;
    _write = write;
    _clearedAt = null;
    _off = await read('net_off') == '1';
    _entries
      ..clear()
      ..addAll(_parse(await read('net_log')));
    notifyListeners();
  }

  /// Re-reads the log: the background engine may have added to it.
  Future<void> reload() async {
    final read = _read;
    if (read == null) return;
    _merge(_parse(await read('net_log')));
    notifyListeners();
  }

  Future<void> setOff(bool value) async {
    _off = value;
    notifyListeners();
    await _write?.call('net_off', value ? '1' : '0');
  }

  Future<void> clearLog() async {
    _clearedAt = DateTime.now();
    _entries.clear();
    notifyListeners();
    await (_saving = _saving.then((_) async {
      try {
        await _write?.call('net_log', '[]');
      } catch (_) {}
    }));
  }

  /// Done when everything logged so far is written (tests).
  Future<void> flush() => _saving;

  /// A client for [purpose]; [inner] replaces the real connection (tests).
  http.Client client(NetPurpose purpose, {http.Client? inner}) => _GateClient(this, purpose, inner ?? http.Client());

  /// Why a request to [url] for [purpose] is not sent, or null when it may go.
  String? refusal(NetPurpose purpose, Uri url) {
    if (_off) return 'off';
    if (url.scheme != 'https') return 'host';
    final host = url.host.toLowerCase();
    final ok = switch (purpose) {
      NetPurpose.rates => (host == 'cdn.jsdelivr.net' && url.path.startsWith('/npm/@fawazahmed0/currency-api@')) ||
          host.endsWith('.currency-api.pages.dev'),
      NetPurpose.bunq => netDestinations[NetPurpose.bunq]!.contains(host),
      // The bank's server: the user picks or types it; it has to be https.
      NetPurpose.fints => host.isNotEmpty,
    };
    return ok ? null : 'host';
  }

  /// Requests since [since] and their bytes (out + in), from the log.
  (int count, int bytes) totalSince(DateTime since) {
    var count = 0, bytes = 0;
    for (final e in _entries) {
      if (e.blocked != null || e.time.isBefore(since)) continue;
      count++;
      bytes += e.sent + e.received;
    }
    return (count, bytes);
  }

  /// Logs [e] before it is sent (saved at once: a request that never ends still shows).
  void _add(NetEntry e) {
    _entries.insert(0, e);
    if (_entries.length > keep) _entries.removeRange(keep, _entries.length);
    notifyListeners();
    _save();
  }

  void _finish(NetEntry e) {
    if (e.done) return;
    e.done = true;
    notifyListeners();
    _save();
  }

  /// Writes the log, merged with what another engine may have written meanwhile.
  void _save() {
    final read = _read, write = _write;
    if (read == null || write == null) return;
    _saving = _saving.then((_) async {
      try {
        _merge(_parse(await read('net_log')));
        await write('net_log', jsonEncode([for (final e in _entries) e.toJson()]));
      } catch (_) {
        // The log is a convenience: a closed or busy database must not break the request.
      }
    });
  }

  void _merge(List<NetEntry> stored) {
    final have = {for (final e in _entries) e._id: e};
    for (final s in stored) {
      // Read earlier while another engine's request was still running: take its outcome.
      final m = have[s._id];
      if (m != null && m.done && m.status == null && m.error == null && m.blocked == null) {
        m
          ..status = s.status
          ..error = s.error
          ..sent = s.sent
          ..received = s.received;
      }
    }
    final cleared = _clearedAt;
    final added = stored.where((e) => !have.containsKey(e._id) && (cleared == null || e.time.isAfter(cleared))).toList();
    if (added.isEmpty) return;
    _entries
      ..addAll(added)
      ..sort((a, b) => b.time.compareTo(a.time));
    if (_entries.length > keep) _entries.removeRange(keep, _entries.length);
  }

  static List<NetEntry> _parse(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      return [
        for (final j in jsonDecode(json) as List)
          ?NetEntry.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }
}

/// The app's only gate to the internet.
final netGate = NetGate();

class _GateClient extends http.BaseClient {
  _GateClient(this.gate, this.purpose, this.inner);

  final NetGate gate;
  final NetPurpose purpose;
  final http.Client inner;

  static int _size(http.BaseRequest r) {
    var n = '${r.method} ${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''} HTTP/1.1\r\nHost: ${r.url.host}\r\n'.length;
    r.headers.forEach((k, v) => n += k.length + v.length + 4);
    return n + (r.contentLength ?? 0);
  }

  static String _short(Object e) {
    final s = e is http.ClientException ? e.message : e.toString();
    return s.length > 80 ? s.substring(0, 80) : s;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final e = NetEntry(
      time: DateTime.now(),
      purpose: purpose,
      method: request.method,
      host: request.url.host,
      path: request.url.path,
      sent: _size(request),
    );
    final why = gate.refusal(purpose, request.url);
    if (why != null) {
      e
        ..blocked = why
        ..sent = 0;
      gate._add(e);
      gate._finish(e);
      throw NetBlocked(why, request.url);
    }
    gate._add(e);
    final http.StreamedResponse res;
    try {
      res = await inner.send(request);
    } catch (err) {
      e.error = _short(err);
      gate._finish(e);
      rethrow;
    }
    e.status = res.statusCode;
    var n = 0;
    final counted = res.stream.transform(StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (data, sink) {
        n += data.length;
        sink.add(data);
      },
      handleError: (err, st, sink) {
        e
          ..received = n
          ..error = _short(err);
        gate._finish(e);
        sink.addError(err, st);
      },
      handleDone: (sink) {
        e.received = n;
        gate._finish(e);
        sink.close();
      },
    ));
    return http.StreamedResponse(
      http.ByteStream(counted),
      res.statusCode,
      contentLength: res.contentLength,
      request: res.request,
      headers: res.headers,
      isRedirect: res.isRedirect,
      persistentConnection: res.persistentConnection,
      reasonPhrase: res.reasonPhrase,
    );
  }

  @override
  void close() => inner.close();
}

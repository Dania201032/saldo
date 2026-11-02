import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The promise "no server, nothing leaves the device except what Settings → Privacy and internet
/// lists" as checks on the source, run with every build (also by the release workflow on GitHub).
/// A change that opens a connection elsewhere, adds a tracking library or turns Android's cloud
/// backup back on fails here first.
void main() {
  const gate = 'lib/net/net_gate.dart';

  String rel(File f) => f.path.replaceAll('\\', '/');

  test('only lib/net/net_gate.dart can open a connection (Dart)', () {
    // Ways to reach the network from Dart without going through NetGate.client.
    final forbidden = <String, RegExp>{
      'http.Client()': RegExp(r'http\.Client\(\)'),
      'IOClient': RegExp(r'\bIOClient\b|package:http/io_client\.dart'),
      'top-level http.get/post…': RegExp(r'\bhttp\.(get|post|put|patch|delete|head|read|readBytes)\('),
      'request.send()': RegExp(r'\bhttp\.(Request|StreamedRequest|MultipartRequest)\('),
      'HttpClient': RegExp(r'\bHttpClient\b'),
      'sockets': RegExp(r'\b(Socket|SecureSocket|RawSocket|RawSecureSocket|RawDatagramSocket|ServerSocket|HttpServer|WebSocket)\b'),
      'other network packages': RegExp(r'package:(dio|web_socket_channel|grpc|socket_io_client|firebase_\w+|sentry\w*)/'),
    };
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (rel(f) == gate) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        forbidden.forEach((what, re) {
          if (re.hasMatch(line)) hits.add('${rel(f)}:${i + 1} $what');
        });
      }
    }
    expect(hits, isEmpty, reason: 'go through netGate.client(NetPurpose…) and list the address in netDestinations');
  });

  test('the Android code opens no connections of its own (Kotlin)', () {
    final forbidden = RegExp(
        r'java\.net\.|HttpURLConnection|HttpsURLConnection|\bURL\(|openConnection|\bSocket\(|okhttp|retrofit|ktor|volley|DownloadManager|WebView');
    final hits = <String>[];
    for (final f in Directory('android/app/src/main/kotlin').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.kt'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (forbidden.hasMatch(lines[i]) && !lines[i].trimLeft().startsWith('//')) hits.add('${rel(f)}:${i + 1}');
      }
    }
    expect(hits, isEmpty);
  });

  test('no analytics, crash-report, ad or tracking libraries', () {
    final tracker = RegExp(
        r'firebase[-_](analytics|crashlytics|messaging|perf|remote)|crashlytics|sentry|appmetrica|amplitude|mixpanel|facebook|appsflyer|adjust_sdk|onesignal|play-services-(ads|analytics|measurement)|google_mobile_ads|bugsnag|datadog|newrelic|segment_analytics|posthog',
        caseSensitive: false);
    for (final path in ['pubspec.yaml', 'pubspec.lock', 'android/app/build.gradle.kts', 'android/build.gradle.kts']) {
      final f = File(path);
      if (!f.existsSync()) continue;
      expect(tracker.firstMatch(f.readAsStringSync())?.group(0), isNull, reason: path);
    }
  });

  test('the direct dependencies are the reviewed ones', () {
    // A new package can bring its own connections: add it here only after checking that it has none
    // (and say so on the privacy screen if it does).
    const reviewed = {
      'archive', 'crypto', 'cryptography', 'fast_gbk', 'file_picker', 'fl_chart', 'flutter', 'flutter_localizations',
      'flutter_secure_storage', 'http', 'intl', 'local_auth', 'path', 'path_provider', 'pointycastle', 'provider',
      'share_plus', 'sqflite_common', 'sqflite_common_ffi', 'sqflite_sqlcipher', 'xml',
    };
    final deps = <String>{};
    var inDeps = false;
    for (final line in File('pubspec.yaml').readAsLinesSync()) {
      if (!line.startsWith(' ') && line.trim().isNotEmpty) inDeps = line.startsWith('dependencies:');
      final m = RegExp(r'^  ([a-z0-9_]+):').firstMatch(line);
      if (inDeps && m != null) deps.add(m.group(1)!);
    }
    expect(deps.difference(reviewed), isEmpty, reason: 'new dependency: check it for network use first');

    // Android libraries (besides AndroidX): PDF text and ML Kit through Play services.
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final libs = RegExp(r'implementation\("([^:"]+):([^:"]+):').allMatches(gradle).map((m) => '${m.group(1)}:${m.group(2)}').toSet();
    expect(libs.where((l) => !l.startsWith('androidx.')).toSet(), {
      'com.tom-roush:pdfbox-android',
      'com.google.android.gms:play-services-mlkit-text-recognition-chinese',
      'com.google.android.gms:play-services-mlkit-barcode-scanning',
    });
  });

  test('ML Kit\'s usage statistics stay switched off, Android backups stay excluded', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      RegExp(r'android:name="backend:com\.google\.android\.datatransport\.cct\.CctBackendFactory"\s+tools:node="remove"').hasMatch(manifest),
      isTrue,
      reason: 'without it ML Kit uploads its logs to Google from the app',
    );
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));

    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
    for (final part in ['cloud-backup', 'device-transfer']) {
      final body = RegExp('<$part>(.*?)</$part>', dotAll: true).firstMatch(rules)?.group(1) ?? '';
      for (final domain in ['root', 'file', 'database', 'sharedpref', 'external']) {
        expect(body, contains('<exclude domain="$domain" path="." />'), reason: '$part $domain');
      }
      expect(body, isNot(contains('<include')));
    }
    final old = File('android/app/src/main/res/xml/backup_rules.xml').readAsStringSync();
    expect(old, isNot(contains('<include')));
  });
}

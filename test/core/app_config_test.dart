import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/config/app_config.dart';

String jwt(String role) {
  String enc(Object o) => base64Url.encode(utf8.encode(json.encode(o))).replaceAll('=', '');
  return '${enc({'alg': 'HS256'})}.${enc({'role': role})}.sig';
}

ConfigIssue? issueOf(ConfigState s) => s is ConfigProblem ? s.issue : null;

void main() {
  const url = 'https://abc.supabase.co';

  test('missing url or key -> missing', () {
    expect(issueOf(evaluateConfig(url: '', anonKey: jwt('anon'))), ConfigIssue.missing);
    expect(issueOf(evaluateConfig(url: url, anonKey: '')), ConfigIssue.missing);
  });

  test('anon JWT over https is ready', () {
    expect(evaluateConfig(url: url, anonKey: jwt('anon')), isA<ConfigReady>());
  });

  test('service_role JWT is refused', () {
    expect(issueOf(evaluateConfig(url: url, anonKey: jwt('service_role'))), ConfigIssue.notAnonKey);
  });

  test('new-style keys', () {
    expect(evaluateConfig(url: url, anonKey: 'sb_publishable_abc'), isA<ConfigReady>());
    expect(issueOf(evaluateConfig(url: url, anonKey: 'sb_secret_abc')), ConfigIssue.notAnonKey);
  });

  test('garbage key is invalid', () {
    expect(issueOf(evaluateConfig(url: url, anonKey: 'nope')), ConfigIssue.invalidKey);
    expect(issueOf(evaluateConfig(url: url, anonKey: 'a.!!!.c')), ConfigIssue.invalidKey);
  });

  test('http only allowed with flag in debug', () {
    const http = 'http://10.0.2.2:54321';
    expect(issueOf(evaluateConfig(url: http, anonKey: jwt('anon'))), ConfigIssue.insecureUrl);
    expect(
      issueOf(evaluateConfig(url: http, anonKey: jwt('anon'), allowInsecureLocal: true)),
      ConfigIssue.insecureUrl,
    );
    expect(
      evaluateConfig(url: http, anonKey: jwt('anon'), allowInsecureLocal: true, isDebug: true),
      isA<ConfigReady>(),
    );
  });

  test('invalid url', () {
    expect(issueOf(evaluateConfig(url: 'not a url', anonKey: jwt('anon'))), ConfigIssue.invalidUrl);
  });
}

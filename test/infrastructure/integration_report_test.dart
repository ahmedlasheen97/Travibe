import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../test_driver/test_report.dart';

void main() {
  test('reports each success and the complete summary', () {
    final lines = <String>[];
    reportTestResults({
      'testResults': {'startup': 'success', 'login': 'success'},
    }, lines.add);
    expect(lines, [
      '✅ startup',
      '✅ login',
      'Web e2e summary: 2 passed, 0 failed, 2 total',
    ]);
  });

  test('reported failures cannot exit successfully', () {
    final lines = <String>[];
    expect(
      () => reportTestResults({
        'testResults': {'startup': 'success', 'login': 'failure details'},
      }, lines.add),
      throwsStateError,
    );
    expect(lines, contains('❌ login'));
    expect(lines.last, 'Web e2e summary: 1 passed, 1 failed, 2 total');
  });

  for (final data in <Map<String, dynamic>?>[
    null,
    {},
    {'testResults': <String, dynamic>{}},
    {'testResults': []},
    {
      'testResults': {7: 'success'},
    },
  ]) {
    test('missing or malformed results fail: $data', () {
      expect(() => reportTestResults(data, (_) {}), throwsStateError);
    });
  }

  for (final result in ['success', 'failure', 'empty']) {
    test('host process exit code reflects $result', () async {
      final process = await Process.run('dart', [
        'run',
        'test/infrastructure/fixtures/report_probe.dart',
        jsonEncode({
          'testResults': result == 'empty' ? {} : {'probe': result},
        }),
      ]);
      expect(process.exitCode, result == 'success' ? 0 : isNot(0));
      expect(process.stdout, contains('Web e2e summary:'));
      if (result != 'success') {
        expect(process.stderr, contains('Bad state:'));
      }
    });
  }
}

/// Validates the browser-to-host reporting contract without Flutter bindings.
void reportTestResults(
  Map<String, dynamic>? data,
  void Function(String) writeLine,
) {
  final raw = data?['testResults'];
  if (raw is! Map || raw.isEmpty || raw.keys.any((key) => key is! String)) {
    writeLine('Web e2e summary: 0 passed, 0 failed, 0 total');
    throw StateError(
      'No valid tests reported by the app - infrastructure failure.',
    );
  }

  var passed = 0;
  var failed = 0;
  for (final entry in raw.entries) {
    final ok = entry.value == 'success';
    ok ? passed++ : failed++;
    writeLine('${ok ? '✅' : '❌'} ${entry.key}');
  }
  writeLine(
    'Web e2e summary: $passed passed, $failed failed, ${raw.length} total',
  );
  if (failed != 0) throw StateError('$failed integration test(s) failed.');
}

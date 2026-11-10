import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

import 'test_report.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (Map<String, dynamic>? data) async {
    // Preserve the raw artifact even when validation fails. An exception exits
    // the host process unsuccessfully, including contradictory success packets.
    await writeResponseData(data);
    reportTestResults(data, (line) => stdout.writeln(line));
  },
);

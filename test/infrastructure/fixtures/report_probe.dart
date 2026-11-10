import 'dart:convert';
import 'dart:io';

import '../../../test_driver/test_report.dart';

// Execute the real host report validator in a separate VM to verify exit codes.
void main(List<String> arguments) => reportTestResults(
  (jsonDecode(arguments.single) as Map).cast<String, dynamic>(),
  (line) => stdout.writeln(line),
);

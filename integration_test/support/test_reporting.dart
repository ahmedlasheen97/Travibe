import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Call once in each entry point, after initializing the integration binding.
/// Registered last, this teardown runs before the binding finalizes its report.
void registerTestReporting(IntegrationTestWidgetsFlutterBinding binding) {
  tearDownAll(() {
    binding.reportData = {
      ...?binding.reportData,
      'testResults': binding.results.map(
        (name, result) => MapEntry(name, result.toString()),
      ),
    };
  });
}

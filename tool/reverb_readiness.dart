import 'dart:convert';
import 'dart:io';
import 'package:travibe/features/chats/data/reverb_readiness.dart';

Future<void> main() async {
  final deployment = ReverbDeployment(
    base: Uri.parse('wss://travibeapp.com/reverb'),
    publicKey: 'e18855d51128bfdb7f62e5c6df983dfe',
  );
  final result = await probeReverb(deployment);
  // This result contains only stage outcomes; never credentials or event data.
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
}

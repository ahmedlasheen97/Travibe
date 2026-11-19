import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/network/reconnect_monitor.dart';
import 'package:travibe/features/chats/data/chat_reachability.dart';

// testWidgets runs on a fake clock, so `tester.pump(duration)` drives timers.
void main() {
  late bool? up;
  late ChatReachability reachability;
  late ReconnectMonitor monitor;
  late int reconnects;

  setUp(() {
    up = false;
    reconnects = 0;
    reachability = ChatReachability();
    monitor = ReconnectMonitor(
      status: () async => up,
      reachability: reachability,
    );
  });
  tearDown(() => monitor.dispose());

  testWidgets('fires when the interface goes offline → online, then stops', (
    tester,
  ) async {
    // Checks run at 0s and 5s: still offline, nothing fires.
    monitor.start(() => reconnects++);
    await tester.pump(const Duration(seconds: 6));
    expect(reconnects, 0);
    up = true;
    await tester.pump(const Duration(seconds: 5));
    expect(reconnects, 1);
    monitor.stop();
    await tester.pump(const Duration(minutes: 1));
    expect(reconnects, 1);
  });

  testWidgets('unknown status is not a reconnect; every third check probes', (
    tester,
  ) async {
    up = null;
    monitor.start(() => reconnects++);
    await tester.pump(const Duration(seconds: 6));
    expect(reconnects, 0);
    await tester.pump(const Duration(seconds: 5));
    expect(reconnects, 1);
    monitor.stop();
  });

  testWidgets('an API response (reachability) fires immediately', (
    tester,
  ) async {
    monitor.start(() => reconnects++);
    await tester.pump();
    reachability.markReachable();
    expect(reconnects, 1);
    monitor.stop();
    reachability.markReachable();
    expect(reconnects, 1);
  });

  testWidgets('a hung status call times out and stop leaves no timers', (
    tester,
  ) async {
    final hung = ReconnectMonitor(
      status: () => Future<bool?>.delayed(const Duration(hours: 1)),
      reachability: reachability,
    );
    hung.start(() => reconnects++);
    await tester.pump(const Duration(seconds: 4));
    hung.stop();
    expect(hung.isRunning, isFalse);
    // Let the hung status future resolve; the binding would fail the test
    // if the monitor's own periodic/timeout timers were still pending.
    await tester.pump(const Duration(hours: 1));
  });
}

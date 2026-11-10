import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/notifications/firebase_bootstrap.dart';

void main() {
  test(
    'configured iOS initializes Core exactly once across concurrent callers',
    () async {
      final gate = Completer<void>();
      var calls = 0;
      final bootstrap = FirebaseBootstrap(
        platform: TargetPlatform.iOS,
        isWeb: false,
        initializeCore: () {
          calls++;
          return gate.future;
        },
      );
      final first = bootstrap.initialize();
      final second = bootstrap.initialize();
      expect(identical(first, second), isTrue);
      expect(calls, 1);
      gate.complete();
      expect(await first, isTrue);
      expect(await bootstrap.initialize(), isTrue);
      expect(calls, 1);
    },
  );

  test('native failure is reported once without failing app startup', () async {
    var calls = 0;
    final errors = <Object>[];
    final failure = FirebaseException(plugin: 'core', code: 'not-configured');
    final bootstrap = FirebaseBootstrap(
      platform: TargetPlatform.iOS,
      isWeb: false,
      initializeCore: () async {
        calls++;
        throw failure;
      },
      onError: errors.add,
    );
    expect(await bootstrap.initialize(), isFalse);
    expect(await bootstrap.initialize(), isFalse);
    expect(errors, [failure]);
    expect(calls, 1);
  });

  for (final platform in TargetPlatform.values) {
    test('web does not use native plist configuration ($platform)', () async {
      var calls = 0;
      final bootstrap = FirebaseBootstrap(
        platform: platform,
        isWeb: true,
        initializeCore: () async => calls++,
      );
      expect(await bootstrap.initialize(), isFalse);
      expect(calls, 0);
    });
    if (platform != TargetPlatform.iOS) {
      test('unconfigured native $platform is left operational', () async {
        var calls = 0;
        final bootstrap = FirebaseBootstrap(
          platform: platform,
          isWeb: false,
          initializeCore: () async => calls++,
        );
        expect(await bootstrap.initialize(), isFalse);
        expect(calls, 0);
      });
    }
  }
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/shares/data/post_share_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Reserved test domain; this is not an assumed Travibe URL contract.
  final fixture = Uri.parse('https://example.invalid/test-post');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(PostShareActions.channel, null);
  });

  test('copies the supplied canonical URI exactly', () async {
    MethodCall? call;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (value) async {
      call = value;
      return null;
    });
    await PostShareActions(verifiedPostUri: fixture).copyLink();
    expect(call!.method, 'Clipboard.setData');
    expect(call!.arguments, {'text': fixture.toString()});
  });

  test(
    'native bridge receives URL and popover anchor, propagates errors',
    () async {
      MethodCall? call;
      messenger.setMockMethodCallHandler(PostShareActions.channel, (
        value,
      ) async {
        call = value;
        return null;
      });
      final actions = PostShareActions(
        verifiedPostUri: fixture,
        text: 'Fallback text',
      );
      await actions.moreOptions(const Rect.fromLTWH(10, 20, 30, 40));
      expect(call!.method, 'share');
      expect(call!.arguments, {
        'url': fixture.toString(),
        'x': 10.0,
        'y': 20.0,
        'width': 30.0,
        'height': 40.0,
      });
      messenger.setMockMethodCallHandler(PostShareActions.channel, (_) async {
        throw PlatformException(code: 'unavailable');
      });
      await expectLater(
        actions.moreOptions(Rect.zero),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test(
    'native text sharing works without a URL and cannot enable Copy Link',
    () async {
      MethodCall? call;
      messenger.setMockMethodCallHandler(PostShareActions.channel, (
        value,
      ) async {
        call = value;
        return null;
      });
      final actions = PostShareActions(text: '  A trip to Cairo  ');
      expect(actions.available, isFalse);
      expect(actions.canShare, isTrue);
      expect(actions.copyLink, throwsStateError);
      await actions.moreOptions(const Rect.fromLTWH(1, 2, 3, 4));
      expect(call!.arguments, {
        'text': 'A trip to Cairo',
        'x': 1.0,
        'y': 2.0,
        'width': 3.0,
        'height': 4.0,
      });
      expect((call!.arguments as Map).containsKey('url'), isFalse);
    },
  );

  test(
    'unregistered native bridge propagates MissingPluginException',
    () async {
      messenger.setMockMethodCallHandler(PostShareActions.channel, (_) async {
        throw MissingPluginException('No native sharing handler');
      });
      await expectLater(
        PostShareActions(
          text: 'Actual post',
        ).moreOptions(const Rect.fromLTWH(0, 0, 32, 32)),
        throwsA(isA<MissingPluginException>()),
      );
    },
  );

  test('blank text cannot open the native sheet', () {
    final actions = PostShareActions(text: '  ');
    expect(actions.canShare, isFalse);
    expect(() => actions.moreOptions(Rect.zero), throwsStateError);
  });

  test(
    'missing or unsafe URLs cannot reach clipboard or native bridge',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (_) async {
        calls++;
        return null;
      });
      messenger.setMockMethodCallHandler(PostShareActions.channel, (_) async {
        calls++;
        return null;
      });
      for (final uri in [
        null,
        Uri.parse('https:relative'),
        Uri.parse('http://example.invalid/post'),
        Uri.parse('https://user:secret@example.invalid/post'),
      ]) {
        final actions = PostShareActions(verifiedPostUri: uri);
        expect(actions.available, isFalse);
        expect(actions.copyLink, throwsStateError);
        expect(() => actions.moreOptions(Rect.zero), throwsStateError);
      }
      expect(calls, 0);
    },
  );
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/deeplinks/deep_links.dart';

void main() {
  final preferences = PreferencesManager();

  group('parseDeepLink', () {
    test('accepts travibe://posts/{id}', () {
      expect(parseDeepLink(Uri.parse('travibe://posts/4')), const PostLink(4));
      expect(parseDeepLink(Uri.parse('travibe://posts/4/')), const PostLink(4));
    });

    test('accepts travibe://users/{id} with "users" as the URI host', () {
      final uri = Uri.parse('travibe://users/42');
      expect(uri.host, 'users');
      expect(uri.pathSegments, ['42']);
      expect(parseDeepLink(uri), const UserLink(42));
      expect(
        parseDeepLink(Uri.parse('travibe://users/42/')),
        const UserLink(42),
      );
      expect(parseDeepLink(Uri.parse('TRAVIBE://USERS/7')), const UserLink(7));
    });

    test('post and user links with the same id are distinct', () {
      expect(const PostLink(1) == const UserLink(1), isFalse);
    });

    test('rejects everything else', () {
      for (final link in [
        'travibe://posts',
        'travibe://posts/0',
        'travibe://posts/-1',
        'travibe://posts/abc',
        'travibe://posts/04',
        'travibe://posts/4/comments',
        'travibe://users',
        'travibe://users/',
        'travibe://users/0',
        'travibe://users/-1',
        'travibe://users/04',
        'travibe://users/abc',
        'travibe://users/42/posts',
        // "users" in the path, not the host.
        'travibe:///users/42',
        'travibe://app/users/42',
        'travibe:users/42',
        'travibe://user/42',
        'https://travibeapp.com/u/42',
        'https://users/42',
        'https://travibeapp.com/p/4',
        'other://posts/4',
        'other://users/4',
      ]) {
        expect(parseDeepLink(Uri.parse(link)), isNull, reason: link);
      }
    });
  });

  group('DeepLinkCoordinator', () {
    late StreamController<Uri> links;
    late List<DeepLink> opened;
    late List<DeepLinkTarget> targets;
    late DeepLinkCoordinator coordinator;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await preferences.init();
      await preferences.saveToken('fixture-session');
      links = StreamController<Uri>();
      opened = [];
      targets = [];
      coordinator = DeepLinkCoordinator(
        links: links.stream,
        open: (target, link) async {
          targets.add(target);
          opened.add(link);
        },
      );
    });
    tearDown(() async {
      coordinator.dispose();
      await links.close();
      await preferences.clearSession();
    });

    Future<BuildContext> root(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      return tester.element(find.byType(SizedBox));
    }

    testWidgets('cold start: the link waits for Root, then opens once', (
      tester,
    ) async {
      links.add(Uri.parse('travibe://posts/4'));
      await tester.pump();
      expect(coordinator.pending, const PostLink(4));
      expect(opened, isEmpty);
      final owner = Object();
      coordinator.attach(owner, await root(tester));
      expect(opened, [const PostLink(4)]);
      expect(coordinator.pending, isNull);
      coordinator.detach(owner);
      coordinator.attach(owner, await root(tester));
      expect(opened, [const PostLink(4)]);
    });

    testWidgets('cold start: a profile link opens with showMyProfile', (
      tester,
    ) async {
      links.add(Uri.parse('travibe://users/42'));
      await tester.pump();
      expect(coordinator.pending, const UserLink(42));
      var mine = 0;
      coordinator.attach(
        Object(),
        await root(tester),
        showMyProfile: () => mine++,
      );
      expect(opened, [const UserLink(42)]);
      targets.single.showMyProfile!();
      expect(mine, 1);
    });

    testWidgets('background: a link while Root is attached opens now', (
      tester,
    ) async {
      coordinator.attach(Object(), await root(tester));
      links
        ..add(Uri.parse('travibe://posts/9'))
        ..add(Uri.parse('travibe://users/5'));
      await tester.pump();
      expect(opened, [const PostLink(9), const UserLink(5)]);
    });

    testWidgets('logged out: pending until Root attaches with a session', (
      tester,
    ) async {
      await preferences.clearSession();
      final owner = Object();
      coordinator.attach(owner, await root(tester));
      links.add(Uri.parse('travibe://users/12'));
      await tester.pump();
      expect(opened, isEmpty);
      expect(coordinator.pending, const UserLink(12));
      // Logout disposes Root; login brings a new Root back.
      coordinator.detach(owner);
      await preferences.saveToken('next-session');
      expect(opened, isEmpty);
      coordinator.attach(Object(), await root(tester));
      expect(opened, [const UserLink(12)]);
    });

    testWidgets('the latest link wins and invalid links are ignored', (
      tester,
    ) async {
      links
        ..add(Uri.parse('travibe://posts/1'))
        ..add(Uri.parse('travibe://users/3'))
        ..add(Uri.parse('travibe:///users/4'))
        ..add(Uri.parse('travibe://friends/5'));
      await tester.pump();
      coordinator.attach(Object(), await root(tester));
      expect(opened, [const UserLink(3)]);
    });
  });
}

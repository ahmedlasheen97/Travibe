import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/deeplinks/post_deep_links.dart';

void main() {
  final preferences = PreferencesManager();

  group('parsePostDeepLink', () {
    test('accepts travibe://posts/{id}', () {
      expect(parsePostDeepLink(Uri.parse('travibe://posts/4')), 4);
      expect(parsePostDeepLink(Uri.parse('travibe://posts/4/')), 4);
    });

    test('rejects everything else', () {
      for (final link in [
        'travibe://posts',
        'travibe://posts/0',
        'travibe://posts/-1',
        'travibe://posts/abc',
        'travibe://posts/04',
        'travibe://posts/4/comments',
        'travibe://users/4',
        'https://travibeapp.com/p/4',
        'other://posts/4',
      ]) {
        expect(parsePostDeepLink(Uri.parse(link)), isNull, reason: link);
      }
    });
  });

  group('PostDeepLinkCoordinator', () {
    late StreamController<Uri> links;
    late List<int> opened;
    late PostDeepLinkCoordinator coordinator;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await preferences.init();
      await preferences.saveToken('fixture-session');
      links = StreamController<Uri>();
      opened = [];
      coordinator = PostDeepLinkCoordinator(
        links: links.stream,
        open: (_, id) async => opened.add(id),
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
      expect(coordinator.pending, 4);
      expect(opened, isEmpty);
      final owner = Object();
      coordinator.attach(owner, await root(tester));
      expect(opened, [4]);
      expect(coordinator.pending, isNull);
      coordinator.detach(owner);
      coordinator.attach(owner, await root(tester));
      expect(opened, [4]);
    });

    testWidgets('background: a link while Root is attached opens now', (
      tester,
    ) async {
      coordinator.attach(Object(), await root(tester));
      links.add(Uri.parse('travibe://posts/9'));
      await tester.pump();
      expect(opened, [9]);
    });

    testWidgets('logged out: pending until Root attaches with a session', (
      tester,
    ) async {
      await preferences.clearSession();
      final owner = Object();
      coordinator.attach(owner, await root(tester));
      links.add(Uri.parse('travibe://posts/12'));
      await tester.pump();
      expect(opened, isEmpty);
      expect(coordinator.pending, 12);
      // Logout disposes Root; login brings a new Root back.
      coordinator.detach(owner);
      await preferences.saveToken('next-session');
      expect(opened, isEmpty);
      coordinator.attach(Object(), await root(tester));
      expect(opened, [12]);
    });

    testWidgets('the latest link wins and invalid links are ignored', (
      tester,
    ) async {
      links
        ..add(Uri.parse('travibe://posts/1'))
        ..add(Uri.parse('travibe://posts/2'))
        ..add(Uri.parse('travibe://users/3'));
      await tester.pump();
      coordinator.attach(Object(), await root(tester));
      expect(opened, [2]);
    });
  });
}

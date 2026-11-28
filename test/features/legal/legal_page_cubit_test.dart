import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/legal/cubit/legal_page_cubit.dart';
import 'package:travibe/features/legal/data/legal_page.dart';

import 'legal_fakes.dart';

void main() {
  const slug = LegalPageSlug.terms;

  test('no cache: loading, then the fetched page', () async {
    final cubit = LegalPageCubit(slug, repo: FakeLegalPagesRepo());
    expect(cubit.state, isA<LegalPageLoading>());
    await cubit.load();
    final state = cubit.state as LegalPageLoaded;
    expect(state.page.title, 'Terms of Service');
    expect(state.refreshing, false);
    expect(state.failures, 0);
    await cubit.close();
  });

  test('cache first, then the fresh copy replaces it', () async {
    final repo = FakeLegalPagesRepo(
      pages: {slug: samplePage(slug, title: 'Fresh')},
      cache: {slug: samplePage(slug, title: 'Cached')},
    )..pending = Completer<void>();
    final cubit = LegalPageCubit(slug, repo: repo);
    final loading = cubit.load();
    await pumpEventQueue();
    final cached = cubit.state as LegalPageLoaded;
    expect(cached.page.title, 'Cached');
    expect(cached.refreshing, true);
    repo.pending!.complete();
    await loading;
    expect((cubit.state as LegalPageLoaded).page.title, 'Fresh');
    await cubit.close();
  });

  test(
    'offline with a cache keeps the cached page and counts the failure',
    () async {
      final repo = FakeLegalPagesRepo(
        pages: {slug: null},
        cache: {slug: samplePage(slug, title: 'Cached')},
      );
      final cubit = LegalPageCubit(slug, repo: repo);
      await cubit.load();
      final state = cubit.state as LegalPageLoaded;
      expect(state.page.title, 'Cached');
      expect(state.refreshing, false);
      expect(state.failures, 1);
      await cubit.close();
    },
  );

  test('offline without a cache is unavailable; refresh recovers', () async {
    final repo = FakeLegalPagesRepo(pages: {slug: null});
    final cubit = LegalPageCubit(slug, repo: repo);
    await cubit.load();
    expect(cubit.state, isA<LegalPageUnavailable>());
    expect(cubit.state.failures, 1);

    await cubit.refresh();
    expect(cubit.state.failures, 2);

    repo.pages[slug] = samplePage(slug);
    final states = <LegalPageState>[];
    final sub = cubit.stream.listen(states.add);
    await cubit.refresh();
    expect(states.first, isA<LegalPageUnavailable>());
    expect((states.first as LegalPageUnavailable).retrying, true);
    expect(cubit.state, isA<LegalPageLoaded>());
    await sub.cancel();
    await cubit.close();
  });

  test(
    'a stale fetch is dropped when a newer refresh finishes first',
    () async {
      final repo = FakeLegalPagesRepo(
        pages: {slug: samplePage(slug, title: 'Old')},
      )..pending = Completer<void>();
      final cubit = LegalPageCubit(slug, repo: repo);
      final first = cubit.load();
      await pumpEventQueue();
      final gate = repo.pending!;
      repo
        ..pending = null
        ..pages[slug] = samplePage(slug, title: 'New');
      await cubit.refresh();
      expect((cubit.state as LegalPageLoaded).page.title, 'New');
      repo.pages[slug] = null; // the old request would now fail
      gate.complete();
      await first;
      final state = cubit.state as LegalPageLoaded;
      expect(state.page.title, 'New');
      expect(state.failures, 0);
      await cubit.close();
    },
  );

  test('a fetch finishing after close does nothing', () async {
    final repo = FakeLegalPagesRepo()..pending = Completer<void>();
    final cubit = LegalPageCubit(slug, repo: repo);
    final loading = cubit.load();
    await pumpEventQueue();
    await cubit.close();
    repo.pending!.complete();
    await loading;
  });
}

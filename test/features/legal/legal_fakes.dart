import 'dart:async';

import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/links/link_opener.dart';
import 'package:travibe/features/legal/data/legal_page.dart';
import 'package:travibe/features/legal/data/legal_pages_repo.dart';

LegalPage samplePage(
  LegalPageSlug slug, {
  String? title,
  List<LegalBlock>? blocks,
}) => LegalPage(
  slug: slug,
  title: title ?? slug.title,
  updatedAt: DateTime(2026, 11, 25),
  blocks:
      blocks ??
      [
        const LegalBlock([
          LegalSpan('1. Who can use Travibe', bold: true),
        ], isHeading: true),
        const LegalBlock([LegalSpan('You must be at least 13 years old.')]),
      ],
);

/// In-memory repo: [pages] answers fetches (null = offline), [cache] answers
/// [cached]. [pending] holds fetches open until completed by the test.
class FakeLegalPagesRepo extends LegalPagesRepo {
  FakeLegalPagesRepo({
    Map<LegalPageSlug, LegalPage?>? pages,
    this.cache = const {},
  }) : pages =
           pages ??
           {for (final slug in LegalPageSlug.values) slug: samplePage(slug)};

  final Map<LegalPageSlug, LegalPage?> pages;
  final Map<LegalPageSlug, LegalPage> cache;
  Completer<void>? pending;
  final fetches = <LegalPageSlug>[];

  @override
  Future<LegalPage?> cached(LegalPageSlug slug) async => cache[slug];

  @override
  Future<LegalPage> fetch(LegalPageSlug slug) async {
    fetches.add(slug);
    if (pending case final gate?) await gate.future;
    final page = pages[slug];
    if (page == null) {
      throw ApiError(message: 'offline', isConnectionError: true);
    }
    return page;
  }
}

class FakeLinkOpener extends LinkOpener {
  FakeLinkOpener({this.succeeds = true});
  bool succeeds;
  final opened = <Uri>[];

  @override
  Future<bool> openInApp(Uri uri) async {
    opened.add(uri);
    return succeeds;
  }
}

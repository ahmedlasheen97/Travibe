import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/features/legal/data/legal_html_parser.dart';
import 'package:travibe/features/legal/data/legal_page.dart';

/// Same shape as https://travibeapp.com/terms (25 November 2026).
const websiteTerms = '''
<!DOCTYPE html>
<html lang="en" dir="ltr">
<head><title>Terms of Service — Travibe</title>
<script>var x = "<p>not content</p>";</script></head>
<body class="bg-ink">
<header><a href="https://travibeapp.com" class="nav-link">Home</a></header>
<main id="main"><article class="mx-auto max-w-3xl">
  <h1 class="text-3xl font-bold">Terms of Service</h1>
  <div class="mt-4 flex text-muted">
    <p>Last updated: <time datetime="2026-11-25">25 November 2026</time></p>
  </div>
  <div class="legal-prose mt-10">
    <p><strong>1. Who can use Travibe</strong></p><p>You must be at least 13 years old &amp; keep your password safe.</p>
    <p><strong>7. Privacy</strong></p><p>Our Privacy Policy (<a href="https://travibeapp.com/privacy">https://travibeapp.com/privacy</a>) explains it.</p>
    <p>Delete at <a href="/delete-account">our site</a>. The Service is &#34;as is&#34;&#x2014;really.</p>
    <div><p>Nested <em>paragraph</em></p></div>
    <p><strong>12. Contact us</strong></p>
    <p>Email: <a href="/cdn-cgi/l/email-protection#11626461617e6365373227252a656370677873747061613f727e7c">support&#64;travibeapp.com</a></p>
    <p>Cairo,<br>Egypt</p>
  </div>
</article></main>
<footer><p>Footer text</p></footer>
</body></html>
''';

void main() {
  LegalPage parse([String html = websiteTerms]) =>
      LegalHtmlParser.parse(html, LegalPageSlug.terms);

  test('reads title, Last updated and language', () {
    final page = parse();
    expect(page.title, 'Terms of Service');
    expect(page.updatedAt, DateTime(2026, 11, 25));
    expect(page.languageCode, 'en');
    expect(page.slug, LegalPageSlug.terms);
  });

  test(
    'reads only the prose, in order, with bold-only paragraphs as headings',
    () {
      final blocks = parse().blocks;
      expect(blocks.map((b) => b.text), [
        '1. Who can use Travibe',
        'You must be at least 13 years old & keep your password safe.',
        '7. Privacy',
        'Our Privacy Policy (https://travibeapp.com/privacy) explains it.',
        'Delete at our site. The Service is "as is"—really.',
        'Nested paragraph',
        '12. Contact us',
        'Email: support@travibeapp.com',
        'Cairo,\nEgypt',
      ]);
      expect(blocks.where((b) => b.isHeading).map((b) => b.text), [
        '1. Who can use Travibe',
        '7. Privacy',
        '12. Contact us',
      ]);
    },
  );

  test('keeps absolute and relative links, resolved to https', () {
    final blocks = parse().blocks;
    expect(
      blocks[3].spans[1],
      LegalSpan(
        'https://travibeapp.com/privacy',
        link: Uri.parse('https://travibeapp.com/privacy'),
      ),
    );
    expect(
      blocks[4].spans[1].link,
      Uri.parse('https://travibeapp.com/delete-account'),
    );
  });

  test('turns Cloudflare-protected and mailto links into email spans', () {
    final email = parse().blocks[7].spans.last;
    expect(email.email, 'support@travibeapp.com');
    expect(email.link, isNull);
    final mailto = LegalHtmlParser.parseProse(
      '<p>Write to <a href="mailto:privacy@travibeapp.com?subject=Hi">us</a></p>',
    );
    expect(
      mailto.single.spans.last,
      const LegalSpan('us', email: 'privacy@travibeapp.com'),
    );
    final cfSpan = LegalHtmlParser.parseProse(
      '<p>Email: <span class="__cf_email__" data-cfemail="11626461617e6365373227252a656370677873747061613f727e7c">[email&#160;protected]</span></p>',
    );
    expect(cfSpan.single.spans.last.email, 'support@travibeapp.com');
    expect(cfSpan.single.text, 'Email: support@travibeapp.com');
  });

  test('decodes Cloudflare emails and rejects garbage', () {
    expect(
      LegalHtmlParser.decodeCloudflareEmail(
        '11626461617e6365373227252a656370677873747061613f727e7c',
      ),
      'support@travibeapp.com',
    );
    expect(LegalHtmlParser.decodeCloudflareEmail('zz'), isNull);
    expect(LegalHtmlParser.decodeCloudflareEmail('1162'), isNull);
  });

  test('lists and explicit headings', () {
    final blocks = LegalHtmlParser.parseProse(
      '<h2>Rights</h2><ul><li>Edit <b>profile</b></li><li>Block users</li></ul>'
      '<ol><li>First</li><li>Second</li></ol>',
    );
    expect(blocks.map((b) => b.text), [
      'Rights',
      '• Edit profile',
      '• Block users',
      '1. First',
      '2. Second',
    ]);
    expect(blocks.first.isHeading, true);
    expect(blocks.skip(1).every((b) => b.isListItem && !b.isHeading), true);
    expect(blocks[1].spans.any((s) => s.bold && s.text == 'profile'), true);
  });

  test('decodes named, decimal and hex entities', () {
    expect(
      LegalHtmlParser.decodeEntities(
        '&lt;a&gt; &quot;x&quot; &#64; &#x40; &rsquo; &bogus;',
      ),
      '<a> "x" @ @ ’ &bogus;',
    );
  });

  test('missing or empty prose is a FormatException', () {
    expect(() => parse('<html><h1>Terms</h1></html>'), throwsFormatException);
    expect(
      () => parse('<h1>Terms</h1><div class="legal-prose">  <p> </p></div>'),
      throwsFormatException,
    );
  });

  test('falls back to the slug title and tolerates a missing date', () {
    final page = parse('<div class="legal-prose"><p>Body</p></div>');
    expect(page.title, 'Terms of Service');
    expect(page.updatedAt, isNull);
    expect(page.languageCode, 'en');
  });

  test('cache JSON round-trips', () {
    final page = parse();
    final copy = LegalPage.fromJson(page.toJson());
    expect(copy.title, page.title);
    expect(copy.updatedAt, page.updatedAt);
    expect(
      copy.blocks.expand((b) => b.spans).toList(),
      page.blocks.expand((b) => b.spans).toList(),
    );
    expect(
      copy.blocks.map((b) => b.isHeading),
      page.blocks.map((b) => b.isHeading),
    );
  });

  test('LegalPageSlug.fromUri recognises our own pages only', () {
    expect(
      LegalPageSlug.fromUri(Uri.parse('https://travibeapp.com/privacy')),
      LegalPageSlug.privacy,
    );
    expect(
      LegalPageSlug.fromUri(Uri.parse('https://www.travibeapp.com/terms/')),
      LegalPageSlug.terms,
    );
    expect(
      LegalPageSlug.fromUri(Uri.parse('https://travibeapp.com/delete-account')),
      isNull,
    );
    expect(
      LegalPageSlug.fromUri(Uri.parse('https://example.com/privacy')),
      isNull,
    );
  });
}

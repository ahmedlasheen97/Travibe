import 'package:travibe/features/legal/data/legal_page.dart';

/// Reads a website legal page (`/terms`, `/privacy`) into a [LegalPage].
///
/// Contract with the website markup: `<html lang>`, the page `<h1>`, an
/// optional `<time datetime="YYYY-MM-DD">`, and a `<div class="legal-prose">`
/// with the body. The body uses simple prose tags (p, strong/b, em, a, br,
/// h2–h6, ul/ol/li); a paragraph that is entirely bold is a section heading.
/// Throws [FormatException] when the prose is missing or empty.
abstract final class LegalHtmlParser {
  static final _tag = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*?)(/?)>');
  static final _comment = RegExp(r'<!--[\s\S]*?-->');
  static final _whitespace = RegExp(r'\s+');
  static final _blockTags = {
    'p', 'div', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', //
    'section', 'article', 'ul', 'ol', 'table', 'tr',
  };

  static LegalPage parse(String html, LegalPageSlug slug) {
    html = html.replaceAll(_comment, '');
    final lang = RegExp(
      r'''<html[^>]*\slang=["']?([a-zA-Z-]+)''',
    ).firstMatch(html)?.group(1);
    final h1 = RegExp(r'<h1[^>]*>([\s\S]*?)</h1>').firstMatch(html)?.group(1);
    final time = RegExp(
      r'''<time[^>]*\sdatetime=["']([^"']+)["']''',
    ).firstMatch(html)?.group(1);
    final blocks = parseProse(_prose(html));
    if (blocks.isEmpty) throw const FormatException('Empty legal page');
    final title = h1 == null ? '' : _collapse(decodeEntities(_stripTags(h1)));
    return LegalPage(
      slug: slug,
      title: title.isEmpty ? slug.title : title,
      updatedAt: time == null ? null : DateTime.tryParse(time.trim()),
      languageCode: (lang ?? 'en').split('-').first.toLowerCase(),
      blocks: blocks,
    );
  }

  /// The inner HTML of the `legal-prose` element.
  static String _prose(String html) {
    final open = RegExp(
      r'''<(div|section|article)\b[^>]*class=["'][^"']*\blegal-prose\b[^"']*["'][^>]*>''',
    ).firstMatch(html);
    if (open == null) throw const FormatException('No legal-prose element');
    final name = open.group(1)!;
    var depth = 1;
    for (final match in RegExp(
      '<(/?)$name\\b[^>]*>',
    ).allMatches(html, open.end)) {
      depth += match.group(1) == '/' ? -1 : 1;
      if (depth == 0) return html.substring(open.end, match.start);
    }
    throw const FormatException('Unclosed legal-prose element');
  }

  static List<LegalBlock> parseProse(String prose) {
    final blocks = <LegalBlock>[];
    final lists = <({bool ordered, int count})>[];
    var spans = <LegalSpan>[];
    var heading = false, listItem = false;
    var bold = 0, skip = 0;
    Uri? link;
    String? email;
    String? cfEmail;
    var inCfEmail = false;

    void flush() {
      final cleaned = _trimSpans(spans);
      if (cleaned.isNotEmpty) {
        final allBold = cleaned.every((s) => s.bold || s.text.trim().isEmpty);
        blocks.add(
          LegalBlock(
            List.unmodifiable(cleaned),
            isHeading: heading || (allBold && !listItem),
            isListItem: listItem,
          ),
        );
      }
      spans = <LegalSpan>[];
      heading = false;
      listItem = false;
    }

    void addText(String raw) {
      if (skip > 0 || inCfEmail) return;
      final text = decodeEntities(raw).replaceAll(_whitespace, ' ');
      if (text.isEmpty) return;
      final address = email;
      spans.add(
        LegalSpan(
          text,
          bold: bold > 0,
          link: address == null ? link : null,
          // An undecodable protected link falls back to its visible text.
          email: address == null
              ? null
              : (address.isEmpty ? text.trim() : address),
        ),
      );
    }

    var index = 0;
    for (final match in _tag.allMatches(prose)) {
      addText(prose.substring(index, match.start));
      index = match.end;
      final closing = match.group(1) == '/';
      final name = match.group(2)!.toLowerCase();
      final attrs = match.group(3) ?? '';
      if (name == 'script' || name == 'style') {
        skip += closing ? -1 : 1;
        if (skip < 0) skip = 0;
        continue;
      }
      if (skip > 0) continue;
      switch (name) {
        case 'br':
          if (spans.isNotEmpty) spans.add(LegalSpan('\n', bold: bold > 0));
        case 'strong' || 'b':
          bold += closing ? -1 : 1;
          if (bold < 0) bold = 0;
        case 'a':
          if (closing) {
            link = null;
            email = null;
          } else {
            final href = _attr(attrs, 'href');
            email = _emailFromHref(href);
            link = email == null ? _resolve(href) : null;
          }
        case 'span' when !closing && _attr(attrs, 'data-cfemail') != null:
          cfEmail = decodeCloudflareEmail(_attr(attrs, 'data-cfemail')!);
          inCfEmail = true;
        case 'span' when closing && inCfEmail:
          inCfEmail = false;
          if (cfEmail != null) {
            spans.add(LegalSpan(cfEmail, bold: bold > 0, email: cfEmail));
          }
          cfEmail = null;
        case 'ul' || 'ol':
          flush();
          if (closing) {
            if (lists.isNotEmpty) lists.removeLast();
          } else {
            lists.add((ordered: name == 'ol', count: 0));
          }
        case 'li' when !closing:
          flush();
          listItem = true;
          if (lists.isNotEmpty) {
            final list = lists.removeLast();
            final count = list.count + 1;
            lists.add((ordered: list.ordered, count: count));
            spans.add(LegalSpan(list.ordered ? '$count. ' : '• '));
          } else {
            spans.add(const LegalSpan('• '));
          }
        case _ when _blockTags.contains(name):
          flush();
          if (!closing && RegExp(r'^h[1-6]$').hasMatch(name)) heading = true;
      }
    }
    addText(prose.substring(index));
    flush();
    return List.unmodifiable(blocks);
  }

  /// Drops leading/trailing whitespace and merges neighbouring spans with the
  /// same style, so the rendered text matches the website's.
  static List<LegalSpan> _trimSpans(List<LegalSpan> spans) {
    final merged = <LegalSpan>[];
    for (final span in spans) {
      final last = merged.isEmpty ? null : merged.last;
      if (last != null &&
          last.bold == span.bold &&
          last.link == span.link &&
          last.email == null &&
          span.email == null) {
        merged[merged.length - 1] = LegalSpan(
          last.text + span.text,
          bold: last.bold,
          link: last.link,
        );
      } else {
        merged.add(span);
      }
    }
    while (merged.isNotEmpty && merged.first.text.trim().isEmpty) {
      merged.removeAt(0);
    }
    while (merged.isNotEmpty && merged.last.text.trim().isEmpty) {
      merged.removeLast();
    }
    if (merged.isEmpty) return merged;
    LegalSpan copy(LegalSpan s, String text) =>
        LegalSpan(text, bold: s.bold, link: s.link, email: s.email);
    merged[0] = copy(merged.first, merged.first.text.trimLeft());
    merged[merged.length - 1] = copy(merged.last, merged.last.text.trimRight());
    // Collapse a space that follows a line break.
    return [
      for (final s in merged)
        s.text.contains('\n')
            ? copy(s, s.text.replaceAll(' \n', '\n').replaceAll('\n ', '\n'))
            : s,
    ];
  }

  static String? _attr(String attrs, String name) {
    final match = RegExp(
      '(?:^|\\s)$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
      caseSensitive: false,
    ).firstMatch(attrs);
    if (match == null) return null;
    return decodeEntities(match.group(1) ?? match.group(2) ?? match.group(3)!);
  }

  static Uri? _resolve(String? href) {
    if (href == null || href.trim().isEmpty) return null;
    final uri = Uri.tryParse(href.trim());
    if (uri == null) return null;
    final resolved = Uri.https(LegalPageSlug.host, '/').resolveUri(uri);
    return resolved.scheme == 'https' || resolved.scheme == 'http'
        ? resolved
        : null;
  }

  static String? _emailFromHref(String? href) {
    if (href == null) return null;
    final value = href.trim();
    if (value.toLowerCase().startsWith('mailto:')) {
      final address = Uri.decodeComponent(
        value.substring(7).split('?').first,
      ).trim();
      return address.isEmpty ? null : address;
    }
    final hash = value.indexOf('#');
    if (value.contains('/cdn-cgi/l/email-protection') && hash != -1) {
      return decodeCloudflareEmail(value.substring(hash + 1)) ?? '';
    }
    return null;
  }

  /// Cloudflare's email obfuscation: hex bytes XOR-ed with the first byte.
  static String? decodeCloudflareEmail(String hex) {
    if (hex.length < 4 || hex.length.isOdd) return null;
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (byte == null) return null;
      bytes.add(byte);
    }
    final key = bytes.first;
    // The payload is the HTML source of the address, so it may hold entities.
    final email = decodeEntities(
      String.fromCharCodes(bytes.skip(1).map((b) => b ^ key)),
    ).trim();
    return email.contains('@') ? email : null;
  }

  static const _named = {
    'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", //
    'nbsp': '\u00A0', 'ndash': '–', 'mdash': '—', 'hellip': '…',
    'lsquo': '‘', 'rsquo': '’', 'ldquo': '“', 'rdquo': '”', 'copy': '©',
    'reg': '®', 'trade': '™', 'bull': '•', 'middot': '·', 'laquo': '«',
    'raquo': '»', 'rarr': '→',
  };

  static String decodeEntities(String text) => text.replaceAllMapped(
    RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);'),
    (m) {
      final entity = m.group(1)!;
      if (entity.startsWith('#')) {
        final hex = entity.length > 1 && (entity[1] == 'x' || entity[1] == 'X');
        final code = int.tryParse(
          entity.substring(hex ? 2 : 1),
          radix: hex ? 16 : 10,
        );
        return code == null || code > 0x10FFFF
            ? m.group(0)!
            : String.fromCharCode(code);
      }
      return _named[entity.toLowerCase()] ?? m.group(0)!;
    },
  );

  static String _stripTags(String html) => html.replaceAll(_tag, '');
  static String _collapse(String text) =>
      text.replaceAll(_whitespace, ' ').trim();
}

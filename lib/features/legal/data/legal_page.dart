import 'package:travibe/core/utils/json_parsers.dart';

/// Public legal pages edited in the admin panel (/admin/legal-pages) and
/// served by the website. No API exists yet (docs/BACKEND_REQUESTS.md).
enum LegalPageSlug {
  terms('Terms of Service'),
  privacy('Privacy Policy');

  const LegalPageSlug(this.title);

  /// Shown until the page's own title has loaded.
  final String title;

  static const host = 'travibeapp.com';

  Uri get webUri => Uri.https(host, '/$name');

  /// The slug a link points at when it is one of our own legal pages.
  static LegalPageSlug? fromUri(Uri uri) {
    if (uri.host != host && uri.host != 'www.$host') return null;
    final path = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    for (final slug in values) {
      if (path == '/${slug.name}') return slug;
    }
    return null;
  }
}

/// One run of text inside a [LegalBlock].
class LegalSpan {
  const LegalSpan(this.text, {this.bold = false, this.link, this.email});
  final String text;
  final bool bold;

  /// An http(s) link; tapped spans open it.
  final Uri? link;

  /// An email address; it stays selectable and copies on tap.
  final String? email;

  Map<String, dynamic> toJson() => {
    't': text,
    if (bold) 'b': true,
    if (link != null) 'l': link.toString(),
    if (email != null) 'e': email,
  };

  factory LegalSpan.fromJson(dynamic json) {
    if (json is! Map || json['t'] is! String) throw const FormatException();
    final email = json['e'];
    return LegalSpan(
      json['t'],
      bold: parseBool(json['b']),
      link: parseHttpsUri(json['l']),
      email: email is String && email.isNotEmpty ? email : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LegalSpan &&
      other.text == text &&
      other.bold == bold &&
      other.link == link &&
      other.email == email;

  @override
  int get hashCode => Object.hash(text, bold, link, email);

  @override
  String toString() =>
      'LegalSpan($text${bold ? ', bold' : ''}${link == null ? '' : ', $link'}'
      '${email == null ? '' : ', $email'})';
}

/// A paragraph, list item or section heading.
class LegalBlock {
  const LegalBlock(
    this.spans, {
    this.isHeading = false,
    this.isListItem = false,
  });
  final List<LegalSpan> spans;
  final bool isHeading, isListItem;

  String get text => spans.map((s) => s.text).join();

  Map<String, dynamic> toJson() => {
    's': [for (final span in spans) span.toJson()],
    if (isHeading) 'h': true,
    if (isListItem) 'li': true,
  };

  factory LegalBlock.fromJson(dynamic json) {
    if (json is! Map || json['s'] is! List) throw const FormatException();
    return LegalBlock(
      List.unmodifiable((json['s'] as List).map(LegalSpan.fromJson)),
      isHeading: parseBool(json['h']),
      isListItem: parseBool(json['li']),
    );
  }
}

class LegalPage {
  const LegalPage({
    required this.slug,
    required this.title,
    required this.blocks,
    this.updatedAt,
    this.languageCode = 'en',
  });
  final LegalPageSlug slug;
  final String title;
  final DateTime? updatedAt;

  /// The page's own language (the website is English-only today).
  final String languageCode;
  final List<LegalBlock> blocks;

  Map<String, dynamic> toJson() => {
    'slug': slug.name,
    'title': title,
    if (updatedAt != null)
      'updated_at': updatedAt!.toIso8601String().substring(0, 10),
    'lang': languageCode,
    'blocks': [for (final block in blocks) block.toJson()],
  };

  factory LegalPage.fromJson(dynamic json) {
    if (json is! Map ||
        json['title'] is! String ||
        json['blocks'] is! List ||
        (json['blocks'] as List).isEmpty) {
      throw const FormatException();
    }
    final slug = LegalPageSlug.values.where((s) => s.name == json['slug']);
    if (slug.isEmpty) throw const FormatException();
    final updated = json['updated_at'];
    final lang = json['lang'];
    return LegalPage(
      slug: slug.single,
      title: json['title'],
      updatedAt: updated is String ? DateTime.tryParse(updated) : null,
      languageCode: lang is String && lang.isNotEmpty ? lang : 'en',
      blocks: List.unmodifiable(
        (json['blocks'] as List).map(LegalBlock.fromJson),
      ),
    );
  }
}

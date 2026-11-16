/// Legal copy is deliberately independent of Flutter and the authentication layer.
enum LegalDocumentType { terms, privacy }

class LegalSection {
  const LegalSection({
    required this.id,
    required this.heading,
    required this.body,
  });
  final String id, heading, body;
}

class LegalDocument {
  const LegalDocument({
    required this.type,
    required this.languageCode,
    required this.title,
    required this.lastUpdatedText,
    required this.effectiveDateText,
    required this.versionLabel,
    required this.reviewNotice,
    required this.introduction,
    required this.relatedDocumentLabel,
    required this.sections,
  });
  static const contentVersion = 'draft-2026-11-14.1';
  static const lastUpdatedIso = '2026-11-14';
  // An authoring date is not an approved effective date.
  static const String? effectiveDateIso = null;
  static const requiresLegalReview = true;
  final LegalDocumentType type;
  final String languageCode,
      title,
      lastUpdatedText,
      effectiveDateText,
      versionLabel,
      reviewNotice,
      introduction,
      relatedDocumentLabel;
  final List<LegalSection> sections;

  /// Intended hosting locations only. These are not verified/published links.
  Uri get preferredPublicUrl => Uri.https(
    'travibeapp.com',
    type == LegalDocumentType.terms ? '/terms' : '/privacy',
  );
}

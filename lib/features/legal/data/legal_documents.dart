import 'legal_content_ar.dart';
import 'legal_content_en.dart';
import 'legal_document.dart';
export 'legal_document.dart';

/// Bundled drafts: no unconfirmed backend endpoint or public URL is requested.
abstract final class LegalDocuments {
  static LegalDocument get(LegalDocumentType type, String languageCode) =>
      switch ((type, languageCode)) {
        (LegalDocumentType.terms, 'ar') => termsAr,
        (LegalDocumentType.privacy, 'ar') => privacyAr,
        (LegalDocumentType.terms, _) => termsEn,
        (LegalDocumentType.privacy, _) => privacyEn,
      };
}

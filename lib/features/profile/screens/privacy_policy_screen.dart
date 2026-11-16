import 'package:flutter/material.dart';
import 'package:travibe/features/legal/data/legal_documents.dart';
import 'package:travibe/features/profile/screens/terms_of_service_screen.dart';
import 'package:travibe/features/profile/widgets/legal_text_screen.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});
  @override
  Widget build(BuildContext context) => LegalTextScreen(
    document: LegalDocuments.get(
      LegalDocumentType.privacy,
      Localizations.localeOf(context).languageCode,
    ),
    onRelatedDocument: () async => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TermsOfServiceScreen()),
    ),
  );
}

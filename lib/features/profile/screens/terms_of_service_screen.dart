import 'package:flutter/material.dart';
import 'package:travibe/features/legal/data/legal_documents.dart';
import 'package:travibe/features/profile/screens/privacy_policy_screen.dart';
import 'package:travibe/features/profile/widgets/legal_text_screen.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});
  @override
  Widget build(BuildContext context) => LegalTextScreen(
    document: LegalDocuments.get(
      LegalDocumentType.terms,
      Localizations.localeOf(context).languageCode,
    ),
    onRelatedDocument: () async => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyScreen()),
    ),
  );
}

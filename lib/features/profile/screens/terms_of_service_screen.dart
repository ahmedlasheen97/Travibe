import 'package:flutter/material.dart';
import 'package:travibe/features/profile/widgets/legal_text_screen.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalTextScreen(
      title: 'Terms of Service',
      sections: [
        LegalSection(
          body:
              'Placeholder intro paragraph — replace with your real Terms of Service text once available.',
        ),
        LegalSection(
          heading: '1. Acceptance of Terms',
          body: 'Placeholder body text for this section.',
        ),
        LegalSection(
          heading: '2. User Responsibilities',
          body: 'Placeholder body text for this section.',
        ),
        // Add remaining sections here
      ],
    );
  }
}

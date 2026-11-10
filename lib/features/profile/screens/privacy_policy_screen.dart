import 'package:flutter/material.dart';
import 'package:travibe/features/profile/widgets/legal_text_screen.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalTextScreen(
      title: 'Privacy Policy',
      sections: [
        LegalSection(
          body:
              'Placeholder intro paragraph — replace with your real Privacy Policy text once available.',
        ),
        LegalSection(
          heading: '1. Information We Collect',
          body: 'Placeholder body text for this section.',
        ),
        LegalSection(
          heading: '2. How We Use Your Data',
          body: 'Placeholder body text for this section.',
        ),
        // Add remaining sections here
      ],
    );
  }
}

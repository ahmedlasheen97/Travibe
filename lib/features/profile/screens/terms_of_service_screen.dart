import 'package:flutter/material.dart';
import 'package:travibe/core/links/link_opener.dart';
import 'package:travibe/features/legal/data/legal_page.dart';
import 'package:travibe/features/legal/data/legal_pages_repo.dart';
import 'package:travibe/features/legal/screens/legal_page_screen.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key, this.repo, this.linkOpener});
  final LegalPagesRepo? repo;
  final LinkOpener? linkOpener;
  @override
  Widget build(BuildContext context) => LegalPageScreen(
    slug: LegalPageSlug.terms,
    repo: repo,
    linkOpener: linkOpener,
  );
}

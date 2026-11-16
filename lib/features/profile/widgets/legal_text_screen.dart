import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/features/legal/data/legal_documents.dart';

/// Presentation only: all document text, status and versioning live in data/.
class LegalTextScreen extends StatefulWidget {
  const LegalTextScreen({
    super.key,
    required this.document,
    required this.onRelatedDocument,
  });
  final LegalDocument document;
  final Future<void> Function() onRelatedDocument;
  @override
  State<LegalTextScreen> createState() => _LegalTextScreenState();
}

class _LegalTextScreenState extends State<LegalTextScreen> {
  LegalDocument get document => widget.document;
  bool _opening = false;
  Future<void> _openRelated() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onRelatedDocument();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(
      fontFamily: 'Plus Jakarta Sans',
      color: const Color(0xFFBDBCBB),
      fontSize: AppSizes.adaptiveFont(15),
      height: 1.65,
    );
    return Scaffold(
      backgroundColor: DarkColors.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSizes.adaptiveWidth(20),
                vertical: 8,
              ),
              child: Row(
                children: [
                  const BackButtonWidget(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        document.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          color: Colors.white,
                          decoration: TextDecoration.none,
                          fontSize: AppSizes.adaptiveFont(18),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 52),
                ],
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: SelectionArea(
                    child: ListView(
                      key: PageStorageKey(
                        'legal-${document.type.name}-${document.languageCode}-${LegalDocument.contentVersion}',
                      ),
                      padding: EdgeInsets.fromLTRB(
                        AppSizes.adaptiveWidth(20),
                        16,
                        AppSizes.adaptiveWidth(20),
                        32,
                      ),
                      children: [
                        Text(document.lastUpdatedText, style: body),
                        const SizedBox(height: 4),
                        Text(document.effectiveDateText, style: body),
                        const SizedBox(height: 4),
                        Text(
                          '${document.versionLabel}: ${LegalDocument.contentVersion}',
                          style: body.copyWith(
                            fontSize: AppSizes.adaptiveFont(13),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          document.reviewNotice,
                          key: const ValueKey('legal-review-notice'),
                          style: body.copyWith(
                            color: DarkColors.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(document.introduction, style: body),
                        const SizedBox(height: 28),
                        for (final section in document.sections)
                          Padding(
                            key: ValueKey('legal-section-${section.id}'),
                            padding: const EdgeInsets.only(bottom: 28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Semantics(
                                  header: true,
                                  child: Text(
                                    section.heading,
                                    style: body.copyWith(
                                      color: Colors.white,
                                      fontSize: AppSizes.adaptiveFont(17),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(section.body, style: body),
                              ],
                            ),
                          ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            key: const ValueKey('legal-related-document'),
                            onPressed: _opening ? null : _openRelated,
                            style: TextButton.styleFrom(
                              foregroundColor: DarkColors.primaryColor,
                              minimumSize: const Size(48, 48),
                              textStyle: body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: Text(document.relatedDocumentLabel),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

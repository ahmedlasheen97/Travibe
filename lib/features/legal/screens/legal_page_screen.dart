import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/links/link_opener.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/legal/cubit/legal_page_cubit.dart';
import 'package:travibe/features/legal/data/legal_page.dart';
import 'package:travibe/features/legal/data/legal_pages_repo.dart';

/// Terms of Service / Privacy Policy, rendered natively from the website page
/// that the admin panel edits. Reached from Settings → Help & Legal, the Sign
/// Up consent links and the public GoRouter routes.
class LegalPageScreen extends StatelessWidget {
  const LegalPageScreen({
    super.key,
    required this.slug,
    this.repo,
    this.linkOpener,
  });

  final LegalPageSlug slug;
  final LegalPagesRepo? repo;
  final LinkOpener? linkOpener;

  static const loadFailedMessage = "Couldn't load. Check your connection.";
  static const openFailedMessage =
      "Couldn't open the page. Check your connection.";

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => LegalPageCubit(slug, repo: repo)..load(),
    child: _LegalPageView(
      slug: slug,
      repo: repo,
      linkOpener: linkOpener ?? const LinkOpener(),
    ),
  );
}

class _LegalPageView extends StatelessWidget {
  const _LegalPageView({
    required this.slug,
    required this.repo,
    required this.linkOpener,
  });

  final LegalPageSlug slug;
  final LegalPagesRepo? repo;
  final LinkOpener linkOpener;

  /// In-text links: our own legal pages open the native screen, everything
  /// else the in-app browser.
  Future<void> _openLink(BuildContext context, Uri uri) async {
    final own = LegalPageSlug.fromUri(uri);
    if (own == slug) return;
    if (own != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              LegalPageScreen(slug: own, repo: repo, linkOpener: linkOpener),
        ),
      );
      return;
    }
    await _openInBrowser(context, uri);
  }

  Future<void> _openInBrowser(BuildContext context, Uri uri) async {
    final toast = TravibeToast.of(context);
    if (!await linkOpener.openInApp(uri)) {
      toast.present(
        const TravibeToastData.error(LegalPageScreen.openFailedMessage),
      );
    }
  }

  Future<void> _copyEmail(BuildContext context, String email) async {
    final toast = TravibeToast.of(context);
    await Clipboard.setData(ClipboardData(text: email));
    toast.present(const TravibeToastData.success('Copied'));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LegalPageCubit>();
    return BlocListener<LegalPageCubit, LegalPageState>(
      listenWhen: (previous, current) => current.failures > previous.failures,
      listener: (context, _) => TravibeToast.show(
        context,
        TravibeToastData.error(
          LegalPageScreen.loadFailedMessage,
          actionLabel: 'Refresh',
          onAction: cubit.refresh,
        ),
      ),
      child: Scaffold(
        backgroundColor: DarkColors.backgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              BlocBuilder<LegalPageCubit, LegalPageState>(
                buildWhen: (a, b) => _title(a) != _title(b),
                builder: (context, state) => _Header(title: _title(state)),
              ),
              Expanded(
                child: BlocBuilder<LegalPageCubit, LegalPageState>(
                  builder: (context, state) => switch (state) {
                    LegalPageLoading() => const Center(
                      key: ValueKey('legal-loading'),
                      child: AppActivityIndicator(),
                    ),
                    LegalPageUnavailable(:final retrying) => _Fallback(
                      retrying: retrying,
                      onOpenInBrowser: () =>
                          _openInBrowser(context, slug.webUri),
                    ),
                    LegalPageLoaded(:final page) => _LegalContent(
                      page: page,
                      onRefresh: cubit.refresh,
                      onLink: (uri) => _openLink(context, uri),
                      onEmail: (email) => _copyEmail(context, email),
                      onViewOnWebsite: () =>
                          _openInBrowser(context, slug.webUri),
                    ),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _title(LegalPageState state) => switch (state) {
    LegalPageLoaded(:final page) => page.title,
    _ => slug.title,
  };
}

TextStyle _bodyStyle() => TextStyle(
  fontFamily: 'Plus Jakarta Sans',
  color: DarkColors.greyColor,
  fontSize: AppSizes.legalBodyFont,
  height: 1.65,
);

class _Header extends StatelessWidget {
  const _Header({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: AppSizes.legalHorizontalPadding,
      vertical: AppSizes.legalHeaderVerticalPadding,
    ),
    child: Row(
      children: [
        const BackButtonWidget(),
        SizedBox(width: AppSizes.adaptiveWidth(8)),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              key: const ValueKey('legal-title'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                color: DarkColors.whiteColor,
                fontSize: AppSizes.legalTitleFont,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        // Balances the back button so the title stays centred.
        SizedBox(width: BackButtonWidget.size + AppSizes.adaptiveWidth(8)),
      ],
    ),
  );
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.retrying, required this.onOpenInBrowser});
  final bool retrying;
  final VoidCallback onOpenInBrowser;

  @override
  Widget build(BuildContext context) {
    final body = _bodyStyle();
    return Center(
      key: const ValueKey('legal-unavailable'),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.legalHorizontalPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              LegalPageScreen.loadFailedMessage,
              textAlign: TextAlign.center,
              style: body,
            ),
            SizedBox(height: AppSizes.legalFallbackGap),
            if (retrying)
              const AppActivityIndicator()
            else
              TextButton(
                key: const ValueKey('legal-open-in-browser'),
                onPressed: onOpenInBrowser,
                style: TextButton.styleFrom(
                  foregroundColor: DarkColors.primaryColor,
                  minimumSize: const Size(48, 48),
                  textStyle: body.copyWith(fontWeight: FontWeight.w600),
                ),
                child: const Text('Open in browser'),
              ),
          ],
        ),
      ),
    );
  }
}

class _LegalContent extends StatelessWidget {
  const _LegalContent({
    required this.page,
    required this.onRefresh,
    required this.onLink,
    required this.onEmail,
    required this.onViewOnWebsite,
  });

  final LegalPage page;
  final Future<void> Function() onRefresh;
  final ValueChanged<Uri> onLink;
  final ValueChanged<String> onEmail;
  final VoidCallback onViewOnWebsite;

  @override
  Widget build(BuildContext context) {
    final body = _bodyStyle();
    final updated = page.updatedAt;
    final rtl = page.languageCode == 'ar';
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: AppRefreshIndicator(
        onRefresh: onRefresh,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.legalMaxContentWidth,
            ),
            child: SelectionArea(
              child: ListView(
                key: PageStorageKey('legal-${page.slug.name}'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: AppSizes.legalContentPadding,
                children: [
                  if (updated != null) ...[
                    Text(
                      'Last updated: ${formatLegalDate(updated)}',
                      key: const ValueKey('legal-last-updated'),
                      style: body.copyWith(fontSize: AppSizes.legalMetaFont),
                    ),
                    SizedBox(height: AppSizes.legalMetaGap),
                  ],
                  for (final (index, block) in page.blocks.indexed)
                    Padding(
                      padding: EdgeInsets.only(
                        top: block.isHeading && index > 0
                            ? AppSizes.legalHeadingTopGap
                            : 0,
                        bottom: block.isHeading
                            ? AppSizes.legalHeadingGap
                            : AppSizes.legalParagraphGap,
                      ),
                      child: _BlockText(
                        block: block,
                        style: block.isHeading
                            ? body.copyWith(
                                color: DarkColors.whiteColor,
                                fontSize: AppSizes.legalHeadingFont,
                                fontWeight: FontWeight.w600,
                              )
                            : body,
                        onLink: onLink,
                        onEmail: onEmail,
                      ),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const ValueKey('legal-view-on-website'),
                      onPressed: onViewOnWebsite,
                      style: TextButton.styleFrom(
                        foregroundColor: DarkColors.primaryColor,
                        minimumSize: const Size(48, 48),
                        padding: EdgeInsets.zero,
                        textStyle: body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      child: const Text('View on website'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One paragraph/heading; owns the tap recognizers of its links and emails.
class _BlockText extends StatefulWidget {
  const _BlockText({
    required this.block,
    required this.style,
    required this.onLink,
    required this.onEmail,
  });

  final LegalBlock block;
  final TextStyle style;
  final ValueChanged<Uri> onLink;
  final ValueChanged<String> onEmail;

  @override
  State<_BlockText> createState() => _BlockTextState();
}

class _BlockTextState extends State<_BlockText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final block = widget.block;
    final link = widget.style.copyWith(
      color: DarkColors.primaryColor,
      decoration: TextDecoration.underline,
      decorationColor: DarkColors.primaryColor,
    );
    final text = Text.rich(
      TextSpan(
        children: [
          for (final span in block.spans)
            TextSpan(
              text: span.text,
              style: [
                if (span.link != null || span.email != null) link,
                if (span.bold && !block.isHeading)
                  const TextStyle(
                    color: DarkColors.whiteColor,
                    fontWeight: FontWeight.w600,
                  ),
              ].fold<TextStyle?>(null, (a, b) => a?.merge(b) ?? b),
              recognizer: switch (span) {
                LegalSpan(:final email?) => _tap(() => widget.onEmail(email)),
                LegalSpan(:final link?) => _tap(() => widget.onLink(link)),
                _ => null,
              },
            ),
        ],
      ),
      style: widget.style,
    );
    final semantic = block.isHeading
        ? Semantics(header: true, child: text)
        : text;
    return block.isListItem
        ? Padding(
            padding: EdgeInsetsDirectional.only(
              start: AppSizes.legalListIndent,
            ),
            child: semantic,
          )
        : semantic;
  }
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

/// "25 November 2026", matching the website.
String formatLegalDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

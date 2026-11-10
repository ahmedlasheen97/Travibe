import 'package:flutter/material.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/features/profilesetup/data/reference_item.dart';

class CatalogStatusView extends StatelessWidget {
  const CatalogStatusView({
    super.key,
    required this.catalog,
    required this.onRetry,
  });
  final ReferenceCatalog catalog;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => switch (catalog.status) {
    CatalogStatus.loading => const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    ),
    CatalogStatus.failure => ErrorRetryView(
      message: catalog.error,
      onRetry: onRetry,
    ),
    CatalogStatus.loaded when catalog.items.isEmpty => ErrorRetryView(
      message: 'No options are available right now.',
      onRetry: onRetry,
    ),
    CatalogStatus.loaded => const SizedBox.shrink(),
  };
}

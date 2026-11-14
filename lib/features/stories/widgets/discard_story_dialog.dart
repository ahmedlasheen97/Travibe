import 'package:flutter/widgets.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';

/// Same glass confirmation as discarding a failed post upload.
Future<bool> showDiscardStoryDialog(BuildContext context) =>
    showGlassConfirmDialog(
      context,
      title: 'Discard story?',
      message: 'Your story won’t be posted.',
      confirmLabel: 'Discard',
    );

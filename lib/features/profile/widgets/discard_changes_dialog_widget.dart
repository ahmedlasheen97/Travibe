import 'package:flutter/widgets.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';

Future<bool> showDiscardChangesDialogWidget(BuildContext context) =>
    showGlassConfirmDialog(
      context,
      title: 'Discard Changes?',
      message: 'You have unsaved changes. Are you sure you want to leave?',
      confirmLabel: 'Discard',
    );

import 'package:flutter/widgets.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';

Future<bool> showDiscardPostDialog(BuildContext context) =>
    showGlassConfirmDialog(
      context,
      title: 'Discard Post?',
      message: 'Your post won’t be saved.',
      confirmLabel: 'Discard',
    );

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/features/auth/cubit/sign_out_cubit.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';

/// Same explicit-only dismissal, API and session lifecycle; compact glass surface.
Future<bool> showLogOutDialogWidget(
  BuildContext context, {
  AuthRepo? authRepo,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (_) => BlocProvider(
      create: (_) => SignOutCubit(repo: authRepo),
      child: BlocConsumer<SignOutCubit, SignOutState>(
        listener: (context, state) {
          if (state.signedOut) Navigator.pop(context, true);
        },
        builder: (context, state) => GlassConfirmDialog(
          surfaceKey: const ValueKey('logout-glass-surface'),
          title: 'Log Out?',
          message: 'Are you sure you want to log out of Travibe?',
          confirmLabel: 'Log Out',
          loading: state.loading,
          loadingLabel: 'Logging out',
          error: state.error,
          notice: state.sessionChanged
              ? 'Your session changed. Close this dialog and reopen Settings.'
              : null,
          confirmEnabled: !state.sessionChanged,
          onConfirm: context.read<SignOutCubit>().submit,
        ),
      ),
    ),
  );
  return result ?? false;
}

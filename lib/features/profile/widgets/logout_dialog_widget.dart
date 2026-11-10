import 'package:flutter/cupertino.dart';
import 'package:travibe/core/widgets/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/theme/dark_colors.dart';
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
        builder: (context, state) {
          final surface = GlassSurface(
            surfaceKey: const ValueKey('logout-glass-surface'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Log Out?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: DarkColors.whiteColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Are you sure you want to log out of Travibe?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: DarkColors.greyColor,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        state.error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFDB4A3D),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (state.sessionChanged)
                    const Text(
                      'Your session changed. Close this dialog and reopen Settings.',
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: state.loading || state.sessionChanged
                              ? null
                              : context.read<SignOutCubit>().submit,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFDB4A3D),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: state.loading
                              ? Semantics(
                                  label: 'Logging out',
                                  child: const CupertinoActivityIndicator(
                                    radius: 11,
                                    color: DarkColors.primaryColor,
                                  ),
                                )
                              : const Text('Log Out'),
                        ),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: state.loading
                              ? null
                              : () => Navigator.pop(context, false),
                          style: TextButton.styleFrom(
                            foregroundColor: DarkColors.whiteColor,
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
          return PopScope(
            canPop: !state.loading,
            child: Dialog(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: surface,
              ),
            ),
          );
        },
      ),
    ),
  );
  return result ?? false;
}

import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/features/profile/widgets/settings_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import '../cubit/account_deletion_cubit.dart';
import '../data/account_repo.dart';
import 'session_exit.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, this.repo});
  final AccountRepo? repo;
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  final _reason = TextEditingController();
  late final _cubit = AccountDeletionCubit(repo: widget.repo);
  bool _showingConfirmation = false;

  /// Kept on screen only: `DELETE /account` has no reason field yet
  /// (requested in docs/BACKEND_REQUESTS.md).
  static const maxReason = 500;

  @override
  void initState() {
    super.initState();
    _password.addListener(_fieldChanged);
    _reason.addListener(_fieldChanged);
  }

  /// Rebuilds the submit button and the unsaved-changes guard.
  void _fieldChanged() => setState(() {});

  bool _canSubmit(AccountDeletionState state) =>
      _password.text.isNotEmpty &&
      !state.loading &&
      !state.sessionChanged &&
      state.error?.outcomeUncertain != true;

  Future<void> _submit() async {
    if (_showingConfirmation || !_canSubmit(_cubit.state)) return;
    FocusScope.of(context).unfocus();
    _showingConfirmation = true;
    try {
      final confirmed = await showGlassConfirmDialog(
        context,
        title: 'Delete your account?',
        message:
            'This action cannot be undone. Your Travibe account will be permanently deleted.',
        confirmLabel: 'Delete',
      );
      if (!mounted || !confirmed) return;
      final request = _cubit.submit(_password.text, confirmed: true);
      // Only the in-flight transport holds the required query value.
      _password.clear();
      await request;
    } finally {
      _showingConfirmation = false;
    }
  }

  @override
  void dispose() {
    _password.removeListener(_fieldChanged);
    _reason.removeListener(_fieldChanged);
    _password.clear();
    _password.dispose();
    _reason.dispose();
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<AccountDeletionCubit, AccountDeletionState>(
    bloc: _cubit,
    listener: (context, state) {
      if (state.sessionChanged) _password.clear();
      if (state.deleted) {
        _password.clear();
        openSignedOutScreen(context);
      }
    },
    builder: (context, state) {
      final error = state.error;
      final fieldError = error?.statusCode == 422 ? error!.message : null;
      return SettingsFormScaffold(
        title: 'Delete Account',
        busy: state.loading,
        // Only a form that can still be sent has changes worth guarding.
        dirty:
            !state.deleted &&
            !state.sessionChanged &&
            error?.outcomeUncertain != true &&
            (_password.text.isNotEmpty || _reason.text.isNotEmpty),
        button: SettingsActionButton(
          key: const ValueKey('delete-account-submit'),
          label: 'Delete my Account',
          color: DarkColors.dangerColor,
          loading: state.loading,
          loadingLabel: 'Deleting account',
          onPressed: _canSubmit(state) ? _submit : null,
        ),
        children: [
          const SettingsNotice(
            'Your account, profile, posts, messages, and related data will be permanently deleted.',
            danger: true,
          ),
          SizedBox(height: AppSizes.h24),
          const SettingsFieldLabel('Current password', required: true),
          CustomTextField(
            key: const ValueKey('delete-account-password'),
            title: '',
            hintText: 'enter your current password',
            controller: _password,
            passwordVisibilityToggle: true,
            enabled: !state.loading && !state.sessionChanged,
            errorText: fieldError,
            prefixIcon: SvgPicture.asset(
              'assets/images/auth/lock.svg',
              width: 20,
              height: 20,
            ),
          ),
          SizedBox(height: AppSizes.h24),
          const SettingsFieldLabel('Problem'),
          SettingsMultilineField(
            fieldKey: const ValueKey('delete-account-reason'),
            controller: _reason,
            hintText: 'Why you want to delete this account?',
            maxLength: maxReason,
            enabled: !state.loading,
          ),
          if (state.sessionChanged)
            Padding(
              padding: EdgeInsets.only(top: AppSizes.h12),
              child: const Text(
                'Your session changed. Reopen Settings before continuing.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          if (error != null && fieldError == null)
            Padding(
              padding: EdgeInsets.only(top: AppSizes.h12),
              child: Text(
                error.message,
                style: const TextStyle(color: DarkColors.dangerColor),
              ),
            ),
        ],
      );
    },
  );
}

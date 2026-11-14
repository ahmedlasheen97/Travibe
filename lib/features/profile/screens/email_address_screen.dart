import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/screens/otp_verification_screen.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/cubit/email_change_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/widgets/settings_form.dart';

/// `Sal******21@gmail.com`: first 3 and last 2 characters of the local part.
String maskEmail(String email) {
  final at = email.lastIndexOf('@');
  if (at <= 0) return email;
  final name = email.substring(0, at);
  final domain = email.substring(at);
  if (name.length <= 2) return '${name[0]}******$domain';
  if (name.length <= 5) return '${name.substring(0, 1)}******$domain';
  return '${name.substring(0, 3)}******${name.substring(name.length - 2)}'
      '$domain';
}

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// Format check matching the API (`format: email`, max 255).
bool isValidEmail(String value) =>
    value.length <= 255 && _emailPattern.hasMatch(value);

class EmailAddressScreen extends StatefulWidget {
  const EmailAddressScreen({
    super.key,
    required this.currentUser,
    this.authRepo,
  });

  final CurrentUserCubit currentUser;
  final AuthRepo? authRepo;

  @override
  State<EmailAddressScreen> createState() => _EmailAddressScreenState();
}

class _EmailAddressScreenState extends State<EmailAddressScreen> {
  final _email = TextEditingController();
  late final _cubit = EmailChangeCubit(repo: widget.authRepo);
  bool _busy = false;

  String get _newEmail => _email.text.trim();
  String? get _currentEmail => widget.currentUser.state.profile?.email;
  bool get _sameAsCurrent =>
      _newEmail.toLowerCase() == _currentEmail?.toLowerCase();
  bool get _canSubmit => isValidEmail(_newEmail) && !_sameAsCurrent && !_busy;

  @override
  void dispose() {
    _email.dispose();
    _cubit.close();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    final email = _newEmail;
    setState(() => _busy = true);
    try {
      final sent = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (_) => BlocProvider.value(
          value: _cubit,
          child: _PasswordDialog(email: email),
        ),
      );
      if (sent != true || !mounted) return;
      ProfileModel? updated;
      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            email: email,
            title: 'Verify your new email',
            authRepo: widget.authRepo,
            onVerify: (code) async => updated = await _cubit.verify(code),
            onResend: _cubit.resend,
          ),
        ),
      );
      final profile = updated;
      if (verified != true || profile == null || !mounted) return;
      widget.currentUser.cacheProfile(
        profile,
        expectedSession: PreferencesManager().sessionRevision,
      );
      final toast = TravibeToast.of(context);
      Navigator.of(context).pop();
      toast.present(
        const TravibeToastData.success('Your email address was updated'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<CurrentUserCubit, CurrentUserState>(
    bloc: widget.currentUser,
    builder: (context, user) => BlocBuilder<EmailChangeCubit, EmailChangeState>(
      bloc: _cubit,
      builder: (context, state) => SettingsFormScaffold(
        title: 'Email Address',
        busy: _busy && state.sending,
        button: SettingsActionButton(
          key: const ValueKey('verify-new-email'),
          label: 'Verify New Email',
          onPressed: _canSubmit ? _verify : null,
        ),
        children: [
          _heading('Current email address'),
          SizedBox(height: AppSizes.h8),
          Text(
            switch (user.profile?.email) {
              final String email when email.isNotEmpty => maskEmail(email),
              _ => '—',
            },
            key: const ValueKey('current-email'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: .7),
              fontSize: AppSizes.sp16,
            ),
          ),
          SizedBox(height: AppSizes.h12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _VerifiedChip(
              verified: user.profile?.emailVerifiedAt != null,
            ),
          ),
          SizedBox(height: AppSizes.adaptiveHeight(28)),
          _heading('Change Email Address'),
          SizedBox(height: AppSizes.h12),
          CustomTextField(
            key: const ValueKey('new-email'),
            title: 'New email',
            hintText: 'enter your new email',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            enabled: !_busy,
            prefixIcon: SvgPicture.asset(
              'assets/images/auth/sms.svg',
              width: 20,
              height: 20,
            ),
            errorText: _newEmail.isNotEmpty && _sameAsCurrent
                ? 'This is already your email address'
                : state.emailError,
            onChanged: (_) {
              _cubit.clearEmailError();
              setState(() {});
            },
          ),
          SizedBox(height: AppSizes.h20),
          const SettingsNotice("We'll send an OTP to your new email address"),
        ],
      ),
    ),
  );

  Widget _heading(String text) => Text(
    text,
    style: TextStyle(
      color: Colors.white,
      fontSize: AppSizes.adaptiveFont(20),
      fontWeight: FontWeight.w500,
    ),
  );
}

class _VerifiedChip extends StatelessWidget {
  const _VerifiedChip({required this.verified});
  final bool verified;

  static const _green = Color(0xFF4CAF50);

  @override
  Widget build(BuildContext context) {
    final color = verified ? _green : DarkColors.dangerColor;
    return Container(
      key: ValueKey(verified ? 'email-verified' : 'email-not-verified'),
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.adaptiveWidth(8),
        vertical: AppSizes.adaptiveHeight(4),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(AppSizes.adaptiveRadius(6)),
      ),
      child: Text(
        verified ? 'Verified' : 'Not verified',
        style: TextStyle(color: color, fontSize: AppSizes.sp14),
      ),
    );
  }
}

/// Glass dialog asking for the current password `POST /email/change` needs.
/// Pops true once the code was sent; false when the email itself was refused
/// (its error then shows under the New email field).
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.email});
  final String email;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<EmailChangeCubit, EmailChangeState>(
        listener: (context, state) {
          if (state.codeSentTo != null) Navigator.pop(context, true);
          if (state.emailError != null) Navigator.pop(context, false);
        },
        builder: (context, state) => GlassConfirmDialog(
          surfaceKey: const ValueKey('email-password-dialog'),
          title: 'Confirm your password',
          message:
              'Enter your current password to send a code to ${widget.email}.',
          confirmLabel: 'Send code',
          destructive: false,
          loading: state.sending,
          loadingLabel: 'Sending code',
          error: state.error,
          confirmEnabled: _password.text.isNotEmpty,
          onConfirm: () => context.read<EmailChangeCubit>().request(
            password: _password.text,
            email: widget.email,
          ),
          content: CustomTextField(
            key: const ValueKey('email-change-password'),
            title: 'Current password',
            hintText: 'enter your current password',
            controller: _password,
            autofocus: true,
            passwordVisibilityToggle: true,
            enabled: !state.sending,
            errorText: state.passwordError,
            prefixIcon: SvgPicture.asset(
              'assets/images/auth/lock.svg',
              width: 20,
              height: 20,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      );
}

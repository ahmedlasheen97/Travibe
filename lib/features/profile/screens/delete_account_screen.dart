import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:flutter/cupertino.dart';
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
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  late final _cubit = AccountDeletionCubit(repo: widget.repo);
  bool _obscure = true;
  bool _confirmed = false;
  bool _confirmationError = false;
  bool _showingConfirmation = false;

  void _cancel() {
    if (_cubit.state.loading) return;
    _password.clear();
    Navigator.of(context).maybePop();
  }

  Future<void> _submit() async {
    if (_showingConfirmation ||
        _cubit.state.loading ||
        _cubit.state.error?.outcomeUncertain == true) {
      return;
    }
    if (!_form.currentState!.validate()) return;
    if (!_confirmed) {
      setState(() => _confirmationError = true);
      return;
    }
    _showingConfirmation = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          backgroundColor: const Color(0xFF141414),
          titleTextStyle: Theme.of(context).textTheme.titleMedium!.copyWith(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
          title: const Text('Permanently Delete Account?'),
          content: const Text(
            'This action cannot be undone. Your Travibe account will be permanently deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
                  fontSize: 14,
                  decoration: TextDecoration.none,
                ),
              ),
              child: const Text('Keep Account'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
                  fontSize: 14,
                  decoration: TextDecoration.none,
                ),
              ),
              child: const Text(
                'Delete Permanently',
                style: TextStyle(color: Color(0xFFDB4A3D)),
              ),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) {
        _password.clear();
        setState(() => _confirmed = false);
        return;
      }
      final request = _cubit.submit(_password.text, confirmed: true);
      // Only the in-flight transport holds the required query value.
      _password.clear();
      setState(() => _confirmed = false);
      await request;
    } finally {
      _showingConfirmation = false;
    }
  }

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<AccountDeletionCubit, AccountDeletionState>(
    bloc: _cubit,
    listener: (context, state) {
      if (state.sessionChanged) {
        _password.clear();
        _confirmed = false;
      }
      if (state.deleted) {
        _password.clear();
        openSignedOutScreen(context);
      }
    },
    builder: (context, state) => PopScope(
      canPop: !state.loading,
      child: Scaffold(
        backgroundColor: DarkColors.backgroundColor,
        appBar: AppBar(
          backgroundColor: DarkColors.backgroundColor,
          centerTitle: true,
          title: const Text(
            'Delete Account',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
          leading: BackButtonWidget(
            onTap: _cancel,
            enabled: !state.loading,
            size: 44,
            iconSize: 18,
          ),
        ),
        body: SafeArea(
          top: false,
          child: Form(
            key: _form,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFDB4A3D),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your account, profile and associated account data will be permanently deleted. This action cannot be undone.',
                              style: TextStyle(
                                color: Color(0xFFDB4A3D),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Current password *',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _password,
                        cursorColor: DarkColors.primaryColor,
                        obscureText: _obscure,
                        enabled: !state.loading && !state.sessionChanged,
                        autocorrect: false,
                        autofillHints: const [],
                        keyboardType: TextInputType.visiblePassword,
                        enableSuggestions: false,
                        enableIMEPersonalizedLearning: false,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Please enter your current password'
                            : null,
                        decoration: InputDecoration(
                          hintText: 'Enter your current password',
                          hintStyle: const TextStyle(color: Colors.white54),
                          errorStyle: const TextStyle(
                            color: Color(0xFFDB4A3D),
                            fontSize: 12,
                          ),
                          errorMaxLines: 3,
                          errorText: state.error?.statusCode == 422
                              ? state.error!.message
                              : null,
                          prefixIcon: const Icon(
                            Icons.lock_outline_rounded,
                            color: Colors.white54,
                          ),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: state.loading
                                ? null
                                : () => setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.white54,
                            ),
                          ),
                          filled: true,
                          fillColor: DarkColors.darkgreyColor,
                          focusColor: DarkColors.darkgreyColor,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide(
                              color: DarkColors.greyColor.withValues(
                                alpha: .25,
                              ),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: const BorderSide(
                              color: DarkColors.primaryColor,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: DarkColors.primaryColor,
                        title: const Text(
                          'I understand that deleting my account is permanent.',
                          style: TextStyle(fontSize: 14, color: Colors.white),
                        ),
                        value: _confirmed,
                        onChanged: state.loading || state.sessionChanged
                            ? null
                            : (value) => setState(() {
                                _confirmed = value == true;
                                _confirmationError = false;
                              }),
                      ),
                      if (_confirmationError)
                        const Text(
                          'Confirm permanent account deletion before continuing.',
                          style: TextStyle(color: Color(0xFFDB4A3D)),
                        ),
                      if (state.sessionChanged)
                        const Text(
                          'Your session changed. Reopen Settings before continuing.',
                        ),
                      if (state.error != null && state.error!.statusCode != 422)
                        Text(
                          state.error!.message,
                          style: const TextStyle(color: Color(0xFFDB4A3D)),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed:
                            state.loading ||
                                state.sessionChanged ||
                                state.error?.outcomeUncertain == true
                            ? null
                            : _submit,
                        style: ElevatedButton.styleFrom(
                          textStyle: Theme.of(context).textTheme.labelLarge!
                              .copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.none,
                              ),
                          backgroundColor: const Color(0xFFDB4A3D),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 56),
                          shape: const StadiumBorder(),
                        ),
                        child: state.loading
                            ? Semantics(
                                label: 'Deleting account',
                                child: const CupertinoActivityIndicator(
                                  radius: 11,
                                  color: DarkColors.primaryColor,
                                ),
                              )
                            : const Text(
                                'Delete my Account',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      TextButton(
                        onPressed: state.loading ? null : _cancel,
                        style: TextButton.styleFrom(
                          textStyle: Theme.of(context).textTheme.labelLarge!
                              .copyWith(
                                fontSize: 15,
                                decoration: TextDecoration.none,
                              ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
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

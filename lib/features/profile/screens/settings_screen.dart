import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/profile/screens/blocked_account_screen.dart';
import 'package:travibe/features/profile/screens/change_password_screen.dart';
import 'package:travibe/features/profile/screens/currency_screen.dart';
import 'package:travibe/features/profile/screens/delete_account_screen.dart';
import 'package:travibe/features/profile/screens/privacy_policy_screen.dart';
import 'package:travibe/features/profile/screens/report_problem_screen.dart';
import 'package:travibe/features/profile/screens/terms_of_service_screen.dart';
import 'package:travibe/features/profile/widgets/language_bottom_sheet.dart';
import 'package:travibe/features/profile/widgets/logout_dialog_widget.dart';
import '../cubit/current_user_cubit.dart';
import '../data/account_repo.dart';
import '../data/settings_update.dart';
import 'session_exit.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.currentUser,
    this.accountRepo,
    this.authRepo,
  });
  final CurrentUserCubit? currentUser;
  final AccountRepo? accountRepo;
  final AuthRepo? authRepo;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late CurrentUserCubit _user;
  bool _accountActionOpen = false;
  bool _initialized = false;
  bool _ownsUser = false;
  bool get _busy => _user.state.loading || _user.state.saving != null;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final provided = widget.currentUser ?? context.read<CurrentUserCubit?>();
    _ownsUser = provided == null;
    _user = provided ?? CurrentUserCubit();
    _user.load();
  }

  @override
  void dispose() {
    if (_ownsUser) _user.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CurrentUserCubit, CurrentUserState>(
      bloc: _user,
      listenWhen: (previous, current) =>
          current.error != null && !identical(previous.error, current.error),
      listener: (context, state) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.error!.message))),
      builder: (context, state) {
        final profile = state.profile;
        final ready = profile?.hasSettings == true;
        return Scaffold(
          backgroundColor: DarkColors.backgroundColor,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                const SizedBox(height: 8),
                _buildTopBar(),
                if (state.loading)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Loading settings',
                  ),
                if (state.error != null || !state.loading && !ready) ...[
                  Text(
                    state.error?.message ?? 'Server settings are unavailable.',
                  ),
                  TextButton(
                    onPressed: _busy ? null : _user.load,
                    child: const Text('Retry settings'),
                  ),
                ],
                const SizedBox(height: 24),
                _sectionTitle('Account'),
                _card([
                  _settingsTile(
                    icon: Icons.mail_outline_rounded,
                    title: 'Email',
                    onTap: () {},
                  ),
                  _divider(),
                  _settingsTile(
                    icon: Icons.lock_outline_rounded,
                    title: 'Change Password',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ChangePasswordScreen(),
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 24),
                _sectionTitle('Privacy'),
                _card([
                  _settingsToggleTile(
                    icon: Icons.person_outline_rounded,
                    title: 'Active Status',
                    value: profile?.showActiveStatus,
                    saving: state.saving == 'show_active_status',
                    onChanged: !ready || _busy
                        ? null
                        : (v) => _user.update(
                            SettingsUpdate({'show_active_status': v}),
                          ),
                  ),
                  _divider(),
                  _settingsToggleTile(
                    icon: Icons.group_outlined,
                    title: 'Show Me in Travel Buddy',
                    value: profile?.showInTravelBuddy,
                    saving: state.saving == 'show_in_travel_buddy',
                    onChanged: !ready || _busy
                        ? null
                        : (v) => _user.update(
                            SettingsUpdate({'show_in_travel_buddy': v}),
                          ),
                  ),
                  _divider(),
                  _settingsTile(
                    icon: Icons.person_off_outlined,
                    title: 'Blocked Accounts',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BlocProvider.value(
                            value: context.read<BlockCubit>(),
                            child: const BlockedAccountsScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 24),
                _sectionTitle('App Preferences'),
                _card([
                  _settingsTile(
                    icon: Icons.language_rounded,
                    title: 'Language',
                    detail: state.saving == 'locale'
                        ? 'Saving…'
                        : profile?.locale == 'ar'
                        ? 'العربية'
                        : profile?.locale == 'en'
                        ? 'English'
                        : null,
                    onTap: !ready || _busy
                        ? null
                        : () async {
                            final session =
                                PreferencesManager().sessionRevision;
                            final result = await LanguageBottomSheet.show(
                              context,
                              profile!.locale!,
                            );
                            if (mounted &&
                                result != null &&
                                session ==
                                    PreferencesManager().sessionRevision) {
                              _user.update(SettingsUpdate({'locale': result}));
                            }
                          },
                  ),
                  _divider(),
                  _settingsTile(
                    icon: Icons.credit_card_rounded,
                    title: 'Currency',
                    detail: state.saving == 'currency_code'
                        ? 'Saving…'
                        : profile?.currencyCode ?? (ready ? 'None' : null),
                    onTap: !ready || _busy
                        ? null
                        : () async {
                            final session =
                                PreferencesManager().sessionRevision;
                            final result =
                                await Navigator.push<CurrencySelection>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CurrencyScreen(
                                      selectedCurrencyCode:
                                          profile?.currencyCode,
                                      allowedCodes: _user.supportedCurrencies,
                                    ),
                                  ),
                                );
                            if (mounted &&
                                result != null &&
                                session ==
                                    PreferencesManager().sessionRevision) {
                              _user.update(
                                SettingsUpdate({'currency_code': result.code}),
                              );
                            }
                          },
                  ),
                ]),
                const SizedBox(height: 24),
                _sectionTitle('Notifications'),
                _card([
                  _settingsToggleTile(
                    icon: Icons.notifications_none_rounded,
                    title: 'Push Notifications',
                    subtitle: 'Receive notifications on your phone',
                    value: profile?.pushNotificationsEnabled,
                    saving: state.saving == 'push_notifications_enabled',
                    onChanged: !ready || _busy
                        ? null
                        : (v) => _user.update(
                            SettingsUpdate({'push_notifications_enabled': v}),
                          ),
                  ),
                ]),
                const SizedBox(height: 24),
                _sectionTitle('Help & Legal'),
                _card([
                  _settingsTile(
                    icon: Icons.flag_outlined,
                    title: 'Report a Problem',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ReportProblemScreen(),
                        ),
                      );
                    },
                  ),
                  _divider(),
                  _settingsTile(
                    icon: Icons.description_outlined,
                    title: 'Terms of Service',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const TermsOfServiceScreen(),
                        ),
                      );
                    },
                  ),
                  _divider(),
                  _settingsTile(
                    icon: Icons.shield_outlined,
                    title: 'Privacy Policy',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PrivacyPolicyScreen(),
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 24),
                _card([
                  _settingsTile(
                    icon: Icons.logout_rounded,
                    title: 'Log Out',
                    onTap: _accountActionOpen
                        ? null
                        : () async {
                            if (_accountActionOpen) return;
                            _accountActionOpen = true;
                            try {
                              final signedOut = await showLogOutDialogWidget(
                                context,
                                authRepo: widget.authRepo,
                              );
                              if (signedOut && context.mounted) {
                                openSignedOutScreen(context);
                              }
                            } finally {
                              if (mounted) _accountActionOpen = false;
                            }
                          },
                  ),
                ]),
                const SizedBox(height: 16),
                _buildDeleteAccount(() async {
                  if (_accountActionOpen) return;
                  _accountActionOpen = true;
                  try {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            DeleteAccountScreen(repo: widget.accountRepo),
                      ),
                    );
                  } finally {
                    if (mounted) _accountActionOpen = false;
                  }
                }),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        BackButtonWidget(
          onTap: () => Navigator.of(context).maybePop(),
          size: 36,
          iconSize: 16,
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Text(
            'Settings and Privacy',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() {
    return const Divider(
      height: 1,
      thickness: 1,
      color: Color(0xFF232323),
      indent: 52,
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required VoidCallback? onTap,
    String? detail,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            if (detail != null)
              Flexible(
                child: Text(
                  detail,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white38,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsToggleTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool? value,
    required ValueChanged<bool>? onChanged,
    bool saving = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (saving)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Saving setting',
              ),
            ),
          if (value == null)
            const Flexible(
              child: Text(
                'Unavailable',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            )
          else
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: DarkColors.primaryColor,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFF3B3B3B),
            ),
        ],
      ),
    );
  }

  Widget _buildDeleteAccount(VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFDB4A3D),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.person_off_outlined,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Delete Account',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

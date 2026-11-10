import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/features/onboarding/cubit/startup_cubit.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/onboarding/data/onboarding_repo.dart';
import 'package:travibe/features/onboarding/screens/splash_screen.dart';

/// Coordinates readiness around the unchanged finite splash animation.
class StartupScreen extends StatefulWidget {
  const StartupScreen({
    super.key,
    required this.onReady,
    this.startup,
    this.auth,
    this.onboardingRepo,
  });
  final ValueChanged<StartupDecision> onReady;
  final StartupCubit? startup;
  final AuthRepo? auth;
  final OnboardingRepo? onboardingRepo;
  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen>
    with WidgetsBindingObserver {
  late final StartupCubit _startup =
      widget.startup ?? StartupCubit(auth: widget.auth);
  bool _animationDone = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startup.resolve();
    if (!PreferencesManager().onboardingCompleted) {
      (widget.onboardingRepo ?? OnboardingRepo.shared).prefetch(
        PreferencesManager().getLanguage(),
      );
    }
  }

  void _maybeNavigate() {
    void navigate() {
      if (!mounted || _navigated || !_animationDone) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      final state = _startup.state;
      if (state.decision == null ||
          state.sessionRevision != PreferencesManager().sessionRevision) {
        return;
      }
      _navigated = true;
      widget.onReady(state.decision!);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => navigate());
      WidgetsBinding.instance.ensureVisualUpdate();
    } else {
      // Splash completion is already post-frame; do not add another vsync delay.
      navigate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _maybeNavigate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.startup == null) _startup.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<StartupCubit, StartupState>(
        bloc: _startup,
        listener: (_, _) => _maybeNavigate(),
        builder: (context, state) => Stack(
          fit: StackFit.expand,
          children: [
            SplashScreen(
              onComplete: () {
                setState(() => _animationDone = true);
                _maybeNavigate();
              },
            ),
            if (_animationDone && state.error != null)
              ColoredBox(
                color: DarkColors.primaryColor,
                child: ErrorRetryView(
                  message: state.error!,
                  onRetry: _startup.resolve,
                ),
              ),
          ],
        ),
      );
}

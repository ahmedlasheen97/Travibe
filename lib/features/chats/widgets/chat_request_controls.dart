import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/core/widgets/glass_surface.dart';

/// Small, clipped glass surfaces; no full-screen blur or animation dependency.
class ChatRequestButton extends StatefulWidget {
  const ChatRequestButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = const Color(0xFF343434),
    this.loading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool loading;
  @override
  State<ChatRequestButton> createState() => _ChatRequestButtonState();
}

class _ChatRequestButtonState extends State<ChatRequestButton> {
  bool _pressed = false;
  Alignment _highlight = Alignment.topLeft;
  bool get _enabled => widget.onPressed != null && !widget.loading;
  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        void locate(PointerEvent event) {
          if (!_enabled || reduced) return;
          setState(() {
            _pressed = true;
            _highlight = Alignment(
              (event.localPosition.dx / constraints.maxWidth * 2 - 1).clamp(
                -1,
                1,
              ),
              (event.localPosition.dy / 50 * 2 - 1).clamp(-1, 1),
            );
          });
        }

        void release(PointerEvent _) {
          if (_pressed) setState(() => _pressed = false);
        }

        return AnimatedScale(
          scale: _pressed && _enabled && !reduced ? .97 : 1,
          duration: reduced ? Duration.zero : const Duration(milliseconds: 240),
          curve: Curves.easeOutBack,
          child: Listener(
            onPointerDown: locate,
            onPointerMove: locate,
            onPointerUp: release,
            onPointerCancel: release,
            child: GlassSurface(
              radius: 100,
              opacity: .65,
              child: ColoredBox(
                color: widget.color.withValues(
                  alpha: _enabled || widget.loading ? .8 : .4,
                ),
                child: AnimatedContainer(
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minHeight: 50),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: _highlight,
                      radius: 1.2,
                      colors: [
                        Colors.white.withValues(
                          alpha: _pressed && !reduced ? .23 : .08,
                        ),
                        Colors.transparent,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .12),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(100),
                      onTap: _enabled ? widget.onPressed : null,
                      splashFactory: reduced
                          ? NoSplash.splashFactory
                          : InkRipple.splashFactory,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Center(
                          child: widget.loading
                              ? Semantics(
                                  label: '${widget.label} in progress',
                                  child: const SizedBox.square(
                                    dimension: 20,
                                    child: CupertinoActivityIndicator(
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  widget.label,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ChatPendingRequestControls extends StatelessWidget {
  const ChatPendingRequestControls({
    super.key,
    required this.onAccept,
    required this.onDecline,
    this.accepting = false,
    this.error,
  });
  final VoidCallback? onAccept, onDecline;
  final bool accepting;
  final String? error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Accept request to reply',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ChatRequestButton(label: 'Decline', onPressed: onDecline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChatRequestButton(
                label: 'Accept',
                onPressed: onAccept,
                loading: accepting,
                color: DarkColors.primaryColor,
              ),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error!, style: const TextStyle(color: Colors.white70)),
          ),
      ],
    ),
  );
}

class ChatDeclineRequestDialog extends StatefulWidget {
  const ChatDeclineRequestDialog({
    super.key,
    required this.onConfirm,
    this.title = 'Decline message request?',
    this.description = 'This request will be removed from your requests.',
    this.confirmLabel = 'Decline',
    this.failureMessage = 'Unable to decline request. Please try again.',
  });
  final Future<void> Function() onConfirm;
  final String title, description, confirmLabel, failureMessage;
  @override
  State<ChatDeclineRequestDialog> createState() =>
      _ChatDeclineRequestDialogState();
}

class _ChatDeclineRequestDialogState extends State<ChatDeclineRequestDialog> {
  final _preferences = PreferencesManager();
  late final int _session;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _session = _preferences.sessionRevision;
    _preferences.addListener(_changed);
  }

  void _changed() {
    if (_session == _preferences.sessionRevision) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  @override
  void dispose() {
    _preferences.removeListener(_changed);
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy || _session != _preferences.sessionRevision) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted && _session == _preferences.sessionRevision) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted && _session == _preferences.sessionRevision) {
        setState(() {
          _busy = false;
          _error = widget.failureMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => GlassConfirmDialog(
    title: widget.title,
    message: widget.description,
    confirmLabel: widget.confirmLabel,
    loading: _busy,
    error: _error,
    onConfirm: _confirm,
  );
}

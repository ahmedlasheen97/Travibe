import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/navigation/bottom_nav_visibility.dart';
import 'package:travibe/core/theme/dark_colors.dart';

enum TravibeToastVariant { success, info, error }

/// What one floating toast shows (docs/figma/home_toasts/).
@immutable
class TravibeToastData {
  const TravibeToastData({
    required this.message,
    this.variant = TravibeToastVariant.info,
    this.actionLabel,
    this.onAction,
    this.onClose,
    this.leading,
    this.duration = const Duration(seconds: 4),
  }) : assert((actionLabel == null) == (onAction == null));

  /// Green, check-circle; hides after ~3s.
  const TravibeToastData.success(String message)
    : this(
        message: message,
        variant: TravibeToastVariant.success,
        duration: const Duration(seconds: 3),
      );

  const TravibeToastData.info(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Widget? leading,
  }) : this(
         message: message,
         actionLabel: actionLabel,
         onAction: onAction,
         leading: leading,
       );

  const TravibeToastData.error(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onClose,
  }) : this(
         message: message,
         variant: TravibeToastVariant.error,
         actionLabel: actionLabel,
         onAction: onAction,
         onClose: onClose,
       );

  final String message;
  final TravibeToastVariant variant;

  /// Pill button on the trailing side.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Shows an X when set.
  final VoidCallback? onClose;

  /// Replaces the variant icon (e.g. an upload spinner).
  final Widget? leading;

  /// Auto-hide delay for [TravibeToastController.show]. Sticky toasts ignore it.
  final Duration duration;

  bool _sameContent(TravibeToastData other) =>
      message == other.message &&
      variant == other.variant &&
      actionLabel == other.actionLabel &&
      (onClose == null) == (other.onClose == null);
}

@immutable
class TravibeToastEntry {
  const TravibeToastEntry._(this.id, this.data, {required this.sticky});
  final int id;
  final TravibeToastData data;
  final bool sticky;
}

/// Holds the single visible toast. A transient toast ([show]) always wins;
/// when it ends, the latest unresolved sticky toast ([setSticky]) returns.
class TravibeToastController extends ChangeNotifier {
  TravibeToastEntry? _transient;
  final _sticky = <String, TravibeToastEntry>{};
  Timer? _timer;
  int _ids = 0;

  TravibeToastEntry? get current =>
      _transient ?? (_sticky.isEmpty ? null : _sticky.values.last);

  void show(TravibeToastData data) {
    _timer?.cancel();
    _transient = TravibeToastEntry._(++_ids, data, sticky: false);
    _timer = Timer(data.duration, dismiss);
    notifyListeners();
  }

  /// Hides the transient toast, if any.
  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_transient == null) return;
    _transient = null;
    notifyListeners();
  }

  /// Sets or (with null) clears the persistent toast for [key]. A changed
  /// sticky toast is new, so it replaces any transient one.
  void setSticky(String key, TravibeToastData? data) {
    final old = _sticky[key];
    if (data == null) {
      if (_sticky.remove(key) != null) notifyListeners();
      return;
    }
    if (old != null && old.data._sameContent(data)) {
      // Same toast with fresh callbacks (e.g. upload progress): no re-announce.
      _sticky[key] = TravibeToastEntry._(old.id, data, sticky: true);
    } else {
      _sticky.remove(key);
      _sticky[key] = TravibeToastEntry._(++_ids, data, sticky: true);
      _timer?.cancel();
      _transient = null;
    }
    notifyListeners();
  }

  bool hasSticky(String key) => _sticky.containsKey(key);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class TravibeToastScope extends InheritedNotifier<TravibeToastController> {
  const TravibeToastScope({
    super.key,
    required TravibeToastController controller,
    required super.child,
  }) : super(notifier: controller);

  static TravibeToastController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TravibeToastScope>()?.notifier;
}

/// Shows toasts from a context captured before any await. Inside Root this
/// uses the floating toast; elsewhere (pushed routes, isolated tests) it
/// falls back to a plain SnackBar.
class TravibeToast {
  TravibeToast.of(BuildContext context)
    : _controller = TravibeToastScope.maybeOf(context),
      _messenger = ScaffoldMessenger.maybeOf(context);

  final TravibeToastController? _controller;
  final ScaffoldMessengerState? _messenger;

  static void show(BuildContext context, TravibeToastData data) =>
      TravibeToast.of(context).present(data);

  void present(TravibeToastData data) {
    final controller = _controller;
    if (controller != null) {
      controller.show(data);
      return;
    }
    final action = data.onAction;
    _messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(data.message),
          duration: data.duration,
          action: action == null
              ? null
              : SnackBarAction(label: data.actionLabel!, onPressed: action),
        ),
      );
  }

  void dismiss() {
    final controller = _controller;
    if (controller != null) {
      controller.dismiss();
    } else {
      _messenger?.hideCurrentSnackBar();
    }
  }
}

/// Root's toast slot: floats [AppSizes.h16] above the nav bar and follows it
/// when it hides. Must be a direct child of a [Stack].
class TravibeToastHost extends StatefulWidget {
  const TravibeToastHost({
    super.key,
    required this.controller,
    required this.visibility,
    required this.navHeight,
    required this.safeBottom,
  });
  final TravibeToastController controller;
  final BottomNavVisibility visibility;
  final double navHeight;
  final double safeBottom;

  @override
  State<TravibeToastHost> createState() => _TravibeToastHostState();
}

class _TravibeToastHostState extends State<TravibeToastHost> {
  int? _announced;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_announce);
  }

  @override
  void didUpdateWidget(TravibeToastHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_announce);
      widget.controller.addListener(_announce);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_announce);
    super.dispose();
  }

  void _announce() {
    final entry = widget.controller.current;
    if (entry == null || entry.id == _announced || !mounted) return;
    _announced = entry.id;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        entry.data.message,
        Directionality.of(context),
      ),
    );
  }

  void _run(TravibeToastEntry entry, VoidCallback? callback) {
    if (!entry.sticky) widget.controller.dismiss();
    callback?.call();
  }

  @override
  Widget build(BuildContext context) {
    final animate = !MediaQuery.disableAnimationsOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.visibility, widget.controller]),
      builder: (context, _) {
        final entry = widget.controller.current;
        final data = entry?.data;
        return AnimatedPositioned(
          duration: animate ? BottomNavVisibility.duration : Duration.zero,
          curve: BottomNavVisibility.curve,
          left: 0,
          right: 0,
          bottom:
              (widget.visibility.visible
                  ? widget.navHeight
                  : widget.safeBottom) +
              AppSizes.h16,
          child: AnimatedSwitcher(
            duration: animate
                ? const Duration(milliseconds: 200)
                : Duration.zero,
            child: entry == null || data == null
                ? const SizedBox.shrink()
                : TravibeToastView(
                    key: ValueKey('travibe-toast-${entry.id}'),
                    data: data,
                    onAction: data.onAction == null
                        ? null
                        : () => _run(entry, data.onAction),
                    onClose: data.onClose == null
                        ? null
                        : () => _run(entry, data.onClose),
                  ),
          ),
        );
      },
    );
  }
}

/// The toast surface. Figma: 20px side margins, ~46 tall, icon 20, text 16,
/// capsule pill and optional X on the trailing side.
class TravibeToastView extends StatelessWidget {
  const TravibeToastView({
    super.key,
    required this.data,
    this.onAction,
    this.onClose,
  });
  final TravibeToastData data;
  final VoidCallback? onAction;
  final VoidCallback? onClose;

  static Color colorOf(TravibeToastVariant variant) => switch (variant) {
    TravibeToastVariant.success => DarkColors.toastSuccess,
    TravibeToastVariant.info => DarkColors.toastInfo,
    TravibeToastVariant.error => DarkColors.toastError,
  };

  static IconData iconOf(TravibeToastVariant variant) => switch (variant) {
    TravibeToastVariant.success => Icons.check_circle,
    TravibeToastVariant.info => Icons.check_circle,
    TravibeToastVariant.error => Icons.error,
  };

  @override
  Widget build(BuildContext context) {
    final trailing = data.actionLabel != null || data.onClose != null;
    final textStyle = TextStyle(
      fontFamily: 'Plus Jakarta Sans',
      fontSize: AppSizes.adaptiveFont(16),
      height: 1.4,
      fontWeight: FontWeight.w400,
      color: DarkColors.whiteColor,
      decoration: TextDecoration.none,
    );
    return Semantics(
      container: true,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: AppSizes.adaptiveWidth(20)),
        constraints: BoxConstraints(minHeight: AppSizes.adaptiveHeight(46)),
        padding: EdgeInsetsDirectional.only(
          start: AppSizes.adaptiveWidth(12),
          end: AppSizes.adaptiveWidth(trailing ? 6 : 12),
        ),
        decoration: BoxDecoration(
          color: colorOf(data.variant),
          borderRadius: BorderRadius.circular(AppSizes.adaptiveRadius(8)),
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: SizedBox.square(
                dimension: AppSizes.adaptiveWidth(20),
                child:
                    data.leading ??
                    Icon(
                      iconOf(data.variant),
                      key: ValueKey('toast-icon-${data.variant.name}'),
                      size: AppSizes.adaptiveWidth(20),
                      color: DarkColors.whiteColor,
                    ),
              ),
            ),
            SizedBox(width: AppSizes.adaptiveWidth(10)),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: AppSizes.adaptiveHeight(10),
                ),
                child: Text(
                  data.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                ),
              ),
            ),
            if (data.actionLabel != null) ...[
              SizedBox(width: AppSizes.adaptiveWidth(8)),
              _Pill(
                label: data.actionLabel!,
                color: data.variant == TravibeToastVariant.error
                    ? DarkColors.toastErrorPill
                    : DarkColors.toastInfoPill,
                style: textStyle,
                onTap: onAction,
              ),
            ],
            if (data.onClose != null)
              IconButton(
                onPressed: onClose,
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close,
                  size: AppSizes.adaptiveWidth(24),
                  color: DarkColors.whiteColor,
                ),
              )
            else if (data.actionLabel != null)
              SizedBox(width: AppSizes.adaptiveWidth(2)),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.style,
    required this.onTap,
  });
  final String label;
  final Color color;
  final TextStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // 44px tall hit area around the 32px Figma capsule.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          widthFactor: 1,
          child: Container(
            height: AppSizes.adaptiveHeight(32),
            padding: EdgeInsets.symmetric(
              horizontal: AppSizes.adaptiveWidth(16),
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppSizes.adaptiveRadius(50)),
            ),
            child: Text(label, style: style),
          ),
        ),
      ),
    ),
  );
}

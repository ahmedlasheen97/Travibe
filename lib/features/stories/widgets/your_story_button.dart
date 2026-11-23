import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/stories/data/story_model.dart';

/// Only the authenticated ID and known future expiry establish an own active
/// story. Names, absent expiry and stale session data are never ownership proof.
///
/// Home's "You" bubble and my Profile picture share this menu. Profile renames
/// the rows, hides the add row ([showAddStory]: its "+" badge adds a story),
/// adds [onViewPicture] ("View profile picture") and opens the picture instead
/// of adding a story when there is no active story ([onTapWithoutStory]).
class YourStoryButton extends StatefulWidget {
  const YourStoryButton({
    super.key,
    required this.child,
    this.group,
    this.currentUserId,
    this.onAddStory,
    this.onViewStory,
    this.onViewPicture,
    this.onTapWithoutStory,
    this.viewStoryLabel = 'View Story',
    this.addStoryLabel = 'Add to Story',
    this.semanticsLabel = 'Your Story',
    this.showAddStory = true,
    this.now,
  });
  final Widget child;
  final StoryGroup? group;
  final int? currentUserId;
  final VoidCallback? onAddStory, onViewStory;

  /// Adds a "View profile picture" row when set.
  final VoidCallback? onViewPicture;

  /// Tap without an active story; defaults to [onAddStory].
  final VoidCallback? onTapWithoutStory;
  final String viewStoryLabel, addStoryLabel, semanticsLabel;

  /// Shows the [addStoryLabel] row in the menu (Home); Profile hides it.
  final bool showAddStory;
  final DateTime Function()? now;

  @override
  State<YourStoryButton> createState() => _YourStoryButtonState();
}

class _YourStoryButtonState extends State<YourStoryButton> {
  final _menu = MenuController();
  bool _menuOpen = false;

  void _menuChanged(bool open) {
    if (!mounted || open == _menuOpen) return;
    // MenuAnchor can close mid-frame (e.g. on unmount); defer the rebuild.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _menuChanged(open));
      return;
    }
    setState(() => _menuOpen = open);
  }

  final _session = PreferencesManager();
  late int _acceptedSession;
  Timer? _expiry;
  DateTime get _now => widget.now?.call() ?? DateTime.now();

  bool get _hasActiveStory =>
      _session.hasSession &&
      _acceptedSession == _session.sessionRevision &&
      widget.currentUserId != null &&
      widget.group?.user.id == widget.currentUserId &&
      widget.group!.hasActiveStoryAt(_now);

  @override
  void initState() {
    super.initState();
    _acceptedSession = _session.sessionRevision;
    _session.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    _acceptedSession = -1;
    _expiry?.cancel();
    _menu.close();
  }

  @override
  void didUpdateWidget(covariant YourStoryButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ownerChanged = oldWidget.currentUserId != widget.currentUserId;
    if (ownerChanged || oldWidget.group != widget.group) {
      // Home already gates identity and collections by session generation.
      _acceptedSession = _session.sessionRevision;
    }
    if (ownerChanged || !_hasActiveStory) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _menu.close();
      });
    }
    _scheduleExpiry();
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    if (!_menu.isOpen || !_hasActiveStory) return;
    final now = _now;
    final expiries =
        widget.group!.stories
            .map((story) => story.expiresAt)
            .whereType<DateTime>()
            .where((expiry) => expiry.isAfter(now))
            .toList()
          ..sort();
    if (expiries.isEmpty) {
      _expiry = Timer(Duration.zero, () {
        if (mounted) _menu.close();
      });
      return;
    }
    _expiry = Timer(
      expiries.last.difference(now) + const Duration(milliseconds: 1),
      () {
        if (mounted && !_hasActiveStory) _menu.close();
      },
    );
  }

  void _tap() {
    if (_menu.isOpen) {
      _menu.close();
      return;
    }
    if (_hasActiveStory) {
      _menu.open();
      _scheduleExpiry();
    } else {
      (widget.onTapWithoutStory ?? widget.onAddStory)?.call();
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _session.removeListener(_sessionChanged);
    // MenuAnchor removes its root-overlay entries on unmount.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Home's SafeArea/Scaffold may have consumed padding at the anchor. The
    // root-overlay menu still needs the physical window's unconsumed insets.
    final window = MediaQueryData.fromView(View.of(context));
    final padding = window.viewPadding;
    final rowStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(208, 56)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      foregroundColor: const WidgetStatePropertyAll(Colors.white),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontFamily: 'Plus Jakarta Sans',
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    // The menu lives in an overlay, not a route: Android back closes it
    // first instead of leaving the app.
    return PopScope(
      canPop: !_menuOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _menu.close();
      },
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: window.padding,
          viewPadding: window.viewPadding,
          viewInsets: window.viewInsets,
        ),
        child: MenuAnchor(
          controller: _menu,
          onOpen: () => _menuChanged(true),
          onClose: () {
            _expiry?.cancel();
            _menuChanged(false);
          },
          useRootOverlay: true,
          crossAxisUnconstrained: false,
          consumeOutsideTap: true,
          alignmentOffset: const Offset(0, 8),
          reservedPadding: EdgeInsets.fromLTRB(
            padding.left + 8,
            padding.top + 8,
            padding.right + 8,
            padding.bottom + 8,
          ),
          style: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(Color(0xFF171717)),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
            elevation: const WidgetStatePropertyAll(8),
            alignment: AlignmentDirectional.bottomStart,
          ),
          menuChildren: [
            MenuItemButton(
              key: const ValueKey('view-my-story'),
              onPressed: widget.onViewStory == null
                  ? null
                  : () {
                      _menu.close();
                      if (_hasActiveStory) widget.onViewStory?.call();
                    },
              style: rowStyle,
              semanticsLabel: widget.onViewStory == null
                  ? '${widget.viewStoryLabel}. Viewer unavailable.'
                  : widget.viewStoryLabel,
              leadingIcon: SvgPicture.asset(
                'assets/images/interactions/story.svg',
                width: 24,
                height: 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.viewStoryLabel),
                  if (widget.onViewStory == null)
                    const Text(
                      'Viewer unavailable',
                      style: TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                ],
              ),
            ),
            if (widget.showAddStory)
              MenuItemButton(
                key: const ValueKey('add-new-story'),
                style: rowStyle,
                leadingIcon: SvgPicture.asset(
                  'assets/images/interactions/add.svg',
                  width: 24,
                  height: 24,
                ),
                onPressed: () {
                  _menu.close();
                  widget.onAddStory?.call();
                },
                child: Text(widget.addStoryLabel),
              ),
            if (widget.onViewPicture case final viewPicture?)
              MenuItemButton(
                key: const ValueKey('view-profile-picture'),
                style: rowStyle,
                leadingIcon: SvgPicture.asset(
                  'assets/images/icons/profile-circle.svg',
                  width: 24,
                  height: 24,
                ),
                onPressed: () {
                  _menu.close();
                  viewPicture();
                },
                child: const Text('View profile picture'),
              ),
          ],
          child: Semantics(
            button: true,
            label: _hasActiveStory
                ? widget.showAddStory
                      ? '${widget.semanticsLabel}. ${widget.viewStoryLabel} or '
                            '${widget.addStoryLabel}'
                      : '${widget.semanticsLabel}. ${widget.viewStoryLabel}'
                : widget.onTapWithoutStory != null
                ? widget.semanticsLabel
                : '${widget.semanticsLabel}. ${widget.addStoryLabel}',
            child: GestureDetector(
              key: const ValueKey('your-story-bubble'),
              behavior: HitTestBehavior.opaque,
              onTap: _tap,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

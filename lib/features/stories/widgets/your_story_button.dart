import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/stories/data/story_model.dart';

/// Only the authenticated ID and known future expiry establish an own active
/// story. Names, absent expiry and stale session data are never ownership proof.
class YourStoryButton extends StatefulWidget {
  const YourStoryButton({
    super.key,
    required this.child,
    this.group,
    this.currentUserId,
    this.onAddStory,
    this.onViewStory,
    this.now,
  });
  final Widget child;
  final StoryGroup? group;
  final int? currentUserId;
  final VoidCallback? onAddStory, onViewStory;
  final DateTime Function()? now;

  @override
  State<YourStoryButton> createState() => _YourStoryButtonState();
}

class _YourStoryButtonState extends State<YourStoryButton> {
  final _menu = MenuController();
  final _session = PreferencesManager();
  late int _acceptedSession;
  Timer? _expiry;
  DateTime get _now => widget.now?.call() ?? DateTime.now();

  bool get _hasActiveStory =>
      _session.hasSession &&
      _acceptedSession == _session.sessionRevision &&
      widget.currentUserId != null &&
      widget.group?.user.id == widget.currentUserId &&
      widget.group!.stories.any(
        (story) => story.expiresAt?.isAfter(_now) == true,
      );

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
      widget.onAddStory?.call();
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
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: window.padding,
        viewPadding: window.viewPadding,
        viewInsets: window.viewInsets,
      ),
      child: MenuAnchor(
        controller: _menu,
        onClose: () => _expiry?.cancel(),
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
                ? 'View Story. Viewer unavailable.'
                : 'View Story',
            leadingIcon: SvgPicture.asset(
              'assets/images/interactions/story.svg',
              width: 24,
              height: 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('View Story'),
                if (widget.onViewStory == null)
                  const Text(
                    'Viewer unavailable',
                    style: TextStyle(fontSize: 11, color: Colors.white60),
                  ),
              ],
            ),
          ),
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
            child: const Text('Add to Story'),
          ),
        ],
        child: Semantics(
          button: true,
          label: _hasActiveStory
              ? 'Your Story. View Story or Add to Story'
              : 'Your Story. Add to Story',
          child: GestureDetector(
            key: const ValueKey('your-story-bubble'),
            behavior: HitTestBehavior.opaque,
            onTap: _tap,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/shares/screens/open_shared_post.dart';

/// `travibe://posts/{id}` → post ID; anything else → null.
int? parsePostDeepLink(Uri uri) {
  if (uri.scheme != 'travibe' || uri.host != 'posts') return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length != 1) return null;
  final id = int.tryParse(segments.single);
  return id != null && id > 0 && '$id' == segments.single ? id : null;
}

typedef PostLinkOpener = Future<void> Function(BuildContext context, int id);

/// Holds the latest post link until Root is attached with a signed-in
/// session. A link that arrives on a cold start, or while logged out, opens
/// once the startup/login flow reaches Root.
class PostDeepLinkCoordinator {
  PostDeepLinkCoordinator({
    Stream<Uri>? links,
    PostLinkOpener? open,
    PreferencesManager? preferences,
  }) : _open = open ?? openSharedPost,
       _preferences = preferences ?? PreferencesManager() {
    _links = links?.listen(handle, onError: (Object _) {});
    _preferences.addListener(_flush);
  }

  final PostLinkOpener _open;
  final PreferencesManager _preferences;
  StreamSubscription<Uri>? _links;
  Object? _owner;
  BuildContext? _context;
  int? _pending;

  /// Post waiting for Root and a session; for tests and diagnostics.
  int? get pending => _pending;

  void handle(Uri uri) {
    final id = parsePostDeepLink(uri);
    if (id == null) return;
    _pending = id;
    _flush();
  }

  void attach(Object owner, BuildContext context) {
    _owner = owner;
    _context = context;
    _flush();
  }

  void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _context = null;
  }

  void _flush() {
    final id = _pending, context = _context;
    if (id == null ||
        context == null ||
        !context.mounted ||
        !_preferences.hasSession) {
      return;
    }
    _pending = null;
    unawaited(_open(context, id));
  }

  void dispose() {
    _preferences.removeListener(_flush);
    unawaited(_links?.cancel() ?? Future<void>.value());
    _links = null;
    _owner = null;
    _context = null;
  }
}

/// Provides a [PostDeepLinkCoordinator]. Without one, an inert coordinator is
/// created so widget tests never touch the platform link channel.
class PostDeepLinksHost extends StatefulWidget {
  const PostDeepLinksHost({super.key, this.coordinator, required this.child});
  final PostDeepLinkCoordinator? coordinator;
  final Widget child;
  @override
  State<PostDeepLinksHost> createState() => _PostDeepLinksHostState();
}

class _PostDeepLinksHostState extends State<PostDeepLinksHost> {
  late final _owned = widget.coordinator == null
      ? PostDeepLinkCoordinator()
      : null;

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PostDeepLinksScope(
    coordinator: widget.coordinator ?? _owned!,
    child: widget.child,
  );
}

class PostDeepLinksScope extends InheritedWidget {
  const PostDeepLinksScope({
    super.key,
    required this.coordinator,
    required super.child,
  });
  final PostDeepLinkCoordinator coordinator;

  static PostDeepLinkCoordinator? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PostDeepLinksScope>()
      ?.coordinator;

  @override
  bool updateShouldNotify(PostDeepLinksScope oldWidget) =>
      !identical(coordinator, oldWidget.coordinator);
}

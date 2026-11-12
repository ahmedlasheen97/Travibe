import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/profile/screens/open_shared_profile.dart';
import 'package:travibe/features/shares/screens/open_shared_post.dart';

/// An in-app link target.
sealed class DeepLink {
  const DeepLink(this.id);
  final int id;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType && other is DeepLink && other.id == id;

  @override
  int get hashCode => Object.hash(runtimeType, id);
}

/// `travibe://posts/{id}`.
final class PostLink extends DeepLink {
  const PostLink(super.id);
  @override
  String toString() => 'PostLink($id)';
}

/// `travibe://users/{id}`.
final class UserLink extends DeepLink {
  const UserLink(super.id);
  @override
  String toString() => 'UserLink($id)';
}

/// `travibe://posts/{id}` / `travibe://users/{id}`; anything else → null.
/// In `travibe://users/42` the URI **host** is `users` and the path is `/42`.
DeepLink? parseDeepLink(Uri uri) {
  if (uri.scheme != 'travibe') return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length != 1) return null;
  final id = int.tryParse(segments.single);
  if (id == null || id < 1 || '$id' != segments.single) return null;
  return switch (uri.host) {
    'posts' => PostLink(id),
    'users' => UserLink(id),
    _ => null,
  };
}

/// Where Root lets a link open: its context, and a way to show the
/// signed-in user's own Profile tab.
class DeepLinkTarget {
  const DeepLinkTarget(this.context, {this.showMyProfile});
  final BuildContext context;
  final VoidCallback? showMyProfile;
}

typedef DeepLinkOpener =
    Future<void> Function(DeepLinkTarget target, DeepLink link);

Future<void> openDeepLink(DeepLinkTarget target, DeepLink link) =>
    switch (link) {
      PostLink(:final id) => openSharedPost(target.context, id),
      UserLink(:final id) => openSharedProfile(
        target.context,
        id,
        showMyProfile: target.showMyProfile,
      ),
    };

/// Holds the latest link until Root is attached with a signed-in session.
/// A link that arrives on a cold start, or while logged out, opens once the
/// startup/login flow reaches Root.
class DeepLinkCoordinator {
  DeepLinkCoordinator({
    Stream<Uri>? links,
    DeepLinkOpener? open,
    PreferencesManager? preferences,
  }) : _open = open ?? openDeepLink,
       _preferences = preferences ?? PreferencesManager() {
    _links = links?.listen(handle, onError: (Object _) {});
    _preferences.addListener(_flush);
  }

  final DeepLinkOpener _open;
  final PreferencesManager _preferences;
  StreamSubscription<Uri>? _links;
  Object? _owner;
  DeepLinkTarget? _target;
  DeepLink? _pending;

  /// Link waiting for Root and a session; for tests and diagnostics.
  DeepLink? get pending => _pending;

  void handle(Uri uri) {
    final link = parseDeepLink(uri);
    if (link == null) return;
    _pending = link;
    _flush();
  }

  void attach(
    Object owner,
    BuildContext context, {
    VoidCallback? showMyProfile,
  }) {
    _owner = owner;
    _target = DeepLinkTarget(context, showMyProfile: showMyProfile);
    _flush();
  }

  void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _target = null;
  }

  void _flush() {
    final link = _pending, target = _target;
    if (link == null ||
        target == null ||
        !target.context.mounted ||
        !_preferences.hasSession) {
      return;
    }
    _pending = null;
    unawaited(_open(target, link));
  }

  void dispose() {
    _preferences.removeListener(_flush);
    unawaited(_links?.cancel() ?? Future<void>.value());
    _links = null;
    _owner = null;
    _target = null;
  }
}

/// Provides a [DeepLinkCoordinator]. Without one, an inert coordinator is
/// created so widget tests never touch the platform link channel.
class DeepLinksHost extends StatefulWidget {
  const DeepLinksHost({super.key, this.coordinator, required this.child});
  final DeepLinkCoordinator? coordinator;
  final Widget child;
  @override
  State<DeepLinksHost> createState() => _DeepLinksHostState();
}

class _DeepLinksHostState extends State<DeepLinksHost> {
  late final _owned = widget.coordinator == null ? DeepLinkCoordinator() : null;

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DeepLinksScope(
    coordinator: widget.coordinator ?? _owned!,
    child: widget.child,
  );
}

class DeepLinksScope extends InheritedWidget {
  const DeepLinksScope({
    super.key,
    required this.coordinator,
    required super.child,
  });
  final DeepLinkCoordinator coordinator;

  static DeepLinkCoordinator? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeepLinksScope>()?.coordinator;

  @override
  bool updateShouldNotify(DeepLinksScope oldWidget) =>
      !identical(coordinator, oldWidget.coordinator);
}

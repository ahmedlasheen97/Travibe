import 'package:flutter/services.dart';

/// External sharing has no backend side effects. A verified canonical URI takes
/// precedence over text. Text alone does not link back to the original post.
class PostShareActions {
  PostShareActions({this.verifiedPostUri, this.text});
  final Uri? verifiedPostUri;
  final String? text;

  bool get canShare => available || (text?.trim().isNotEmpty ?? false);

  bool get available {
    final uri = verifiedPostUri;
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  Uri get _uri {
    if (!available) {
      throw StateError('A verified public post link is unavailable.');
    }
    return verifiedPostUri!;
  }

  Future<void> copyLink() =>
      Clipboard.setData(ClipboardData(text: _uri.toString()));

  static const channel = MethodChannel('travibe/post_sharing');

  Future<void> moreOptions(Rect origin) {
    if (!canShare) {
      throw StateError('No post text or verified link is available.');
    }
    return channel.invokeMethod<void>('share', {
      if (available) 'url': _uri.toString() else 'text': text!.trim(),
      'x': origin.left,
      'y': origin.top,
      'width': origin.width,
      'height': origin.height,
    });
  }
}

import 'package:travibe/core/permissions/app_permission.dart';
import 'package:travibe/core/permissions/permission_flow.dart';
import 'package:flutter/services.dart';
import 'chat_emoji_picker.dart';
import 'chat_send_button.dart';
import 'chat_voice_composer.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'chat_reply_preview.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/chat_audio_controller.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.composer,
    required this.text,
    this.focusNode,
    this.attachmentAnchor,
    required this.audio,
    required this.canSend,
    required this.uploading,
    required this.onAttachment,
    required this.onTyped,
    required this.onSendVoice,
    this.mediaError,
    this.selectedMediaTray,
    this.onSendAttachments,
    this.topAccessory,
    this.disabledReason = 'Sending is currently unavailable.',
    this.replySenderName,
  });

  /// "You" or the other person's name for the reply bar.
  final String Function(String senderId)? replySenderName;
  final ChatComposerCubit composer;
  final TextEditingController text;
  final FocusNode? focusNode;
  final GlobalKey? attachmentAnchor;
  final ChatAudioController audio;
  final bool canSend, uploading;
  final VoidCallback onAttachment, onTyped, onSendVoice;
  final String? mediaError;
  final String disabledReason;
  final Widget? selectedMediaTray, topAccessory;
  final VoidCallback? onSendAttachments;
  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer>
    with WidgetsBindingObserver {
  /// Records, or, when the microphone is blocked in Settings, explains why
  /// with the shared permission sheet.
  Future<void> _startRecording() async {
    await widget.audio.startRecording();
    if (mounted &&
        widget.audio.needsSettings &&
        !widget.audio.promptedForPermission) {
      await PermissionFlow.showSettings(context, AppPermission.microphone);
    }
  }

  final _ownedFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  late final int _session;
  @override
  void initState() {
    super.initState();
    _session = widget.composer.state.session;
    WidgetsBinding.instance.addObserver(this);
    widget.audio.addListener(_audioNotice);
  }

  /// Shows the controller's one-shot hints (e.g. "too short") as a toast.
  void _audioNotice() {
    final message = widget.audio.notice;
    if (message == null || !mounted) return;
    widget.audio.takeNotice();
    TravibeToast.show(context, TravibeToastData.info(message));
  }

  /// Return key: same action as the send button; empty drafts do nothing.
  void _submit() {
    if (!widget.canSend || widget.audio.recording) return;
    if (widget.selectedMediaTray != null && !widget.uploading) {
      widget.onSendAttachments?.call();
    } else if (widget.composer.state.draft.trim().isNotEmpty) {
      widget.composer.send();
    }
  }

  bool get _voiceMode => widget.audio.recording || widget.audio.draft != null;

  @override
  void didChangeMetrics() {
    // Native keyboard dismissal changes View insets after the toggle's frame.
    if (mounted && _emojiVisible) setState(() {});
  }

  bool _emojiVisible = false;
  double _keyboardInset(BuildContext context) =>
      View.of(context).viewInsets.bottom / View.of(context).devicePixelRatio;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.isCurrentOf(context) == false) {
      _emojiVisible = false;
    }
  }

  @override
  void didUpdateWidget(ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audio != widget.audio) {
      oldWidget.audio.removeListener(_audioNotice);
      widget.audio.addListener(_audioNotice);
    }
    if (oldWidget.composer != widget.composer || !widget.canSend) {
      _emojiVisible = false;
    }
  }

  void _toggleEmoji() {
    if (widget.composer.isClosed || widget.composer.state.session != _session) {
      return;
    }
    if (_emojiVisible) {
      _keyboard();
      return;
    }
    setState(() => _emojiVisible = true);
    _focus.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _attachments() {
    setState(() => _emojiVisible = false);
    _focus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.isCurrentOf(context) != false) {
        widget.onAttachment();
      }
    });
  }

  void _keyboard() {
    setState(() => _emojiVisible = false);
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_emojiVisible &&
          _focus.hasFocus &&
          ModalRoute.isCurrentOf(context) != false) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      }
    });
  }

  void _insertEmoji(String emoji) {
    if (!mounted ||
        !widget.canSend ||
        widget.audio.recording ||
        widget.composer.isClosed ||
        widget.composer.state.session != _session) {
      return;
    }
    widget.text.value = insertChatEmoji(widget.text.value, emoji);
    widget.composer.edit(widget.text.text);
    widget.onTyped();
  }

  double _pickerHeight(BuildContext context) {
    final view = View.of(context);
    final height = MediaQuery.sizeOf(context).height;
    final safe =
        (view.viewPadding.top + view.viewPadding.bottom) /
        view.devicePixelRatio;
    final controls =
        72 * MediaQuery.textScalerOf(context).scale(14) / 14 +
        (widget.topAccessory == null ? 0 : 52) +
        (widget.selectedMediaTray == null ? 0 : 110) +
        (widget.composer.state.replyTo == null ? 0 : 60);
    return (height - safe - 96 - controls).clamp(90.0, 220.0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.audio.removeListener(_audioNotice);
    _ownedFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ComposerViewport(
    child: AnimatedBuilder(
      animation: widget.audio,
      builder: (_, _) => BlocConsumer<ChatComposerCubit, ChatComposerState>(
        bloc: widget.composer,
        listener: (_, state) {
          if (state.session != _session && _emojiVisible) {
            setState(() => _emojiVisible = false);
          }
          if (state.draft.isEmpty && widget.text.text.isNotEmpty) {
            widget.text.clear();
          }
        },
        builder: (context, state) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?widget.topAccessory,
              if ((state.error != null && state.localMessages.isEmpty) ||
                  widget.mediaError != null ||
                  widget.audio.error != null)
                Text(
                  widget.mediaError ??
                      (state.localMessages.isEmpty ? state.error : null) ??
                      widget.audio.error!,
                  style: const TextStyle(color: Colors.white60),
                ),
              if (!widget.canSend)
                Text(
                  widget.disabledReason,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              if (state.replyTo != null)
                Padding(
                  key: const ValueKey('chat-reply-bar'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ChatReplyQuote(
                          title:
                              'Replying to ${widget.replySenderName?.call(state.replyTo!.senderId) ?? 'message'}',
                          preview: ChatReplyPreview.fromMessage(state.replyTo!),
                          lineColor: chatReplyAccent,
                          titleColor: chatReplyAccent,
                          background: Colors.white.withValues(alpha: .06),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('chat-reply-cancel'),
                        tooltip: 'Cancel reply',
                        onPressed: () => widget.composer.setReply(null),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ?widget.selectedMediaTray,
              if (_voiceMode)
                ChatVoiceComposer(
                  audio: widget.audio,
                  canSend: widget.canSend,
                  uploading: widget.uploading,
                  onSendVoice: widget.onSendVoice,
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF141414),
                          border: Border.all(color: Colors.white12),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                              key: widget.attachmentAnchor,
                              tooltip: 'Attachments',
                              onPressed:
                                  widget.uploading || widget.audio.recording
                                  ? null
                                  : _attachments,
                              icon: const Icon(
                                Icons.add,
                                color: Colors.white70,
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: widget.text,
                                cursorColor: Colors.white,
                                focusNode: _focus,
                                // Return sends; long drafts still wrap.
                                keyboardType: _emojiVisible
                                    ? TextInputType.none
                                    : TextInputType.text,
                                textInputAction: TextInputAction.send,
                                // Overrides the default unfocus so the
                                // keyboard stays up for the next message.
                                onEditingComplete: _submit,
                                onTap: () {
                                  if (_emojiVisible) _keyboard();
                                },
                                readOnly: widget.audio.recording,
                                minLines: 1,
                                maxLines:
                                    MediaQuery.sizeOf(context).height < 500
                                    ? 3
                                    : 5,
                                onChanged: (value) {
                                  widget.composer.edit(value);
                                  widget.onTyped();
                                },
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Type Message',
                                  hintFadeDuration: Duration.zero,
                                  filled: false,
                                  hintStyle: TextStyle(color: Colors.white60),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: _emojiVisible
                                  ? 'Show keyboard'
                                  : 'Show emoji picker',
                              onPressed:
                                  !widget.canSend || widget.audio.recording
                                  ? null
                                  : _toggleEmoji,
                              icon: _emojiVisible
                                  ? const Icon(
                                      Icons.keyboard_outlined,
                                      color: Colors.white70,
                                    )
                                  : SvgPicture.asset(
                                      'assets/images/interactions/happyemoji.svg',
                                      width: 20,
                                      height: 20,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!widget.audio.recording &&
                        (widget.selectedMediaTray != null ||
                            state.draft.trim().isNotEmpty))
                      // Sending state lives on each bubble ("Sending…"); the
                      // button never spins and stays usable for the next message.
                      ChatSendButton(
                        // While an attachment uploads, the button sends text.
                        tooltip:
                            widget.selectedMediaTray != null &&
                                !widget.uploading
                            ? 'Send attachments'
                            : 'Send message',
                        onPressed: !widget.canSend
                            ? null
                            : widget.selectedMediaTray != null &&
                                  !widget.uploading
                            ? widget.onSendAttachments
                            : widget.composer.send,
                      )
                    else
                      SizedBox.square(
                        dimension: 48,
                        child: IconButton(
                          tooltip: widget.audio.supported
                              ? 'Record voice message'
                              : 'Voice recording unavailable',
                          style: IconButton.styleFrom(
                            backgroundColor: DarkColors.primaryColor,
                            disabledBackgroundColor: const Color(0xFF803D14),
                          ),
                          onPressed: !widget.canSend || widget.uploading
                              ? null
                              : widget.audio.supported &&
                                    widget.selectedMediaTray == null
                              ? _startRecording
                              : null,
                          icon: const Icon(
                            Icons.mic_none_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              if (_emojiVisible &&
                  widget.canSend &&
                  !_voiceMode &&
                  _keyboardInset(context) == 0)
                ChatEmojiPicker(
                  height: _pickerHeight(context),
                  onSelected: _insertEmoji,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ComposerViewport extends StatelessWidget {
  const _ComposerViewport({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final view = View.of(context), media = MediaQuery.of(context);
    final height = media.size.height > 0
        ? media.size.height
        : view.physicalSize.height / view.devicePixelRatio;
    // Scaffold removes its consumed viewInsets from descendants; retain the
    // actual keyboard inset when bounding the optional draft/error controls.
    final keyboard = media.viewInsets.bottom > 0
        ? media.viewInsets.bottom
        : view.viewInsets.bottom / view.devicePixelRatio;
    final available =
        height -
        keyboard -
        (view.viewPadding.top + view.viewPadding.bottom) /
            view.devicePixelRatio;
    final limit = (available - 96).clamp(0.0, height);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: limit),
      child: SingleChildScrollView(reverse: true, child: child),
    );
  }
}

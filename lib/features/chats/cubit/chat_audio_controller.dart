import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import '../data/chat_models.dart';
import '../data/chat_device_media.dart';

class ChatVoiceDraft {
  const ChatVoiceDraft(this.bytes, this.durationMs);
  final Uint8List bytes;
  final int durationMs;
}

/// One lazy player and recorder per conversation; no background audio service.
/// Paths/URLs, audio bytes and plugin exceptions are never logged.
class ChatAudioController extends ChangeNotifier {
  ChatAudioController({
    AudioRecorder? recorder,
    AudioPlayer? player,
    ChatDeviceMedia? deviceMedia,
    bool? recordingSupported,
  }) : _deviceMedia = deviceMedia ?? const ChatDeviceMedia() {
    _recorder = recorder;
    _player = player;
    _recordingSupported = recordingSupported;
    _session = _preferences.sessionRevision;
    _preferences.addListener(_accountChanged);
  }
  final ChatDeviceMedia _deviceMedia;
  late final bool? _recordingSupported;
  ChatMicrophonePermission? permission;
  bool get needsSettings =>
      permission == ChatMicrophonePermission.permanentlyDenied ||
      permission == ChatMicrophonePermission.restricted;
  Future<void> openSettings() async {
    try {
      await _deviceMedia.openSettings();
    } catch (_) {
      error = 'Unable to open Settings.';
      _notify();
    }
  }

  StreamSubscription<Amplitude>? _amplitude;
  StreamSubscription<RecordState>? _recordState;
  Timer? _ticker;
  bool recordingPaused = false;
  Duration get recordingDuration => _clock.elapsed;
  final List<double> levels = [];
  Directory? _previewDirectory;
  Future<void>? _shutdownJob;
  final _preferences = PreferencesManager();
  late final int _session;
  AudioPlayer? _player;
  AudioRecorder? _recorder;
  StreamSubscription<Duration>? _position;
  StreamSubscription<PlayerState>? _playState;
  StreamSubscription<PlayerException>? _errors;
  Directory? _directory;
  final _clock = Stopwatch();
  bool _closed = false, _busy = false;
  bool _foreground = true;
  int _playbackGeneration = 0, _captureEpoch = 0;
  bool _previewing = false;
  void resume() {
    _foreground = true;
  }

  bool recording = false, playing = false;
  String? currentMessageId, error;
  Duration position = Duration.zero, duration = Duration.zero;
  ChatVoiceDraft? draft;
  final Set<Future<void> Function()> _videoPauses = {};
  void registerVideoPause(Future<void> Function() pause) =>
      _videoPauses.add(pause);
  void unregisterVideoPause(Future<void> Function() pause) =>
      _videoPauses.remove(pause);
  Future<void> pauseVideos() async {
    for (final pause in List.of(_videoPauses)) {
      try {
        await pause().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  bool get supported =>
      _recordingSupported ??
      (!kIsWeb && (Platform.isIOS || Platform.isAndroid));
  bool get _active =>
      !_closed &&
      _preferences.hasSession &&
      _session == _preferences.sessionRevision;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _accountChanged() {
    if (_session != _preferences.sessionRevision) unawaited(_shutdown());
  }

  Future<void> toggle(ChatMessage message) async {
    if (!_active ||
        !_foreground ||
        _busy ||
        recording ||
        message.mediaUrl == null) {
      return;
    }
    final generation = ++_playbackGeneration;
    _busy = true;
    try {
      await pauseVideos();
      if (!_active || !_foreground) return;
      final player = _player ??= AudioPlayer();
      _position ??= player.positionStream.listen((value) {
        if (_active) {
          position = value;
          _notify();
        }
      });
      _playState ??= player.playerStateStream.listen((value) {
        if (_active) {
          playing =
              value.playing &&
              value.processingState != ProcessingState.completed;
          _notify();
        }
      });
      _errors ??= player.errorStream.listen((_) {
        if (_active) {
          error = 'Unable to play this recording.';
          playing = false;
          _notify();
        }
      });
      if (currentMessageId == message.id && playing) {
        await player.pause();
      } else {
        if (currentMessageId != message.id) {
          await player.stop();
          if (!_active || !_foreground) return;
          currentMessageId = message.id;
          position = Duration.zero;
          duration =
              await player.setUrl(message.mediaUrl.toString()) ??
              message.duration ??
              Duration.zero;
        } else if (player.processingState == ProcessingState.completed) {
          await player.seek(Duration.zero);
        }
        if (!_active || !_foreground || generation != _playbackGeneration) {
          await player.stop();
          return;
        }
        error = null;
        unawaited(
          player.play().catchError((Object _) {
            if (_active) {
              error = 'Unable to play this recording.';
              _notify();
            }
          }),
        );
      }
    } catch (_) {
      if (_active) {
        error = 'Unable to play this recording.';
        currentMessageId = null;
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> startRecording() async {
    if (!_active ||
        !_foreground ||
        !supported ||
        _busy ||
        recording ||
        draft != null) {
      return;
    }
    _busy = true;
    final capture = ++_captureEpoch;
    try {
      await pauseVideos();
      await _player?.stop();
      if (!_active || !_foreground || capture != _captureEpoch) return;
      final recorder = _recorder ??= AudioRecorder();
      permission = await _deviceMedia.microphone();
      if (!_active || !_foreground || capture != _captureEpoch) return;
      if (permission == ChatMicrophonePermission.notDetermined ||
          permission == ChatMicrophonePermission.denied) {
        permission = await _deviceMedia.microphone(request: true);
      }
      if (permission != ChatMicrophonePermission.granted) {
        error = needsSettings
            ? 'Allow microphone access in Settings to record a voice message.'
            : 'Microphone access is needed. Tap the microphone to try again.';
        return;
      }
      if (!await recorder.hasPermission(request: false)) {
        error = 'Microphone access is unavailable.';
        return;
      }
      if (!_active || !_foreground || capture != _captureEpoch) return;
      _directory = await Directory.systemTemp.createTemp('travibe_voice_');
      if (!_active || !_foreground || capture != _captureEpoch) return;
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: '${_directory!.path}/recording.m4a',
      );
      if (!_active || !_foreground || capture != _captureEpoch) {
        await recorder.cancel();
        return;
      }
      _clock
        ..reset()
        ..start();
      recording = true;
      recordingPaused = false;
      levels.clear();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (recording && _active) _notify();
      });
      await _amplitude?.cancel();
      _amplitude = recorder
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((sample) {
            if (!_active || !recording || recordingPaused) return;
            levels.add(((sample.current.clamp(-60, 0) + 60) / 60).toDouble());
            if (levels.length > 32) levels.removeAt(0);
            _notify();
          }, onError: (Object _) {});
      await _recordState?.cancel();
      _recordState = recorder.onStateChanged().listen((state) {
        if (!_active || !recording || _busy) return;
        if (state == RecordState.pause) {
          recordingPaused = true;
          _clock.stop();
        }
        if (state == RecordState.record) {
          recordingPaused = false;
          _clock.start();
        }
        if (state == RecordState.stop) unawaited(cancelRecording());
        _notify();
      });
      error = null;
    } catch (_) {
      if (_active) error = 'Unable to start recording. Please try again.';
    } finally {
      if (!recording) await _removeTemporary();
      _busy = false;
      _notify();
    }
  }

  Future<void> stopRecording() async {
    if (!recording || _busy) return;
    _busy = true;
    final capture = _captureEpoch;
    _clock.stop();
    _ticker?.cancel();
    await _amplitude?.cancel();
    recordingPaused = false;
    try {
      final path = await _recorder?.stop();
      recording = false;
      if (path != null && _active && capture == _captureEpoch) {
        final file = File(path);
        final size = await file.length();
        if (size == 0 ||
            size > 20 * 1024 * 1024 ||
            _clock.elapsedMilliseconds < 1 ||
            _clock.elapsedMilliseconds > 86400000) {
          error = 'This recording is too large or too long.';
        } else {
          final bytes = await file.readAsBytes();
          if (_active && capture == _captureEpoch) {
            draft = ChatVoiceDraft(bytes, _clock.elapsedMilliseconds);
          }
        }
      }
    } catch (_) {
      if (_active) error = 'Unable to finish this recording.';
    } finally {
      await _removeTemporary();
      _busy = false;
      _notify();
    }
  }

  Future<void> pauseRecording() async {
    if (!_active || !recording || _busy) return;
    _busy = true;
    try {
      if (recordingPaused) {
        await _recorder?.resume();
        _clock.start();
        recordingPaused = false;
      } else {
        await _recorder?.pause();
        _clock.stop();
        recordingPaused = true;
      }
    } catch (_) {
      error = 'Unable to pause or resume recording.';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> cancelRecording() async {
    ++_captureEpoch;
    _clock.stop();
    _ticker?.cancel();
    recording = false;
    recordingPaused = false;
    await _amplitude?.cancel();
    try {
      await _recorder?.cancel();
    } catch (_) {}
    await _removeTemporary();
    levels.clear();
    _notify();
  }

  Future<void> previewDraft() async {
    final voice = draft;
    if (voice == null || !_active || recording || _previewing) return;
    _previewing = true;
    try {
      _previewDirectory ??= await Directory.systemTemp.createTemp(
        'travibe_voice_preview_',
      );
      if (!_active) return;
      final file = File('${_previewDirectory!.path}/preview.m4a');
      await file.writeAsBytes(voice.bytes, flush: true);
      if (!_active || !identical(voice, draft)) return;
      await toggle(
        ChatMessage(
          id: 'voice-draft',
          senderId: '',
          kind: ChatMessageKind.audio,
          mediaUrl: file.uri,
          duration: Duration(milliseconds: voice.durationMs),
        ),
      );
    } catch (_) {
      if (_active) {
        error = 'Unable to preview recording.';
        _notify();
      }
    } finally {
      _previewing = false;
    }
  }

  void discardDraft() {
    draft = null;
    unawaited(stopPlayback());
    unawaited(_removePreview());
    error = null;
    _notify();
  }

  Future<void> stopPlayback() async {
    _playbackGeneration++;
    try {
      await _player?.stop();
    } catch (_) {}
    currentMessageId = null;
    playing = false;
    position = Duration.zero;
    _notify();
  }

  Future<void> pause() async {
    _playbackGeneration++;
    _foreground = false;
    await pauseVideos();
    try {
      await _player?.pause();
    } catch (_) {}
    if (recording) await stopRecording();
  }

  Future<void> _removeTemporary() async {
    final directory = _directory;
    _directory = null;
    if (directory != null) {
      try {
        await directory.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _removePreview() async {
    final directory = _previewDirectory;
    _previewDirectory = null;
    try {
      await directory?.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> _shutdown() => _shutdownJob ??= _performShutdown();
  Future<void> _performShutdown() async {
    _playbackGeneration++;
    _captureEpoch++;
    draft = null;
    levels.clear();
    error = null;
    currentMessageId = null;
    position = Duration.zero;
    duration = Duration.zero;
    recording = false;
    playing = false;
    _clock.stop();
    _notify();
    _ticker?.cancel();
    await _amplitude?.cancel();
    await _recordState?.cancel();
    recordingPaused = false;
    draft = null;
    recording = false;
    playing = false;
    _clock.stop();
    try {
      await _player?.stop();
    } catch (_) {}
    await pauseVideos();
    await _position?.cancel();
    await _playState?.cancel();
    await _errors?.cancel();
    try {
      await _player?.dispose();
    } catch (_) {}
    try {
      await _recorder?.cancel();
      await _recorder?.dispose();
    } catch (_) {}
    await _removeTemporary();
    await _removePreview();
    _notify();
  }

  @override
  void dispose() {
    _preferences.removeListener(_accountChanged);
    _closed = true;
    unawaited(_shutdown());
    super.dispose();
  }
}

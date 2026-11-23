import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import '../data/chat_models.dart';
import '../data/chat_device_media.dart';
import '../data/chat_voice_waveform.dart';

class ChatVoiceDraft {
  ChatVoiceDraft(this.bytes, this.durationMs, {List<double>? waveform})
    : waveform = waveform ?? chatPlaceholderWaveform(durationMs);
  final Uint8List bytes;
  final int durationMs;

  /// Captured levels (0–1), downsampled for the preview pill.
  final List<double> waveform;
}

/// One lazy player and recorder per conversation; no background audio service.
/// Paths/URLs, audio bytes and plugin exceptions are never logged.
class ChatAudioController extends ChangeNotifier {
  ChatAudioController({
    AudioRecorder? recorder,
    AudioPlayer? player,
    ChatDeviceMedia? deviceMedia,
    bool? recordingSupported,
    Stopwatch? clock,
    this.maxRecording = const Duration(minutes: 5),
    this.minRecording = const Duration(seconds: 1),
    this.resumeTimeout = const Duration(seconds: 3),
  }) : _deviceMedia = deviceMedia ?? const ChatDeviceMedia(),
       _clock = clock ?? Stopwatch() {
    _recorder = recorder;
    _player = player;
    _recordingSupported = recordingSupported;
    _session = _preferences.sessionRevision;
    _preferences.addListener(_accountChanged);
  }
  final ChatDeviceMedia _deviceMedia;
  late final bool? _recordingSupported;

  /// Recording stops itself here and becomes a preview.
  final Duration maxRecording;

  /// Shorter recordings are dropped with a [notice].
  final Duration minRecording;

  /// How long a start waits for the app to return from the system prompt.
  final Duration resumeTimeout;

  /// Id of the draft preview in [currentMessageId].
  static const draftId = 'voice-draft';

  /// One-shot hint for the composer (e.g. a recording that was too short).
  String? notice;
  String? takeNotice() {
    final value = notice;
    notice = null;
    return value;
  }

  ChatMicrophonePermission? permission;

  /// The last [startRecording] showed the system microphone prompt, so a
  /// denial there needs no further explanation until the next tap.
  bool promptedForPermission = false;
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

  /// The latest 32 live levels for the recording pill.
  final List<double> levels = [];
  final List<double> _capture = [];
  String? _outputPath;
  Completer<void>? _resumed;
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
  final Stopwatch _clock;
  bool _closed = false, _busy = false;
  bool _foreground = true;
  int _playbackGeneration = 0, _captureEpoch = 0;
  bool _previewing = false;
  void resume() {
    _foreground = true;
    _resumed?.complete();
    _resumed = null;
  }

  /// The system microphone prompt briefly backgrounds the app; wait for it to
  /// come back so the first recording starts right after granting.
  Future<bool> _awaitForeground() async {
    if (_foreground) return true;
    final resumed = _resumed ??= Completer<void>();
    try {
      await resumed.future.timeout(resumeTimeout);
    } on TimeoutException {
      // Still in the background; do not record.
    }
    return _foreground;
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
      promptedForPermission = false;
      permission = await _deviceMedia.microphone();
      if (!_active || !_foreground || capture != _captureEpoch) return;
      if (permission == ChatMicrophonePermission.notDetermined ||
          permission == ChatMicrophonePermission.denied) {
        promptedForPermission = true;
        permission = await _deviceMedia.microphone(request: true);
        if (permission == ChatMicrophonePermission.granted &&
            !await _awaitForeground()) {
          return;
        }
      }
      if (permission != ChatMicrophonePermission.granted) {
        // Settings-blocked: the composer's single Settings sheet explains it.
        error = needsSettings
            ? null
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
      final output = '${_directory!.path}/recording.m4a';
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: output,
      );
      _outputPath = output;
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
      _capture.clear();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!recording || !_active) return;
        if (_clock.elapsed >= maxRecording) {
          unawaited(stopRecording());
        } else {
          _notify();
        }
      });
      await _amplitude?.cancel();
      _amplitude = recorder
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((sample) {
            if (!_active || !recording || recordingPaused) return;
            final level = ((sample.current.clamp(-60, 0) + 60) / 60).toDouble();
            levels.add(level);
            _capture.add(level);
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
        // The OS stopped the recorder (e.g. a call): keep it as a preview.
        if (state == RecordState.stop) unawaited(stopRecording());
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
      String? path;
      try {
        path = await _recorder?.stop();
      } catch (_) {
        // Already stopped by the OS; the file is still at [_outputPath].
      }
      path ??= _outputPath;
      recording = false;
      final elapsed = _clock.elapsed;
      if (path != null && _active && capture == _captureEpoch) {
        final file = File(path);
        final size = await file.exists() ? await file.length() : 0;
        if (elapsed < minRecording) {
          notice =
              'Voice note too short. Tap the mic and record at least '
              '1 second.';
        } else if (size == 0 || size > 20 * 1024 * 1024) {
          error = 'This recording is too large or too long.';
        } else {
          final bytes = await file.readAsBytes();
          if (_active && capture == _captureEpoch) {
            final ms = elapsed.inMilliseconds;
            draft = ChatVoiceDraft(
              bytes,
              ms,
              waveform: chatDownsampleWaveform(_capture, durationMs: ms),
            );
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
    _capture.clear();
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
          id: draftId,
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

  /// Seeks the loaded message (or draft) to [fraction] of its length.
  Future<void> seek(String messageId, double fraction) async {
    final player = _player;
    if (!_active || player == null || currentMessageId != messageId) return;
    final total = duration.inMilliseconds;
    if (total <= 0) return;
    final target = Duration(
      milliseconds: (total * fraction.clamp(0.0, 1.0)).round(),
    );
    position = target;
    _notify();
    try {
      await player.seek(target);
    } catch (_) {}
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
    _outputPath = null;
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
    _capture.clear();
    notice = null;
    _resumed?.complete();
    _resumed = null;
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

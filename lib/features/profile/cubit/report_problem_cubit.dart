import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/create_post/data/post_image.dart';
import 'package:travibe/features/profile/data/support_repo.dart';

class ReportProblemState {
  const ReportProblemState({
    this.submitting = false,
    this.sent = false,
    this.error,
  });
  final bool submitting, sent;
  final String? error;
}

/// Uploads screenshots (once each, even across retries), then sends the
/// report. Results from a previous session are dropped.
class ReportProblemCubit extends Cubit<ReportProblemState> {
  ReportProblemCubit({SupportRepo? repo})
    : _repo = repo ?? SupportRepo(),
      super(const ReportProblemState());

  final SupportRepo _repo;
  final _preferences = PreferencesManager();
  final _uploaded = <String, int>{};
  CancelToken? _cancel;

  Future<void> submit({
    required String category,
    required String description,
    List<PostImage> screenshots = const [],
  }) async {
    final text = description.trim();
    if (isClosed || state.submitting || state.sent || text.isEmpty) return;
    final session = _preferences.sessionRevision;
    bool current() => !isClosed && session == _preferences.sessionRevision;
    final cancel = _cancel = CancelToken();
    emit(const ReportProblemState(submitting: true));
    try {
      final ids = <int>[];
      for (final image in screenshots) {
        ids.add(
          _uploaded[image.localId] ??= await _repo.uploadScreenshot(
            image,
            isActive: current,
            cancelToken: cancel,
          ),
        );
      }
      if (!current()) return;
      await _repo.reportProblem(
        category: category,
        description: text,
        mediaIds: ids,
      );
      if (!current()) return;
      emit(const ReportProblemState(sent: true));
    } catch (error) {
      if (!current()) return;
      emit(
        ReportProblemState(
          error: error is ApiError
              ? error.message
              : 'Unable to send your report. Please retry.',
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _cancel?.cancel();
    return super.close();
  }
}

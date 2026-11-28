import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/legal/data/legal_page.dart';
import 'package:travibe/features/legal/data/legal_pages_repo.dart';

part 'legal_page_state.dart';

/// Cache first, then the website. One cubit per [slug].
class LegalPageCubit extends Cubit<LegalPageState> {
  LegalPageCubit(this.slug, {LegalPagesRepo? repo})
    : _repo = repo ?? LegalPagesRepo.shared,
      super(const LegalPageLoading());

  final LegalPageSlug slug;
  final LegalPagesRepo _repo;
  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;
    final cached = await _repo.cached(slug);
    if (isClosed || generation != _generation) return;
    if (cached != null) {
      emit(LegalPageLoaded(cached, refreshing: true, failures: state.failures));
    }
    await _fetch(generation);
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    final current = state;
    emit(switch (current) {
      LegalPageLoaded(:final page) => LegalPageLoaded(
        page,
        refreshing: true,
        failures: current.failures,
      ),
      LegalPageUnavailable() => LegalPageUnavailable(
        retrying: true,
        failures: current.failures,
      ),
      LegalPageLoading() => current,
    });
    await _fetch(generation);
  }

  Future<void> _fetch(int generation) async {
    try {
      final page = await _repo.fetch(slug);
      if (isClosed || generation != _generation) return;
      emit(LegalPageLoaded(page, failures: state.failures));
    } catch (_) {
      if (isClosed || generation != _generation) return;
      final failures = state.failures + 1;
      emit(switch (state) {
        LegalPageLoaded(:final page) => LegalPageLoaded(
          page,
          failures: failures,
        ),
        _ => LegalPageUnavailable(failures: failures),
      });
    }
  }
}

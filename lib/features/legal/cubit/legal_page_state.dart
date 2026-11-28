part of 'legal_page_cubit.dart';

@immutable
sealed class LegalPageState {
  const LegalPageState({this.failures = 0});

  /// Failed fetches so far; each increase shows the Refresh toast once.
  final int failures;
}

/// First load with nothing cached.
final class LegalPageLoading extends LegalPageState {
  const LegalPageLoading({super.failures});
}

/// Shows [page]; it may be the cached copy while a fetch is running or after
/// one failed.
final class LegalPageLoaded extends LegalPageState {
  const LegalPageLoaded(this.page, {this.refreshing = false, super.failures});
  final LegalPage page;
  final bool refreshing;
}

/// No connection and no cached copy.
final class LegalPageUnavailable extends LegalPageState {
  const LegalPageUnavailable({this.retrying = false, super.failures});
  final bool retrying;
}

part of 'search_cubit.dart';

enum SearchTab { top, recent, people }

enum SearchStatus { idle, loading, loaded, failure }

@immutable
class SearchState {
  final String query; // trimmed text currently in the field
  final SearchTab tab;
  final SearchStatus status;
  final String errorMessage;
  final List<String> recentSearches;
  final List<PublicUserModel> people;
  final bool hasMorePeople;
  final bool isLoadingMore;
  final String paginationError;

  const SearchState({
    this.query = '',
    this.tab = SearchTab.people,
    this.status = SearchStatus.idle,
    this.errorMessage = '',
    this.recentSearches = const [],
    this.people = const [],
    this.hasMorePeople = false,
    this.isLoadingMore = false,
    this.paginationError = '',
  });

  /// What we actually send to the API: the query without a leading "@".
  String get searchTerm =>
      query.startsWith('@') ? query.substring(1).trim() : query;

  bool get hasInput => query.isNotEmpty;

  /// The API requires at least 3 characters.
  bool get isTooShort => hasInput && searchTerm.runes.length < 3;
  bool get isTooLong => searchTerm.runes.length > 100;
  bool get canSearch => hasInput && !isTooShort && !isTooLong;

  SearchState copyWith({
    String? query,
    SearchTab? tab,
    SearchStatus? status,
    String? errorMessage,
    List<String>? recentSearches,
    List<PublicUserModel>? people,
    bool? hasMorePeople,
    bool? isLoadingMore,
    String? paginationError,
  }) {
    return SearchState(
      query: query ?? this.query,
      tab: tab ?? this.tab,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      recentSearches: recentSearches ?? this.recentSearches,
      people: people ?? this.people,
      hasMorePeople: hasMorePeople ?? this.hasMorePeople,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      paginationError: paginationError ?? this.paginationError,
    );
  }
}

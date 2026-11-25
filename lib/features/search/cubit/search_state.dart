part of 'search_cubit.dart';

/// Posts first: the default for plain queries; "@..." switches to People.
enum SearchTab { posts, people }

enum SearchStatus { idle, loading, loaded, failure }

@immutable
class SearchState {
  final String query; // trimmed text currently in the field
  final SearchTab tab;
  final SearchStatus status;
  final String errorMessage;
  final List<RecentSearch> recentSearches;
  final List<PublicUserModel> people;
  final bool hasMorePeople;
  final bool isLoadingMore;
  final String paginationError;

  // Posts tab (GET /search/posts); loaded lazily when the tab is shown.
  final SearchStatus postsStatus;
  final String postsError;
  final List<PostModel> posts;
  final bool hasMorePosts;
  final bool isLoadingMorePosts;
  final String postsPaginationError;

  const SearchState({
    this.query = '',
    this.tab = SearchTab.posts,
    this.status = SearchStatus.idle,
    this.errorMessage = '',
    this.recentSearches = const [],
    this.people = const [],
    this.hasMorePeople = false,
    this.isLoadingMore = false,
    this.paginationError = '',
    this.postsStatus = SearchStatus.idle,
    this.postsError = '',
    this.posts = const [],
    this.hasMorePosts = false,
    this.isLoadingMorePosts = false,
    this.postsPaginationError = '',
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
    List<RecentSearch>? recentSearches,
    List<PublicUserModel>? people,
    bool? hasMorePeople,
    bool? isLoadingMore,
    String? paginationError,
    SearchStatus? postsStatus,
    String? postsError,
    List<PostModel>? posts,
    bool? hasMorePosts,
    bool? isLoadingMorePosts,
    String? postsPaginationError,
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
      postsStatus: postsStatus ?? this.postsStatus,
      postsError: postsError ?? this.postsError,
      posts: posts ?? this.posts,
      hasMorePosts: hasMorePosts ?? this.hasMorePosts,
      isLoadingMorePosts: isLoadingMorePosts ?? this.isLoadingMorePosts,
      postsPaginationError: postsPaginationError ?? this.postsPaginationError,
    );
  }
}

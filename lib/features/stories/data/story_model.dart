import 'package:travibe/features/stories/data/story_editor_draft.dart';
import 'package:travibe/features/stories/data/story_elements.dart';

int storyId(dynamic value) {
  if (value is! int || value < 1) {
    throw const FormatException('Invalid Story ID');
  }
  return value;
}

Map storyObject(dynamic value) {
  if (value is! Map) throw const FormatException('Invalid Story object');
  return value;
}

String? storyString(dynamic value) {
  if (value != null && value is! String) {
    throw const FormatException('Invalid Story string');
  }
  return value as String?;
}

DateTime? storyDate(dynamic value) {
  if (value == null) return null;
  if (value is! String || DateTime.tryParse(value) == null) {
    throw const FormatException('Invalid Story timestamp');
  }
  return DateTime.parse(value);
}

bool _bool(dynamic value) {
  if (value is! bool) throw const FormatException('Invalid Story flag');
  return value;
}

int _count(dynamic value) {
  if (value is! int || value < 0) {
    throw const FormatException('Invalid Story count');
  }
  return value;
}

class StoryAuthor {
  const StoryAuthor({required this.id, required this.name, this.avatarUrl});
  final int id;
  final String name;
  final String? avatarUrl;
  factory StoryAuthor.fromJson(dynamic json) {
    final map = storyObject(json);
    if (map['name'] is! String) {
      throw const FormatException('Invalid Story author');
    }
    return StoryAuthor(
      id: storyId(map['id']),
      name: map['name'],
      avatarUrl: storyString(map['avatar_url']),
    );
  }
}

class StorySummary {
  StorySummary.fromJson(dynamic json) {
    final map = storyObject(json);
    id = storyId(map['id']);
    thumbnailUrl = storyString(map['thumbnail_url']);
    createdAt = storyDate(map['created_at']);
    expiresAt = storyDate(map['expires_at']);
    viewsCount = _count(map['views_count']);
    hasSeen = _bool(map['has_seen']);
  }
  StorySummary.viewed(StorySummary previous, int count)
    : id = previous.id,
      thumbnailUrl = previous.thumbnailUrl,
      createdAt = previous.createdAt,
      expiresAt = previous.expiresAt,
      viewsCount = count,
      hasSeen = true;
  late final int id;
  late final String? thumbnailUrl;
  late final DateTime? createdAt, expiresAt;
  late final int viewsCount;
  late final bool hasSeen;
}

class StoryGroup {
  StoryGroup.fromJson(dynamic json) {
    final map = storyObject(json);
    user = StoryAuthor.fromJson(map['user']);
    hasUnseen = _bool(map['has_unseen']);
    if (map['stories'] is! List) {
      throw const FormatException('Invalid Story list');
    }
    stories = List.unmodifiable(
      (map['stories'] as List).map(StorySummary.fromJson),
    );
  }
  StoryGroup._(this.user, this.hasUnseen, this.stories);
  StoryGroup reconcile(Map<int, int> seen, Set<int> deleted) {
    if (!stories.any((s) => seen.containsKey(s.id) || deleted.contains(s.id))) {
      return this;
    }
    final items = [
      for (final item in stories)
        if (!deleted.contains(item.id))
          seen.containsKey(item.id)
              ? StorySummary.viewed(item, seen[item.id]!)
              : item,
    ];
    return StoryGroup._(
      user,
      items.any((s) => !s.hasSeen),
      List.unmodifiable(items),
    );
  }

  StoryGroup merge(StoryGroup previous) {
    final merged = {for (final story in previous.stories) story.id: story};
    for (final story in stories) {
      merged[story.id] = story;
    }
    return StoryGroup._(
      user,
      hasUnseen || previous.hasUnseen,
      List.unmodifiable(merged.values),
    );
  }

  late final StoryAuthor user;
  late final bool hasUnseen;
  late final List<StorySummary> stories;
}

class StoriesPage {
  StoriesPage.fromJson(dynamic json) {
    final map = storyObject(json);
    if (map['data'] is! List) {
      throw const FormatException('Invalid Stories collection');
    }
    groups = List.unmodifiable((map['data'] as List).map(StoryGroup.fromJson));
    final meta = storyObject(map['meta']);
    page = storyId(meta['current_page']);
    lastPage = storyId(meta['last_page']);
    perPage = storyId(meta['per_page']);
    total = _count(meta['total']);
    if (page > lastPage) {
      throw const FormatException('Invalid Stories pagination');
    }
    final links = storyObject(map['links']);
    for (final field in ['first', 'last', 'next', 'prev']) {
      storyString(links[field]);
    }
  }
  late final List<StoryGroup> groups;
  late final int page, lastPage, perPage, total;
  bool get hasMore => page < lastPage;
}

class StoryMedia {
  StoryMedia.fromJson(dynamic json) {
    final map = storyObject(json);
    id = storyId(map['id']);
    url = storyString(map['url']);
    thumbnailUrl = storyString(map['thumbnail_url']);
  }
  late final int id;
  late final String? url, thumbnailUrl;
}

class StoryDetail {
  StoryDetail.fromJson(dynamic json) {
    final map = storyObject(json);
    id = storyId(map['id']);
    userId = storyId(map['user_id']);
    user = StoryAuthor.fromJson(map['user']);
    if (user.id != userId) throw const FormatException('Invalid Story owner');
    if (map['visibility'] != 'public' && map['visibility'] != 'followers') {
      throw const FormatException('Invalid Story visibility');
    }
    visibility = map['visibility'];
    locationName = storyString(map['location_name']);
    if (map['media'] is! List ||
        (map['media'] as List).length != 1 ||
        map['elements'] is! List ||
        (map['elements'] as List).length > 50) {
      throw const FormatException('Invalid Story content');
    }
    media = StoryMedia.fromJson((map['media'] as List).single);
    // Preserve arbitrary server elements. Only our v1 text codec interprets them.
    elements = List.unmodifiable(map['elements'] as List);
    mentions = StoryMention.listFrom(map['mentions']);
    viewsCount = _count(map['views_count']);
    likesCount = _count(map['likes_count']);
    isLiked = _bool(map['is_liked']);
    isMine = _bool(map['is_mine']);
    hasSeen = _bool(map['has_seen']);
    createdAt = storyDate(map['created_at']);
    expiresAt = storyDate(map['expires_at']);
  }
  late final int id, userId, viewsCount, likesCount;
  late final StoryAuthor user;
  late final StoryMedia media;
  late final String visibility;
  late final String? locationName;
  late final List<dynamic> elements;

  /// Server-resolved mentions; blocked or unknown handles are omitted.
  late final List<StoryMention> mentions;

  /// The user a `@handle` sticker links to, matched case-insensitively.
  int? mentionedUserId(String username) {
    final handle = username.toLowerCase();
    for (final mention in mentions) {
      if (mention.handle == handle) return mention.userId;
    }
    return null;
  }

  late final bool isLiked, isMine, hasSeen;
  late final DateTime? createdAt, expiresAt;
}

class StoryMention {
  const StoryMention({required this.handle, required this.userId});
  final String handle;
  final int userId;

  /// Optional field: malformed entries are dropped rather than failing a Story.
  static List<StoryMention> listFrom(dynamic json) {
    if (json is! List) return const [];
    return List.unmodifiable([
      for (final item in json)
        if (item is Map &&
            item['handle'] is String &&
            item['user'] is Map &&
            item['user']['id'] is int &&
            (item['user']['id'] as int) > 0)
          StoryMention(
            handle: (item['handle'] as String).toLowerCase(),
            userId: item['user']['id'] as int,
          ),
    ]);
  }
}

class CreateStoryRequest {
  CreateStoryRequest({required this.mediaId, required this.draft});
  final int mediaId;
  final StoryEditorDraft draft;
  Map<String, dynamic> toJson() {
    storyId(mediaId);
    return {
      'media_ids': [mediaId],
      'visibility': draft.audience.visibility,
      'location_name': null,
      'elements': StoryElements.encode(draft.layers),
    };
  }
}

class StoryViewerUser {
  StoryViewerUser.fromJson(dynamic json) {
    final map = storyObject(json);
    author = StoryAuthor.fromJson(map);
    username = storyString(map['username']);
    countryCode = storyString(map['country_code']);
    viewedAt = storyDate(map['viewed_at']);
    if (viewedAt == null) {
      throw const FormatException('Missing viewer timestamp');
    }
    isFollowing = _bool(map['is_following']);
    followsYou = _bool(map['follows_you']);
    followRequested = map['follow_requested'] == true;
    hasLiked = _bool(map['has_liked']);
  }
  late final StoryAuthor author;
  late final String? username, countryCode;
  late final DateTime? viewedAt;
  late final bool isFollowing, followsYou, followRequested, hasLiked;
}

class StoryViewersPage {
  StoryViewersPage.fromJson(dynamic json) {
    final map = storyObject(json);
    if (map['data'] is! List) throw const FormatException('Invalid viewers');
    users = List.unmodifiable(
      (map['data'] as List).map(StoryViewerUser.fromJson),
    );
    final meta = storyObject(map['meta']);
    page = storyId(meta['current_page']);
    lastPage = storyId(meta['last_page']);
    perPage = storyId(meta['per_page']);
    total = _count(meta['total']);
    if (page > lastPage) {
      throw const FormatException('Invalid pagination');
    }
    final links = storyObject(map['links']);
    for (final key in ['first', 'last', 'next', 'prev']) {
      storyString(links[key]);
    }
  }
  late final List<StoryViewerUser> users;
  late final int page, lastPage, perPage, total;
  bool get hasMore => page < lastPage;
}

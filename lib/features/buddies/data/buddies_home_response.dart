/// Strict parsing of the verified GET /buddies home contract.
Map<String, dynamic> _object(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected object');
  }
  return value;
}

T _required<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! T) throw FormatException('Invalid $key');
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value != null && value is! String) throw FormatException('Invalid $key');
  return value as String?;
}

class BuddyInterest {
  BuddyInterest.fromJson(Map<String, dynamic> json)
    : slug = _required<String>(json, 'slug'),
      name = _required<String>(json, 'name');
  final String slug;
  final String name;
}

class BuddyTripResource {
  BuddyTripResource.fromJson(Map<String, dynamic> json)
    : destinationCity = _required<String>(json, 'destination_city'),
      destinationCountryCode = _required<String>(
        json,
        'destination_country_code',
      ),
      startsOn = _required<String>(json, 'starts_on'),
      endsOn = _nullableString(json, 'ends_on');
  final String destinationCity;
  final String destinationCountryCode;
  final String startsOn;
  final String? endsOn;
}

class BuddyResource {
  BuddyResource.fromJson(Map<String, dynamic> json)
    : id = _required<int>(json, 'id'),
      name = _required<String>(json, 'name'),
      username = _nullableString(json, 'username'),
      avatarUrl = _nullableString(json, 'avatar_url'),
      city = _nullableString(json, 'city'),
      countryCode = _nullableString(json, 'country_code'),
      sharedInterestsCount = _required<int>(json, 'shared_interests_count'),
      isFollowing = _required<bool>(json, 'is_following'),
      interests = List.unmodifiable(
        (json['interests'] != null ? _required<List>(json, 'interests') : [])
            .map((item) => BuddyInterest.fromJson(_object(item))),
      ),
      trip = json['trip'] == null
          ? null
          : BuddyTripResource.fromJson(_object(json['trip'])) {
    if (id < 1 || sharedInterestsCount < 0) {
      throw const FormatException('Invalid buddy counts or ID');
    }
  }
  final int id;
  final String name;
  final String? username, avatarUrl, city, countryCode;
  final int sharedInterestsCount;
  final bool isFollowing;
  final List<BuddyInterest> interests;
  final BuddyTripResource? trip;
}

class BuddyCity {
  BuddyCity.fromJson(Map<String, dynamic> json)
    : city = _required<String>(json, 'city'),
      countryCode = _nullableString(json, 'country_code');
  final String city;
  final String? countryCode;
}

class BuddiesHomeMeta {
  BuddiesHomeMeta._({
    required this.profileCompleted,
    required this.showInTravelBuddy,
    required this.hasCurrentCity,
    required this.currentCity,
  });
  BuddiesHomeMeta withVisibility(bool value) => BuddiesHomeMeta._(
    profileCompleted: profileCompleted,
    showInTravelBuddy: value,
    hasCurrentCity: hasCurrentCity,
    currentCity: currentCity,
  );
  BuddiesHomeMeta withLocation(String? location) {
    final parts = location?.split(',');
    final code = parts?.last.trim();
    final city = parts != null && parts.length >= 2
        ? parts.take(parts.length - 1).join(',').trim()
        : null;
    final usable =
        city != null &&
        city.isNotEmpty &&
        code != null &&
        RegExp(r'^[A-Z]{2}$').hasMatch(code);
    return BuddiesHomeMeta._(
      profileCompleted: profileCompleted,
      showInTravelBuddy: showInTravelBuddy,
      hasCurrentCity: usable,
      currentCity: usable
          ? BuddyCity.fromJson({'city': city, 'country_code': code})
          : null,
    );
  }

  BuddiesHomeMeta.fromJson(Map<String, dynamic> json)
    : profileCompleted = _required<bool>(json, 'profile_completed'),
      showInTravelBuddy = _required<bool>(json, 'show_in_travel_buddy'),
      hasCurrentCity = _required<bool>(json, 'has_current_city'),
      currentCity = json['current_city'] == null
          ? null
          : BuddyCity.fromJson(_object(json['current_city']));
  final bool profileCompleted, showInTravelBuddy, hasCurrentCity;
  final BuddyCity? currentCity;
}

class BuddiesHomeResponse {
  BuddiesHomeResponse._({
    required this.inYourCity,
    required this.withSameInterests,
    required this.meta,
  });
  BuddiesHomeResponse withVisibility(bool? value) => value == null
      ? this
      : BuddiesHomeResponse._(
          inYourCity: inYourCity,
          withSameInterests: withSameInterests,
          meta: meta.withVisibility(value),
        );
  BuddiesHomeResponse withLocation(
    String? location, {
    bool invalidateCity = false,
  }) => BuddiesHomeResponse._(
    inYourCity: invalidateCity ? const [] : inYourCity,
    withSameInterests: withSameInterests,
    meta: meta.withLocation(location),
  );

  BuddiesHomeResponse.fromJson(Map<String, dynamic> json)
    : inYourCity = _buddies(_object(json['data']), 'in_your_city'),
      withSameInterests = _buddies(
        _object(json['data']),
        'with_same_interests',
      ),
      meta = BuddiesHomeMeta.fromJson(_object(json['meta']));
  final List<BuddyResource> inYourCity, withSameInterests;
  final BuddiesHomeMeta meta;

  static List<BuddyResource> _buddies(Map<String, dynamic> json, String key) {
    final items = _required<List>(
      json,
      key,
    ).map((item) => BuddyResource.fromJson(_object(item)));
    return List.unmodifiable({for (final item in items) item.id: item}.values);
  }
}

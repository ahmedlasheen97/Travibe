/// Story-specific choices with verified backend visibility values.
enum StoryAudience {
  public,
  followers;

  String get label => switch (this) {
    public => 'Public',
    followers => 'Followers',
  };

  String get description => switch (this) {
    public => 'Anyone can see your story.',
    followers => 'Only people who follow you can see your story.',
  };

  String get visibility => switch (this) {
    public => 'public',
    followers => 'followers',
  };
}

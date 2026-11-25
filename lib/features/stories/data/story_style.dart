/// Shape of Home's stories row (Settings → Story Style). Profile pictures and
/// the story viewer stay circular whatever this is set to.
enum StoryStyle {
  circle,
  rectangle;

  /// App default for new installs and anyone who hasn't chosen.
  static const fallback = StoryStyle.circle;

  String get label => switch (this) {
    StoryStyle.circle => 'Circle',
    StoryStyle.rectangle => 'Rectangle',
  };

  static StoryStyle parse(String? value) => StoryStyle.values.firstWhere(
    (style) => style.name == value,
    orElse: () => fallback,
  );
}

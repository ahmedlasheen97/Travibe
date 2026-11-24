/// Shape of Home's stories row (experiment). Profile pictures and the story
/// viewer stay circular whatever this is set to.
enum StoryStyle {
  circle,
  rectangle;

  static StoryStyle parse(String? value) => StoryStyle.values.firstWhere(
    (style) => style.name == value,
    orElse: () => StoryStyle.circle,
  );
}

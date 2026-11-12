import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/utils/formatters.dart';

void main() {
  test('only exactly one is singular', () {
    expect(countLabel(0, 'Like'), '0 Likes');
    expect(countLabel(1, 'Like'), '1 Like');
    expect(countLabel(2, 'Like'), '2 Likes');
    expect(countLabel(1, 'comment'), '1 comment');
    expect(countLabel(5, 'comment'), '5 comments');
    expect(countLabel(1, 'reply', 'replies'), '1 reply');
    expect(countLabel(3, 'reply', 'replies'), '3 replies');
  });

  test('formats large counts and accepts pre-formatted text', () {
    expect(countLabel(1200, 'Like'), '1.2K Likes');
    expect(countLabel(1000, 'Like'), '1K Likes');
    expect(countLabel('1', 'Like'), '1 Like');
    expect(countLabel('1.2K', 'Like'), '1.2K Likes');
  });
}

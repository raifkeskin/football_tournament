import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/core/widgets/youtube_player_page.dart';

void main() {
  test('youtubeVideoId supports watch, live, short and schemaless URLs', () {
    const id = 'dQw4w9WgXcQ';

    expect(youtubeVideoId('https://www.youtube.com/watch?v=$id'), id);
    expect(youtubeVideoId('https://youtube.com/live/$id?feature=share'), id);
    expect(youtubeVideoId('https://youtu.be/$id?si=abc'), id);
    expect(youtubeVideoId('www.youtube.com/embed/$id'), id);
  });

  test('youtubeVideoId rejects channel pages without a video id', () {
    expect(youtubeVideoId('https://www.youtube.com/@channel/live'), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:spotmeta_downloader/models/track_metadata.dart';
import 'package:spotmeta_downloader/services/romaji_service.dart';

void main() {
  group('RomajiService Line-by-Line Timestamp & Kanji-to-Romaji Tests', () {
    test('parseLyricLine isolates timestampPrefix and lyricContent accurately', () {
      final line1 = RomajiService.parseLyricLine(
        '[00:20.15] 誰も教えてくれなかった 歪んだルール',
      );
      expect(line1.timestampPrefix, '[00:20.15]');
      expect(line1.lyricContent, '誰も教えてくれなかった 歪んだルール');
      expect(line1.hasTimestamp, isTrue);
      expect(line1.hasLyricContent, isTrue);

      final tsOnly = RomajiService.parseLyricLine('[00:00.00]');
      expect(tsOnly.timestampPrefix, '[00:00.00]');
      expect(tsOnly.lyricContent, '');
      expect(tsOnly.hasTimestamp, isTrue);
      expect(tsOnly.hasLyricContent, isFalse);

      final multiTs = RomajiService.parseLyricLine(
        '[01:10.05][02:30.10] 幼い頃に強く願った',
      );
      expect(multiTs.timestampPrefix, '[01:10.05][02:30.10]');
      expect(multiTs.lyricContent, '幼い頃に強く願った');

      final plain = RomajiService.parseLyricLine('夢のありかを探す旅は始まったばかり');
      expect(plain.timestampPrefix, '');
      expect(plain.lyricContent, '夢のありかを探す旅は始まったばかり');
      expect(plain.hasTimestamp, isFalse);
      expect(plain.hasLyricContent, isTrue);
    });

    test(
        'romanizeLyrics preserves all [mm:ss.xx] timestamps, line count, English in parens, and converts all Kanji',
        () async {
      final service = RomajiService();
      const rawLrc = '''[00:00.00]
[00:13.20] 海へ今すぐ飛び込め (Go to the outside of daydream)
[00:16.50] (Break your limits)
[00:19.10] 叶えたい弱い自分に宿したプライド
[00:25.40] 孤独の波に飲み込まれても変わらない願い
[01:29.30] 運命に抗ってゆけ Pride on myself, ah
[01:38.00] 誰も教えてくれなかった 歪んだルール
[01:44.20] 幼い頃に強く願った
[01:50.60] 夢のありかを探す旅は始まったばかり''';

      final romanized = await service.romanizeLyrics(rawLrc);
      final inputLines = rawLrc.split('\n');
      final outputLines = romanized.split('\n');

      // 1. Exact line count preserved
      expect(outputLines.length, equals(inputLines.length));

      // 2. Timestamp-only line preserved as-is
      expect(outputLines[0], equals('[00:00.00]'));

      // 3. Every timestamp prefix preserved at exact line index
      expect(outputLines[1], startsWith('[00:13.20] '));
      expect(outputLines[2], equals('[00:16.50] (Break your limits)'));
      expect(outputLines[3], startsWith('[00:19.10] '));
      expect(outputLines[4], startsWith('[00:25.40] '));
      expect(outputLines[5], startsWith('[01:29.30] '));
      expect(outputLines[6], startsWith('[01:38.00] '));
      expect(outputLines[7], startsWith('[01:44.20] '));
      expect(outputLines[8], startsWith('[01:50.60] '));

      // 4. English parenthetical phrases preserved without katakana distortion
      expect(outputLines[1], contains('(Go to the outside of daydream)'));
      expect(outputLines[2], contains('(Break your limits)'));
      expect(outputLines[5], contains('Pride on myself, ah'));

      // 5. Zero leaked Kanji or Kana in output
      expect(RomajiService.containsJapanese(romanized), isFalse);
    });

    test(
        'romanizeTrackLyrics synchronizes syncedLyrics and derives plainLyrics without timestamps',
        () async {
      final service = RomajiService();
      const synced = '''[00:13.20] 海へ今すぐ飛び込め (Go to the outside of daydream)
[00:16.50] (Break your limits)
[01:38.00] 誰も教えてくれなかった 歪んだルール''';

      const track = TrackMetadata(
        spotifyUrl: 'https://open.spotify.com/track/test',
        title: 'Resister',
        artist: 'ASCA',
        album: 'Resister - EP',
        releaseYear: '2019',
        durationSeconds: 227,
        coverUrl: '',
        syncedLyrics: synced,
        plainLyrics: '海へ今すぐ飛び込め\n誰も教えてくれなかった',
      );

      final updated = await service.romanizeTrackLyrics(track);

      expect(updated.syncedLyrics, isNotNull);
      expect(updated.plainLyrics, isNotNull);
      expect(RomajiService.containsJapanese(updated.syncedLyrics!), isFalse);
      expect(RomajiService.containsJapanese(updated.plainLyrics!), isFalse);

      // Synced has timestamps, Plain has no timestamps
      expect(updated.syncedLyrics!, contains('[00:13.20]'));
      expect(updated.syncedLyrics!, contains('[01:38.00]'));
      expect(updated.plainLyrics!, isNot(contains('[00:13.20]')));
      expect(updated.plainLyrics!, isNot(contains('[01:38.00]')));
      expect(updated.plainLyrics!.split('\n').length, equals(3));
    });
  });
}

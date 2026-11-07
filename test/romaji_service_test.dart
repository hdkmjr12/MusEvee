import 'package:flutter_test/flutter_test.dart';
import 'package:spotmeta_downloader/models/track_metadata.dart';
import 'package:spotmeta_downloader/services/lyrics_service.dart';
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
        'normalizeForComparison unifies macron vowels, long vowels, punctuation, and spacing',
        () {
      final normA = RomajiService.normalizeForComparison(
        'Kimi wa kanpekide kyūkyoku no aidoru',
      );
      final normB = RomajiService.normalizeForComparison(
        'Kimi wa kanpeki de kyuukyoku no aidoru!',
      );
      expect(normA, equals(normB));
      expect(RomajiService.similarityRatio(normA, normB), equals(1.0));
    });

    test(
        'romanizeLyrics deduplicates bilingual Kanji + Romaji lines so each timestamp has only 1 clean Romaji line',
        () async {
      final service = RomajiService();
      const bilingualLrc = '''[00:01.00] 無敵の笑顔で荒らすメディア
[00:01.00] Muteki no egao de arasu media
[00:15.20] 君は完璧で究極のアイドル
[00:15.50] Kimi wa kanpeki de kyuukyoku no aidoru''';

      final romanized = await service.romanizeLyrics(bilingualLrc);
      final lines = romanized.split('\n');

      // Duplicate Romaji lines must be collapsed from 4 lines down to 2 lines
      expect(lines.length, equals(2));
      expect(lines[0], startsWith('[00:01.00] '));
      expect(lines[1], startsWith('[00:15.20] '));
      expect(RomajiService.containsJapanese(romanized), isFalse);
      // Should keep the cleaner spaced version ("kanpeki de")
      expect(lines[1].toLowerCase(), contains('kanpeki de'));
    });

    test(
        'LyricsService classifies language tags accurately and prioritizes original Japanese/Romaji over English version for YOASOBI - Idol',
        () async {
      expect(
        LyricsService.classifyLyricsLanguage(
          '[00:01.00] 無敵の笑顔で荒らすメディア\n[00:03.00] 知りたいその秘密ミステリアス',
        ),
        equals('[Jepang/Kanji]'),
      );
      expect(
        LyricsService.classifyLyricsLanguage(
          '[00:01.00] Muteki no egao de arasu media\n[00:03.00] Shiritai sono himitsu misuteriasu',
        ),
        equals('[Romaji]'),
      );
      expect(
        LyricsService.classifyLyricsLanguage(
          "[00:00.51] Couldn't beat her smile, it Readily garnished all the media",
        ),
        equals('[Inggris/Lainnya]'),
      );

      final lyricsService = LyricsService();
      final response = await lyricsService.fetchLyricsWithCandidates(
        trackName: 'Idol',
        artistName: 'YOASOBI',
        albumName: 'Idol - Single',
        durationSeconds: 213,
      );

      expect(response.candidates, isNotEmpty);
      expect(response.selectedCandidate, isNotNull);
      // Must NOT pick English translation as bestResult when Japanese/Romaji exists
      expect(
        response.selectedCandidate!.languageTag,
        isNot(equals('[Inggris/Lainnya]')),
      );
      expect(
        RomajiService.containsJapanese(
          response.bestResult.syncedLyrics ?? '',
        ),
        isTrue,
      );
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

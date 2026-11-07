import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotmeta_downloader/models/local_song.dart';
import 'package:spotmeta_downloader/models/track_metadata.dart';
import 'package:spotmeta_downloader/services/lyrics_service.dart';
import 'package:spotmeta_downloader/services/romaji_service.dart';

void main() {
  group('RomajiService, LyricsService & LocalSong Tests', () {
    test('parseLyricLine isolates timestampPrefix and lyricContent accurately',
        () {
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

      expect(outputLines.length, equals(inputLines.length));
      expect(outputLines[0], equals('[00:00.00]'));
      expect(outputLines[1], startsWith('[00:13.20] '));
      expect(outputLines[2], equals('[00:16.50] (Break your limits)'));
      expect(outputLines[3], startsWith('[00:19.10] '));
      expect(outputLines[4], startsWith('[00:25.40] '));
      expect(outputLines[5], startsWith('[01:29.30] '));
      expect(outputLines[6], startsWith('[01:38.00] '));
      expect(outputLines[7], startsWith('[01:44.20] '));
      expect(outputLines[8], startsWith('[01:50.60] '));

      expect(outputLines[1], contains('(Go to the outside of daydream)'));
      expect(outputLines[2], contains('(Break your limits)'));
      expect(outputLines[5], contains('Pride on myself, ah'));
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
        'romanizeLyrics & deduplicateRomajiLyrics eliminate double Romaji and inline furigana',
        () async {
      final service = RomajiService();
      const bilingualLrc = '''[00:01.00] 無敵(むてき)の笑顔で荒らすメディア
[00:01.00] Muteki no egao de arasu media
[00:15.20] 君は完璧で究極のアイドル
[00:15.50] Kimi wa kanpeki de kyūkyoku no aidoru''';

      final romanized = await service.romanizeLyrics(bilingualLrc);
      final lines = romanized.split('\n');

      expect(lines.length, equals(2));
      expect(lines[0], startsWith('[00:01.00] '));
      expect(lines[1], startsWith('[00:15.20] '));
      expect(RomajiService.containsJapanese(romanized), isFalse);
      expect(lines[1].toLowerCase(), contains('kanpeki de'));

      // Also test already-converted duplicate Romaji lines
      const alreadyDoubleRomaji = '''[00:01.00] Muteki no egao de arasu media
[00:01.00] Mutekino egaode arasu media!''';
      final deduped = RomajiService.deduplicateRomajiLyrics(alreadyDoubleRomaji);
      expect(deduped.split('\n').length, equals(1));
    });

    test(
        'LyricsService classifies language tags accurately and prioritizes Japanese/Romaji over English version',
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
          "[00:00.51] Couldn't beat her smile, it readily garnished all the media",
        ),
        equals('[Inggris/Lainnya]'),
      );

      // Mock Dio returning both English translation and Original Japanese candidates
      final mockDio = Dio();
      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.contains('/api/get')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'id': 101,
                    'trackName': 'Idol',
                    'artistName': 'YOASOBI',
                    'albumName': 'Idol',
                    'duration': 213,
                    'syncedLyrics':
                        "[00:01.00] Couldn't beat her smile, it garnished all the media\n[00:04.00] You are my savior, my true savior",
                  },
                ),
              );
              return;
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: [
                  {
                    'id': 101,
                    'trackName': 'Idol',
                    'artistName': 'YOASOBI',
                    'albumName': 'Idol',
                    'duration': 213,
                    'syncedLyrics':
                        "[00:01.00] Couldn't beat her smile, it garnished all the media\n[00:04.00] You are my savior, my true savior",
                  },
                  {
                    'id': 202,
                    'trackName': 'アイドル',
                    'artistName': 'YOASOBI',
                    'albumName': 'アイドル',
                    'duration': 213,
                    'syncedLyrics':
                        '[00:01.00] 無敵の笑顔で荒らすメディア\n[00:04.00] 知りたいその秘密ミステリアス',
                  },
                  {
                    'id': 303,
                    'trackName': 'Idol (Romaji)',
                    'artistName': 'YOASOBI',
                    'albumName': 'Idol',
                    'duration': 213,
                    'syncedLyrics':
                        '[00:01.00] Muteki no egao de arasu media\n[00:04.00] Kimi wa kanpeki de kyuukyoku no aidoru',
                  },
                ],
              ),
            );
          },
        ),
      );

      final lyricsService = LyricsService(dio: mockDio);
      final response = await lyricsService.fetchLyricsWithCandidates(
        trackName: 'Idol',
        artistName: 'YOASOBI',
        albumName: 'Idol - Single',
        durationSeconds: 213,
      );

      expect(response.candidates.length, greaterThanOrEqualTo(3));
      expect(response.selectedCandidate, isNotNull);
      // Japanese Kanji must rank #1, Romaji #2, and English translation last!
      expect(response.selectedCandidate!.languageTag, equals('[Jepang/Kanji]'));
      expect(response.candidates.last.languageTag, equals('[Inggris/Lainnya]'));
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
      expect(updated.syncedLyrics!, contains('[00:13.20]'));
      expect(updated.plainLyrics!, isNot(contains('[00:13.20]')));
    });

    test('LocalSong parses USLT synced LRC timestamps accurately', () {
      const song = LocalSong(
        filePath: '/storage/emulated/0/Music/Music Japan/YOASOBI - Idol.mp3',
        fileName: 'YOASOBI - Idol.mp3',
        folderName: 'Music Japan',
        title: 'Idol',
        artist: 'YOASOBI',
        album: 'THE BOOK 3',
        year: '2023',
        durationMs: 213000,
        sizeBytes: 8400000,
        bitrateKbps: 320,
        sampleRateHz: 44100,
        usltLyrics:
            '[ti:Idol]\r\n[00:01.20] Muteki no egao de arasu media\r\n[00:15.50] Kimi wa kanpeki de kyuukyoku no aidoru',
      );

      expect(song.hasLyrics, isTrue);
      expect(song.hasSyncedLyrics, isTrue);
      expect(song.parsedSyncedLyrics.length, equals(2));
      expect(song.parsedSyncedLyrics[0].timeMs, equals(1200));
      expect(song.parsedSyncedLyrics[1].timeMs, equals(15500));
      expect(song.plainLyricLines.length, equals(2));
    });
  });
}

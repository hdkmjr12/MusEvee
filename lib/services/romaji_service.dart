import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/track_metadata.dart';

/// Represents a single parsed line of lyrics split into its optional LRC
/// `[mm:ss.xx]` timestamp prefix and its pure lyric text content.
class ParsedLyricLine {
  final String timestampPrefix;
  final String lyricContent;

  const ParsedLyricLine({
    required this.timestampPrefix,
    required this.lyricContent,
  });

  bool get hasTimestamp => timestampPrefix.isNotEmpty;
  bool get hasLyricContent => lyricContent.trim().isNotEmpty;
}

class RomajiService {
  final Dio _dio;

  static const int _batchConcurrency = 8;

  RomajiService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
              ),
            );

  static final RegExp _japaneseRegex = RegExp(
    r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]',
  );

  static final RegExp _kanjiRegex = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff]');

  /// Strict line-by-line LRC parser regex that isolates one or more leading
  /// `[mm:ss.xx]` timestamps in group(1) and the pure lyric text in group(2).
  static final RegExp lineTimestampRegex = RegExp(
    r'^((?:\[\d{2}:\d{2}(?:\.\d{1,3})?\])+)(.*)$',
  );

  /// Fallback timestamp detector that also catches 1-3 digit minutes or `:` ms.
  static final RegExp anyLrcTimestampRegex = RegExp(
    r'^((?:\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\])+)(.*)$',
  );

  /// Matches contiguous Japanese segments (including numbers attached to Kanji
  /// such as `1人` or `100年`, and spaces between Japanese phrases) while leaving
  /// parenthetical or trailing English phrases untouched.
  static final RegExp _japaneseSegmentRegex = RegExp(
    r'(?:[0-9０-９]*[\u3000-\u303f\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uff00-\uffef]+)+(?:\s+(?:[0-9０-９]*[\u3000-\u303f\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uff00-\uffef]+)+)*',
  );

  /// Returns true if [text] contains Hiragana, Katakana, or Kanji characters.
  static bool containsJapanese(String text) {
    if (text.trim().isEmpty) return false;
    return _japaneseRegex.hasMatch(text);
  }

  /// Returns true if [text] contains any Kanji characters.
  static bool containsKanji(String text) {
    if (text.trim().isEmpty) return false;
    return _kanjiRegex.hasMatch(text);
  }

  /// Returns true if [track] has Japanese characters in title, artist, or album.
  static bool trackHasJapanese(TrackMetadata track) {
    return containsJapanese(track.title) ||
        containsJapanese(track.artist) ||
        containsJapanese(track.album);
  }

  /// Returns true if [track] has Japanese characters in its synced or plain lyrics.
  static bool trackLyricsHasJapanese(TrackMetadata track) {
    return containsJapanese(track.syncedLyrics ?? '') ||
        containsJapanese(track.plainLyrics ?? '');
  }

  /// Parses a single lyric line into [ParsedLyricLine] (`timestampPrefix` and `lyricContent`).
  static ParsedLyricLine parseLyricLine(String rawLine) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) {
      return const ParsedLyricLine(timestampPrefix: '', lyricContent: '');
    }

    final strictMatch = lineTimestampRegex.firstMatch(trimmed);
    if (strictMatch != null) {
      return ParsedLyricLine(
        timestampPrefix: (strictMatch.group(1) ?? '').trim(),
        lyricContent: (strictMatch.group(2) ?? '').trim(),
      );
    }

    final fallbackMatch = anyLrcTimestampRegex.firstMatch(trimmed);
    if (fallbackMatch != null) {
      return ParsedLyricLine(
        timestampPrefix: (fallbackMatch.group(1) ?? '').trim(),
        lyricContent: (fallbackMatch.group(2) ?? '').trim(),
      );
    }

    return ParsedLyricLine(timestampPrefix: '', lyricContent: trimmed);
  }

  /// Strips `[mm:ss.xx]` timestamps and LRC metadata headers from [lyrics]
  /// line-by-line to produce clean `plainLyrics` without making extra API calls.
  static String stripTimestamps(String lyrics) {
    if (lyrics.trim().isEmpty) return '';
    final normalized = lyrics.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final lrcHeaderRegex = RegExp(
      r'^\[(ti|ar|al|by|offset|length|re|ve):.*\]$',
      caseSensitive: false,
    );

    final plainLines = <String>[];
    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (lrcHeaderRegex.hasMatch(trimmed)) continue;
      final parsed = parseLyricLine(trimmed);
      if (parsed.hasTimestamp && !parsed.hasLyricContent) {
        plainLines.add('');
      } else {
        plainLines.add(parsed.lyricContent.trim());
      }
    }
    return plainLines.join('\n').trim();
  }

  static const Map<String, String> _digraphMap = {
    // Hiragana digraphs
    'きゃ': 'kya', 'きゅ': 'kyu', 'きょ': 'kyo',
    'しゃ': 'sha', 'しゅ': 'shu', 'しょ': 'sho',
    'ちゃ': 'cha', 'ちゅ': 'chu', 'ちょ': 'cho',
    'にゃ': 'nya', 'にゅ': 'nyu', 'にょ': 'nyo',
    'ひゃ': 'hya', 'ひゅ': 'hyu', 'ひょ': 'hyo',
    'みゃ': 'mya', 'みゅ': 'myu', 'みょ': 'myo',
    'りゃ': 'rya', 'りゅ': 'ryu', 'りょ': 'ryo',
    'ぎゃ': 'gya', 'ぎゅ': 'gyu', 'ぎょ': 'gyo',
    'じゃ': 'ja', 'じゅ': 'ju', 'じょ': 'jo',
    'びゃ': 'bya', 'びゅ': 'byu', 'びょ': 'byo',
    'ぴゃ': 'pya', 'ぴゅ': 'pyu', 'ぴょ': 'pyo',
    'ふぁ': 'fa', 'ふぃ': 'fi', 'ふぇ': 'fe', 'ふぉ': 'fo',
    'てぃ': 'ti', 'でぃ': 'di', 'うぃ': 'wi', 'うぇ': 'we', 'うぉ': 'wo',
    // Katakana digraphs
    'キャ': 'kya', 'キュ': 'kyu', 'キョ': 'kyo',
    'シャ': 'sha', 'シュ': 'shu', 'ショ': 'sho',
    'チャ': 'cha', 'チュ': 'chu', 'チョ': 'cho',
    'ニャ': 'nya', 'ニュ': 'nyu', 'ニョ': 'nyo',
    'ヒャ': 'hya', 'ヒュ': 'hyu', 'ヒョ': 'hyo',
    'ミャ': 'mya', 'ミュ': 'myu', 'ミョ': 'myo',
    'リャ': 'rya', 'リュ': 'ryu', 'リョ': 'ryo',
    'ギャ': 'gya', 'ギュ': 'gyu', 'ギョ': 'gyo',
    'ジャ': 'ja', 'ジュ': 'ju', 'ジョ': 'jo',
    'ビャ': 'bya', 'ビュ': 'byu', 'ビョ': 'byo',
    'ピャ': 'pya', 'ピュ': 'pyu', 'ピョ': 'pyo',
    'ファ': 'fa', 'フィ': 'fi', 'フェ': 'fe', 'フォ': 'fo',
    'ティ': 'ti', 'ディ': 'di', 'トゥ': 'tu', 'ドゥ': 'du',
    'ウィ': 'wi', 'ウェ': 'we', 'ウォ': 'wo',
    'ヴァ': 'va', 'ヴィ': 'vi', 'ヴ': 'vu', 'ヴェ': 've', 'ヴォ': 'vo',
    'シェ': 'she', 'ジェ': 'je', 'チェ': 'che',
  };

  static const Map<String, String> _monographMap = {
    // Hiragana
    'あ': 'a', 'い': 'i', 'う': 'u', 'え': 'e', 'お': 'o',
    'か': 'ka', 'き': 'ki', 'く': 'ku', 'け': 'ke', 'こ': 'ko',
    'さ': 'sa', 'し': 'shi', 'す': 'su', 'せ': 'se', 'そ': 'so',
    'た': 'ta', 'ち': 'chi', 'つ': 'tsu', 'て': 'te', 'と': 'to',
    'な': 'na', 'に': 'ni', 'ぬ': 'nu', 'ね': 'ne', 'の': 'no',
    'は': 'ha', 'ひ': 'hi', 'ふ': 'fu', 'へ': 'he', 'ほ': 'ho',
    'ま': 'ma', 'み': 'mi', 'む': 'mu', 'め': 'me', 'も': 'mo',
    'や': 'ya', 'ゆ': 'yu', 'よ': 'yo',
    'ら': 'ra', 'り': 'ri', 'る': 'ru', 'れ': 're', 'ろ': 'ro',
    'わ': 'wa', 'ゐ': 'wi', 'ゑ': 'we', 'を': 'o', 'ん': 'n',
    'が': 'ga', 'ぎ': 'gi', 'ぐ': 'gu', 'げ': 'ge', 'ご': 'go',
    'ざ': 'za', 'じ': 'ji', 'ず': 'zu', 'ぜ': 'ze', 'ぞ': 'zo',
    'だ': 'da', 'ぢ': 'ji', 'づ': 'zu', 'で': 'de', 'ど': 'do',
    'ば': 'ba', 'び': 'bi', 'ぶ': 'bu', 'べ': 'be', 'ぼ': 'bo',
    'ぱ': 'pa', 'ぴ': 'pi', 'ぷ': 'pu', 'ぺ': 'pe', 'ぽ': 'po',
    'ぁ': 'a', 'ぃ': 'i', 'ぅ': 'u', 'ぇ': 'e', 'ぉ': 'o',
    'ゃ': 'ya', 'ゅ': 'yu', 'ょ': 'yo', 'ゎ': 'wa',
    // Katakana
    'ア': 'a', 'イ': 'i', 'ウ': 'u', 'エ': 'e', 'オ': 'o',
    'カ': 'ka', 'キ': 'ki', 'ク': 'ku', 'ケ': 'ke', 'コ': 'ko',
    'サ': 'sa', 'シ': 'shi', 'ス': 'su', 'セ': 'se', 'ソ': 'so',
    'タ': 'ta', 'チ': 'chi', 'ツ': 'tsu', 'テ': 'te', 'ト': 'to',
    'ナ': 'na', 'ニ': 'ni', 'ヌ': 'nu', 'ネ': 'ne', 'ノ': 'no',
    'ハ': 'ha', 'ヒ': 'hi', 'フ': 'fu', 'ヘ': 'he', 'ホ': 'ho',
    'マ': 'ma', 'ミ': 'mi', 'ム': 'mu', 'メ': 'me', 'モ': 'mo',
    'ヤ': 'ya', 'ユ': 'yu', 'ヨ': 'yo',
    'ラ': 'ra', 'リ': 'ri', 'ル': 'ru', 'レ': 're', 'ロ': 'ro',
    'ワ': 'wa', 'ヰ': 'wi', 'ヱ': 'we', 'ヲ': 'o', 'ン': 'n',
    'ガ': 'ga', 'ギ': 'gi', 'グ': 'gu', 'ゲ': 'ge', 'ゴ': 'go',
    'ザ': 'za', 'ジ': 'ji', 'ズ': 'zu', 'ゼ': 'ze', 'ゾ': 'zo',
    'ダ': 'da', 'ヂ': 'ji', 'ヅ': 'zu', 'デ': 'de', 'ド': 'do',
    'バ': 'ba', 'ビ': 'bi', 'ブ': 'bu', 'ベ': 'be', 'ボ': 'bo',
    'パ': 'pa', 'ピ': 'pi', 'プ': 'pu', 'ペ': 'pe', 'ポ': 'po',
    'ァ': 'a', 'ィ': 'i', 'ゥ': 'u', 'ェ': 'e', 'ォ': 'o',
    'ャ': 'ya', 'ュ': 'yu', 'ョ': 'yo', 'ヮ': 'wa',
    '・': ' ', '　': ' ',
  };

  /// Direct local Hepburn romanization for Hiragana and Katakana strings.
  static String convertKanaToRomaji(String input) {
    if (input.isEmpty) return input;
    final buffer = StringBuffer();
    int i = 0;
    bool doubleNextConsonant = false;

    while (i < input.length) {
      final char = input[i];

      // Small tsu (sokuon) doubles the next consonant
      if (char == 'っ' || char == 'ッ') {
        doubleNextConsonant = true;
        i++;
        continue;
      }

      // Prolonged sound mark
      if (char == 'ー') {
        i++;
        continue;
      }

      // Check 2-char digraph first
      if (i + 1 < input.length) {
        final twoChar = input.substring(i, i + 2);
        final digraphRomaji = _digraphMap[twoChar];
        if (digraphRomaji != null) {
          if (doubleNextConsonant && digraphRomaji.isNotEmpty) {
            buffer.write(digraphRomaji[0]);
            doubleNextConsonant = false;
          }
          buffer.write(digraphRomaji);
          i += 2;
          continue;
        }
      }

      // Check 1-char monograph
      final monoRomaji = _monographMap[char];
      if (monoRomaji != null) {
        if (doubleNextConsonant && monoRomaji.isNotEmpty) {
          buffer.write(monoRomaji[0]);
          doubleNextConsonant = false;
        }
        buffer.write(monoRomaji);
        i++;
        continue;
      }

      doubleNextConsonant = false;
      buffer.write(char);
      i++;
    }

    return buffer.toString();
  }

  /// Cleans a single romanized line: normalizes full-width Japanese punctuation,
  /// strips any stray line breaks, and collapses duplicate spaces while keeping
  /// standard punctuation intact.
  static String cleanRomajiLine(String input) {
    if (input.isEmpty) return '';
    var cleaned = input
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('　', ' ')
        .replaceAll('、', ', ')
        .replaceAll('。', '. ')
        .replaceAll('！', '! ')
        .replaceAll('？', '? ')
        .replaceAll('「', '"')
        .replaceAll('」', '"')
        .replaceAll('『', '"')
        .replaceAll('』', '"')
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('～', '~')
        .replaceAll('〜', '~')
        .replaceAll('`', "'");

    // Remove spaces immediately before closing punctuation or after opening parens
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\s+([,.)!?])'),
      (m) => m.group(1)!,
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(\()\s+'),
      (m) => m.group(1)!,
    );

    // Collapse multiple spaces into a single space
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  /// Queries Google Translate's `dt=rm` morphological romanization endpoint
  /// for a single Japanese segment with automatic retry so Kanji never leaks.
  Future<String> _fetchRomajiSegmentFromApi(String segment) async {
    final trimmed = segment.trim();
    if (trimmed.isEmpty || !containsJapanese(trimmed)) {
      return trimmed;
    }

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final resp = await _dio
            .get<dynamic>(
              'https://translate.googleapis.com/translate_a/single',
              queryParameters: {
                'client': 'gtx',
                'sl': 'ja',
                'tl': 'en',
                'dt': 'rm',
                'q': trimmed,
              },
            )
            .timeout(const Duration(seconds: 8));

        final data = resp.data is String
            ? jsonDecode(resp.data as String)
            : resp.data;
        if (data is List && data.isNotEmpty && data[0] is List) {
          final sentences = data[0] as List;
          final romajiParts = <String>[];
          for (final entry in sentences) {
            if (entry is List && entry.length >= 4 && entry[3] != null) {
              final rm = entry[3].toString().trim();
              if (rm.isNotEmpty) {
                romajiParts.add(rm);
              }
            }
          }
          if (romajiParts.isNotEmpty) {
            final joined = romajiParts.join(' ').trim();
            final converted = convertKanaToRomaji(joined);
            if (!containsKanji(converted)) {
              return cleanRomajiLine(converted);
            }
          }
        }
      } catch (e) {
        debugPrint(
          '[ROMAJI] Attempt ${attempt + 1} gagal untuk "$trimmed": $e',
        );
      }

      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }

    // Offline fallback if network is unreachable
    return cleanRomajiLine(convertKanaToRomaji(trimmed));
  }

  /// Romanizes a single line of text (without timestamps), preserving any
  /// English phrases in parentheses or inline Latin words while converting all
  /// Japanese Kanji + Kana phrases via `dt=rm`.
  Future<String> romanizeText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !containsJapanese(trimmed)) {
      return text;
    }

    final matches = _japaneseSegmentRegex.allMatches(trimmed).toList();
    if (matches.isEmpty) {
      return cleanRomajiLine(await _fetchRomajiSegmentFromApi(trimmed));
    }

    final segmentMap = <String, String>{};
    for (final m in matches) {
      final seg = m.group(0)!;
      if (!segmentMap.containsKey(seg)) {
        segmentMap[seg] = await _fetchRomajiSegmentFromApi(seg);
      }
    }

    final replaced = trimmed.replaceAllMapped(_japaneseSegmentRegex, (m) {
      final seg = m.group(0)!;
      return segmentMap[seg] ?? seg;
    });

    return cleanRomajiLine(replaced);
  }

  /// Converts full multi-line lyrics from Japanese Kanji/Kana into Romaji
  /// while strictly isolating and preserving `[mm:ss.xx]` timestamps and
  /// 1-to-1 line alignment.
  Future<String> romanizeLyrics(String rawLyrics) async {
    if (rawLyrics.trim().isEmpty || !containsJapanese(rawLyrics)) {
      return rawLyrics;
    }

    final normalizedInput =
        rawLyrics.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rawLines = normalizedInput.split('\n');
    final parsedLines = rawLines.map(parseLyricLine).toList();

    // 1. Collect all unique Japanese segments across all lyricContent lines
    final uniqueSegments = <String>[];
    final seenSegments = <String>{};

    for (final parsed in parsedLines) {
      if (!parsed.hasLyricContent || !containsJapanese(parsed.lyricContent)) {
        continue;
      }
      final matches =
          _japaneseSegmentRegex.allMatches(parsed.lyricContent).toList();
      if (matches.isEmpty) {
        final full = parsed.lyricContent.trim();
        if (seenSegments.add(full)) {
          uniqueSegments.add(full);
        }
      } else {
        for (final m in matches) {
          final seg = m.group(0)!;
          if (seenSegments.add(seg)) {
            uniqueSegments.add(seg);
          }
        }
      }
    }

    // 2. Transliterate unique Japanese segments in parallel batches of 8
    //    so lines never merge and requests complete rapidly.
    final segmentCache = <String, String>{};
    for (int i = 0; i < uniqueSegments.length; i += _batchConcurrency) {
      final end = (i + _batchConcurrency < uniqueSegments.length)
          ? i + _batchConcurrency
          : uniqueSegments.length;
      final batch = uniqueSegments.sublist(i, end);
      final batchResults = await Future.wait(
        batch.map(_fetchRomajiSegmentFromApi),
      );
      for (int j = 0; j < batch.length; j++) {
        segmentCache[batch[j]] = batchResults[j];
      }
    }

    // 3. Reconstruct each line 1-to-1 with its original timestampPrefix
    final outputLines = <String>[];
    for (int i = 0; i < rawLines.length; i++) {
      final originalTrimmed = rawLines[i].trim();
      final parsed = parsedLines[i];

      // Preserve empty lines or timestamp-only lines untouched
      if (originalTrimmed.isEmpty) {
        outputLines.add('');
        continue;
      }
      if (!parsed.hasLyricContent) {
        outputLines.add(parsed.timestampPrefix);
        continue;
      }

      String romanizedLine;
      if (!containsJapanese(parsed.lyricContent)) {
        romanizedLine = parsed.lyricContent.trim();
      } else {
        final replaced = parsed.lyricContent.replaceAllMapped(
          _japaneseSegmentRegex,
          (m) {
            final seg = m.group(0)!;
            return segmentCache[seg] ?? convertKanaToRomaji(seg);
          },
        );
        romanizedLine = cleanRomajiLine(replaced);
      }

      if (parsed.hasTimestamp) {
        outputLines.add('${parsed.timestampPrefix} ${romanizedLine.trim()}');
      } else {
        outputLines.add(romanizedLine.trim());
      }
    }

    return outputLines.join('\n');
  }

  /// Automatically converts Japanese Title, Artist, and Album of [metadata]
  /// into Romaji / international equivalents using iTunes US catalog matching
  /// + Romaji transliteration fallback.
  Future<TrackMetadata> romanizeTrackInfo(TrackMetadata metadata) async {
    String newTitle = metadata.title;
    String newArtist = metadata.artist;
    String newAlbum = metadata.album;

    // 1. Try iTunes US English lookup first for official Romaji/English artist & title
    try {
      final query = '${metadata.artist} ${metadata.title}';
      final resp = await _dio
          .get<dynamic>(
            'https://itunes.apple.com/search',
            queryParameters: {
              'term': query,
              'country': 'US',
              'lang': 'en_us',
              'entity': 'song',
              'limit': 5,
            },
          )
          .timeout(const Duration(seconds: 7));

      final map = resp.data is String
          ? jsonDecode(resp.data as String)
          : resp.data;
      if (map is Map && map['results'] is List) {
        final results = map['results'] as List;
        for (final item in results) {
          if (item is! Map) continue;
          final durMs = (item['trackTimeMillis'] is num)
              ? (item['trackTimeMillis'] as num).toInt()
              : 0;
          final durSec = durMs > 0 ? (durMs / 1000).round() : 0;
          if (metadata.durationSeconds > 0 &&
              durSec > 0 &&
              (durSec - metadata.durationSeconds).abs() <= 6) {
            final candidateTitle = (item['trackName']?.toString() ?? '').trim();
            final candidateArtist =
                (item['artistName']?.toString() ?? '').trim();
            final candidateAlbum =
                (item['collectionName']?.toString() ?? '').trim();

            if (candidateTitle.isNotEmpty && !containsJapanese(candidateTitle)) {
              newTitle = candidateTitle;
            }
            if (candidateArtist.isNotEmpty &&
                !containsJapanese(candidateArtist)) {
              newArtist = candidateArtist;
            }
            if (candidateAlbum.isNotEmpty && !containsJapanese(candidateAlbum)) {
              newAlbum = candidateAlbum;
            }
            break;
          }
        }
      }
    } catch (_) {}

    // 2. Transliterate any remaining Japanese fields via romanizeText
    if (containsJapanese(newTitle)) {
      final romTitle = await romanizeText(newTitle);
      if (romTitle.trim().isNotEmpty) {
        newTitle = _titleCaseWords(romTitle);
      }
    }
    if (containsJapanese(newArtist)) {
      final romArtist = await romanizeText(newArtist);
      if (romArtist.trim().isNotEmpty) {
        newArtist = _titleCaseWords(romArtist);
      }
    }
    if (containsJapanese(newAlbum)) {
      final romAlbum = await romanizeText(newAlbum);
      if (romAlbum.trim().isNotEmpty) {
        newAlbum = _titleCaseWords(romAlbum);
      }
    }

    return metadata.copyWith(
      title: newTitle,
      artist: newArtist,
      album: newAlbum,
    );
  }

  /// Synchronizes and converts both `syncedLyrics` and `plainLyrics` of [metadata]
  /// into Romaji. If `syncedLyrics` exists, it is romanized with timestamp
  /// preservation and `plainLyrics` is derived directly by stripping timestamps
  /// (avoiding double API calls).
  Future<TrackMetadata> romanizeTrackLyrics(TrackMetadata metadata) async {
    if (metadata.hasSyncedLyrics &&
        containsJapanese(metadata.syncedLyrics!)) {
      final romanizedSynced = await romanizeLyrics(metadata.syncedLyrics!);
      final romanizedPlain = stripTimestamps(romanizedSynced);
      return metadata.copyWith(
        syncedLyrics: romanizedSynced,
        plainLyrics: romanizedPlain,
      );
    }

    if (metadata.hasPlainLyrics && containsJapanese(metadata.plainLyrics!)) {
      final romanizedPlain = await romanizeLyrics(metadata.plainLyrics!);
      return metadata.copyWith(
        plainLyrics: romanizedPlain,
      );
    }

    return metadata;
  }

  static String _titleCaseWords(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return input;
    return trimmed
        .split(RegExp(r'\s+'))
        .map((w) {
          if (w.isEmpty) return w;
          return w[0].toUpperCase() + w.substring(1);
        })
        .join(' ');
  }
}

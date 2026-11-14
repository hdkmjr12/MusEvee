import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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

class _ProcessedLyricLine {
  final String timestampPrefix;
  final String romanizedContent;
  final String originalContent;
  final bool wasOriginallyJapanese;
  final bool isEmptyLine;

  const _ProcessedLyricLine({
    required this.timestampPrefix,
    required this.romanizedContent,
    required this.originalContent,
    required this.wasOriginallyJapanese,
    required this.isEmptyLine,
  });
}

class RomajiService {
  final Dio _dio;
  final File? _injectedCacheFile;

  static const int _batchConcurrency = 8;
  static const String _cacheFileName = 'musevee_romaji_cache_v1.json';
  static const int _maxDiskCacheEntries = 6000;

  final Map<String, String> _diskSegmentCache = <String, String>{};
  bool _diskCacheLoaded = false;
  bool _diskCacheDirty = false;
  bool _lastConversionLeftUnconvertedKanji = false;

  bool get lastConversionLeftUnconvertedKanji =>
      _lastConversionLeftUnconvertedKanji;

  @visibleForTesting
  int get cachedSegmentCount => _diskSegmentCache.length;

  RomajiService({Dio? dio, File? cacheFile})
      : _injectedCacheFile = cacheFile,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
              ),
            );

  Future<File?> _resolveCacheFile() async {
    if (_injectedCacheFile != null) return _injectedCacheFile;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}${Platform.pathSeparator}$_cacheFileName');
    } catch (_) {
      return null;
    }
  }

  Future<void> ensureDiskCacheLoaded() async {
    if (_diskCacheLoaded) return;
    _diskCacheLoaded = true;
    try {
      final file = await _resolveCacheFile();
      if (file == null || !await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          final k = key?.toString().trim() ?? '';
          final v = value?.toString().trim() ?? '';
          if (k.isNotEmpty && v.isNotEmpty && !containsKanji(v)) {
            _diskSegmentCache[k] = v;
          }
        });
      }
    } catch (_) {
      // Ignore corrupt/missing cache gracefully so offline Kana conversion works.
    }
  }

  Future<void> _persistDiskCacheIfNeeded() async {
    if (!_diskCacheDirty) return;
    _diskCacheDirty = false;
    try {
      final file = await _resolveCacheFile();
      if (file == null) return;
      while (_diskSegmentCache.length > _maxDiskCacheEntries) {
        _diskSegmentCache.remove(_diskSegmentCache.keys.first);
      }
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(jsonEncode(_diskSegmentCache), flush: true);
    } catch (_) {
      // Disk write errors should never crash offline romanization.
    }
  }

  @visibleForTesting
  Future<void> seedOfflineSegmentCacheForTesting(
    Map<String, String> entries, {
    bool persist = true,
  }) async {
    await ensureDiskCacheLoaded();
    for (final e in entries.entries) {
      final k = e.key.trim();
      final v = e.value.trim();
      if (k.isNotEmpty && v.isNotEmpty && !containsKanji(v)) {
        _diskSegmentCache[k] = v;
        _diskCacheDirty = true;
      }
    }
    if (persist) {
      await _persistDiskCacheIfNeeded();
    }
  }

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
  /// for a single Japanese segment with automatic retry and persistent offline
  /// segment caching so previously converted Kanji songs stay 100% offline-ready.
  Future<String> _fetchRomajiSegmentFromApi(String segment) async {
    final trimmed = segment.trim();
    if (trimmed.isEmpty || !containsJapanese(trimmed)) {
      return trimmed;
    }

    await ensureDiskCacheLoaded();
    final cached = _diskSegmentCache.remove(trimmed);
    if (cached != null && !containsKanji(cached)) {
      // Re-insert to keep LRU recency.
      _diskSegmentCache[trimmed] = cached;
      return cached;
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
              final clean = cleanRomajiLine(converted);
              if (clean.isNotEmpty) {
                _diskSegmentCache[trimmed] = clean;
                _diskCacheDirty = true;
              }
              return clean;
            }
          }
        }
      } catch (e) {
        debugPrint(
          '[ROMAJI] Attempt ${attempt + 1} gagal untuk "$trimmed": $e',
        );
        if (e is SocketException ||
            (e is DioException &&
                (e.type == DioExceptionType.connectionError ||
                    e.error is SocketException))) {
          break;
        }
      }

      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }

    // Offline fallback if network is unreachable (Hiragana/Katakana convert 100% locally)
    return cleanRomajiLine(convertKanaToRomaji(trimmed));
  }

  /// Romanizes a single line of text (without timestamps), preserving any
  /// English phrases in parentheses or inline Latin words while converting all
  /// Japanese Kanji + Kana phrases via cached/online `dt=rm` + offline Kana.
  Future<String> romanizeText(String text) async {
    _lastConversionLeftUnconvertedKanji = false;
    final trimmed = text.trim();
    if (trimmed.isEmpty || !containsJapanese(trimmed)) {
      return text;
    }

    await ensureDiskCacheLoaded();
    final matches = _japaneseSegmentRegex.allMatches(trimmed).toList();
    String output;
    if (matches.isEmpty) {
      output = cleanRomajiLine(await _fetchRomajiSegmentFromApi(trimmed));
    } else {
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
      output = cleanRomajiLine(replaced);
    }

    await _persistDiskCacheIfNeeded();
    _lastConversionLeftUnconvertedKanji = containsKanji(output);
    return output;
  }

  /// Strips inline Hiragana/Katakana furigana readings immediately attached to
  /// Kanji (e.g. `無敵(むてき)` -> `無敵`) while keeping English parentheticals intact.
  static String stripInlineFurigana(String text) {
    if (text.isEmpty || !containsKanji(text)) return text;
    return text.replaceAllMapped(
      RegExp(
        r'([\u3400-\u4dbf\u4e00-\u9fff]+)[(（《【\[][\u3040-\u309f\u30a0-\u30ffー]+[)）》】\]]',
      ),
      (m) => m.group(1)!,
    );
  }

  /// Deduplicates already-romanized lyrics that still contain duplicate Romaji
  /// lines on identical or near-identical (`< 0.75s`) timestamps.
  static String deduplicateRomajiLyrics(String rawLyrics) {
    if (rawLyrics.trim().isEmpty) return rawLyrics;
    final normalizedInput =
        rawLyrics.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rawLines = normalizedInput.split('\n');
    final processed = <_ProcessedLyricLine>[];

    for (final raw in rawLines) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        processed.add(
          const _ProcessedLyricLine(
            timestampPrefix: '',
            romanizedContent: '',
            originalContent: '',
            wasOriginallyJapanese: false,
            isEmptyLine: true,
          ),
        );
        continue;
      }
      final parsed = parseLyricLine(trimmed);
      final cleanedContent = parsed.hasLyricContent
          ? _deduplicateInlineBilingual(parsed.lyricContent.trim())
          : '';
      processed.add(
        _ProcessedLyricLine(
          timestampPrefix: parsed.timestampPrefix,
          romanizedContent: cleanedContent,
          originalContent: parsed.lyricContent.trim(),
          wasOriginallyJapanese: false,
          isEmptyLine: false,
        ),
      );
    }

    final deduped = _deduplicateBilingualLines(processed);
    return _formatProcessedLines(deduped);
  }

  static String _formatProcessedLines(List<_ProcessedLyricLine> lines) {
    final outputLines = <String>[];
    for (final line in lines) {
      if (line.isEmptyLine) {
        outputLines.add('');
      } else if (line.romanizedContent.isEmpty) {
        outputLines.add(line.timestampPrefix);
      } else if (line.timestampPrefix.isNotEmpty) {
        outputLines.add('${line.timestampPrefix} ${line.romanizedContent}');
      } else {
        outputLines.add(line.romanizedContent);
      }
    }
    return outputLines.join('\n');
  }

  /// Converts full multi-line lyrics from Japanese Kanji/Kana into Romaji
  /// while strictly isolating and preserving `[mm:ss.xx]` timestamps and
  /// deduplicating bilingual Kanji + Romaji lines.
  Future<String> romanizeLyrics(String rawLyrics) async {
    _lastConversionLeftUnconvertedKanji = false;
    if (rawLyrics.trim().isEmpty) {
      return rawLyrics;
    }
    if (!containsJapanese(rawLyrics)) {
      return deduplicateRomajiLyrics(rawLyrics);
    }

    await ensureDiskCacheLoaded();

    final normalizedInput =
        rawLyrics.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rawLines = normalizedInput.split('\n');
    final parsedLines = rawLines
        .map((line) {
          final parsed = parseLyricLine(line);
          if (!parsed.hasLyricContent) return parsed;
          return ParsedLyricLine(
            timestampPrefix: parsed.timestampPrefix,
            lyricContent: stripInlineFurigana(parsed.lyricContent),
          );
        })
        .toList();

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

    // 3. Reconstruct each line with its original timestampPrefix and metadata
    final processedLines = <_ProcessedLyricLine>[];
    for (int i = 0; i < rawLines.length; i++) {
      final originalTrimmed = rawLines[i].trim();
      final parsed = parsedLines[i];

      // Preserve empty lines or timestamp-only lines untouched
      if (originalTrimmed.isEmpty) {
        processedLines.add(
          const _ProcessedLyricLine(
            timestampPrefix: '',
            romanizedContent: '',
            originalContent: '',
            wasOriginallyJapanese: false,
            isEmptyLine: true,
          ),
        );
        continue;
      }
      if (!parsed.hasLyricContent) {
        processedLines.add(
          _ProcessedLyricLine(
            timestampPrefix: parsed.timestampPrefix,
            romanizedContent: '',
            originalContent: '',
            wasOriginallyJapanese: false,
            isEmptyLine: false,
          ),
        );
        continue;
      }

      final hadJapanese = containsJapanese(parsed.lyricContent);
      String romanizedLine;
      if (!hadJapanese) {
        romanizedLine = _deduplicateInlineBilingual(parsed.lyricContent.trim());
      } else {
        final replaced = parsed.lyricContent.replaceAllMapped(
          _japaneseSegmentRegex,
          (m) {
            final seg = m.group(0)!;
            return segmentCache[seg] ?? convertKanaToRomaji(seg);
          },
        );
        romanizedLine = _deduplicateInlineBilingual(cleanRomajiLine(replaced));
      }

      processedLines.add(
        _ProcessedLyricLine(
          timestampPrefix: parsed.timestampPrefix,
          romanizedContent: romanizedLine.trim(),
          originalContent: parsed.lyricContent.trim(),
          wasOriginallyJapanese: hadJapanese,
          isEmptyLine: false,
        ),
      );
    }

    // 4. Deduplicate consecutive bilingual or duplicate Romaji lines
    final deduplicated = _deduplicateBilingualLines(processedLines);
    final formatted = _formatProcessedLines(deduplicated);
    await _persistDiskCacheIfNeeded();
    _lastConversionLeftUnconvertedKanji = containsKanji(formatted);
    return formatted;
  }

  /// Normalizes a Romaji/Latin lyric string for bilingual duplicate comparison:
  /// - Lowercases all characters
  /// - Converts macron vowels (`ā`, `ī`, `ū`, `ē`, `ō`) and circumflex vowels to plain vowels
  /// - Unifies Hepburn / Kunrei / long-vowel variants (`ou`/`oo` -> `o`, `uu` -> `u`, `aa` -> `a`, `ii` -> `i`, `ee` -> `e`, `wo` -> `o`, `dzu`/`du` -> `zu`)
  /// - Strips all punctuation, apostrophes (`'`), and whitespace
  static String normalizeForComparison(String text) {
    if (text.trim().isEmpty) return '';
    var s = text.toLowerCase();

    // Replace macron & circumflex vowels
    s = s
        .replaceAll('ā', 'a')
        .replaceAll('ī', 'i')
        .replaceAll('ū', 'u')
        .replaceAll('ē', 'e')
        .replaceAll('ō', 'o')
        .replaceAll('â', 'a')
        .replaceAll('î', 'i')
        .replaceAll('û', 'u')
        .replaceAll('ê', 'e')
        .replaceAll('ô', 'o');

    // Normalize common Japanese particle & romanization variants before stripping spaces
    s = s
        .replaceAll(RegExp(r'\bwo\b'), 'o')
        .replaceAll('dzu', 'zu')
        .replaceAll('du', 'zu')
        .replaceAll('tch', 'cch')
        .replaceAll('si', 'shi')
        .replaceAll('ti', 'chi')
        .replaceAll('tu', 'tsu')
        .replaceAll('hu', 'fu')
        .replaceAll('zi', 'ji')
        .replaceAll('sya', 'sha')
        .replaceAll('syu', 'shu')
        .replaceAll('syo', 'sho')
        .replaceAll('tya', 'cha')
        .replaceAll('tyu', 'chu')
        .replaceAll('tyo', 'cho')
        .replaceAll('jya', 'ja')
        .replaceAll('jyu', 'ju')
        .replaceAll('jyo', 'jo');

    // Strip all punctuation, apostrophes, and spaces (keep only a-z and 0-9)
    s = s.replaceAll(RegExp(r'[^a-z0-9]'), '');

    // Collapse long vowel spellings (ou -> o, oo -> o, uu -> u, aa -> a, ii -> i, ee -> e)
    // and nasal assimilation (nb -> mb, np -> mp, nm -> mm -> m)
    s = s
        .replaceAll('nb', 'mb')
        .replaceAll('np', 'mp')
        .replaceAll('nm', 'mm')
        .replaceAll('ou', 'o')
        .replaceAll(RegExp(r'a+'), 'a')
        .replaceAll(RegExp(r'i+'), 'i')
        .replaceAll(RegExp(r'u+'), 'u')
        .replaceAll(RegExp(r'e+'), 'e')
        .replaceAll(RegExp(r'o+'), 'o');

    return s;
  }

  /// Parses the first `[mm:ss.xx]` timestamp in [timestampPrefix] into seconds.
  static double? parseTimestampSeconds(String timestampPrefix) {
    if (timestampPrefix.isEmpty) return null;
    final match = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]')
        .firstMatch(timestampPrefix);
    if (match == null) return null;
    final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
    final fracStr = match.group(3) ?? '';
    double frac = 0.0;
    if (fracStr.isNotEmpty) {
      final raw = int.tryParse(fracStr) ?? 0;
      if (fracStr.length == 1) {
        frac = raw / 10.0;
      } else if (fracStr.length == 2) {
        frac = raw / 100.0;
      } else {
        frac = raw / 1000.0;
      }
    }
    return (minutes * 60) + seconds + frac;
  }

  /// Computes normalized similarity ratio in `[0.0, 1.0]` between two strings
  /// that have already been passed through [normalizeForComparison].
  static double similarityRatio(String normA, String normB) {
    if (normA.isEmpty || normB.isEmpty) return 0.0;
    if (normA == normB) return 1.0;

    final shorter = normA.length <= normB.length ? normA : normB;
    final longer = normA.length <= normB.length ? normB : normA;
    if (longer.contains(shorter) && shorter.length >= 4) {
      return shorter.length / longer.length;
    }

    if (normA.length < 2 || normB.length < 2) {
      return normA == normB ? 1.0 : 0.0;
    }

    final bigramsA = <String, int>{};
    for (int i = 0; i < normA.length - 1; i++) {
      final bg = normA.substring(i, i + 2);
      bigramsA[bg] = (bigramsA[bg] ?? 0) + 1;
    }

    int intersection = 0;
    for (int i = 0; i < normB.length - 1; i++) {
      final bg = normB.substring(i, i + 2);
      final count = bigramsA[bg] ?? 0;
      if (count > 0) {
        intersection++;
        bigramsA[bg] = count - 1;
      }
    }

    return (2.0 * intersection) / ((normA.length - 1) + (normB.length - 1));
  }

  /// Detects if a pure Latin line is likely Japanese Romaji rather than English
  /// translation by checking strong Romaji particles/syllables and rejecting English lines.
  static bool isRomajiText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || containsJapanese(trimmed)) return false;
    final lower = trimmed.toLowerCase();
    final words = lower
        .replaceAll(RegExp(r"[^a-zāīūēō\s']"), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return false;

    const strongEnglishMarkers = {
      'the', 'you', 'and', 'with', 'that', 'this', 'from', 'have', 'your',
      'for', 'not', 'are', 'was', 'were', 'will', 'would', 'could', 'should',
      "couldn't", "don't", "can't", "won't", "isn't", "i'm", "you're", "it's",
      'know', 'like', 'love', 'heart', 'smile', 'eyes', 'world', 'night',
      'never', 'always', 'every', 'about', 'what', 'when', 'where', 'there',
      'their', 'they', 'even', 'just', 'into', 'out', 'down',
    };

    int englishHits = 0;
    for (final w in words) {
      if (strongEnglishMarkers.contains(w)) {
        englishHits++;
      }
    }
    if (englishHits >= 2) return false;

    const strongRomajiMarkers = {
      'wa', 'ni', 'wo', 'ga', 'de', 'mo', 'ka', 'ne', 'yo', 'na', 'ze', 'zo',
      'kara', 'made', 'kedo', 'keredo', 'node', 'noni', 'tara', 'reba',
      'desu', 'masu', 'desho', 'deshou', 'darou', 'daro', 'janai', 'nai',
      'nakatta', 'tai', 'takunai', 'kimi', 'boku', 'watashi', 'atashi', 'ore',
      'anata', 'kokoro', 'sekai', 'yume', 'koi', 'uta', 'koe', 'namida',
      'hikari', 'sora', 'kaze', 'toki', 'ima', 'kyou', 'ashita', 'mirai',
      'koto', 'mono', 'hito', 'dare', 'nani', 'doko', 'itsu', 'soshite',
      'demo', 'datte', 'kitto', 'zutto', 'motto', 'chotto', 'ichiban',
      'hitori', 'futari', 'kanpeki', 'kyuukyoku', 'kyūkyoku', 'aidoru',
      'muteki', 'egao', 'shiritai', 'himitsu',
    };

    int hits = 0;
    int noToHits = 0;
    for (final w in words) {
      if (w == 'no' || w == 'to') {
        noToHits++;
        continue;
      }
      if (strongRomajiMarkers.contains(w) ||
          w.endsWith('tsu') ||
          w.endsWith('shi') ||
          w.endsWith('chi') ||
          w.endsWith('nai') ||
          w.endsWith('tara') ||
          w.endsWith('masu') ||
          w.endsWith('desu') ||
          w.contains('kyu') ||
          w.contains('kya') ||
          w.contains('kyo') ||
          w.contains('ryu') ||
          w.contains('shu') ||
          w.contains('cho')) {
        hits++;
      }
    }

    if (hits >= 1) {
      final totalHits = hits + noToHits;
      return (totalHits / words.length >= 0.18) || totalHits >= 2;
    }
    return false;
  }

  /// Chooses the cleaner Romaji line between the auto-converted Japanese line
  /// and the existing Romaji line (preferring natural word spacing and clean ASCII).
  static String _pickCleanerRomajiText(
    String convertedFromJp,
    String existingLatin,
  ) {
    final a = convertedFromJp.trim();
    final b = existingLatin.trim();
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;

    final wordsA = a.split(RegExp(r'\s+')).length;
    final wordsB = b.split(RegExp(r'\s+')).length;
    final hasMacronA = RegExp(r'[āīūēōĀĪŪĒŌ]').hasMatch(a);
    final hasMacronB = RegExp(r'[āīūēōĀĪŪĒŌ]').hasMatch(b);

    // Prefer the line that separates particles cleanly (more words up to a reasonable bound)
    // and avoids macrons if word counts are comparable.
    if (wordsB > wordsA && !hasMacronB) {
      return b;
    }
    if (wordsA > wordsB && !hasMacronA) {
      return a;
    }
    if (!hasMacronB && hasMacronA && (wordsB >= wordsA)) {
      return b;
    }
    return wordsB >= wordsA ? b : a;
  }

  /// Deduplicates inline bilingual lyrics on a single line such as:
  /// `Kimi wa kanpekide kyūkyoku no aidoru / Kimi wa kanpeki de kyuukyoku no aidoru`
  static String _deduplicateInlineBilingual(String line) {
    for (final sep in [' / ', ' | ', ' - ', ' // ']) {
      if (line.contains(sep)) {
        final parts = line.split(sep);
        if (parts.length == 2) {
          final norm0 = normalizeForComparison(parts[0]);
          final norm1 = normalizeForComparison(parts[1]);
          if (norm0.isNotEmpty &&
              norm1.isNotEmpty &&
              similarityRatio(norm0, norm1) >= 0.72) {
            return _pickCleanerRomajiText(parts[0], parts[1]);
          }
        }
      }
    }
    return line;
  }

  /// Deduplicates consecutive bilingual or duplicate Romaji lines:
  /// - 1 line originally Japanese + 1 line originally Romaji (same/`<1s` timestamp or high normalized similarity)
  /// - Kanji line + Kana reading line, or already-romanized duplicate pair sharing identical/`<0.75s` timestamp
  /// - Trilingual triplet at identical timestamp (e.g. Kanji + Translation + Romaji)
  static List<_ProcessedLyricLine> _deduplicateBilingualLines(
    List<_ProcessedLyricLine> lines,
  ) {
    if (lines.length < 2) return lines;
    final consumed = List<bool>.filled(lines.length, false);
    final result = <_ProcessedLyricLine>[];

    for (int i = 0; i < lines.length; i++) {
      if (consumed[i]) continue;
      var current = lines[i];
      if (current.isEmptyLine || current.romanizedContent.isEmpty) {
        result.add(current);
        continue;
      }

      // Check up to 2 subsequent non-empty lines if they share the same/close timestamp
      for (int offset = 1; offset <= 2; offset++) {
        final nextIdx = i + offset;
        if (nextIdx >= lines.length || consumed[nextIdx]) continue;

        final next = lines[nextIdx];
        if (next.isEmptyLine) continue;
        if (next.romanizedContent.isEmpty) break;

        final secCurr = parseTimestampSeconds(current.timestampPrefix);
        final secNext = parseTimestampSeconds(next.timestampPrefix);
        final sameTimestamp = current.timestampPrefix.isNotEmpty &&
            current.timestampPrefix == next.timestampPrefix;
        final closeTimestamp = secCurr != null &&
            secNext != null &&
            (secNext - secCurr).abs() < 1.0;
        final veryCloseTimestamp = sameTimestamp ||
            (secCurr != null &&
                secNext != null &&
                (secNext - secCurr).abs() < 0.75);
        final bothUntimestamped =
            current.timestampPrefix.isEmpty && next.timestampPrefix.isEmpty;

        // Only look across offset == 2 if timestamps are identical/close (trilingual LRC) or if i+1 was empty
        if (offset == 2 &&
            !lines[i + 1].isEmptyLine &&
            !sameTimestamp &&
            !closeTimestamp) {
          continue;
        }

        final normCurr = normalizeForComparison(current.romanizedContent);
        final normNext = normalizeForComparison(next.romanizedContent);
        final similarity = similarityRatio(normCurr, normNext);

        final isOneJpOneLatin =
            (current.wasOriginallyJapanese && !next.wasOriginallyJapanese) ||
            (!current.wasOriginallyJapanese && next.wasOriginallyJapanese);

        bool isDuplicate = false;
        if (isOneJpOneLatin) {
          final latinLine = current.wasOriginallyJapanese ? next : current;
          isDuplicate = similarity >= 0.65 ||
              ((sameTimestamp || closeTimestamp) &&
                  (similarity >= 0.45 ||
                      isRomajiText(latinLine.originalContent)));
        } else if ((veryCloseTimestamp && similarity >= 0.72) ||
            (bothUntimestamped && similarity >= 0.90)) {
          // Handles Kanji + Kana furigana lines OR already-romanized duplicate lines
          isDuplicate = true;
        }

        if (isDuplicate) {
          final chosenText = _pickCleanerRomajiText(
            current.romanizedContent,
            next.romanizedContent,
          );
          final chosenPrefix = current.timestampPrefix.isNotEmpty
              ? current.timestampPrefix
              : next.timestampPrefix;

          current = _ProcessedLyricLine(
            timestampPrefix: chosenPrefix,
            romanizedContent: chosenText,
            originalContent: current.originalContent,
            wasOriginallyJapanese:
                current.wasOriginallyJapanese || next.wasOriginallyJapanese,
            isEmptyLine: false,
          );
          consumed[nextIdx] = true;
          // If an empty line stood between current and nextIdx, consume it too
          if (offset == 2 && lines[i + 1].isEmptyLine) {
            consumed[i + 1] = true;
          }
        }
      }

      result.add(current);
    }

    return result;
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

    final out = metadata.copyWith(
      title: newTitle,
      artist: newArtist,
      album: newAlbum,
    );
    _lastConversionLeftUnconvertedKanji =
        containsKanji(newTitle) || containsKanji(newArtist) || containsKanji(newAlbum);
    return out;
  }

  /// Synchronizes and converts both `syncedLyrics` and `plainLyrics` of [metadata]
  /// into Romaji. If `syncedLyrics` exists, it is romanized with timestamp
  /// preservation and `plainLyrics` is derived directly by stripping timestamps
  /// (avoiding double API calls).
  Future<TrackMetadata> romanizeTrackLyrics(TrackMetadata metadata) async {
    _lastConversionLeftUnconvertedKanji = false;
    if (metadata.hasSyncedLyrics) {
      final romanizedSynced = await romanizeLyrics(metadata.syncedLyrics!);
      final romanizedPlain = stripTimestamps(romanizedSynced);
      final out = metadata.copyWith(
        syncedLyrics: romanizedSynced,
        plainLyrics: romanizedPlain,
      );
      _lastConversionLeftUnconvertedKanji = containsKanji(romanizedSynced);
      return out;
    }

    if (metadata.hasPlainLyrics) {
      final romanizedPlain = await romanizeLyrics(metadata.plainLyrics!);
      final out = metadata.copyWith(
        plainLyrics: romanizedPlain,
      );
      _lastConversionLeftUnconvertedKanji = containsKanji(romanizedPlain);
      return out;
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

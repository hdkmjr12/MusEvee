import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/track_metadata.dart';

class RomajiService {
  final Dio _dio;

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

  /// Returns true if [text] contains Hiragana, Katakana, or Kanji characters.
  static bool containsJapanese(String text) {
    if (text.trim().isEmpty) return false;
    return _japaneseRegex.hasMatch(text);
  }

  /// Returns true if [track] has Japanese characters in title, artist, or album.
  static bool trackHasJapanese(TrackMetadata track) {
    return containsJapanese(track.title) ||
        containsJapanese(track.artist) ||
        containsJapanese(track.album);
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

  /// Converts a Japanese text (including Kanji + Kana) into Romaji using
  /// public transliteration endpoint with fallback to local Hepburn Kana table.
  Future<String> romanizeText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !containsJapanese(trimmed)) {
      return text;
    }

    // If it contains no Kanji (only Hiragana/Katakana), local Hepburn is instant & exact
    if (!_kanjiRegex.hasMatch(trimmed)) {
      return _titleCaseWords(convertKanaToRomaji(trimmed));
    }

    // Otherwise query the public transliteration endpoint (`dt=rm`)
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

      final data = resp.data is String ? jsonDecode(resp.data as String) : resp.data;
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
          return convertKanaToRomaji(joined);
        }
      }
    } catch (e) {
      debugPrint('[ROMAJI] Transliterasi endpoint gagal, fallback lokal: $e');
    }

    return convertKanaToRomaji(trimmed);
  }

  /// Converts full multi-line lyrics (preserving `[mm:ss.xx]` timestamps if present)
  /// from Japanese Kanji/Kana into Romaji.
  Future<String> romanizeLyrics(String rawLyrics) async {
    if (rawLyrics.trim().isEmpty || !containsJapanese(rawLyrics)) {
      return rawLyrics;
    }

    final lines = rawLyrics.split(RegExp(r'\r?\n'));
    final timestampRegex = RegExp(r'^(\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\])+');

    final prefixes = <String>[];
    final textBodies = <String>[];

    for (final line in lines) {
      final match = timestampRegex.firstMatch(line.trim());
      if (match != null) {
        final ts = match.group(0)!;
        prefixes.add(ts);
        textBodies.add(line.trim().substring(ts.length).trim());
      } else {
        prefixes.add('');
        textBodies.add(line.trim());
      }
    }

    final combinedBody = textBodies.join('\n');
    String romanizedBody = combinedBody;

    try {
      final resp = await _dio
          .get<dynamic>(
            'https://translate.googleapis.com/translate_a/single',
            queryParameters: {
              'client': 'gtx',
              'sl': 'ja',
              'tl': 'en',
              'dt': 'rm',
              'q': combinedBody,
            },
          )
          .timeout(const Duration(seconds: 10));

      final data = resp.data is String ? jsonDecode(resp.data as String) : resp.data;
      if (data is List && data.isNotEmpty && data[0] is List) {
        final sentences = data[0] as List;
        final sb = StringBuffer();
        for (final entry in sentences) {
          if (entry is List && entry.length >= 4 && entry[3] != null) {
            sb.write(entry[3].toString());
          }
        }
        final resultStr = sb.toString().trim();
        if (resultStr.isNotEmpty) {
          romanizedBody = convertKanaToRomaji(resultStr);
        }
      }
    } catch (_) {
      romanizedBody = convertKanaToRomaji(combinedBody);
    }

    final romanizedLines = romanizedBody.split(RegExp(r'\r?\n'));
    final outputLines = <String>[];

    for (int i = 0; i < lines.length; i++) {
      final prefix = prefixes[i];
      final romLine = i < romanizedLines.length
          ? romanizedLines[i].trim()
          : convertKanaToRomaji(textBodies[i]);
      if (prefix.isNotEmpty) {
        outputLines.add('$prefix $romLine'.trimRight());
      } else {
        outputLines.add(romLine);
      }
    }

    return outputLines.join('\r\n');
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


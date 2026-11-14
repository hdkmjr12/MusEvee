import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/track_metadata.dart';
import 'romaji_service.dart';

class LyricsResult {
  final String? syncedLyrics;
  final String? plainLyrics;

  const LyricsResult({
    this.syncedLyrics,
    this.plainLyrics,
  });

  bool get hasSynced =>
      syncedLyrics != null && syncedLyrics!.trim().isNotEmpty;

  bool get hasPlain =>
      plainLyrics != null && plainLyrics!.trim().isNotEmpty;

  bool get hasAny => hasSynced || hasPlain;
}

/// Represents a single lyrics candidate from LRCLIB with automatic language
/// classification (`[Jepang/Kanji]`, `[Romaji]`, `[Bilingual]`, `[Inggris/Lainnya]`)
/// and a 2-line preview for the manual "Ganti Lirik" picker.
class LyricsCandidate {
  final String id;
  final String trackName;
  final String artistName;
  final String albumName;
  final int durationSeconds;
  final String? syncedLyrics;
  final String? plainLyrics;
  final String languageTag;
  final int score;

  const LyricsCandidate({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.durationSeconds,
    this.syncedLyrics,
    this.plainLyrics,
    required this.languageTag,
    this.score = 0,
  });

  bool get hasSynced =>
      syncedLyrics != null && syncedLyrics!.trim().isNotEmpty;

  bool get hasPlain =>
      plainLyrics != null && plainLyrics!.trim().isNotEmpty;

  bool get hasAny => hasSynced || hasPlain;

  String get formattedDuration {
    if (durationSeconds <= 0) return '--:--';
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  /// Returns the first 2 non-empty lyric lines (without timestamps or LRC headers)
  /// for previewing inside the "Ganti Lirik" selector.
  String get previewTwoLines {
    final raw = hasSynced ? syncedLyrics! : (plainLyrics ?? '');
    if (raw.trim().isEmpty) return '';
    final stripped = RomajiService.stripTimestamps(raw);
    final lines = stripped
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(2)
        .toList();
    return lines.join('\n');
  }

  LyricsResult toLyricsResult() => LyricsResult(
        syncedLyrics: syncedLyrics,
        plainLyrics: plainLyrics,
      );
}

class LyricsSearchResponse {
  final LyricsResult bestResult;
  final List<LyricsCandidate> candidates;
  final LyricsCandidate? selectedCandidate;

  const LyricsSearchResponse({
    required this.bestResult,
    required this.candidates,
    this.selectedCandidate,
  });
}

class LyricsService {
  final Dio _dio;

  LyricsService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
                headers: const {
                  'User-Agent':
                      'MusEvee/4.9.0 (https://github.com/hdkmjr12/MusEvee)',
                  'Accept': 'application/json',
                },
              ),
            );

  static const Set<String> _commonEnglishWords = {
    'the', 'you', 'and', 'with', 'that', 'this', 'from', 'have', 'your',
    'for', 'not', 'are', 'was', 'were', 'will', 'would', 'could', 'should',
    "couldn't", "don't", "can't", "won't", "isn't", "i'm", "you're", "it's",
    'know', 'like', 'love', 'heart', 'smile', 'eyes', 'world', 'night',
    'never', 'always', 'every', 'about', 'what', 'when', 'where', 'there',
    'their', 'they', 'even', 'just', 'into', 'out', 'down', 'make', 'take',
    'want', 'need', 'feel', 'time', 'life', 'away', 'back', 'through',
  };

  /// Automatically classifies a lyrics text into one of:
  /// - `[Jepang/Kanji]`
  /// - `[Romaji]`
  /// - `[Bilingual]`
  /// - `[Inggris/Lainnya]`
  static String classifyLyricsLanguage(String rawLyrics) {
    final stripped = RomajiService.stripTimestamps(rawLyrics);
    if (stripped.isEmpty) return '[Inggris/Lainnya]';

    final lines = stripped
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '[Inggris/Lainnya]';

    int jpLines = 0;
    int latinLines = 0;
    int romajiLines = 0;
    int inlineBilingualLines = 0;

    for (final line in lines) {
      if (RomajiService.containsJapanese(line)) {
        jpLines++;
        // Check if this Japanese line also has an inline Romaji/English half
        final latinChars =
            RegExp(r'[a-zA-Z]').allMatches(line).length;
        if (latinChars >= 16 &&
            (line.contains(' / ') ||
                line.contains(' | ') ||
                line.contains(' - '))) {
          inlineBilingualLines++;
        }
      } else if (RegExp(r'[a-zA-Z]').hasMatch(line)) {
        latinLines++;
        if (RomajiService.isRomajiText(line)) {
          romajiLines++;
        }
      }
    }

    if (jpLines > 0) {
      if (inlineBilingualLines >= 3 ||
          (latinLines >= 3 && latinLines >= (jpLines * 0.35))) {
        return '[Bilingual]';
      }
      return '[Jepang/Kanji]';
    }

    if (romajiLines >= 2 &&
        (romajiLines / (latinLines > 0 ? latinLines : 1) >= 0.25)) {
      return '[Romaji]';
    }
    if (RomajiService.isRomajiText(stripped)) {
      return '[Romaji]';
    }

    return '[Inggris/Lainnya]';
  }

  /// Counts how many common English words appear in [rawLyrics].
  static int countEnglishIndicators(String rawLyrics) {
    final stripped = RomajiService.stripTimestamps(rawLyrics).toLowerCase();
    if (stripped.isEmpty) return 0;
    final words = stripped
        .replaceAll(RegExp(r"[^a-z\s']"), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    int count = 0;
    for (final w in words) {
      if (_commonEnglishWords.contains(w)) {
        count++;
      }
    }
    return count;
  }

  /// Queries LRCLIB Public API and returns an updated [TrackMetadata] using
  /// language-prioritized candidate selection.
  /// Never throws on missing lyrics or network errors so downloads can proceed.
  Future<TrackMetadata> enrichWithLyrics(
    TrackMetadata metadata, {
    String? targetFolder,
  }) async {
    debugPrint(
      '[AUTO_E2E] TAHAP_3: Mencari lirik di LRCLIB untuk "${metadata.artist} - ${metadata.title}" (${metadata.durationSeconds}s)...',
    );
    try {
      final response = await fetchLyricsWithCandidates(
        trackName: metadata.title,
        artistName: metadata.artist,
        albumName: metadata.album,
        durationSeconds: metadata.durationSeconds,
        targetFolder: targetFolder,
      );

      final result = response.bestResult;
      debugPrint(
        '[AUTO_E2E] TAHAP_3: Hasil LRCLIB -> hasSynced=${result.hasSynced}, hasPlain=${result.hasPlain}, kandidat=${response.candidates.length}',
      );

      return metadata.copyWith(
        syncedLyrics: result.syncedLyrics,
        plainLyrics: result.plainLyrics,
      );
    } catch (e, s) {
      debugPrint(
        '[AUTO_E2E] TAHAP_3: Error LRCLIB ditangkap dengan aman (lanjut tanpa lirik): $e\n$s',
      );
      return metadata;
    }
  }

  /// Fetches `syncedLyrics` (primary) and `plainLyrics` (fallback) from LRCLIB
  /// with automatic Japanese/Romaji original lyrics prioritization.
  Future<LyricsResult> fetchLyrics({
    required String trackName,
    required String artistName,
    required String albumName,
    required int durationSeconds,
    String? targetFolder,
  }) async {
    final response = await fetchLyricsWithCandidates(
      trackName: trackName,
      artistName: artistName,
      albumName: albumName,
      durationSeconds: durationSeconds,
      targetFolder: targetFolder,
    );
    return response.bestResult;
  }

  /// Fetches all matching LRCLIB candidates, classifies their language tags
  /// (`[Jepang/Kanji]`, `[Romaji]`, `[Bilingual]`, `[Inggris/Lainnya]`),
  /// scores them by duration proximity, synced availability, and original
  /// language priority, and returns both the best result and the candidate list.
  Future<LyricsSearchResponse> fetchLyricsWithCandidates({
    required String trackName,
    required String artistName,
    required String albumName,
    required int durationSeconds,
    String? targetFolder,
  }) async {
    final rawMaps = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    void addRawMap(Map<String, dynamic>? map) {
      if (map == null) return;
      final synced = _nonEmptyString(map['syncedLyrics']);
      final plain = _nonEmptyString(map['plainLyrics']);
      if (synced == null && plain == null) return;
      final id = (map['id']?.toString() ?? '').trim();
      if (id.isNotEmpty) {
        if (!seenIds.add(id)) return;
      }
      rawMaps.add(map);
    }

    final primaryArtist = artistName.split(',').first.trim();
    final cleanTrack = trackName
        .replaceAll(
          RegExp(
            r'\s*[\(\[](feat\.?|ft\.?|with\s).*?[\)\]]',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    // Run /api/get and /api/search in parallel so we always see all language versions
    final futures = <Future<void>>[
      // 1. /api/get
      () async {
        try {
          final queryParams = <String, dynamic>{
            'track_name': trackName,
            'artist_name': artistName,
          };
          if (albumName.trim().isNotEmpty) {
            queryParams['album_name'] = albumName;
          }
          if (durationSeconds > 0) {
            queryParams['duration'] = durationSeconds;
          }
          final response = await _dio
              .get<dynamic>(
                'https://lrclib.net/api/get',
                queryParameters: queryParams,
              )
              .timeout(const Duration(seconds: 9));
          addRawMap(_ensureMap(response.data));
        } catch (_) {}
      }(),
      // 2. /api/search?track_name=...&artist_name=...
      () async {
        try {
          final response = await _dio
              .get<dynamic>(
                'https://lrclib.net/api/search',
                queryParameters: {
                  'track_name': cleanTrack,
                  'artist_name': primaryArtist,
                },
              )
              .timeout(const Duration(seconds: 9));
          for (final item in _ensureList(response.data)) {
            addRawMap(_ensureMap(item));
          }
        } catch (_) {}
      }(),
      // 3. /api/search?q={artist} {track}
      () async {
        try {
          final response = await _dio
              .get<dynamic>(
                'https://lrclib.net/api/search',
                queryParameters: {'q': '$primaryArtist $cleanTrack'},
              )
              .timeout(const Duration(seconds: 9));
          for (final item in _ensureList(response.data)) {
            addRawMap(_ensureMap(item));
          }
        } catch (_) {}
      }(),
    ];

    await Future.wait(futures);

    // Determine whether the user explicitly wants an English version
    final explicitlyWantsEnglish = RegExp(
      r'\b(english\s*ver|eng\s*ver|english\s*version|english\s*cover)\b',
      caseSensitive: false,
    ).hasMatch(trackName);

    // Pre-classify all gathered items
    final classifiedItems = <({Map<String, dynamic> map, String tag, int duration, int diff})>[];
    bool hasJapaneseOrRomajiInPool = false;

    for (final map in rawMaps) {
      final synced = _nonEmptyString(map['syncedLyrics']);
      final plain = _nonEmptyString(map['plainLyrics']);
      final sampleText = synced ?? plain ?? '';
      final tag = classifyLyricsLanguage(sampleText);
      final itemDuration = _parseDuration(map['duration']);
      final diff = (durationSeconds > 0 && itemDuration > 0)
          ? (itemDuration - durationSeconds).abs()
          : 999;

      if ((tag == '[Jepang/Kanji]' ||
              tag == '[Bilingual]' ||
              tag == '[Romaji]') &&
          (durationSeconds <= 0 || diff <= 12)) {
        hasJapaneseOrRomajiInPool = true;
      }

      classifiedItems.add((
        map: map,
        tag: tag,
        duration: itemDuration,
        diff: diff,
      ));
    }

    final metadataHasJapanese = RomajiService.containsJapanese(trackName) ||
        RomajiService.containsJapanese(artistName) ||
        RomajiService.containsJapanese(albumName);
    final folderIsJapan =
        (targetFolder ?? '').toLowerCase().contains('japan');
    final shouldPreferJapanese = !explicitlyWantsEnglish &&
        (metadataHasJapanese || folderIsJapan || hasJapaneseOrRomajiInPool);

    final candidates = <LyricsCandidate>[];
    final seenSignatures = <String>{};

    for (int idx = 0; idx < classifiedItems.length; idx++) {
      final entry = classifiedItems[idx];
      final map = entry.map;
      final tag = entry.tag;
      final itemDuration = entry.duration;
      final diff = entry.diff;

      // Skip tracks whose duration is wildly off (> 25s) when we have a known target duration
      if (durationSeconds > 0 && itemDuration > 0 && diff > 25) {
        continue;
      }

      final synced = _nonEmptyString(map['syncedLyrics']);
      final plain = _nonEmptyString(map['plainLyrics']);
      final rawText = synced ?? plain ?? '';

      // Deduplicate near-identical lyrics uploads while keeping distinct language/sync modes
      final normSig = RomajiService.normalizeForComparison(
        RomajiService.stripTimestamps(rawText),
      );
      final shortSig = normSig.length > 90 ? normSig.substring(0, 90) : normSig;
      final dedupKey = '$tag|${synced != null}|$shortSig';
      if (shortSig.isNotEmpty && !seenSignatures.add(dedupKey)) {
        continue;
      }

      int score = 0;

      // 1. Duration match priority (<= 3s gets top score)
      if (durationSeconds > 0 && itemDuration > 0) {
        if (diff <= 1) {
          score += 420;
        } else if (diff <= 3) {
          score += 390;
        } else if (diff <= 6) {
          score += 270;
        } else if (diff <= 12) {
          score += 140;
        } else {
          score -= diff * 10;
        }
      }

      // 2. Synced lyrics availability
      if (synced != null) {
        score += 260;
      } else if (plain != null) {
        score += 80;
      }

      // 3. Language priority
      if (explicitlyWantsEnglish) {
        if (tag == '[Inggris/Lainnya]') {
          score += 450;
        }
      } else if (shouldPreferJapanese) {
        if (tag == '[Jepang/Kanji]') {
          score += 520;
        } else if (tag == '[Bilingual]') {
          score += 430;
        } else if (tag == '[Romaji]') {
          score += 390;
        } else if (tag == '[Inggris/Lainnya]') {
          final engHits = countEnglishIndicators(rawText);
          score -= (engHits >= 5) ? 350 : 200;
        }
      }

      final id = (map['id']?.toString() ?? 'cand_$idx').trim();
      candidates.add(
        LyricsCandidate(
          id: id.isEmpty ? 'cand_$idx' : id,
          trackName: (map['trackName']?.toString() ?? trackName).trim(),
          artistName: (map['artistName']?.toString() ?? artistName).trim(),
          albumName: (map['albumName']?.toString() ?? albumName).trim(),
          durationSeconds: itemDuration > 0 ? itemDuration : durationSeconds,
          syncedLyrics: synced,
          plainLyrics: plain ??
              (synced != null ? RomajiService.stripTimestamps(synced) : null),
          languageTag: tag,
          score: score,
        ),
      );
    }

    // Sort descending by score
    candidates.sort((a, b) => b.score.compareTo(a.score));

    if (candidates.isNotEmpty) {
      final best = candidates.first;
      return LyricsSearchResponse(
        bestResult: best.toLyricsResult(),
        candidates: candidates,
        selectedCandidate: best,
      );
    }

    // Fallback C: GET https://api.lyrics.ovh/v1/{artist}/{title}
    try {
      final encodedArtist = Uri.encodeComponent(primaryArtist);
      final encodedTrack = Uri.encodeComponent(cleanTrack);
      final ovhResp = await _dio
          .get<dynamic>(
            'https://api.lyrics.ovh/v1/$encodedArtist/$encodedTrack',
          )
          .timeout(const Duration(seconds: 8));
      final map = _ensureMap(ovhResp.data);
      final ovhLyrics = _nonEmptyString(map?['lyrics']);
      if (ovhLyrics != null) {
        debugPrint('[AUTO_E2E] TAHAP_3: Lirik plain ditemukan via lyrics.ovh');
        final tag = classifyLyricsLanguage(ovhLyrics);
        final cand = LyricsCandidate(
          id: 'ovh_fallback',
          trackName: trackName,
          artistName: artistName,
          albumName: albumName,
          durationSeconds: durationSeconds,
          plainLyrics: ovhLyrics,
          languageTag: tag,
          score: 100,
        );
        return LyricsSearchResponse(
          bestResult: cand.toLyricsResult(),
          candidates: [cand],
          selectedCandidate: cand,
        );
      }
    } catch (e) {
      debugPrint('[AUTO_E2E] TAHAP_3: Fallback lyrics.ovh gagal: $e');
    }

    return const LyricsSearchResponse(
      bestResult: LyricsResult(),
      candidates: [],
    );
  }

  int _parseDuration(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) {
      final parsedDouble = double.tryParse(value);
      if (parsedDouble != null) return parsedDouble.round();
    }
    return 0;
  }

  String? _nonEmptyString(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    return str.isNotEmpty ? str : null;
  }

  Map<String, dynamic>? _ensureMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  List<dynamic> _ensureList(dynamic data) {
    if (data is List) return data;
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is List) return decoded;
      } catch (_) {}
    }
    return const [];
  }
}

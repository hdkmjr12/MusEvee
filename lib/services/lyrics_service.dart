import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/track_metadata.dart';

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
                      'SpotMetaDownloader/1.0.0 (https://github.com/spotmeta)',
                  'Accept': 'application/json',
                },
              ),
            );

  /// Queries LRCLIB Public API (`https://lrclib.net/api/get` with fallback to
  /// `https://lrclib.net/api/search`) and returns an updated [TrackMetadata].
  /// Never throws on missing lyrics or network errors so downloads can proceed.
  Future<TrackMetadata> enrichWithLyrics(TrackMetadata metadata) async {
    debugPrint(
      '[AUTO_E2E] TAHAP_3: Mencari lirik di LRCLIB untuk "${metadata.artist} - ${metadata.title}" (${metadata.durationSeconds}s)...',
    );
    try {
      final result = await fetchLyrics(
        trackName: metadata.title,
        artistName: metadata.artist,
        albumName: metadata.album,
        durationSeconds: metadata.durationSeconds,
      );

      debugPrint(
        '[AUTO_E2E] TAHAP_3: Hasil LRCLIB -> hasSynced=${result.hasSynced}, hasPlain=${result.hasPlain}',
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

  /// Fetches `syncedLyrics` (primary) and `plainLyrics` (fallback) from LRCLIB.
  Future<LyricsResult> fetchLyrics({
    required String trackName,
    required String artistName,
    required String albumName,
    required int durationSeconds,
  }) async {
    // 1. Primary attempt: GET https://lrclib.net/api/get
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
          .timeout(const Duration(seconds: 10));

      final parsed = _extractFromItem(response.data);
      if (parsed.hasAny) {
        debugPrint('[AUTO_E2E] TAHAP_3: Lirik ditemukan via /api/get');
        return parsed;
      }
    } catch (e) {
      debugPrint('[AUTO_E2E] TAHAP_3: /api/get tidak cocok ($e), mencoba fallback /api/search...');
    }

    // 2. Fallback A: GET https://lrclib.net/api/search with track_name & artist_name
    try {
      final searchParams = <String, dynamic>{
        'track_name': trackName,
        'artist_name': artistName,
      };
      if (albumName.trim().isNotEmpty) {
        searchParams['album_name'] = albumName;
      }

      final response = await _dio
          .get<dynamic>(
            'https://lrclib.net/api/search',
            queryParameters: searchParams,
          )
          .timeout(const Duration(seconds: 10));

      final best = _pickBestFromSearchList(response.data, durationSeconds);
      if (best.hasAny) {
        debugPrint('[AUTO_E2E] TAHAP_3: Lirik ditemukan via /api/search (spesifik)');
        return best;
      }
    } catch (e) {
      debugPrint('[AUTO_E2E] TAHAP_3: /api/search spesifik gagal ($e), mencoba query umum...');
    }

    // 3. Fallback B: GET https://lrclib.net/api/search?q={artist} {track}
    try {
      final primaryArtist = artistName.split(',').first.trim();
      final cleanTrack = trackName
          .replaceAll(
            RegExp(r'\s*[\(\[](feat\.?|ft\.?|with\s).*?[\)\]]',
                caseSensitive: false),
            '',
          )
          .trim();

      final response = await _dio
          .get<dynamic>(
            'https://lrclib.net/api/search',
            queryParameters: {'q': '$primaryArtist $cleanTrack'},
          )
          .timeout(const Duration(seconds: 10));

      final best = _pickBestFromSearchList(response.data, durationSeconds);
      if (best.hasAny) {
        debugPrint('[AUTO_E2E] TAHAP_3: Lirik ditemukan via /api/search?q=');
        return best;
      }
    } catch (e, s) {
      debugPrint('[AUTO_E2E] TAHAP_3: /api/search?q= gagal: $e\n$s');
    }

    // 4. Fallback C: GET https://api.lyrics.ovh/v1/{artist}/{title}
    try {
      final primaryArtist = artistName.split(',').first.trim();
      final cleanTrack = trackName
          .replaceAll(
            RegExp(r'\s*[\(\[](feat\.?|ft\.?|with\s).*?[\)\]]',
                caseSensitive: false),
            '',
          )
          .trim();
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
        return LyricsResult(plainLyrics: ovhLyrics);
      }
    } catch (e) {
      debugPrint('[AUTO_E2E] TAHAP_3: Fallback lyrics.ovh gagal: $e');
    }

    return const LyricsResult();
  }

  LyricsResult _extractFromItem(dynamic raw) {
    final map = _ensureMap(raw);
    if (map == null) return const LyricsResult();

    final synced = _nonEmptyString(map['syncedLyrics']);
    final plain = _nonEmptyString(map['plainLyrics']);

    return LyricsResult(
      syncedLyrics: synced,
      plainLyrics: plain,
    );
  }

  LyricsResult _pickBestFromSearchList(dynamic rawList, int targetDuration) {
    final list = _ensureList(rawList);
    if (list.isEmpty) return const LyricsResult();

    Map<String, dynamic>? bestSyncedMatch;
    int bestSyncedDiff = 999999;

    Map<String, dynamic>? bestPlainMatch;
    int bestPlainDiff = 999999;

    for (final item in list) {
      final map = _ensureMap(item);
      if (map == null) continue;

      final synced = _nonEmptyString(map['syncedLyrics']);
      final plain = _nonEmptyString(map['plainLyrics']);
      final itemDuration = _parseDuration(map['duration']);
      final diff = (targetDuration > 0 && itemDuration > 0)
          ? (itemDuration - targetDuration).abs()
          : 999;

      if (synced != null) {
        if (bestSyncedMatch == null || diff < bestSyncedDiff) {
          bestSyncedMatch = map;
          bestSyncedDiff = diff;
        }
      } else if (plain != null) {
        if (bestPlainMatch == null || diff < bestPlainDiff) {
          bestPlainMatch = map;
          bestPlainDiff = diff;
        }
      }
    }

    final chosen = bestSyncedMatch ?? bestPlainMatch;
    if (chosen == null) return const LyricsResult();

    return _extractFromItem(chosen);
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

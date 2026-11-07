import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import '../models/track_metadata.dart';

class MetadataException implements Exception {
  final String message;
  const MetadataException(this.message);

  @override
  String toString() => message;
}

class SpotifyCollectionResult {
  final String title;
  final String subtitle;
  final String coverUrl;
  final String collectionType; // 'album' or 'playlist'
  final List<TrackMetadata> tracks;

  const SpotifyCollectionResult({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.collectionType,
    required this.tracks,
  });
}

class MetadataService {
  final Dio _dio;

  MetadataService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
                headers: const {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                  'Accept-Language': 'en-US,en;q=0.9',
                },
              ),
            );

  /// Checks whether [rawInput] contains a Spotify track URL or URI.
  bool isSpotifyInput(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return false;
    if (RegExp(r'spotify:track:[a-zA-Z0-9]{15,30}').hasMatch(trimmed)) {
      return true;
    }
    return RegExp(
      r'https?://(?:open\.)?spotify\.com/(?:intl-[a-z-]+/)?track/[a-zA-Z0-9]+',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }

  /// Checks whether [rawInput] contains a Spotify Album or Playlist URL/URI.
  bool isSpotifyCollectionInput(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return false;
    if (RegExp(r'spotify:(?:album|playlist):[a-zA-Z0-9]{15,30}')
        .hasMatch(trimmed)) {
      return true;
    }
    return RegExp(
      r'https?://(?:open\.)?spotify\.com/(?:intl-[a-z-]+/)?(?:album|playlist)/[a-zA-Z0-9]+',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }

  /// Extracts a Spotify URL from shared text (e.g. "Listen on Spotify: https://open.spotify.com/track/...")
  /// or returns the trimmed input.
  String extractUrlFromSharedText(String rawInput) {
    final trimmed = rawInput.trim();
    final urlMatch = RegExp(
      r'https?://(?:open\.)?spotify\.com/[^\s]+',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (urlMatch != null) {
      return urlMatch.group(0)!.trim();
    }
    final uriMatch = RegExp(
      r'spotify:(?:track|album|playlist):[a-zA-Z0-9]{15,30}',
    ).firstMatch(trimmed);
    if (uriMatch != null) {
      return uriMatch.group(0)!.trim();
    }
    return trimmed;
  }

  /// Extracts a full track list from a public Spotify Album or Playlist link
  /// using Spotify's public embed page (`__NEXT_DATA__`) + Deezer enrichment.
  Future<SpotifyCollectionResult> fetchAlbumOrPlaylist(String rawInput) async {
    final extracted = extractUrlFromSharedText(rawInput);
    String collectionType = 'album';
    String collectionId = '';

    final uriMatch = RegExp(
      r'spotify:(album|playlist):([a-zA-Z0-9]{15,30})',
      caseSensitive: false,
    ).firstMatch(extracted);

    if (uriMatch != null) {
      collectionType = uriMatch.group(1)!.toLowerCase();
      collectionId = uriMatch.group(2)!;
    } else {
      final urlMatch = RegExp(
        r'spotify\.com/(?:intl-[a-z-]+/)?(album|playlist)/([a-zA-Z0-9]{15,30})',
        caseSensitive: false,
      ).firstMatch(extracted);
      if (urlMatch != null) {
        collectionType = urlMatch.group(1)!.toLowerCase();
        collectionId = urlMatch.group(2)!;
      }
    }

    if (collectionId.isEmpty) {
      throw const MetadataException(
        'Link Album atau Playlist Spotify tidak valid.',
      );
    }

    final embedUrl =
        'https://open.spotify.com/embed/$collectionType/$collectionId';
    final canonicalCollectionUrl =
        'https://open.spotify.com/$collectionType/$collectionId';

    String collectionTitle =
        collectionType == 'album' ? 'Spotify Album' : 'Spotify Playlist';
    String collectionSubtitle = '';
    String collectionCover = '';
    String releaseYear = DateTime.now().year.toString();
    final tracks = <TrackMetadata>[];

    // 1. Parse Spotify Embed __NEXT_DATA__ JSON
    try {
      final resp = await _dio
          .get<String>(
            embedUrl,
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(const Duration(seconds: 15));

      final htmlStr = resp.data ?? '';
      if (htmlStr.isNotEmpty) {
        final doc = html_parser.parse(htmlStr);
        final nextScript = doc.querySelector('script#__NEXT_DATA__');
        final jsonText = nextScript?.text.trim() ?? '';
        if (jsonText.isNotEmpty) {
          final root = _ensureMap(jsonText);
          final props = _ensureMap(root?['props']);
          final pageProps = _ensureMap(props?['pageProps']);
          final state = _ensureMap(pageProps?['state']);
          final data = _ensureMap(state?['data']);
          final entity = _ensureMap(data?['entity']);

            if (entity != null) {
            final name = _cleanCollectionTitle(
              (entity['title'] ?? entity['name'] ?? '').toString().trim(),
            );
            if (name.isNotEmpty) collectionTitle = name;

            final sub = (entity['subtitle'] ?? '').toString().trim();
            if (sub.isNotEmpty) collectionSubtitle = sub;

            final releaseDate = _ensureMap(entity['releaseDate']);
            final isoString =
                (releaseDate?['isoString'] ?? entity['release_date'] ?? '')
                    .toString();
            final parsedYr = _extractYear(isoString);
            if (parsedYr.isNotEmpty) releaseYear = parsedYr;

            final coverArt = _ensureMap(entity['coverArt']);
            final sources = coverArt?['sources'] ??
                _ensureMap(entity['images'])?['items'] ??
                entity['images'];
            if (sources is List && sources.isNotEmpty) {
              for (final src in sources) {
                final srcMap = _ensureMap(src);
                final url = (srcMap?['url'] ?? '').toString().trim();
                if (url.isNotEmpty) {
                  collectionCover = url;
                  break;
                }
              }
            }

            final rawTrackList = entity['trackList'];
            if (rawTrackList is List) {
              for (final item in rawTrackList) {
                final tMap = _ensureMap(item);
                if (tMap == null) continue;

                final tTitle =
                    (tMap['title'] ?? tMap['name'] ?? '').toString().trim();
                if (tTitle.isEmpty) continue;

                String tArtist = (tMap['subtitle'] ?? '').toString().trim();
                if (tArtist.isEmpty) {
                  tArtist = collectionSubtitle.isNotEmpty
                      ? collectionSubtitle
                      : 'Spotify Artist';
                }
                // Replace non-breaking space in Spotify embed artist strings
                tArtist = tArtist.replaceAll('\u00A0', ' ').trim();

                final durMs = _parseInt(tMap['duration']);
                final durSec = durMs > 0 ? (durMs / 1000).round() : 200;

                final uriStr = (tMap['uri'] ?? '').toString().trim();
                String trackUrl = canonicalCollectionUrl;
                final tidMatch =
                    RegExp(r'spotify:track:([a-zA-Z0-9]+)').firstMatch(uriStr);
                if (tidMatch != null) {
                  trackUrl =
                      'https://open.spotify.com/track/${tidMatch.group(1)}';
                }

                final audioPreview = _ensureMap(tMap['audioPreview']);
                final previewUrl =
                    (audioPreview?['url'] ?? '').toString().trim();

                tracks.add(
                  TrackMetadata(
                    spotifyUrl: trackUrl,
                    title: tTitle,
                    artist: tArtist,
                    album: collectionType == 'album' ? collectionTitle : tTitle,
                    releaseYear: releaseYear,
                    durationSeconds: durSec,
                    coverUrl: collectionCover,
                    previewAudioUrl: previewUrl.isNotEmpty ? previewUrl : null,
                  ),
                );
              }
            }
          }
        }
        if (collectionTitle == 'Spotify Album' ||
            collectionTitle == 'Spotify Playlist') {
          final ogTitle = doc
                  .querySelector('meta[property="og:title"]')
                  ?.attributes['content'] ??
              doc.querySelector('title')?.text ??
              '';
          final cleanedOg = _cleanCollectionTitle(ogTitle);
          if (cleanedOg.isNotEmpty) {
            collectionTitle = cleanedOg;
          }
        }
      }
    } catch (e) {
      debugPrint('[AUTO_E2E] Embed ekstraksi $collectionType gagal: $e');
    }

    // 2. Enrich title via oEmbed if still generic, or fallback track list if empty
    if (tracks.isEmpty ||
        collectionTitle == 'Spotify Album' ||
        collectionTitle == 'Spotify Playlist') {
      try {
        final oembedResp = await _dio.get<dynamic>(
          'https://open.spotify.com/oembed',
          queryParameters: {'url': canonicalCollectionUrl},
        );
        final oData = _ensureMap(oembedResp.data);
        if (oData != null) {
          final oTitle = _cleanCollectionTitle(
            (oData['title'] ?? '').toString().trim(),
          );
          final oThumb = (oData['thumbnail_url'] ?? '').toString().trim();
          if (oTitle.isNotEmpty) collectionTitle = oTitle;
          if (oThumb.isNotEmpty && collectionCover.isEmpty) {
            collectionCover = oThumb;
          }
        }
      } catch (_) {}

      if (tracks.isEmpty && collectionTitle.isNotEmpty) {
        final fallbackTracks = await searchMusicTracks(
          '$collectionSubtitle $collectionTitle'.trim(),
        );
        tracks.addAll(fallbackTracks);
      }
    }

    if (tracks.isEmpty) {
      throw const MetadataException(
        'Tidak dapat mengekstrak daftar lagu dari link Album/Playlist tersebut.',
      );
    }

    return SpotifyCollectionResult(
      title: collectionTitle,
      subtitle: collectionSubtitle,
      coverUrl: collectionCover,
      collectionType: collectionType,
      tracks: tracks,
    );
  }

  String _cleanCollectionTitle(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    s = s
        .replaceFirst(RegExp(r'\s*[|\-–—]\s*Spotify\s*$', caseSensitive: false), '')
        .replaceFirst(
          RegExp(r'\s*-\s*(?:playlist|album)\s+by\s+.+$', caseSensitive: false),
          '',
        )
        .trim();
    return s;
  }

  /// Alias for [searchMusicTracks] for cross-script & multi-region catalog search.
  Future<List<TrackMetadata>> searchTracks(String rawQuery) =>
      searchMusicTracks(rawQuery);

  /// Searches music tracks directly by keyword (Western, Indonesian, Romaji J-Pop/Anime, Kanji/Kana)
  /// using a Multi-Source & Cross-Script Search Engine:
  /// 1. Automatic Romaji -> Kanji/Kana query expansion (`Google Input Tools ja-t-i0-und` + `Google Translate gtx`)
  /// 2. Parallel Multi-Region queries (`Future.wait`):
  ///    - iTunes Japan (`country=JP&lang=ja_jp`) with original + Kanji/Kana expanded queries
  ///    - iTunes Global/Indonesia (`country=ID`)
  ///    - Deezer Public Search API (`cover_xl` 1000x1000) with original + expanded queries
  /// 3. Smart cross-script relevance ranking & deduplication (penalizing orgel/karaoke/music-box covers).
  Future<List<TrackMetadata>> searchMusicTracks(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      throw const MetadataException('Kata kunci pencarian tidak boleh kosong.');
    }

    debugPrint('[MusEvee] SEARCH: Mencari lagu untuk kata kunci: "$query"');

    // Step 1: Expand Latin/Romaji query into Kanji/Kana equivalents (e.g. "heikousen sayuri" -> "平行線 さユり")
    final expansion = await expandRomajiQueryForJapanese(query);
    final jaQueries = expansion.expandedQueries;
    if (jaQueries.isNotEmpty) {
      debugPrint(
        '[MusEvee] SEARCH: Ekspansi Romaji -> Kanji/Kana: ${jaQueries.join(" | ")}',
      );
    }

    // Step 2: Run multi-region iTunes (JP + Global/ID) & Deezer searches in parallel
    final searchFutures = <Future<_CatalogBatch>>[
      _searchItunesCatalog(
        query,
        country: 'ID',
        limit: 15,
      ).then((list) => _CatalogBatch(tracks: list, isItunes: true, boost: 8)),
      _searchDeezerCatalog(
        query,
        limit: 15,
      ).then((list) => _CatalogBatch(tracks: list, isItunes: false, boost: 10)),
      _searchItunesCatalog(
        query,
        country: 'JP',
        lang: 'ja_jp',
        limit: 15,
      ).then((list) => _CatalogBatch(tracks: list, isItunes: true, boost: 6)),
    ];

    for (final jaQ in jaQueries.take(2)) {
      searchFutures.add(
        _searchItunesCatalog(
          jaQ,
          country: 'JP',
          lang: 'ja_jp',
          limit: 15,
        ).then((list) => _CatalogBatch(tracks: list, isItunes: true, boost: 12)),
      );
      searchFutures.add(
        _searchDeezerCatalog(
          jaQ,
          limit: 10,
        ).then((list) => _CatalogBatch(tracks: list, isItunes: false, boost: 8)),
      );
    }

    final batches = await Future.wait<_CatalogBatch>(searchFutures);

    // Index true release years & high-res covers from iTunes batches
    final itunesYearMap = <String, String>{};
    final itunesCoverMap = <String, String>{};
    final itunesPreviewMap = <String, String>{};
    for (final batch in batches) {
      if (!batch.isItunes) continue;
      for (final t in batch.tracks) {
        final key = _dedupTrackKey(t.artist, t.title);
        if (t.releaseYear.isNotEmpty && !itunesYearMap.containsKey(key)) {
          itunesYearMap[key] = t.releaseYear;
        }
        if (t.coverUrl.isNotEmpty && !itunesCoverMap.containsKey(key)) {
          itunesCoverMap[key] = t.coverUrl;
        }
        if (t.previewAudioUrl != null &&
            t.previewAudioUrl!.isNotEmpty &&
            !itunesPreviewMap.containsKey(key)) {
          itunesPreviewMap[key] = t.previewAudioUrl!;
        }
      }
    }

    // Merge, enrich, deduplicate, and score candidates
    final candidatesByKey = <String, _ScoredSearchTrack>{};
    int sequenceCounter = 0;

    for (final batch in batches) {
      for (int idx = 0; idx < batch.tracks.length; idx++) {
        var track = batch.tracks[idx];
        final normKey = _dedupTrackKey(track.artist, track.title);

        if (!batch.isItunes) {
          final realYear = itunesYearMap[normKey];
          if (realYear != null && realYear.isNotEmpty) {
            track = track.copyWith(releaseYear: realYear);
          }
          if (track.coverUrl.isEmpty && itunesCoverMap.containsKey(normKey)) {
            track = track.copyWith(coverUrl: itunesCoverMap[normKey]);
          }
          if ((track.previewAudioUrl == null ||
                  track.previewAudioUrl!.isEmpty) &&
              itunesPreviewMap.containsKey(normKey)) {
            track = track.copyWith(previewAudioUrl: itunesPreviewMap[normKey]);
          }
        }

        final score = _scoreTrackRelevance(
          track: track,
          rawQuery: query,
          expansion: expansion,
          rankInSource: idx,
          sourceBoost: batch.boost,
        );

        final existing = candidatesByKey[normKey];
        if (existing == null) {
          candidatesByKey[normKey] = _ScoredSearchTrack(
            track: track,
            score: score,
            order: sequenceCounter++,
          );
        } else if (score > existing.score) {
          candidatesByKey[normKey] = _ScoredSearchTrack(
            track: track,
            score: score,
            order: existing.order,
          );
        }
      }
    }

    final ranked = candidatesByKey.values.toList()
      ..sort((a, b) {
        final cmp = b.score.compareTo(a.score);
        if (cmp != 0) return cmp;
        return a.order.compareTo(b.order);
      });

    if (ranked.isEmpty) {
      throw MetadataException(
        'Tidak ditemukan lagu untuk kata kunci "$query". Coba gunakan nama artis dan judul lagu.',
      );
    }

    return ranked.take(25).map((e) => e.track).toList();
  }

  static final RegExp _japaneseScriptRegex = RegExp(
    r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]',
  );

  static final RegExp _coverNoiseRegex = RegExp(
    r'(\borgel\b|オルゴール|music\s*box|originally\s+performed\s+by|\bkaraoke\b|カラオケ|\btribute\b|\b8-?bit\b|\bringtone\b|off\s*vocal|inst\.?\s*ver)',
    caseSensitive: false,
  );

  /// Expands Latin/Romaji keywords into Japanese Kanji/Kana equivalents using
  /// Google Input Tools (`ja-t-i0-und`) + Google Translate (`gtx`) in parallel.
  @visibleForTesting
  Future<RomajiQueryExpansion> expandRomajiQueryForJapanese(
    String rawQuery,
  ) async {
    final cleaned = rawQuery
        .replaceAll(RegExp(r'[\-—–/|,:;()\[\]]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final rawTokens = cleaned
        .split(' ')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final tokenVariants = <Set<String>>[
      for (final tok in rawTokens) {tok.toLowerCase()},
    ];

    if (cleaned.isEmpty || !RegExp(r'[a-zA-Z]').hasMatch(cleaned)) {
      return RomajiQueryExpansion(
        originalTokens: rawTokens,
        tokenVariantGroups: tokenVariants,
        expandedQueries: const [],
      );
    }

    // Run whole-phrase IME, per-token IME, and GTX transliteration/translation in parallel
    final futures = <Future<void>>[];
    final phraseCandidates = <String>[];
    String? gtxCandidate;

    // 1. Whole-phrase Google Input Tools Japanese IME (`heikousen sayuri` -> `平行線 さユり`)
    futures.add(() async {
      try {
        final resp = await _dio
            .get<dynamic>(
              'https://inputtools.google.com/request',
              queryParameters: {
                'text': cleaned.toLowerCase(),
                'itc': 'ja-t-i0-und',
                'num': 4,
              },
            )
            .timeout(const Duration(milliseconds: 3500));
        final parsed = _parseGoogleImeResponse(resp.data);
        if (parsed.isNotEmpty && parsed.first.isNotEmpty) {
          for (final cand in parsed.first) {
            final norm = cand.replaceAll('\u3000', ' ').trim();
            if (norm.isNotEmpty && _japaneseScriptRegex.hasMatch(norm)) {
              phraseCandidates.add(norm);
            }
          }
        }
      } catch (_) {}
    }());

    // 2. Per-token Google Input Tools Japanese IME (`heikousen,sayuri` -> `["平行線", ...]`, `["さユり", ...]`)
    if (rawTokens.isNotEmpty && rawTokens.length <= 6) {
      futures.add(() async {
        try {
          final latinIdx = <int>[];
          final latinWords = <String>[];
          for (int i = 0; i < rawTokens.length; i++) {
            if (RegExp(r'^[a-zA-Z0-9\x27]+$').hasMatch(rawTokens[i])) {
              latinIdx.add(i);
              latinWords.add(rawTokens[i].toLowerCase());
            }
          }
          if (latinWords.isEmpty) return;

          final resp = await _dio
              .get<dynamic>(
                'https://inputtools.google.com/request',
                queryParameters: {
                  'text': latinWords.join(','),
                  'itc': 'ja-t-i0-und',
                  'num': 5,
                },
              )
              .timeout(const Duration(milliseconds: 3500));
          final perWord = _parseGoogleImeResponse(resp.data);
          for (int k = 0;
              k < perWord.length && k < latinIdx.length;
              k++) {
            final targetGroup = tokenVariants[latinIdx[k]];
            for (final c in perWord[k]) {
              final cleanCand = c.replaceAll('\u3000', ' ').trim().toLowerCase();
              if (cleanCand.isNotEmpty) {
                targetGroup.add(cleanCand);
              }
            }
          }
        } catch (_) {}
      }());
    }

    // 3. Google Translate (`gtx`) fallback for loanwords / English-to-Japanese titles
    futures.add(() async {
      try {
        final resp = await _dio
            .get<dynamic>(
              'https://translate.googleapis.com/translate_a/single',
              queryParameters: {
                'client': 'gtx',
                'sl': 'en',
                'tl': 'ja',
                'dt': 't',
                'q': cleaned,
              },
            )
            .timeout(const Duration(milliseconds: 3200));
        final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
        if (data is List && data.isNotEmpty && data[0] is List) {
          final sb = StringBuffer();
          for (final seg in data[0]) {
            if (seg is List && seg.isNotEmpty && seg[0] != null) {
              sb.write(seg[0].toString());
            }
          }
          final translated = sb.toString().replaceAll('\u3000', ' ').trim();
          if (translated.isNotEmpty &&
              _japaneseScriptRegex.hasMatch(translated)) {
            gtxCandidate = translated;
          }
        }
      } catch (_) {}
    }());

    await Future.wait(futures);

    final uniqueQueries = <String>[];
    final seenLower = <String>{cleaned.toLowerCase()};

    void addExpanded(String candidate) {
      final norm = candidate
          .replaceAll('\u3000', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (norm.isEmpty || !_japaneseScriptRegex.hasMatch(norm)) return;
      if (seenLower.add(norm.toLowerCase())) {
        uniqueQueries.add(norm);
      }
    }

    // Priority A: Top phrase candidate from Google Input Tools (`平行線 さユり`)
    for (final c in phraseCandidates.take(2)) {
      addExpanded(c);
      // Also enrich tokenVariantGroups when space-split aligns with rawTokens
      final parts = c.split(' ').where((p) => p.isNotEmpty).toList();
      if (parts.length == tokenVariants.length) {
        for (int i = 0; i < parts.length; i++) {
          tokenVariants[i].add(parts[i].toLowerCase());
        }
      }
    }

    // Priority B: Assembled top #0 Japanese IME candidate per token
    if (tokenVariants.isNotEmpty) {
      final assembled = <String>[];
      for (int i = 0; i < rawTokens.length; i++) {
        final jaPick = tokenVariants[i].firstWhere(
          (v) => _japaneseScriptRegex.hasMatch(v),
          orElse: () => rawTokens[i],
        );
        assembled.add(jaPick);
      }
      addExpanded(assembled.join(' '));
    }

    // Priority C: Google Translate candidate
    if (gtxCandidate != null) {
      addExpanded(gtxCandidate!);
    }

    return RomajiQueryExpansion(
      originalTokens: rawTokens,
      tokenVariantGroups: tokenVariants,
      expandedQueries: uniqueQueries,
    );
  }

  List<List<String>> _parseGoogleImeResponse(dynamic rawData) {
    try {
      final decoded = rawData is String ? jsonDecode(rawData) : rawData;
      if (decoded is! List || decoded.length < 2 || decoded[0] != 'SUCCESS') {
        return const [];
      }
      final entries = decoded[1];
      if (entries is! List) return const [];
      final out = <List<String>>[];
      for (final entry in entries) {
        if (entry is List && entry.length >= 2 && entry[1] is List) {
          final cands = (entry[1] as List)
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
          out.add(cands);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  String _dedupTrackKey(String artist, String title) {
    final normArtist = artist.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final normTitle = _stripFeaturedFromTitle(title)
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '$normArtist|$normTitle';
  }

  double _scoreTrackRelevance({
    required TrackMetadata track,
    required String rawQuery,
    required RomajiQueryExpansion expansion,
    required int rankInSource,
    required int sourceBoost,
  }) {
    final titleLower = track.title.toLowerCase();
    final cleanTitleLower = _stripFeaturedFromTitle(track.title).toLowerCase();
    final artistLower = track.artist.toLowerCase();
    final albumLower = track.album.toLowerCase();
    final combined = '$titleLower $artistLower';

    double score = sourceBoost.toDouble() +
        ((15 - rankInSource).clamp(0, 15) * 1.2);

    final groups = expansion.tokenVariantGroups;
    int matchedGroups = 0;
    bool anyTitleHit = false;
    bool anyArtistHit = false;
    int exactOriginalMatches = 0;

    for (int i = 0; i < groups.length; i++) {
      final group = groups[i];
      final origTok = expansion.originalTokens[i].toLowerCase();

      bool groupHitTitle = false;
      bool groupHitArtist = false;
      for (final variant in group) {
        if (variant.isEmpty) continue;
        if (titleLower.contains(variant)) {
          groupHitTitle = true;
          if (cleanTitleLower == variant) {
            score += 22;
          }
        }
        if (artistLower.contains(variant)) {
          groupHitArtist = true;
          if (artistLower == variant) {
            score += 22;
          }
        }
      }

      if (combined.contains(origTok)) {
        exactOriginalMatches++;
      }

      if (groupHitTitle || groupHitArtist) {
        matchedGroups++;
        if (groupHitTitle) anyTitleHit = true;
        if (groupHitArtist) anyArtistHit = true;
      }
    }

    if (groups.isNotEmpty) {
      final coverage = matchedGroups / groups.length;
      score += coverage * 75.0;
      if (matchedGroups == groups.length) {
        score += 35.0;
      }
    }

    if (anyTitleHit && anyArtistHit) {
      score += 45.0;
    }

    if (exactOriginalMatches > 0) {
      score += exactOriginalMatches * 8.0;
    }

    // Penalize orgel / music box / karaoke / tribute covers unless explicitly requested
    final userAskedForCover = _coverNoiseRegex.hasMatch(rawQuery);
    if (!userAskedForCover &&
        (_coverNoiseRegex.hasMatch(titleLower) ||
            _coverNoiseRegex.hasMatch(artistLower) ||
            _coverNoiseRegex.hasMatch(albumLower))) {
      score -= 110.0;
    }

    return score;
  }

  Future<List<TrackMetadata>> _searchItunesCatalog(
    String query, {
    String? country,
    String? lang,
    int limit = 15,
  }) async {
    try {
      final params = <String, dynamic>{
        'term': query,
        'entity': 'song',
        'limit': limit,
      };
      if (country != null && country.isNotEmpty) {
        params['country'] = country;
      }
      if (lang != null && lang.isNotEmpty) {
        params['lang'] = lang;
      }

      final resp = await _dio
          .get<dynamic>(
            'https://itunes.apple.com/search',
            queryParameters: params,
          )
          .timeout(const Duration(seconds: 10));

      final map = _ensureMap(resp.data);
      final rawList = map?['results'];
      if (rawList is! List) return const [];

      final tracks = <TrackMetadata>[];
      for (final item in rawList) {
        final m = _ensureMap(item);
        if (m == null) continue;

        final title = (m['trackName']?.toString() ?? '').trim();
        final artist = (m['artistName']?.toString() ?? '').trim();
        if (title.isEmpty || artist.isEmpty) continue;

        final album = (m['collectionName']?.toString() ?? title).trim();
        final releaseDate = (m['releaseDate']?.toString() ?? '').trim();
        final year = _extractYear(releaseDate);
        final durationMs = _parseInt(m['trackTimeMillis']);
        final durationSec = durationMs > 0 ? (durationMs / 1000).round() : 200;

        String artwork = (m['artworkUrl100']?.toString() ?? '').trim();
        if (artwork.isNotEmpty) {
          artwork = artwork.replaceAll('100x100bb', '1000x1000bb');
        }

        final previewUrl = (m['previewUrl']?.toString() ?? '').trim();
        final trackViewUrl = (m['trackViewUrl']?.toString() ?? '').trim();

        tracks.add(
          TrackMetadata(
            spotifyUrl: trackViewUrl.isNotEmpty ? trackViewUrl : 'search:$artist - $title',
            title: title,
            artist: artist,
            album: album.isNotEmpty ? album : title,
            releaseYear:
                year.isNotEmpty ? year : DateTime.now().year.toString(),
            durationSeconds: durationSec,
            coverUrl: artwork,
            previewAudioUrl: previewUrl.isNotEmpty ? previewUrl : null,
          ),
        );
      }
      return tracks;
    } catch (e) {
      debugPrint('[MusEvee] SEARCH: iTunes ($country) search gagal: $e');
      return const [];
    }
  }

  Future<List<TrackMetadata>> _searchDeezerCatalog(
    String query, {
    int limit = 15,
  }) async {
    try {
      final list = await _queryDeezerSearch(query);
      if (list.isEmpty) return const [];

      final tracks = <TrackMetadata>[];
      for (final item in list.take(limit)) {
        final m = _ensureMap(item);
        if (m == null) continue;

        final title = (m['title']?.toString() ?? '').trim();
        final artistObj = _ensureMap(m['artist']);
        final artist = (artistObj?['name']?.toString() ?? '').trim();
        if (title.isEmpty || artist.isEmpty) continue;

        final albumObj = _ensureMap(m['album']);
        final albumTitle = (albumObj?['title']?.toString() ?? title).trim();
        final coverXl = (albumObj?['cover_xl']?.toString() ??
                albumObj?['cover_big']?.toString() ??
                albumObj?['cover_medium']?.toString() ??
                '')
            .trim();

        final durationSec = _parseInt(m['duration']);
        final previewUrl = (m['preview']?.toString() ?? '').trim();
        final linkUrl = (m['link']?.toString() ?? '').trim();

        tracks.add(
          TrackMetadata(
            spotifyUrl: linkUrl.isNotEmpty ? linkUrl : 'search:$artist - $title',
            title: title,
            artist: artist,
            album: albumTitle.isNotEmpty ? albumTitle : title,
            releaseYear: DateTime.now().year.toString(),
            durationSeconds: durationSec > 0 ? durationSec : 200,
            coverUrl: coverXl,
            previewAudioUrl: previewUrl.isNotEmpty ? previewUrl : null,
          ),
        );
      }
      return tracks;
    } catch (e) {
      debugPrint('[MusEvee] SEARCH: Deezer search gagal: $e');
      return const [];
    }
  }

  /// Normalizes and validates a Spotify track URL.
  String normalizeSpotifyTrackUrl(String rawUrl) {
    final trimmed = extractUrlFromSharedText(rawUrl);
    if (trimmed.isEmpty) {
      throw const MetadataException('URL Spotify tidak boleh kosong.');
    }

    final spotifyUriMatch =
        RegExp(r'^spotify:track:([a-zA-Z0-9]{22})$').firstMatch(trimmed);
    if (spotifyUriMatch != null) {
      return 'https://open.spotify.com/track/${spotifyUriMatch.group(1)}';
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        (!uri.host.endsWith('open.spotify.com') &&
            !uri.host.endsWith('spotify.com'))) {
      throw const MetadataException(
        'Link tidak valid. Gunakan link lagu Spotify seperti https://open.spotify.com/track/...',
      );
    }

    final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final trackIndex = pathSegments.indexOf('track');
    if (trackIndex == -1 || trackIndex + 1 >= pathSegments.length) {
      throw const MetadataException(
        'URL bukan merupakan link lagu (track) Spotify yang valid.',
      );
    }

    final trackId = pathSegments[trackIndex + 1];
    if (!RegExp(r'^[a-zA-Z0-9]{15,30}$').hasMatch(trackId)) {
      throw const MetadataException('ID lagu Spotify pada URL tidak valid.');
    }

    return 'https://open.spotify.com/track/$trackId';
  }

  /// Extracts initial metadata from Spotify oEmbed & HTML meta tags,
  /// then enriches it with Deezer Public API (Album, Release Year, Duration, 1000x1000 Cover).
  Future<TrackMetadata> fetchTrackMetadata(String rawSpotifyUrl) async {
    debugPrint('[AUTO_E2E] TAHAP_1: Memulai ekstraksi metadata untuk URL: $rawSpotifyUrl');
    final canonicalUrl = normalizeSpotifyTrackUrl(rawSpotifyUrl);
    debugPrint('[AUTO_E2E] TAHAP_1: Canonical URL: $canonicalUrl');

    // Tahap 1: Spotify Public Extractor (oEmbed + HTML Meta Tags)
    final spotifyData = await _extractFromSpotifyPublic(canonicalUrl);
    debugPrint(
      '[AUTO_E2E] TAHAP_1: Hasil Spotify -> title="${spotifyData.title}", artist="${spotifyData.artist}", album="${spotifyData.album}", year="${spotifyData.releaseYear}", duration=${spotifyData.durationSeconds}s, cover="${spotifyData.coverUrl}"',
    );

    String title = spotifyData.title;
    String artist = spotifyData.artist;
    String album = spotifyData.album;
    String releaseYear = spotifyData.releaseYear;
    int durationSeconds = spotifyData.durationSeconds;
    String coverUrl = spotifyData.coverUrl;
    String? previewAudioUrl = spotifyData.previewAudioUrl;

    // Tahap 2: Deezer Public API Enricher
    debugPrint('[AUTO_E2E] TAHAP_2: Memulai pengayaan metadata via Deezer API...');
    final deezerEnriched = await _enrichWithDeezer(
      title: title,
      artist: artist,
      fallbackDuration: durationSeconds,
    );

    if (deezerEnriched != null) {
      debugPrint(
        '[AUTO_E2E] TAHAP_2: Hasil Deezer -> title="${deezerEnriched.title}", artist="${deezerEnriched.artist}", album="${deezerEnriched.album}", year="${deezerEnriched.releaseYear}", duration=${deezerEnriched.durationSeconds}s, cover="${deezerEnriched.coverUrl}"',
      );
      if (deezerEnriched.title.isNotEmpty && title.isEmpty) {
        title = deezerEnriched.title;
      }
      if (deezerEnriched.artist.isNotEmpty &&
          (artist.isEmpty || artist == 'Unknown Artist')) {
        artist = deezerEnriched.artist;
      }
      if (deezerEnriched.album.isNotEmpty) {
        album = deezerEnriched.album;
      }
      if (deezerEnriched.releaseYear.isNotEmpty) {
        releaseYear = deezerEnriched.releaseYear;
      }
      if (deezerEnriched.durationSeconds > 0) {
        durationSeconds = deezerEnriched.durationSeconds;
      }
      if (deezerEnriched.coverUrl.isNotEmpty) {
        coverUrl = deezerEnriched.coverUrl;
      }
      if (deezerEnriched.previewAudioUrl != null &&
          deezerEnriched.previewAudioUrl!.isNotEmpty) {
        previewAudioUrl = deezerEnriched.previewAudioUrl;
      }
    } else {
      debugPrint('[AUTO_E2E] TAHAP_2: Deezer tidak mengembalikan hasil tambahan, menggunakan metadata Spotify.');
    }

    final finalMetadata = TrackMetadata(
      spotifyUrl: canonicalUrl,
      title: title.isNotEmpty ? title : 'Spotify Track',
      artist: artist.isNotEmpty ? artist : 'Unknown Artist',
      album: album.isNotEmpty ? album : (title.isNotEmpty ? title : 'Single'),
      releaseYear: releaseYear.isNotEmpty
          ? releaseYear
          : DateTime.now().year.toString(),
      durationSeconds: durationSeconds > 0 ? durationSeconds : 200,
      coverUrl: coverUrl,
      previewAudioUrl: previewAudioUrl,
    );

    debugPrint(
      '[AUTO_E2E] TAHAP_2: Metadata Final -> "${finalMetadata.artist} - ${finalMetadata.title}" (${finalMetadata.album}, ${finalMetadata.releaseYear}, ${finalMetadata.durationSeconds}s)',
    );
    return finalMetadata;
  }

  Future<_PartialMetadata> _extractFromSpotifyPublic(
    String canonicalUrl,
  ) async {
    String oembedTitle = '';
    String oembedAuthor = '';
    String oembedThumbnail = '';

    // 1A. Call Spotify Public oEmbed API
    try {
      final oembedResponse = await _dio.get<dynamic>(
        'https://open.spotify.com/oembed',
        queryParameters: {'url': canonicalUrl},
      );
      final data = _ensureMap(oembedResponse.data);
      if (data != null) {
        oembedTitle = (data['title']?.toString() ?? '').trim();
        oembedAuthor = (data['author_name']?.toString() ?? '').trim();
        oembedThumbnail = (data['thumbnail_url']?.toString() ?? '').trim();
        debugPrint(
          '[AUTO_E2E] TAHAP_1: oEmbed berhasil -> title="$oembedTitle", author="$oembedAuthor", thumb="$oembedThumbnail"',
        );
      }
    } catch (e, s) {
      debugPrint('[AUTO_E2E] TAHAP_1: oEmbed gagal: $e\n$s');
    }

    // 1B. Fetch Spotify Track HTML and parse OpenGraph & music meta tags
    String ogTitle = '';
    String ogDescription = '';
    String ogImage = '';
    String musicianDescription = '';
    String releaseDateMeta = '';
    String pageTitle = '';
    int durationSeconds = 0;

    try {
      final htmlResponse = await _dio.get<String>(
        canonicalUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: const {
            'User-Agent': 'facebookexternalhit/1.1',
            'Accept-Language': 'en-US,en;q=0.9',
          },
        ),
      );
      final htmlContent = htmlResponse.data ?? '';
      if (htmlContent.isNotEmpty) {
        final document = html_parser.parse(htmlContent);
        pageTitle = document.querySelector('title')?.text.trim() ?? '';

        final metaElements = document.querySelectorAll('meta');
        for (final dom.Element meta in metaElements) {
          final prop =
              (meta.attributes['property'] ?? meta.attributes['name'] ?? '')
                  .toLowerCase()
                  .trim();
          final content = (meta.attributes['content'] ?? '').trim();
          if (content.isEmpty) continue;

          switch (prop) {
            case 'og:title':
              ogTitle = content;
              break;
            case 'og:description':
              ogDescription = content;
              break;
            case 'og:image':
              ogImage = content;
              break;
            case 'music:duration':
              final parsed = int.tryParse(content);
              if (parsed != null && parsed > 0) {
                durationSeconds = parsed;
              }
              break;
            case 'music:musician_description':
              musicianDescription = content;
              break;
            case 'music:release_date':
              releaseDateMeta = content;
              break;
          }
        }
        debugPrint(
          '[AUTO_E2E] TAHAP_1: HTML Meta -> ogTitle="$ogTitle", ogDesc="$ogDescription", musician="$musicianDescription", duration=$durationSeconds',
        );
      }
    } catch (e, s) {
      debugPrint('[AUTO_E2E] TAHAP_1: Ekstraksi HTML gagal (fallback ke oEmbed): $e\n$s');
    }

    String title = ogTitle.isNotEmpty ? ogTitle : oembedTitle;
    title = _cleanSpotifyTitle(title);

    String artist = musicianDescription.trim();
    if (artist.isEmpty && oembedAuthor.isNotEmpty) {
      artist = oembedAuthor;
    }

    String album = '';
    String releaseYear = _extractYear(releaseDateMeta);

    // Parse og:description (supports English & localized descriptions e.g. Indonesian)
    if (ogDescription.isNotEmpty) {
      final parsedDesc = _parseOgDescription(ogDescription, title);
      if (artist.isEmpty && parsedDesc.artist.isNotEmpty) {
        artist = parsedDesc.artist;
      }
      if (parsedDesc.album.isNotEmpty) {
        album = parsedDesc.album;
      }
      if (releaseYear.isEmpty && parsedDesc.year.isNotEmpty) {
        releaseYear = parsedDesc.year;
      }
    }

    // Fallback: parse HTML <title> e.g. "Song - song and lyrics by Artist | Spotify"
    if (pageTitle.isNotEmpty) {
      final byMatch = RegExp(
        r'^(.*?)\s*-\s*song(?:\s+and\s+lyrics)?\s+by\s+(.*?)\s*\|\s*Spotify',
        caseSensitive: false,
      ).firstMatch(pageTitle);
      if (byMatch != null) {
        if (title.isEmpty) {
          title = byMatch.group(1)?.trim() ?? '';
        }
        if (artist.isEmpty) {
          artist = byMatch.group(2)?.trim() ?? '';
        }
      }
    }

    final coverUrl = ogImage.isNotEmpty ? ogImage : oembedThumbnail;

    return _PartialMetadata(
      title: title,
      artist: artist,
      album: album,
      releaseYear: releaseYear,
      durationSeconds: durationSeconds,
      coverUrl: coverUrl,
    );
  }

  Future<_PartialMetadata?> _enrichWithDeezer({
    required String title,
    required String artist,
    required int fallbackDuration,
  }) async {
    if (title.isEmpty) return null;

    try {
      final cleanTitle = _stripFeaturedFromTitle(title);
      final primaryArtist = artist.split(',').first.trim();

      // 1. Primary strict search: artist:"{artist}" track:"{title}"
      List<dynamic> results = const [];
      final bool hasKnownArtist =
          primaryArtist.isNotEmpty && primaryArtist != 'Unknown Artist';

      if (hasKnownArtist) {
        final strictQuery = 'artist:"$primaryArtist" track:"$cleanTitle"';
        results = await _queryDeezerSearch(strictQuery);
      }

      // 2. Fallback loose search: {artist} {title}
      if (results.isEmpty && hasKnownArtist) {
        final looseQuery = '$primaryArtist $cleanTitle';
        results = await _queryDeezerSearch(looseQuery);
      }

      // 3. Fallback title-only search ONLY if artist was missing from Spotify
      if (results.isEmpty && !hasKnownArtist) {
        results = await _queryDeezerSearch('track:"$cleanTitle"');
      }
      if (results.isEmpty && !hasKnownArtist) {
        results = await _queryDeezerSearch(cleanTitle);
      }

      if (results.isEmpty) return null;

      // Pick best matching track (verifying artist match if artist is known)
      Map<String, dynamic>? chosenTrack;
      final lowerPrimaryArtist = primaryArtist.toLowerCase();

      for (final item in results) {
        final map = _ensureMap(item);
        if (map == null) continue;

        if (hasKnownArtist) {
          final itemArtistObj = _ensureMap(map['artist']);
          final itemArtistName =
              (itemArtistObj?['name']?.toString() ?? '').trim().toLowerCase();
          if (itemArtistName.isNotEmpty &&
              !itemArtistName.contains(lowerPrimaryArtist) &&
              !lowerPrimaryArtist.contains(itemArtistName)) {
            continue;
          }
        }

        chosenTrack ??= map;

        final itemDuration = _parseInt(map['duration']);
        if (fallbackDuration > 0 &&
            itemDuration > 0 &&
            (itemDuration - fallbackDuration).abs() <= 5) {
          chosenTrack = map;
          break;
        }
      }

      if (chosenTrack == null) return null;

      final deezerTitle = (chosenTrack['title']?.toString() ?? '').trim();
      final deezerDuration = _parseInt(chosenTrack['duration']);
      final deezerPreview = (chosenTrack['preview']?.toString() ?? '').trim();

      final artistObj = _ensureMap(chosenTrack['artist']);
      final deezerArtist = (artistObj?['name']?.toString() ?? '').trim();

      final albumObj = _ensureMap(chosenTrack['album']);
      final albumId = albumObj?['id']?.toString() ?? '';
      final albumTitle = (albumObj?['title']?.toString() ?? '').trim();
      final coverXl = (albumObj?['cover_xl']?.toString() ??
              albumObj?['cover_big']?.toString() ??
              albumObj?['cover_medium']?.toString() ??
              '')
          .trim();

      // Fetch album details for release_date if albumId is available
      String releaseYear = '';
      if (albumId.isNotEmpty) {
        try {
          final albumResp = await _dio.get<dynamic>(
            'https://api.deezer.com/album/$albumId',
          );
          final albumData = _ensureMap(albumResp.data);
          final releaseDate =
              (albumData?['release_date']?.toString() ?? '').trim();
          releaseYear = _extractYear(releaseDate);
        } catch (e, s) {
          debugPrint('[AUTO_E2E] TAHAP_2: Gagal mengambil detail album Deezer $albumId: $e\n$s');
        }
      }

      return _PartialMetadata(
        title: deezerTitle,
        artist: deezerArtist,
        album: albumTitle,
        releaseYear: releaseYear,
        durationSeconds: deezerDuration,
        coverUrl: coverXl,
        previewAudioUrl: deezerPreview.isNotEmpty ? deezerPreview : null,
      );
    } catch (e, s) {
      debugPrint('[AUTO_E2E] TAHAP_2: Error saat enrich Deezer: $e\n$s');
      return null;
    }
  }

  Future<List<dynamic>> _queryDeezerSearch(String query) async {
    try {
      final response = await _dio.get<dynamic>(
        'https://api.deezer.com/search',
        queryParameters: {'q': query},
      );
      final map = _ensureMap(response.data);
      final dataList = map?['data'];
      if (dataList is List) {
        return dataList;
      }
    } catch (e, s) {
      debugPrint('[AUTO_E2E] TAHAP_2: Query Deezer "$query" gagal: $e\n$s');
    }
    return const [];
  }

  String _cleanSpotifyTitle(String rawTitle) {
    var cleaned = rawTitle.trim();
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*-\s*song(?:\s+and\s+lyrics)?\s+by\s+.*?\s*\|\s*Spotify.*$',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*\|\s*Spotify.*$', caseSensitive: false),
      '',
    );
    return cleaned.trim();
  }

  String _stripFeaturedFromTitle(String title) {
    return title
        .replaceAll(
          RegExp(r'\s*[\(\[](feat\.?|ft\.?|with\s).*?[\)\]]',
              caseSensitive: false),
          '',
        )
        .trim();
  }

  _OgDescParts _parseOgDescription(String description, String trackTitle) {
    var desc = description.trim();
    // Strip localized "Listen to ... on Spotify." / "Dengarkan ... di Spotify." prefix
    desc = desc.replaceFirst(
      RegExp(r'^.*?\bSpotify\.\s*', caseSensitive: false),
      '',
    );

    final parts = desc
        .split('·')
        .map((s) => s.trim().replaceAll(RegExp(r'\.$'), ''))
        .where((s) => s.isNotEmpty)
        .toList();

    String artist = '';
    String album = '';
    String year = '';

    if (parts.isNotEmpty) {
      artist = parts[0];
    }

    for (final part in parts) {
      if (RegExp(r'^\d{4}$').hasMatch(part)) {
        year = part;
      }
    }

    if (parts.length >= 4) {
      album = parts[1];
    } else if (parts.length == 3) {
      final middle = parts[1];
      final lowerMiddle = middle.toLowerCase();
      if (lowerMiddle != 'song' &&
          lowerMiddle != 'lagu' &&
          lowerMiddle != 'single' &&
          lowerMiddle != trackTitle.toLowerCase()) {
        album = middle;
      }
    }

    return _OgDescParts(artist: artist, album: album, year: year);
  }

  String _extractYear(String rawDate) {
    final match = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(rawDate);
    return match?.group(1) ?? '';
  }

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
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
}

class _PartialMetadata {
  final String title;
  final String artist;
  final String album;
  final String releaseYear;
  final int durationSeconds;
  final String coverUrl;
  final String? previewAudioUrl;

  const _PartialMetadata({
    required this.title,
    required this.artist,
    required this.album,
    required this.releaseYear,
    required this.durationSeconds,
    required this.coverUrl,
    this.previewAudioUrl,
  });
}

class RomajiQueryExpansion {
  final List<String> originalTokens;
  final List<Set<String>> tokenVariantGroups;
  final List<String> expandedQueries;

  const RomajiQueryExpansion({
    required this.originalTokens,
    required this.tokenVariantGroups,
    required this.expandedQueries,
  });
}

class _CatalogBatch {
  final List<TrackMetadata> tracks;
  final bool isItunes;
  final int boost;

  const _CatalogBatch({
    required this.tracks,
    required this.isItunes,
    required this.boost,
  });
}

class _ScoredSearchTrack {
  final TrackMetadata track;
  final double score;
  final int order;

  const _ScoredSearchTrack({
    required this.track,
    required this.score,
    required this.order,
  });
}

class _OgDescParts {
  final String artist;
  final String album;
  final String year;

  const _OgDescParts({
    required this.artist,
    required this.album,
    required this.year,
  });
}

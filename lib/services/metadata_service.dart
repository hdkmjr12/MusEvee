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
            final name =
                (entity['title'] ?? entity['name'] ?? '').toString().trim();
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
      }
    } catch (e) {
      debugPrint('[AUTO_E2E] Embed ekstraksi $collectionType gagal: $e');
    }

    // 2. Fallback: If embed trackList was empty, fetch oEmbed + query Deezer Album/Playlist
    if (tracks.isEmpty) {
      try {
        final oembedResp = await _dio.get<dynamic>(
          'https://open.spotify.com/oembed',
          queryParameters: {'url': canonicalCollectionUrl},
        );
        final oData = _ensureMap(oembedResp.data);
        if (oData != null) {
          final oTitle = (oData['title'] ?? '').toString().trim();
          final oThumb = (oData['thumbnail_url'] ?? '').toString().trim();
          if (oTitle.isNotEmpty) collectionTitle = oTitle;
          if (oThumb.isNotEmpty && collectionCover.isEmpty) {
            collectionCover = oThumb;
          }
        }
      } catch (_) {}

      if (collectionTitle.isNotEmpty) {
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

  /// Searches music tracks directly by keyword (title, artist, anime/J-Pop, etc.)
  /// combining iTunes Search API (rich releaseYear & Japanese/global catalog)
  /// and Deezer Public Search API (1000x1000 cover_xl).
  Future<List<TrackMetadata>> searchMusicTracks(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      throw const MetadataException('Kata kunci pencarian tidak boleh kosong.');
    }

    debugPrint('[AUTO_E2E] SEARCH: Mencari lagu untuk kata kunci: "$query"');

    final results = await Future.wait<List<TrackMetadata>>([
      _searchItunesCatalog(query),
      _searchDeezerCatalog(query),
    ]);

    final itunesTracks = results[0];
    final deezerTracks = results[1];

    // Merge and deduplicate while preserving releaseYear from iTunes when matched
    final merged = <TrackMetadata>[];
    final seenKeys = <String>{};

    // Index iTunes release years by normalized artist+title
    final itunesYearMap = <String, String>{};
    for (final t in itunesTracks) {
      final key =
          '${t.artist.toLowerCase().trim()}|${_stripFeaturedFromTitle(t.title).toLowerCase().trim()}';
      if (t.releaseYear.isNotEmpty) {
        itunesYearMap[key] = t.releaseYear;
      }
    }

    // Interleave Deezer & iTunes results for best coverage of Western + Japanese tracks
    final maxLen = itunesTracks.length > deezerTracks.length
        ? itunesTracks.length
        : deezerTracks.length;

    for (int i = 0; i < maxLen; i++) {
      if (i < deezerTracks.length) {
        var dTrack = deezerTracks[i];
        final normKey =
            '${dTrack.artist.toLowerCase().trim()}|${_stripFeaturedFromTitle(dTrack.title).toLowerCase().trim()}';
        if (seenKeys.add(normKey)) {
          final matchedYear = itunesYearMap[normKey];
          if (matchedYear != null && matchedYear.isNotEmpty) {
            dTrack = dTrack.copyWith(releaseYear: matchedYear);
          }
          merged.add(dTrack);
        }
      }
      if (i < itunesTracks.length) {
        final iTrack = itunesTracks[i];
        final normKey =
            '${iTrack.artist.toLowerCase().trim()}|${_stripFeaturedFromTitle(iTrack.title).toLowerCase().trim()}';
        if (seenKeys.add(normKey)) {
          merged.add(iTrack);
        }
      }
    }

    if (merged.isEmpty) {
      throw MetadataException(
        'Tidak ditemukan lagu untuk kata kunci "$query". Coba gunakan nama artis dan judul lagu.',
      );
    }

    return merged.take(20).toList();
  }

  Future<List<TrackMetadata>> _searchItunesCatalog(String query) async {
    try {
      final resp = await _dio
          .get<dynamic>(
            'https://itunes.apple.com/search',
            queryParameters: {
              'term': query,
              'entity': 'song',
              'limit': 15,
            },
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
      debugPrint('[AUTO_E2E] SEARCH: iTunes search gagal: $e');
      return const [];
    }
  }

  Future<List<TrackMetadata>> _searchDeezerCatalog(String query) async {
    try {
      final list = await _queryDeezerSearch(query);
      if (list.isEmpty) return const [];

      final tracks = <TrackMetadata>[];
      for (final item in list.take(15)) {
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
      debugPrint('[AUTO_E2E] SEARCH: Deezer search gagal: $e');
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

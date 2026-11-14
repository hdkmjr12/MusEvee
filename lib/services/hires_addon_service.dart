import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/track_metadata.dart';
import '../providers/settings_provider.dart';
import '../utils/app_strings.dart';
import 'romaji_service.dart';

/// Result of a successful Hi-Res Lossless (`.flac`) download from an add-on source.
class HiResDownloadResult {
  final File flacFile;
  final HiResAddonSource addonSource;
  final String trackId;
  final String? isrc;
  final String streamUrl;
  final int sizeBytes;

  const HiResDownloadResult({
    required this.flacFile,
    required this.addonSource,
    required this.trackId,
    required this.streamUrl,
    required this.sizeBytes,
    this.isrc,
  });
}

/// Result of inspecting a single add-on URL or `index.json` catalog.
class AddonInspectionResult {
  final HiResAddonSource updatedSource;
  final List<HiResAddonSource> expandedSubModules;

  const AddonInspectionResult({
    required this.updatedSource,
    this.expandedSubModules = const <HiResAddonSource>[],
  });
}

/// Waterfall resolver & health inspector for Hi-Res Lossless (`.flac`) Add-on
/// sources (supporting both Monochrome/TracksStreamer APIs like
/// `https://tracks.monochrome.st` and BitChord/Stremio module manifests &
/// `index.json` catalogs).
class HiResAddonService {
  static const Duration requestTimeout = Duration(seconds: 6);
  static const int minValidFlacBytes = 131072; // >= 128 KB

  final http.Client _httpClient;
  final Future<Directory> Function()? _tempDirResolver;

  HiResAddonService({
    http.Client? httpClient,
    Future<Directory> Function()? tempDirResolver,
  })  : _httpClient = httpClient ?? http.Client(),
        _tempDirResolver = tempDirResolver;

  static const Map<String, String> _defaultHeaders = <String, String>{
    'Accept': 'application/json, text/plain, */*',
    'User-Agent': 'MusEvee/4.9 (Android; Hi-Res Lossless Client)',
  };

  /// Inspects [source] (`manifest.json`, `/info`, `index.json`, or Monochrome
  /// `/search/tracks`) with a strict 6-second timeout and returns updated
  /// metadata, health status, and any sub-modules discovered from an `index.json`.
  Future<AddonInspectionResult> inspectAddonEndpoint(
    HiResAddonSource source,
  ) async {
    final baseUrl = SettingsProvider.normalizeAddonUrl(source.url);
    if (baseUrl.isEmpty) {
      return AddonInspectionResult(
        updatedSource: source.copyWith(isHealthy: false),
      );
    }

    // 1. Check if this is an `index.json` module catalog
    if (baseUrl.toLowerCase().endsWith('/index.json') ||
        baseUrl.toLowerCase().endsWith('.json')) {
      try {
        final resp = await _httpClient
            .get(Uri.parse(baseUrl), headers: _defaultHeaders)
            .timeout(requestTimeout);
        if (resp.statusCode == 200 && resp.body.trim().isNotEmpty) {
          final decoded = jsonDecode(resp.body);
          final subModules = parseIndexCatalogModules(decoded);
          if (subModules.isNotEmpty) {
            return AddonInspectionResult(
              updatedSource: source.copyWith(
                isHealthy: true,
                downloadsAllowed: true,
              ),
              expandedSubModules: subModules,
            );
          }
          if (decoded is Map) {
            final parsed = _mergeManifestIntoSource(source, decoded, true);
            return AddonInspectionResult(updatedSource: parsed);
          }
        }
        return AddonInspectionResult(
          updatedSource: source.copyWith(isHealthy: false),
        );
      } catch (_) {
        return AddonInspectionResult(
          updatedSource: source.copyWith(isHealthy: false),
        );
      }
    }

    // 2. Check if this is a Monochrome TracksStreamer API endpoint (e.g. tracks.monochrome.st)
    if (_isLikelyMonochromeEndpoint(baseUrl)) {
      final ok = await _pingMonochromeEndpoint(baseUrl);
      if (ok) {
        return AddonInspectionResult(
          updatedSource: source.copyWith(
            isHealthy: true,
            downloadsAllowed: true,
          ),
        );
      }
    }

    // 3. Probe standard BitChord / module manifest endpoints (`/manifest.json`, `/info`, base URL)
    final candidateManifestUrls = <String>[
      '$baseUrl/manifest.json',
      '$baseUrl/info',
      baseUrl,
    ];

    for (final manifestUrl in candidateManifestUrls) {
      try {
        final resp = await _httpClient
            .get(Uri.parse(manifestUrl), headers: _defaultHeaders)
            .timeout(requestTimeout);
        if (resp.statusCode == 200 && resp.body.trim().isNotEmpty) {
          final bodyTrimmed = resp.body.trimLeft();
          if (bodyTrimmed.startsWith('{') || bodyTrimmed.startsWith('[')) {
            final decoded = jsonDecode(bodyTrimmed);
            if (decoded is List) {
              final subModules = parseIndexCatalogModules(decoded);
              return AddonInspectionResult(
                updatedSource:
                    source.copyWith(isHealthy: subModules.isNotEmpty),
                expandedSubModules: subModules,
              );
            }
            if (decoded is Map) {
              final subModules = parseIndexCatalogModules(decoded);
              final updated = _mergeManifestIntoSource(source, decoded, true);
              return AddonInspectionResult(
                updatedSource: updated,
                expandedSubModules: subModules,
              );
            }
          }
        }
      } catch (_) {}
    }

    // 4. Final fallback: check if endpoint responds to `/search/tracks?q=test&limit=1`
    final monoOk = await _pingMonochromeEndpoint(baseUrl);
    return AddonInspectionResult(
      updatedSource: source.copyWith(isHealthy: monoOk),
    );
  }

  /// Refreshes health & manifest details for all [sources] in parallel with a
  /// strict per-source timeout, expanding any `index.json` sub-modules without
  /// duplicates.
  Future<List<HiResAddonSource>> refreshAddonsHealth(
    List<HiResAddonSource> sources,
  ) async {
    final inspections = await Future.wait(
      sources.map((src) => inspectAddonEndpoint(src)),
    );

    final updatedList = <HiResAddonSource>[];
    final seenUrls = <String>{};

    for (final result in inspections) {
      final norm = SettingsProvider.normalizeAddonUrl(
        result.updatedSource.url,
      ).toLowerCase();
      if (norm.isNotEmpty && seenUrls.add(norm)) {
        updatedList.add(result.updatedSource);
      }
      for (final sub in result.expandedSubModules) {
        final subNorm = SettingsProvider.normalizeAddonUrl(
          sub.url,
        ).toLowerCase();
        if (subNorm.isNotEmpty && seenUrls.add(subNorm)) {
          updatedList.add(sub);
        }
      }
    }
    return updatedList;
  }

  /// Parses an `index.json` payload (either a JSON `List` or a `Map` containing
  /// `modules`, `addons`, or `sources`) into a deduplicated list of [HiResAddonSource]s.
  static List<HiResAddonSource> parseIndexCatalogModules(Object? decoded) {
    final rawItems = <dynamic>[];
    if (decoded is List) {
      rawItems.addAll(decoded);
    } else if (decoded is Map) {
      for (final key in const <String>[
        'modules',
        'addons',
        'sources',
        'items'
      ]) {
        final val = decoded[key];
        if (val is List) {
          rawItems.addAll(val);
        }
      }
    }

    final results = <HiResAddonSource>[];
    final seenUrls = <String>{};

    for (final item in rawItems) {
      if (item is String) {
        final cleaned = SettingsProvider.normalizeAddonUrl(item);
        if (cleaned.isNotEmpty && seenUrls.add(cleaned.toLowerCase())) {
          results.add(
            HiResAddonSource(
              id: SettingsProvider.addonIdFromUrl(cleaned),
              url: cleaned,
              name: SettingsProvider.inferAddonDisplayName(cleaned),
              enabled: true,
              isHealthy: true,
            ),
          );
        }
      } else if (item is Map) {
        final rawUrl = (item['url'] ??
                item['endpoint'] ??
                item['manifestUrl'] ??
                item['baseUrl'] ??
                '')
            .toString()
            .trim();
        var cleaned = SettingsProvider.normalizeAddonUrl(rawUrl);
        if (cleaned.toLowerCase().endsWith('/manifest.json')) {
          cleaned =
              cleaned.substring(0, cleaned.length - '/manifest.json'.length);
        }
        if (cleaned.isEmpty || !seenUrls.add(cleaned.toLowerCase())) continue;

        final name = (item['name'] ?? item['title'] ?? '').toString().trim();
        final version = (item['version'] ?? '1.0.0').toString().trim();
        final allowDl = item['allowDownloads'] ?? item['downloadsAllowed'];
        final isStreamingOnly = item['streamingOnly'] == true;
        final downloadsAllowed = isStreamingOnly
            ? false
            : (allowDl == null
                ? true
                : (allowDl == true || allowDl == 1 || allowDl == '1'));

        results.add(
          HiResAddonSource(
            id: (item['id'] ?? '').toString().trim().isNotEmpty
                ? item['id'].toString().trim()
                : SettingsProvider.addonIdFromUrl(cleaned),
            url: cleaned,
            name: name.isNotEmpty
                ? name
                : SettingsProvider.inferAddonDisplayName(cleaned),
            version: version.isNotEmpty ? version : '1.0.0',
            capabilities: const <String>['FLAC', 'Lossless', 'Hi-Res'],
            downloadsAllowed: downloadsAllowed,
            enabled: true,
            isHealthy: true,
          ),
        );
      }
    }
    return results;
  }

  static HiResAddonSource _mergeManifestIntoSource(
    HiResAddonSource source,
    Map<dynamic, dynamic> manifest,
    bool isHealthy,
  ) {
    final name =
        (manifest['name'] ?? manifest['title'] ?? '').toString().trim();
    final version = (manifest['version'] ?? '').toString().trim();
    final allowDl = manifest['allowDownloads'] ?? manifest['downloadsAllowed'];
    final downloadsAllowed = allowDl == null
        ? source.downloadsAllowed
        : (allowDl == true || allowDl == 1 || allowDl == '1');

    return source.copyWith(
      name: name.isNotEmpty ? name : source.name,
      version: version.isNotEmpty ? version : source.version,
      downloadsAllowed: downloadsAllowed,
      isHealthy: isHealthy,
    );
  }

  static bool _isLikelyMonochromeEndpoint(String baseUrl) {
    final lower = baseUrl.toLowerCase();
    return lower.contains('monochrome') ||
        lower.contains('qqdl.site') ||
        lower.contains('squid.wtf') ||
        lower.contains('kinoplus');
  }

  Future<bool> _pingMonochromeEndpoint(String baseUrl) async {
    try {
      final uri = Uri.parse('$baseUrl/search/tracks?q=love&limit=1');
      final resp = await _httpClient
          .get(uri, headers: _defaultHeaders)
          .timeout(requestTimeout);
      if (resp.statusCode == 200 && resp.body.trimLeft().startsWith('{')) {
        final decoded = jsonDecode(resp.body);
        return decoded is Map && decoded['tracks'] is List;
      }
    } catch (_) {}
    return false;
  }

  /// Resolves and downloads a lossless `.flac` file for [track] by trying
  /// [enabledAddons] sequentially in priority order (`#1` downward).
  ///
  /// Returns `null` if no enabled add-on could provide a valid `.flac` file so
  /// the caller can seamlessly fall back to YouTube MP3 `320 kbps`.
  Future<HiResDownloadResult?> resolveAndDownloadHiResFlac(
    TrackMetadata track,
    List<HiResAddonSource> enabledAddons, {
    void Function(double progress, String detail)? onProgress,
  }) async {
    final activeList = enabledAddons.where((a) => a.enabled).toList();
    if (activeList.isEmpty) return null;

    for (int i = 0; i < activeList.length; i++) {
      final addon = activeList[i];
      final baseUrl = SettingsProvider.normalizeAddonUrl(addon.url);
      if (baseUrl.isEmpty) continue;

      onProgress?.call(
        0.05,
        AppStrings.tr(
          'Mencari Hi-Res FLAC di ${addon.name} (${i + 1}/${activeList.length})...',
          'Searching Hi-Res FLAC on ${addon.name} (${i + 1}/${activeList.length})...',
        ),
      );

      try {
        // 1. Expand index.json on the fly if needed
        if (baseUrl.toLowerCase().endsWith('/index.json')) {
          final inspected = await inspectAddonEndpoint(addon);
          for (final sub in inspected.expandedSubModules) {
            final res = await _trySingleAddonForTrack(
              track,
              sub,
              onProgress: onProgress,
            );
            if (res != null) return res;
          }
          continue;
        }

        final result = await _trySingleAddonForTrack(
          track,
          addon,
          onProgress: onProgress,
        );
        if (result != null) {
          return result;
        }
      } catch (_) {
        // Move immediately to the next add-on in priority order
      }
    }

    return null;
  }

  Future<HiResDownloadResult?> _trySingleAddonForTrack(
    TrackMetadata track,
    HiResAddonSource addon, {
    void Function(double progress, String detail)? onProgress,
  }) async {
    final baseUrl = SettingsProvider.normalizeAddonUrl(addon.url);
    if (baseUrl.isEmpty) return null;

    // Strategy A: Monochrome / TracksStreamer API (`/search/tracks` -> `/track/{id}`)
    final monoCandidate = await _resolveFromMonochromeApi(baseUrl, track);
    if (monoCandidate != null) {
      bool anyValidFlacStreamAttempted = false;
      for (final streamUrl in monoCandidate.streamUrls) {
        final attempt = await _downloadAndVerifyFlacStream(
          streamUrl: streamUrl,
          addon: addon,
          trackId: monoCandidate.trackId,
          isrc: monoCandidate.isrc,
          onProgress: onProgress,
        );
        if (attempt.result != null) {
          return attempt.result;
        }
        if (attempt.verifiedFlacHeader) {
          // URL pertama sudah terbukti merupakan stream FLAC asli, tetapi koneksi
          // tetap gagal setelah semua percobaan auto-resume Range. Jangan mengulang
          // dari 0 MB pada recordingId / Strategy B di server yang sama.
          anyValidFlacStreamAttempted = true;
          break;
        }
      }
      if (anyValidFlacStreamAttempted) {
        return null;
      }
    }

    // Strategy B: BitChord / Stremio / Generic Module endpoints (`/search`, `/track`, `/stream`, `/download`)
    final moduleCandidate = await _resolveFromModuleApi(baseUrl, track);
    if (moduleCandidate != null) {
      for (final streamUrl in moduleCandidate.streamUrls) {
        final attempt = await _downloadAndVerifyFlacStream(
          streamUrl: streamUrl,
          addon: addon,
          trackId: moduleCandidate.trackId,
          isrc: moduleCandidate.isrc,
          onProgress: onProgress,
        );
        if (attempt.result != null) {
          return attempt.result;
        }
        if (attempt.verifiedFlacHeader) {
          break;
        }
      }
    }

    return null;
  }

  Future<_ResolvedStreamCandidate?> _resolveFromMonochromeApi(
    String baseUrl,
    TrackMetadata track,
  ) async {
    final rawArtistTitle = '${track.artist} ${track.title}'.trim();
    final primaryArtist = track.artist
        .split(RegExp(r'\s*(?:,|&|/|×|;|\bfeat\.?\b|\bft\.?\b)\s*',
            caseSensitive: false))
        .first
        .trim();
    final cleanTitle =
        track.title.replaceAll(RegExp(r'\s*[\(\[].*?[\)\]]'), '').trim();
    final cleanArtistTitle = '$primaryArtist $cleanTitle'.trim();

    final queries = <String>[
      if (rawArtistTitle.isNotEmpty) rawArtistTitle,
      if (cleanArtistTitle.isNotEmpty && cleanArtistTitle != rawArtistTitle)
        cleanArtistTitle,
      if (track.title.trim().isNotEmpty) track.title.trim(),
      if (primaryArtist.isNotEmpty &&
          primaryArtist != rawArtistTitle &&
          primaryArtist != track.title.trim())
        primaryArtist,
    ];

    for (final q in queries) {
      if (q.isEmpty) continue;
      try {
        final uri = Uri.parse(
          '$baseUrl/search/tracks?q=${Uri.encodeQueryComponent(q)}&limit=8',
        );
        final resp = await _httpClient
            .get(uri, headers: _defaultHeaders)
            .timeout(requestTimeout);
        if (resp.statusCode != 200 || !resp.body.trimLeft().startsWith('{')) {
          break;
        }
        final decoded = jsonDecode(resp.body);
        if (decoded is! Map || decoded['tracks'] is! List) {
          break;
        }

        final tracks = decoded['tracks'] as List;
        Map<dynamic, dynamic>? bestMap;
        int bestScore = 0;

        for (final rawItem in tracks) {
          if (rawItem is! Map) continue;
          if (rawItem['playable'] == false) continue;
          final score = scoreCandidateTrack(track, rawItem);
          if (score > bestScore) {
            bestScore = score;
            bestMap = rawItem;
          }
        }

        if (bestMap != null && bestScore >= 55) {
          final trackId =
              (bestMap['trackId'] ?? bestMap['id'] ?? '').toString().trim();
          final recordingId = (bestMap['recordingId'] ?? '').toString().trim();
          final isrc = (bestMap['isrc'] ?? '').toString().trim();
          final urls = <String>[
            if (trackId.isNotEmpty) '$baseUrl/track/$trackId',
            if (recordingId.isNotEmpty && recordingId != trackId)
              '$baseUrl/track/$recordingId',
          ];
          if (urls.isNotEmpty) {
            return _ResolvedStreamCandidate(
              trackId: trackId.isNotEmpty ? trackId : recordingId,
              isrc: isrc.isNotEmpty ? isrc : null,
              streamUrls: urls,
            );
          }
        }
      } catch (_) {
        break;
      }
    }
    return null;
  }

  Future<_ResolvedStreamCandidate?> _resolveFromModuleApi(
    String baseUrl,
    TrackMetadata track,
  ) async {
    final query = '${track.artist} ${track.title}'.trim();
    if (query.isEmpty) return null;
    final encodedQuery = Uri.encodeQueryComponent(query);
    final encodedTitle = Uri.encodeQueryComponent(track.title.trim());
    final encodedArtist = Uri.encodeQueryComponent(track.artist.trim());

    final searchUrls = <String>[
      '$baseUrl/search?q=$encodedQuery',
      '$baseUrl/search/track/$encodedQuery.json',
      '$baseUrl/track?title=$encodedTitle&artist=$encodedArtist',
    ];

    for (final url in searchUrls) {
      try {
        final resp = await _httpClient
            .get(Uri.parse(url), headers: _defaultHeaders)
            .timeout(requestTimeout);
        if (resp.statusCode != 200) continue;
        final body = resp.body.trim();
        if (!body.startsWith('{') && !body.startsWith('[')) continue;

        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['error'] != null) {
          // e.g. {"error": "bitchord_auth"} -> immediately abort this addon
          return null;
        }

        // Direct stream/download URL in response
        if (decoded is Map) {
          final directUrl = _extractDirectAudioUrlFromMap(decoded, baseUrl);
          if (directUrl != null) {
            return _ResolvedStreamCandidate(
              trackId:
                  (decoded['id'] ?? decoded['trackId'] ?? 'direct').toString(),
              streamUrls: <String>[directUrl],
            );
          }
        }

        // Candidate list in response
        final list = _extractTrackListFromDecoded(decoded);
        if (list.isEmpty) continue;

        Map<dynamic, dynamic>? bestItem;
        int bestScore = 0;
        for (final item in list) {
          if (item is! Map) continue;
          final score = scoreCandidateTrack(track, item);
          if (score > bestScore) {
            bestScore = score;
            bestItem = item;
          }
        }

        if (bestItem != null && bestScore >= 50) {
          final direct = _extractDirectAudioUrlFromMap(bestItem, baseUrl);
          final id = (bestItem['id'] ??
                  bestItem['trackId'] ??
                  bestItem['recordingId'] ??
                  '')
              .toString()
              .trim();
          final streamUrls = <String>[
            if (direct != null) direct,
          ];
          if (id.isNotEmpty) {
            final resolvedFromId = await _resolveStreamEndpointsForId(
              baseUrl,
              id,
            );
            for (final u in resolvedFromId) {
              if (!streamUrls.contains(u)) {
                streamUrls.add(u);
              }
            }
          }
          if (streamUrls.isNotEmpty) {
            return _ResolvedStreamCandidate(
              trackId: id.isNotEmpty ? id : '0',
              isrc: bestItem['isrc']?.toString(),
              streamUrls: streamUrls,
            );
          }
        }
      } catch (_) {}
    }

    return null;
  }

  Future<List<String>> _resolveStreamEndpointsForId(
    String baseUrl,
    String id,
  ) async {
    final encodedId = Uri.encodeComponent(id);
    final endpoints = <String>[
      '$baseUrl/stream/$encodedId',
      '$baseUrl/stream/track/$encodedId.json',
      '$baseUrl/download/$encodedId',
      '$baseUrl/track/$encodedId',
    ];
    final resolvedUrls = <String>[];

    for (final endpoint in endpoints) {
      try {
        final req = http.Request('GET', Uri.parse(endpoint));
        req.headers.addAll(_defaultHeaders);
        req.headers['Range'] = 'bytes=0-511';
        final streamed = await _httpClient.send(req).timeout(requestTimeout);
        final status = streamed.statusCode;
        final contentType =
            (streamed.headers['content-type'] ?? '').toLowerCase();

        if (status == 200 || status == 206) {
          if (contentType.contains('audio/flac') ||
              contentType.contains('application/octet-stream')) {
            final firstBytes = await streamed.stream.first.timeout(
              requestTimeout,
              onTimeout: () => const <int>[],
            );
            if (isFlacHeaderBytes(firstBytes)) {
              resolvedUrls.add(endpoint);
              break;
            }
          } else if (contentType.contains('application/json') ||
              contentType.contains('text/plain')) {
            final text = await streamed.stream.bytesToString().timeout(
                  requestTimeout,
                );
            if (text.trimLeft().startsWith('{')) {
              final map = jsonDecode(text);
              if (map is Map) {
                final extracted = _extractDirectAudioUrlFromMap(map, baseUrl);
                if (extracted != null) {
                  resolvedUrls.add(extracted);
                  break;
                }
              }
            }
          }
        }
      } catch (_) {}
    }
    return resolvedUrls;
  }

  static List<dynamic> _extractTrackListFromDecoded(Object? decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in const <String>[
        'tracks',
        'results',
        'items',
        'data',
        'songs',
      ]) {
        final v = decoded[key];
        if (v is List) return v;
        if (v is Map && v['items'] is List) {
          return v['items'] as List;
        }
      }
    }
    return const <dynamic>[];
  }

  static String? _extractDirectAudioUrlFromMap(
    Map<dynamic, dynamic> map,
    String baseUrl,
  ) {
    for (final key in const <String>[
      'streamUrl',
      'downloadUrl',
      'audioUrl',
      'flacUrl',
      'url',
      'stream',
    ]) {
      final val = map[key];
      if (val is String && val.trim().isNotEmpty) {
        final trimmed = val.trim();
        if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
          return trimmed;
        }
        if (trimmed.startsWith('/')) {
          return '$baseUrl$trimmed';
        }
      }
    }
    final streams = map['streams'];
    if (streams is List) {
      for (final s in streams) {
        if (s is Map) {
          final u = _extractDirectAudioUrlFromMap(s, baseUrl);
          if (u != null) return u;
        }
      }
    }
    return null;
  }

  static final RegExp _kanaRegex = RegExp(r'[\u3040-\u30ff]');
  static final RegExp _kanjiRegex = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff]');
  static final RegExp _artistSplitRegex = RegExp(
    r'\s*(?:,|&|/|×|;|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b|\bwith\b)\s*',
    caseSensitive: false,
  );

  static String _normalizeWithKanaRomaji(
    String raw, {
    bool stripFeat = false,
  }) {
    final converted =
        _kanaRegex.hasMatch(raw) ? RomajiService.convertKanaToRomaji(raw) : raw;
    return TrackMetadata.normalizeTrackSegment(
      converted,
      stripFeat: stripFeat,
    );
  }

  /// Reduces an ASCII / kana-romanized word sequence to its Japanese-loanword
  /// phonetic consonant skeleton (e.g. `"propose"` -> `"prps"`, `"プロポーズ"` /
  /// `"puropozu"` -> `"prps"`).
  static String _loanwordPhoneticSkeleton(String raw) {
    final romaji =
        _kanaRegex.hasMatch(raw) ? RomajiService.convertKanaToRomaji(raw) : raw;
    var s = romaji.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (s.isEmpty) return '';

    if (s.startsWith('kn')) s = s.substring(1);
    if (s.startsWith('wr')) s = s.substring(1);
    s = s
        .replaceAll('ph', 'f')
        .replaceAll('qu', 'k')
        .replaceAll('gh', '')
        .replaceAll('sh', 's')
        .replaceAll('th', 's')
        .replaceAll('wh', 'w')
        .replaceAll('ck', 'k')
        .replaceAll(RegExp(r'c(?=[eiy])'), 's')
        .replaceAll('c', 'k')
        .replaceAll('v', 'b')
        .replaceAll('l', 'r')
        .replaceAll('z', 's');

    // Strip vowels so Japanese epenthetic vowels (pu-ro-po-zu) align with English (propose)
    s = s.replaceAll(RegExp(r'[aeiouy]'), '');
    // Collapse consecutive duplicate consonants (e.g. "ss" -> "s")
    s = s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
    return s;
  }

  static List<String> _normalizedArtistTokens(String rawArtist) {
    final tokens = <String>{};
    void addVariant(String part) {
      final norm = TrackMetadata.normalizeTrackSegment(part, stripFeat: false);
      if (norm.isNotEmpty) tokens.add(norm);
      final romajiNorm = _normalizeWithKanaRomaji(part, stripFeat: false);
      if (romajiNorm.isNotEmpty) tokens.add(romajiNorm);
    }

    addVariant(rawArtist);
    for (final part in rawArtist.split(_artistSplitRegex)) {
      final cleaned = part.trim();
      if (cleaned.isNotEmpty) {
        addVariant(cleaned);
      }
    }
    return tokens.toList(growable: false);
  }

  static bool _artistsMatch(String targetArtist, String candArtist) {
    final targetTokens = _normalizedArtistTokens(targetArtist);
    final candTokens = _normalizedArtistTokens(candArtist);
    for (final t in targetTokens) {
      for (final c in candTokens) {
        if (t == c) return true;
        final shorterLen = t.length < c.length ? t.length : c.length;
        if (shorterLen >= 4 && (c.contains(t) || t.contains(c))) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _isUnknownArtistLabel(String normArtist) {
    return normArtist.isEmpty ||
        normArtist.startsWith('unknownartist') ||
        normArtist.startsWith('variousartists') ||
        normArtist.startsWith('spotifyartist');
  }

  /// Scores how closely a candidate JSON track matches [target] (`0..220`).
  static int scoreCandidateTrack(
    TrackMetadata target,
    Map<dynamic, dynamic> candidate,
  ) {
    final candTitle =
        (candidate['title'] ?? candidate['name'] ?? '').toString().trim();
    if (candTitle.isEmpty) return 0;

    String candArtist = '';
    if (candidate['artistNames'] is List &&
        (candidate['artistNames'] as List).isNotEmpty) {
      candArtist = (candidate['artistNames'] as List)
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .join(', ');
    } else if (candidate['artist'] is Map) {
      candArtist = (candidate['artist']['name'] ?? '').toString().trim();
    } else if (candidate['artist'] != null) {
      candArtist = candidate['artist'].toString().trim();
    } else if (candidate['artists'] is List &&
        (candidate['artists'] as List).isNotEmpty) {
      final first = (candidate['artists'] as List).first;
      if (first is Map) {
        candArtist = (first['name'] ?? '').toString().trim();
      } else {
        candArtist = first.toString().trim();
      }
    }

    final targetIsrc = (target.isrc ?? '').trim().toUpperCase();
    final candIsrc = (candidate['isrc'] ?? '').toString().trim().toUpperCase();
    final bool isIsrcMatch =
        targetIsrc.isNotEmpty && candIsrc.isNotEmpty && targetIsrc == candIsrc;

    // Immediately reject non-vocal / backing versions when target is a normal vocal track
    final targetLower = target.title.toLowerCase();
    final candLower = candTitle.toLowerCase();
    for (final hardRejectQualifier in const <String>[
      'instrumental',
      'karaoke',
      'off vocal',
      'backing track',
    ]) {
      if (candLower.contains(hardRejectQualifier) &&
          !targetLower.contains(hardRejectQualifier)) {
        return 0;
      }
    }

    // Strict Artist Verification: never accept a cover / original by an unrelated singer
    final normTargetArtist = TrackMetadata.normalizeTrackSegment(
      target.artist,
      stripFeat: true,
    );
    final normCandArtist = TrackMetadata.normalizeTrackSegment(
      candArtist,
      stripFeat: true,
    );
    final hasKnownTargetArtist = !_isUnknownArtistLabel(normTargetArtist);
    final hasKnownCandArtist = !_isUnknownArtistLabel(normCandArtist);
    final artistMatched = hasKnownTargetArtist &&
        hasKnownCandArtist &&
        _artistsMatch(target.artist, candArtist);

    if (hasKnownTargetArtist &&
        hasKnownCandArtist &&
        !artistMatched &&
        !isIsrcMatch) {
      // Only allow mismatched-script artists when one is Kanji and the other is Latin
      // (e.g. "米津玄師" vs "Kenshi Yonezu") with strict penalty; otherwise reject 0.
      final targetHasKanji = _kanjiRegex.hasMatch(target.artist);
      final candHasKanji = _kanjiRegex.hasMatch(candArtist);
      if (targetHasKanji == candHasKanji) {
        return 0;
      }
    }

    final normTargetTitle = TrackMetadata.normalizeTrackSegment(
      target.title,
      stripFeat: true,
    );
    final normCandTitle = TrackMetadata.normalizeTrackSegment(
      candTitle,
      stripFeat: true,
    );
    final romajiTargetTitle = _normalizeWithKanaRomaji(
      target.title,
      stripFeat: true,
    );
    final romajiCandTitle = _normalizeWithKanaRomaji(
      candTitle,
      stripFeat: true,
    );
    if (normTargetTitle.isEmpty || normCandTitle.isEmpty) return 0;

    int score = 0;
    if (isIsrcMatch) {
      score += 120;
    } else if (normTargetTitle == normCandTitle ||
        (romajiTargetTitle.isNotEmpty &&
            romajiTargetTitle == romajiCandTitle)) {
      score += 65;
    } else {
      final shorterNormLen = normCandTitle.length < normTargetTitle.length
          ? normCandTitle.length
          : normTargetTitle.length;
      if (shorterNormLen >= 3 &&
          (normCandTitle.contains(normTargetTitle) ||
              normTargetTitle.contains(normCandTitle) ||
              romajiCandTitle.contains(romajiTargetTitle) ||
              romajiTargetTitle.contains(romajiCandTitle))) {
        score += 45;
      } else if (artistMatched &&
          (_kanaRegex.hasMatch(target.title) !=
              _kanaRegex.hasMatch(candTitle))) {
        // Cross-script Japanese Katakana/Hiragana loanword matching when the artist is verified
        // (e.g. target "propose" by 9Lana vs Monochrome "プロポーズ" by 9Lana).
        final skelTarget = _loanwordPhoneticSkeleton(target.title);
        final skelCand = _loanwordPhoneticSkeleton(candTitle);
        if (skelTarget.length >= 3 && skelCand == skelTarget) {
          score += 55;
        } else {
          return 0;
        }
      } else {
        return 0;
      }
    }

    // Penalize unwanted Live / Sped up / Slowed / Cover / Remix variants if target is studio track
    for (final qualifier in const <String>[
      'live',
      'sped up',
      'slowed',
      'cover',
      'remix',
      'acoustic',
    ]) {
      if (candLower.contains(qualifier) && !targetLower.contains(qualifier)) {
        score -= 35;
      }
    }

    if (hasKnownTargetArtist && hasKnownCandArtist) {
      if (artistMatched) {
        score += 40;
      } else if (!isIsrcMatch) {
        score -= 40;
      }
    }

    // Duration proximity check
    final rawDur = candidate['duration'] ?? candidate['durationMs'];
    if (rawDur is num && target.durationSeconds > 0) {
      final val = rawDur.toInt();
      // Monochrome returns duration in ms (e.g. 208266), others in seconds (e.g. 208)
      final candSec = val > 2000 ? (val / 1000).round() : val;
      final diff = (candSec - target.durationSeconds).abs();
      if (diff <= 4) {
        score += 20;
      } else if (diff <= 12) {
        score += 10;
      } else if (diff > 35) {
        score -= 40;
      }
    }

    return score;
  }

  /// Checks whether [bytes] begins with the native `fLaC` magic header
  /// (`0x66 0x4C 0x61 0x43`) or an `ID3` wrapper immediately followed by `fLaC`.
  static bool isFlacHeaderBytes(List<int> bytes) {
    if (bytes.length < 4) return false;
    // Direct 'fLaC' magic: 0x66 ('f'), 0x4C ('L'), 0x61 ('a'), 0x43 ('C')
    if (bytes[0] == 0x66 &&
        bytes[1] == 0x4C &&
        bytes[2] == 0x61 &&
        bytes[3] == 0x43) {
      return true;
    }
    // Optional ID3v2 header prepended to FLAC
    if (bytes.length >= 10 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      final tagSize = ((bytes[6] & 0x7F) << 21) |
          ((bytes[7] & 0x7F) << 14) |
          ((bytes[8] & 0x7F) << 7) |
          (bytes[9] & 0x7F);
      final flacOffset = 10 + tagSize;
      if (bytes.length >= flacOffset + 4) {
        return bytes[flacOffset] == 0x66 &&
            bytes[flacOffset + 1] == 0x4C &&
            bytes[flacOffset + 2] == 0x61 &&
            bytes[flacOffset + 3] == 0x43;
      }
      return true;
    }
    return false;
  }

  Future<Directory> _resolveTempDir() async {
    final resolver = _tempDirResolver;
    if (resolver != null) {
      return resolver();
    }
    return getTemporaryDirectory();
  }

  static int? _parseTotalSizeFromContentRange(String? contentRange) {
    if (contentRange == null || contentRange.isEmpty) return null;
    final slashIdx = contentRange.lastIndexOf('/');
    if (slashIdx < 0 || slashIdx + 1 >= contentRange.length) return null;
    final totalPart = contentRange.substring(slashIdx + 1).trim();
    if (totalPart == '*') return null;
    return int.tryParse(totalPart);
  }

  Future<_FlacDownloadAttempt> _downloadAndVerifyFlacStream({
    required String streamUrl,
    required HiResAddonSource addon,
    required String trackId,
    String? isrc,
    void Function(double progress, String detail)? onProgress,
  }) async {
    File? tempFile;
    RandomAccessFile? raf;
    bool verifiedHeader = false;
    int receivedBytes = 0;
    int expectedTotalBytes = 0;
    const int maxResumeAttempts = 5;

    Future<void> cleanupTemp() async {
      final currentRaf = raf;
      raf = null;
      try {
        await currentRaf?.close();
      } catch (_) {}
      final currentTemp = tempFile;
      if (currentTemp != null) {
        try {
          if (await currentTemp.exists()) {
            await currentTemp.delete();
          }
        } catch (_) {}
      }
    }

    try {
      final tempDir = await _resolveTempDir();
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final createdFile = File(
        '${tempDir.path}${Platform.pathSeparator}hires_${DateTime.now().microsecondsSinceEpoch}.flac',
      );
      tempFile = createdFile;
      final activeRaf = await createdFile.open(mode: FileMode.write);
      raf = activeRaf;

      final headerAccum = BytesBuilder(copy: false);
      int resumeCount = 0;

      while (true) {
        final isResumeRequest = receivedBytes > 0;
        final req = http.Request('GET', Uri.parse(streamUrl));
        req.headers.addAll(_defaultHeaders);
        if (isResumeRequest) {
          req.headers['Range'] = 'bytes=$receivedBytes-';
        }

        http.StreamedResponse streamed;
        try {
          streamed = await _httpClient.send(req).timeout(
                const Duration(seconds: 12),
              );
        } catch (_) {
          if (verifiedHeader && resumeCount < maxResumeAttempts) {
            resumeCount++;
            await Future<void>.delayed(
              Duration(milliseconds: 500 * resumeCount),
            );
            continue;
          }
          await cleanupTemp();
          return _FlacDownloadAttempt(
            result: null,
            verifiedFlacHeader: verifiedHeader,
          );
        }

        final status = streamed.statusCode;
        if (status != 200 && status != 206) {
          if (verifiedHeader &&
              (status == 429 || status >= 500) &&
              resumeCount < maxResumeAttempts) {
            resumeCount++;
            await Future<void>.delayed(
              Duration(milliseconds: 500 * resumeCount),
            );
            continue;
          }
          await cleanupTemp();
          return _FlacDownloadAttempt(
            result: null,
            verifiedFlacHeader: verifiedHeader,
          );
        }

        final contentType =
            (streamed.headers['content-type'] ?? '').toLowerCase();
        if (contentType.contains('text/html') ||
            contentType.contains('application/json')) {
          await cleanupTemp();
          return _FlacDownloadAttempt(
            result: null,
            verifiedFlacHeader: verifiedHeader,
          );
        }

        // Prevent file corruption if we requested a byte Range (`receivedBytes > 0`)
        // but the server ignored `Range` and returned `200 OK` from byte 0.
        if (isResumeRequest && status == 200) {
          await activeRaf.truncate(0);
          await activeRaf.setPosition(0);
          receivedBytes = 0;
          verifiedHeader = false;
          headerAccum.clear();
        }

        if (expectedTotalBytes <= 0) {
          final rangeTotal = _parseTotalSizeFromContentRange(
            streamed.headers['content-range'],
          );
          if (rangeTotal != null && rangeTotal > 0) {
            expectedTotalBytes = rangeTotal;
          } else if (status == 200 &&
              streamed.contentLength != null &&
              streamed.contentLength! > 0) {
            expectedTotalBytes = streamed.contentLength!;
          } else if (status == 206 &&
              streamed.contentLength != null &&
              streamed.contentLength! > 0) {
            expectedTotalBytes = receivedBytes + streamed.contentLength!;
          }
        }

        bool streamInterrupted = false;
        int bytesInThisSegment = 0;

        try {
          await for (final chunk in streamed.stream.timeout(
            const Duration(seconds: 25),
          )) {
            if (!verifiedHeader) {
              headerAccum.add(chunk);
              final preview = headerAccum.toBytes();
              if (preview.length >= 16) {
                if (!isFlacHeaderBytes(preview)) {
                  await cleanupTemp();
                  return const _FlacDownloadAttempt(
                    result: null,
                    verifiedFlacHeader: false,
                  );
                }
                verifiedHeader = true;
              }
            }

            await activeRaf.writeFrom(chunk);
            receivedBytes += chunk.length;
            bytesInThisSegment += chunk.length;

            if (expectedTotalBytes > 0) {
              final frac = (receivedBytes / expectedTotalBytes).clamp(0.0, 1.0);
              final mb = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
              final totalMb =
                  (expectedTotalBytes / (1024 * 1024)).toStringAsFixed(1);
              onProgress?.call(
                frac,
                AppStrings.svcDownloadingHiResProgress(
                  mb,
                  totalMb,
                  addon.name,
                ),
              );
            } else {
              final mb = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
              onProgress?.call(
                0.5,
                AppStrings.svcDownloadingHiResProgress(
                  mb,
                  null,
                  addon.name,
                ),
              );
            }
          }
        } catch (_) {
          streamInterrupted = true;
        }

        await activeRaf.flush();

        // Check if download is still incomplete (`receivedBytes < expectedTotalBytes`)
        // or the stream broke mid-way after verifying the FLAC header.
        final isIncomplete = streamInterrupted ||
            (expectedTotalBytes > 0 && receivedBytes < expectedTotalBytes);

        if (isIncomplete) {
          // Reset consecutive stall counter if this segment made tangible progress (>= 256 KB)
          if (bytesInThisSegment >= 256 * 1024) {
            resumeCount = 0;
          }
          if (verifiedHeader && resumeCount < maxResumeAttempts) {
            resumeCount++;
            await Future<void>.delayed(
              Duration(milliseconds: 450 * resumeCount),
            );
            continue;
          }
          await cleanupTemp();
          return _FlacDownloadAttempt(
            result: null,
            verifiedFlacHeader: verifiedHeader,
          );
        }

        break;
      }

      await activeRaf.flush();
      await activeRaf.close();
      raf = null;

      if (!verifiedHeader || receivedBytes < minValidFlacBytes) {
        await cleanupTemp();
        return _FlacDownloadAttempt(
          result: null,
          verifiedFlacHeader: verifiedHeader,
        );
      }

      return _FlacDownloadAttempt(
        result: HiResDownloadResult(
          flacFile: createdFile,
          addonSource: addon,
          trackId: trackId,
          isrc: isrc,
          streamUrl: streamUrl,
          sizeBytes: receivedBytes,
        ),
        verifiedFlacHeader: true,
      );
    } catch (_) {
      await cleanupTemp();
      return _FlacDownloadAttempt(
        result: null,
        verifiedFlacHeader: verifiedHeader,
      );
    }
  }
}

class _FlacDownloadAttempt {
  final HiResDownloadResult? result;
  final bool verifiedFlacHeader;

  const _FlacDownloadAttempt({
    required this.result,
    required this.verifiedFlacHeader,
  });
}

class _ResolvedStreamCandidate {
  final String trackId;
  final String? isrc;
  final List<String> streamUrls;

  const _ResolvedStreamCandidate({
    required this.trackId,
    required this.streamUrls,
    this.isrc,
  });
}

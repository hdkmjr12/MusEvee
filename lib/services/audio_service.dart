import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/track_metadata.dart';

class AudioExtractionException implements Exception {
  final String message;
  const AudioExtractionException(this.message);

  @override
  String toString() => message;
}

class YoutubeCandidate {
  final String videoId;
  final String title;
  final String channelName;
  final int durationSeconds;
  final bool isBestMatch;

  const YoutubeCandidate({
    required this.videoId,
    required this.title,
    required this.channelName,
    required this.durationSeconds,
    required this.isBestMatch,
  });

  String get formattedDuration {
    if (durationSeconds <= 0) return '--:--';
    final mins = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }
}

class _ClientProfile {
  final String name;
  final List<YoutubeApiClient>? clients;
  final bool requireWatchPage;

  const _ClientProfile({
    required this.name,
    required this.clients,
    required this.requireWatchPage,
  });
}

class AudioService {
  final Dio _dio;

  AudioService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 15),
                followRedirects: true,
                maxRedirects: 5,
              ),
            );

  static final List<_ClientProfile> _clientProfiles = [
    const _ClientProfile(
      name: 'AndroidSdkless',
      clients: [YoutubeApiClient.androidSdkless],
      requireWatchPage: false,
    ),
    const _ClientProfile(
      name: 'AndroidVR',
      clients: [YoutubeApiClient.androidVr],
      requireWatchPage: false,
    ),
    _ClientProfile(
      name: 'iOS',
      clients: [YoutubeApiClient.ios],
      requireWatchPage: false,
    ),
    const _ClientProfile(
      name: 'TV',
      clients: [YoutubeApiClient.tv],
      requireWatchPage: true,
    ),
    const _ClientProfile(
      name: 'Safari',
      clients: [YoutubeApiClient.safari],
      requireWatchPage: false,
    ),
    const _ClientProfile(
      name: 'Default',
      clients: null,
      requireWatchPage: true,
    ),
  ];

  static const List<String> _pipedInstances = [
    'https://pipedapi.kavin.rocks',
    'https://api.piped.private.coffee',
    'https://pipedapi.tokhmi.xyz',
    'https://pipedapi.moomoo.me',
  ];

  static const List<String> _invidiousInstances = [
    'https://inv.tux.pizza',
    'https://invidious.nerdvpn.de',
    'https://invidious.jing.rocks',
    'https://iv.ggtyler.dev',
  ];

  static const List<String> _saavnApiInstances = [
    'https://saavn.dev/api/search/songs',
    'https://jiosaavn-api-privatecvc2.vercel.app/search/songs',
    'https://saavn.sumit.co/api/search/songs',
  ];

  /// Returns the top 5 ranked YouTube video candidates for [metadata] so the user
  /// can inspect or manually override the audio source before downloading.
  Future<List<YoutubeCandidate>> searchYoutubeCandidates(
    TrackMetadata metadata,
  ) async {
    final query = '${metadata.artist} - ${metadata.title} Official Audio';
    final yt = YoutubeExplode();
    try {
      final results = await yt.search
          .search(query)
          .timeout(const Duration(seconds: 12));
      final batch = results.take(8).toList();
      if (batch.isEmpty) return const [];

      final ranked = _rankTopCandidates(batch, metadata.durationSeconds);
      final topFive = ranked.take(5).toList();
      final candidates = <YoutubeCandidate>[];

      for (int i = 0; i < topFive.length; i++) {
        final v = topFive[i];
        candidates.add(
          YoutubeCandidate(
            videoId: v.id.value,
            title: v.title,
            channelName: v.author.isNotEmpty ? v.author : 'YouTube Music',
            durationSeconds: v.duration?.inSeconds ?? 0,
            isBestMatch: i == 0,
          ),
        );
      }
      return candidates;
    } catch (e) {
      debugPrint('[AUTO_E2E] searchYoutubeCandidates gagal: $e');
      return const [];
    } finally {
      yt.close();
    }
  }

  /// Searches and downloads the highest-bitrate audio stream with multi-layer
  /// fallbacks (YoutubeExplode multi-client -> Direct Client-UA Range -> Piped/Invidious -> Public Audio CDN).
  Future<File> downloadBestAudioStream(
    TrackMetadata metadata, {
    void Function(double progress, String detail)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final preferredId = metadata.preferredYoutubeVideoId?.trim() ?? '';
    final query = '${metadata.artist} - ${metadata.title} Official Audio';
    debugPrint('[AUTO_E2E] TAHAP_4: Memulai pencarian audio untuk query: "$query" (preferredId="$preferredId")');
    onProgress?.call(0.02, 'Mencari sumber audio: "$query"...');

    // 1. Search candidate videos on YouTube (or fetch preferred video first)
    List<Video> rankedVideos = const [];
    final searchYt = YoutubeExplode();
    try {
      Video? preferredVideo;
      if (preferredId.isNotEmpty) {
        try {
          preferredVideo = await searchYt.videos
              .get(preferredId)
              .timeout(const Duration(seconds: 10));
        } catch (e) {
          debugPrint('[AUTO_E2E] TAHAP_4: Gagal mengambil preferredVideo $preferredId: $e');
        }
      }

      final searchResults = await searchYt.search
          .search(query)
          .timeout(const Duration(seconds: 15));

      final topBatch = searchResults.take(8).toList();
      debugPrint(
        '[AUTO_E2E] TAHAP_4: Pencarian YouTube menghasilkan ${topBatch.length} kandidat di batch pertama.',
      );
      if (topBatch.isNotEmpty) {
        rankedVideos = _rankTopCandidates(topBatch, metadata.durationSeconds);
      }

      if (preferredVideo != null) {
        rankedVideos = [
          preferredVideo,
          ...rankedVideos.where((v) => v.id.value != preferredVideo!.id.value),
        ];
      }
    } catch (e, s) {
      debugPrint('[AUTO_E2E] TAHAP_4: Pencarian YoutubeExplode gagal: $e\n$s');
    } finally {
      searchYt.close();
    }

    String lastErrorDetail = 'Belum ada stream yang berhasil.';

    // 2. Layer 1: Try YoutubeExplode multi-client extraction on top candidate videos
    final videosToTry = rankedVideos.take(3).toList();
    for (int vIdx = 0; vIdx < videosToTry.length; vIdx++) {
      final video = videosToTry[vIdx];
      final durationStr = _formatDuration(video.duration);
      debugPrint(
        '[AUTO_E2E] TAHAP_4: Mencoba kandidat video #${vIdx + 1}: id=${video.id.value}, title="${video.title}", dur=$durationStr',
      );

      onProgress?.call(
        0.05,
        'Sumber terpilih: "${video.title}" ($durationStr)',
      );

      for (int cIdx = 0; cIdx < _clientProfiles.length; cIdx++) {
        final profile = _clientProfiles[cIdx];
        final manifestProgress =
            0.06 + ((cIdx / _clientProfiles.length) * 0.08);

        onProgress?.call(
          manifestProgress,
          'Ekstraksi manifest via client ${profile.name}...',
        );
        debugPrint(
          '[AUTO_E2E] TAHAP_4: Meminta manifest video ${video.id.value} dengan client ${profile.name} (watchPage=${profile.requireWatchPage})...',
        );

        final clientYt = YoutubeExplode();
        StreamManifest? manifest;

        try {
          manifest = await _runWithHardTimeout<StreamManifest>(
            action: () => clientYt.videos.streamsClient
                .getManifest(
                  video.id,
                  ytClients: profile.clients,
                  requireWatchPage: profile.requireWatchPage,
                )
                .timeout(const Duration(seconds: 12)),
            timeout: const Duration(seconds: 12),
            onTimeoutDispose: clientYt.close,
          );
          debugPrint(
            '[AUTO_E2E] TAHAP_4: Manifest ${profile.name} BERHASIL -> audioOnly=${manifest.audioOnly.length}, muxed=${manifest.muxed.length}',
          );
        } catch (e, s) {
          lastErrorDetail = 'Manifest ${profile.name} gagal: $e';
          debugPrint('[AUTO_E2E] TAHAP_4: Manifest ${profile.name} GAGAL: $e\n$s');
          clientYt.close();
          continue;
        }

        final candidateStreams = _buildPrioritizedStreams(
          manifest,
          profileName: profile.name,
        );
        if (candidateStreams.isEmpty) {
          lastErrorDetail =
              'Client ${profile.name} tidak memiliki stream audio/muxed.';
          debugPrint('[AUTO_E2E] TAHAP_4: $lastErrorDetail');
          clientYt.close();
          continue;
        }

        final streamsToTry = candidateStreams.take(3).toList();
        for (int sIdx = 0; sIdx < streamsToTry.length; sIdx++) {
          final streamInfo = streamsToTry[sIdx];
          final ext = streamInfo.container.name.isNotEmpty
              ? streamInfo.container.name.toLowerCase()
              : 'm4a';
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final rawAudioFile = File(
            '${tempDir.path}${Platform.pathSeparator}spotmeta_yt_${timestamp}_${cIdx}_$sIdx.$ext',
          );

          debugPrint(
            '[AUTO_E2E] TAHAP_4: Mengunduh stream #${sIdx + 1} (${streamInfo.runtimeType}, tag=${streamInfo.tag}, container=$ext, bitrate=${streamInfo.bitrate}, size=${streamInfo.size.totalBytes})...',
          );

          bool receivedHttp403 = false;

          // Attempt A: Direct HTTP download (progressive no-Range for Muxed / AndroidSdkless, Range chunks for adaptive)
          try {
            final directFile = await _downloadDirectUrlWithClientUa(
              streamUrl: streamInfo.url,
              totalBytes: streamInfo.size.totalBytes,
              bitrateKbps: streamInfo.bitrate.kiloBitsPerSecond.round(),
              containerLabel: ext.toUpperCase(),
              targetFile: rawAudioFile,
              useRangeChunks: streamInfo is AudioOnlyStreamInfo &&
                  profile.name != 'AndroidSdkless',
              onProgress: onProgress,
            );
            clientYt.close();
            debugPrint(
              '[AUTO_E2E] TAHAP_4: Unduhan Direct Client-UA BERHASIL -> ${directFile.path} (${await directFile.length()} bytes)',
            );
            onProgress?.call(1.0, 'Unduhan stream audio selesai.');
            return directFile;
          } catch (e, s) {
            final errStr = e.toString();
            if (errStr.contains('403')) {
              receivedHttp403 = true;
            }
            lastErrorDetail =
                'Direct stream ${streamInfo.container.name} (${profile.name}) gagal: $e';
            debugPrint(
              '[AUTO_E2E] TAHAP_4: Direct Client-UA stream #${sIdx + 1} gagal ($e)...\n$s',
            );
            try {
              if (await rawAudioFile.exists()) await rawAudioFile.delete();
            } catch (_) {}
          }

          // Skip YoutubeExplode's internal streamsClient.get() if the URL already returned 403
          // because youtube_explode_dart 3.1.0 enters an internal getManifest retry loop on 403.
          if (receivedHttp403) {
            continue;
          }

          // Attempt B: YoutubeExplode streamsClient.get(streamInfo) with 10s chunk timeout
          try {
            final downloadedFile = await _downloadStreamWithChunkTimeout(
              yt: clientYt,
              streamInfo: streamInfo,
              targetFile: rawAudioFile,
              clientName: profile.name,
              onProgress: onProgress,
            );

            clientYt.close();
            debugPrint(
              '[AUTO_E2E] TAHAP_4: Unduhan YoutubeExplode stream BERHASIL -> ${downloadedFile.path} (${await downloadedFile.length()} bytes)',
            );
            onProgress?.call(1.0, 'Unduhan stream audio selesai.');
            return downloadedFile;
          } catch (e, s) {
            lastErrorDetail =
                'Stream ${streamInfo.container.name} (${profile.name}) gagal: $e';
            debugPrint('[AUTO_E2E] TAHAP_4: $lastErrorDetail\n$s');
            try {
              if (await rawAudioFile.exists()) {
                await rawAudioFile.delete();
              }
            } catch (_) {}
          }
        }

        clientYt.close();
      }

      // Layer 2A: Try Piped & Invidious Public APIs for this videoId
      debugPrint(
        '[AUTO_E2E] TAHAP_4: Semua client YoutubeExplode gagal untuk ${video.id.value}. Mencoba fallback Piped / Invidious API...',
      );
      final pipedOrInvidiousFile = await _tryPipedAndInvidiousFallback(
        videoId: video.id.value,
        tempDir: tempDir,
        onProgress: onProgress,
      );
      if (pipedOrInvidiousFile != null) {
        return pipedOrInvidiousFile;
      }
    }

    // Layer 3: Public Audio CDN Extractor Fallback (Saavn / Public Music CDN 320kbps AAC/M4A)
    debugPrint(
      '[AUTO_E2E] TAHAP_4: Mencoba fallback Public Audio CDN untuk "${metadata.artist} - ${metadata.title}"...',
    );
    final publicCdnFile = await _tryPublicAudioCdnFallback(
      metadata: metadata,
      tempDir: tempDir,
      onProgress: onProgress,
    );
    if (publicCdnFile != null) {
      return publicCdnFile;
    }

    throw AudioExtractionException(
      'Gagal mengunduh stream audio di semua jalur ekstraksi. Detail terakhir: $lastErrorDetail',
    );
  }

  /// Downloads a YouTube `googlevideo.com` URL directly.
  /// For progressive/AndroidSdkless streams (`useRangeChunks == false`), sends
  /// a single continuous GET without `Range` header to avoid 403 Range blocks.
  Future<File> _downloadDirectUrlWithClientUa({
    required Uri streamUrl,
    required int totalBytes,
    required int bitrateKbps,
    required String containerLabel,
    required File targetFile,
    required bool useRangeChunks,
    void Function(double progress, String detail)? onProgress,
  }) async {
    final clientParam = (streamUrl.queryParameters['c'] ?? '').toUpperCase();
    final userAgent = _userAgentForClient(clientParam);

    final sink = targetFile.openWrite();
    int receivedBytes = 0;
    int lastUiUpdateMs = 0;

    try {
      const int chunkSize = 9437184; // 9 MB chunks when Range mode is active
      final int expectedTotal = totalBytes > 0 ? totalBytes : 0;

      while (expectedTotal == 0 || receivedBytes < expectedTotal) {
        final int start = receivedBytes;
        final int end = expectedTotal > 0
            ? ((start + chunkSize - 1) < (expectedTotal - 1)
                ? (start + chunkSize - 1)
                : (expectedTotal - 1))
            : (start + chunkSize - 1);

        final headers = <String, dynamic>{
          'Accept': '*/*',
          'Accept-Encoding': 'identity',
          'Connection': 'keep-alive',
        };

        final Uri requestUri = streamUrl;
        if (useRangeChunks && expectedTotal > 0) {
          headers['User-Agent'] = userAgent;
          headers['Range'] = 'bytes=$start-$end';
        }

        final response = await _dio
            .get<ResponseBody>(
              requestUri.toString(),
              options: Options(
                responseType: ResponseType.stream,
                headers: headers,
                validateStatus: (status) =>
                    status != null && status >= 200 && status < 300,
              ),
            )
            .timeout(const Duration(seconds: 12));

        final bodyStream = response.data?.stream;
        if (bodyStream == null) {
          throw const AudioExtractionException('Response body stream kosong.');
        }

        int chunkReceived = 0;
        await for (final Uint8List data
            in bodyStream.timeout(const Duration(seconds: 12))) {
          sink.add(data);
          receivedBytes += data.length;
          chunkReceived += data.length;

          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (nowMs - lastUiUpdateMs >= 80 ||
              (expectedTotal > 0 && receivedBytes >= expectedTotal)) {
            lastUiUpdateMs = nowMs;
            final downloadedMb =
                (receivedBytes / (1024 * 1024)).toStringAsFixed(2);
            if (expectedTotal > 0) {
              final ratio = (receivedBytes / expectedTotal).clamp(0.0, 1.0);
              final mappedProgress = 0.16 + (ratio * 0.84);
              final totalMb =
                  (expectedTotal / (1024 * 1024)).toStringAsFixed(2);
              onProgress?.call(
                mappedProgress,
                'Mengunduh audio ($containerLabel ${bitrateKbps}kbps): $downloadedMb MB / $totalMb MB',
              );
            } else {
              onProgress?.call(
                0.55,
                'Mengunduh audio ($containerLabel ${bitrateKbps}kbps): $downloadedMb MB',
              );
            }
          }
        }

        if (!useRangeChunks || expectedTotal == 0 || chunkReceived == 0) {
          break;
        }
      }

      await sink.flush();
    } finally {
      try {
        await sink.close();
      } catch (_) {}
    }

    if (!await targetFile.exists() || await targetFile.length() < 65536) {
      throw AudioExtractionException(
        'File hasil unduhan direct terlalu kecil (${await targetFile.exists() ? await targetFile.length() : 0} bytes).',
      );
    }

    return targetFile;
  }

  String _userAgentForClient(String clientName) {
    if (clientName.contains('IOS')) {
      return 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)';
    }
    if (clientName.contains('ANDROID_VR')) {
      return 'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1) gzip';
    }
    if (clientName.contains('ANDROID')) {
      return 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
    }
    if (clientName.contains('TV')) {
      return 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version,gzip(gfe)';
    }
    return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15';
  }

  /// Fallback 2A & 2B: Piped API and Invidious Public API stream extractors.
  Future<File?> _tryPipedAndInvidiousFallback({
    required String videoId,
    required Directory tempDir,
    void Function(double progress, String detail)? onProgress,
  }) async {
    // 1. Try Piped instances
    for (final instance in _pipedInstances) {
      try {
        onProgress?.call(0.14, 'Mencoba mirror Piped ($instance)...');
        final resp = await _dio
            .get<dynamic>('$instance/streams/$videoId')
            .timeout(const Duration(seconds: 10));
        final map = _ensureMap(resp.data);
        final audioStreams = map?['audioStreams'];
        if (audioStreams is List && audioStreams.isNotEmpty) {
          final sorted = audioStreams
              .map(_ensureMap)
              .whereType<Map<String, dynamic>>()
              .toList()
            ..sort(
              (a, b) => _parseInt(b['bitrate']).compareTo(_parseInt(a['bitrate'])),
            );

          for (final stream in sorted.take(2)) {
            final url = (stream['url']?.toString() ?? '').trim();
            if (url.isEmpty) continue;
            final mime = (stream['mimeType']?.toString() ?? '').toLowerCase();
            final ext = mime.contains('mp4') ? 'm4a' : 'webm';
            final outFile = File(
              '${tempDir.path}${Platform.pathSeparator}spotmeta_piped_${DateTime.now().millisecondsSinceEpoch}.$ext',
            );
            final downloaded = await _downloadGenericHttpAudio(
              url: url,
              targetFile: outFile,
              label: 'Piped ${ext.toUpperCase()}',
              onProgress: onProgress,
            );
            if (downloaded != null) return downloaded;
          }
        }
      } catch (e) {
        debugPrint('[AUTO_E2E] TAHAP_4: Piped $instance gagal: $e');
      }
    }

    // 2. Try Invidious instances
    for (final instance in _invidiousInstances) {
      try {
        onProgress?.call(0.15, 'Mencoba mirror Invidious ($instance)...');
        final resp = await _dio
            .get<dynamic>('$instance/api/v1/videos/$videoId')
            .timeout(const Duration(seconds: 10));
        final map = _ensureMap(resp.data);
        final adaptive = map?['adaptiveFormats'];
        if (adaptive is List && adaptive.isNotEmpty) {
          final audioItems = adaptive
              .map(_ensureMap)
              .whereType<Map<String, dynamic>>()
              .where((m) =>
                  (m['type']?.toString() ?? '').toLowerCase().startsWith('audio/'))
              .toList()
            ..sort(
              (a, b) => _parseInt(b['bitrate']).compareTo(_parseInt(a['bitrate'])),
            );

          for (final item in audioItems.take(2)) {
            final url = (item['url']?.toString() ?? '').trim();
            if (url.isEmpty) continue;
            final outFile = File(
              '${tempDir.path}${Platform.pathSeparator}spotmeta_inv_${DateTime.now().millisecondsSinceEpoch}.m4a',
            );
            final downloaded = await _downloadGenericHttpAudio(
              url: url,
              targetFile: outFile,
              label: 'Invidious Audio',
              onProgress: onProgress,
            );
            if (downloaded != null) return downloaded;
          }
        }
      } catch (e) {
        debugPrint('[AUTO_E2E] TAHAP_4: Invidious $instance gagal: $e');
      }
    }

    return null;
  }

  /// Fallback 3: Public Music CDN API (320kbps M4A/MP4 direct CDN stream)
  /// used if YouTube / Piped / Invidious are blocked or throttled on the network.
  Future<File?> _tryPublicAudioCdnFallback({
    required TrackMetadata metadata,
    required Directory tempDir,
    void Function(double progress, String detail)? onProgress,
  }) async {
    final primaryArtist = metadata.artist.split(',').first.trim();
    final cleanTitle = metadata.title
        .replaceAll(
          RegExp(r'\s*[\(\[](feat\.?|ft\.?|with\s).*?[\)\]]',
              caseSensitive: false),
          '',
        )
        .trim();
    final query = '$primaryArtist $cleanTitle';

    for (final endpoint in _saavnApiInstances) {
      try {
        onProgress?.call(0.15, 'Mengambil stream dari Public Audio CDN...');
        debugPrint('[AUTO_E2E] TAHAP_4: Query Public Audio CDN $endpoint?query=$query');

        final resp = await _dio
            .get<dynamic>(
              endpoint,
              queryParameters: {'query': query, 'limit': 8},
            )
            .timeout(const Duration(seconds: 12));

        final root = _ensureMap(resp.data);
        if (root == null) continue;

        List<dynamic> results = const [];
        final dataField = root['data'];
        if (dataField is Map) {
          final innerResults = dataField['results'];
          if (innerResults is List) results = innerResults;
        } else if (dataField is List) {
          results = dataField;
        } else if (root['results'] is List) {
          results = root['results'] as List<dynamic>;
        }

        if (results.isEmpty) continue;

        // Pick best candidate matching duration (±10s) or first result
        Map<String, dynamic>? chosenSong;
        for (final item in results) {
          final map = _ensureMap(item);
          if (map == null) continue;
          chosenSong ??= map;
          final dur = _parseInt(map['duration']);
          if (metadata.durationSeconds > 0 &&
              dur > 0 &&
              (dur - metadata.durationSeconds).abs() <= 10) {
            chosenSong = map;
            break;
          }
        }

        if (chosenSong == null) continue;

        final downloadUrls = chosenSong['downloadUrl'] ?? chosenSong['download_url'];
        String bestStreamUrl = '';

        if (downloadUrls is List && downloadUrls.isNotEmpty) {
          // Pick highest quality (usually last item in list, e.g. 320kbps)
          for (final u in downloadUrls.reversed) {
            final uMap = _ensureMap(u);
            final link =
                (uMap?['url'] ?? uMap?['link'] ?? '').toString().trim();
            if (link.startsWith('http')) {
              bestStreamUrl = link;
              break;
            }
          }
        } else if (downloadUrls is String && downloadUrls.startsWith('http')) {
          bestStreamUrl = downloadUrls;
        }

        if (bestStreamUrl.isEmpty) continue;

        debugPrint(
          '[AUTO_E2E] TAHAP_4: Stream Public CDN ditemukan: $bestStreamUrl',
        );

        final outFile = File(
          '${tempDir.path}${Platform.pathSeparator}spotmeta_cdn_${DateTime.now().millisecondsSinceEpoch}.m4a',
        );

        final downloaded = await _downloadGenericHttpAudio(
          url: bestStreamUrl,
          targetFile: outFile,
          label: 'AAC 320kbps',
          onProgress: onProgress,
        );
        if (downloaded != null) {
          debugPrint(
            '[AUTO_E2E] TAHAP_4: Unduhan Public Audio CDN BERHASIL -> ${downloaded.path} (${await downloaded.length()} bytes)',
          );
          return downloaded;
        }
      } catch (e, s) {
        debugPrint('[AUTO_E2E] TAHAP_4: Public Audio CDN $endpoint gagal: $e\n$s');
      }
    }

    return null;
  }

  Future<File?> _downloadGenericHttpAudio({
    required String url,
    required File targetFile,
    required String label,
    void Function(double progress, String detail)? onProgress,
  }) async {
    try {
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      int lastUiMs = 0;
      await _dio
          .download(
            url,
            targetFile.path,
            onReceiveProgress: (received, total) {
              final nowMs = DateTime.now().millisecondsSinceEpoch;
              if (nowMs - lastUiMs >= 80 || (total > 0 && received >= total)) {
                lastUiMs = nowMs;
                final recMb = (received / (1024 * 1024)).toStringAsFixed(2);
                if (total > 0) {
                  final ratio = (received / total).clamp(0.0, 1.0);
                  final mapped = 0.16 + (ratio * 0.84);
                  final totMb = (total / (1024 * 1024)).toStringAsFixed(2);
                  onProgress?.call(
                    mapped,
                    'Mengunduh audio ($label): $recMb MB / $totMb MB',
                  );
                } else {
                  onProgress?.call(
                    0.55,
                    'Mengunduh audio ($label): $recMb MB',
                  );
                }
              }
            },
          )
          .timeout(const Duration(seconds: 45));

      if (await targetFile.exists() && await targetFile.length() >= 65536) {
        onProgress?.call(1.0, 'Unduhan stream audio selesai.');
        return targetFile;
      }
    } catch (e) {
      debugPrint('[AUTO_E2E] TAHAP_4: _downloadGenericHttpAudio ($label) gagal: $e');
      try {
        if (await targetFile.exists()) await targetFile.delete();
      } catch (_) {}
    }
    return null;
  }

  List<Video> _rankTopCandidates(
    List<Video> batch,
    int targetDurationSeconds,
  ) {
    if (batch.isEmpty) return const [];
    if (targetDurationSeconds <= 0) return batch;

    final withinFive = <Video>[];
    final withinTen = <Video>[];
    final others = <Video>[];

    for (final video in batch) {
      final dur = video.duration?.inSeconds;
      if (dur != null) {
        final diff = (dur - targetDurationSeconds).abs();
        if (diff <= 5) {
          withinFive.add(video);
          continue;
        } else if (diff <= 10) {
          withinTen.add(video);
          continue;
        }
      }
      others.add(video);
    }

    withinFive.sort(
      (a, b) => _scoreCandidate(b, targetDurationSeconds)
          .compareTo(_scoreCandidate(a, targetDurationSeconds)),
    );
    withinTen.sort(
      (a, b) => _scoreCandidate(b, targetDurationSeconds)
          .compareTo(_scoreCandidate(a, targetDurationSeconds)),
    );

    return [
      ...withinFive,
      ...withinTen,
      ...others,
    ];
  }

  int _scoreCandidate(Video video, int targetDurationSeconds) {
    int score = 100;
    final dur = video.duration?.inSeconds ?? targetDurationSeconds;
    score -= (dur - targetDurationSeconds).abs() * 5;

    final lowerTitle = video.title.toLowerCase();
    final lowerAuthor = video.author.toLowerCase();

    if (lowerTitle.contains('official audio') ||
        lowerTitle.contains('audio') ||
        lowerAuthor.contains('topic')) {
      score += 20;
    }
    if (lowerTitle.contains('live') ||
        lowerTitle.contains('concert') ||
        lowerTitle.contains('karaoke') ||
        lowerTitle.contains('extended')) {
      score -= 35;
    }
    return score;
  }

  List<StreamInfo> _buildPrioritizedStreams(
    StreamManifest manifest, {
    required String profileName,
  }) {
    final audioOnlyList = manifest.audioOnly.toList();

    final mp4Audio = <AudioOnlyStreamInfo>[];
    final otherAudio = <AudioOnlyStreamInfo>[];

    for (final stream in audioOnlyList) {
      final containerName = stream.container.name.toLowerCase();
      if (containerName == 'mp4' || containerName == 'm4a') {
        mp4Audio.add(stream);
      } else {
        otherAudio.add(stream);
      }
    }

    mp4Audio.sort(
      (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond),
    );
    otherAudio.sort(
      (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond),
    );

    final muxedList = manifest.muxed.toList()
      ..sort(
        (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond),
      );

    // On AndroidSdkless, YoutubeExplode validates streams.first (muxed tag=18)
    // and YouTube only permits downloading one stream per Android manifest without PO token.
    // Putting muxed first on AndroidSdkless guarantees a fast 200 OK download.
    if (profileName == 'AndroidSdkless') {
      return <StreamInfo>[
        ...muxedList,
        ...mp4Audio,
        ...otherAudio,
      ];
    }

    return <StreamInfo>[
      ...mp4Audio.take(1),
      ...muxedList.take(1),
      ...otherAudio.take(1),
      ...mp4Audio.skip(1),
      ...otherAudio.skip(1),
      ...muxedList.skip(1),
    ];
  }

  Future<File> _downloadStreamWithChunkTimeout({
    required YoutubeExplode yt,
    required StreamInfo streamInfo,
    required File targetFile,
    required String clientName,
    void Function(double progress, String detail)? onProgress,
  }) async {
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final totalBytes = streamInfo.size.totalBytes;
    final bitrateKbps = (streamInfo.bitrate.kiloBitsPerSecond).round();
    final containerLabel = streamInfo.container.name.toUpperCase();
    final streamTypeLabel =
        streamInfo is AudioOnlyStreamInfo ? 'Audio' : 'Muxed';

    onProgress?.call(
      0.16,
      'Menghubungkan stream $streamTypeLabel $containerLabel (${bitrateKbps}kbps - $clientName)...',
    );

    final fileSink = targetFile.openWrite();
    int receivedBytes = 0;
    int lastUiUpdateMs = 0;

    final completer = Completer<void>();
    StreamSubscription<List<int>>? subscription;
    Timer? chunkTimer;

    void resetChunkTimer() {
      chunkTimer?.cancel();
      chunkTimer = Timer(const Duration(seconds: 12), () {
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException(
              'Stream stalled selama 12 detik ($receivedBytes bytes diterima).',
            ),
          );
          unawaited(subscription?.cancel());
        }
      });
    }

    try {
      resetChunkTimer();

      final byteStream = yt.videos.streamsClient
          .get(streamInfo)
          .timeout(const Duration(seconds: 12));

      subscription = byteStream.listen(
        (chunk) {
          if (completer.isCompleted) return;
          resetChunkTimer();

          fileSink.add(chunk);
          receivedBytes += chunk.length;

          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (nowMs - lastUiUpdateMs >= 80 || receivedBytes == totalBytes) {
            lastUiUpdateMs = nowMs;
            final downloadedMb =
                (receivedBytes / (1024 * 1024)).toStringAsFixed(2);

            if (totalBytes > 0) {
              final ratio = (receivedBytes / totalBytes).clamp(0.0, 1.0);
              final mappedProgress = 0.16 + (ratio * 0.84);
              final totalMb = (totalBytes / (1024 * 1024)).toStringAsFixed(2);
              onProgress?.call(
                mappedProgress,
                'Mengunduh audio ($containerLabel ${bitrateKbps}kbps): $downloadedMb MB / $totalMb MB',
              );
            } else {
              onProgress?.call(
                0.55,
                'Mengunduh audio ($containerLabel ${bitrateKbps}kbps): $downloadedMb MB',
              );
            }
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        cancelOnError: true,
      );

      await completer.future;
      chunkTimer?.cancel();
      await fileSink.flush();
    } finally {
      chunkTimer?.cancel();
      unawaited(subscription?.cancel());
      try {
        await fileSink.close();
      } catch (_) {}
    }

    if (!await targetFile.exists() || await targetFile.length() < 65536) {
      throw const AudioExtractionException(
        'File stream audio kosong atau terlalu kecil (< 64 KB).',
      );
    }

    return targetFile;
  }

  Future<T> _runWithHardTimeout<T>({
    required Future<T> Function() action,
    required Duration timeout,
    required void Function() onTimeoutDispose,
  }) async {
    final completer = Completer<T>();
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        onTimeoutDispose();
        completer.completeError(
          TimeoutException(
              'Operasi melewati batas waktu ${timeout.inSeconds} detik.'),
        );
      }
    });

    try {
      final result = await action();
      if (!completer.isCompleted) {
        completer.complete(result);
      }
      return await completer.future;
    } catch (e, s) {
      if (!completer.isCompleted) {
        completer.completeError(e, s);
      }
      return await completer.future;
    } finally {
      timer.cancel();
    }
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

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final totalSeconds = duration.inSeconds;
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }
}

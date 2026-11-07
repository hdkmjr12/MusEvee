class TrackMetadata {
  final String spotifyUrl;
  final String title;
  final String artist;
  final String album;
  final String releaseYear;
  final int durationSeconds;
  final String coverUrl;
  final String? syncedLyrics;
  final String? plainLyrics;
  final String? previewAudioUrl;
  final String? preferredYoutubeVideoId;

  const TrackMetadata({
    required this.spotifyUrl,
    required this.title,
    required this.artist,
    required this.album,
    required this.releaseYear,
    required this.durationSeconds,
    required this.coverUrl,
    this.syncedLyrics,
    this.plainLyrics,
    this.previewAudioUrl,
    this.preferredYoutubeVideoId,
  });

  TrackMetadata copyWith({
    String? spotifyUrl,
    String? title,
    String? artist,
    String? album,
    String? releaseYear,
    int? durationSeconds,
    String? coverUrl,
    String? syncedLyrics,
    String? plainLyrics,
    String? previewAudioUrl,
    String? preferredYoutubeVideoId,
    bool clearSyncedLyrics = false,
    bool clearPreferredYoutubeVideoId = false,
  }) {
    return TrackMetadata(
      spotifyUrl: spotifyUrl ?? this.spotifyUrl,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      releaseYear: releaseYear ?? this.releaseYear,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      coverUrl: coverUrl ?? this.coverUrl,
      syncedLyrics:
          clearSyncedLyrics ? null : (syncedLyrics ?? this.syncedLyrics),
      plainLyrics: plainLyrics ?? this.plainLyrics,
      previewAudioUrl: previewAudioUrl ?? this.previewAudioUrl,
      preferredYoutubeVideoId: clearPreferredYoutubeVideoId
          ? null
          : (preferredYoutubeVideoId ?? this.preferredYoutubeVideoId),
    );
  }

  bool get hasSyncedLyrics =>
      syncedLyrics != null && syncedLyrics!.trim().isNotEmpty;

  bool get hasPlainLyrics =>
      plainLyrics != null && plainLyrics!.trim().isNotEmpty;

  bool get hasAnyLyrics => hasSyncedLyrics || hasPlainLyrics;

  String? get bestLyrics {
    if (hasPlainLyrics) return plainLyrics!.trim();
    if (hasSyncedLyrics) return cleanPlainLyrics;
    return null;
  }

  /// Returns synchronized LRC lyrics (`[mm:ss.xx] line`) normalized with `\r\n`
  /// line breaks for Musicolet's embedded USLT synced lyrics support.
  String? get normalizedSyncedLyrics {
    if (!hasSyncedLyrics) return null;
    final normalized = syncedLyrics!
        .trim()
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\n', '\r\n');
    return normalized.isNotEmpty ? normalized : null;
  }

  /// Returns clean plain lyrics without `[mm:ss.xx]` timestamps and normalized
  /// with `\r\n` line breaks (matching ID3v2.4 `USLT` format for Musicolet).
  String? get cleanPlainLyrics {
    if (hasPlainLyrics) {
      return plainLyrics!
          .trim()
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .replaceAll('\n', '\r\n');
    }
    if (hasSyncedLyrics) {
      final cleanedLines = syncedLyrics!
          .split(RegExp(r'\r?\n'))
          .where(
            (line) => !RegExp(
              r'^\[(ti|ar|al|by|offset|length|re|ve):',
              caseSensitive: false,
            ).hasMatch(line.trim()),
          )
          .map(
            (line) => line
                .replaceAll(RegExp(r'\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]'), '')
                .trim(),
          )
          .toList();
      final joined = cleanedLines.join('\r\n').trim();
      return joined.isNotEmpty ? joined : null;
    }
    return null;
  }

  /// Selects the appropriate lyrics payload (`syncedLyrics` with `[mm:ss.xx]` or
  /// `cleanPlainLyrics`) based on [preferSyncedLyrics].
  String? lyricsForEmbedding({required bool preferSyncedLyrics}) {
    if (preferSyncedLyrics && hasSyncedLyrics) {
      return normalizedSyncedLyrics;
    }
    return cleanPlainLyrics ?? normalizedSyncedLyrics;
  }

  String get formattedDuration {
    if (durationSeconds <= 0) return '00:00';
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    final minStr = minutes.toString().padLeft(2, '0');
    final secStr = seconds.toString().padLeft(2, '0');
    return '$minStr:$secStr';
  }

  List<String> get previewLyricsLines {
    final raw = cleanPlainLyrics ?? bestLyrics;
    if (raw == null || raw.isEmpty) return const [];

    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    return lines.take(4).toList();
  }

  String get sanitizedFileName {
    final rawName = '$artist - $title';
    final cleaned = rawName
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final safeBase = cleaned.isEmpty ? 'SpotMeta_Track' : cleaned;
    return '$safeBase.mp3';
  }
}

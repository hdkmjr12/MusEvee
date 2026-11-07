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

  /// Normalizes a single title or artist string (lowercase, macron/accent folding,
  /// Katakana->Hiragana unification, noise-tag removal, and punctuation stripping)
  /// for smart duplicate detection across local folders and playlists.
  static String normalizeTrackSegment(String raw, {bool stripFeat = false}) {
    if (raw.trim().isEmpty) return '';
    var s = raw.toLowerCase().trim();

    // Fold macrons & common Latin diacritics
    const diacritics = <String, String>{
      'ā': 'a',
      'ī': 'i',
      'ū': 'u',
      'ē': 'e',
      'ō': 'o',
      'â': 'a',
      'î': 'i',
      'û': 'u',
      'ê': 'e',
      'ô': 'o',
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ä': 'a',
      'ë': 'e',
      'ï': 'i',
      'ö': 'o',
      'ü': 'u',
    };
    diacritics.forEach((k, v) {
      s = s.replaceAll(k, v);
    });

    // Unify Katakana -> Hiragana so e.g. さユり == さゆり == サユリ
    final sb = StringBuffer();
    for (final rune in s.runes) {
      if (rune >= 0x30A1 && rune <= 0x30F6) {
        sb.writeCharCode(rune - 0x60);
      } else {
        sb.writeCharCode(rune);
      }
    }
    s = sb.toString();

    // Remove video/audio noise suffixes while keeping real remix/live qualifiers
    s = s.replaceAll(
      RegExp(
        r'[\(\[\{]\s*(?:official\s*(?:music\s*)?(?:video|audio|mv|lyric\s*video)|lyric\s*video|lyrics?|audio|mv|hd|hq|remastered(?:\s*\d{2,4})?)\s*[\)\]\}]',
        caseSensitive: false,
      ),
      ' ',
    );
    s = s.replaceAll(
      RegExp(r'\b(?:official\s+music\s+video|official\s+video|official\s+audio)\b'),
      ' ',
    );

    if (stripFeat) {
      s = s.replaceAll(
        RegExp(r'[\(\[\{]?\b(?:feat\.?|ft\.?|featuring|cv\.?)\b.*$'),
        ' ',
      );
      final primarySplit = s.split(RegExp(r'[,&/×;]'));
      if (primarySplit.isNotEmpty && primarySplit.first.trim().isNotEmpty) {
        s = primarySplit.first;
      }
    }

    // Fold Romaji long vowels on pure ASCII words
    if (RegExp(r'^[a-z0-9\s\-\x27]+$').hasMatch(s)) {
      s = s
          .replaceAll('ou', 'o')
          .replaceAll('uu', 'u')
          .replaceAll('oo', 'o');
    }

    s = s.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
    return s;
  }

  /// Builds a canonical track identity `artist::title` for smart deduplication.
  static String normalizeTrackIdentity(String title, [String artist = '']) {
    final normTitle = normalizeTrackSegment(title, stripFeat: true);
    final normArtist = normalizeTrackSegment(artist, stripFeat: true);
    if (normArtist.isEmpty) return normTitle;
    return '$normArtist::$normTitle';
  }
}

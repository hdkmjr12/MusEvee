import 'track_metadata.dart';

class SyncedLyricEntry {
  final int timeMs;
  final String text;

  const SyncedLyricEntry({
    required this.timeMs,
    required this.text,
  });

  String get formattedTime {
    final totalSeconds = (timeMs ~/ 1000).clamp(0, 359999);
    final mins = totalSeconds ~/ 60;
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }
}

/// Unique queue item wrapper so duplicate songs in the playback queue keep
/// distinct widget keys (`ValueKey(entry.queueId)`) and stable active indices
/// during drag-and-drop reorder or shuffle/unshuffle transitions.
class QueueEntry {
  final String queueId;
  final LocalSong song;

  const QueueEntry({
    required this.queueId,
    required this.song,
  });

  QueueEntry copyWith({
    String? queueId,
    LocalSong? song,
  }) {
    return QueueEntry(
      queueId: queueId ?? this.queueId,
      song: song ?? this.song,
    );
  }
}

class LocalSong {
  static final Expando<List<SyncedLyricEntry>> _syncedLyricsMemo =
      Expando<List<SyncedLyricEntry>>('syncedLyricsMemo');
  static final Expando<List<String>> _plainLinesMemo =
      Expando<List<String>>('plainLinesMemo');

  static final RegExp _lrcLineTimeRegex = RegExp(
    r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]',
  );
  static final RegExp _lrcHeaderRegex = RegExp(
    r'^\[(ti|ar|al|by|length|re|ve):.*\]$',
    caseSensitive: false,
  );
  static final RegExp _lrcOffsetRegex = RegExp(
    r'^\[offset:\s*([+-]?\d+)\s*\]$',
    caseSensitive: false,
  );

  final String filePath;
  final String fileName;
  final String folderName;
  final String title;
  final String artist;
  final String album;
  final String year;
  final int durationMs;
  final int sizeBytes;
  final int bitrateKbps;
  final int sampleRateHz;
  final String? coverFilePath;
  final String? usltLyrics;
  final bool hasLyricsFlag;
  final bool hasSyncedLyricsFlag;
  final int dominantColorValue;
  final int lastModifiedMs;

  const LocalSong({
    required this.filePath,
    required this.fileName,
    required this.folderName,
    required this.title,
    required this.artist,
    required this.album,
    required this.year,
    required this.durationMs,
    required this.sizeBytes,
    required this.bitrateKbps,
    required this.sampleRateHz,
    this.coverFilePath,
    this.usltLyrics,
    this.hasLyricsFlag = false,
    this.hasSyncedLyricsFlag = false,
    this.dominantColorValue = 0xFF1E222B,
    this.lastModifiedMs = 0,
  });

  factory LocalSong.fromNativeMap(Map<dynamic, dynamic> map) {
    final rawPath = (map['filePath']?.toString() ?? '').trim();
    final rawFileName = (map['fileName']?.toString() ?? '').trim();
    final rawFolder = (map['folderName']?.toString() ?? 'Music').trim();
    final rawTitle = (map['title']?.toString() ?? '').trim();
    final rawArtist = (map['artist']?.toString() ?? '').trim();
    final rawAlbum = (map['album']?.toString() ?? '').trim();
    final rawYear = (map['year']?.toString() ?? '').trim();

    int parseInt(dynamic v, [int fallback = 0]) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    final rawCover = (map['coverFilePath']?.toString() ?? '').trim();
    final rawUslt = (map['usltLyrics']?.toString() ?? '').trim();
    final explicitHasLyrics = map['hasLyrics'] == true;
    final explicitHasSynced = map['hasSyncedLyrics'] == true;
    final computedHasLyrics = explicitHasLyrics || rawUslt.isNotEmpty;
    final computedHasSynced = explicitHasSynced ||
        (rawUslt.isNotEmpty && _lrcLineTimeRegex.hasMatch(rawUslt));

    return LocalSong(
      filePath: rawPath,
      fileName: rawFileName.isNotEmpty
          ? rawFileName
          : rawPath.split('/').last,
      folderName: rawFolder.isNotEmpty ? rawFolder : 'Music',
      title: rawTitle.isNotEmpty ? rawTitle : rawFileName,
      artist: rawArtist.isNotEmpty ? rawArtist : 'Unknown Artist',
      album: rawAlbum.isNotEmpty ? rawAlbum : 'Unknown Album',
      year: rawYear,
      durationMs: parseInt(map['durationMs']),
      sizeBytes: parseInt(map['sizeBytes']),
      bitrateKbps: parseInt(map['bitrateKbps'], 320),
      sampleRateHz: parseInt(map['sampleRateHz'], 44100),
      coverFilePath: rawCover.isNotEmpty ? rawCover : null,
      usltLyrics: rawUslt.isNotEmpty ? rawUslt : null,
      hasLyricsFlag: computedHasLyrics,
      hasSyncedLyricsFlag: computedHasSynced,
      dominantColorValue: parseInt(
        map['dominantColor'] ?? map['dominantColorValue'],
        0xFF1E222B,
      ),
      lastModifiedMs: parseInt(map['lastModifiedMs']),
    );
  }

  factory LocalSong.fromJson(Map<String, dynamic> json) =>
      LocalSong.fromNativeMap(json);

  /// Compact metadata-only serialization for `musevee_library_cache_v1.json`.
  /// Full `usltLyrics` strings are intentionally omitted from disk cache and
  /// loaded on-demand when a track is played so User Data stays under 5 MB.
  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'fileName': fileName,
      'folderName': folderName,
      'title': title,
      'artist': artist,
      'album': album,
      'year': year,
      'durationMs': durationMs,
      'sizeBytes': sizeBytes,
      'bitrateKbps': bitrateKbps,
      'sampleRateHz': sampleRateHz,
      'coverFilePath': coverFilePath,
      'hasLyrics': hasLyrics,
      'hasSyncedLyrics': hasSyncedLyrics,
      'dominantColor': dominantColorValue,
      'lastModifiedMs': lastModifiedMs,
    };
  }

  LocalSong copyWith({
    String? filePath,
    String? fileName,
    String? folderName,
    String? title,
    String? artist,
    String? album,
    String? year,
    int? durationMs,
    int? sizeBytes,
    int? bitrateKbps,
    int? sampleRateHz,
    String? coverFilePath,
    String? usltLyrics,
    bool? hasLyricsFlag,
    bool? hasSyncedLyricsFlag,
    int? dominantColorValue,
    int? lastModifiedMs,
    bool clearLyrics = false,
  }) {
    final resolvedUslt =
        clearLyrics ? null : (usltLyrics ?? this.usltLyrics);
    return LocalSong(
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      folderName: folderName ?? this.folderName,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      year: year ?? this.year,
      durationMs: durationMs ?? this.durationMs,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      coverFilePath: coverFilePath ?? this.coverFilePath,
      usltLyrics: resolvedUslt,
      hasLyricsFlag: clearLyrics
          ? false
          : (hasLyricsFlag ??
              (resolvedUslt != null && resolvedUslt.trim().isNotEmpty
                  ? true
                  : this.hasLyricsFlag)),
      hasSyncedLyricsFlag: clearLyrics
          ? false
          : (hasSyncedLyricsFlag ??
              (resolvedUslt != null && _lrcLineTimeRegex.hasMatch(resolvedUslt)
                  ? true
                  : this.hasSyncedLyricsFlag)),
      dominantColorValue: dominantColorValue ?? this.dominantColorValue,
      lastModifiedMs: lastModifiedMs ?? this.lastModifiedMs,
    );
  }

  bool get hasCover =>
      coverFilePath != null && coverFilePath!.trim().isNotEmpty;

  bool get hasLyrics =>
      hasLyricsFlag || (usltLyrics != null && usltLyrics!.trim().isNotEmpty);

  bool get hasSyncedLyrics =>
      hasSyncedLyricsFlag ||
      (usltLyrics != null && _lrcLineTimeRegex.hasMatch(usltLyrics!));

  /// True when the actual `USLT` text payload is currently hydrated in RAM.
  bool get isLyricsLoadedInMemory =>
      usltLyrics != null && usltLyrics!.trim().isNotEmpty;

  /// Resolves the physical parent directory path containing this audio file.
  String get folderPath {
    final normalized = filePath.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    if (idx > 0) {
      return normalized.substring(0, idx);
    }
    return '/storage/emulated/0/Music/$folderName';
  }

  int get durationSeconds =>
      durationMs > 0 ? (durationMs / 1000).round() : 0;

  /// Musicolet-style compact duration (`3:47` or `0:20`).
  String get formattedDuration => formatMillis(durationMs);

  String get formattedFileSize {
    if (sizeBytes <= 0) return '0 MB';
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(2)} MB';
  }

  static String formatMillis(int ms) {
    if (ms <= 0) return '0:00';
    final totalSec = ms ~/ 1000;
    final mins = totalSec ~/ 60;
    final secs = (totalSec % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  /// Parses embedded LRC timestamps `[mm:ss.xx]` into sorted [SyncedLyricEntry] items.
  List<SyncedLyricEntry> get parsedSyncedLyrics {
    final rawText = usltLyrics;
    if (!hasSyncedLyrics || rawText == null || rawText.trim().isEmpty) {
      return const [];
    }
    final cached = _syncedLyricsMemo[this];
    if (cached != null) return cached;

    final raw = rawText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = raw.split('\n');

    int globalOffsetMs = 0;
    final entries = <SyncedLyricEntry>[];

    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      final offsetMatch = _lrcOffsetRegex.firstMatch(trimmed);
      if (offsetMatch != null) {
        globalOffsetMs = int.tryParse(offsetMatch.group(1) ?? '0') ?? 0;
        continue;
      }
      if (_lrcHeaderRegex.hasMatch(trimmed)) continue;

      final matches = _lrcLineTimeRegex.allMatches(trimmed).toList();
      if (matches.isEmpty) continue;

      final content = trimmed.replaceAll(_lrcLineTimeRegex, '').trim();
      for (final m in matches) {
        final mins = int.tryParse(m.group(1) ?? '0') ?? 0;
        final secs = int.tryParse(m.group(2) ?? '0') ?? 0;
        final fracStr = m.group(3) ?? '';
        int ms = 0;
        if (fracStr.length == 1) {
          ms = (int.tryParse(fracStr) ?? 0) * 100;
        } else if (fracStr.length == 2) {
          ms = (int.tryParse(fracStr) ?? 0) * 10;
        } else if (fracStr.length >= 3) {
          ms = int.tryParse(fracStr.substring(0, 3)) ?? 0;
        }
        final totalMs =
            ((mins * 60 + secs) * 1000 + ms + globalOffsetMs).clamp(0, 86400000);
        entries.add(SyncedLyricEntry(timeMs: totalMs, text: content));
      }
    }

    entries.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    final unmodifiable = List<SyncedLyricEntry>.unmodifiable(entries);
    _syncedLyricsMemo[this] = unmodifiable;
    return unmodifiable;
  }

  /// Returns clean plain lyrics lines (without timestamps or LRC headers).
  List<String> get plainLyricLines {
    final rawText = usltLyrics;
    if (!hasLyrics || rawText == null || rawText.trim().isEmpty) {
      return const [];
    }
    final cached = _plainLinesMemo[this];
    if (cached != null) return cached;

    final raw = rawText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final out = <String>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (_lrcHeaderRegex.hasMatch(trimmed) ||
          _lrcOffsetRegex.hasMatch(trimmed)) {
        continue;
      }
      final cleaned = trimmed.replaceAll(_lrcLineTimeRegex, '').trim();
      out.add(cleaned);
    }
    final unmodifiable = List<String>.unmodifiable(out);
    _plainLinesMemo[this] = unmodifiable;
    return unmodifiable;
  }

  /// Converts this [LocalSong] to [TrackMetadata] for compatibility with
  /// `TagEditorSheet`, `RomajiService`, `LyricsService`, and `TaggingService`.
  TrackMetadata toTrackMetadata() {
    final synced = hasSyncedLyrics ? usltLyrics : null;
    final plain = hasLyrics ? plainLyricLines.join('\n').trim() : null;
    return TrackMetadata(
      spotifyUrl: 'local:$filePath',
      title: title,
      artist: artist,
      album: album,
      releaseYear: year,
      durationSeconds: durationSeconds,
      coverUrl: '',
      syncedLyrics: synced,
      plainLyrics: plain,
    );
  }
}

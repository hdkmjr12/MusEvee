import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/local_song.dart';
import '../services/folder_service.dart';
import '../services/lyrics_service.dart';
import '../services/romaji_service.dart';
import '../services/tagging_service.dart';

/// Musicolet's playback loop / advance modes:
/// - `repeatAll`: Repeat entire queue (`🔁`)
/// - `repeatOne`: Repeat single track (`🔂`)
/// - `playSingleStop`: Musicolet's signature `1→` (play current track then stop)
/// - `playQueueOnce`: Play queue until end then stop (`→|`)
enum MusicoletPlayMode {
  repeatAll,
  repeatOne,
  playSingleStop,
  playQueueOnce,
}

enum EmbeddedLyricsDisplayMode {
  synced,
  plain,
}

/// Lightweight value object isolating 200ms (`5 Hz`) playback position updates
/// so only Seekbar and MiniPlayer progress bar rebuild — NOT the 8 tabs!
class PlaybackProgress {
  final int positionMs;
  final int durationMs;

  const PlaybackProgress({
    required this.positionMs,
    required this.durationMs,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackProgress &&
          positionMs == other.positionMs &&
          durationMs == other.durationMs;

  @override
  int get hashCode => Object.hash(positionMs, durationMs);
}

class LocalMusicProvider extends ChangeNotifier {
  static const MethodChannel _systemChannel = MethodChannel(
    'com.spotmeta.downloader/system',
  );

  static const List<double> fontSizePresets = [13.5, 15.5, 18.0, 20.5];

  final FolderService _folderService;
  final TaggingService _taggingService;
  final RomajiService _romajiService;
  final LyricsService _lyricsService;
  final Random _random = Random();

  LocalMusicProvider({
    FolderService? folderService,
    TaggingService? taggingService,
    RomajiService? romajiService,
    LyricsService? lyricsService,
  })  : _folderService = folderService ?? FolderService(),
        _taggingService = taggingService ?? TaggingService(),
        _romajiService = romajiService ?? RomajiService(),
        _lyricsService = lyricsService ?? LyricsService() {
    _initialize();
  }

  List<LocalSong> _allSongs = [];
  List<String> _availableFolders =
      List<String>.from(FolderService.defaultFolders);
  final Set<String> _favoritePaths = {};
  bool _isLoadingLibrary = false;
  bool _isSyncingLibrary = false;

  // Memoized O(N log N) library groupings (invalidated ONLY when `_allSongs` or `_availableFolders` mutates)
  Map<String, List<LocalSong>>? _cachedFolderSongsMap;
  Map<String, List<LocalSong>>? _cachedAlbumSongsMap;
  Map<String, List<LocalSong>>? _cachedArtistSongsMap;

  void _invalidateGroupingCaches() {
    _cachedFolderSongsMap = null;
    _cachedAlbumSongsMap = null;
    _cachedArtistSongsMap = null;
  }

  // Dedicated 200ms progress & active lyric notifiers to prevent 5 Hz global tree rebuilds
  final ValueNotifier<PlaybackProgress> progressNotifier =
      ValueNotifier<PlaybackProgress>(
    const PlaybackProgress(positionMs: 0, durationMs: 0),
  );
  final ValueNotifier<int> activeLyricIndexNotifier = ValueNotifier<int>(-1);

  void _syncProgressNotifiers() {
    progressNotifier.value = PlaybackProgress(
      positionMs: _positionMs,
      durationMs: durationMs,
    );
    activeLyricIndexNotifier.value = activeSyncedLyricIndex;
  }

  @override
  void dispose() {
    progressNotifier.dispose();
    activeLyricIndexNotifier.dispose();
    super.dispose();
  }

  /// Optional 2-way sync callback so `DownloaderProvider` immediately updates
  /// folder counts, duplicate badges, and history file paths without disk rescans.
  void Function({
    required List<LocalSong> songs,
    required List<String> folders,
    String? oldPath,
    String? newPath,
    LocalSong? updatedSong,
  })? onLocalLibraryMutated;

  // Active Playback & Musicolet True Queue-Order Shuffle State
  int _nextQueueEntryCounter = 1;
  List<QueueEntry> _queueEntries = [];
  List<QueueEntry> _originalQueueEntries = [];
  int _currentIndex = -1;
  int _playbackSessionId = 0;
  int _lastCompletedSessionId = -1;
  int _seekGuardUntilEpochMs = 0;
  bool _isPlaying = false;
  bool _hasPreparedNative = false;
  int _positionMs = 0;
  int _durationMs = 0;
  double _volume = 0.85;
  MusicoletPlayMode _playMode = MusicoletPlayMode.repeatAll;
  bool _isShuffle = false;

  String _allocateQueueId() => 'qe_${_nextQueueEntryCounter++}';

  // Musicolet Now Playing Lyrics Overlay State
  bool _showLyricsOverlay = true;
  EmbeddedLyricsDisplayMode _lyricsDisplayMode =
      EmbeddedLyricsDisplayMode.synced;
  bool _autoScrollLyrics = true;
  int _fontSizeIndex = 1; // 15.5sp default

  // LRCLIB Candidates for currently playing local song
  List<LyricsCandidate> _localLyricsCandidates = const [];
  bool _isLoadingLyricsCandidates = false;
  bool _isProcessingLocalTag = false;

  // Local Search Query
  String _localSearchQuery = '';
  bool _filterFavoritesOnly = false;

  // Getters
  List<LocalSong> get allSongs => List.unmodifiable(_allSongs);
  List<String> get availableFolders => List.unmodifiable(_availableFolders);
  bool get isLoadingLibrary => _isLoadingLibrary;

  List<QueueEntry> get queueEntries => List.unmodifiable(_queueEntries);
  List<LocalSong> get queue =>
      List.unmodifiable(_queueEntries.map((e) => e.song));
  int get currentIndex => _currentIndex;
  QueueEntry? get currentQueueEntry =>
      (_currentIndex >= 0 && _currentIndex < _queueEntries.length)
          ? _queueEntries[_currentIndex]
          : null;
  LocalSong? get currentSong => currentQueueEntry?.song;

  bool get isPlaying => _isPlaying;
  int get positionMs => _positionMs;
  int get durationMs {
    if (_durationMs > 0) return _durationMs;
    return currentSong?.durationMs ?? 0;
  }

  double get volume => _volume;
  MusicoletPlayMode get playMode => _playMode;
  bool get isShuffle => _isShuffle;

  bool get showLyricsOverlay => _showLyricsOverlay;
  EmbeddedLyricsDisplayMode get lyricsDisplayMode => _lyricsDisplayMode;
  bool get autoScrollLyrics => _autoScrollLyrics;
  double get lyricsFontSize => fontSizePresets[_fontSizeIndex];

  List<LyricsCandidate> get localLyricsCandidates =>
      List.unmodifiable(_localLyricsCandidates);
  bool get isLoadingLyricsCandidates => _isLoadingLyricsCandidates;
  bool get isProcessingLocalTag => _isProcessingLocalTag;

  String get localSearchQuery => _localSearchQuery;
  bool get filterFavoritesOnly => _filterFavoritesOnly;

  bool isFavorite(String filePath) => _favoritePaths.contains(filePath);

  /// Grouped songs per folder (always includes `Music Barat`, `Music Japan`, `Music Random`).
  Map<String, List<LocalSong>> get folderSongsMap {
    final cached = _cachedFolderSongsMap;
    if (cached != null) return cached;

    final map = <String, List<LocalSong>>{};
    for (final f in _availableFolders) {
      map[f] = [];
    }
    for (final song in _allSongs) {
      map.putIfAbsent(song.folderName, () => []).add(song);
    }
    _cachedFolderSongsMap = map;
    return map;
  }

  /// Grouped songs per Album.
  Map<String, List<LocalSong>> get albumSongsMap {
    final cached = _cachedAlbumSongsMap;
    if (cached != null) return cached;

    final map = <String, List<LocalSong>>{};
    for (final song in _allSongs) {
      final key = song.album.trim().isNotEmpty ? song.album.trim() : 'Single';
      map.putIfAbsent(key, () => []).add(song);
    }
    final sortedKeys = map.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final result = {for (final k in sortedKeys) k: map[k]!};
    _cachedAlbumSongsMap = result;
    return result;
  }

  /// Grouped songs per Artist.
  Map<String, List<LocalSong>> get artistSongsMap {
    final cached = _cachedArtistSongsMap;
    if (cached != null) return cached;

    final map = <String, List<LocalSong>>{};
    for (final song in _allSongs) {
      final key = song.artist.trim().isNotEmpty
          ? song.artist.trim()
          : 'Unknown Artist';
      map.putIfAbsent(key, () => []).add(song);
    }
    final sortedKeys = map.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final result = {for (final k in sortedKeys) k: map[k]!};
    _cachedArtistSongsMap = result;
    return result;
  }

  /// Filtered local songs for the Search Lokal tab.
  List<LocalSong> get filteredLocalSongs {
    final q = _localSearchQuery.trim().toLowerCase();
    return _allSongs.where((song) {
      if (_filterFavoritesOnly && !_favoritePaths.contains(song.filePath)) {
        return false;
      }
      if (q.isEmpty) return true;
      return song.title.toLowerCase().contains(q) ||
          song.artist.toLowerCase().contains(q) ||
          song.album.toLowerCase().contains(q) ||
          song.folderName.toLowerCase().contains(q);
    }).toList();
  }

  /// Binary-searches the active synced lyric line index for [_positionMs].
  int get activeSyncedLyricIndex {
    final song = currentSong;
    if (song == null || !song.hasSyncedLyrics) return -1;
    final entries = song.parsedSyncedLyrics;
    if (entries.isEmpty) return -1;

    int low = 0;
    int high = entries.length - 1;
    int active = -1;
    // Slight +120ms lookahead makes lyric ribbon feel snappy and musical
    final targetMs = _positionMs + 120;

    while (low <= high) {
      final mid = (low + high) >> 1;
      if (entries[mid].timeMs <= targetMs) {
        active = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return active;
  }

  Future<void> _initialize() async {
    if (!Platform.isAndroid) return;
    await _loadFavorites();
    final hydrated = await _loadLibraryAndSessionCache();
    if (hydrated) {
      _syncProgressNotifiers();
      notifyListeners();
      _notifyExternalSync();
    }
    await _syncDeviceVolume();
    await refreshLibrary(
      requestPermission: true,
      silentBackground: hydrated,
    );
  }

  Future<void> _requestAudioReadPermissions() async {
    if (!Platform.isAndroid) return;
    try {
      final audioStatus = await Permission.audio.status;
      if (!audioStatus.isGranted) {
        await Permission.audio.request();
      }
    } catch (_) {}
    try {
      final storageStatus = await Permission.storage.status;
      if (!storageStatus.isGranted) {
        await Permission.storage.request();
      }
    } catch (_) {}
  }

  /// Incrementally delta-syncs `/storage/emulated/0/Music/*` and MediaStore via
  /// `MainActivity.kt` (`scanLocalMusicLibraryDelta`), inspecting only new or
  /// modified MP3 files (`lastModifiedMs` + `sizeBytes` + persistent cover file)
  /// and persisting `musicevee_library_cache_v1.json`.
  Future<void> refreshLibrary({
    bool requestPermission = false,
    bool silentBackground = false,
  }) async {
    if (!Platform.isAndroid) return;
    if (_isSyncingLibrary) return;

    _isSyncingLibrary = true;
    final showLoadingSpinner = !silentBackground || _allSongs.isEmpty;
    if (showLoadingSpinner) {
      _isLoadingLibrary = true;
      notifyListeners();
    }

    try {
      if (requestPermission) {
        await _requestAudioReadPermissions();
      }
      final prevFolders = List<String>.from(_availableFolders);
      _availableFolders = await _folderService.listAvailableFolders();

      final cachedIndex = <String, Map<String, dynamic>>{
        for (final s in _allSongs)
          s.filePath: {
            'lastModifiedMs': s.lastModifiedMs,
            'sizeBytes': s.sizeBytes,
            'coverFilePath': s.coverFilePath,
          },
      };

      final deltaResult =
          await _systemChannel.invokeMethod<Map<dynamic, dynamic>>(
        'scanLocalMusicLibraryDelta',
        {
          'folders': _availableFolders,
          'cachedIndex': cachedIndex,
        },
      );

      List<LocalSong> nextSongs;
      bool libraryMutated = false;

      if (deltaResult != null) {
        final rawPresent = deltaResult['presentPaths'] as List<dynamic>? ??
            const <dynamic>[];
        final rawUpdated = deltaResult['updatedTracks'] as List<dynamic>? ??
            const <dynamic>[];

        final presentSet = rawPresent
            .map((e) => e?.toString() ?? '')
            .where((p) => p.isNotEmpty)
            .toSet();
        final updatedByPath = <String, LocalSong>{};
        for (final item in rawUpdated) {
          if (item is Map) {
            final song = LocalSong.fromNativeMap(item);
            if (song.filePath.isNotEmpty) {
              updatedByPath[song.filePath] = song;
            }
          }
        }

        final existingByPath = {for (final s in _allSongs) s.filePath: s};
        final removedSongs = _allSongs
            .where((s) => !presentSet.contains(s.filePath))
            .toList();

        if (updatedByPath.isNotEmpty ||
            removedSongs.isNotEmpty ||
            existingByPath.length != presentSet.length) {
          libraryMutated = true;
          final merged = <LocalSong>[];
          for (final path in presentSet) {
            final updated = updatedByPath[path];
            if (updated != null) {
              merged.add(updated);
            } else {
              final existing = existingByPath[path];
              if (existing != null) {
                merged.add(existing);
              }
            }
          }
          merged.sort((a, b) {
            final cmp = b.lastModifiedMs.compareTo(a.lastModifiedMs);
            if (cmp != 0) return cmp;
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
          nextSongs = merged;

          // Clean up orphan covers for files removed externally outside MusicEvee
          if (removedSongs.isNotEmpty) {
            final activeCovers = nextSongs
                .map((s) => s.coverFilePath)
                .whereType<String>()
                .toSet();
            for (final rem in removedSongs) {
              final cov = rem.coverFilePath;
              if (cov != null && cov.isNotEmpty && !activeCovers.contains(cov)) {
                try {
                  final cf = File(cov);
                  if (await cf.exists()) {
                    await cf.delete();
                  }
                } catch (_) {}
              }
            }
          }
        } else {
          nextSongs = _allSongs;
        }
      } else {
        // Fallback if native delta handler is unavailable
        final rawList = await _systemChannel.invokeMethod<List<dynamic>>(
          'scanLocalMusicLibrary',
          {'folders': _availableFolders},
        );
        final parsed = <LocalSong>[];
        if (rawList != null) {
          for (final item in rawList) {
            if (item is Map) {
              final song = LocalSong.fromNativeMap(item);
              if (song.filePath.isNotEmpty) {
                parsed.add(song);
              }
            }
          }
        }
        parsed.sort((a, b) {
          final cmp = b.lastModifiedMs.compareTo(a.lastModifiedMs);
          if (cmp != 0) return cmp;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        nextSongs = parsed;
        libraryMutated = true;
      }

      _allSongs = nextSongs;

      // Ensure any extra folder names discovered are in _availableFolders
      final seenLower = _availableFolders.map((f) => f.toLowerCase()).toSet();
      for (final s in _allSongs) {
        if (s.folderName.isNotEmpty &&
            !seenLower.contains(s.folderName.toLowerCase())) {
          seenLower.add(s.folderName.toLowerCase());
          _availableFolders = [..._availableFolders, s.folderName];
        }
      }

      final foldersMutated = !listEquals(prevFolders, _availableFolders);
      if (libraryMutated || foldersMutated) {
        _invalidateGroupingCaches();
      }

      // Sync queue items with updated metadata & prune externally deleted files
      if (_queueEntries.isNotEmpty) {
        final byPath = {for (final s in _allSongs) s.filePath: s};
        final activeQueueId = currentQueueEntry?.queueId;
        _queueEntries = _queueEntries
            .where((e) => byPath.containsKey(e.song.filePath))
            .map((e) => e.copyWith(song: byPath[e.song.filePath]!))
            .toList();
        _originalQueueEntries = _originalQueueEntries
            .where((e) => byPath.containsKey(e.song.filePath))
            .map((e) => e.copyWith(song: byPath[e.song.filePath]!))
            .toList();

        if (_queueEntries.isEmpty) {
          if (_allSongs.isNotEmpty) {
            _setQueueFromSongs(_allSongs);
            _durationMs = _queueEntries.first.song.durationMs;
            _hasPreparedNative = false;
          } else {
            _currentIndex = -1;
            _positionMs = 0;
            _durationMs = 0;
            _hasPreparedNative = false;
          }
        } else if (activeQueueId != null) {
          final restoredIdx = _queueEntries.indexWhere(
            (e) => e.queueId == activeQueueId,
          );
          _currentIndex = restoredIdx != -1
              ? restoredIdx
              : _currentIndex.clamp(0, _queueEntries.length - 1);
        }
      } else if (_allSongs.isNotEmpty) {
        // Pre-populate queue with all local songs ready to play on first launch
        _setQueueFromSongs(_allSongs);
        _durationMs = _queueEntries.first.song.durationMs;
        _hasPreparedNative = false;
      }

      _syncProgressNotifiers();
      if (libraryMutated || foldersMutated) {
        await _saveLibraryCache();
        await _savePlayerSession();
      }
      if (libraryMutated || foldersMutated || !silentBackground) {
        _notifyExternalSync();
      }
    } catch (e) {
      debugPrint('[MusicEvee] refreshLibrary gagal: $e');
    } finally {
      _isSyncingLibrary = false;
      final wasLoading = _isLoadingLibrary;
      _isLoadingLibrary = false;
      if (wasLoading || !silentBackground) {
        notifyListeners();
      } else {
        notifyListeners();
      }
    }
  }

  void _notifyExternalSync({
    String? oldPath,
    String? newPath,
    LocalSong? updatedSong,
  }) {
    onLocalLibraryMutated?.call(
      songs: _allSongs,
      folders: _availableFolders,
      oldPath: oldPath,
      newPath: newPath,
      updatedSong: updatedSong,
    );
  }

  void _fisherYatesShuffle(List<QueueEntry> list) {
    for (int i = list.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      if (i != j) {
        final tmp = list[i];
        list[i] = list[j];
        list[j] = tmp;
      }
    }
  }

  void _setQueueFromSongs(
    List<LocalSong> songs, {
    LocalSong? startWithSong,
    bool? forceShuffle,
  }) {
    final baseEntries = songs
        .map((s) => QueueEntry(queueId: _allocateQueueId(), song: s))
        .toList();

    int chosenIdx = 0;
    if (startWithSong != null) {
      chosenIdx = baseEntries.indexWhere(
        (e) => e.song.filePath == startWithSong.filePath,
      );
      if (chosenIdx == -1) {
        baseEntries.insert(
          0,
          QueueEntry(queueId: _allocateQueueId(), song: startWithSong),
        );
        chosenIdx = 0;
      }
    }

    _originalQueueEntries = List<QueueEntry>.from(baseEntries);
    if (forceShuffle != null) {
      _isShuffle = forceShuffle;
    }

    if (_isShuffle && baseEntries.length > 1) {
      if (startWithSong != null) {
        final active = baseEntries[chosenIdx];
        final rest = <QueueEntry>[
          for (int i = 0; i < baseEntries.length; i++)
            if (i != chosenIdx) baseEntries[i],
        ];
        _fisherYatesShuffle(rest);
        _queueEntries = [active, ...rest];
        _currentIndex = 0;
      } else {
        final shuffled = List<QueueEntry>.from(baseEntries);
        _fisherYatesShuffle(shuffled);
        _queueEntries = shuffled;
        _currentIndex = 0;
      }
    } else {
      _queueEntries = List<QueueEntry>.from(baseEntries);
      _currentIndex = startWithSong != null
          ? chosenIdx
          : (baseEntries.isNotEmpty ? 0 : -1);
    }
  }

  // ===========================================================================
  // NATIVE CALLBACK HANDLERS (routed from unified MethodChannel handler)
  // ===========================================================================
  void handleNativePosition({
    required int positionMs,
    required int durationMs,
    required bool isPlaying,
    int? sessionId,
    String? path,
  }) {
    if (sessionId != null && sessionId > 0 && sessionId != _playbackSessionId) {
      return;
    }
    final activeSong = currentSong;
    if (path != null &&
        path.isNotEmpty &&
        activeSong != null &&
        path != activeSong.filePath) {
      return;
    }

    // 350ms seekbar snap-back guard: ignore stale pre-seek native ticks
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs < _seekGuardUntilEpochMs &&
        (positionMs - _positionMs).abs() > 600) {
      return;
    }

    final prevPlaying = _isPlaying;
    _positionMs = positionMs;
    if (durationMs > 0) {
      _durationMs = durationMs;
    }
    _isPlaying = isPlaying;
    _syncProgressNotifiers();
    if (prevPlaying != _isPlaying) {
      notifyListeners();
    }
  }

  void handleNativePlayerState({
    required bool isPlaying,
    required int positionMs,
    required int durationMs,
    int? sessionId,
    String? path,
  }) {
    if (sessionId != null && sessionId > 0 && sessionId != _playbackSessionId) {
      return;
    }
    final activeSong = currentSong;
    if (path != null &&
        path.isNotEmpty &&
        activeSong != null &&
        path != activeSong.filePath) {
      return;
    }

    final wasPlaying = _isPlaying;
    _isPlaying = isPlaying;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final blockedBySeekGuard =
        nowMs < _seekGuardUntilEpochMs &&
        (positionMs - _positionMs).abs() > 600;
    if (!blockedBySeekGuard &&
        positionMs >= 0 &&
        (positionMs > 0 || !isPlaying)) {
      _positionMs = positionMs;
    }
    if (durationMs > 0) {
      _durationMs = durationMs;
    }
    _syncProgressNotifiers();
    notifyListeners();
    if (wasPlaying && !isPlaying) {
      _savePlayerSession();
    }
  }

  void handleNativeTrackCompleted({int? sessionId, String? path}) {
    if (sessionId != null && sessionId > 0 && sessionId != _playbackSessionId) {
      return;
    }
    final activeSong = currentSong;
    if (path != null &&
        path.isNotEmpty &&
        activeSong != null &&
        path != activeSong.filePath) {
      return;
    }
    if (_lastCompletedSessionId == _playbackSessionId) {
      return;
    }
    _lastCompletedSessionId = _playbackSessionId;
    playNext(fromAutoComplete: true);
  }

  // ===========================================================================
  // PLAYBACK & QUEUE CONTROLS (TRUE QUEUE-ORDER SHUFFLE)
  // ===========================================================================
  Future<void> playSong(
    LocalSong song, {
    List<LocalSong>? queueContext,
    int startPositionMs = 0,
    bool? forceShuffle,
  }) async {
    if (queueContext != null && queueContext.isNotEmpty) {
      _setQueueFromSongs(
        queueContext,
        startWithSong: song,
        forceShuffle: forceShuffle,
      );
    } else {
      final existingIdx = _queueEntries.indexWhere(
        (e) => e.song.filePath == song.filePath,
      );
      if (existingIdx != -1) {
        _currentIndex = existingIdx;
        _queueEntries[existingIdx] = _queueEntries[existingIdx].copyWith(
          song: song,
        );
        final origIdx = _originalQueueEntries.indexWhere(
          (e) => e.queueId == _queueEntries[existingIdx].queueId,
        );
        if (origIdx != -1) {
          _originalQueueEntries[origIdx] = _originalQueueEntries[origIdx]
              .copyWith(song: song);
        }
      } else {
        final entry = QueueEntry(queueId: _allocateQueueId(), song: song);
        final insertAt =
            (_currentIndex >= 0 && _currentIndex + 1 <= _queueEntries.length)
                ? _currentIndex + 1
                : _queueEntries.length;
        _queueEntries.insert(insertAt, entry);
        final activeId = currentQueueEntry?.queueId;
        final origAnchor = activeId != null
            ? _originalQueueEntries.indexWhere((e) => e.queueId == activeId)
            : -1;
        if (origAnchor != -1 &&
            origAnchor + 1 <= _originalQueueEntries.length) {
          _originalQueueEntries.insert(origAnchor + 1, entry);
        } else {
          _originalQueueEntries.add(entry);
        }
        _currentIndex = insertAt;
      }
    }

    _localLyricsCandidates = const [];
    await _startCurrentQueueTrack(startPositionMs: startPositionMs);
  }

  /// Plays [filePath] (e.g. from Download History) WITHOUT wiping out an active
  /// playback queue: if a queue already exists, jumps to or inserts right after
  /// the current track; if the queue is empty, initializes from its folder.
  Future<void> playSongByPath(String filePath) async {
    LocalSong? targetSong;
    final idx = _allSongs.indexWhere((s) => s.filePath == filePath);
    if (idx != -1) {
      targetSong = _allSongs[idx];
    } else if (Platform.isAndroid) {
      targetSong = await upsertSingleSongByPath(filePath);
    }
    if (targetSong == null) return;

    if (_queueEntries.isEmpty) {
      final sameFolder = folderSongsMap[targetSong.folderName] ?? const [];
      await playSong(
        targetSong,
        queueContext: sameFolder.isNotEmpty ? sameFolder : [targetSong],
      );
    } else {
      await playSong(targetSong);
    }
  }

  Future<void> playQueueIndex(int index) async {
    if (index < 0 || index >= _queueEntries.length) return;
    _currentIndex = index;
    _localLyricsCandidates = const [];
    await _startCurrentQueueTrack();
  }

  Future<void> playFolder(String folderName, {bool shuffle = false}) async {
    final songs = folderSongsMap[folderName] ?? const [];
    if (songs.isEmpty) return;
    _setQueueFromSongs(songs, forceShuffle: shuffle);
    _localLyricsCandidates = const [];
    await _startCurrentQueueTrack();
  }

  Future<void> playAlbum(String albumName, {bool shuffle = false}) async {
    final songs = albumSongsMap[albumName] ?? const [];
    if (songs.isEmpty) return;
    _setQueueFromSongs(songs, forceShuffle: shuffle);
    _localLyricsCandidates = const [];
    await _startCurrentQueueTrack();
  }

  Future<void> playArtist(String artistName, {bool shuffle = false}) async {
    final songs = artistSongsMap[artistName] ?? const [];
    if (songs.isEmpty) return;
    _setQueueFromSongs(songs, forceShuffle: shuffle);
    _localLyricsCandidates = const [];
    await _startCurrentQueueTrack();
  }

  Future<void> _startCurrentQueueTrack({int startPositionMs = 0}) async {
    final song = currentSong;
    if (song == null) return;

    final sessionId = ++_playbackSessionId;
    _lastCompletedSessionId = -1;
    _seekGuardUntilEpochMs = 0;
    _positionMs = startPositionMs;
    _durationMs = song.durationMs;
    _isPlaying = true;
    _hasPreparedNative = true;
    if (song.hasSyncedLyrics) {
      _lyricsDisplayMode = EmbeddedLyricsDisplayMode.synced;
    }
    _syncProgressNotifiers();
    notifyListeners();
    _savePlayerSession();

    if (!Platform.isAndroid) return;
    try {
      final ok = await _systemChannel.invokeMethod<bool>(
        'localPlayFile',
        {
          'path': song.filePath,
          'positionMs': startPositionMs,
          'sessionId': sessionId,
        },
      );
      if (ok != true && sessionId == _playbackSessionId) {
        _isPlaying = false;
        _hasPreparedNative = false;
        notifyListeners();
      }
    } catch (_) {
      if (sessionId == _playbackSessionId) {
        _isPlaying = false;
        _hasPreparedNative = false;
        notifyListeners();
      }
    }
  }

  Future<void> togglePlayPause() async {
    final song = currentSong;
    if (song == null) {
      if (_allSongs.isNotEmpty) {
        await playSong(_allSongs.first, queueContext: _allSongs);
      }
      return;
    }

    if (_isPlaying) {
      _isPlaying = false;
      notifyListeners();
      _savePlayerSession();
      if (Platform.isAndroid) {
        try {
          await _systemChannel.invokeMethod<bool>('localPause');
        } catch (_) {}
      }
    } else {
      if (!_hasPreparedNative) {
        await _startCurrentQueueTrack(startPositionMs: _positionMs);
        return;
      }
      _isPlaying = true;
      notifyListeners();
      if (Platform.isAndroid) {
        try {
          final resumed =
              await _systemChannel.invokeMethod<bool>('localResume');
          if (resumed != true) {
            await _startCurrentQueueTrack(startPositionMs: _positionMs);
          }
        } catch (_) {
          await _startCurrentQueueTrack(startPositionMs: _positionMs);
        }
      }
    }
  }

  Future<void> seekTo(int targetMs) async {
    final clamped = targetMs.clamp(0, durationMs > 0 ? durationMs : 86400000);
    _seekGuardUntilEpochMs = DateTime.now().millisecondsSinceEpoch + 350;
    _positionMs = clamped;
    _syncProgressNotifiers();
    _savePlayerSession();

    if (!Platform.isAndroid) return;
    if (!_hasPreparedNative && currentSong != null) {
      return;
    }
    try {
      await _systemChannel.invokeMethod<bool>(
        'localSeekTo',
        {'positionMs': clamped},
      );
    } catch (_) {}
  }

  Future<void> playNext({bool fromAutoComplete = false}) async {
    if (_queueEntries.isEmpty) return;

    if (fromAutoComplete) {
      if (_playMode == MusicoletPlayMode.playSingleStop) {
        // Musicolet `1→`: stop cleanly after finishing current track
        _isPlaying = false;
        _positionMs = 0;
        _hasPreparedNative = false;
        _syncProgressNotifiers();
        notifyListeners();
        _savePlayerSession();
        return;
      }
      if (_playMode == MusicoletPlayMode.repeatOne) {
        await _startCurrentQueueTrack(startPositionMs: 0);
        return;
      }
    }

    // Always advance linearly along visual `_queueEntries` (`_currentIndex + 1`)
    if (_currentIndex + 1 < _queueEntries.length) {
      _currentIndex++;
      _localLyricsCandidates = const [];
      await _startCurrentQueueTrack();
    } else {
      if (fromAutoComplete && _playMode == MusicoletPlayMode.playQueueOnce) {
        _isPlaying = false;
        _positionMs = 0;
        _hasPreparedNative = false;
        _syncProgressNotifiers();
        notifyListeners();
        _savePlayerSession();
        return;
      }
      _currentIndex = 0;
      _localLyricsCandidates = const [];
      await _startCurrentQueueTrack();
    }
  }

  Future<void> playPrevious() async {
    if (_queueEntries.isEmpty) return;
    if (_positionMs > 3500) {
      await seekTo(0);
      return;
    }
    // Always step backward linearly along visual `_queueEntries` (`_currentIndex - 1`)
    if (_currentIndex > 0) {
      _currentIndex--;
    } else {
      _currentIndex = _queueEntries.length - 1;
    }
    _localLyricsCandidates = const [];
    await _startCurrentQueueTrack();
  }

  void addToQueue(LocalSong song, {bool playNext = false}) {
    if (_queueEntries.isEmpty) {
      playSong(song, queueContext: [song]);
      return;
    }
    final entry = QueueEntry(queueId: _allocateQueueId(), song: song);
    if (playNext &&
        _currentIndex >= 0 &&
        _currentIndex + 1 <= _queueEntries.length) {
      final activeId = currentQueueEntry?.queueId;
      _queueEntries.insert(_currentIndex + 1, entry);
      final origAnchor = activeId != null
          ? _originalQueueEntries.indexWhere((e) => e.queueId == activeId)
          : -1;
      if (origAnchor != -1 &&
          origAnchor + 1 <= _originalQueueEntries.length) {
        _originalQueueEntries.insert(origAnchor + 1, entry);
      } else {
        _originalQueueEntries.add(entry);
      }
    } else {
      _queueEntries.add(entry);
      _originalQueueEntries.add(entry);
    }
    notifyListeners();
    _savePlayerSession();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queueEntries.length) return;
    final removedEntry = _queueEntries.removeAt(index);
    _originalQueueEntries.removeWhere((e) => e.queueId == removedEntry.queueId);
    final removingCurrent = index == _currentIndex;

    if (_queueEntries.isEmpty) {
      _playbackSessionId++;
      _currentIndex = -1;
      _isPlaying = false;
      _positionMs = 0;
      _durationMs = 0;
      _hasPreparedNative = false;
      if (Platform.isAndroid) {
        _systemChannel.invokeMethod<bool>('localStop');
      }
    } else if (removingCurrent) {
      if (_currentIndex >= _queueEntries.length) {
        _currentIndex = 0;
      }
      if (_isPlaying) {
        _startCurrentQueueTrack();
      } else {
        _positionMs = 0;
        _durationMs = currentSong?.durationMs ?? 0;
        _hasPreparedNative = false;
      }
    } else if (index < _currentIndex) {
      _currentIndex--;
    }
    _syncProgressNotifiers();
    notifyListeners();
    _savePlayerSession();
  }

  void reorderQueueItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queueEntries.length) return;
    if (newIndex < 0 || newIndex >= _queueEntries.length) return;

    final activeQueueId = currentQueueEntry?.queueId;
    final moved = _queueEntries.removeAt(oldIndex);
    _queueEntries.insert(newIndex, moved);
    if (!_isShuffle) {
      _originalQueueEntries = List<QueueEntry>.from(_queueEntries);
    }
    if (activeQueueId != null) {
      _currentIndex = _queueEntries.indexWhere(
        (e) => e.queueId == activeQueueId,
      );
    }
    notifyListeners();
    _savePlayerSession();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    reorderQueueItem(oldIndex, newIndex);
  }

  void clearQueue() {
    _playbackSessionId++;
    _queueEntries = [];
    _originalQueueEntries = [];
    _currentIndex = -1;
    _isPlaying = false;
    _positionMs = 0;
    _durationMs = 0;
    _hasPreparedNative = false;
    if (Platform.isAndroid) {
      _systemChannel.invokeMethod<bool>('localStop');
    }
    _syncProgressNotifiers();
    notifyListeners();
    _savePlayerSession();
  }

  // ===========================================================================
  // MUSICOLET CONTROLS: PLAY MODE, SHUFFLE, LYRICS OVERLAY, VOLUME, EQUALIZER
  // ===========================================================================
  void cyclePlayMode() {
    switch (_playMode) {
      case MusicoletPlayMode.repeatAll:
        _playMode = MusicoletPlayMode.repeatOne;
        break;
      case MusicoletPlayMode.repeatOne:
        _playMode = MusicoletPlayMode.playSingleStop;
        break;
      case MusicoletPlayMode.playSingleStop:
        _playMode = MusicoletPlayMode.playQueueOnce;
        break;
      case MusicoletPlayMode.playQueueOnce:
        _playMode = MusicoletPlayMode.repeatAll;
        break;
    }
    notifyListeners();
    _savePlayerSession();
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    if (_queueEntries.length > 1) {
      final active = currentQueueEntry;
      if (_isShuffle) {
        if (_originalQueueEntries.isEmpty) {
          _originalQueueEntries = List<QueueEntry>.from(_queueEntries);
        }
        if (active != null) {
          final rest = _queueEntries
              .where((e) => e.queueId != active.queueId)
              .toList();
          _fisherYatesShuffle(rest);
          _queueEntries = [active, ...rest];
          _currentIndex = 0;
        } else {
          final shuffled = List<QueueEntry>.from(_queueEntries);
          _fisherYatesShuffle(shuffled);
          _queueEntries = shuffled;
        }
      } else {
        final currentById = {for (final e in _queueEntries) e.queueId: e};
        final restored = <QueueEntry>[];
        for (final orig in _originalQueueEntries) {
          final match = currentById.remove(orig.queueId);
          if (match != null) {
            restored.add(match);
          }
        }
        restored.addAll(currentById.values);
        _queueEntries = restored;
        _originalQueueEntries = List<QueueEntry>.from(restored);
        if (active != null) {
          _currentIndex = _queueEntries.indexWhere(
            (e) => e.queueId == active.queueId,
          );
        }
      }
    }
    notifyListeners();
    _savePlayerSession();
  }

  void setShowLyricsOverlay(bool visible) {
    if (_showLyricsOverlay == visible) return;
    _showLyricsOverlay = visible;
    notifyListeners();
    _savePlayerSession();
  }

  void setLyricsDisplayMode(EmbeddedLyricsDisplayMode mode) {
    if (_lyricsDisplayMode == mode) return;
    _lyricsDisplayMode = mode;
    notifyListeners();
    _savePlayerSession();
  }

  void toggleAutoScrollLyrics() {
    _autoScrollLyrics = !_autoScrollLyrics;
    notifyListeners();
    _savePlayerSession();
  }

  void cycleLyricsFontSize() {
    _fontSizeIndex = (_fontSizeIndex + 1) % fontSizePresets.length;
    notifyListeners();
    _savePlayerSession();
  }

  void setLocalSearchQuery(String query) {
    _localSearchQuery = query;
    notifyListeners();
  }

  void toggleFilterFavoritesOnly() {
    _filterFavoritesOnly = !_filterFavoritesOnly;
    notifyListeners();
  }

  Future<void> toggleFavorite(String filePath) async {
    if (_favoritePaths.contains(filePath)) {
      _favoritePaths.remove(filePath);
    } else {
      _favoritePaths.add(filePath);
    }
    notifyListeners();
    await _saveFavorites();
  }

  Future<void> _syncDeviceVolume() async {
    if (!Platform.isAndroid) return;
    try {
      final v = await _systemChannel.invokeMethod<double>('getVolume');
      if (v != null) {
        _volume = v.clamp(0.0, 1.0);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setVolume(double newVolume) async {
    _volume = newVolume.clamp(0.0, 1.0);
    notifyListeners();
    if (!Platform.isAndroid) return;
    try {
      await _systemChannel.invokeMethod<bool>(
        'setVolume',
        {'volume': _volume},
      );
    } catch (_) {}
  }

  Future<bool> openSystemEqualizer() async {
    if (!Platform.isAndroid) return false;
    try {
      final opened = await _systemChannel.invokeMethod<bool>('openEqualizer');
      return opened == true;
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // LOCAL SONG TAG EDITING, AUTO-ROMAJI, LRCLIB PICKER, MOVE FOLDER & DELETE
  // ===========================================================================
  Future<void> loadLyricsCandidatesForSong(LocalSong song) async {
    if (_isLoadingLyricsCandidates) return;
    _isLoadingLyricsCandidates = true;
    notifyListeners();

    try {
      final resp = await _lyricsService.fetchLyricsWithCandidates(
        trackName: song.title,
        artistName: song.artist,
        albumName: song.album,
        durationSeconds: song.durationSeconds,
        targetFolder: song.folderName,
      );
      _localLyricsCandidates = resp.candidates;
    } catch (_) {
      _localLyricsCandidates = const [];
    } finally {
      _isLoadingLyricsCandidates = false;
      notifyListeners();
    }
  }

  Future<String> retagLocalSong({
    required LocalSong song,
    required String title,
    required String artist,
    required String album,
    required String releaseYear,
    required String lyricsText,
    required bool preferSyncedLyrics,
    String? syncedLyrics,
  }) async {
    _isProcessingLocalTag = true;
    notifyListeners();

    final isEditingCurrent = currentSong?.filePath == song.filePath;
    final wasPlaying = isEditingCurrent && _isPlaying;
    final savedPos = isEditingCurrent ? _positionMs : 0;

    try {
      if (wasPlaying && Platform.isAndroid) {
        await _systemChannel.invokeMethod<bool>('localPause');
      }

      final trimmedLyrics = lyricsText.trim();
      final hasLrcTimestamps =
          RegExp(r'\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]').hasMatch(trimmedLyrics);

      String? resolvedSyncedLyrics;
      String? resolvedPlainLyrics;
      bool shouldClearSynced = false;

      if (syncedLyrics != null && syncedLyrics.trim().isNotEmpty) {
        resolvedSyncedLyrics = syncedLyrics.trim();
        resolvedPlainLyrics =
            RomajiService.stripTimestamps(resolvedSyncedLyrics);
      } else if (hasLrcTimestamps) {
        resolvedSyncedLyrics = trimmedLyrics;
        resolvedPlainLyrics = RomajiService.stripTimestamps(trimmedLyrics);
      } else {
        resolvedSyncedLyrics = null;
        resolvedPlainLyrics = trimmedLyrics;
        shouldClearSynced = true;
      }

      final baseMeta = song.toTrackMetadata();
      final updatedMeta = baseMeta.copyWith(
        title: title.trim().isNotEmpty ? title.trim() : song.title,
        artist: artist.trim().isNotEmpty ? artist.trim() : song.artist,
        album: album.trim().isNotEmpty ? album.trim() : song.album,
        releaseYear:
            releaseYear.trim().isNotEmpty ? releaseYear.trim() : song.year,
        syncedLyrics: resolvedSyncedLyrics,
        plainLyrics: resolvedPlainLyrics,
        clearSyncedLyrics: shouldClearSynced,
      );

      final effectivePreferSynced = (hasLrcTimestamps ||
              (syncedLyrics != null && syncedLyrics.trim().isNotEmpty))
          ? true
          : preferSyncedLyrics;

      final newPath = await _taggingService.retagExistingMp3(
        filePath: song.filePath,
        updatedMetadata: updatedMeta,
        preferSyncedLyrics: effectivePreferSynced,
      );

      if (_favoritePaths.remove(song.filePath)) {
        _favoritePaths.add(newPath);
        await _saveFavorites();
      }

      await _reloadSingleSongInMemory(
        oldPath: song.filePath,
        newPath: newPath,
        wasPlaying: wasPlaying,
        resumePositionMs: savedPos,
      );

      return newPath;
    } finally {
      _isProcessingLocalTag = false;
      notifyListeners();
    }
  }

  Future<void> applyLyricsCandidateToSong(
    LocalSong song,
    LyricsCandidate candidate,
  ) async {
    final text = candidate.hasSynced
        ? (candidate.syncedLyrics ?? '')
        : (candidate.plainLyrics ?? '');
    await retagLocalSong(
      song: song,
      title: song.title,
      artist: song.artist,
      album: song.album,
      releaseYear: song.year,
      lyricsText: text,
      preferSyncedLyrics: candidate.hasSynced,
      syncedLyrics: candidate.syncedLyrics,
    );
    if (candidate.hasSynced) {
      _lyricsDisplayMode = EmbeddedLyricsDisplayMode.synced;
    } else {
      _lyricsDisplayMode = EmbeddedLyricsDisplayMode.plain;
    }
    notifyListeners();
  }

  /// Converts a local song's embedded USLT lyrics (and optionally Japanese
  /// title/artist/album) to deduplicated Romaji and writes it back into the MP3.
  Future<bool> autoRomanizeLocalSong(
    LocalSong song, {
    bool includeMetadata = false,
  }) async {
    if (_isProcessingLocalTag) return false;
    _isProcessingLocalTag = true;
    notifyListeners();

    try {
      var meta = song.toTrackMetadata();
      if (includeMetadata && RomajiService.trackHasJapanese(meta)) {
        meta = await _romajiService.romanizeTrackInfo(meta);
      }
      if (meta.hasAnyLyrics) {
        meta = await _romajiService.romanizeTrackLyrics(meta);
      }
      _isProcessingLocalTag = false;

      final lyricsToSave = meta.hasSyncedLyrics
          ? (meta.syncedLyrics ?? '')
          : (meta.plainLyrics ?? '');

      await retagLocalSong(
        song: song,
        title: meta.title,
        artist: meta.artist,
        album: meta.album,
        releaseYear: meta.releaseYear,
        lyricsText: lyricsToSave,
        preferSyncedLyrics: meta.hasSyncedLyrics,
        syncedLyrics: meta.syncedLyrics,
      );
      return true;
    } catch (e) {
      _isProcessingLocalTag = false;
      notifyListeners();
      return false;
    }
  }

  /// Registers a newly created folder without rescanning the entire audio disk.
  void registerFolder(String folderName) {
    final trimmed = folderName.trim();
    if (trimmed.isEmpty) return;
    final exists = _availableFolders.any(
      (f) => f.toLowerCase() == trimmed.toLowerCase(),
    );
    if (!exists) {
      _availableFolders = [..._availableFolders, trimmed];
      _invalidateGroupingCaches();
      notifyListeners();
      _notifyExternalSync();
      _saveLibraryCache();
    }
  }

  /// Prepares `LocalMusicProvider` before `DownloaderProvider` mutates (retags
  /// or moves) an existing local MP3 file so Android releases its file handle
  /// if [targetPath] is currently loaded in `MediaPlayer`.
  Future<Map<String, dynamic>?> prepareForExternalFileMutation(
    String targetPath,
  ) async {
    final isCurrent = currentSong?.filePath == targetPath;
    if (!isCurrent) return null;

    final snapshot = <String, dynamic>{
      'wasPlaying': _isPlaying,
      'positionMs': _positionMs,
    };
    if (Platform.isAndroid) {
      _playbackSessionId++;
      await _systemChannel.invokeMethod<bool>('localStop');
      _hasPreparedNative = false;
    }
    return snapshot;
  }

  /// Completes an external file mutation (retag/rename/move from Download History)
  /// and keeps `_allSongs`, `_queueEntries`, `_favoritePaths`, and active playback
  /// 100% synchronized.
  Future<void> completeExternalFileMutation({
    required String oldPath,
    required String newPath,
    Map<String, dynamic>? snapshot,
  }) async {
    if (_favoritePaths.remove(oldPath)) {
      _favoritePaths.add(newPath);
      await _saveFavorites();
    }
    await _reloadSingleSongInMemory(
      oldPath: oldPath,
      newPath: newPath,
      wasPlaying: snapshot?['wasPlaying'] == true,
      resumePositionMs: (snapshot?['positionMs'] as int?) ?? 0,
      notifyExternal: false,
    );
  }

  /// Reads metadata for a single newly downloaded or updated MP3 file and upserts
  /// it into memory without rescanning the entire library.
  Future<LocalSong?> upsertSingleSongByPath(String filePath) async {
    if (!Platform.isAndroid || filePath.trim().isEmpty) return null;
    try {
      final map = await _systemChannel.invokeMethod<Map<dynamic, dynamic>>(
        'readLocalTrackDetails',
        {'path': filePath},
      );
      if (map == null) return null;
      final refreshed = LocalSong.fromNativeMap(map);
      if (refreshed.filePath.isEmpty) return null;

      final existingIdx = _allSongs.indexWhere(
        (s) => s.filePath == refreshed.filePath,
      );
      if (existingIdx != -1) {
        _allSongs[existingIdx] = refreshed;
      } else {
        _allSongs = [refreshed, ..._allSongs];
      }

      if (refreshed.folderName.isNotEmpty &&
          !_availableFolders.any(
            (f) => f.toLowerCase() == refreshed.folderName.toLowerCase(),
          )) {
        _availableFolders = [..._availableFolders, refreshed.folderName];
      }

      for (int i = 0; i < _queueEntries.length; i++) {
        if (_queueEntries[i].song.filePath == refreshed.filePath) {
          _queueEntries[i] = _queueEntries[i].copyWith(song: refreshed);
        }
      }
      for (int i = 0; i < _originalQueueEntries.length; i++) {
        if (_originalQueueEntries[i].song.filePath == refreshed.filePath) {
          _originalQueueEntries[i] = _originalQueueEntries[i].copyWith(
            song: refreshed,
          );
        }
      }

      if (_queueEntries.isEmpty) {
        _setQueueFromSongs(_allSongs);
        _durationMs = _queueEntries.first.song.durationMs;
        _hasPreparedNative = false;
      }

      _invalidateGroupingCaches();
      _syncProgressNotifiers();
      notifyListeners();
      _notifyExternalSync(
        oldPath: refreshed.filePath,
        newPath: refreshed.filePath,
        updatedSong: refreshed,
      );
      await _saveLibraryCache();
      await _savePlayerSession();
      return refreshed;
    } catch (_) {
      return null;
    }
  }

  Future<String> moveLocalSongToFolder({
    required LocalSong song,
    required String targetFolderName,
  }) async {
    final isCurrent = currentSong?.filePath == song.filePath;
    final wasPlaying = isCurrent && _isPlaying;
    final savedPos = isCurrent ? _positionMs : 0;

    if (isCurrent && Platform.isAndroid) {
      _playbackSessionId++;
      await _systemChannel.invokeMethod<bool>('localStop');
      _hasPreparedNative = false;
    }

    final movedPath = await _folderService.moveDownloadedFile(
      currentFilePath: song.filePath,
      targetFolderName: targetFolderName,
    );

    if (_favoritePaths.remove(song.filePath)) {
      _favoritePaths.add(movedPath);
      await _saveFavorites();
    }

    if (!_availableFolders.contains(targetFolderName)) {
      _availableFolders = [..._availableFolders, targetFolderName];
    }

    await _reloadSingleSongInMemory(
      oldPath: song.filePath,
      newPath: movedPath,
      wasPlaying: wasPlaying,
      resumePositionMs: savedPos,
    );

    return movedPath;
  }

  Future<bool> deleteLocalSong(LocalSong song) async {
    final targetPath = song.filePath;
    final wasCurrent = currentSong?.filePath == targetPath;
    final wasPlayingCurrent = wasCurrent && _isPlaying;

    // Remove ALL occurrences of `targetPath` in `_queueEntries` & `_originalQueueEntries`
    int removedBeforeCurrent = 0;
    final filteredQueue = <QueueEntry>[];
    for (int i = 0; i < _queueEntries.length; i++) {
      if (_queueEntries[i].song.filePath == targetPath) {
        if (i < _currentIndex) {
          removedBeforeCurrent++;
        }
      } else {
        filteredQueue.add(_queueEntries[i]);
      }
    }
    _queueEntries = filteredQueue;
    _originalQueueEntries.removeWhere((e) => e.song.filePath == targetPath);

    if (_queueEntries.isEmpty) {
      _playbackSessionId++;
      _currentIndex = -1;
      _isPlaying = false;
      _positionMs = 0;
      _durationMs = 0;
      _hasPreparedNative = false;
      if (Platform.isAndroid) {
        _systemChannel.invokeMethod<bool>('localStop');
      }
    } else {
      _currentIndex = (_currentIndex - removedBeforeCurrent).clamp(
        0,
        _queueEntries.length - 1,
      );
      if (wasCurrent) {
        if (wasPlayingCurrent) {
          _startCurrentQueueTrack();
        } else {
          _playbackSessionId++;
          _positionMs = 0;
          _durationMs = currentSong?.durationMs ?? 0;
          _hasPreparedNative = false;
          if (Platform.isAndroid) {
            _systemChannel.invokeMethod<bool>('localStop');
          }
        }
      }
    }

    _allSongs.removeWhere((s) => s.filePath == targetPath);
    if (_favoritePaths.remove(targetPath)) {
      await _saveFavorites();
    }

    // Remove orphan extracted cover thumbnail if no other track shares it
    if (song.coverFilePath != null && song.coverFilePath!.isNotEmpty) {
      final sharedCover = _allSongs.any(
        (s) => s.coverFilePath == song.coverFilePath,
      );
      if (!sharedCover) {
        try {
          final coverFile = File(song.coverFilePath!);
          if (await coverFile.exists()) {
            await coverFile.delete();
          }
        } catch (_) {}
      }
    }

    _invalidateGroupingCaches();
    _syncProgressNotifiers();
    notifyListeners();
    _notifyExternalSync(oldPath: targetPath, newPath: null);
    await _saveLibraryCache();
    await _savePlayerSession();
    return _folderService.deleteMediaFile(targetPath);
  }

  Future<void> _reloadSingleSongInMemory({
    required String oldPath,
    required String newPath,
    required bool wasPlaying,
    required int resumePositionMs,
    bool notifyExternal = true,
  }) async {
    if (!Platform.isAndroid) return;
    LocalSong? refreshed;
    try {
      final map = await _systemChannel.invokeMethod<Map<dynamic, dynamic>>(
        'readLocalTrackDetails',
        {'path': newPath},
      );
      if (map != null) {
        refreshed = LocalSong.fromNativeMap(map);
        final libIdx = _allSongs.indexWhere((s) => s.filePath == oldPath);
        if (libIdx != -1) {
          _allSongs[libIdx] = refreshed;
        } else {
          final newIdx = _allSongs.indexWhere((s) => s.filePath == newPath);
          if (newIdx != -1) {
            _allSongs[newIdx] = refreshed;
          } else {
            _allSongs.insert(0, refreshed);
          }
        }

        if (refreshed.folderName.isNotEmpty &&
            !_availableFolders.any(
              (f) => f.toLowerCase() == refreshed!.folderName.toLowerCase(),
            )) {
          _availableFolders = [..._availableFolders, refreshed.folderName];
        }

        for (int i = 0; i < _queueEntries.length; i++) {
          final p = _queueEntries[i].song.filePath;
          if (p == oldPath || p == newPath) {
            _queueEntries[i] = _queueEntries[i].copyWith(song: refreshed);
          }
        }
        for (int i = 0; i < _originalQueueEntries.length; i++) {
          final p = _originalQueueEntries[i].song.filePath;
          if (p == oldPath || p == newPath) {
            _originalQueueEntries[i] = _originalQueueEntries[i].copyWith(
              song: refreshed,
            );
          }
        }

        if (currentSong?.filePath == newPath) {
          if (wasPlaying) {
            await _startCurrentQueueTrack(startPositionMs: resumePositionMs);
          } else {
            _hasPreparedNative = false;
            _positionMs = resumePositionMs;
          }
        }
      }
    } catch (_) {}
    _invalidateGroupingCaches();
    _syncProgressNotifiers();
    notifyListeners();
    await _saveLibraryCache();
    await _savePlayerSession();
    if (notifyExternal) {
      _notifyExternalSync(
        oldPath: oldPath,
        newPath: newPath,
        updatedSong: refreshed,
      );
    }
  }

  // ===========================================================================
  // INCREMENTAL LIBRARY CACHE, PLAYER SESSION & FAVORITES PERSISTENCE
  // ===========================================================================
  Future<bool> _loadLibraryAndSessionCache() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final libFile = File('${docs.path}/musicevee_library_cache_v1.json');
      if (!await libFile.exists()) return false;

      final rawLib = await libFile.readAsString();
      final decodedLib = jsonDecode(rawLib);
      if (decodedLib is! Map) return false;

      final rawFolders = decodedLib['folders'];
      if (rawFolders is List) {
        final folders = rawFolders
            .map((e) => e.toString().trim())
            .where((f) => f.isNotEmpty)
            .toList();
        if (folders.isNotEmpty) {
          _availableFolders = folders;
        }
      }

      final rawSongs = decodedLib['songs'];
      final hydratedSongs = <LocalSong>[];
      if (rawSongs is List) {
        for (final item in rawSongs) {
          if (item is Map) {
            final song = LocalSong.fromJson(Map<String, dynamic>.from(item));
            if (song.filePath.isNotEmpty) {
              hydratedSongs.add(song);
            }
          }
        }
      }
      if (hydratedSongs.isEmpty) return false;

      _allSongs = hydratedSongs;
      _invalidateGroupingCaches();
      final byPath = {for (final s in _allSongs) s.filePath: s};

      // Restore last Musicolet player session & queue order
      final sessionFile = File('${docs.path}/musicevee_player_session.json');
      bool restoredQueue = false;
      if (await sessionFile.exists()) {
        final rawSession = await sessionFile.readAsString();
        final sess = jsonDecode(rawSession);
        if (sess is Map) {
          final modeIdx = (sess['playMode'] as num?)?.toInt();
          if (modeIdx != null &&
              modeIdx >= 0 &&
              modeIdx < MusicoletPlayMode.values.length) {
            _playMode = MusicoletPlayMode.values[modeIdx];
          }
          _isShuffle = sess['isShuffle'] == true;
          if (sess['showLyricsOverlay'] is bool) {
            _showLyricsOverlay = sess['showLyricsOverlay'] as bool;
          }
          final lyrMode = (sess['lyricsDisplayMode'] as num?)?.toInt();
          if (lyrMode != null &&
              lyrMode >= 0 &&
              lyrMode < EmbeddedLyricsDisplayMode.values.length) {
            _lyricsDisplayMode = EmbeddedLyricsDisplayMode.values[lyrMode];
          }
          if (sess['autoScrollLyrics'] is bool) {
            _autoScrollLyrics = sess['autoScrollLyrics'] as bool;
          }
          final fIdx = (sess['fontSizeIndex'] as num?)?.toInt();
          if (fIdx != null && fIdx >= 0 && fIdx < fontSizePresets.length) {
            _fontSizeIndex = fIdx;
          }

          final qPaths = (sess['queuePaths'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const <String>[];
          final origPaths = (sess['originalQueuePaths'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const <String>[];

          final builtQueue = <QueueEntry>[];
          for (final p in qPaths) {
            final song = byPath[p];
            if (song != null) {
              builtQueue.add(QueueEntry(queueId: _allocateQueueId(), song: song));
            }
          }
          if (builtQueue.isNotEmpty) {
            _queueEntries = builtQueue;
            // Rebuild `_originalQueueEntries` reusing matching `queueId`s where possible
            final poolByPath = <String, List<QueueEntry>>{};
            for (final e in builtQueue) {
              poolByPath.putIfAbsent(e.song.filePath, () => []).add(e);
            }
            final builtOrig = <QueueEntry>[];
            for (final p in origPaths) {
              final pool = poolByPath[p];
              if (pool != null && pool.isNotEmpty) {
                builtOrig.add(pool.removeAt(0));
              } else {
                final song = byPath[p];
                if (song != null) {
                  builtOrig.add(
                    QueueEntry(queueId: _allocateQueueId(), song: song),
                  );
                }
              }
            }
            for (final remaining in poolByPath.values) {
              builtOrig.addAll(remaining);
            }
            _originalQueueEntries = builtOrig.isNotEmpty
                ? builtOrig
                : List<QueueEntry>.from(builtQueue);

            final savedIdx = (sess['currentIndex'] as num?)?.toInt() ?? 0;
            _currentIndex = savedIdx.clamp(0, _queueEntries.length - 1);
            final activeDur = _queueEntries[_currentIndex].song.durationMs;
            final savedPos = (sess['positionMs'] as num?)?.toInt() ?? 0;
            _positionMs = activeDur > 0
                ? savedPos.clamp(0, activeDur)
                : savedPos.clamp(0, 86400000);
            _durationMs = activeDur;
            _hasPreparedNative = false;
            _isPlaying = false;
            restoredQueue = true;
          }
        }
      }

      if (!restoredQueue) {
        _setQueueFromSongs(_allSongs);
        _durationMs = _queueEntries.first.song.durationMs;
        _positionMs = 0;
        _hasPreparedNative = false;
        _isPlaying = false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveLibraryCache() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final libFile = File('${docs.path}/musicevee_library_cache_v1.json');
      final payload = <String, dynamic>{
        'version': 1,
        'folders': _availableFolders,
        'songs': _allSongs.map((s) => s.toJson()).toList(),
      };
      await libFile.writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  Future<void> _savePlayerSession() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final sessionFile = File('${docs.path}/musicevee_player_session.json');
      final payload = <String, dynamic>{
        'playMode': _playMode.index,
        'isShuffle': _isShuffle,
        'showLyricsOverlay': _showLyricsOverlay,
        'lyricsDisplayMode': _lyricsDisplayMode.index,
        'autoScrollLyrics': _autoScrollLyrics,
        'fontSizeIndex': _fontSizeIndex,
        'currentIndex': _currentIndex,
        'positionMs': _positionMs,
        'queuePaths': _queueEntries.map((e) => e.song.filePath).toList(),
        'originalQueuePaths':
            _originalQueueEntries.map((e) => e.song.filePath).toList(),
      };
      await sessionFile.writeAsString(jsonEncode(payload));
    } catch (_) {}
  }
  Future<void> _loadFavorites() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final f = File('${docs.path}/musicevee_favorites.json');
      if (await f.exists()) {
        final raw = await f.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _favoritePaths
            ..clear()
            ..addAll(decoded.map((e) => e.toString()));
        }
      }
    } catch (_) {}
  }

  Future<void> _saveFavorites() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final f = File('${docs.path}/musicevee_favorites.json');
      await f.writeAsString(jsonEncode(_favoritePaths.toList()), flush: true);
    } catch (_) {}
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/local_playlist.dart';
import '../models/local_song.dart';
import '../models/track_metadata.dart';
import '../services/folder_service.dart';
import '../services/lyrics_service.dart';
import '../services/romaji_service.dart';
import '../services/tagging_service.dart';
import '../utils/app_strings.dart';

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

/// Metadata for a physical audio folder detected on device storage (used by
/// the "Kelola / Sembunyikan Folder" sheet in `LocalFoldersView`).
class DetectedFolderInfo {
  final String folderName;
  final String folderPath;
  final int songCount;
  final bool isHidden;

  const DetectedFolderInfo({
    required this.folderName,
    required this.folderPath,
    required this.songCount,
    required this.isHidden,
  });
}

/// Built-in Musicolet Smart Playlist IDs displayed in the top section of
/// `LocalPlaylistsView`.
class SmartPlaylistId {
  static const String allSongs = 'smart_all_songs';
  static const String favorites = 'smart_favorites';
  static const String recentlyAdded = 'smart_recently_added';
  static const String recentlyPlayed = 'smart_recently_played';
  static const String mostPlayed = 'smart_most_played';
  static const String notPlayed = 'smart_not_played';

  static const List<String> allIds = <String>[
    allSongs,
    favorites,
    recentlyAdded,
    recentlyPlayed,
    mostPlayed,
    notPlayed,
  ];

  static bool isSmartId(String id) => allIds.contains(id);

  static String titleFor(String id) => AppStrings.smartPlaylistTitle(id);
}

/// Persistent play count & last-played timestamp for a local audio track
/// (`musevee_play_stats_v1.json`).
class TrackPlayStat {
  final int playCount;
  final int lastPlayedMs;

  const TrackPlayStat({
    required this.playCount,
    required this.lastPlayedMs,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'playCount': playCount,
        'lastPlayedMs': lastPlayedMs,
      };

  factory TrackPlayStat.fromJson(Map<String, dynamic> json) => TrackPlayStat(
        playCount: (json['playCount'] as num?)?.toInt() ?? 0,
        lastPlayedMs: (json['lastPlayedMs'] as num?)?.toInt() ?? 0,
      );
}

class LocalMusicProvider extends ChangeNotifier {
  static const MethodChannel _systemChannel = MethodChannel(
    'com.spotmeta.downloader/system',
  );

  static const List<double> fontSizePresets = [13.5, 15.5, 18.0, 20.5];
  static const String hiddenFoldersFileName = 'musevee_hidden_folders_v1.json';
  static const String playStatsFileName = 'musevee_play_stats_v1.json';

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

  /// All songs discovered on storage (before applying `_hiddenFolderPaths` filter).
  List<LocalSong> _discoveredSongs = [];

  /// Active visible songs in the library (excludes hidden folders).
  List<LocalSong> _allSongs = [];

  List<String> _availableFolders = <String>[
    FolderService.defaultNeutralFolder,
  ];
  final List<LocalPlaylist> _playlists = [];
  final Set<String> _favoritePaths = {};
  final Set<String> _hiddenFolderPaths = {};
  final Map<String, TrackPlayStat> _playStatsByPath = {};
  bool _onlyMusicFolders = false;
  bool _isLoadingLibrary = false;
  bool _isSyncingLibrary = false;
  bool _requestedNotificationPermission = false;

  @visibleForTesting
  bool debugEnableNativeChannelInTests = false;

  bool get _shouldInvokeNativeChannel =>
      Platform.isAndroid || debugEnableNativeChannelInTests;

  // First-Run Permission Onboarding & Live Island Status
  bool _hasAllFilesAccess = true;
  bool _hasNotificationPermission = true;
  bool _permissionBannerDismissed = false;

  // Memoized O(N log N) library groupings (invalidated ONLY when `_allSongs` or `_availableFolders` mutates)
  Map<String, List<LocalSong>>? _cachedFolderSongsMap;
  Map<String, List<LocalSong>>? _cachedAlbumSongsMap;
  Map<String, List<LocalSong>>? _cachedArtistSongsMap;
  Map<String, LocalSong>? _cachedSongsByPath;

  void _invalidateGroupingCaches() {
    _cachedFolderSongsMap = null;
    _cachedAlbumSongsMap = null;
    _cachedArtistSongsMap = null;
    _cachedSongsByPath = null;
  }

  Map<String, LocalSong> get _songsByPath {
    final cached = _cachedSongsByPath;
    if (cached != null) return cached;
    final built = <String, LocalSong>{for (final s in _allSongs) s.filePath: s};
    _cachedSongsByPath = built;
    return built;
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
  double _volume = 1.0;
  double _preAmpGainDb = 0.0;
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
  Uint8List? _currentFullCoverBytes;
  String? _currentFullCoverSongPath;

  // Local Search Query
  String _localSearchQuery = '';
  bool _filterFavoritesOnly = false;

  // Getters
  List<LocalSong> get allSongs => List.unmodifiable(_allSongs);
  List<LocalSong> get discoveredSongs => List.unmodifiable(_discoveredSongs);
  List<String> get availableFolders => List.unmodifiable(_availableFolders);
  List<LocalPlaylist> get playlists => List.unmodifiable(_playlists);
  Set<String> get hiddenFolderPaths => Set.unmodifiable(_hiddenFolderPaths);
  bool get onlyMusicFolders => _onlyMusicFolders;
  bool get isLoadingLibrary => _isLoadingLibrary;

  bool get hasAllFilesAccess => _hasAllFilesAccess;
  bool get hasNotificationPermission => _hasNotificationPermission;
  bool get permissionBannerDismissed => _permissionBannerDismissed;
  bool get shouldShowPermissionOnboarding =>
      Platform.isAndroid &&
      !_permissionBannerDismissed &&
      (!_hasAllFilesAccess || !_hasNotificationPermission);

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
  double get preAmpGainDb => _preAmpGainDb;
  String get audioContentType => 'music';
  String get audioUsage => 'media';
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
  Uint8List? get currentFullCoverBytes =>
      (_currentFullCoverSongPath != null &&
              _currentFullCoverSongPath == currentSong?.filePath)
          ? _currentFullCoverBytes
          : null;

  String get localSearchQuery => _localSearchQuery;
  bool get filterFavoritesOnly => _filterFavoritesOnly;

  bool isFavorite(String filePath) => _favoritePaths.contains(filePath);

  static String _normalizeFolderKey(String raw) {
    var trimmed = raw.trim().replaceAll('\\', '/');
    while (trimmed.length > 1 && trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.toLowerCase();
  }

  bool isFolderHidden(String folderPath, {String? folderName}) {
    final normPath = _normalizeFolderKey(folderPath);
    if (normPath.isNotEmpty && _hiddenFolderPaths.contains(normPath)) {
      return true;
    }
    if (folderName != null && folderName.trim().isNotEmpty) {
      final normName = _normalizeFolderKey(folderName);
      if (normName.isNotEmpty && _hiddenFolderPaths.contains(normName)) {
        return true;
      }
    }
    return false;
  }

  bool isSongInHiddenFolder(LocalSong song) =>
      isFolderHidden(song.folderPath, folderName: song.folderName);

  void _rebuildVisibleSongs() {
    _allSongs = _discoveredSongs
        .where((s) => !isSongInHiddenFolder(s))
        .toList();
    _invalidateGroupingCaches();
  }

  /// Returns all detected folders across storage (both visible and hidden)
  /// with their song counts and paths for the "Kelola Folder" bottom sheet.
  List<DetectedFolderInfo> get detectedFoldersInfo {
    final groupedByPath = <String, List<LocalSong>>{};
    final displayPathByKey = <String, String>{};
    final displayNameByKey = <String, String>{};

    for (final song in _discoveredSongs) {
      final path = song.folderPath;
      final name = song.folderName.trim().isNotEmpty
          ? song.folderName.trim()
          : 'Music';
      final key = _normalizeFolderKey(path.isNotEmpty ? path : name);
      if (key.isEmpty) continue;
      displayPathByKey.putIfAbsent(key, () => path);
      displayNameByKey.putIfAbsent(key, () => name);
      groupedByPath.putIfAbsent(key, () => []).add(song);
    }

    final items = <DetectedFolderInfo>[];
    for (final entry in groupedByPath.entries) {
      final key = entry.key;
      final songs = entry.value;
      if (songs.isEmpty) continue;
      final folderPath = displayPathByKey[key] ?? songs.first.folderPath;
      final folderName = displayNameByKey[key] ?? songs.first.folderName;
      items.add(
        DetectedFolderInfo(
          folderName: folderName,
          folderPath: folderPath,
          songCount: songs.length,
          isHidden: isFolderHidden(folderPath, folderName: folderName),
        ),
      );
    }

    final priorityLower =
        FolderService.defaultFolders.map((f) => f.toLowerCase()).toList();
    items.sort((a, b) {
      final aIdx = priorityLower.indexOf(a.folderName.toLowerCase());
      final bIdx = priorityLower.indexOf(b.folderName.toLowerCase());
      if (aIdx != -1 && bIdx != -1) return aIdx.compareTo(bIdx);
      if (aIdx != -1) return -1;
      if (bIdx != -1) return 1;
      return a.folderName.toLowerCase().compareTo(b.folderName.toLowerCase());
    });
    return items;
  }

  int get hiddenFoldersCount =>
      detectedFoldersInfo.where((f) => f.isHidden).length;

  /// Applies a batch of folder visibility updates (from the "Kelola Folder" modal's
  /// **Terapkan** button or programmatic calls) and synchronizes the active
  /// playback queue and native audio engine (`localPlayFile` / `localStop`).
  Future<void> applyFolderVisibilityChanges({
    Iterable<String>? hiddenFolderPaths,
    Map<String, bool>? folderVisibilityByPath,
    bool? onlyMusicFolders,
  }) async {
    final previousCurrentSong = currentSong;
    final previousQueueId = currentQueueEntry?.queueId;
    final previousIndex = _currentIndex;
    final wasPlaying = _isPlaying;

    final allDetected = detectedFoldersInfo;

    if (onlyMusicFolders != null) {
      final prevOnlyMusic = _onlyMusicFolders;
      _onlyMusicFolders = onlyMusicFolders;
      if (hiddenFolderPaths == null && folderVisibilityByPath == null) {
        if (onlyMusicFolders) {
          for (final info in allDetected) {
            if (!info.folderName.toLowerCase().contains('music')) {
              final np = _normalizeFolderKey(info.folderPath);
              final nn = _normalizeFolderKey(info.folderName);
              if (np.isNotEmpty) _hiddenFolderPaths.add(np);
              if (nn.isNotEmpty) _hiddenFolderPaths.add(nn);
            }
          }
        } else if (prevOnlyMusic) {
          for (final info in allDetected) {
            if (!info.folderName.toLowerCase().contains('music')) {
              _hiddenFolderPaths.remove(_normalizeFolderKey(info.folderPath));
              _hiddenFolderPaths.remove(_normalizeFolderKey(info.folderName));
            }
          }
        }
      }
    }

    if (hiddenFolderPaths != null) {
      _hiddenFolderPaths.clear();
      for (final raw in hiddenFolderPaths) {
        final normKey = _normalizeFolderKey(raw);
        if (normKey.isEmpty) continue;
        _hiddenFolderPaths.add(normKey);
        for (final info in allDetected) {
          final np = _normalizeFolderKey(info.folderPath);
          final nn = _normalizeFolderKey(info.folderName);
          if (np == normKey || nn == normKey) {
            if (np.isNotEmpty) _hiddenFolderPaths.add(np);
            if (nn.isNotEmpty) _hiddenFolderPaths.add(nn);
          }
        }
      }
    }

    if (folderVisibilityByPath != null) {
      for (final entry in folderVisibilityByPath.entries) {
        final normKey = _normalizeFolderKey(entry.key);
        if (normKey.isEmpty) continue;
        final isVisible = entry.value;
        final matched = allDetected.where(
          (info) =>
              _normalizeFolderKey(info.folderPath) == normKey ||
              _normalizeFolderKey(info.folderName) == normKey,
        );
        if (!isVisible) {
          _hiddenFolderPaths.add(normKey);
          for (final info in matched) {
            final np = _normalizeFolderKey(info.folderPath);
            final nn = _normalizeFolderKey(info.folderName);
            if (np.isNotEmpty) _hiddenFolderPaths.add(np);
            if (nn.isNotEmpty) _hiddenFolderPaths.add(nn);
          }
        } else {
          _hiddenFolderPaths.remove(normKey);
          for (final info in matched) {
            _hiddenFolderPaths.remove(_normalizeFolderKey(info.folderPath));
            _hiddenFolderPaths.remove(_normalizeFolderKey(info.folderName));
          }
        }
      }
    }

    _rebuildVisibleSongs();
    await _syncQueueAndAudioAfterVisibilityChange(
      previousCurrentSong: previousCurrentSong,
      previousQueueId: previousQueueId,
      previousIndex: previousIndex,
      wasPlaying: wasPlaying,
    );
    _syncProgressNotifiers();
    notifyListeners();
    _notifyExternalSync();
    await _saveHiddenFolders();
    await _savePlayerSession();
  }

  Future<void> setFolderHidden(
    String folderPath, {
    String? folderName,
    required bool hidden,
  }) async {
    final key = folderPath.trim().isNotEmpty
        ? folderPath.trim()
        : (folderName?.trim() ?? '');
    if (key.isEmpty) return;
    await applyFolderVisibilityChanges(
      folderVisibilityByPath: <String, bool>{key: !hidden},
    );
  }

  Future<void> showAllHiddenFolders() async {
    if (_hiddenFolderPaths.isEmpty && !_onlyMusicFolders) return;
    await applyFolderVisibilityChanges(
      hiddenFolderPaths: const <String>[],
      onlyMusicFolders: false,
    );
  }

  Future<void> _syncQueueAndAudioAfterVisibilityChange({
    required LocalSong? previousCurrentSong,
    required String? previousQueueId,
    required int previousIndex,
    required bool wasPlaying,
  }) async {
    final visibleByPath = {for (final s in _allSongs) s.filePath: s};
    final previousSongWasHidden = previousCurrentSong != null &&
        !visibleByPath.containsKey(previousCurrentSong.filePath);

    int removedBeforeCurrent = 0;
    if (_queueEntries.isNotEmpty) {
      final filteredQueue = <QueueEntry>[];
      for (int i = 0; i < _queueEntries.length; i++) {
        final entry = _queueEntries[i];
        final updatedSong = visibleByPath[entry.song.filePath];
        if (updatedSong != null) {
          filteredQueue.add(entry.copyWith(song: updatedSong));
        } else if (i < previousIndex) {
          removedBeforeCurrent++;
        }
      }
      _queueEntries = filteredQueue;
      _originalQueueEntries = _originalQueueEntries
          .where((e) => visibleByPath.containsKey(e.song.filePath))
          .map((e) => e.copyWith(song: visibleByPath[e.song.filePath]!))
          .toList();
    }

    if (_queueEntries.isEmpty) {
      // Queue became empty: stop native AudioPlayer, clear queue, reset
      // currentIndex = -1 / currentSong = null, set isPlaying = false,
      // and clear notification / Live Island.
      _playbackSessionId++;
      _queueEntries = [];
      _originalQueueEntries = [];
      _currentIndex = -1;
      _isPlaying = false;
      _positionMs = 0;
      _durationMs = 0;
      _hasPreparedNative = false;
      _localLyricsCandidates = const [];
      if (_shouldInvokeNativeChannel) {
        try {
          await _systemChannel.invokeMethod<bool>('localStop');
        } catch (_) {}
      }
      return;
    }

    if (previousSongWasHidden) {
      // Currently playing/active song belonged to a newly hidden folder, and
      // queue still has remaining songs from other visible folders.
      _currentIndex = (previousIndex - removedBeforeCurrent)
          .clamp(0, _queueEntries.length - 1);
      _localLyricsCandidates = const [];
      if (_shouldInvokeNativeChannel) {
        try {
          await _systemChannel.invokeMethod<bool>('localStop');
        } catch (_) {}
      }

      if (wasPlaying) {
        // Reload and play the new song at currentIndex so audio output is 100%
        // synchronized with the song title displayed on screen!
        await _startCurrentQueueTrack(startPositionMs: 0);
      } else {
        final nextSong = currentSong;
        _positionMs = 0;
        _durationMs = nextSong?.durationMs ?? 0;
        _hasPreparedNative = false;
        if (nextSong != null && _shouldInvokeNativeChannel) {
          try {
            await _systemChannel.invokeMethod<bool>(
              'updateMediaNotification',
              {
                'title': nextSong.title,
                'artist': nextSong.artist,
                'album': nextSong.album,
                'coverPath': nextSong.coverFilePath,
                'durationMs': nextSong.durationMs,
              },
            );
          } catch (_) {}
        }
      }
    } else {
      if (previousQueueId != null) {
        final restoredIdx = _queueEntries.indexWhere(
          (e) => e.queueId == previousQueueId,
        );
        _currentIndex = restoredIdx != -1
            ? restoredIdx
            : _currentIndex.clamp(0, _queueEntries.length - 1);
      } else {
        _currentIndex = _currentIndex.clamp(0, _queueEntries.length - 1);
      }
    }
  }

  /// Grouped songs per folder (only includes folders that contain >= 1 visible song).
  Map<String, List<LocalSong>> get folderSongsMap {
    final cached = _cachedFolderSongsMap;
    if (cached != null) return cached;

    final grouped = <String, List<LocalSong>>{};
    for (final song in _allSongs) {
      final name = song.folderName.trim();
      if (name.isEmpty) continue;
      grouped.putIfAbsent(name, () => []).add(song);
    }

    final ordered = <String, List<LocalSong>>{};
    final seenLower = <String>{};
    // Keep priority folders (`Music Barat`, `Music Japan`, `Music Random`, etc.) first when non-empty
    final priorityOrder = <String>[
      ...FolderService.defaultFolders,
      ..._availableFolders,
    ];
    for (final f in priorityOrder) {
      final matchKey = grouped.keys.firstWhere(
        (k) => k.toLowerCase() == f.toLowerCase(),
        orElse: () => '',
      );
      if (matchKey.isNotEmpty &&
          !seenLower.contains(matchKey.toLowerCase()) &&
          grouped[matchKey]!.isNotEmpty) {
        ordered[matchKey] = grouped[matchKey]!;
        seenLower.add(matchKey.toLowerCase());
      }
    }

    final remainingKeys = grouped.keys
        .where(
          (k) =>
              !seenLower.contains(k.toLowerCase()) && grouped[k]!.isNotEmpty,
        )
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final k in remainingKeys) {
      ordered[k] = grouped[k]!;
    }

    _cachedFolderSongsMap = ordered;
    return ordered;
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
    await _loadHiddenFolders();
    await _loadFavorites();
    await _loadPlayStats();
    await _loadPlaylists();
    await checkPermissionsStatus();
    final hydrated = await _loadLibraryAndSessionCache();
    if (hydrated) {
      _syncProgressNotifiers();
      notifyListeners();
      _notifyExternalSync();
    } else {
      notifyListeners();
    }
    await setVolume(1.0);
    await refreshLibrary(
      requestPermission: true,
      silentBackground: hydrated,
    );
    await checkPermissionsStatus();
  }

  // ===========================================================================
  // FIRST-RUN PERMISSION ONBOARDING & LIVE ISLAND STATUS
  // ===========================================================================
  Future<void> checkPermissionsStatus({
    bool refreshIfNewlyGranted = false,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      final prevAllFiles = _hasAllFilesAccess;
      final prevNotif = _hasNotificationPermission;
      final status = await _folderService.getPermissionsStatus();
      _hasAllFilesAccess = status['hasAllFilesAccess'] == true;
      _hasNotificationPermission = status['hasNotificationPermission'] == true;

      if (_hasAllFilesAccess && _hasNotificationPermission) {
        _permissionBannerDismissed = false;
      }

      if (prevAllFiles != _hasAllFilesAccess ||
          prevNotif != _hasNotificationPermission) {
        notifyListeners();
      }

      if (refreshIfNewlyGranted && !prevAllFiles && _hasAllFilesAccess) {
        await refreshLibrary(silentBackground: _allSongs.isNotEmpty);
      }
    } catch (_) {}
  }

  void dismissPermissionBanner() {
    if (_permissionBannerDismissed) return;
    _permissionBannerDismissed = true;
    notifyListeners();
  }

  Future<void> requestAllFilesAccessPermission() async {
    if (!Platform.isAndroid) return;
    await _folderService.requestAllFilesAccess();
    await checkPermissionsStatus(refreshIfNewlyGranted: true);
  }

  Future<bool> requestNotificationAndLiveIslandPermission() async {
    if (!Platform.isAndroid) return true;
    bool granted = await _folderService.requestNotificationPermission();
    if (!granted) {
      try {
        final status = await Permission.notification.request();
        granted = status.isGranted;
      } catch (_) {}
    }
    await checkPermissionsStatus();
    if (!_hasNotificationPermission) {
      await _folderService.openNotificationSettings();
      await checkPermissionsStatus();
    }
    return _hasNotificationPermission;
  }

  Future<void> openNotificationSettings() async {
    if (!Platform.isAndroid) return;
    await _folderService.openNotificationSettings();
    await checkPermissionsStatus();
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
    if (!_requestedNotificationPermission) {
      _requestedNotificationPermission = true;
      try {
        final notifStatus = await Permission.notification.status;
        if (notifStatus.isDenied) {
          await Permission.notification.request();
        }
      } catch (_) {}
    }
  }

  /// Incrementally delta-syncs device storage and MediaStore via
  /// `MainActivity.kt` (`scanLocalMusicLibraryDelta`), inspecting only new or
  /// modified audio files (`lastModifiedMs` + `sizeBytes` + persistent cover file)
  /// and persisting `musevee_library_cache_v1.json`.
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
        for (final s in _discoveredSongs)
          s.filePath: {
            'lastModifiedMs': s.lastModifiedMs,
            'sizeBytes': s.sizeBytes,
            'coverFilePath': s.coverFilePath,
            'hasLyrics': s.hasLyrics,
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

      List<LocalSong> nextDiscovered;
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

        final existingByPath = {
          for (final s in _discoveredSongs) s.filePath: s,
        };
        final removedSongs = _discoveredSongs
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
          nextDiscovered = merged;

          // Clean up orphan covers for files removed externally outside MusEvee
          if (removedSongs.isNotEmpty) {
            final activeCovers = nextDiscovered
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
          nextDiscovered = _discoveredSongs;
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
        nextDiscovered = parsed;
        libraryMutated = true;
      }

      _discoveredSongs = nextDiscovered;
      _rebuildVisibleSongs();

      // Ensure any extra `/storage/emulated/0/Music/<subfolder>` names discovered are in `_availableFolders`
      final seenLower = _availableFolders.map((f) => f.toLowerCase()).toSet();
      for (final s in _allSongs) {
        final isUnderBaseMusic = s.folderPath
            .toLowerCase()
            .startsWith('${FolderService.baseMusicRoot.toLowerCase()}/');
        if (isUnderBaseMusic &&
            s.folderName.isNotEmpty &&
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
      debugPrint('[MusEvee] refreshLibrary gagal: $e');
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
      } else if (chosenIdx > 0) {
        // Rotate the queue so the selected song is placed at index 0 (#1 in Queue),
        // followed by songs after it (chosenIdx + 1 .. end), and then the songs
        // that originally preceded it (0 .. chosenIdx - 1) appended at the bottom.
        final tail = baseEntries.sublist(chosenIdx);
        final head = baseEntries.sublist(0, chosenIdx);
        baseEntries
          ..clear()
          ..addAll(tail)
          ..addAll(head);
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

  /// Handles transport actions originating from the native Android `MediaSession`
  /// & `Notification.MediaStyle` notification shade / lockscreen / headset buttons.
  void handleMediaNotificationAction({
    required String action,
    int positionMs = 0,
  }) {
    switch (action) {
      case 'play':
        if (!_isPlaying) {
          togglePlayPause();
        }
        break;
      case 'pause':
        if (_isPlaying) {
          togglePlayPause();
        }
        break;
      case 'next':
        playNext();
        break;
      case 'previous':
        playPrevious();
        break;
      case 'seek':
        seekTo(positionMs);
        break;
      case 'stop':
        _isPlaying = false;
        _hasPreparedNative = false;
        _syncProgressNotifiers();
        notifyListeners();
        _savePlayerSession();
        break;
    }
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

  /// Plays every resolvable song of playlist [playlistId] (either a Smart Playlist
  /// or a User Playlist) as the active Queue, optionally starting from [startSong].
  Future<void> playPlaylist(
    String playlistId, {
    bool shuffle = false,
    LocalSong? startSong,
  }) async {
    final songs = songsForPlaylistId(playlistId);
    if (songs.isEmpty) return;
    _setQueueFromSongs(
      songs,
      startWithSong: startSong,
      forceShuffle: shuffle,
    );
    _localLyricsCandidates = const [];
    await _startCurrentQueueTrack();
  }

  /// Merges songs across multiple folders ([folderPaths] may contain folder names
  /// like `'Music Barat'` or full folder paths like `'/storage/emulated/0/Music/Music Barat'`),
  /// deduplicates by `filePath`, and either replaces the active Queue (with optional
  /// Fisher-Yates True Shuffle Mix across all combined tracks) or appends to the end
  /// of the current Queue without interrupting playback.
  /// Returns the number of unique songs loaded/appended.
  Future<int> playCombinedFolders(
    List<String> folderPaths, {
    bool shuffle = false,
    bool appendToCurrentQueue = false,
  }) async {
    if (folderPaths.isEmpty) return 0;

    final grouped = folderSongsMap;
    final seenPaths = <String>{};
    final combined = <LocalSong>[];

    for (final rawTarget in folderPaths) {
      final trimmed = rawTarget.trim();
      if (trimmed.isEmpty) continue;
      final normTarget = _normalizeFolderKey(trimmed);

      // 1. Direct match by folderName key in folderSongsMap
      final directKey = grouped.keys.firstWhere(
        (k) => _normalizeFolderKey(k) == normTarget,
        orElse: () => '',
      );
      if (directKey.isNotEmpty) {
        for (final song in grouped[directKey]!) {
          if (seenPaths.add(song.filePath)) {
            combined.add(song);
          }
        }
        continue;
      }

      // 2. Match by full folderPath or folderName across visible songs
      for (final song in _allSongs) {
        if (_normalizeFolderKey(song.folderPath) == normTarget ||
            _normalizeFolderKey(song.folderName) == normTarget) {
          if (seenPaths.add(song.filePath)) {
            combined.add(song);
          }
        }
      }
    }

    return _mergeAndPlayOrAppendSongs(
      combined,
      shuffle: shuffle,
      appendToCurrentQueue: appendToCurrentQueue,
    );
  }

  /// Merges songs across multiple user playlists ([playlistIds], restricted to
  /// `Your playlists` when combining multiple playlists), deduplicates by `filePath`,
  /// and either replaces the active Queue (with optional Fisher-Yates True Shuffle Mix
  /// across all combined tracks) or appends to the end of the current Queue.
  /// Returns the number of unique songs loaded/appended.
  Future<int> playCombinedPlaylists(
    List<String> playlistIds, {
    bool shuffle = false,
    bool appendToCurrentQueue = false,
  }) async {
    if (playlistIds.isEmpty) return 0;

    final allowSingleSmartAppend =
        playlistIds.length == 1 && appendToCurrentQueue;
    final seenPaths = <String>{};
    final combined = <LocalSong>[];

    for (final rawId in playlistIds) {
      final id = rawId.trim();
      if (id.isEmpty) continue;
      if (SmartPlaylistId.isSmartId(id) && !allowSingleSmartAppend) {
        continue;
      }
      final songs = songsForPlaylistId(id);
      for (final song in songs) {
        if (seenPaths.add(song.filePath)) {
          combined.add(song);
        }
      }
    }

    return _mergeAndPlayOrAppendSongs(
      combined,
      shuffle: shuffle,
      appendToCurrentQueue: appendToCurrentQueue,
    );
  }

  Future<int> _mergeAndPlayOrAppendSongs(
    List<LocalSong> uniqueSongs, {
    required bool shuffle,
    required bool appendToCurrentQueue,
  }) async {
    if (uniqueSongs.isEmpty) return 0;

    if (appendToCurrentQueue && _queueEntries.isNotEmpty) {
      final existingPaths = _queueEntries.map((e) => e.song.filePath).toSet();
      final toAppend = uniqueSongs
          .where((s) => existingPaths.add(s.filePath))
          .toList();
      if (toAppend.isEmpty) return 0;

      final newEntries = toAppend
          .map((s) => QueueEntry(queueId: _allocateQueueId(), song: s))
          .toList();
      _originalQueueEntries.addAll(newEntries);

      if (shuffle || _isShuffle) {
        final shuffledAppend = List<QueueEntry>.from(newEntries);
        _fisherYatesShuffle(shuffledAppend);
        _queueEntries.addAll(shuffledAppend);
      } else {
        _queueEntries.addAll(newEntries);
      }

      notifyListeners();
      _savePlayerSession();
      return toAppend.length;
    }

    _setQueueFromSongs(uniqueSongs, forceShuffle: shuffle);
    _localLyricsCandidates = const [];
    await _startCurrentQueueTrack();
    return uniqueSongs.length;
  }

  @visibleForTesting
  void seedSongsForTesting(List<LocalSong> songs) {
    _discoveredSongs = List<LocalSong>.from(songs);
    _rebuildVisibleSongs();
    notifyListeners();
  }

  /// Loads embedded `USLT` lyrics on-demand from the physical MP3 file if
  /// `musevee_library_cache_v1.json` omitted the full text string (`hasLyrics == true`
  /// while `usltLyrics` is empty).
  Future<LocalSong> ensureSongLyricsLoaded(LocalSong song) async {
    if ((song.usltLyrics != null && song.usltLyrics!.trim().isNotEmpty) ||
        !_shouldInvokeNativeChannel) {
      return song;
    }
    try {
      final map = await _systemChannel.invokeMethod<Map<dynamic, dynamic>>(
        'readLocalTrackDetails',
        {'path': song.filePath},
      );
      if (map != null) {
        final refreshed = LocalSong.fromNativeMap(map);
        if (refreshed.filePath.isNotEmpty) {
          _replaceSongInMemoryCaches(refreshed);
          return refreshed;
        }
      }
    } catch (_) {}
    return song;
  }

  void _replaceSongInMemoryCaches(LocalSong refreshed) {
    final discIdx = _discoveredSongs.indexWhere(
      (s) => s.filePath == refreshed.filePath,
    );
    if (discIdx != -1) {
      _discoveredSongs[discIdx] = refreshed;
    }
    final allIdx = _allSongs.indexWhere(
      (s) => s.filePath == refreshed.filePath,
    );
    if (allIdx != -1) {
      _allSongs[allIdx] = refreshed;
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
    _invalidateGroupingCaches();
  }

  Future<void> _loadCurrentSongDetailsAndCoverOnDemand(
    LocalSong song,
    int sessionId,
  ) async {
    if (!_shouldInvokeNativeChannel) return;
    try {
      if (song.hasLyrics &&
          (song.usltLyrics == null || song.usltLyrics!.trim().isEmpty)) {
        final refreshed = await ensureSongLyricsLoaded(song);
        if (sessionId == _playbackSessionId &&
            currentSong?.filePath == refreshed.filePath) {
          if (refreshed.hasSyncedLyrics) {
            _lyricsDisplayMode = EmbeddedLyricsDisplayMode.synced;
          }
          _syncProgressNotifiers();
          notifyListeners();
        }
      }
      final rawBytes = await _systemChannel.invokeMethod<Uint8List>(
        'readEmbeddedCoverBytes',
        {'path': song.filePath},
      );
      if (sessionId == _playbackSessionId &&
          currentSong?.filePath == song.filePath) {
        _currentFullCoverBytes =
            (rawBytes != null && rawBytes.isNotEmpty) ? rawBytes : null;
        _currentFullCoverSongPath = song.filePath;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _startCurrentQueueTrack({int startPositionMs = 0}) async {
    final song = currentSong;
    if (song == null) return;

    if (startPositionMs == 0) {
      _recordTrackPlayed(song.filePath);
    }

    if (_currentFullCoverSongPath != song.filePath) {
      _currentFullCoverBytes = null;
      _currentFullCoverSongPath = null;
    }

    final sessionId = ++_playbackSessionId;
    _lastCompletedSessionId = -1;
    _seekGuardUntilEpochMs = 0;
    _positionMs = startPositionMs;
    _durationMs = song.durationMs;
    _volume = 1.0;
    _isPlaying = true;
    _hasPreparedNative = true;
    if (song.hasSyncedLyrics) {
      _lyricsDisplayMode = EmbeddedLyricsDisplayMode.synced;
    }
    _syncProgressNotifiers();
    notifyListeners();
    _savePlayerSession();

    if (!_shouldInvokeNativeChannel) return;
    _loadCurrentSongDetailsAndCoverOnDemand(song, sessionId);
    try {
      await _systemChannel.invokeMethod<bool>(
        'setVolume',
        {'volume': 1.0},
      );
      final ok = await _systemChannel.invokeMethod<bool>(
        'localPlayFile',
        {
          'path': song.filePath,
          'positionMs': startPositionMs,
          'sessionId': sessionId,
          'title': song.title,
          'artist': song.artist,
          'album': song.album,
          'coverPath': song.coverFilePath,
          'durationMs': song.durationMs,
          'volume': 1.0,
          'preAmpDb': _preAmpGainDb,
          'contentType': audioContentType,
          'usage': audioUsage,
        },
      );
      if (ok == false && sessionId == _playbackSessionId) {
        _isPlaying = false;
        _hasPreparedNative = false;
        notifyListeners();
      }
    } catch (_) {
      if (Platform.isAndroid && sessionId == _playbackSessionId) {
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
      if (_shouldInvokeNativeChannel) {
        try {
          _systemChannel.invokeMethod<bool>('localStop');
        } catch (_) {}
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
    if (_shouldInvokeNativeChannel) {
      try {
        _systemChannel.invokeMethod<bool>('localStop');
      } catch (_) {}
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

  Future<void> setVolume(double newVolume) async {
    _volume = newVolume.clamp(0.0, 1.0);
    notifyListeners();
    if (!_shouldInvokeNativeChannel) return;
    try {
      await _systemChannel.invokeMethod<bool>(
        'setVolume',
        {'volume': _volume},
      );
    } catch (_) {}
  }

  Future<void> setPreAmpGainDb(double gainDb) async {
    _preAmpGainDb = gainDb.clamp(0.0, 6.0);
    notifyListeners();
    if (!_shouldInvokeNativeChannel) return;
    try {
      await _systemChannel.invokeMethod<bool>(
        'setPreAmpGainDb',
        {'gainDb': _preAmpGainDb},
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
      // Release MediaPlayer file lock completely (even if paused) before rewriting MP3
      if (isEditingCurrent && Platform.isAndroid) {
        _playbackSessionId++;
        _isPlaying = false;
        _hasPreparedNative = false;
        await _systemChannel.invokeMethod<bool>('localStop');
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

      final hydratedSong = await ensureSongLyricsLoaded(song);
      final baseMeta = hydratedSong.toTrackMetadata();
      final updatedMeta = baseMeta.copyWith(
        title: title.trim().isNotEmpty ? title.trim() : hydratedSong.title,
        artist: artist.trim().isNotEmpty ? artist.trim() : hydratedSong.artist,
        album: album.trim().isNotEmpty ? album.trim() : hydratedSong.album,
        releaseYear: releaseYear.trim().isNotEmpty
            ? releaseYear.trim()
            : hydratedSong.year,
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
      await _remapPlaylistPath(song.filePath, newPath);

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
      final hydratedSong = await ensureSongLyricsLoaded(song);
      var meta = hydratedSong.toTrackMetadata();
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
    await _remapPlaylistPath(oldPath, newPath);
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

      final discIdx = _discoveredSongs.indexWhere(
        (s) => s.filePath == refreshed.filePath,
      );
      if (discIdx != -1) {
        _discoveredSongs[discIdx] = refreshed;
      } else {
        _discoveredSongs = [refreshed, ..._discoveredSongs];
      }
      _rebuildVisibleSongs();

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

      if (_queueEntries.isEmpty && _allSongs.isNotEmpty) {
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
    await _remapPlaylistPath(song.filePath, movedPath);

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
    if (targetPath.trim().isEmpty) return false;

    final wasCurrent = currentSong?.filePath == targetPath;
    final wasPlayingCurrent = wasCurrent && _isPlaying;

    // 1. Release native MediaPlayer file lock FIRST if this track is active/loaded
    if (wasCurrent) {
      _playbackSessionId++;
      _isPlaying = false;
      _hasPreparedNative = false;
      if (Platform.isAndroid) {
        await _systemChannel.invokeMethod<bool>('localStop');
      }
    }

    // 2. Delete physical file via layered Android 11–15 Scoped Storage handler
    final deleted = await _folderService.deleteLocalAudioFile(targetPath);
    if (!deleted) {
      // Keep in-memory library & queue intact if user cancelled or deletion failed
      _syncProgressNotifiers();
      notifyListeners();
      return false;
    }

    // 3. Physical deletion confirmed: remove all occurrences from Queue & Library
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
    } else {
      _currentIndex = (_currentIndex - removedBeforeCurrent).clamp(
        0,
        _queueEntries.length - 1,
      );
      if (wasCurrent) {
        if (wasPlayingCurrent) {
          await _startCurrentQueueTrack();
        } else {
          _positionMs = 0;
          _durationMs = currentSong?.durationMs ?? 0;
          _hasPreparedNative = false;
        }
      }
    }

    _discoveredSongs.removeWhere((s) => s.filePath == targetPath);
    _rebuildVisibleSongs();
    if (_favoritePaths.remove(targetPath)) {
      await _saveFavorites();
    }
    await _remapPlaylistPath(targetPath, null);

    // Remove orphan extracted cover thumbnail if no other track shares it
    if (song.coverFilePath != null && song.coverFilePath!.isNotEmpty) {
      final sharedCover = _discoveredSongs.any(
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
    return true;
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
        final discIdx = _discoveredSongs.indexWhere(
          (s) => s.filePath == oldPath,
        );
        if (discIdx != -1) {
          _discoveredSongs[discIdx] = refreshed;
        } else {
          final newIdx = _discoveredSongs.indexWhere(
            (s) => s.filePath == newPath,
          );
          if (newIdx != -1) {
            _discoveredSongs[newIdx] = refreshed;
          } else {
            _discoveredSongs.insert(0, refreshed);
          }
        }
        _rebuildVisibleSongs();

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
            try {
              await _systemChannel.invokeMethod<bool>(
                'updateMediaNotification',
                {
                  'title': refreshed.title,
                  'artist': refreshed.artist,
                  'album': refreshed.album,
                  'coverPath': refreshed.coverFilePath,
                  'durationMs': refreshed.durationMs,
                },
              );
            } catch (_) {}
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
  // INCREMENTAL LIBRARY CACHE, PLAYER SESSION, FAVORITES & HIDDEN FOLDERS
  // ===========================================================================
  Future<File> _resolveDocFile(
    Directory docs,
    String primaryName,
    String legacyName,
  ) async {
    final primary = File('${docs.path}/$primaryName');
    if (await primary.exists()) return primary;
    final legacy = File('${docs.path}/$legacyName');
    if (await legacy.exists()) return legacy;
    return primary;
  }

  Future<bool> _loadLibraryAndSessionCache() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final libFile = await _resolveDocFile(
        docs,
        'musevee_library_cache_v1.json',
        'musicevee_library_cache_v1.json',
      );
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

      _discoveredSongs = hydratedSongs;
      _rebuildVisibleSongs();
      final byPath = {for (final s in _allSongs) s.filePath: s};

      // Restore last Musicolet player session & queue order
      final sessionFile = await _resolveDocFile(
        docs,
        'musevee_player_session.json',
        'musicevee_player_session.json',
      );
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

      if (!restoredQueue && _allSongs.isNotEmpty) {
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
    if (!Platform.isAndroid) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final libFile = File('${docs.path}/musevee_library_cache_v1.json');
      final payload = <String, dynamic>{
        'version': 1,
        'folders': _availableFolders,
        'songs': _discoveredSongs.map((s) => s.toJson()).toList(),
      };
      await libFile.writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  Future<void> _savePlayerSession() async {
    if (!Platform.isAndroid) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final sessionFile = File('${docs.path}/musevee_player_session.json');
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
    if (!Platform.isAndroid) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final f = await _resolveDocFile(
        docs,
        'musevee_favorites.json',
        'musicevee_favorites.json',
      );
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
    if (!Platform.isAndroid) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final f = File('${docs.path}/musevee_favorites.json');
      await f.writeAsString(jsonEncode(_favoritePaths.toList()), flush: true);
    } catch (_) {}
  }

  Future<void> _loadHiddenFolders() async {
    if (!Platform.isAndroid) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final f = File('${docs.path}/$hiddenFoldersFileName');
      if (await f.exists()) {
        final raw = await f.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _hiddenFolderPaths
            ..clear()
            ..addAll(
              decoded
                  .map((e) => _normalizeFolderKey(e.toString()))
                  .where((k) => k.isNotEmpty),
            );
          _onlyMusicFolders = false;
        } else if (decoded is Map) {
          final rawPaths = decoded['hiddenPaths'];
          if (rawPaths is List) {
            _hiddenFolderPaths
              ..clear()
              ..addAll(
                rawPaths
                    .map((e) => _normalizeFolderKey(e.toString()))
                    .where((k) => k.isNotEmpty),
              );
          }
          _onlyMusicFolders = decoded['onlyMusicFolders'] == true;
        }
      }
    } catch (_) {}
  }

  Future<void> _saveHiddenFolders() async {
    if (!Platform.isAndroid) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final f = File('${docs.path}/$hiddenFoldersFileName');
      await f.writeAsString(
        jsonEncode({
          'hiddenPaths': _hiddenFolderPaths.toList(),
          'onlyMusicFolders': _onlyMusicFolders,
        }),
        flush: true,
      );
    } catch (_) {}
  }

  // ===========================================================================
  // LOCAL PLAYLISTS (`musicevee_playlists_v1.json`), 6 SMART PLAYLISTS &
  // PLAY STATS (`musevee_play_stats_v1.json`)
  // ===========================================================================
  static const String playlistsFileName = 'musicevee_playlists_v1.json';

  int playCountFor(String filePath) =>
      _playStatsByPath[filePath]?.playCount ?? 0;

  int lastPlayedMsFor(String filePath) =>
      _playStatsByPath[filePath]?.lastPlayedMs ?? 0;

  void _recordTrackPlayed(String filePath, {int? playedAtMs}) {
    if (filePath.trim().isEmpty) return;
    final prev = _playStatsByPath[filePath];
    final nowMs = playedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    _playStatsByPath[filePath] = TrackPlayStat(
      playCount: (prev?.playCount ?? 0) + 1,
      lastPlayedMs: nowMs,
    );
    _savePlayStats();
  }

  @visibleForTesting
  void recordPlayForTesting(String filePath, {int? playedAtMs}) {
    _recordTrackPlayed(filePath, playedAtMs: playedAtMs);
    notifyListeners();
  }

  /// Resolves songs for one of the 6 Musicolet built-in Smart Playlists:
  /// - `smart_all_songs`: All active visible songs (`_allSongs`)
  /// - `smart_favorites`: Songs marked as Favorite (`_favoritePaths`)
  /// - `smart_recently_added`: Sorted by `lastModifiedMs` descending
  /// - `smart_recently_played`: Songs with `playCount > 0`, sorted by `lastPlayedMs` descending
  /// - `smart_most_played`: Songs with `playCount > 0`, sorted by `playCount` descending
  /// - `smart_not_played`: Songs with `playCount == 0`
  List<LocalSong> songsForSmartPlaylist(String smartId) {
    switch (smartId) {
      case SmartPlaylistId.allSongs:
        return List<LocalSong>.from(_allSongs);
      case SmartPlaylistId.favorites:
        return _allSongs
            .where((s) => _favoritePaths.contains(s.filePath))
            .toList();
      case SmartPlaylistId.recentlyAdded:
        final sorted = List<LocalSong>.from(_allSongs)
          ..sort((a, b) {
            final cmp = b.lastModifiedMs.compareTo(a.lastModifiedMs);
            if (cmp != 0) return cmp;
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
        return sorted;
      case SmartPlaylistId.recentlyPlayed:
        final played = _allSongs
            .where((s) => playCountFor(s.filePath) > 0)
            .toList()
          ..sort((a, b) {
            final cmp =
                lastPlayedMsFor(b.filePath).compareTo(lastPlayedMsFor(a.filePath));
            if (cmp != 0) return cmp;
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
        return played;
      case SmartPlaylistId.mostPlayed:
        final played = _allSongs
            .where((s) => playCountFor(s.filePath) > 0)
            .toList()
          ..sort((a, b) {
            final countCmp =
                playCountFor(b.filePath).compareTo(playCountFor(a.filePath));
            if (countCmp != 0) return countCmp;
            final recCmp =
                lastPlayedMsFor(b.filePath).compareTo(lastPlayedMsFor(a.filePath));
            if (recCmp != 0) return recCmp;
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
        return played;
      case SmartPlaylistId.notPlayed:
        return _allSongs
            .where((s) => playCountFor(s.filePath) == 0)
            .toList();
      default:
        return const <LocalSong>[];
    }
  }

  /// Resolves songs for any playlist identifier (either a `SmartPlaylistId` or
  /// a user-created `LocalPlaylist.id`).
  List<LocalSong> songsForPlaylistId(String id) {
    if (SmartPlaylistId.isSmartId(id)) {
      return songsForSmartPlaylist(id);
    }
    final playlist = playlistById(id);
    if (playlist == null) return const <LocalSong>[];
    return songsForPlaylist(playlist);
  }

  LocalPlaylist? playlistById(String id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  LocalPlaylist? playlistByName(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final p in _playlists) {
      if (p.name.trim().toLowerCase() == key) return p;
    }
    return null;
  }

  /// Resolves playlist paths into in-memory [LocalSong]s (missing files skipped).
  List<LocalSong> songsForPlaylist(LocalPlaylist playlist) {
    final byPath = _songsByPath;
    final result = <LocalSong>[];
    for (final path in playlist.songPaths) {
      final song = byPath[path];
      if (song != null) result.add(song);
    }
    return result;
  }

  /// First resolvable cover art path of a playlist (custom cover takes priority).
  String? playlistCoverPath(LocalPlaylist playlist) {
    final custom = playlist.customCoverPath;
    if (custom != null && custom.isNotEmpty) return custom;
    for (final s in songsForPlaylist(playlist)) {
      final c = s.coverFilePath;
      if (c != null && c.isNotEmpty) return c;
    }
    return null;
  }

  List<LocalPlaylist> playlistsContaining(String filePath) =>
      _playlists.where((p) => p.songPaths.contains(filePath)).toList();

  Future<LocalPlaylist> createPlaylist(
    String name, {
    List<String> initialPaths = const [],
  }) async {
    final now = DateTime.now();
    final trimmed = name.trim().isEmpty ? 'Playlist Baru' : name.trim();
    final seen = <String>{};
    final playlist = LocalPlaylist(
      id: 'pl_${now.microsecondsSinceEpoch}',
      name: trimmed,
      songPaths: List<String>.unmodifiable(
        initialPaths.where((p) => p.trim().isNotEmpty && seen.add(p)),
      ),
      createdAt: now,
      updatedAt: now,
    );
    _playlists.insert(0, playlist);
    notifyListeners();
    await _savePlaylists();
    return playlist;
  }

  /// Returns the playlist named [name] (case-insensitive) or creates it — used
  /// by Spotify Album/Playlist batch downloads to auto-sync playlist names.
  Future<LocalPlaylist> ensurePlaylistNamed(String name) async {
    final existing = playlistByName(name);
    if (existing != null) return existing;
    return createPlaylist(name);
  }

  Future<void> renamePlaylist(String id, String newName) async {
    final idx = _playlists.indexWhere((p) => p.id == id);
    final trimmed = newName.trim();
    if (idx == -1 || trimmed.isEmpty) return;
    _playlists[idx] = _playlists[idx].copyWith(
      name: trimmed,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    await _savePlaylists();
  }

  Future<void> deletePlaylist(String id) async {
    final before = _playlists.length;
    _playlists.removeWhere((p) => p.id == id);
    if (_playlists.length == before) return;
    notifyListeners();
    await _savePlaylists();
  }

  /// Appends [paths] to playlist [id], skipping songs already inside it.
  /// Returns the number of songs actually added.
  Future<int> addSongsToPlaylist(String id, List<String> paths) async {
    final idx = _playlists.indexWhere((p) => p.id == id);
    if (idx == -1) return 0;
    final current = List<String>.from(_playlists[idx].songPaths);
    final existing = current.toSet();
    int added = 0;
    for (final raw in paths) {
      final path = raw.trim();
      if (path.isEmpty || !existing.add(path)) continue;
      current.add(path);
      added++;
    }
    if (added == 0) return 0;
    _playlists[idx] = _playlists[idx].copyWith(
      songPaths: current,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    await _savePlaylists();
    return added;
  }

  Future<bool> addSongToPlaylist(String id, String filePath) async =>
      (await addSongsToPlaylist(id, [filePath])) > 0;

  Future<void> removeSongFromPlaylist(String id, String filePath) async {
    final idx = _playlists.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final current = List<String>.from(_playlists[idx].songPaths);
    if (!current.remove(filePath)) return;
    _playlists[idx] = _playlists[idx].copyWith(
      songPaths: current,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    await _savePlaylists();
  }

  Future<void> reorderPlaylistSong(String id, int oldIndex, int newIndex) async {
    final idx = _playlists.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final current = List<String>.from(_playlists[idx].songPaths);
    if (oldIndex < 0 || oldIndex >= current.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    target = target.clamp(0, current.length - 1);
    final moved = current.removeAt(oldIndex);
    current.insert(target, moved);
    _playlists[idx] = _playlists[idx].copyWith(
      songPaths: current,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    await _savePlaylists();
  }

  /// Smart Deduplication: finds an already-present local song matching
  /// [title]/[artist] by normalized identity (`artist::title`, Katakana/Hiragana,
  /// macron & noise-tag folding) so downloads can be skipped.
  LocalSong? findLocalSongByIdentity(String title, String artist) {
    final identity = TrackMetadata.normalizeTrackIdentity(title, artist);
    final titleOnly = TrackMetadata.normalizeTrackSegment(
      title,
      stripFeat: true,
    );
    final artistOnly = TrackMetadata.normalizeTrackSegment(
      artist,
      stripFeat: true,
    );
    if (titleOnly.isEmpty) return null;

    LocalSong? looseMatch;
    for (final s in _allSongs) {
      if (identity.isNotEmpty &&
          TrackMetadata.normalizeTrackIdentity(s.title, s.artist) == identity) {
        return s;
      }
      if (looseMatch == null && artistOnly.length >= 2) {
        final sTitle = TrackMetadata.normalizeTrackSegment(
          s.title,
          stripFeat: true,
        );
        final sArtist = TrackMetadata.normalizeTrackSegment(s.artist);
        if (sTitle == titleOnly && sArtist.contains(artistOnly)) {
          looseMatch = s;
        }
      }
    }
    return looseMatch;
  }

  Future<void> _remapPlaylistPath(String oldPath, String? newPath) async {
    if (oldPath == newPath) return;
    final prevStat = _playStatsByPath.remove(oldPath);
    if (prevStat != null && newPath != null && newPath.isNotEmpty) {
      _playStatsByPath[newPath] = prevStat;
    }
    if (prevStat != null) {
      await _savePlayStats();
    }
    bool changed = false;
    for (int i = 0; i < _playlists.length; i++) {
      final paths = _playlists[i].songPaths;
      if (!paths.contains(oldPath)) continue;
      final updated = <String>[];
      final seen = <String>{};
      for (final p in paths) {
        final mapped = p == oldPath ? newPath : p;
        if (mapped != null && seen.add(mapped)) updated.add(mapped);
      }
      _playlists[i] = _playlists[i].copyWith(
        songPaths: updated,
        updatedAt: DateTime.now(),
      );
      changed = true;
    }
    if (changed) await _savePlaylists();
  }

  Future<void> _loadPlayStats() async {
    if (!Platform.isAndroid) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final f = File('${docs.path}/$playStatsFileName');
      if (!await f.exists()) return;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map) return;
      _playStatsByPath.clear();
      for (final entry in decoded.entries) {
        final path = entry.key.toString();
        final val = entry.value;
        if (path.isNotEmpty && val is Map) {
          _playStatsByPath[path] = TrackPlayStat.fromJson(
            Map<String, dynamic>.from(val),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _savePlayStats() async {
    if (!Platform.isAndroid) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final f = File('${docs.path}/$playStatsFileName');
      final payload = <String, dynamic>{
        for (final entry in _playStatsByPath.entries)
          entry.key: entry.value.toJson(),
      };
      await f.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }

  Future<void> _loadPlaylists() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final f = await _resolveDocFile(
        docs,
        playlistsFileName,
        'musevee_playlists_v1.json',
      );
      if (!await f.exists()) return;
      final decoded = jsonDecode(await f.readAsString());
      final rawList = decoded is Map ? decoded['playlists'] : decoded;
      if (rawList is! List) return;
      _playlists
        ..clear()
        ..addAll(
          rawList
              .whereType<Map>()
              .map((m) => LocalPlaylist.fromJson(Map<String, dynamic>.from(m))),
        );
    } catch (_) {}
  }

  Future<void> _savePlaylists() async {
    if (!Platform.isAndroid) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final f = File('${docs.path}/$playlistsFileName');
      final payload = <String, dynamic>{
        'version': 1,
        'playlists': _playlists.map((p) => p.toJson()).toList(),
      };
      await f.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }
}

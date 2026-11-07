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

  // Active Playback & Queue State
  List<LocalSong> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _hasPreparedNative = false;
  int _positionMs = 0;
  int _durationMs = 0;
  double _volume = 0.85;
  MusicoletPlayMode _playMode = MusicoletPlayMode.repeatAll;
  bool _isShuffle = false;

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

  List<LocalSong> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  LocalSong? get currentSong =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;

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
    final map = <String, List<LocalSong>>{};
    for (final f in _availableFolders) {
      map[f] = [];
    }
    for (final song in _allSongs) {
      map.putIfAbsent(song.folderName, () => []).add(song);
    }
    return map;
  }

  /// Grouped songs per Album.
  Map<String, List<LocalSong>> get albumSongsMap {
    final map = <String, List<LocalSong>>{};
    for (final song in _allSongs) {
      final key = song.album.trim().isNotEmpty ? song.album.trim() : 'Single';
      map.putIfAbsent(key, () => []).add(song);
    }
    final sortedKeys = map.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return {for (final k in sortedKeys) k: map[k]!};
  }

  /// Grouped songs per Artist.
  Map<String, List<LocalSong>> get artistSongsMap {
    final map = <String, List<LocalSong>>{};
    for (final song in _allSongs) {
      final key = song.artist.trim().isNotEmpty
          ? song.artist.trim()
          : 'Unknown Artist';
      map.putIfAbsent(key, () => []).add(song);
    }
    final sortedKeys = map.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return {for (final k in sortedKeys) k: map[k]!};
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
    await _syncDeviceVolume();
    await refreshLibrary(requestPermission: true);
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

  /// Scans `/storage/emulated/0/Music/*` and MediaStore via `MainActivity.kt`
  /// to load all local MP3s along with their `APIC` covers, `USLT` lyrics,
  /// and dominant ambient colors.
  Future<void> refreshLibrary({bool requestPermission = false}) async {
    if (!Platform.isAndroid) return;
    if (_isLoadingLibrary) return;

    _isLoadingLibrary = true;
    notifyListeners();

    try {
      if (requestPermission) {
        await _requestAudioReadPermissions();
      }
      _availableFolders = await _folderService.listAvailableFolders();

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

      // Sort newest modified first within library, or title-sorted
      parsed.sort((a, b) {
        final cmp = b.lastModifiedMs.compareTo(a.lastModifiedMs);
        if (cmp != 0) return cmp;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

      _allSongs = parsed;

      // Ensure any extra folder names discovered are in _availableFolders
      final seenLower = _availableFolders.map((f) => f.toLowerCase()).toSet();
      for (final s in _allSongs) {
        if (s.folderName.isNotEmpty &&
            !seenLower.contains(s.folderName.toLowerCase())) {
          seenLower.add(s.folderName.toLowerCase());
          _availableFolders = [..._availableFolders, s.folderName];
        }
      }

      // Refresh queue items with updated metadata if paths match
      if (_queue.isNotEmpty) {
        final byPath = {for (final s in _allSongs) s.filePath: s};
        _queue = _queue.map((q) => byPath[q.filePath] ?? q).toList();
      } else if (_allSongs.isNotEmpty) {
        // Pre-populate queue with all local songs ready to play on first launch
        _queue = List<LocalSong>.from(_allSongs);
        _currentIndex = 0;
        _durationMs = _queue.first.durationMs;
        _hasPreparedNative = false;
      }
    } catch (e) {
      debugPrint('[MusicEvee] refreshLibrary gagal: $e');
    } finally {
      _isLoadingLibrary = false;
      notifyListeners();
    }
  }

  // ===========================================================================
  // NATIVE CALLBACK HANDLERS (routed from unified MethodChannel handler)
  // ===========================================================================
  void handleNativePosition({
    required int positionMs,
    required int durationMs,
    required bool isPlaying,
  }) {
    _positionMs = positionMs;
    if (durationMs > 0) {
      _durationMs = durationMs;
    }
    _isPlaying = isPlaying;
    notifyListeners();
  }

  void handleNativePlayerState({
    required bool isPlaying,
    required int positionMs,
    required int durationMs,
  }) {
    _isPlaying = isPlaying;
    if (positionMs >= 0 && (positionMs > 0 || !isPlaying)) {
      _positionMs = positionMs;
    }
    if (durationMs > 0) {
      _durationMs = durationMs;
    }
    notifyListeners();
  }

  void handleNativeTrackCompleted() {
    playNext(fromAutoComplete: true);
  }

  // ===========================================================================
  // PLAYBACK & QUEUE CONTROLS
  // ===========================================================================
  Future<void> playSong(
    LocalSong song, {
    List<LocalSong>? queueContext,
    int startPositionMs = 0,
  }) async {
    if (queueContext != null && queueContext.isNotEmpty) {
      _queue = List<LocalSong>.from(queueContext);
      _currentIndex = _queue.indexWhere((s) => s.filePath == song.filePath);
      if (_currentIndex == -1) {
        _queue.insert(0, song);
        _currentIndex = 0;
      }
    } else {
      final existingIdx = _queue.indexWhere((s) => s.filePath == song.filePath);
      if (existingIdx != -1) {
        _currentIndex = existingIdx;
        _queue[existingIdx] = song;
      } else {
        final insertAt =
            (_currentIndex >= 0 && _currentIndex + 1 <= _queue.length)
                ? _currentIndex + 1
                : _queue.length;
        _queue.insert(insertAt, song);
        _currentIndex = insertAt;
      }
    }

    _localLyricsCandidates = const [];
    await _startCurrentQueueTrack(startPositionMs: startPositionMs);
  }

  Future<void> playSongByPath(String filePath) async {
    final idx = _allSongs.indexWhere((s) => s.filePath == filePath);
    if (idx != -1) {
      await playSong(_allSongs[idx], queueContext: _allSongs);
      return;
    }
    if (Platform.isAndroid) {
      try {
        final details = await _systemChannel.invokeMethod<Map<dynamic, dynamic>>(
          'readLocalTrackDetails',
          {'path': filePath},
        );
        if (details != null) {
          final loaded = LocalSong.fromNativeMap(details);
          _allSongs = [loaded, ..._allSongs];
          await playSong(loaded, queueContext: _allSongs);
        }
      } catch (_) {}
    }
  }

  Future<void> playQueueIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    _localLyricsCandidates = const [];
    await _startCurrentQueueTrack();
  }

  Future<void> playFolder(String folderName, {bool shuffle = false}) async {
    final songs = folderSongsMap[folderName] ?? const [];
    if (songs.isEmpty) return;
    _isShuffle = shuffle;
    final startIdx = shuffle ? _random.nextInt(songs.length) : 0;
    await playSong(songs[startIdx], queueContext: songs);
  }

  Future<void> playAlbum(String albumName, {bool shuffle = false}) async {
    final songs = albumSongsMap[albumName] ?? const [];
    if (songs.isEmpty) return;
    _isShuffle = shuffle;
    final startIdx = shuffle ? _random.nextInt(songs.length) : 0;
    await playSong(songs[startIdx], queueContext: songs);
  }

  Future<void> playArtist(String artistName, {bool shuffle = false}) async {
    final songs = artistSongsMap[artistName] ?? const [];
    if (songs.isEmpty) return;
    _isShuffle = shuffle;
    final startIdx = shuffle ? _random.nextInt(songs.length) : 0;
    await playSong(songs[startIdx], queueContext: songs);
  }

  Future<void> _startCurrentQueueTrack({int startPositionMs = 0}) async {
    final song = currentSong;
    if (song == null) return;

    _positionMs = startPositionMs;
    _durationMs = song.durationMs;
    _isPlaying = true;
    _hasPreparedNative = true;
    if (song.hasSyncedLyrics) {
      _lyricsDisplayMode = EmbeddedLyricsDisplayMode.synced;
    }
    notifyListeners();

    if (!Platform.isAndroid) return;
    try {
      final ok = await _systemChannel.invokeMethod<bool>(
        'localPlayFile',
        {
          'path': song.filePath,
          'positionMs': startPositionMs,
        },
      );
      if (ok != true) {
        _isPlaying = false;
        _hasPreparedNative = false;
        notifyListeners();
      }
    } catch (_) {
      _isPlaying = false;
      _hasPreparedNative = false;
      notifyListeners();
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
    _positionMs = clamped;
    notifyListeners();

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
    if (_queue.isEmpty) return;

    if (fromAutoComplete) {
      if (_playMode == MusicoletPlayMode.playSingleStop) {
        // Musicolet `1→`: stop cleanly after finishing current track
        _isPlaying = false;
        _positionMs = 0;
        _hasPreparedNative = false;
        notifyListeners();
        return;
      }
      if (_playMode == MusicoletPlayMode.repeatOne) {
        await _startCurrentQueueTrack(startPositionMs: 0);
        return;
      }
    }

    if (_isShuffle && _queue.length > 1) {
      int nextIdx = _currentIndex;
      for (int tries = 0; tries < 6 && nextIdx == _currentIndex; tries++) {
        nextIdx = _random.nextInt(_queue.length);
      }
      _currentIndex = nextIdx;
      _localLyricsCandidates = const [];
      await _startCurrentQueueTrack();
      return;
    }

    if (_currentIndex + 1 < _queue.length) {
      _currentIndex++;
      _localLyricsCandidates = const [];
      await _startCurrentQueueTrack();
    } else {
      if (fromAutoComplete && _playMode == MusicoletPlayMode.playQueueOnce) {
        _isPlaying = false;
        _positionMs = 0;
        _hasPreparedNative = false;
        notifyListeners();
        return;
      }
      _currentIndex = 0;
      _localLyricsCandidates = const [];
      await _startCurrentQueueTrack();
    }
  }

  Future<void> playPrevious() async {
    if (_queue.isEmpty) return;
    if (_positionMs > 3500) {
      await seekTo(0);
      return;
    }
    if (_currentIndex > 0) {
      _currentIndex--;
    } else {
      _currentIndex = _queue.length - 1;
    }
    _localLyricsCandidates = const [];
    await _startCurrentQueueTrack();
  }

  void addToQueue(LocalSong song, {bool playNext = false}) {
    if (_queue.isEmpty) {
      playSong(song, queueContext: [song]);
      return;
    }
    if (playNext && _currentIndex >= 0 && _currentIndex + 1 <= _queue.length) {
      _queue.insert(_currentIndex + 1, song);
    } else {
      _queue.add(song);
    }
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    final removingCurrent = index == _currentIndex;
    _queue.removeAt(index);

    if (_queue.isEmpty) {
      _currentIndex = -1;
      _isPlaying = false;
      _positionMs = 0;
      _durationMs = 0;
      _hasPreparedNative = false;
      if (Platform.isAndroid) {
        _systemChannel.invokeMethod<bool>('localStop');
      }
    } else if (removingCurrent) {
      if (_currentIndex >= _queue.length) {
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
    notifyListeners();
  }

  void reorderQueueItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;

    final currentPath = currentSong?.filePath;
    final moved = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, moved);
    if (currentPath != null) {
      _currentIndex = _queue.indexWhere((s) => s.filePath == currentPath);
    }
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    reorderQueueItem(oldIndex, newIndex);
  }

  void clearQueue() {
    _queue = [];
    _currentIndex = -1;
    _isPlaying = false;
    _positionMs = 0;
    _durationMs = 0;
    _hasPreparedNative = false;
    if (Platform.isAndroid) {
      _systemChannel.invokeMethod<bool>('localStop');
    }
    notifyListeners();
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
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    notifyListeners();
  }

  void setShowLyricsOverlay(bool visible) {
    if (_showLyricsOverlay == visible) return;
    _showLyricsOverlay = visible;
    notifyListeners();
  }

  void setLyricsDisplayMode(EmbeddedLyricsDisplayMode mode) {
    if (_lyricsDisplayMode == mode) return;
    _lyricsDisplayMode = mode;
    notifyListeners();
  }

  void toggleAutoScrollLyrics() {
    _autoScrollLyrics = !_autoScrollLyrics;
    notifyListeners();
  }

  void cycleLyricsFontSize() {
    _fontSizeIndex = (_fontSizeIndex + 1) % fontSizePresets.length;
    notifyListeners();
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

  Future<String> moveLocalSongToFolder({
    required LocalSong song,
    required String targetFolderName,
  }) async {
    final isCurrent = currentSong?.filePath == song.filePath;
    final wasPlaying = isCurrent && _isPlaying;
    final savedPos = isCurrent ? _positionMs : 0;

    if (isCurrent && Platform.isAndroid) {
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
    final idxInQueue = _queue.indexWhere((s) => s.filePath == song.filePath);
    if (idxInQueue != -1) {
      removeFromQueue(idxInQueue);
    }
    _allSongs.removeWhere((s) => s.filePath == song.filePath);
    if (_favoritePaths.remove(song.filePath)) {
      await _saveFavorites();
    }
    notifyListeners();
    return _folderService.deleteMediaFile(song.filePath);
  }

  Future<void> _reloadSingleSongInMemory({
    required String oldPath,
    required String newPath,
    required bool wasPlaying,
    required int resumePositionMs,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      final map = await _systemChannel.invokeMethod<Map<dynamic, dynamic>>(
        'readLocalTrackDetails',
        {'path': newPath},
      );
      if (map != null) {
        final refreshed = LocalSong.fromNativeMap(map);
        final libIdx = _allSongs.indexWhere((s) => s.filePath == oldPath);
        if (libIdx != -1) {
          _allSongs[libIdx] = refreshed;
        } else {
          _allSongs.insert(0, refreshed);
        }

        for (int i = 0; i < _queue.length; i++) {
          if (_queue[i].filePath == oldPath || _queue[i].filePath == newPath) {
            _queue[i] = refreshed;
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
    notifyListeners();
  }

  // ===========================================================================
  // FAVORITES PERSISTENCE
  // ===========================================================================
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

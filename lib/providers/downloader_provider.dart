import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/download_item.dart';
import '../models/track_metadata.dart';
import '../services/audio_service.dart';
import '../services/folder_service.dart';
import '../services/lyrics_service.dart';
import '../services/metadata_service.dart';
import '../services/romaji_service.dart';
import '../services/tagging_service.dart';

enum DownloaderState {
  idle,
  searchingCatalog,
  showingSearchResults,
  fetchingMetadata,
  readyToDownload,
  fetchingLyrics,
  downloadingAudio,
  taggingAudio,
  completed,
  error,
}

class DownloaderProvider extends ChangeNotifier {
  static const MethodChannel _systemChannel = MethodChannel(
    'com.spotmeta.downloader/system',
  );

  final MetadataService _metadataService;
  final LyricsService _lyricsService;
  final AudioService _audioService;
  final TaggingService _taggingService;
  final FolderService _folderService;
  final RomajiService _romajiService;

  DownloaderProvider({
    MetadataService? metadataService,
    LyricsService? lyricsService,
    AudioService? audioService,
    TaggingService? taggingService,
    FolderService? folderService,
    RomajiService? romajiService,
  })  : _metadataService = metadataService ?? MetadataService(),
        _lyricsService = lyricsService ?? LyricsService(),
        _audioService = audioService ?? AudioService(),
        _taggingService = taggingService ?? TaggingService(),
        _folderService = folderService ?? FolderService(),
        _romajiService = romajiService ?? RomajiService() {
    _initFolders();
  }

  DownloaderState _state = DownloaderState.idle;
  TrackMetadata? _trackMetadata;
  SpotifyCollectionResult? _currentCollection;
  List<TrackMetadata> _searchResults = const [];
  final Map<String, String> _duplicateFolderMap = {};
  Map<String, int> _folderSongCounts = {};
  List<String> _availableFolders =
      List<String>.from(FolderService.defaultFolders);
  String _selectedFolder = FolderService.defaultFolders.first;

  // Feature 1: 30s Audio Preview & Manual YouTube Candidate Picker
  bool _isPreviewPlaying = false;
  String? _activePreviewUrl;
  List<YoutubeCandidate> _youtubeCandidates = const [];
  bool _isSearchingYoutubeCandidates = false;
  YoutubeCandidate? _selectedYoutubeCandidate;

  // Feature 2: Synced [LRC] vs Plain Lyrics toggle & Manual Lyrics Candidate Picker
  bool _preferSyncedLyrics = true;
  List<LyricsCandidate> _lyricsCandidates = const [];
  bool _isSearchingLyricsCandidates = false;
  LyricsCandidate? _selectedLyricsCandidate;

  // Feature 3: Auto-Romaji state
  bool _isRomanizing = false;

  final List<DownloadItem> _queueItems = [];
  bool _isProcessingQueue = false;

  double _progress = 0.0;
  String _statusMessage = 'Siap mencari lagu.';
  String? _errorMessage;
  String? _savedFilePath;

  DownloaderState get state => _state;
  TrackMetadata? get trackMetadata => _trackMetadata;
  SpotifyCollectionResult? get currentCollection => _currentCollection;
  List<TrackMetadata> get searchResults => _searchResults;
  List<String> get availableFolders => List.unmodifiable(_availableFolders);
  String get selectedFolder => _selectedFolder;
  List<DownloadItem> get queueItems => List.unmodifiable(_queueItems);
  Map<String, int> get folderSongCounts => Map.unmodifiable(_folderSongCounts);

  bool get isPreviewPlaying => _isPreviewPlaying;
  String? get activePreviewUrl => _activePreviewUrl;
  List<YoutubeCandidate> get youtubeCandidates =>
      List.unmodifiable(_youtubeCandidates);
  bool get isSearchingYoutubeCandidates => _isSearchingYoutubeCandidates;
  YoutubeCandidate? get selectedYoutubeCandidate => _selectedYoutubeCandidate;
  bool get preferSyncedLyrics => _preferSyncedLyrics;
  List<LyricsCandidate> get lyricsCandidates =>
      List.unmodifiable(_lyricsCandidates);
  bool get isSearchingLyricsCandidates => _isSearchingLyricsCandidates;
  LyricsCandidate? get selectedLyricsCandidate => _selectedLyricsCandidate;
  bool get isRomanizing => _isRomanizing;
  RomajiService get romajiService => _romajiService;

  int get activeQueueCount => _queueItems
      .where(
        (e) =>
            e.status == DownloadItemStatus.queued ||
            e.status == DownloadItemStatus.downloading ||
            e.status == DownloadItemStatus.tagging,
      )
      .length;

  double get progress => _progress;
  String get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  String? get savedFilePath => _savedFilePath;

  bool get isBusy =>
      _state == DownloaderState.searchingCatalog ||
      _state == DownloaderState.fetchingMetadata ||
      _state == DownloaderState.fetchingLyrics ||
      _state == DownloaderState.downloadingAudio ||
      _state == DownloaderState.taggingAudio;

  bool get canDownload =>
      _trackMetadata != null &&
      (_state == DownloaderState.readyToDownload ||
          _state == DownloaderState.completed ||
          _state == DownloaderState.error);

  bool isSpotifyTrackInput(String rawInput) =>
      _metadataService.isSpotifyInput(rawInput);

  bool isSpotifyCollectionInput(String rawInput) =>
      _metadataService.isSpotifyCollectionInput(rawInput);

  /// Returns the folder name if [track] already exists in one of the Music folders.
  String? duplicateFolderFor(TrackMetadata track) {
    return _duplicateFolderMap[track.sanitizedFileName.toLowerCase()];
  }

  // ===========================================================================
  // FEATURE 1A: 30s AUDIO PREVIEW (Native MediaPlayer via MethodChannel)
  // ===========================================================================
  Future<void> togglePreviewAudio(String? previewUrl) async {
    final cleanUrl = previewUrl?.trim() ?? '';
    if (cleanUrl.isEmpty) return;

    if (_isPreviewPlaying && _activePreviewUrl == cleanUrl) {
      await stopPreviewAudio();
      return;
    }

    try {
      _isPreviewPlaying = true;
      _activePreviewUrl = cleanUrl;
      notifyListeners();
      final ok = await _systemChannel.invokeMethod<bool>(
        'playPreviewUrl',
        {'url': cleanUrl},
      );
      if (ok != true) {
        _isPreviewPlaying = false;
        _activePreviewUrl = null;
        notifyListeners();
      }
    } catch (_) {
      _isPreviewPlaying = false;
      _activePreviewUrl = null;
      notifyListeners();
    }
  }

  Future<void> stopPreviewAudio() async {
    final wasPlaying = _isPreviewPlaying || _activePreviewUrl != null;
    _isPreviewPlaying = false;
    _activePreviewUrl = null;
    if (wasPlaying) {
      notifyListeners();
    }
    try {
      await _systemChannel.invokeMethod<bool>('stopPreview');
    } catch (_) {}
  }

  void handleNativePreviewStateChanged({
    required bool isPlaying,
    String? url,
  }) {
    _isPreviewPlaying = isPlaying;
    _activePreviewUrl = isPlaying ? url : null;
    notifyListeners();
  }

  // ===========================================================================
  // FEATURE 1B: YOUTUBE SOURCE CANDIDATE PICKER
  // ===========================================================================
  Future<void> loadYoutubeCandidates() async {
    final current = _trackMetadata;
    if (current == null || _isSearchingYoutubeCandidates) return;

    _isSearchingYoutubeCandidates = true;
    notifyListeners();

    try {
      final list = await _audioService.searchYoutubeCandidates(current);
      _youtubeCandidates = list;
      if (_selectedYoutubeCandidate != null) {
        final match = list
            .where((c) => c.videoId == _selectedYoutubeCandidate!.videoId)
            .toList();
        if (match.isNotEmpty) {
          _selectedYoutubeCandidate = match.first;
        }
      }
    } catch (_) {
      _youtubeCandidates = const [];
    } finally {
      _isSearchingYoutubeCandidates = false;
      notifyListeners();
    }
  }

  void selectYoutubeCandidate(YoutubeCandidate? candidate) {
    _selectedYoutubeCandidate = candidate;
    final current = _trackMetadata;
    if (current != null) {
      _trackMetadata = current.copyWith(
        preferredYoutubeVideoId: candidate?.videoId,
        clearPreferredYoutubeVideoId: candidate == null,
      );
    }
    notifyListeners();
  }

  // ===========================================================================
  // FEATURE 2: SYNCED LRC VS PLAIN LYRICS TOGGLE & MANUAL LYRICS PICKER
  // ===========================================================================
  void setPreferSyncedLyrics(bool value) {
    if (_preferSyncedLyrics == value) return;
    _preferSyncedLyrics = value;
    notifyListeners();
  }

  /// Loads LRCLIB lyrics candidates for [forTrack] (or [_trackMetadata]) so the
  /// user can manually switch between `[Jepang/Kanji]`, `[Romaji]`, `[Bilingual]`,
  /// and `[Inggris/Lainnya]` versions via the "Ganti Lirik" picker.
  Future<void> loadLyricsCandidates({TrackMetadata? forTrack}) async {
    final target = forTrack ?? _trackMetadata;
    if (target == null || _isSearchingLyricsCandidates) return;

    _isSearchingLyricsCandidates = true;
    notifyListeners();

    try {
      final response = await _lyricsService.fetchLyricsWithCandidates(
        trackName: target.title,
        artistName: target.artist,
        albumName: target.album,
        durationSeconds: target.durationSeconds,
        targetFolder: _selectedFolder,
      );
      _lyricsCandidates = response.candidates;
      if (_selectedLyricsCandidate != null) {
        final match = response.candidates
            .where((c) => c.id == _selectedLyricsCandidate!.id)
            .toList();
        if (match.isNotEmpty) {
          _selectedLyricsCandidate = match.first;
        } else {
          _selectedLyricsCandidate = response.selectedCandidate;
        }
      } else {
        _selectedLyricsCandidate = response.selectedCandidate;
      }
    } catch (_) {
      _lyricsCandidates = const [];
    } finally {
      _isSearchingLyricsCandidates = false;
      notifyListeners();
    }
  }

  /// Applies the chosen [candidate] to the current previewed track metadata.
  void selectLyricsCandidate(LyricsCandidate candidate) {
    _selectedLyricsCandidate = candidate;
    final current = _trackMetadata;
    if (current != null) {
      _trackMetadata = current.copyWith(
        syncedLyrics: candidate.syncedLyrics,
        plainLyrics: candidate.plainLyrics,
        clearSyncedLyrics: !candidate.hasSynced,
      );
      _preferSyncedLyrics = candidate.hasSynced;
    }
    notifyListeners();
  }

  // ===========================================================================
  // FEATURE 3: AUTO-ROMAJI CONVERSION
  // ===========================================================================
  Future<bool> autoRomanizeCurrentTrack() async {
    final current = _trackMetadata;
    if (current == null || _isRomanizing) return false;

    _isRomanizing = true;
    notifyListeners();

    try {
      var romanized = await _romajiService.romanizeTrackInfo(current);
      if (RomajiService.trackLyricsHasJapanese(romanized)) {
        romanized = await _romajiService.romanizeTrackLyrics(romanized);
        if (romanized.hasSyncedLyrics) {
          _preferSyncedLyrics = true;
        }
      }
      _trackMetadata = romanized;
      await _checkDuplicatesForTracks([romanized]);
      return true;
    } catch (_) {
      return false;
    } finally {
      _isRomanizing = false;
      notifyListeners();
    }
  }

  /// Converts the current track's lyrics (`syncedLyrics` and `plainLyrics`)
  /// into Romaji while preserving `[mm:ss.xx]` timestamps and deriving
  /// `plainLyrics` without duplicate API requests.
  Future<bool> autoRomanizeCurrentLyrics() async {
    final current = _trackMetadata;
    if (current == null || _isRomanizing) return false;

    _isRomanizing = true;
    notifyListeners();

    try {
      final romanized = await _romajiService.romanizeTrackLyrics(current);
      _trackMetadata = romanized;
      if (romanized.hasSyncedLyrics) {
        _preferSyncedLyrics = true;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      _isRomanizing = false;
      notifyListeners();
    }
  }

  // ===========================================================================
  // FOLDER MANAGEMENT
  // ===========================================================================
  Future<void> _initFolders() async {
    try {
      final folders = await _folderService.listAvailableFolders();
      final lastFolder = await _folderService.loadLastSelectedFolder();
      _availableFolders = folders;
      if (_availableFolders.contains(lastFolder)) {
        _selectedFolder = lastFolder;
      } else if (lastFolder.isNotEmpty) {
        _availableFolders = [..._availableFolders, lastFolder];
        _selectedFolder = lastFolder;
      }
      _folderSongCounts =
          await _folderService.getFolderSongCounts(_availableFolders);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshFolders() async {
    final folders = await _folderService.listAvailableFolders();
    if (!folders.contains(_selectedFolder) && _selectedFolder.isNotEmpty) {
      _availableFolders = [...folders, _selectedFolder];
    } else {
      _availableFolders = folders;
    }
    _folderSongCounts =
        await _folderService.getFolderSongCounts(_availableFolders);
    notifyListeners();
    onLibraryChanged?.call();
  }

  VoidCallback? onLibraryChanged;

  Future<void> selectFolder(String folderName) async {
    final trimmed = folderName.trim();
    if (trimmed.isEmpty) return;
    _selectedFolder = trimmed;
    if (!_availableFolders.contains(trimmed)) {
      _availableFolders = [..._availableFolders, trimmed];
    }
    notifyListeners();
    await _folderService.saveLastSelectedFolder(trimmed);
  }

  Future<String> createAndSelectFolder(String rawName) async {
    final created = await _folderService.createCustomFolder(rawName);
    await refreshFolders();
    await selectFolder(created);
    return created;
  }

  /// Resets the state back to idle.
  void reset() {
    stopPreviewAudio();
    _state = DownloaderState.idle;
    _trackMetadata = null;
    _currentCollection = null;
    _searchResults = const [];
    _youtubeCandidates = const [];
    _selectedYoutubeCandidate = null;
    _lyricsCandidates = const [];
    _selectedLyricsCandidate = null;
    _progress = 0.0;
    _statusMessage = 'Siap mencari lagu.';
    _errorMessage = null;
    _savedFilePath = null;
    notifyListeners();
  }

  /// Smart entry point: automatically detects whether [rawInput] is a Spotify
  /// Album/Playlist link, a Spotify Track link, or a music search query.
  Future<void> submitSmartInput(String rawInput) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty || isBusy) return;

    await stopPreviewAudio();

    if (_metadataService.isSpotifyCollectionInput(trimmed)) {
      final extractedUrl = _metadataService.extractUrlFromSharedText(trimmed);
      await checkCollection(extractedUrl);
    } else if (_metadataService.isSpotifyInput(trimmed)) {
      final extractedUrl = _metadataService.extractUrlFromSharedText(trimmed);
      await checkTrack(extractedUrl);
    } else {
      await searchTracks(trimmed);
    }
  }

  /// Searches music tracks by keyword (Deezer + iTunes) and checks for existing duplicates.
  Future<void> searchTracks(String query) async {
    if (isBusy) return;

    _errorMessage = null;
    _savedFilePath = null;
    _trackMetadata = null;
    _currentCollection = null;
    _searchResults = const [];

    _setState(
      DownloaderState.searchingCatalog,
      progress: 0.35,
      message: 'Memuat info...',
    );

    try {
      final results = await _metadataService.searchMusicTracks(query);
      _searchResults = results;

      await _checkDuplicatesForTracks(results);

      _setState(
        DownloaderState.showingSearchResults,
        progress: 1.0,
        message: '${results.length} lagu ditemukan',
      );
    } catch (e, s) {
      _handleError(e, s);
    }
  }

  /// Selects a track from the search results list, fetches its lyrics and
  /// language-classified candidates, and prepares it for download.
  Future<void> selectSearchResult(TrackMetadata selected) async {
    if (isBusy) return;

    await stopPreviewAudio();
    _errorMessage = null;
    _savedFilePath = null;
    _trackMetadata = selected;
    _youtubeCandidates = const [];
    _selectedYoutubeCandidate = null;
    _lyricsCandidates = const [];
    _selectedLyricsCandidate = null;
    _preferSyncedLyrics = true;

    _setState(
      DownloaderState.fetchingLyrics,
      progress: 0.70,
      message: 'Mengambil lirik...',
    );

    try {
      final lyricsResponse = await _lyricsService.fetchLyricsWithCandidates(
        trackName: selected.title,
        artistName: selected.artist,
        albumName: selected.album,
        durationSeconds: selected.durationSeconds,
        targetFolder: _selectedFolder,
      );
      _lyricsCandidates = lyricsResponse.candidates;
      _selectedLyricsCandidate = lyricsResponse.selectedCandidate;

      final enriched = selected.copyWith(
        syncedLyrics: lyricsResponse.bestResult.syncedLyrics,
        plainLyrics: lyricsResponse.bestResult.plainLyrics,
      );
      _trackMetadata = enriched;
      _preferSyncedLyrics = enriched.hasSyncedLyrics;
      await _checkDuplicatesForTracks([enriched]);

      _setState(
        DownloaderState.readyToDownload,
        progress: 1.0,
        message: 'Siap disimpan ke $_selectedFolder',
      );
    } catch (e, s) {
      _handleError(e, s);
    }
  }

  /// Returns to the search results list without re-fetching from the network.
  void backToSearchResults() {
    if (_searchResults.isEmpty || isBusy) return;
    stopPreviewAudio();
    _trackMetadata = null;
    _lyricsCandidates = const [];
    _selectedLyricsCandidate = null;
    _errorMessage = null;
    _savedFilePath = null;
    _setState(
      DownloaderState.showingSearchResults,
      progress: 1.0,
      message: '${_searchResults.length} lagu ditemukan',
    );
  }

  /// Updates the currently previewed track's metadata and/or lyrics before downloading.
  Future<void> updatePreviewMetadata({
    required String title,
    required String artist,
    required String album,
    required String releaseYear,
    required String plainLyrics,
    String? syncedLyrics,
  }) async {
    final current = _trackMetadata;
    if (current == null) return;

    final trimmedLyrics = plainLyrics.trim();
    final hasLrcTimestamps =
        RegExp(r'\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]').hasMatch(trimmedLyrics);

    String? resolvedSyncedLyrics;
    String? resolvedPlainLyrics;
    bool shouldClearSynced = false;

    if (syncedLyrics != null && syncedLyrics.trim().isNotEmpty) {
      resolvedSyncedLyrics = syncedLyrics.trim();
      resolvedPlainLyrics = hasLrcTimestamps
          ? RomajiService.stripTimestamps(resolvedSyncedLyrics)
          : (trimmedLyrics.isNotEmpty
              ? trimmedLyrics
              : RomajiService.stripTimestamps(resolvedSyncedLyrics));
    } else if (hasLrcTimestamps) {
      resolvedSyncedLyrics = trimmedLyrics;
      resolvedPlainLyrics = RomajiService.stripTimestamps(trimmedLyrics);
    } else {
      resolvedSyncedLyrics = current.syncedLyrics;
      resolvedPlainLyrics = trimmedLyrics;
      shouldClearSynced = !_preferSyncedLyrics;
    }

    final updated = current.copyWith(
      title: title.trim().isNotEmpty ? title.trim() : current.title,
      artist: artist.trim().isNotEmpty ? artist.trim() : current.artist,
      album: album.trim().isNotEmpty ? album.trim() : current.album,
      releaseYear: releaseYear.trim().isNotEmpty
          ? releaseYear.trim()
          : current.releaseYear,
      syncedLyrics: resolvedSyncedLyrics,
      plainLyrics: resolvedPlainLyrics,
      clearSyncedLyrics: shouldClearSynced,
    );

    _trackMetadata = updated;
    if (hasLrcTimestamps ||
        (syncedLyrics != null && syncedLyrics.trim().isNotEmpty)) {
      _preferSyncedLyrics = true;
    }
    await _checkDuplicatesForTracks([updated]);
    notifyListeners();
  }

  /// Checks a Spotify track URL: extracts Spotify public metadata, enriches via
  /// Deezer Public API, and fetches lyrics & candidates from LRCLIB for the preview card.
  Future<void> checkTrack(String spotifyUrl) async {
    if (isBusy) return;

    await stopPreviewAudio();
    _errorMessage = null;
    _savedFilePath = null;
    _trackMetadata = null;
    _currentCollection = null;
    _youtubeCandidates = const [];
    _selectedYoutubeCandidate = null;
    _lyricsCandidates = const [];
    _selectedLyricsCandidate = null;
    _preferSyncedLyrics = true;

    _setState(
      DownloaderState.fetchingMetadata,
      progress: 0.2,
      message: 'Memuat info...',
    );

    try {
      final baseMetadata =
          await _metadataService.fetchTrackMetadata(spotifyUrl);
      _trackMetadata = baseMetadata;

      _setState(
        DownloaderState.fetchingLyrics,
        progress: 0.75,
        message: 'Mengambil lirik...',
      );

      final lyricsResponse = await _lyricsService.fetchLyricsWithCandidates(
        trackName: baseMetadata.title,
        artistName: baseMetadata.artist,
        albumName: baseMetadata.album,
        durationSeconds: baseMetadata.durationSeconds,
        targetFolder: _selectedFolder,
      );
      _lyricsCandidates = lyricsResponse.candidates;
      _selectedLyricsCandidate = lyricsResponse.selectedCandidate;

      final enrichedMetadata = baseMetadata.copyWith(
        syncedLyrics: lyricsResponse.bestResult.syncedLyrics,
        plainLyrics: lyricsResponse.bestResult.plainLyrics,
      );
      _trackMetadata = enrichedMetadata;
      _preferSyncedLyrics = enrichedMetadata.hasSyncedLyrics;
      await _checkDuplicatesForTracks([enrichedMetadata]);

      _setState(
        DownloaderState.readyToDownload,
        progress: 1.0,
        message: 'Siap disimpan ke $_selectedFolder',
      );
    } catch (e, s) {
      _handleError(e, s);
    }
  }

  // ===========================================================================
  // FEATURE 4: SPOTIFY ALBUM & PLAYLIST COLLECTION EXTRACTOR & BATCH QUEUE
  // ===========================================================================
  Future<void> checkCollection(String collectionUrl) async {
    if (isBusy) return;

    await stopPreviewAudio();
    _errorMessage = null;
    _savedFilePath = null;
    _trackMetadata = null;
    _currentCollection = null;

    _setState(
      DownloaderState.fetchingMetadata,
      progress: 0.35,
      message: 'Memuat info...',
    );

    try {
      final collection =
          await _metadataService.fetchAlbumOrPlaylist(collectionUrl);
      await _checkDuplicatesForTracks(collection.tracks);
      _currentCollection = collection;

      _setState(
        DownloaderState.readyToDownload,
        progress: 1.0,
        message: '${collection.tracks.length} lagu dimuat',
      );
    } catch (e, s) {
      _handleError(e, s);
    }
  }

  Future<void> enqueueBatchTracks(
    List<TrackMetadata> tracks, {
    String? folderName,
  }) async {
    if (tracks.isEmpty) return;
    final targetFolder = (folderName ?? _selectedFolder).trim();

    for (final track in tracks.reversed) {
      final item = DownloadItem(
        id: 'q_${DateTime.now().microsecondsSinceEpoch}_${track.title.hashCode}',
        metadata: track,
        targetFolderName: targetFolder,
        status: DownloadItemStatus.queued,
        progress: 0.0,
        statusDetail: 'Dalam antrean',
        createdAt: DateTime.now(),
        preferSyncedLyrics: true,
      );
      _queueItems.insert(0, item);
    }
    notifyListeners();

    if (!_isProcessingQueue) {
      await _processQueue();
    }
  }

  /// Executes the full download pipeline for the currently previewed track
  /// into `_selectedFolder`.
  Future<void> downloadTrack() async {
    final currentMeta = _trackMetadata;
    if (currentMeta == null || isBusy) return;

    await stopPreviewAudio();
    _errorMessage = null;
    _savedFilePath = null;
    final targetFolder = _selectedFolder;
    final useSynced = _preferSyncedLyrics;

    try {
      _setState(
        DownloaderState.fetchingLyrics,
        progress: 0.08,
        message: 'Mengambil lirik...',
      );

      TrackMetadata workingMeta = currentMeta;
      if (!workingMeta.hasAnyLyrics) {
        workingMeta = await _lyricsService.enrichWithLyrics(
          workingMeta,
          targetFolder: targetFolder,
        );
        _trackMetadata = workingMeta;
      }

      _setState(
        DownloaderState.downloadingAudio,
        progress: 0.20,
        message: 'Mengunduh lagu...',
      );

      final rawAudioFile = await _audioService.downloadBestAudioStream(
        workingMeta,
        onProgress: (subProgress, _) {
          final overall = 0.20 + (subProgress.clamp(0.0, 1.0) * 0.60);
          _setState(
            DownloaderState.downloadingAudio,
            progress: overall,
            message: 'Mengunduh lagu...',
          );
        },
      );

      _setState(
        DownloaderState.taggingAudio,
        progress: 0.80,
        message: 'Menyimpan...',
      );

      final outputPath = await _taggingService.convertAndTagAudio(
        rawAudioFile: rawAudioFile,
        metadata: workingMeta,
        targetFolderName: targetFolder,
        preferSyncedLyrics: useSynced,
        onProgress: (subProgress, _) {
          final overall = 0.80 + (subProgress.clamp(0.0, 1.0) * 0.19);
          _setState(
            DownloaderState.taggingAudio,
            progress: overall,
            message: 'Menyimpan...',
          );
        },
      );

      _savedFilePath = outputPath;
      _duplicateFolderMap[workingMeta.sanitizedFileName.toLowerCase()] =
          targetFolder;
      await refreshFolders();

      // Record in history list
      final historyItem = DownloadItem(
        id: 'dl_${DateTime.now().millisecondsSinceEpoch}',
        metadata: workingMeta,
        targetFolderName: targetFolder,
        status: DownloadItemStatus.completed,
        progress: 1.0,
        statusDetail: 'Selesai',
        savedFilePath: outputPath,
        createdAt: DateTime.now(),
        preferSyncedLyrics: useSynced,
      );
      _queueItems.insert(0, historyItem);

      _setState(
        DownloaderState.completed,
        progress: 1.0,
        message: 'Selesai',
      );
      debugPrint(
        '[AUTO_E2E] COMPLETED: status=completed (100%), file=$outputPath',
      );
    } catch (e, s) {
      _handleError(e, s);
    }
  }

  /// Adds a track (e.g. from search results) to the background download queue
  /// and processes queued tracks sequentially.
  Future<void> enqueueTrack(
    TrackMetadata track, {
    String? folderName,
    bool? preferSynced,
  }) async {
    await stopPreviewAudio();
    final targetFolder = (folderName ?? _selectedFolder).trim();
    final item = DownloadItem(
      id: 'q_${DateTime.now().microsecondsSinceEpoch}',
      metadata: track,
      targetFolderName: targetFolder,
      status: DownloadItemStatus.queued,
      progress: 0.0,
      statusDetail: 'Dalam antrean',
      createdAt: DateTime.now(),
      preferSyncedLyrics: preferSynced ?? _preferSyncedLyrics,
    );

    _queueItems.insert(0, item);
    notifyListeners();

    if (!_isProcessingQueue) {
      await _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (true) {
        final nextIndex = _queueItems.lastIndexWhere(
          (item) => item.status == DownloadItemStatus.queued,
        );
        if (nextIndex == -1) break;

        final currentItem = _queueItems[nextIndex];
        _updateQueueItem(
          currentItem.id,
          status: DownloadItemStatus.downloading,
          progress: 0.08,
          detail: 'Mengambil lirik...',
        );

        try {
          var meta = currentItem.metadata;
          if (!meta.hasAnyLyrics) {
            meta = await _lyricsService.enrichWithLyrics(
              meta,
              targetFolder: currentItem.targetFolderName,
            );
          }

          final rawFile = await _audioService.downloadBestAudioStream(
            meta,
            onProgress: (sub, _) {
              _updateQueueItem(
                currentItem.id,
                status: DownloadItemStatus.downloading,
                progress: 0.12 + (sub.clamp(0.0, 1.0) * 0.62),
                detail: 'Mengunduh lagu...',
              );
            },
          );

          _updateQueueItem(
            currentItem.id,
            status: DownloadItemStatus.tagging,
            progress: 0.78,
            detail: 'Menyimpan...',
          );

          final savedPath = await _taggingService.convertAndTagAudio(
            rawAudioFile: rawFile,
            metadata: meta,
            targetFolderName: currentItem.targetFolderName,
            preferSyncedLyrics: currentItem.preferSyncedLyrics,
            onProgress: (sub, _) {
              _updateQueueItem(
                currentItem.id,
                status: DownloadItemStatus.tagging,
                progress: 0.78 + (sub.clamp(0.0, 1.0) * 0.21),
                detail: 'Menyimpan...',
              );
            },
          );

          _duplicateFolderMap[meta.sanitizedFileName.toLowerCase()] =
              currentItem.targetFolderName;
          await refreshFolders();

          _updateQueueItem(
            currentItem.id,
            metadata: meta,
            status: DownloadItemStatus.completed,
            progress: 1.0,
            detail: 'Selesai',
            savedFilePath: savedPath,
          );
        } catch (e) {
          _updateQueueItem(
            currentItem.id,
            status: DownloadItemStatus.failed,
            progress: 0.0,
            detail: 'Gagal',
            errorMessage: e.toString(),
          );
        }
      }
    } finally {
      _isProcessingQueue = false;
      notifyListeners();
    }
  }

  void _updateQueueItem(
    String id, {
    TrackMetadata? metadata,
    String? targetFolderName,
    DownloadItemStatus? status,
    double? progress,
    String? detail,
    String? savedFilePath,
    String? errorMessage,
    bool? preferSyncedLyrics,
  }) {
    final idx = _queueItems.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    _queueItems[idx] = _queueItems[idx].copyWith(
      metadata: metadata,
      targetFolderName: targetFolderName,
      status: status,
      progress: progress,
      statusDetail: detail,
      savedFilePath: savedFilePath,
      errorMessage: errorMessage,
      preferSyncedLyrics: preferSyncedLyrics,
    );
    notifyListeners();
  }

  // ===========================================================================
  // FEATURE 5: INSTANT RE-TAG EXISTING LOCAL MP3 WITHOUT RE-DOWNLOADING
  // ===========================================================================
  Future<String> retagCompletedItem({
    required String itemId,
    required String title,
    required String artist,
    required String album,
    required String releaseYear,
    required String lyricsText,
    required bool preferSyncedLyrics,
    String? syncedLyrics,
  }) async {
    final idx = _queueItems.indexWhere((e) => e.id == itemId);
    if (idx == -1) {
      throw Exception('Item riwayat unduhan tidak ditemukan.');
    }
    final item = _queueItems[idx];
    final currentPath = item.savedFilePath;
    if (currentPath == null || currentPath.isEmpty) {
      throw Exception('Path file MP3 lokal tidak tersedia.');
    }

    final oldKey = item.metadata.sanitizedFileName.toLowerCase();
    final trimmedLyrics = lyricsText.trim();
    final hasLrcTimestamps =
        RegExp(r'\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]').hasMatch(trimmedLyrics);

    String? resolvedSyncedLyrics;
    String? resolvedPlainLyrics;
    bool shouldClearSynced = false;

    if (syncedLyrics != null && syncedLyrics.trim().isNotEmpty) {
      resolvedSyncedLyrics = syncedLyrics.trim();
      resolvedPlainLyrics = hasLrcTimestamps
          ? RomajiService.stripTimestamps(resolvedSyncedLyrics)
          : (trimmedLyrics.isNotEmpty
              ? trimmedLyrics
              : RomajiService.stripTimestamps(resolvedSyncedLyrics));
    } else if (hasLrcTimestamps) {
      resolvedSyncedLyrics = trimmedLyrics;
      resolvedPlainLyrics = RomajiService.stripTimestamps(trimmedLyrics);
    } else {
      resolvedSyncedLyrics = item.metadata.syncedLyrics;
      resolvedPlainLyrics = trimmedLyrics;
      shouldClearSynced = !preferSyncedLyrics;
    }

    final updatedMeta = item.metadata.copyWith(
      title: title.trim().isNotEmpty ? title.trim() : item.metadata.title,
      artist: artist.trim().isNotEmpty ? artist.trim() : item.metadata.artist,
      album: album.trim().isNotEmpty ? album.trim() : item.metadata.album,
      releaseYear: releaseYear.trim().isNotEmpty
          ? releaseYear.trim()
          : item.metadata.releaseYear,
      syncedLyrics: resolvedSyncedLyrics,
      plainLyrics: resolvedPlainLyrics,
      clearSyncedLyrics: shouldClearSynced,
    );

    final effectivePreferSynced = (hasLrcTimestamps ||
            (syncedLyrics != null && syncedLyrics.trim().isNotEmpty))
        ? true
        : preferSyncedLyrics;

    final newPath = await _taggingService.retagExistingMp3(
      filePath: currentPath,
      updatedMetadata: updatedMeta,
      preferSyncedLyrics: effectivePreferSynced,
    );

    _duplicateFolderMap.remove(oldKey);
    _duplicateFolderMap[updatedMeta.sanitizedFileName.toLowerCase()] =
        item.targetFolderName;
    await refreshFolders();

    _queueItems[idx] = item.copyWith(
      metadata: updatedMeta,
      savedFilePath: newPath,
      preferSyncedLyrics: effectivePreferSynced,
      statusDetail: 'Selesai',
    );

    notifyListeners();
    return newPath;
  }

  /// Moves a completed download item (or the currently saved file) to [newFolderName]
  /// and notifies Android MediaScanner so Musicolet updates immediately.
  Future<String> moveItemToFolder({
    required String itemId,
    required String newFolderName,
  }) async {
    final idx = _queueItems.indexWhere((e) => e.id == itemId);
    if (idx == -1) {
      throw Exception('Item unduhan tidak ditemukan.');
    }
    final item = _queueItems[idx];
    final currentPath = item.savedFilePath;
    if (currentPath == null || currentPath.isEmpty) {
      throw Exception('File tidak tersedia.');
    }

    final movedPath = await _folderService.moveDownloadedFile(
      currentFilePath: currentPath,
      targetFolderName: newFolderName,
    );

    _duplicateFolderMap[item.metadata.sanitizedFileName.toLowerCase()] =
        newFolderName;
    await refreshFolders();

    _queueItems[idx] = item.copyWith(
      targetFolderName: newFolderName,
      savedFilePath: movedPath,
      statusDetail: 'Selesai',
    );

    if (_savedFilePath == currentPath) {
      _savedFilePath = movedPath;
      _statusMessage = 'Selesai';
    }

    notifyListeners();
    return movedPath;
  }

  void clearCompletedQueueItems() {
    _queueItems.removeWhere(
      (e) =>
          e.status == DownloadItemStatus.completed ||
          e.status == DownloadItemStatus.failed,
    );
    notifyListeners();
  }

  Future<void> _checkDuplicatesForTracks(List<TrackMetadata> tracks) async {
    try {
      final folders = await _folderService.listAvailableFolders();
      _availableFolders = folders;
      for (final t in tracks) {
        final foundFolder = await _folderService.findDuplicateFolder(
          t.sanitizedFileName,
          folders,
        );
        final key = t.sanitizedFileName.toLowerCase();
        if (foundFolder != null) {
          _duplicateFolderMap[key] = foundFolder;
        } else {
          _duplicateFolderMap.remove(key);
        }
      }
    } catch (_) {}
  }

  void _setState(
    DownloaderState newState, {
    required double progress,
    required String message,
  }) {
    _state = newState;
    _progress = progress.clamp(0.0, 1.0);
    _statusMessage = message;
    final pct = (_progress * 100).round();
    debugPrint('[AUTO_E2E] STATE=${newState.name} ($pct%): $message');
    notifyListeners();
  }

  void _handleError(Object error, StackTrace stackTrace) {
    final cleanMsg = error
        .toString()
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .trim();
    _state = DownloaderState.error;
    _errorMessage = cleanMsg.isNotEmpty
        ? cleanMsg
        : 'Terjadi kesalahan yang tidak diketahui.';
    _statusMessage = _errorMessage!;
    debugPrint('[AUTO_E2E] ERROR: $_errorMessage\n$stackTrace');
    notifyListeners();
  }
}

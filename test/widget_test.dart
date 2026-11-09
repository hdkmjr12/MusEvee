import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spotmeta_downloader/main.dart';
import 'package:spotmeta_downloader/models/local_song.dart';
import 'package:spotmeta_downloader/providers/downloader_provider.dart';
import 'package:spotmeta_downloader/providers/local_music_provider.dart';
import 'package:spotmeta_downloader/services/metadata_service.dart';
import 'package:spotmeta_downloader/utils/app_strings.dart';
import 'package:spotmeta_downloader/widgets/local_library_views.dart';

LocalSong _mockSong(
  int id, {
  String? lyrics,
  String folderName = 'Music Japan',
  String? customPath,
}) {
  final folderPath = '/storage/emulated/0/Music/$folderName';
  return LocalSong(
    filePath: customPath ?? '$folderPath/Song_$id.mp3',
    fileName: 'Song_$id.mp3',
    folderName: folderName,
    title: 'Song $id',
    artist: 'Artist $id',
    album: 'Album $id',
    year: '2026',
    durationMs: 180000,
    sizeBytes: 4096000,
    bitrateKbps: 320,
    sampleRateHz: 44100,
    usltLyrics: lyrics,
    lastModifiedMs: 1700000000000 + id,
  );
}

void main() {
  setUp(() {
    AppStrings.debugLanguageCodeOverride = 'id';
  });

  tearDown(() {
    AppStrings.debugLanguageCodeOverride = null;
  });

  testWidgets(
      'MusEveeApp renders 6-tab Musicolet UI, switches to Downloader tab with 3 Horizontal Carousels, and opens Queue/History Modal Sheet',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MusEveeApp());
    await tester.pump();

    // Default tab is Musicolet Now Playing (Tab 1)
    expect(find.text('MusEvee Player'), findsOneWidget);
    expect(find.text('Cari & Unduh Lagu'), findsOneWidget);

    // Switch to Downloader tab (Tab 4: Cloud Download icon in MusicoletBottomStrip)
    await tester.tap(find.byIcon(Icons.cloud_download_outlined).last);
    await tester.pumpAndSettle();

    expect(find.text('Cari lagu atau tempel link...'), findsOneWidget);
    expect(find.text('Judul / Artis (Romaji J-Pop)'), findsOneWidget);
    expect(find.text('Link YouTube / YT Music'), findsOneWidget);
    expect(
      find.text('Link Spotify (Track, Album & Playlist)'),
      findsOneWidget,
    );
    expect(
      find.text(
        'MusEvee All-in-One Downloader (MP3 320kbps + USLT Lyrics)',
      ),
      findsOneWidget,
    );

    // Verify the 3 Horizontal Carousels are rendered in the Downloader tab
    expect(find.byKey(const ValueKey('carousel_for_you')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('carousel_global_trending')),
      findsOneWidget,
    );
    expect(find.text('Untukmu'), findsOneWidget);
    expect(find.text('Global Trending'), findsOneWidget);
    expect(find.text('Idol'), findsOneWidget);

    // Scroll down slightly in the Downloader ListView to reveal the 3rd carousel (Indonesia Trending)
    await tester.drag(find.byType(ListView).first, const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('carousel_indonesia_trending')),
      findsOneWidget,
    );
    expect(find.text('Indonesia Trending'), findsOneWidget);

    // Tap the compact Queue & History button next to the Downloader Omnibox
    await tester.tap(find.byTooltip('Antrean & Riwayat Unduhan'));
    await tester.pumpAndSettle();

    expect(find.text('Antrean & Riwayat Unduhan'), findsOneWidget);

    // Close modal sheet and switch to Tab 5: Settings (`Pengaturan`)
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Pengaturan'), findsOneWidget);
    await tester.tap(find.byTooltip('Pengaturan'));
    await tester.pumpAndSettle();

    expect(find.text('Terbaik — 320 kbps'), findsOneWidget);
    expect(find.text('Seimbang — 192 kbps'), findsOneWidget);
    expect(find.text('Hemat — 128 kbps'), findsOneWidget);
    expect(find.text('MusEvee v4.7'), findsOneWidget);
  });

  test(
      'Rotated Queue places selected song at #1 (index 0) and appends preceding songs at the bottom',
      () async {
    final provider = LocalMusicProvider();
    addTearDown(provider.dispose);

    final songs = List.generate(5, (i) => _mockSong(i + 1));
    await provider.playSong(songs[2], queueContext: songs); // Song 3

    expect(provider.currentIndex, 0);
    expect(provider.currentSong?.title, 'Song 3');
    expect(
      provider.queue.map((s) => s.title).toList(),
      ['Song 3', 'Song 4', 'Song 5', 'Song 1', 'Song 2'],
    );
  });

  test(
      'True Queue-Order Shuffle advances linearly along visual queue and restores rotated order',
      () async {
    final provider = LocalMusicProvider();
    addTearDown(provider.dispose);

    final songs = List.generate(8, (i) => _mockSong(i + 1));
    await provider.playSong(songs[2], queueContext: songs);

    const expectedRotatedOrder = <String>[
      'Song 3',
      'Song 4',
      'Song 5',
      'Song 6',
      'Song 7',
      'Song 8',
      'Song 1',
      'Song 2',
    ];

    expect(provider.currentIndex, 0);
    expect(provider.currentSong?.title, 'Song 3');
    expect(
      provider.queueEntries.map((e) => e.song.title).toList(),
      expectedRotatedOrder,
    );

    // Enable shuffle: active song stays at index 0, rest is shuffled physically
    provider.toggleShuffle();
    expect(provider.isShuffle, isTrue);
    expect(provider.currentIndex, 0);
    expect(provider.currentSong?.title, 'Song 3');

    final shuffledOrder = provider.queueEntries.map((e) => e.song.title).toList();
    expect(shuffledOrder.length, 8);

    // Next & Previous MUST strictly follow the visual queue order even when Shuffle is ON!
    await provider.playNext();
    expect(provider.currentIndex, 1);
    expect(provider.currentSong?.title, shuffledOrder[1]);

    await provider.playNext();
    expect(provider.currentIndex, 2);
    expect(provider.currentSong?.title, shuffledOrder[2]);

    await provider.playPrevious();
    expect(provider.currentIndex, 1);
    expect(provider.currentSong?.title, shuffledOrder[1]);

    // Turning Shuffle OFF restores exact rotated queue order while keeping current active song
    final activeBeforeRestore = provider.currentSong!.title;
    provider.toggleShuffle();
    expect(provider.isShuffle, isFalse);
    expect(
      provider.queueEntries.map((e) => e.song.title).toList(),
      expectedRotatedOrder,
    );
    expect(provider.currentSong?.title, activeBeforeRestore);
  });

  test(
      '200ms handleNativePosition updates progressNotifier without triggering global notifyListeners',
      () async {
    final provider = LocalMusicProvider();
    addTearDown(provider.dispose);

    final song = _mockSong(
      1,
      lyrics: '[00:01.00] First line\n[00:05.00] Second line',
    );
    await provider.playSong(song, queueContext: [song]);

    int globalRebuilds = 0;
    provider.addListener(() => globalRebuilds++);

    provider.handleNativePosition(
      positionMs: 1200,
      durationMs: 180000,
      isPlaying: true,
    );
    expect(provider.progressNotifier.value.positionMs, 1200);
    expect(provider.activeLyricIndexNotifier.value, 0);
    expect(globalRebuilds, 0);

    provider.handleNativePosition(
      positionMs: 5200,
      durationMs: 180000,
      isPlaying: true,
    );
    expect(provider.progressNotifier.value.positionMs, 5200);
    expect(provider.activeLyricIndexNotifier.value, 1);
    expect(globalRebuilds, 0);
  });

  test(
      'Multi-Folder & Multi-Playlist Queue Merger merges songs with filePath deduplication and append support',
      () async {
    final provider = LocalMusicProvider()
      ..debugEnableNativeChannelInTests = true;
    addTearDown(provider.dispose);

    final barat1 = _mockSong(1, folderName: 'Music Barat');
    final barat2 = _mockSong(2, folderName: 'Music Barat');
    final random1 = _mockSong(3, folderName: 'Music Random');
    final random2 = _mockSong(4, folderName: 'Music Random');
    final japan1 = _mockSong(5, folderName: 'Music Japan');

    provider.seedSongsForTesting([barat1, barat2, random1, random2, japan1]);

    // Merge Music Barat + Music Random (excluding Music Japan)
    final mergedCount = await provider.playCombinedFolders([
      '/storage/emulated/0/Music/Music Barat',
      '/storage/emulated/0/Music/Music Random',
      '/storage/emulated/0/Music/Music Barat', // duplicate folder input
    ]);

    expect(mergedCount, 4);
    expect(provider.queueEntries.length, 4);
    expect(
      provider.queueEntries.any((e) => e.song.folderName == 'Music Japan'),
      isFalse,
    );

    // Append Music Japan + Music Barat to active queue -> only japan1 should be newly added!
    final appendedCount = await provider.playCombinedFolders(
      [
        '/storage/emulated/0/Music/Music Barat',
        '/storage/emulated/0/Music/Music Japan',
      ],
      appendToCurrentQueue: true,
    );
    expect(appendedCount, 1);
    expect(provider.queueEntries.length, 5);
  });

  test(
      'LocalMusicProvider enforces full 1.0 volume and Hi-Fi Android AudioAttributes on initialization and every track load',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('com.spotmeta.downloader/system');
    final recordedCalls = <MethodCall>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      recordedCalls.add(call);
      if (call.method == 'localPlayFile' ||
          call.method == 'setVolume' ||
          call.method == 'setPreAmpGainDb' ||
          call.method == 'localStop') {
        return true;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final provider = LocalMusicProvider()
      ..debugEnableNativeChannelInTests = true;
    addTearDown(provider.dispose);

    // Default volume MUST be 1.0 (100% unattenuated) with 0.0 dB pre-amp and Hi-Fi attributes
    expect(provider.volume, 1.0);
    expect(provider.preAmpGainDb, 0.0);
    expect(provider.audioContentType, 'music');
    expect(provider.audioUsage, 'media');

    // Simulate temporary volume reduction, then load/play a new song:
    // _startCurrentQueueTrack MUST explicitly restore volume to 1.0!
    await provider.setVolume(0.4);
    expect(provider.volume, 0.4);
    recordedCalls.clear();

    final song = _mockSong(1, folderName: 'Music Japan');
    await provider.playSong(song, queueContext: [song]);

    expect(provider.volume, 1.0);
    expect(
      recordedCalls.any(
        (c) =>
            c.method == 'setVolume' &&
            (c.arguments as Map)['volume'] == 1.0,
      ),
      isTrue,
    );
    final playCall = recordedCalls.firstWhere(
      (c) => c.method == 'localPlayFile',
    );
    final playArgs = playCall.arguments as Map;
    expect(playArgs['path'], song.filePath);
    expect(playArgs['volume'], 1.0);
    expect(playArgs['contentType'], 'music');
    expect(playArgs['usage'], 'media');
  });

  test(
      'applyFolderVisibilityChanges synchronizes Queue and reloads or stops AudioPlayer when active folder is hidden',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('com.spotmeta.downloader/system');
    final recordedCalls = <MethodCall>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      recordedCalls.add(call);
      if (call.method == 'localPlayFile' ||
          call.method == 'setVolume' ||
          call.method == 'localStop') {
        return true;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final provider = LocalMusicProvider()
      ..debugEnableNativeChannelInTests = true;
    addTearDown(provider.dispose);

    final barat1 = _mockSong(1, folderName: 'Music Barat');
    final japan1 = _mockSong(2, folderName: 'Music Japan');
    final podcast1 = _mockSong(3, folderName: 'Podcasts');

    provider.seedSongsForTesting([barat1, japan1, podcast1]);
    await provider.playSong(
      barat1,
      queueContext: [barat1, japan1, podcast1],
    );

    expect(provider.currentSong?.filePath, barat1.filePath);
    expect(provider.isPlaying, isTrue);
    recordedCalls.clear();

    // 1. Hide 'Music Barat' while barat1 is playing -> must stop barat1 and immediately play japan1!
    await provider.applyFolderVisibilityChanges(
      folderVisibilityByPath: {
        '/storage/emulated/0/Music/Music Barat': false,
      },
    );

    expect(provider.currentSong?.filePath, japan1.filePath);
    expect(provider.currentIndex, 0);
    expect(provider.isPlaying, isTrue);
    expect(provider.queue.map((s) => s.filePath).toList(), [
      japan1.filePath,
      podcast1.filePath,
    ]);
    expect(recordedCalls.any((c) => c.method == 'localStop'), isTrue);
    final reloadPlayCall = recordedCalls.lastWhere(
      (c) => c.method == 'localPlayFile',
    );
    expect((reloadPlayCall.arguments as Map)['path'], japan1.filePath);

    // 2. Enable 'onlyMusicFolders' filter -> 'Podcasts' is hidden while 'Music Japan' keeps playing
    recordedCalls.clear();
    await provider.applyFolderVisibilityChanges(onlyMusicFolders: true);
    expect(provider.onlyMusicFolders, isTrue);
    expect(provider.queue.map((s) => s.filePath).toList(), [japan1.filePath]);
    expect(provider.currentSong?.filePath, japan1.filePath);
    expect(provider.isPlaying, isTrue);
    expect(recordedCalls.any((c) => c.method == 'localStop'), isFalse);

    // 3. Hide 'Music Japan' as well -> Queue becomes empty, audio stops completely, currentSong = null
    recordedCalls.clear();
    await provider.applyFolderVisibilityChanges(
      folderVisibilityByPath: {
        '/storage/emulated/0/Music/Music Japan': false,
      },
    );
    expect(provider.queue, isEmpty);
    expect(provider.currentIndex, -1);
    expect(provider.currentSong, isNull);
    expect(provider.isPlaying, isFalse);
    expect(recordedCalls.any((c) => c.method == 'localStop'), isTrue);
  });

  testWidgets(
      'Kelola Folder modal buffers toggles in draft state and only applies when Terapkan button is tapped',
      (WidgetTester tester) async {
    final localProvider = LocalMusicProvider();
    final downloaderProvider = DownloaderProvider();
    addTearDown(localProvider.dispose);
    addTearDown(downloaderProvider.dispose);

    final barat1 = _mockSong(1, folderName: 'Music Barat');
    final japan1 = _mockSong(2, folderName: 'Music Japan');
    localProvider.seedSongsForTesting([barat1, japan1]);
    await localProvider.playSong(barat1, queueContext: [barat1, japan1]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalMusicProvider>.value(
            value: localProvider,
          ),
          ChangeNotifierProvider<DownloaderProvider>.value(
            value: downloaderProvider,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LocalFoldersView(
              onOpenNowPlaying: () {},
              onCreateNewFolder: (_) async {},
              onMoveLocalSongFolder: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open Kelola Folder sheet
    await tester.tap(find.text('Kelola Folder'));
    await tester.pumpAndSettle();

    expect(find.text('Kelola / Sembunyikan Folder'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('manage_folders_apply_button')),
      findsOneWidget,
    );

    // Toggle 'Music Barat' OFF in draft -> should NOT hide folder or stop barat1 yet!
    await tester.tap(
      find.byKey(const ValueKey('folder_visibility_switch_Music Barat')),
    );
    await tester.pumpAndSettle();

    expect(
      localProvider.isFolderHidden('/storage/emulated/0/Music/Music Barat'),
      isFalse,
    );
    expect(localProvider.currentSong?.filePath, barat1.filePath);
    expect(find.text('Terapkan (1)'), findsOneWidget);

    // Now tap 'Terapkan (1)' -> applies batch changes & switches active song to japan1!
    await tester.tap(
      find.byKey(const ValueKey('manage_folders_apply_button')),
    );
    await tester.pumpAndSettle();

    expect(
      localProvider.isFolderHidden('/storage/emulated/0/Music/Music Barat'),
      isTrue,
    );
    expect(localProvider.currentSong?.filePath, japan1.filePath);
  });

  testWidgets(
      'LocalPlaylistsView renders 6 Musicolet Smart Playlists, Your playlists header, and + New Playlist button',
      (WidgetTester tester) async {
    final localProvider = LocalMusicProvider();
    final downloaderProvider = DownloaderProvider();
    addTearDown(localProvider.dispose);
    addTearDown(downloaderProvider.dispose);

    final song1 = _mockSong(1, folderName: 'Music Barat');
    final song2 = _mockSong(2, folderName: 'Music Japan');
    final song3 = _mockSong(3, folderName: 'Music Random');
    localProvider.seedSongsForTesting([song1, song2, song3]);
    await localProvider.toggleFavorite(song2.filePath);

    // Simulate playing song1 twice and song3 once (song2 remains Not played)
    localProvider.recordPlayForTesting(song1.filePath, playedAtMs: 1000);
    localProvider.recordPlayForTesting(song1.filePath, playedAtMs: 2000);
    localProvider.recordPlayForTesting(song3.filePath, playedAtMs: 3000);

    expect(
      localProvider
          .songsForSmartPlaylist(SmartPlaylistId.allSongs)
          .map((s) => s.title)
          .toList(),
      ['Song 1', 'Song 2', 'Song 3'],
    );
    expect(
      localProvider
          .songsForSmartPlaylist(SmartPlaylistId.favorites)
          .map((s) => s.title)
          .toList(),
      ['Song 2'],
    );
    expect(
      localProvider
          .songsForSmartPlaylist(SmartPlaylistId.recentlyAdded)
          .map((s) => s.title)
          .toList(),
      ['Song 3', 'Song 2', 'Song 1'],
    );
    expect(
      localProvider
          .songsForSmartPlaylist(SmartPlaylistId.recentlyPlayed)
          .map((s) => s.title)
          .toList(),
      ['Song 3', 'Song 1'],
    );
    expect(
      localProvider
          .songsForSmartPlaylist(SmartPlaylistId.mostPlayed)
          .map((s) => s.title)
          .toList(),
      ['Song 1', 'Song 3'],
    );
    expect(
      localProvider
          .songsForSmartPlaylist(SmartPlaylistId.notPlayed)
          .map((s) => s.title)
          .toList(),
      ['Song 2'],
    );

    AppStrings.debugLanguageCodeOverride = 'en';

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalMusicProvider>.value(
            value: localProvider,
          ),
          ChangeNotifierProvider<DownloaderProvider>.value(
            value: downloaderProvider,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LocalPlaylistsView(
              onOpenNowPlaying: () {},
              onMoveLocalSongFolder: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All songs'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Recently added'), findsOneWidget);
    expect(find.text('Recently played'), findsOneWidget);
    expect(find.text('Most played'), findsOneWidget);
    expect(find.text('Not played'), findsOneWidget);
    expect(find.text('Your playlists'), findsOneWidget);
    expect(find.text('New Playlist'), findsOneWidget);

    // Restrict Multi-Select / Mix Playlist ONLY to Your playlists:
    // playCombinedPlaylists must ignore SmartPlaylistId entries and only merge user playlists!
    final userPl1 = await localProvider.createPlaylist('J-Pop Mix');
    final userPl2 = await localProvider.createPlaylist('Workout Mix');
    await localProvider.addSongToPlaylist(userPl1.id, song1.filePath);
    await localProvider.addSongToPlaylist(userPl2.id, song2.filePath);

    final smartOnlyCount = await localProvider.playCombinedPlaylists([
      SmartPlaylistId.allSongs,
      SmartPlaylistId.favorites,
    ]);
    expect(smartOnlyCount, 0);

    final userMixCount = await localProvider.playCombinedPlaylists([
      SmartPlaylistId.allSongs, // ignored
      userPl1.id,
      userPl2.id,
    ]);
    expect(userMixCount, 2);
    expect(
      localProvider.queue.map((s) => s.title).toList(),
      ['Song 1', 'Song 2'],
    );

    // Tap the search shortcut button in the Playlists header -> opens All songs drill-down with search bar
    await tester.tap(
      find.byKey(const ValueKey('playlists_search_shortcut_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final searchFieldFinder = find.byKey(
      const ValueKey('all_songs_search_field'),
    );
    expect(searchFieldFinder, findsOneWidget);

    // Filter songs in All songs drill-down and verify playing uses filtered queueContext
    await tester.enterText(searchFieldFinder, 'Song 2');
    await tester.pump(const Duration(milliseconds: 250));
    expect(localProvider.localSearchQuery, 'Song 2');
    expect(localProvider.filteredLocalSongs.length, 1);

    await tester.tap(find.text('Song 2').last);
    await tester.pump(const Duration(milliseconds: 250));
    expect(localProvider.queue.map((s) => s.title).toList(), ['Song 2']);

    // Pressing Back from All songs drill-down MUST clear localSearchQuery
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(localProvider.localSearchQuery, isEmpty);
  });

  test(
      'AppStrings automatically switches UI texts between Indonesian (id/in) and English (en)',
      () {
    AppStrings.debugLanguageCodeOverride = 'id';
    expect(AppStrings.isIndonesian, isTrue);
    expect(AppStrings.smartPlaylistTitle(SmartPlaylistId.allSongs), 'Semua lagu');
    expect(AppStrings.yourPlaylistsHeader, 'Playlist kamu');
    expect(AppStrings.forYouTitle, 'Untukmu');
    expect(AppStrings.omniboxHint, 'Cari lagu atau tempel link...');

    AppStrings.debugLanguageCodeOverride = 'en';
    expect(AppStrings.isIndonesian, isFalse);
    expect(AppStrings.smartPlaylistTitle(SmartPlaylistId.allSongs), 'All songs');
    expect(AppStrings.yourPlaylistsHeader, 'Your playlists');
    expect(AppStrings.forYouTitle, 'For You');
    expect(AppStrings.omniboxHint, 'Search songs or paste link...');
  });

  test(
      'Offline detection distinguishes network errors from empty search and supports manual/typing banner dismissal',
      () {
    expect(
      MetadataService.isNetworkOfflineError(
        const SocketException('Failed host lookup: api.deezer.com'),
      ),
      isTrue,
    );
    expect(
      MetadataService.isNetworkOfflineError(
        const NetworkOfflineException('No internet connection'),
      ),
      isTrue,
    );

    final dlProvider = DownloaderProvider();
    addTearDown(dlProvider.dispose);

    expect(dlProvider.statusBannerDismissed, isFalse);

    dlProvider.clearTransientErrorOnTyping();
    expect(dlProvider.statusBannerDismissed, isTrue);
    expect(dlProvider.shouldShowStatusBanner, isFalse);

    dlProvider.dismissStatusBanner();
    expect(dlProvider.statusBannerDismissed, isTrue);
    expect(dlProvider.shouldShowStatusBanner, isFalse);
  });

  test(
      'LocalSong.toJson omits raw usltLyrics text and stores compact boolean flags (< 5 MB User Data optimization)',
      () async {
    final syncedSong = _mockSong(
      10,
      lyrics: '[00:01.00] Line 1\n[00:05.00] Line 2',
    );
    final jsonMap = syncedSong.toJson();

    expect(jsonMap.containsKey('usltLyrics'), isFalse);
    expect(jsonMap['hasLyrics'], isTrue);
    expect(jsonMap['hasSyncedLyrics'], isTrue);

    // Deserializing from compact JSON preserves hasLyrics and hasSyncedLyrics flags even before on-demand USLT load
    final restored = LocalSong.fromJson(jsonMap);
    expect(restored.usltLyrics, isNull);
    expect(restored.hasLyrics, isTrue);
    expect(restored.hasSyncedLyrics, isTrue);
    expect(restored.isLyricsLoadedInMemory, isFalse);

    // Accessing parsedSyncedLyrics and plainLyricLines before on-demand load must NEVER throw a null check error
    expect(restored.parsedSyncedLyrics, isEmpty);
    expect(restored.plainLyricLines, isEmpty);

    final hydrated = restored.copyWith(
      usltLyrics: '[00:01.00] Line 1\n[00:05.00] Line 2',
    );
    expect(hydrated.isLyricsLoadedInMemory, isTrue);
    expect(hydrated.parsedSyncedLyrics.length, 2);
    expect(hydrated.plainLyricLines.length, 2);

    // Playing, switching tracks, toggling play/pause, and applying folder visibility changes
    // on songs with unloaded on-demand USLT lyrics must work cleanly without crashing
    final localProvider = LocalMusicProvider();
    addTearDown(localProvider.dispose);

    final compactSong1 = LocalSong.fromJson(
      _mockSong(
        1,
        folderName: 'Music Barat',
        lyrics: '[00:01.00] Hello\n[00:03.00] World',
      ).toJson(),
    );
    final compactSong2 = LocalSong.fromJson(
      _mockSong(
        2,
        folderName: 'Music Japan',
        lyrics: '[00:02.00] Konnichiwa',
      ).toJson(),
    );

    localProvider.seedSongsForTesting([compactSong1, compactSong2]);
    expect(localProvider.currentSong?.usltLyrics, isNull);
    expect(localProvider.activeSyncedLyricIndex, -1);

    await localProvider.togglePlayPause();
    expect(localProvider.isPlaying, isTrue);

    await localProvider.playQueueIndex(1);
    expect(localProvider.currentSong?.filePath, compactSong2.filePath);
    expect(localProvider.isPlaying, isTrue);

    await localProvider.playSong(
      compactSong1,
      queueContext: [compactSong1, compactSong2],
    );
    expect(localProvider.currentSong?.filePath, compactSong1.filePath);

    await localProvider.applyFolderVisibilityChanges(
      hiddenFolderPaths: {'/storage/emulated/0/Music/Music Barat'},
    );
    expect(
      localProvider.isFolderHidden('/storage/emulated/0/Music/Music Barat'),
      isTrue,
    );
    expect(localProvider.currentSong?.filePath, compactSong2.filePath);
  });
}

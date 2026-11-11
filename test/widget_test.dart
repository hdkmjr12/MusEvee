import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spotmeta_downloader/main.dart';
import 'package:spotmeta_downloader/models/local_song.dart';
import 'package:spotmeta_downloader/models/track_metadata.dart';
import 'package:spotmeta_downloader/providers/downloader_provider.dart';
import 'package:spotmeta_downloader/providers/local_music_provider.dart';
import 'package:spotmeta_downloader/services/metadata_service.dart';
import 'package:spotmeta_downloader/services/romaji_service.dart';
import 'package:spotmeta_downloader/theme/musevee_palette.dart';
import 'package:spotmeta_downloader/utils/app_strings.dart';
import 'package:spotmeta_downloader/widgets/local_library_views.dart';
import 'package:spotmeta_downloader/widgets/musicolet_bottom_strip.dart';
import 'package:spotmeta_downloader/widgets/musicolet_mini_player.dart';
import 'package:spotmeta_downloader/widgets/now_playing_view.dart';

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

    // Switch to Downloader tab (Tab 4 in MusicoletBottomStrip)
    await tester.tap(find.byTooltip(AppStrings.tabDownloaderTooltip));
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

    expect(find.text('Tampilan'), findsOneWidget);
    expect(find.text('Gelap'), findsOneWidget);
    expect(find.text('Terang'), findsOneWidget);
    expect(find.text('Terbaik — 320 kbps'), findsOneWidget);
    expect(find.text('Seimbang — 192 kbps'), findsOneWidget);
    expect(find.text('Hemat — 128 kbps'), findsOneWidget);
    expect(find.text('MusEvee v4.8'), findsOneWidget);

    // Switch to Light Mode (`theme_mode_light`) and verify all 6 tabs render cleanly without error
    await tester.tap(find.byKey(const ValueKey('theme_mode_light')));
    await tester.pumpAndSettle();

    final appWidget = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(appWidget.themeMode, ThemeMode.light);

    // Visit Tab 0 (Queue), Tab 1 (Now Playing), Tab 2 (Folders), Tab 3 (Playlists), Tab 4 (Downloader) in Light Mode
    await tester.tap(find.byTooltip(AppStrings.tabQueueTooltip));
    await tester.pumpAndSettle();
    expect(find.textContaining('Queue'), findsWidgets);

    await tester.tap(find.byTooltip(AppStrings.tabFoldersTooltip));
    await tester.pumpAndSettle();
    expect(find.textContaining('Folders'), findsWidgets);

    await tester.tap(find.byTooltip(AppStrings.tabPlaylistsTooltip));
    await tester.pumpAndSettle();
    expect(find.text('Playlist kamu'), findsOneWidget);

    // Open New Playlist dialog in Light Mode and close it
    await tester.ensureVisible(find.text('Playlist Baru'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playlist Baru'));
    await tester.pumpAndSettle();
    expect(find.text('Batal'), findsOneWidget);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(AppStrings.tabNowPlayingTooltip));
    await tester.pumpAndSettle();
    expect(find.text('MusEvee Player'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  test(
      'Phase 1 Navigation icon state mapping resolves asset paths, moving circle background, and active/inactive colors across Light and Dark palettes',
      () {
    const light = MusEveePalette.light;
    const dark = MusEveePalette.dark;

    // When Tab 1 (Now Playing) is selected in Light Mode:
    final npActiveLight = MusicoletBottomStrip.resolveTabVisualState(
      tabIndex: MusicoletBottomStrip.nowPlayingTabIndex,
      selectedIndex: MusicoletBottomStrip.nowPlayingTabIndex,
      palette: light,
    );
    expect(npActiveLight.isActive, isTrue);
    expect(npActiveLight.iconData, Icons.play_arrow_rounded);
    expect(npActiveLight.isCircularPlayBadge, isTrue);
    expect(npActiveLight.circleBackgroundColor, light.nowPlayingPrimary);
    expect(npActiveLight.iconColor, light.nowPlayingOnPrimary);

    // When Tab 0 (Queue) is selected, Tab 1 (Now Playing) is inactive (plain triangle, no circle):
    final npInactiveLight = MusicoletBottomStrip.resolveTabVisualState(
      tabIndex: MusicoletBottomStrip.nowPlayingTabIndex,
      selectedIndex: MusicoletBottomStrip.queueTabIndex,
      palette: light,
    );
    expect(npInactiveLight.isActive, isFalse);
    expect(npInactiveLight.iconData, Icons.play_arrow_rounded);
    expect(npInactiveLight.isCircularPlayBadge, isFalse);
    expect(npInactiveLight.circleBackgroundColor, isNull);
    expect(npInactiveLight.iconColor, light.nowPlayingInactiveIcon);

    // Other tabs when Tab 1 is selected are inactive (pale gray, no circle):
    final queueInactiveLight = MusicoletBottomStrip.resolveTabVisualState(
      tabIndex: MusicoletBottomStrip.queueTabIndex,
      selectedIndex: MusicoletBottomStrip.nowPlayingTabIndex,
      palette: light,
    );
    expect(queueInactiveLight.isActive, isFalse);
    expect(queueInactiveLight.assetPath, 'assets/icons/add-to-playlist.png');
    expect(queueInactiveLight.circleBackgroundColor, isNull);
    expect(queueInactiveLight.iconColor, light.nowPlayingInactiveIcon);

    // Verify all 6 tab asset mappings and active moving-circle state in Dark Mode:
    const expectedAssets = <int, String?>{
      0: 'assets/icons/add-to-playlist.png',
      1: null,
      2: 'assets/icons/folder.png',
      3: 'assets/icons/music-album.png',
      4: 'assets/icons/downloading.png',
      5: 'assets/icons/settings.png',
    };
    for (final entry in expectedAssets.entries) {
      final activeState = MusicoletBottomStrip.resolveTabVisualState(
        tabIndex: entry.key,
        selectedIndex: entry.key,
        palette: dark,
      );
      expect(activeState.isActive, isTrue);
      expect(activeState.assetPath, entry.value);
      expect(activeState.isCircularPlayBadge, isTrue);
      expect(activeState.circleBackgroundColor, dark.nowPlayingPrimary);
      expect(activeState.iconColor, dark.nowPlayingOnPrimary);
    }

    // Verify computeIndicatorLeft centers the ~44px circle inside each of the 6 slots:
    const stripWidth = 360.0; // 60px per slot
    for (int i = 0; i < 6; i++) {
      final left = MusicoletBottomStrip.computeIndicatorLeft(
        stripWidth: stripWidth,
        selectedIndex: i,
      );
      expect(left, closeTo(i * 60.0 + (60.0 - 44.0) * 0.5, 0.001));
    }
  });

  testWidgets(
      'MusicoletBottomStrip slides the single 44px active circle behind the selected tab and renders Now Playing as a plain triangle',
      (WidgetTester tester) async {
    int selectedTab = 1;
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setHostState) {
          return MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
            ),
            home: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: MusicoletBottomStrip(
                selectedIndex: selectedTab,
                onTabSelected: (idx) => setHostState(() => selectedTab = idx),
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    final circleFinder = find.byKey(
      const ValueKey<String>('nav_moving_active_circle'),
    );
    expect(circleFinder, findsOneWidget);

    // On Tab 1 (Now Playing), circle center X matches Tab 1 button center X
    final tab1Center = tester.getCenter(
      find.byKey(const ValueKey<String>('nav_tab_button_1')),
    );
    expect(tester.getSize(circleFinder), const Size(44.0, 44.0));
    expect(tester.getCenter(circleFinder).dx, closeTo(tab1Center.dx, 0.5));

    // Switch to Tab 0 (Queue) -> circle slides to Tab 0 center X; Now Playing has no circle around it
    await tester.tap(find.byKey(const ValueKey<String>('nav_tab_button_0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    // Mid-animation: between Tab 1 and Tab 0
    final midCenterDx = tester.getCenter(circleFinder).dx;
    final tab0Center = tester.getCenter(
      find.byKey(const ValueKey<String>('nav_tab_button_0')),
    );
    expect(midCenterDx, lessThan(tab1Center.dx));
    expect(midCenterDx, greaterThan(tab0Center.dx));

    await tester.pumpAndSettle();
    expect(tester.getCenter(circleFinder).dx, closeTo(tab0Center.dx, 0.5));
    expect(
      find.byKey(const ValueKey<String>('nav_now_playing_inactive')),
      findsOneWidget,
    );

    // Switch to Tab 4 (Downloader) -> circle slides to Tab 4 center X
    final tab4Center = tester.getCenter(
      find.byKey(const ValueKey<String>('nav_tab_button_4')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('nav_tab_button_4')));
    await tester.pumpAndSettle();
    expect(tester.getCenter(circleFinder).dx, closeTo(tab4Center.dx, 0.5));
  });

  test(
      'Fixed Home disc framing (0.95x diameter, 0.60x left edge), standard Home column width, and active lyric font step-down (22 -> 20 -> 18, min 18) with >= 1.55x contrast',
      () {
    const screenW = 390.0;
    final normalWidth = NowPlayingView.computeStandardHomeColumnWidth(screenW);
    expect(normalWidth, closeTo(390.0 * 0.60 - 40.0, 0.001)); // 194.0

    // Default contrast ratio on Home: 22.0 / 13.5 = 1.6296 >= 1.55
    expect(MusEveePalette.lyricActiveMaxFontSize, 22.0);
    expect(MusEveePalette.lyricActiveMidFontSize, 20.0);
    expect(MusEveePalette.lyricActiveMinFontSize, 18.0);
    expect(MusEveePalette.lyricSecondaryFontSize, 13.5);
    expect(MusEveePalette.lyricPanelSecondaryFontSize, 14.5);
    expect(
      MusEveePalette.lyricActiveMaxFontSize /
          MusEveePalette.lyricSecondaryFontSize,
      greaterThanOrEqualTo(1.55),
    );

    // Short line fits at 22.0
    expect(
      NowPlayingView.computeActiveLyricFontSize(
        'Short line',
        maxWidth: normalWidth,
      ),
      22.0,
    );

    // Medium-length line steps down from 22 -> 20 or 18, never below 18.0
    const mediumLine =
        'Muteki no egao de arasu media shiritai sono himitsu misteria';
    final steppedFont = NowPlayingView.computeActiveLyricFontSize(
      mediumLine,
      maxWidth: normalWidth,
    );
    expect(steppedFont, isIn(<double>[22.0, 20.0, 18.0]));
    expect(steppedFont, lessThan(22.0));
    expect(steppedFont, greaterThanOrEqualTo(18.0));

    // Very long J-Pop/Romaji line steps down to floor 18.0 (and wraps up to 3 lines with ellipsis)
    const longRomajiLine =
        'Daremo karemo kizukanai uchi ni kokoro ubawareru kanpeki de usotsuki na kimi wa tensai teki na aidoru sama';
    expect(
      NowPlayingView.computeActiveLyricFontSize(
        longRomajiLine,
        maxWidth: normalWidth,
      ),
      18.0,
    );
  });

  testWidgets(
      'Phase 1 NowPlayingView verifies disc rotation & spin-down preserving angle, fixed Home disc framing across short & long-lyric songs, no-lyrics flow, all 3 overflow menu groups, and 360px/430px layouts',
      (WidgetTester tester) async {
    final localProvider = LocalMusicProvider();
    final downloaderProvider = DownloaderProvider();
    addTearDown(localProvider.dispose);
    addTearDown(downloaderProvider.dispose);

    final longRomajiSong = _mockSong(
      1,
      lyrics: '[00:01.00] Short opening line\n'
          '[00:05.00] Daremo karemo kizukanai uchi ni kokoro ubawareru kanpeki de usotsuki na kimi wa tensai teki na aidoru sama\n'
          '[00:10.00] Short closing line',
    );
    final noLyricsSong = _mockSong(2, lyrics: null);

    localProvider.seedSongsForTesting([longRomajiSong, noLyricsSong]);
    await localProvider.playSong(
      longRomajiSong,
      queueContext: [longRomajiSong, noLyricsSong],
    );

    final npKey = GlobalKey<NowPlayingViewState>();

    // 1. Test on narrow 360x780 screen
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          theme: ThemeData.light().copyWith(
            extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
          ),
          home: Scaffold(
            body: NowPlayingView(
              key: npKey,
              onNavigateToDownloader: () {},
              onNavigateToFolders: () {},
              onMoveLocalSongFolder: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Fixed Home disc framing (0.95 * 360 = 342.0 diameter, left = 0.60 * 360 = 216.0)
    // stays identical at song start, mid-song on long Romaji line, and after switching songs!
    final discFinder = find.byKey(
      const ValueKey<String>('now_playing_single_shared_disc'),
    );
    final discRectAtStart = tester.getRect(discFinder);
    expect(discRectAtStart.width, closeTo(360.0 * 0.95, 0.01));
    expect(discRectAtStart.left, closeTo(360.0 * 0.60, 0.01));

    localProvider.handleNativePosition(
      positionMs: 1200,
      durationMs: 180000,
      isPlaying: true,
    );
    await tester.pump();
    expect(tester.getRect(discFinder), discRectAtStart);

    localProvider.handleNativePosition(
      positionMs: 5500,
      durationMs: 180000,
      isPlaying: true,
    );
    await tester.pump();
    expect(tester.getRect(discFinder), discRectAtStart);

    // Disc rotates while playing; pause spins down within ~0.8s and preserves final angle (> 0)
    expect(npKey.currentState!.isDiscTickerActive, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 2000));
    final angleWhilePlaying = npKey.currentState!.currentDiscAngleRad;
    expect(angleWhilePlaying, greaterThan(0.0));

    // Pause -> spin-down over 0.8s, then ticker stops completely and angle is preserved
    await localProvider.togglePlayPause();
    expect(localProvider.isPlaying, isFalse);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 700));
    expect(npKey.currentState!.isDiscTickerActive, isFalse);
    final angleAtStop = npKey.currentState!.currentDiscAngleRad;
    expect(angleAtStop, greaterThanOrEqualTo(angleWhilePlaying));

    // Play again -> resumes from preserved angle without resetting to 0
    await localProvider.togglePlayPause();
    expect(localProvider.isPlaying, isTrue);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      npKey.currentState!.currentDiscAngleRad,
      greaterThan(angleAtStop),
    );

    // Pause so pumpAndSettle can run cleanly for menu sheet inspection
    await localProvider.togglePlayPause();
    await tester.pump(const Duration(milliseconds: 950));
    expect(npKey.currentState!.isDiscTickerActive, isFalse);

    // Open `...` overflow menu sheet and verify all 3 groups are present
    await tester.tap(
      find.byKey(const ValueKey<String>('now_playing_overflow_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tambah ke Antrean'), findsOneWidget);
    expect(find.text('Tambah ke Playlist'), findsOneWidget);
    expect(find.text('Info File & Path Folder'), findsOneWidget);
    expect(find.text('Buka Folder'), findsOneWidget);
    expect(find.text('Pindah Folder'), findsOneWidget);
    expect(find.text('Edit Tag & Embedded Lyrics'), findsOneWidget);
    expect(find.text('Hapus File Lagu'), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -280),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ganti Lirik dari LRCLIB'), findsOneWidget);
    expect(find.text('Auto-Romaji Lirik & Judul Jepang'), findsOneWidget);
    expect(find.text('Ukuran Font Lirik'), findsOneWidget);
    expect(find.text('Sinkronisasi Waktu Lirik'), findsOneWidget);
    expect(find.text('Mode & Sumber Lirik'), findsOneWidget);
    expect(find.text('Equalizer Sistem Android'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('overflow_volume_slider')),
      findsOneWidget,
    );

    // Dismiss `...` sheet
    Navigator.of(tester.element(find.byType(NowPlayingView))).pop();
    await tester.pumpAndSettle();

    // Switch to song with NO USLT lyrics (noLyricsSong) -> disc framing is STILL identical (zero disc jump!), tapping prompt opens search/manual sheet
    await localProvider.playNext();
    await localProvider.togglePlayPause(); // pause so ticker stops after spin-down
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 950));
    expect(tester.getRect(discFinder), discRectAtStart);
    expect(
      find.byKey(const ValueKey<String>('now_playing_no_lyrics_prompt')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('now_playing_no_lyrics_prompt')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cari Lirik LRCLIB'), findsOneWidget);
    expect(find.text('Isi Manual'), findsOneWidget);
    Navigator.of(tester.element(find.byType(NowPlayingView))).pop();
    await tester.pumpAndSettle();

    // 2. Test on wide 430x932 screen -> no overflow
    await tester.binding.setSurfaceSize(const Size(430, 932));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Phase 1 NowPlayingView executes all 3 overflow menu groups, tap-to-seek on 3-line lyrics, plain lyrics column, and Downloader badge + MiniPlayer',
      (WidgetTester tester) async {
    final localProvider = LocalMusicProvider();
    final downloaderProvider = DownloaderProvider();
    addTearDown(localProvider.dispose);
    addTearDown(downloaderProvider.dispose);

    final syncedSong = _mockSong(
      1,
      lyrics: '[00:02.00] But what if I call\n'
          '[00:08.00] And you pick up the phone\n'
          '[00:15.00] And I use this holiday to make my way to your ghost',
    );
    final plainSong = _mockSong(
      2,
      lyrics: 'Untimed first line\nUntimed second line\nUntimed third line',
    );

    localProvider.seedSongsForTesting([syncedSong, plainSong]);
    await localProvider.playSong(
      syncedSong,
      queueContext: [syncedSong, plainSong],
    );
    // Pause so spin-down finishes and pumpAndSettle works for modal sheets/dialogs
    await localProvider.togglePlayPause();

    bool navigatedToFolders = false;
    LocalSong? movedSong;
    int selectedNavTab = 1;

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
        child: StatefulBuilder(
          builder: (context, setHostState) {
            return MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const <ThemeExtension<dynamic>>[MusEveePalette.dark],
              ),
              home: Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: selectedNavTab == 1
                          ? NowPlayingView(
                              isVisible: selectedNavTab == 1,
                              onNavigateToDownloader: () {},
                              onNavigateToFolders: () {
                                navigatedToFolders = true;
                              },
                              onMoveLocalSongFolder: (s) async {
                                movedSong = s;
                              },
                            )
                          : const Center(child: Text('Other Tab Content')),
                    ),
                    if (selectedNavTab != 1)
                      MusicoletMiniPlayer(
                        onTapOpenNowPlaying: () =>
                            setHostState(() => selectedNavTab = 1),
                      ),
                  ],
                ),
                bottomNavigationBar: MusicoletBottomStrip(
                  selectedIndex: selectedNavTab,
                  activeDownloadBadgeCount: 2,
                  onTabSelected: (idx) =>
                      setHostState(() => selectedNavTab = idx),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    // Verify active download badge ('2') is visible on Downloader tab
    expect(find.text('2'), findsOneWidget);

    // Natural active-line progression (index 0 -> 1) triggers 400ms slide-up animation
    localProvider.handleNativePosition(
      positionMs: 2500,
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pumpAndSettle();
    expect(localProvider.activeLyricIndexNotifier.value, 0);

    localProvider.handleNativePosition(
      positionMs: 8500,
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pump();
    final slideTransformAtStart = tester.widget<Transform>(
      find.byKey(
        const ValueKey<String>('now_playing_three_line_slide_transform'),
      ),
    );
    // At t=0 of natural step, column starts shifted down (+28px) and slides upward to 0
    expect(slideTransformAtStart.transform.getTranslation().y, closeTo(28.0, 0.5));
    await tester.pump(const Duration(milliseconds: 200));
    final slideTransformMid = tester.widget<Transform>(
      find.byKey(
        const ValueKey<String>('now_playing_three_line_slide_transform'),
      ),
    );
    expect(slideTransformMid.transform.getTranslation().y, greaterThan(0.0));
    expect(slideTransformMid.transform.getTranslation().y, lessThan(28.0));
    await tester.pump(const Duration(milliseconds: 250));
    final slideTransformEnd = tester.widget<Transform>(
      find.byKey(
        const ValueKey<String>('now_playing_three_line_slide_transform'),
      ),
    );
    expect(slideTransformEnd.transform.getTranslation().y, closeTo(0.0, 0.01));

    // Section E: Tapping a lyric line on Home NEVER invokes seekTo; it opens the Full Lyrics Sheet while staying on Home (p == 1.0)
    final posBeforeHomeTap = localProvider.positionMs;
    await tester.tap(find.byKey(const ValueKey<String>('lyric_line_next')));
    await tester.pumpAndSettle();
    expect(localProvider.positionMs, posBeforeHomeTap);
    expect(find.byType(BottomSheet), findsOneWidget);
    final nowPlayingStateForHomeTap = tester.state<NowPlayingViewState>(
      find.byType(NowPlayingView),
    );
    expect(nowPlayingStateForHomeTap.currentPanelProgress, closeTo(1.0, 1e-4));
    Navigator.of(tester.element(find.byType(NowPlayingView))).pop();
    await tester.pumpAndSettle();

    // Open `...` menu and execute items across all 3 groups:
    // 1. Add to Queue
    final initialQueueLen = localProvider.queue.length;
    await tester.tap(
      find.byKey(const ValueKey<String>('now_playing_overflow_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah ke Antrean'));
    await tester.pumpAndSettle();
    expect(localProvider.queue.length, initialQueueLen + 1);

    // 2. File Info & Folder Path dialog
    await tester.tap(
      find.byKey(const ValueKey<String>('now_playing_overflow_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Info File & Path Folder'));
    await tester.pumpAndSettle();
    expect(find.text('Informasi File & Tag ID3'), findsOneWidget);
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();

    // 3. Open Folder & Move to Folder callbacks
    await tester.tap(
      find.byKey(const ValueKey<String>('now_playing_overflow_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buka Folder'));
    await tester.pumpAndSettle();
    expect(navigatedToFolders, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('now_playing_overflow_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pindah Folder'));
    await tester.pumpAndSettle();
    expect(movedSong?.filePath, syncedSong.filePath);

    // 4. Lyrics Group: Font Size, Auto-Sync toggle, and Volume/Pre-Amp sliders
    final initialFont = localProvider.lyricsFontSize;
    final initialSync = localProvider.autoScrollLyrics;
    await tester.tap(
      find.byKey(const ValueKey<String>('now_playing_overflow_button')),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -280),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ukuran Font Lirik'));
    await tester.pump();
    expect(localProvider.lyricsFontSize, isNot(equals(initialFont)));

    await tester.tap(find.text('Sinkronisasi Waktu Lirik'));
    await tester.pump();
    expect(localProvider.autoScrollLyrics, !initialSync);

    // Drag Volume slider inside sheet
    final volSliderFinder =
        find.byKey(const ValueKey<String>('overflow_volume_slider'));
    await tester.ensureVisible(volSliderFinder);
    await tester.pumpAndSettle();
    await tester.drag(volSliderFinder, const Offset(-60, 0));
    await tester.pump();
    expect(localProvider.volume, lessThan(1.0));

    Navigator.of(tester.element(find.byType(NowPlayingView))).pop();
    await tester.pumpAndSettle();

    // Switch to plain untimed lyrics song -> renders static plain column cleanly
    await localProvider.playSong(plainSong, queueContext: [plainSong]);
    await localProvider.togglePlayPause();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('now_playing_plain_lyrics_column')),
      findsOneWidget,
    );
    expect(find.text('Untimed first line'), findsOneWidget);

    // Switch to Tab 0 (Queue) -> Mini Player renders above bottom strip
    await tester.tap(find.byTooltip(AppStrings.tabQueueTooltip));
    await tester.pumpAndSettle();
    expect(find.byType(MusicoletMiniPlayer), findsOneWidget);
    expect(find.text('Song 2'), findsOneWidget);
  });

  testWidgets(
      'Phase 1 Lyrics Stability: wrapped line count and slot height remain identical across slide-up transition, and song-start/end lyrics stay left-anchored',
      (WidgetTester tester) async {
    final localProvider = LocalMusicProvider();
    final downloaderProvider = DownloaderProvider();
    addTearDown(localProvider.dispose);
    addTearDown(downloaderProvider.dispose);

    // Song starting with short lines ("Yeah!", "Young Money") followed by a multi-line wrapped lyric
    final song = _mockSong(
      1,
      lyrics: '[00:01.00] Yeah!\n'
          '[00:05.00] Young Money\n'
          '[00:10.00] We gonna party like it is the end of the world tonight together\n'
          '[00:16.00] Final outro line',
    );

    localProvider.seedSongsForTesting([song]);
    await localProvider.playSong(song, queueContext: [song]);
    await localProvider.togglePlayPause(); // paused so ticker does not spin indefinitely

    final npKey = GlobalKey<NowPlayingViewState>();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          theme: ThemeData.light().copyWith(
            extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
          ),
          home: Scaffold(
            body: NowPlayingView(
              key: npKey,
              onNavigateToDownloader: () {},
              onNavigateToFolders: () {},
              onMoveLocalSongFolder: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    // 1. Verify per-song active typography & slot metrics are pre-computed and cached for ALL lines before any transition
    final state = npKey.currentState!;
    final cachedLine0 = state.debugActiveMetricsForIndex(0);
    final cachedLine1 = state.debugActiveMetricsForIndex(1);
    final cachedLine2 = state.debugActiveMetricsForIndex(2);
    final cachedLine3 = state.debugActiveMetricsForIndex(3);
    expect(cachedLine0, isNotNull);
    expect(cachedLine1, isNotNull);
    expect(cachedLine2, isNotNull);
    expect(cachedLine3, isNotNull);
    expect(cachedLine2!.wrappedLineCount, greaterThanOrEqualTo(2));

    // 2. Problem 2 check: At song start (index 0: "Yeah!", no previous line),
    // the active line's left edge is anchored at 26.0px and the empty previous slot still reserves its height.
    localProvider.handleNativePosition(
      positionMs: 1200,
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pump();
    expect(localProvider.activeLyricIndexNotifier.value, 0);

    final activeLine0Finder = find.byKey(
      const ValueKey<String>('lyric_line_active_0_Yeah!'),
    );
    final prevSlotFinder = find.byKey(
      const ValueKey<String>('lyric_slot_previous'),
    );
    final activeSlotFinder = find.byKey(
      const ValueKey<String>('lyric_slot_active'),
    );
    final nextSlotFinder = find.byKey(
      const ValueKey<String>('lyric_slot_next'),
    );

    final songStartActiveLeft = tester.getTopLeft(activeLine0Finder).dx;
    final songStartColumnWidth = tester.getSize(activeSlotFinder).width;
    final emptyPrevSlotSize = tester.getSize(prevSlotFinder);
    expect(songStartActiveLeft, closeTo(26.0, 0.1));
    expect(emptyPrevSlotSize.width, closeTo(songStartColumnWidth, 0.1));
    expect(emptyPrevSlotSize.height, greaterThanOrEqualTo(16.0));

    // 3. Problem 1 check: Step naturally from index 1 -> index 2 (multi-line wrapped lyric).
    // First move to index 1 and settle so we are in the normal 3-line state before the 1 -> 2 transition.
    localProvider.handleNativePosition(
      positionMs: 5500,
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pumpAndSettle();
    expect(localProvider.activeLyricIndexNotifier.value, 1);

    final activeLine1Finder = find.byKey(
      const ValueKey<String>('lyric_line_active_1_Young Money'),
    );
    final normalStateActiveLeft = tester.getTopLeft(activeLine1Finder).dx;
    expect(songStartActiveLeft, closeTo(normalStateActiveLeft, 0.01));

    // Before the 1 -> 2 transition starts, record line 2's cached active wrap count and slot height
    final line2MetricsBefore = state.debugActiveMetricsForIndex(2)!;
    final expectedWrapCount = line2MetricsBefore.wrappedLineCount;
    final expectedSlotHeight = line2MetricsBefore.slotHeight;
    final expectedFontSize = line2MetricsBefore.fontSize;

    // Trigger natural step 1 -> 2 (starts 400ms slide-up transition)
    localProvider.handleNativePosition(
      positionMs: 10500,
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pump(); // First frame of transition (t = 0.0)

    final activeLine2Finder = find.byKey(
      const ValueKey<String>(
        'lyric_line_active_2_We gonna party like it is the end of the world tonight together',
      ),
    );
    expect(state.isLyricSlideAnimating, isTrue);

    // At frame 0 of transition: slot height, font size, weight, and wrap count match final active metrics
    final slotSizeAtStart = tester.getSize(activeSlotFinder);
    final textAtStart = tester.widget<Text>(activeLine2Finder);
    expect(slotSizeAtStart.height, closeTo(expectedSlotHeight, 0.01));
    expect(slotSizeAtStart.width, closeTo(songStartColumnWidth, 0.01));
    expect(textAtStart.style!.fontSize, closeTo(expectedFontSize, 0.001));
    expect(textAtStart.style!.fontWeight, FontWeight.w400);
    expect(
      state.debugActiveMetricsForIndex(2)!.wrappedLineCount,
      expectedWrapCount,
    );

    // Mid-transition (t ~ 160ms into 400ms slide): no reflow, identical slot height, font size, weight, wrap count, and left edge
    await tester.pump(const Duration(milliseconds: 160));
    expect(state.isLyricSlideAnimating, isTrue);
    final slotSizeMid = tester.getSize(activeSlotFinder);
    final prevSlotSizeMid = tester.getSize(prevSlotFinder);
    final textMid = tester.widget<Text>(activeLine2Finder);
    final prevTextMid = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyric_line_previous')),
    );
    expect(slotSizeMid.height, closeTo(expectedSlotHeight, 0.01));
    expect(slotSizeMid.width, closeTo(songStartColumnWidth, 0.01));
    expect(textMid.style!.fontSize, closeTo(expectedFontSize, 0.001));
    expect(textMid.style!.fontWeight, FontWeight.w400);
    expect(tester.getTopLeft(activeLine2Finder).dx, closeTo(26.0, 0.1));
    expect(
      state.debugActiveMetricsForIndex(2)!.wrappedLineCount,
      expectedWrapCount,
    );

    // After transition completes (t = 1.0): identical slot height, font size, weight, wrap count, and left edge (zero height jump)
    await tester.pumpAndSettle();
    expect(state.isLyricSlideAnimating, isFalse);
    final slotSizeAfter = tester.getSize(activeSlotFinder);
    final prevSlotSizeAfter = tester.getSize(prevSlotFinder);
    final textAfter = tester.widget<Text>(activeLine2Finder);
    final prevTextAfter = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyric_line_previous')),
    );
    expect(slotSizeAfter.height, closeTo(expectedSlotHeight, 0.01));
    expect(slotSizeAfter.width, closeTo(songStartColumnWidth, 0.01));
    expect(prevSlotSizeAfter.height, closeTo(prevSlotSizeMid.height, 0.01));
    expect(textAfter.style!.fontSize, closeTo(expectedFontSize, 0.001));
    expect(textAfter.style!.fontWeight, FontWeight.w400);
    expect(
      prevTextAfter.style!.fontSize,
      closeTo(prevTextMid.style!.fontSize!, 0.001),
    );
    expect(tester.getTopLeft(activeLine2Finder).dx, closeTo(26.0, 0.1));
    expect(
      state.debugActiveMetricsForIndex(2)!.wrappedLineCount,
      expectedWrapCount,
    );

    // 4. At song end (index 3, no next line), left edge is still 26.0px and empty next slot reserves its height
    localProvider.handleNativePosition(
      positionMs: 16500,
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pumpAndSettle();
    final activeLine3Finder = find.byKey(
      const ValueKey<String>('lyric_line_active_3_Final outro line'),
    );
    expect(tester.getTopLeft(activeLine3Finder).dx, closeTo(26.0, 0.1));
    expect(tester.getSize(nextSlotFinder).height, greaterThanOrEqualTo(16.0));
    expect(
      tester.getSize(nextSlotFinder).width,
      closeTo(songStartColumnWidth, 0.1),
    );
  });

  test(
      'Phase 1.5 Pager dots state mapping for panels 0/1/2 and lyrics opacity-by-distance constants',
      () {
    const light = MusEveePalette.light;
    const dark = MusEveePalette.dark;

    // 1. Dots state mapping for panels 0 (Lyrics), 1 (Home), 2 (Full Disc)
    expect(
      NowPlayingView.resolvePagerDotColors(
        activePageIndex: NowPlayingView.lyricsPanelIndex,
        palette: light,
      ),
      <Color>[
        light.nowPlayingPrimary,
        light.nowPlayingInactiveIcon,
        light.nowPlayingInactiveIcon,
      ],
    );
    expect(
      NowPlayingView.resolvePagerDotColors(
        activePageIndex: NowPlayingView.homePanelIndex,
        palette: light,
      ),
      <Color>[
        light.nowPlayingInactiveIcon,
        light.nowPlayingPrimary,
        light.nowPlayingInactiveIcon,
      ],
    );
    expect(
      NowPlayingView.resolvePagerDotColors(
        activePageIndex: NowPlayingView.fullDiscPanelIndex,
        palette: dark,
      ),
      <Color>[
        dark.nowPlayingInactiveIcon,
        dark.nowPlayingInactiveIcon,
        dark.nowPlayingPrimary,
      ],
    );

    // 2. Opacity-by-distance steps (0 = 1.0, ±1 = 0.90, ±2 = 0.65, ±3+ = 0.45 hard floor)
    expect(NowPlayingView.lyricsPanelOpacityDistance0, 1.0);
    expect(NowPlayingView.lyricsPanelOpacityDistance1, 0.90);
    expect(NowPlayingView.lyricsPanelOpacityDistance2, 0.65);
    expect(NowPlayingView.lyricsPanelOpacityDistance3Plus, 0.45);
    expect(MusEveePalette.lyricsPanelEdgeFadeHeightFactor, 0.08);
    expect(
      NowPlayingView.lyricPanelOpacityForDistance(0),
      1.0,
    );
    expect(
      NowPlayingView.lyricPanelOpacityForDistance(1),
      0.90,
    );
    expect(
      NowPlayingView.lyricPanelOpacityForDistance(-1),
      0.90,
    );
    expect(
      NowPlayingView.lyricPanelOpacityForDistance(2),
      0.65,
    );
    expect(
      NowPlayingView.lyricPanelOpacityForDistance(-2),
      0.65,
    );
    expect(
      NowPlayingView.lyricPanelOpacityForDistance(3),
      0.45,
    );
    expect(
      NowPlayingView.lyricPanelOpacityForDistance(-5),
      0.45,
    );
    expect(
      NowPlayingView.lyricPanelOpacityForDistance(50),
      0.45,
    );
    expect(
      NowPlayingView.lyricsPanelOpacityDistance0,
      greaterThan(NowPlayingView.lyricsPanelOpacityDistance1),
    );
    expect(
      NowPlayingView.lyricsPanelOpacityDistance1,
      greaterThan(NowPlayingView.lyricsPanelOpacityDistance2),
    );
    expect(
      NowPlayingView.lyricsPanelOpacityDistance2,
      greaterThan(NowPlayingView.lyricsPanelOpacityDistance3Plus),
    );

    // 3. Lyric measurement uses FontWeight.w400 (Regular)
    final measured = NowPlayingView.measureActiveLyricLine(
      'And I use this holiday to make my way to your ghost',
      columnWidth: 165.0,
    );
    expect(measured.fontWeight, FontWeight.w400);

    // 4. Disc keyframe geometry at p = 0 / 1 / 2 (fixed framing for all songs)
    const screenW = 390.0;
    const zoneH = 440.0;

    final geomP0 = NowPlayingView.computeDiscGeometryForProgress(
      progress: 0.0,
      screenWidth: screenW,
      zoneHeight: zoneH,
    );
    final geomP1 = NowPlayingView.computeDiscGeometryForProgress(
      progress: 1.0,
      screenWidth: screenW,
      zoneHeight: zoneH,
    );
    final geomP2 = NowPlayingView.computeDiscGeometryForProgress(
      progress: 2.0,
      screenWidth: screenW,
      zoneHeight: zoneH,
    );

    // p = 0: center is beyond right edge by more than radius (completely off-screen right)
    expect(geomP0.centerX - geomP0.radius, greaterThan(screenW));
    expect(geomP0.left, greaterThan(screenW));

    // p = 1: Fixed Home framing (0.95 * screenW, left = 0.60 * screenW)
    expect(MusEveePalette.discDiameterFactor, 0.95);
    expect(MusEveePalette.discLeftEdgeFactor, 0.60);
    expect(
      geomP1.diameter,
      closeTo(screenW * MusEveePalette.discDiameterFactor, 0.001),
    );
    expect(
      geomP1.left,
      closeTo(screenW * MusEveePalette.discLeftEdgeFactor, 0.001),
    );

    // p = 2: Full Disc framing (horizontally centered at screenW / 2, diameter = min(0.95 * screenW, zoneH - 8))
    expect(geomP2.centerX, closeTo(screenW / 2.0, 0.001));
    expect(
      geomP2.diameter,
      closeTo(screenW * MusEveePalette.discDiameterFactor, 0.001),
    );

    // Continuous interpolation between keyframes (p = 0.5 and p = 1.5)
    final geomP05 = NowPlayingView.computeDiscGeometryForProgress(
      progress: 0.5,
      screenWidth: screenW,
      zoneHeight: zoneH,
    );
    final geomP15 = NowPlayingView.computeDiscGeometryForProgress(
      progress: 1.5,
      screenWidth: screenW,
      zoneHeight: zoneH,
    );
    expect(
      geomP05.centerX,
      closeTo((geomP0.centerX + geomP1.centerX) / 2.0, 0.001),
    );
    expect(
      geomP15.centerX,
      closeTo((geomP1.centerX + geomP2.centerX) / 2.0, 0.001),
    );
  });

  testWidgets(
      'Phase 1.5 NowPlayingView 3-Panel Pager: initial Home panel, swipe to Lyrics/Full Disc, shared disc rotation, manual scroll pause/resume, tap-to-seek, and panel persistence across track changes',
      (WidgetTester tester) async {
    final localProvider = LocalMusicProvider();
    final downloaderProvider = DownloaderProvider();
    addTearDown(localProvider.dispose);
    addTearDown(downloaderProvider.dispose);

    final syncedSong1 = _mockSong(
      1,
      lyrics: '[00:01.00] Line Zero Opening\n'
          '[00:04.00] But what if I call\n'
          '[00:08.00] And you pick up the phone\n'
          '[00:12.00] And I use this holiday to make my way to your ghost\n'
          '[00:16.00] Line Four Distance Two\n'
          '[00:20.00] Line Five Distance Three',
    );
    final syncedSong2 = _mockSong(
      2,
      lyrics: '[00:02.00] Second Song First Line\n'
          '[00:07.00] Second Song Second Line',
    );
    final noLyricsSong = _mockSong(3, lyrics: null);

    localProvider.seedSongsForTesting([syncedSong1, syncedSong2, noLyricsSong]);
    await localProvider.playSong(
      syncedSong1,
      queueContext: [syncedSong1, syncedSong2, noLyricsSong],
    );

    final npKey = GlobalKey<NowPlayingViewState>();
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          theme: ThemeData.light().copyWith(
            extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
          ),
          home: Scaffold(
            body: NowPlayingView(
              key: npKey,
              onNavigateToDownloader: () {},
              onNavigateToFolders: () {},
              onMoveLocalSongFolder: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    final state = npKey.currentState!;

    // 1. Initial panel is Home (index 1, p = 1.0), song title weight is SemiBold (w600), and only ONE shared disc exists
    expect(state.currentPagerIndex, NowPlayingView.homePanelIndex);
    expect(state.currentPanelProgress, closeTo(1.0, 0.001));
    expect(
      find.byKey(const ValueKey<String>('now_playing_pager_dots')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('now_playing_single_shared_disc')),
      findsOneWidget,
    );
    final songTitleText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('now_playing_song_title')),
    );
    expect(songTitleText.style!.fontWeight, FontWeight.w600);

    // 1b. Slow half-drag Home -> Lyrics (p = 0.5, t = 0.5): ONE Fluid Lyrics Morph scene is active (zero duplicates), disc glides right, exactly ONE disc exists
    state.debugSetPanelProgress(0.5);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('now_playing_single_shared_disc')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('now_playing_lyrics_morph_scene')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('now_playing_lyrics_panel')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('now_playing_three_line_lyrics')),
      findsNothing,
    );

    // 1c. Slow half-drag Home -> Full Disc (p = 1.5): exactly ONE disc exists at every moment, gliding toward horizontal center
    state.debugSetPanelProgress(1.5);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('now_playing_single_shared_disc')),
      findsOneWidget,
    );
    final homeLyricsTransformP15 = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('now_playing_home_lyrics_transform')),
    );
    expect(homeLyricsTransformP15.transform.getTranslation().x, lessThan(0.0));

    // Reset back to p = 1.0 (Home) for full gesture swipe checks
    state.debugSetPanelProgress(1.0);
    await tester.pump();

    // 2. Disc rotates on Home (Panel 1); swipe left to Full Disc (Panel 2) mid-play -> rotation angle continues seamlessly without reset
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 1200));
    final angleOnHome = state.currentDiscAngleRad;
    expect(angleOnHome, greaterThan(0.0));

    // Swipe left (Home 1 -> Full Disc 2)
    await tester.drag(
      find.byKey(const ValueKey<String>('now_playing_middle_pager')),
      const Offset(-300, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(state.currentPagerIndex, NowPlayingView.fullDiscPanelIndex);
    expect(state.currentPanelProgress, closeTo(2.0, 0.001));
    expect(
      find.byKey(const ValueKey<String>('now_playing_full_disc_panel')),
      findsOneWidget,
    );
    final angleOnFullDisc = state.currentDiscAngleRad;
    expect(angleOnFullDisc, greaterThan(angleOnHome));

    // Track change while on Full Disc (Panel 2) -> stays on Full Disc (index 2)
    await localProvider.playNext(); // syncedSong2
    await tester.pump(const Duration(milliseconds: 350));
    expect(localProvider.currentSong?.filePath, syncedSong2.filePath);
    expect(state.currentPagerIndex, NowPlayingView.fullDiscPanelIndex);

    // Switch back to syncedSong1 and pause so pumpAndSettle works cleanly for Lyrics panel checks
    await localProvider.playPrevious();
    await localProvider.togglePlayPause();
    await tester.pump(const Duration(milliseconds: 950));
    expect(state.isDiscTickerActive, isFalse);

    // 3. Swipe right twice (Full Disc 2 -> Home 1 -> Lyrics 0)
    await tester.drag(
      find.byKey(const ValueKey<String>('now_playing_middle_pager')),
      const Offset(300, 0),
    );
    await tester.pumpAndSettle();
    expect(state.currentPagerIndex, NowPlayingView.homePanelIndex);

    await tester.drag(
      find.byKey(const ValueKey<String>('now_playing_middle_pager')),
      const Offset(300, 0),
    );
    await tester.pumpAndSettle();
    expect(state.currentPagerIndex, NowPlayingView.lyricsPanelIndex);
    expect(
      find.byKey(const ValueKey<String>('now_playing_lyrics_panel')),
      findsOneWidget,
    );

    // 4. Advance playback to line 2 ("And you pick up the phone", 8500ms) and verify opacity-by-distance steps on Panel 0
    localProvider.handleNativePosition(
      positionMs: 8500,
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pumpAndSettle();
    expect(localProvider.activeLyricIndexNotifier.value, 2);

    final op0 = tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey<String>('lyrics_panel_line_opacity_0')),
        )
        .opacity;
    final op1 = tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey<String>('lyrics_panel_line_opacity_1')),
        )
        .opacity;
    final op2 = tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey<String>('lyrics_panel_line_opacity_2')),
        )
        .opacity;
    final op3 = tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey<String>('lyrics_panel_line_opacity_3')),
        )
        .opacity;
    final op4 = tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey<String>('lyrics_panel_line_opacity_4')),
        )
        .opacity;
    final op5 = tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey<String>('lyrics_panel_line_opacity_5')),
        )
        .opacity;

    expect(op2, NowPlayingView.lyricsPanelOpacityDistance0); // active (d=0)
    expect(op1, NowPlayingView.lyricsPanelOpacityDistance1); // d=1
    expect(op3, NowPlayingView.lyricsPanelOpacityDistance1); // d=1
    // In Stage Mode Rest Mode (default), lines at distance > 1 have opacity 0.0
    expect(op0, 0.0); // d=2 at rest
    expect(op4, 0.0); // d=2 at rest
    expect(op5, 0.0); // d=3 at rest

    // 5. Manual vertical scroll on Panel 0 enters Explore Mode (restoring ladder opacities), pauses auto-scroll, NEVER switches panels (p stays 0.0), and returns to Rest Mode after ~4 seconds
    expect(state.isLyricsPanelAutoScrollPaused, isFalse);
    expect(state.isLyricsPanelInExploreMode, isFalse);
    await tester.drag(
      find.byKey(const ValueKey<String>('lyrics_panel_scroll_view')),
      const Offset(0, -80),
    );
    await tester.pump();
    expect(state.isLyricsPanelAutoScrollPaused, isTrue);
    expect(state.isLyricsPanelInExploreMode, isTrue);
    expect(state.currentPagerIndex, NowPlayingView.lyricsPanelIndex);
    expect(state.currentPanelProgress, closeTo(0.0, 0.001));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_opacity_0')),
          )
          .opacity,
      NowPlayingView.lyricsPanelOpacityDistance2,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_opacity_4')),
          )
          .opacity,
      NowPlayingView.lyricsPanelOpacityDistance2,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_opacity_5')),
          )
          .opacity,
      NowPlayingView.lyricsPanelOpacityDistance3Plus,
    );

    // Wait 4.1 seconds -> auto-scroll resumes and returns to Rest Mode
    await tester.pump(const Duration(milliseconds: 4100));
    await tester.pumpAndSettle();
    expect(state.isLyricsPanelAutoScrollPaused, isFalse);
    expect(state.isLyricsPanelInExploreMode, isFalse);

    // 5b. A horizontal drag starting directly ON the Panel 0 lyrics list switches panels to Home (1)
    await tester.drag(
      find.byKey(const ValueKey<String>('lyrics_panel_scroll_view')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    expect(state.currentPagerIndex, NowPlayingView.homePanelIndex);
    expect(state.currentPanelProgress, closeTo(1.0, 0.001));

    // Swipe right back to Lyrics (Panel 0)
    await tester.drag(
      find.byKey(const ValueKey<String>('now_playing_middle_pager')),
      const Offset(260, 0),
    );
    await tester.pumpAndSettle();
    expect(state.currentPagerIndex, NowPlayingView.lyricsPanelIndex);
    expect(state.currentPanelProgress, closeTo(0.0, 0.001));

    // Also verify Panel 0 active lyric uses FontWeight.w400 (Regular)
    final panel0ActiveLine = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyrics_panel_line_text_2')),
    );
    expect(panel0ActiveLine.style!.fontWeight, FontWeight.w400);

    // 6. Tapping a lyric line in Panel 0 seeks playback to that line's timestamp (line 3 -> 12000ms)
    await tester.tap(
      find.byKey(const ValueKey<String>('lyrics_panel_line_3')),
    );
    await tester.pumpAndSettle();
    expect(localProvider.positionMs, 12000);

    // 7. Track change while on Lyrics (Panel 0) -> stays on Lyrics (index 0); no-lyrics song shows prompt on Panel 0
    await localProvider.playSong(
      noLyricsSong,
      queueContext: [syncedSong1, syncedSong2, noLyricsSong],
    );
    await localProvider.togglePlayPause();
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();
    expect(state.currentPagerIndex, NowPlayingView.lyricsPanelIndex);
    expect(
      find.byKey(const ValueKey<String>('lyrics_panel_no_lyrics_prompt')),
      findsOneWidget,
    );
  });

  test(
      'Phase 1.7 Fluid Lyrics Morph math: container width/left interpolation, live text re-wrapping, per-line centering offset at t = 0 / 0.5 / 1, and activeSyncedLyricIndex before first timestamp',
      () {
    const screenW = 390.0;
    const homeColW = 162.8;
    const stageW = screenW - 64.0; // 326.0

    // 1. Container left & width at t = 0.0 (Home), t = 0.5 (mid-morph), t = 1.0 (Lyrics Stage)
    expect(
      NowPlayingView.computeMorphContainerLeft(t: 0.0),
      closeTo(26.0, 0.001),
    );
    expect(
      NowPlayingView.computeMorphContainerLeft(t: 0.5),
      closeTo(29.0, 0.001),
    );
    expect(
      NowPlayingView.computeMorphContainerLeft(t: 1.0),
      closeTo(32.0, 0.001),
    );

    final w0 = NowPlayingView.computeMorphContainerWidth(
      t: 0.0,
      homeColumnWidth: homeColW,
      screenWidth: screenW,
    );
    final w05 = NowPlayingView.computeMorphContainerWidth(
      t: 0.5,
      homeColumnWidth: homeColW,
      screenWidth: screenW,
    );
    final w1 = NowPlayingView.computeMorphContainerWidth(
      t: 1.0,
      homeColumnWidth: homeColW,
      screenWidth: screenW,
    );
    expect(w0, closeTo(homeColW, 0.001));
    expect(w05, closeTo((homeColW + stageW) / 2.0, 0.001));
    expect(w1, closeTo(stageW, 0.001));

    // 2. Live text re-wrapping as containerWidth(t) expands from Home to Stage
    const sampleLine = 'And I know it?';
    final roleFontSize = NowPlayingView.computeActiveLyricFontSize(
      sampleLine,
      maxWidth: homeColW,
    );
    final mAtHome = NowPlayingView.measureLyricLineAtWidth(
      sampleLine,
      containerWidth: w0,
      fontSize: roleFontSize,
      isActiveRole: true,
    );
    final mAtMid = NowPlayingView.measureLyricLineAtWidth(
      sampleLine,
      containerWidth: w05,
      fontSize: roleFontSize,
      isActiveRole: true,
    );
    final mAtStage = NowPlayingView.measureLyricLineAtWidth(
      sampleLine,
      containerWidth: w1,
      fontSize: roleFontSize,
      isActiveRole: true,
    );
    expect(mAtHome.wrappedLineCount, greaterThanOrEqualTo(2));
    expect(mAtStage.wrappedLineCount, 1);

    // 3. Per-line horizontal offsetX at t = 0.0 (left-aligned = 0), t = 0.5 (starting centering blend), t = 1.0 (centered)
    final offset0 = NowPlayingView.computeMorphLineOffsetX(
      t: 0.0,
      containerWidth: w0,
      lineMeasuredWidth: mAtHome.measuredLineWidth,
    );
    final offset05 = NowPlayingView.computeMorphLineOffsetX(
      t: 0.5,
      containerWidth: w05,
      lineMeasuredWidth: mAtMid.measuredLineWidth,
    );
    final offset1 = NowPlayingView.computeMorphLineOffsetX(
      t: 1.0,
      containerWidth: w1,
      lineMeasuredWidth: mAtStage.measuredLineWidth,
    );
    expect(offset0, 0.0);
    expect(offset05, greaterThan(0.0));
    expect(offset05, lessThan((w05 - mAtMid.measuredLineWidth) / 2.0));
    expect(
      offset1,
      closeTo((w1 - mAtStage.measuredLineWidth) / 2.0, 0.001),
    );

    // 4. Extra lines fade factor (0 for t <= 0.65, 1 at t = 1.0)
    expect(NowPlayingView.computeMorphExtraLinesFadeFactor(0.0), 0.0);
    expect(NowPlayingView.computeMorphExtraLinesFadeFactor(0.5), 0.0);
    expect(NowPlayingView.computeMorphExtraLinesFadeFactor(0.65), 0.0);
    expect(
      NowPlayingView.computeMorphExtraLinesFadeFactor(0.82),
      greaterThan(0.0),
    );
    expect(NowPlayingView.computeMorphExtraLinesFadeFactor(1.0), 1.0);

    // 5. Active line rule before first lyric timestamp: returns -1 when positionMs < entries.first.timeMs
    final entries = <SyncedLyricEntry>[
      const SyncedLyricEntry(timeMs: 13200, text: 'First vocal line'),
      const SyncedLyricEntry(timeMs: 18000, text: 'Second vocal line'),
    ];
    expect(NowPlayingView.resolveActiveSyncedLyricIndex(entries, 0), -1);
    expect(NowPlayingView.resolveActiveSyncedLyricIndex(entries, 13199), -1);
    expect(NowPlayingView.resolveActiveSyncedLyricIndex(entries, 13200), 0);
    expect(NowPlayingView.resolveActiveSyncedLyricIndex(entries, 18500), 1);
  });

  testWidgets(
      'Phase 1.7 Settled-State Exclusivity, Pixel-for-Pixel Handover Equality (t = 0 & t = 1), and Instrumental Intro (active == -1 before first lyric timestamp)',
      (WidgetTester tester) async {
    final localProvider = LocalMusicProvider();
    final downloaderProvider = DownloaderProvider();
    addTearDown(localProvider.dispose);
    addTearDown(downloaderProvider.dispose);

    // Song with an instrumental intro: first lyric starts at 00:13.20 (13200ms)
    final introSong = _mockSong(
      1,
      lyrics: '[00:13.20] And you know I am too?\n'
          '[00:18.00] Tell me where the road goes tonight\n'
          '[00:23.00] Underneath the silver streetlights\n'
          '[00:28.00] Fourth line at distance two\n'
          '[00:33.00] Fifth line at distance three',
    );

    localProvider.seedSongsForTesting([introSong]);
    await localProvider.playSong(introSong, queueContext: [introSong]);
    await localProvider.togglePlayPause();

    final npKey = GlobalKey<NowPlayingViewState>();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          theme: ThemeData.light().copyWith(
            extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
          ),
          home: Scaffold(
            body: NowPlayingView(
              key: npKey,
              onNavigateToDownloader: () {},
              onNavigateToFolders: () {},
              onMoveLocalSongFolder: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    final state = npKey.currentState!;
    const palette = MusEveePalette.light;

    // =========================================================================
    // A. INSTRUMENTAL INTRO (positionMs = 3000 < 13200 -> active == -1)
    // =========================================================================
    localProvider.handleNativePosition(
      positionMs: 3000,
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pumpAndSettle();

    // 1. On Home (p = 1.0) during intro (Section C): 3-line Intro Stack fills top / middle / bottom slots
    // with lines 0, 1, 2 in secondary styling (13.5pt, nowPlayingSecondary) and opacities 1.0 / 0.72 / 0.48
    expect(
      find.byKey(
        const ValueKey<String>('lyric_line_active_0_And you know I am too?'),
      ),
      findsNothing,
    );
    final upcoming0Finder = find.byKey(
      const ValueKey<String>('lyric_line_upcoming_0_And you know I am too?'),
    );
    final upcoming1Finder = find.byKey(
      const ValueKey<String>(
        'lyric_line_upcoming_1_Tell me where the road goes tonight',
      ),
    );
    final upcoming2Finder = find.byKey(
      const ValueKey<String>(
        'lyric_line_upcoming_2_Underneath the silver streetlights',
      ),
    );
    expect(upcoming0Finder, findsOneWidget);
    expect(upcoming1Finder, findsOneWidget);
    expect(upcoming2Finder, findsOneWidget);
    for (final finder in <Finder>[
      upcoming0Finder,
      upcoming1Finder,
      upcoming2Finder,
    ]) {
      final txt = tester.widget<Text>(finder);
      expect(
        txt.style!.fontSize,
        closeTo(MusEveePalette.lyricSecondaryFontSize, 0.001),
      );
      expect(txt.style!.color, palette.nowPlayingSecondary);
    }

    // 2. On Lyrics Stage (p = 0.0) during intro: no line at distance 0 (opacity 1.0);
    // line 0 uses distance-1 opacity (0.90) & secondary style, line 1 uses 0.65, line 2+ uses 0.0 in Rest mode
    state.debugSetPanelProgress(0.0);
    await tester.pump();
    final introOp0 = tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey<String>('lyrics_panel_line_opacity_0')),
        )
        .opacity;
    final introOp1 = tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey<String>('lyrics_panel_line_opacity_1')),
        )
        .opacity;
    final introOp2 = tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey<String>('lyrics_panel_line_opacity_2')),
        )
        .opacity;
    expect(introOp0, NowPlayingView.lyricsPanelOpacityDistance1); // 0.90
    expect(introOp1, NowPlayingView.lyricsPanelOpacityDistance2); // 0.65
    expect(introOp2, 0.0); // Stage Mode Rest Mode hides lines beyond stageDistance <= 1
    final stageLine0IntroText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyrics_panel_line_text_0')),
    );
    expect(
      stageLine0IntroText.style!.fontSize,
      closeTo(MusEveePalette.lyricPanelSecondaryFontSize, 0.001),
    );
    expect(stageLine0IntroText.style!.color, palette.nowPlayingSecondary);

    // 3. During Fluid Morph (p = 0.5) in intro: line 0 stays secondary (not promoted to active)
    state.debugSetPanelProgress(0.5);
    await tester.pump();
    final morphLine0IntroText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('morph_lyric_text_0')),
    );
    expect(
      morphLine0IntroText.style!.fontSize,
      closeTo(NowPlayingView.computeMorphSecondaryFontSize(0.5), 0.001),
    );
    expect(morphLine0IntroText.style!.color, palette.nowPlayingSecondary);

    // 4. Return to Home (p = 1.0) and cross first timestamp (13500ms >= 13200ms):
    // Promotion (-1 -> 0) settles Line 0 into the middle active slot over 400ms!
    state.debugSetPanelProgress(1.0);
    await tester.pump();
    localProvider.handleNativePosition(
      positionMs: 13500,
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pumpAndSettle();

    final active0Finder = find.byKey(
      const ValueKey<String>('lyric_line_active_0_And you know I am too?'),
    );
    expect(active0Finder, findsOneWidget);
    final active0Text = tester.widget<Text>(active0Finder);
    expect(
      active0Text.style!.fontSize,
      greaterThan(MusEveePalette.lyricSecondaryFontSize),
    );
    expect(active0Text.style!.color, palette.nowPlayingPrimary);

    // 5. Seeking back before first timestamp (4000ms < 13200ms) demotes (0 -> -1) back to the 3-line Intro Stack
    localProvider.seekTo(4000);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('lyric_line_active_0_And you know I am too?'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey<String>('lyric_line_upcoming_0_And you know I am too?'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'lyric_line_upcoming_1_Tell me where the road goes tonight',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'lyric_line_upcoming_2_Underneath the silver streetlights',
        ),
      ),
      findsOneWidget,
    );

    // =========================================================================
    // B. SETTLED-STATE EXCLUSIVITY & NO DUPLICATE LYRIC WIDGETS
    // =========================================================================
    // Advance to line 1 (18500ms) so previous (0), active (1), and next (2) all have text
    await localProvider.seekTo(18500);
    await tester.pumpAndSettle();

    // At p = 1.0 (settled Home): stage and morph layers are completely absent
    state.debugSetPanelProgress(1.0);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('now_playing_three_line_lyrics')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('now_playing_lyrics_panel')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('now_playing_lyrics_morph_scene')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('lyric_line_previous')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'lyric_line_active_1_Tell me where the road goes tonight',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('lyric_line_next')),
      findsOneWidget,
    );

    // At p = 0.5 (mid-morph): ONLY morph layer is present; strictly 1 slot per line (no ghost/double text)
    state.debugSetPanelProgress(0.5);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('now_playing_lyrics_morph_scene')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('now_playing_three_line_lyrics')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('now_playing_lyrics_panel')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('morph_lyric_text_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('morph_lyric_text_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('morph_lyric_text_2')),
      findsOneWidget,
    );

    // At p = 0.0 (settled Lyrics Stage): home and morph layers are completely absent
    state.debugSetPanelProgress(0.0);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('now_playing_lyrics_panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('now_playing_three_line_lyrics')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('now_playing_lyrics_morph_scene')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_text_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_text_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_text_2')),
      findsOneWidget,
    );

    // =========================================================================
    // C. HANDOVER EQUALITY AT t = 1.0 (p = 0.0) AND t = 0.0 (p = 1.0)
    // =========================================================================
    // 1. Compare settled Lyrics Stage (p = 0.0) vs Morph at t = 1.0 (p = 0.0)
    final settledStageSlot0 = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_0')),
    );
    final settledStageSlot1 = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_1')),
    );
    final settledStageSlot2 = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_2')),
    );
    final settledStageSlot3 = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_3')),
    );
    final settledStageText1 = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_text_1')),
    );

    state.debugRenderMorphAtSettledEndpoints = true;
    state.debugSetPanelProgress(0.0); // t = 1.0 in Morph
    await tester.pump();

    final morphT1Slot0 = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_slot_0')),
    );
    final morphT1Slot1 = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_slot_1')),
    );
    final morphT1Slot2 = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_slot_2')),
    );
    final morphT1Slot3 = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_slot_3')),
    );
    final morphT1Text1 = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_text_1')),
    );

    expect(morphT1Slot0.left, closeTo(settledStageSlot0.left, 0.001));
    expect(morphT1Slot0.top, closeTo(settledStageSlot0.top, 0.001));
    expect(morphT1Slot0.width, closeTo(settledStageSlot0.width, 0.001));
    expect(morphT1Slot0.height, closeTo(settledStageSlot0.height, 0.001));

    expect(morphT1Slot1.left, closeTo(settledStageSlot1.left, 0.001));
    expect(morphT1Slot1.top, closeTo(settledStageSlot1.top, 0.001));
    expect(morphT1Slot1.width, closeTo(settledStageSlot1.width, 0.001));
    expect(morphT1Slot1.height, closeTo(settledStageSlot1.height, 0.001));

    expect(morphT1Slot2.left, closeTo(settledStageSlot2.left, 0.001));
    expect(morphT1Slot2.top, closeTo(settledStageSlot2.top, 0.001));
    expect(morphT1Slot3.top, closeTo(settledStageSlot3.top, 0.001));
    expect(morphT1Text1.left, closeTo(settledStageText1.left, 0.001));
    expect(morphT1Text1.top, closeTo(settledStageText1.top, 0.001));

    // 2. Compare Morph at t = 0.0 (p = 1.0) vs settled Home (p = 1.0)
    state.debugSetPanelProgress(1.0); // t = 0.0 in Morph
    await tester.pump();
    final morphT0SlotPrev = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_slot_0')),
    );
    final morphT0SlotActive = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_slot_1')),
    );
    final morphT0SlotNext = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_slot_2')),
    );

    state.debugRenderMorphAtSettledEndpoints = false;
    state.debugSetPanelProgress(1.0); // settled Home
    await tester.pump();
    final settledHomeSlotPrev = tester.getRect(
      find.byKey(const ValueKey<String>('lyric_slot_previous')),
    );
    final settledHomeSlotActive = tester.getRect(
      find.byKey(const ValueKey<String>('lyric_slot_active')),
    );
    final settledHomeSlotNext = tester.getRect(
      find.byKey(const ValueKey<String>('lyric_slot_next')),
    );

    expect(morphT0SlotPrev.left, closeTo(settledHomeSlotPrev.left, 0.001));
    expect(morphT0SlotPrev.top, closeTo(settledHomeSlotPrev.top, 0.001));
    expect(morphT0SlotPrev.width, closeTo(settledHomeSlotPrev.width, 0.001));
    expect(morphT0SlotPrev.height, closeTo(settledHomeSlotPrev.height, 0.001));

    expect(morphT0SlotActive.left, closeTo(settledHomeSlotActive.left, 0.001));
    expect(morphT0SlotActive.top, closeTo(settledHomeSlotActive.top, 0.001));
    expect(
      morphT0SlotActive.width,
      closeTo(settledHomeSlotActive.width, 0.001),
    );
    expect(
      morphT0SlotActive.height,
      closeTo(settledHomeSlotActive.height, 0.001),
    );

    expect(morphT0SlotNext.left, closeTo(settledHomeSlotNext.left, 0.001));
    expect(morphT0SlotNext.top, closeTo(settledHomeSlotNext.top, 0.001));
  });

  test(
      'Phase 1.8 Row-Level Lyrics Math: individual continuation-row centering at t = 1 and ±8px wrap hysteresis',
      () {
    const stageW = 326.0;
    const homeW = 162.0;

    // 1. A line that wraps into 2 rows at stage width (or any width) splits into individual LyricRowMetrics
    // and centers EVERY row individually at t = 1.0 (continuation row x-offset > 0 and > row 0 x-offset)
    const wrappedAtStageLine = 'Tell me where the road goes';
    final stageMetrics = NowPlayingView.measureLyricLineAtWidth(
      wrappedAtStageLine,
      containerWidth: stageW,
      fontSize: 17.0,
      isActiveRole: true,
      devicePixelRatio: 3.0,
    );
    expect(stageMetrics.wrappedLineCount, 2);
    expect(stageMetrics.rows.length, 2);

    final row0 = stageMetrics.rows[0];
    final row1 = stageMetrics.rows[1];
    expect(row0.text, isNotEmpty);
    expect(row1.text, isNotEmpty);
    expect(row1.localTop, greaterThan(row0.localTop));
    // Continuation row (row 1) is shorter than row 0
    expect(row1.width, lessThan(row0.width));

    final row0StageOffsetX = NowPlayingView.computeMorphRowOffsetX(
      t: 1.0,
      containerWidth: stageW,
      rowWidth: row0.width,
      devicePixelRatio: 3.0,
    );
    final row1StageOffsetX = NowPlayingView.computeMorphRowOffsetX(
      t: 1.0,
      containerWidth: stageW,
      rowWidth: row1.width,
      devicePixelRatio: 3.0,
    );
    expect(row0StageOffsetX, greaterThan(0.0));
    expect(row1StageOffsetX, greaterThan(0.0));
    expect(row1StageOffsetX, greaterThan(row0StageOffsetX));
    expect(
      row1StageOffsetX,
      closeTo(
        NowPlayingView.snapToPhysicalPixel((stageW - row1.width) / 2.0, 3.0),
        1e-5,
      ),
    );

    // At Home (t = 0.0), both rows are left-anchored (x-offset == 0.0)
    expect(
      NowPlayingView.computeMorphRowOffsetX(
        t: 0.0,
        containerWidth: homeW,
        rowWidth: row0.width,
        devicePixelRatio: 3.0,
      ),
      0.0,
    );
    expect(
      NowPlayingView.computeMorphRowOffsetX(
        t: 0.0,
        containerWidth: homeW,
        rowWidth: row1.width,
        devicePixelRatio: 3.0,
      ),
      0.0,
    );

    // 2. Wrap hysteresis (±8.0 logical px):
    // Find the exact break-even width B where a sample line transitions between 2 rows and 1 row
    const hysteresisLine = 'And you know I am too?';
    double low = 120.0;
    double high = 450.0;
    for (int iter = 0; iter < 30; iter++) {
      final mid = (low + high) / 2.0;
      final m = NowPlayingView.measureLyricLineAtWidth(
        hysteresisLine,
        containerWidth: mid,
        fontSize: 17.0,
        isActiveRole: true,
      );
      if (m.wrappedLineCount > 1) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final breakEvenWidth = (low + high) / 2.0;

    // Starting from 2 wrapped rows (narrower than break-even):
    // Oscillating ±4px across breakEvenWidth (breakEvenWidth + 4.0) MUST NOT unwrap to 1 row!
    final atPlus4From2 = NowPlayingView.measureLyricLineWithHysteresis(
      hysteresisLine,
      containerWidth: breakEvenWidth + 4.0,
      fontSize: 17.0,
      isActiveRole: true,
      previousWrapCount: 2,
      hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx, // 8.0
    );
    expect(atPlus4From2.wrappedLineCount, 2);
    expect(atPlus4From2.rows.length, 2);

    // Crossing breakEvenWidth by +12px (> 8px hysteresis) DOES unwrap to 1 row!
    final atPlus12From2 = NowPlayingView.measureLyricLineWithHysteresis(
      hysteresisLine,
      containerWidth: breakEvenWidth + 12.0,
      fontSize: 17.0,
      isActiveRole: true,
      previousWrapCount: 2,
      hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx,
    );
    expect(atPlus12From2.wrappedLineCount, 1);
    expect(atPlus12From2.rows.length, 1);

    // Now starting from 1 row (wider than break-even):
    // Oscillating -4px below breakEvenWidth (breakEvenWidth - 4.0) MUST NOT re-wrap to 2 rows!
    final atMinus4From1 = NowPlayingView.measureLyricLineWithHysteresis(
      hysteresisLine,
      containerWidth: breakEvenWidth - 4.0,
      fontSize: 17.0,
      isActiveRole: true,
      previousWrapCount: 1,
      hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx,
    );
    expect(atMinus4From1.wrappedLineCount, 1);
    expect(atMinus4From1.rows.length, 1);

    // Crossing breakEvenWidth by -12px (< -8px hysteresis) DOES re-wrap to 2 rows!
    final atMinus12From1 = NowPlayingView.measureLyricLineWithHysteresis(
      hysteresisLine,
      containerWidth: breakEvenWidth - 12.0,
      fontSize: 17.0,
      isActiveRole: true,
      previousWrapCount: 1,
      hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx,
    );
    expect(atMinus12From1.wrappedLineCount, 2);
    expect(atMinus12From1.rows.length, 2);
  });

  testWidgets(
      'Phase 1.8 Row-Level Renderer & 180ms Row-Glide: centered continuation rows, 0.0px handover on fractional DPR, and smooth row-glide with mid-glide reversal',
      (WidgetTester tester) async {
    final localProvider = LocalMusicProvider();
    final downloaderProvider = DownloaderProvider();
    addTearDown(localProvider.dispose);
    addTearDown(downloaderProvider.dispose);

    // Line 0 wraps into 2 rows at Stage (~326px) with a short continuation row;
    // Line 1 wraps into 2 rows at Home (~162px) and unwraps to 1 row at Stage (~326px)
    final morphSong = _mockSong(
      1,
      lyrics: '[00:01.00] Tell me where the road goes tonight\n'
          '[00:05.00] And you know\n'
          '[00:10.00] Silver lights\n'
          '[00:15.00] Fourth line',
    );

    localProvider.seedSongsForTesting([morphSong]);
    await localProvider.playSong(morphSong, queueContext: [morphSong]);
    await localProvider.togglePlayPause();

    final npKey = GlobalKey<NowPlayingViewState>();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Use a fractional devicePixelRatio (2.75) like real Android phones to verify physical pixel snapping
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          devicePixelRatio: 2.75,
        ),
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<LocalMusicProvider>.value(
              value: localProvider,
            ),
            ChangeNotifierProvider<DownloaderProvider>.value(
              value: downloaderProvider,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
            ),
            home: Scaffold(
              body: NowPlayingView(
                key: npKey,
                onNavigateToDownloader: () {},
                onNavigateToFolders: () {},
                onMoveLocalSongFolder: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    final state = npKey.currentState!;

    // Advance to line 1 ("And you know I am too?", 6000ms)
    localProvider.handleNativePosition(
      positionMs: 6000,
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pumpAndSettle();

    // =========================================================================
    // 1. Continuation row centering at Stage (p = 0.0 / t = 1.0) & 0.0px handover
    // =========================================================================
    state.debugSetPanelProgress(0.0);
    await tester.pump();

    // Line 0 ("And I use this holiday to make my way to your ghost tonight") wraps into 2 rows at Stage width
    final stageLine0Row0 = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_0_row_0')),
    );
    final stageLine0Row1 = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_0_row_1')),
    );
    // Continuation row (row 1) has a larger left offset than row 0 (centered individually, NOT left-aligned)
    expect(stageLine0Row1.left, greaterThan(stageLine0Row0.left));
    expect(stageLine0Row1.top, greaterThan(stageLine0Row0.top));

    // Compare EVERY row Rect in settled Lyrics Stage (p = 0.0) vs Morph at t = 1.0 (p = 0.0)
    final settledStageLine1Row0 = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_1_row_0')),
    );
    final settledStageLine2Row0 = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_2_row_0')),
    );

    state.debugRenderMorphAtSettledEndpoints = true;
    state.debugSetPanelProgress(0.0);
    await tester.pump();

    final morphT1Line0Row0 = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_0_row_0')),
    );
    final morphT1Line0Row1 = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_0_row_1')),
    );
    final morphT1Line1Row0 = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_1_row_0')),
    );
    final morphT1Line2Row0 = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_2_row_0')),
    );

    expect(morphT1Line0Row0.left, closeTo(stageLine0Row0.left, 1e-4));
    expect(morphT1Line0Row0.top, closeTo(stageLine0Row0.top, 1e-4));
    expect(morphT1Line0Row1.left, closeTo(stageLine0Row1.left, 1e-4));
    expect(morphT1Line0Row1.top, closeTo(stageLine0Row1.top, 1e-4));
    expect(morphT1Line1Row0.left, closeTo(settledStageLine1Row0.left, 1e-4));
    expect(morphT1Line1Row0.top, closeTo(settledStageLine1Row0.top, 1e-4));
    expect(morphT1Line2Row0.left, closeTo(settledStageLine2Row0.left, 1e-4));
    expect(morphT1Line2Row0.top, closeTo(settledStageLine2Row0.top, 1e-4));

    // Compare EVERY row Rect in settled Home (p = 1.0) vs Morph at t = 0.0 (p = 1.0)
    state.debugRenderMorphAtSettledEndpoints = false;
    state.debugSetPanelProgress(1.0);
    await tester.pump();

    final settledHomeActiveRow0 = tester.getRect(
      find.byKey(const ValueKey<String>('home_lyric_active_row_0')),
    );
    final settledHomeActiveRow1 = tester.getRect(
      find.byKey(const ValueKey<String>('home_lyric_active_row_1')),
    );
    final settledHomeNextRow0 = tester.getRect(
      find.byKey(const ValueKey<String>('home_lyric_next_row_0')),
    );

    state.debugRenderMorphAtSettledEndpoints = true;
    state.debugSetPanelProgress(1.0);
    await tester.pump();

    final morphT0ActiveRow0 = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_1_row_0')),
    );
    final morphT0ActiveRow1 = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_1_row_1')),
    );
    final morphT0NextRow0 = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_2_row_0')),
    );

    expect(morphT0ActiveRow0.left, closeTo(settledHomeActiveRow0.left, 1e-4));
    expect(morphT0ActiveRow0.top, closeTo(settledHomeActiveRow0.top, 1e-4));
    expect(morphT0ActiveRow1.left, closeTo(settledHomeActiveRow1.left, 1e-4));
    expect(morphT0ActiveRow1.top, closeTo(settledHomeActiveRow1.top, 1e-4));
    expect(morphT0NextRow0.left, closeTo(settledHomeNextRow0.left, 1e-4));
    expect(morphT0NextRow0.top, closeTo(settledHomeNextRow0.top, 1e-4));

    // =========================================================================
    // 2. 180ms easeOutCubic Row-Glide when wrap count changes + mid-glide reversal
    // =========================================================================
    state.debugRenderMorphAtSettledEndpoints = false;
    state.debugSetPanelProgress(1.0);
    await tester.pump();

    // At Home (p = 1.0), active line 1 ("And you know I am too?") is wrapped into 2 rows
    expect(state.debugCommittedWrapCountForLine(1), 2);
    final twoRowSlotHeight = state.debugAnimatedSlotHeightForLine(1)!;
    expect(state.isRowGlideAnimating, isFalse);

    // Drag to p = 0.25 (t = 0.75, wide enough to cross break-even + 8px hysteresis -> 1 row)
    state.debugSetPanelProgress(0.25);
    await tester.pump();

    expect(state.debugCommittedWrapCountForLine(1), 1);
    expect(state.isRowGlideAnimating, isTrue);
    expect(state.isLineRowGliding(1), isTrue);

    // At frame 0 of the 180ms glide, animatedSlotHeight starts at twoRowSlotHeight (zero jump!)
    final heightAtGlideStart = state.debugAnimatedSlotHeightForLine(1)!;
    expect(heightAtGlideStart, closeTo(twoRowSlotHeight, 0.01));

    // Advance 60ms into the 180ms glide -> slotHeight and row 0 top are at smooth intermediate values
    await tester.pump(const Duration(milliseconds: 60));
    expect(state.isRowGlideAnimating, isTrue);
    final heightAt60ms = state.debugAnimatedSlotHeightForLine(1)!;
    final rowTopsAt60ms = state.debugAnimatedRowTopsForLine(1)!;
    expect(heightAt60ms, lessThan(twoRowSlotHeight));
    expect(heightAt60ms, greaterThan(22.0));
    expect(rowTopsAt60ms[0], greaterThan(0.0));

    // Mid-glide reversal! Drag back toward Home (p = 0.90) at 60ms -> retargets from heightAt60ms without teleporting
    state.debugSetPanelProgress(0.90);
    await tester.pump();
    expect(state.debugCommittedWrapCountForLine(1), 2);
    expect(state.isLineRowGliding(1), isTrue);
    final heightOnReversalFrame = state.debugAnimatedSlotHeightForLine(1)!;
    expect(heightOnReversalFrame, closeTo(heightAt60ms, 0.01));

    // Let the reversed 180ms glide complete -> settles smoothly back to twoRowSlotHeight
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.isRowGlideAnimating, isFalse);
    expect(
      state.debugAnimatedSlotHeightForLine(1)!,
      closeTo(twoRowSlotHeight, 0.01),
    );
  });

  testWidgets(
      'Settled Lyrics Panel (p = 0) Option 1 Fix: pure document-coordinate anchoring (0.0px Frame-0 teleport), 300ms slot-height glide on activation/deactivation (including wrap-count changes), and 0.0px handover with live scroll offset',
      (WidgetTester tester) async {
    final localProvider = LocalMusicProvider();
    final downloaderProvider = DownloaderProvider();
    addTearDown(localProvider.dispose);
    addTearDown(downloaderProvider.dispose);

    // Under Flutter's test font (1em per character) at Stage width (376 - 64 = 312px):
    // - 21 characters at 14.5pt secondary = 21 * 14.5 = 304.5px <= 312px (1 row, ~20.4px)
    // - 21 characters at 15.0pt active = 21 * 15.0 = 315.0px > 312px (2 rows, ~39.2px)
    final eightLettersSong = _mockSong(
      1,
      lyrics: '[00:11.00] Short line\n'
          '[00:14.00] One two three four 21\n'
          '[00:17.00] Six seven eight ni 21\n'
          '[00:22.00] Opening and closing!\n'
          '[00:27.00] Final short lyric',
    );

    localProvider.seedSongsForTesting([eightLettersSong]);
    await localProvider.playSong(
      eightLettersSong,
      queueContext: [eightLettersSong],
    );
    await localProvider.togglePlayPause();

    final npKey = GlobalKey<NowPlayingViewState>();
    await tester.binding.setSurfaceSize(const Size(376, 835));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(376, 835),
          devicePixelRatio: 2.5,
        ),
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<LocalMusicProvider>.value(
              value: localProvider,
            ),
            ChangeNotifierProvider<DownloaderProvider>.value(
              value: downloaderProvider,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
            ),
            home: Scaffold(
              body: NowPlayingView(
                key: npKey,
                onNavigateToDownloader: () {},
                onNavigateToFolders: () {},
                onMoveLocalSongFolder: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    final state = npKey.currentState!;

    // Settle in Panel 0 (Lyrics stage, p = 0.0) at active line 1 (14500ms)
    localProvider.handleNativePosition(
      positionMs: 14500,
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pumpAndSettle();

    state.debugSetPanelProgress(0.0);
    await tester.pumpAndSettle();

    // At rest on line 1 (which wraps to 2 rows at active 15pt):
    // Line 2 ("That right there is the scariest feeling") is secondary
    final line0Before = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_0')),
    );
    final line1Before = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_1')),
    );
    final line2Before = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_2')),
    );
    final line3Before = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_3')),
    );
    final settledLine1ActiveHeight = state.debugAnimatedSlotHeightForLine(1)!;
    final settledLine2SecondaryHeight =
        state.debugAnimatedSlotHeightForLine(2)!;
    expect(settledLine1ActiveHeight, greaterThan(settledLine2SecondaryHeight));

    // =========================================================================
    // 1. Frame 0 of centerIdx change (1 -> 2): 0.0px screenY teleport & 400ms interpolated slide
    // =========================================================================
    localProvider.handleNativePosition(
      positionMs: 17100,
      durationMs: 180000,
      isPlaying: true,
    );
    // Pump Frame 0 (build runs BEFORE travel/slide advances a single pixel)
    await tester.pump();

    final line0Frame0 = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_0')),
    );
    final line1Frame0 = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_1')),
    );
    final line2Frame0 = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_2')),
    );
    final line3Frame0 = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_3')),
    );

    // Lines 0, 1, 2, 3 have 0.0px Frame-0 screen displacement and 0.0pt font jump!
    expect((line0Frame0.top - line0Before.top).abs(), lessThanOrEqualTo(0.01));
    expect((line1Frame0.top - line1Before.top).abs(), lessThanOrEqualTo(0.01));
    expect((line2Frame0.top - line2Before.top).abs(), lessThanOrEqualTo(0.01));
    expect((line3Frame0.top - line3Before.top).abs(), lessThanOrEqualTo(0.01));
    expect(line3Frame0.top, greaterThanOrEqualTo(line2Frame0.bottom));

    // On Frame 0 (u = 0.0), outgoing line 1 still starts at its active height and incoming line 2 starts at its secondary height
    expect(state.isPanel0TravelAnimating, isTrue);
    expect(
      state.debugAnimatedSlotHeightForLine(1)!,
      closeTo(settledLine1ActiveHeight, 0.01),
    );
    expect(
      state.debugAnimatedSlotHeightForLine(2)!,
      closeTo(settledLine2SecondaryHeight, 0.01),
    );

    // Step through the 400ms easeOutCubic upward slide in 50ms (20fps) frames,
    // including a 200ms progressNotifier tick mid-slide, verifying strictly monotonic motion,
    // >= 4 intermediate frames with interpolated font size/color/height/position, and zero overlap!
    double prevLine2Top = line2Frame0.top;
    int intermediateFramesCount = 0;
    final line1StartFont = tester
        .widget<Text>(
          find.byKey(const ValueKey<String>('lyrics_panel_line_text_1')),
        )
        .style!
        .fontSize!;
    final line2StartFont = tester
        .widget<Text>(
          find.byKey(const ValueKey<String>('lyrics_panel_line_text_2')),
        )
        .style!
        .fontSize!;
    final line2StartColor = tester
        .widget<Text>(
          find.byKey(const ValueKey<String>('lyrics_panel_line_text_2')),
        )
        .style!
        .color!;
    final line1StartColor = tester
        .widget<Text>(
          find.byKey(const ValueKey<String>('lyrics_panel_line_text_1')),
        )
        .style!
        .color!;

    for (int step = 1; step <= 8; step++) {
      if (step == 4) {
        // Simulate ~200ms progressNotifier tick mid-travel
        localProvider.handleNativePosition(
          positionMs: 17300,
          durationMs: 180000,
          isPlaying: true,
        );
      }
      await tester.pump(const Duration(milliseconds: 50));
      final curLine2Top = tester
          .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_2')))
          .top;
      final curLine1Font = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_text_1')),
          )
          .style!
          .fontSize!;
      final curLine2Font = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_text_2')),
          )
          .style!
          .fontSize!;
      final curLine2Color = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_text_2')),
          )
          .style!
          .color!;

      // Strictly monotonic upward travel toward stageCenterTop
      expect(curLine2Top, lessThanOrEqualTo(prevLine2Top + 0.01));
      // No frame may show both incoming and outgoing lines at final active typography
      expect(
        curLine1Font >= line1StartFont - 0.05 &&
            curLine2Font >= line1StartFont - 0.05,
        isFalse,
      );

      if (curLine2Top < line2Frame0.top - 1.0 &&
          curLine2Font > line2StartFont + 0.05 &&
          curLine1Font < line1StartFont - 0.05 &&
          curLine2Color != line2StartColor &&
          curLine2Color != line1StartColor) {
        intermediateFramesCount++;
      }

      prevLine2Top = curLine2Top;
    }

    // At rest after 400ms: slide completed cleanly with >= 4 intermediate 20fps frames
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.isPanel0TravelAnimating, isFalse);
    expect(intermediateFramesCount, greaterThanOrEqualTo(4));
    final settledLine2ActiveHeight = state.debugAnimatedSlotHeightForLine(2)!;
    final settledLine1SecondaryHeight =
        state.debugAnimatedSlotHeightForLine(1)!;
    expect(settledLine2ActiveHeight, greaterThan(settledLine2SecondaryHeight));
    expect(settledLine1SecondaryHeight, lessThan(settledLine1ActiveHeight));

    // =========================================================================
    // 2. Document coordinates independent of scroll state & 0.0px handover after manual scroll
    // =========================================================================
    final restLine2Top = tester
        .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_2')))
        .top;
    final restScrollOffset = state.lyricsPanelScrollController.offset;

    // Manually jump scroll controller +30.0px away from targetScrollOffset and trigger a rebuild
    state.lyricsPanelScrollController.jumpTo(restScrollOffset + 30.0);
    localProvider.handleNativePosition(
      positionMs: 17400,
      durationMs: 180000,
      isPlaying: true,
    );
    await tester.pump();

    // Document coordinates do NOT depend on scroll offset -> screenY shifts by exactly -30.0px
    final scrolledLine2Top = tester
        .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_2')))
        .top;
    expect(scrolledLine2Top, closeTo(restLine2Top - 30.0, 1e-4));

    final scrolledLine2Row0 = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_2_row_0')),
    );

    // Handover from settled Panel 0 (at non-target scroll offset) into Morph (t = 1.0) is 0.0px!
    state.debugRenderMorphAtSettledEndpoints = true;
    state.debugSetPanelProgress(0.0);
    await tester.pump();

    final morphFromScrolledLine2Row0 = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_2_row_0')),
    );
    expect(
      morphFromScrolledLine2Row0.left,
      closeTo(scrolledLine2Row0.left, 1e-4),
    );
    expect(
      morphFromScrolledLine2Row0.top,
      closeTo(scrolledLine2Row0.top, 1e-4),
    );
    state.debugRenderMorphAtSettledEndpoints = false;
  });

  testWidgets(
      'Document-level Romaji conversion converts entire lyric list (including line 40 while line 2 plays), invalidates Panel 0 & Home metrics caches by displayed text, and toggles off immediately',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(392, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final testRomajiService = _OfflineTestRomajiService();
    final localProvider = LocalMusicProvider(romajiService: testRomajiService);
    final downloaderProvider = DownloaderProvider(
      romajiService: testRomajiService,
    );

    // Build a 45-line synced Japanese (Kanji + Kana) LRC document (lines 0..44)
    final lrcBuffer = StringBuffer();
    for (int i = 0; i < 45; i++) {
      final totalSec = (i + 1) * 3;
      final mm = (totalSec ~/ 60).toString().padLeft(2, '0');
      final ss = (totalSec % 60).toString().padLeft(2, '0');
      lrcBuffer.writeln('[$mm:$ss.00] 夢の旅路 星空の約束 ライン$i');
    }
    final jpSong = LocalSong(
      filePath: '/storage/emulated/0/Music/Music Japan/YumeNoTabiji.mp3',
      fileName: 'YumeNoTabiji.mp3',
      folderName: 'Music Japan',
      title: '夢の旅路',
      artist: '星空の約束',
      album: 'Music Japan',
      year: '2026',
      durationMs: 180000,
      sizeBytes: 4096000,
      bitrateKbps: 320,
      sampleRateHz: 44100,
      usltLyrics: lrcBuffer.toString().trim(),
    );
    final enSong = _mockSong(
      99,
      lyrics: '[00:05.00] English line zero\n[00:10.00] English line one',
      folderName: 'Pop',
    );

    localProvider.seedSongsForTesting([jpSong, enSong]);
    await localProvider.playSong(jpSong, queueContext: [jpSong, enSong]);
    await localProvider.togglePlayPause(); // Pause disc ticker for pumpAndSettle

    // Playback is at line 2 (9500ms -> line 2 timestamp is 00:09.00)
    localProvider.handleNativePosition(
      positionMs: 9500,
      durationMs: 180000,
      isPlaying: false,
    );

    final npKey = GlobalKey<NowPlayingViewState>();
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
          theme: ThemeData.light().copyWith(
            extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
          ),
          home: Scaffold(
            body: NowPlayingView(
              key: npKey,
              onNavigateToDownloader: () {},
              onNavigateToFolders: () {},
              onMoveLocalSongFolder: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    final state = npKey.currentState!;

    // 1. Initially in Kanji on both Home (p = 1.0) and Settled Lyrics Panel (p = 0.0)
    // Visit Panel 0 first so `_cachedPanel0SecondaryMetrics` is populated with Kanji metrics
    state.debugSetPanelProgress(0.0);
    await tester.pumpAndSettle();

    expect(localProvider.isRomajiEnabledForSong(jpSong.filePath), isFalse);
    expect(
      localProvider.syncedLyricsFor(jpSong)[2].text,
      equals('夢の旅路 星空の約束 ライン2'),
    );
    expect(
      localProvider.syncedLyricsFor(jpSong)[40].text,
      equals('夢の旅路 星空の約束 ライン40'),
    );
    expect(
      state.debugPanel0SecondaryMetricsForIndex(40)!.text,
      equals('夢の旅路 星空の約束 ライン40'),
    );

    // 2. Enable Romaji mode while line 2 is playing:
    //    - Converts the ENTIRE 45-line document in ONE transformation (convertCallCount == 1)
    //    - Line 40 (far beyond playhead at line 2) immediately returns Romaji from `syncedLyricsFor`
    //    - Settled Lyrics panel (`p = 0.0`) immediately invalidates cached Kanji row metrics
    //      and renders Romaji for line 2 AND line 40 (even when scrolling to bottom before line 40 plays)
    final okOn = await localProvider.setRomajiForSong(
      jpSong,
      true,
      includeMetadata: true,
      persistToFile: false,
    );
    expect(okOn, isTrue);
    expect(localProvider.isRomajiEnabledForSong(jpSong.filePath), isTrue);
    expect(testRomajiService.convertCallCount, equals(1));

    await tester.pumpAndSettle();

    final convertedEntries = localProvider.syncedLyricsFor(jpSong);
    expect(convertedEntries.length, equals(45));
    expect(
      convertedEntries[2].text,
      equals('Yume no tabiji Hoshizora no yakusoku rain 2'),
    );
    expect(
      convertedEntries[40].text,
      equals('Yume no tabiji Hoshizora no yakusoku rain 40'),
    );
    for (int i = 0; i < 45; i++) {
      expect(RomajiService.containsJapanese(convertedEntries[i].text), isFalse);
      expect(
        state.debugPanel0SecondaryMetricsForIndex(i)!.text,
        equals('Yume no tabiji Hoshizora no yakusoku rain $i'),
      );
      expect(
        RomajiService.containsJapanese(
          state.debugPanel0SecondaryMetricsForIndex(i)!.rows.first.text,
        ),
        isFalse,
      );
    }

    // Scroll to the very bottom of the Lyrics panel BEFORE line 40 plays:
    // Every line (including line 40 and line 44) already renders Romaji in the widget tree!
    state.lyricsPanelScrollController.jumpTo(
      state.lyricsPanelScrollController.position.maxScrollExtent,
    );
    await tester.pump();

    final line40TextWidget = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyrics_panel_line_text_40')),
    );
    final line44TextWidget = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyrics_panel_line_text_44')),
    );
    expect(
      line40TextWidget.data,
      contains('Yume no tabiji'),
    );
    expect(RomajiService.containsJapanese(line40TextWidget.data!), isFalse);
    expect(
      line44TextWidget.data,
      contains('Yume no tabiji'),
    );
    expect(RomajiService.containsJapanese(line44TextWidget.data!), isFalse);

    // Check Home panel (p = 1.0) agrees on the exact same Romaji script for line 2
    state.debugSetPanelProgress(1.0);
    await tester.pumpAndSettle();
    final homeActiveRow0 = tester.widget<Text>(
      find.byKey(
        const ValueKey<String>(
          'lyric_line_active_2_Yume no tabiji Hoshizora no yakusoku rain 2',
        ),
      ),
    );
    expect(homeActiveRow0.data, contains('Yume no'));
    expect(RomajiService.containsJapanese(homeActiveRow0.data!), isFalse);
    expect(
      state.debugActiveMetricsForIndex(2)!.text,
      equals('Yume no tabiji Hoshizora no yakusoku rain 2'),
    );

    // 3. Play through several lines (2 -> 3 -> 4) in Panel 0: no line flips script mid-song,
    //    and no additional conversion calls occur (convertCallCount stays 1)
    state.debugSetPanelProgress(0.0);
    await tester.pumpAndSettle();
    for (final posMs in <int>[12500, 15500]) {
      localProvider.handleNativePosition(
        positionMs: posMs,
        durationMs: 180000,
        isPlaying: false,
      );
      await tester.pumpAndSettle();
      for (int i = 0; i < 45; i++) {
        expect(
          RomajiService.containsJapanese(
            state.debugPanel0SecondaryMetricsForIndex(i)!.rows.first.text,
          ),
          isFalse,
        );
      }
    }
    expect(testRomajiService.convertCallCount, equals(1));

    // 4. Toggle Romaji OFF: the whole 45-line list returns to Kanji at once in both panels
    final okOff = await localProvider.setRomajiForSong(
      jpSong,
      false,
      includeMetadata: true,
      persistToFile: false,
    );
    expect(okOff, isTrue);
    expect(localProvider.isRomajiEnabledForSong(jpSong.filePath), isFalse);
    await tester.pumpAndSettle();

    final restoredEntries = localProvider.syncedLyricsFor(jpSong);
    expect(restoredEntries[2].text, equals('夢の旅路 星空の約束 ライン2'));
    expect(restoredEntries[40].text, equals('夢の旅路 星空の約束 ライン40'));
    for (int i = 0; i < 45; i++) {
      expect(
        state.debugPanel0SecondaryMetricsForIndex(i)!.text,
        equals('夢の旅路 星空の約束 ライン$i'),
      );
    }

    final restoredLine40Widget = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyrics_panel_line_text_40')),
    );
    expect(restoredLine40Widget.data, contains('夢の旅路'));

    state.debugSetPanelProgress(1.0);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('lyric_line_active_4_夢の旅路 星空の約束 ライン4'),
      ),
      findsOneWidget,
    );

    // 5. Re-enabling Romaji uses the cached document without re-running conversion
    await localProvider.setRomajiForSong(jpSong, true);
    await tester.pumpAndSettle();
    expect(testRomajiService.convertCallCount, equals(1));
    expect(
      localProvider.syncedLyricsFor(jpSong)[40].text,
      equals('Yume no tabiji Hoshizora no yakusoku rain 40'),
    );

    // 6. Non-Japanese song is unaffected
    expect(
      localProvider.syncedLyricsFor(enSong)[0].text,
      equals('English line zero'),
    );
  });

  testWidgets(
      'Combined A+B+C: (A) Fixed Home disc framing (0.95x diameter, 0.60x left) & identical column width across short/long songs, (B) 22->20->18 active vs 13.5 Home / 14.5 Panel 0 secondary (>=1.55x contrast), and (C) 400ms animated line change during morph (0 < p < 1) with retargeting and seamless settle handover to p = 1 & p = 0',
      (WidgetTester tester) async {
    final localProvider = LocalMusicProvider();
    final downloaderProvider = DownloaderProvider();
    addTearDown(localProvider.dispose);
    addTearDown(downloaderProvider.dispose);

    final shortSong = _mockSong(
      1,
      lyrics: '[00:01.00] Line zero\n'
          '[00:05.00] Line one\n'
          '[00:09.00] Line two\n'
          '[00:13.00] Line three\n'
          '[00:17.00] Line four',
    );
    final longSong = _mockSong(
      2,
      lyrics: '[00:01.00] Intro\n'
          '[00:05.00] Daremo karemo kizukanai uchi ni kokoro ubawareru kanpeki de usotsuki na kimi wa tensai teki na aidoru sama\n'
          '[00:10.00] Outro',
    );

    localProvider.seedSongsForTesting([shortSong, longSong]);
    await localProvider.playSong(
      shortSong,
      queueContext: [shortSong, longSong],
    );
    await localProvider.togglePlayPause();

    final npKey = GlobalKey<NowPlayingViewState>();
    const screenW = 390.0;
    const screenH = 844.0;
    await tester.binding.setSurfaceSize(const Size(screenW, screenH));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          theme: ThemeData.light().copyWith(
            extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
          ),
          home: Scaffold(
            body: NowPlayingView(
              key: npKey,
              onNavigateToDownloader: () {},
              onNavigateToFolders: () {},
              onMoveLocalSongFolder: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    final state = npKey.currentState!;
    final discFinder = find.byKey(
      const ValueKey<String>('now_playing_single_shared_disc'),
    );

    // =========================================================================
    // SECTION A: Fixed Home disc framing (0.95x diameter, 0.60x left edge) &
    // identical standard Home column width for short-line and long-line songs
    // =========================================================================
    localProvider.handleNativePosition(
      positionMs: 5500,
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pumpAndSettle();

    final shortDiscRect = tester.getRect(discFinder);
    final shortColWidth = tester
        .getSize(find.byKey(const ValueKey<String>('lyric_slot_active')))
        .width;
    expect(shortDiscRect.width, closeTo(screenW * 0.95, 0.01));
    expect(shortDiscRect.left, closeTo(screenW * 0.60, 0.01));
    expect(
      shortColWidth,
      closeTo(NowPlayingView.computeStandardHomeColumnWidth(screenW), 0.01),
    );

    // Switch to longSong and advance to the very long Romaji line ->
    // zero disc position/size jump and identical Home column width!
    await localProvider.playSong(
      longSong,
      queueContext: [shortSong, longSong],
    );
    await localProvider.togglePlayPause();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 950));
    localProvider.handleNativePosition(
      positionMs: 5500,
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pumpAndSettle();

    final longDiscRect = tester.getRect(discFinder);
    final longColWidth = tester
        .getSize(find.byKey(const ValueKey<String>('lyric_slot_active')))
        .width;
    expect(longDiscRect, equals(shortDiscRect));
    expect(longColWidth, closeTo(shortColWidth, 0.001));

    // =========================================================================
    // SECTION B: Lyric size contrast (22 -> 20 -> 18 active vs 13.5 Home & 14.5 Panel 0)
    // =========================================================================
    // Long active line on Home stepped down to 18.0 (floor), while Home prev/next use 13.5
    final longHomeActiveText = tester.widget<Text>(
      find.byKey(
        const ValueKey<String>(
          'lyric_line_active_1_Daremo karemo kizukanai uchi ni kokoro ubawareru kanpeki de usotsuki na kimi wa tensai teki na aidoru sama',
        ),
      ),
    );
    final longHomePrevText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyric_line_previous')),
    );
    final longHomeNextText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyric_line_next')),
    );
    expect(longHomeActiveText.style!.fontSize, closeTo(18.0, 0.001));
    expect(longHomePrevText.style!.fontSize, closeTo(13.5, 0.001));
    expect(longHomeNextText.style!.fontSize, closeTo(13.5, 0.001));

    // Switch back to shortSong -> short active line on Home uses 22.0 (22.0 / 13.5 = 1.63x >= 1.55x)
    await localProvider.playSong(
      shortSong,
      queueContext: [shortSong, longSong],
    );
    await localProvider.togglePlayPause();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 950));
    localProvider.handleNativePosition(
      positionMs: 5500, // line 1 ("Line one")
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pumpAndSettle();

    final shortHomeActiveText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyric_line_active_1_Line one')),
    );
    final shortHomePrevText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyric_line_previous')),
    );
    expect(shortHomeActiveText.style!.fontSize, closeTo(22.0, 0.001));
    expect(shortHomePrevText.style!.fontSize, closeTo(13.5, 0.001));
    expect(
      shortHomeActiveText.style!.fontSize! / shortHomePrevText.style!.fontSize!,
      greaterThanOrEqualTo(1.55),
    );

    // On Lyrics Panel (p = 0.0): active line 1 uses 22.0, while inactive lines KEEP 14.5
    state.debugSetPanelProgress(0.0);
    await tester.pumpAndSettle();
    final panel0ActiveText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyrics_panel_line_text_1')),
    );
    final panel0InactiveText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyrics_panel_line_text_0')),
    );
    expect(panel0ActiveText.style!.fontSize, closeTo(22.0, 0.001));
    expect(panel0InactiveText.style!.fontSize, closeTo(14.5, 0.001));

    // =========================================================================
    // SECTION C: Line-Change Animation During the Morph (0 < p < 1),
    // Composition with p, Mid-Animation Retargeting, and Seamless Settle Handover
    // =========================================================================
    // 1. Hold p = 0.5 (t = 0.5) at active line 1 (5500ms)
    state.debugSetPanelProgress(0.5);
    await tester.pump();
    final midSecFontSize = NowPlayingView.computeMorphSecondaryFontSize(0.5);
    expect(midSecFontSize, closeTo(14.0, 0.001));

    final line1TopBefore = state.debugLiveTopForLine(1)!;
    final line2TopBefore = state.debugLiveTopForLine(2)!;
    final line1FontBefore = state.debugLiveFontSizeForLine(1)!;
    final line2FontBefore = state.debugLiveFontSizeForLine(2)!;
    expect(line1FontBefore, closeTo(22.0, 0.001));
    expect(line2FontBefore, closeTo(14.0, 0.001));
    expect(line2TopBefore, greaterThan(line1TopBefore));

    // Trigger natural step 1 -> 2 while p = 0.5!
    localProvider.handleNativePosition(
      positionMs: 9500, // line 2 ("Line two")
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pump(); // Frame 0 of 400ms line-change animation (u = 0.0)
    expect(state.isLyricSlideAnimating, isTrue);

    // On Frame 0 (u = 0.0): zero instant jump! Line 1 and Line 2 start at their exact pre-step positions & sizes,
    // and outgoing top line 0 (`morph_lyric_slot_0`) is present so it can slide up and fade out smoothly.
    expect(state.debugLiveTopForLine(1)!, closeTo(line1TopBefore, 0.01));
    expect(state.debugLiveTopForLine(2)!, closeTo(line2TopBefore, 0.01));
    expect(state.debugLiveFontSizeForLine(1)!, closeTo(22.0, 0.01));
    expect(state.debugLiveFontSizeForLine(2)!, closeTo(14.0, 0.01));
    expect(
      find.byKey(const ValueKey<String>('morph_lyric_slot_0')),
      findsOneWidget,
    );

    // Advance 120ms into the 400ms animation -> intermediate positions and intermediate font sizes!
    await tester.pump(const Duration(milliseconds: 120));
    expect(state.isLyricSlideAnimating, isTrue);
    final line1TopMid = state.debugLiveTopForLine(1)!;
    final line2TopMid = state.debugLiveTopForLine(2)!;
    final line1FontMid = state.debugLiveFontSizeForLine(1)!;
    final line2FontMid = state.debugLiveFontSizeForLine(2)!;
    expect(line1TopMid, lessThan(line1TopBefore));
    expect(line2TopMid, lessThan(line2TopBefore));
    expect(line2TopMid, greaterThan(line1TopBefore));
    expect(line1FontMid, lessThan(22.0));
    expect(line1FontMid, greaterThan(14.0));
    expect(line2FontMid, greaterThan(14.0));
    expect(line2FontMid, lessThan(22.0));

    // Verify composition with p: dragging p from 0.5 -> 0.35 DURING the line animation
    // updates containerWidth and disc position immediately without cancelling or freezing the line animation!
    final morphContainerFinder = find.byKey(
      const ValueKey<String>('now_playing_lyrics_morph_container'),
    );
    final widthAtP05 = tester.getSize(morphContainerFinder).width;
    final discLeftAtP05 = tester.getRect(discFinder).left;
    state.debugSetPanelProgress(0.35);
    await tester.pump(const Duration(milliseconds: 40));
    expect(state.isLyricSlideAnimating, isTrue);
    expect(
      tester.getSize(morphContainerFinder).width,
      greaterThan(widthAtP05),
    );
    expect(tester.getRect(discFinder).left, greaterThan(discLeftAtP05));

    // 2. Quick successive line change (2 -> 3) while 1 -> 2 is STILL animating at p = 0.35:
    // Retargets from the current interpolated state with 0.0px / 0.0pt jump on Frame 0!
    final line2TopBeforeRetarget = state.debugLiveTopForLine(2)!;
    final line2FontBeforeRetarget = state.debugLiveFontSizeForLine(2)!;
    final line3TopBeforeRetarget = state.debugLiveTopForLine(3)!;
    final line3FontBeforeRetarget = state.debugLiveFontSizeForLine(3)!;

    localProvider.handleNativePosition(
      positionMs: 13500, // line 3 ("Line three")
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pump(); // Frame 0 of retargeted 2 -> 3 animation
    expect(state.isLyricSlideAnimating, isTrue);
    expect(
      state.debugLiveTopForLine(2)!,
      closeTo(line2TopBeforeRetarget, 0.01),
    );
    expect(
      state.debugLiveFontSizeForLine(2)!,
      closeTo(line2FontBeforeRetarget, 0.01),
    );
    expect(
      state.debugLiveTopForLine(3)!,
      closeTo(line3TopBeforeRetarget, 0.01),
    );
    expect(
      state.debugLiveFontSizeForLine(3)!,
      closeTo(line3FontBeforeRetarget, 0.01),
    );

    // 3. Handover mid-line-animation to settled Home (p = 1.0):
    // Advance 140ms into the 2 -> 3 animation, then settle p = 1.0 ->
    // Settled Home continues the exact same animation seamlessly (zero jump, no restart)!
    await tester.pump(const Duration(milliseconds: 140));
    expect(state.isLyricSlideAnimating, isTrue);
    state.debugRenderMorphAtSettledEndpoints = true;
    state.debugSetPanelProgress(1.0);
    await tester.pump();
    final morphT0Line2RectAtHandover = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_slot_2')),
    );
    final morphT0Line3RectAtHandover = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_slot_3')),
    );
    final morphT0Line3FontAtHandover = state.debugLiveFontSizeForLine(3)!;

    state.debugRenderMorphAtSettledEndpoints = false;
    state.debugSetPanelProgress(1.0); // settled Home takes over mid-slide!
    await tester.pump();
    expect(state.isLyricSlideAnimating, isTrue);
    final homePrevRectAtHandover = tester.getRect(
      find.byKey(const ValueKey<String>('lyric_slot_previous')),
    );
    final homeActiveRectAtHandover = tester.getRect(
      find.byKey(const ValueKey<String>('lyric_slot_active')),
    );
    final homeActiveTextAtHandover = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyric_line_active_3_Line three')),
    );
    expect(
      homePrevRectAtHandover.top,
      closeTo(morphT0Line2RectAtHandover.top, 0.01),
    );
    expect(
      homeActiveRectAtHandover.top,
      closeTo(morphT0Line3RectAtHandover.top, 0.01),
    );
    expect(
      homeActiveTextAtHandover.style!.fontSize,
      closeTo(morphT0Line3FontAtHandover, 0.01),
    );

    // Let the handover animation finish on settled Home
    await tester.pumpAndSettle();
    expect(state.isLyricSlideAnimating, isFalse);
    final homeActiveTextSettled = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyric_line_active_3_Line three')),
    );
    expect(homeActiveTextSettled.style!.fontSize, closeTo(22.0, 0.001));

    // 4. Handover mid-line-animation to settled Lyrics Panel (p = 0.0):
    // Move to p = 0.2, trigger step 3 -> 4, advance 150ms, then settle p = 0.0 ->
    // Settled Lyrics Panel continues the exact same animation seamlessly with 0.0px / 0.0pt jump!
    state.debugSetPanelProgress(0.2);
    await tester.pump();
    localProvider.handleNativePosition(
      positionMs: 17500, // line 4 ("Line four")
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(state.isLyricSlideAnimating, isTrue);

    state.debugRenderMorphAtSettledEndpoints = true;
    state.debugSetPanelProgress(0.0);
    await tester.pump();
    final morphT1Line3RectAtHandover = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_slot_3')),
    );
    final morphT1Line4RectAtHandover = tester.getRect(
      find.byKey(const ValueKey<String>('morph_lyric_slot_4')),
    );
    final morphT1Line4FontAtHandover = state.debugLiveFontSizeForLine(4)!;

    state.debugRenderMorphAtSettledEndpoints = false;
    state.debugSetPanelProgress(0.0); // settled Panel 0 takes over mid-slide!
    await tester.pump();
    expect(state.isLyricSlideAnimating, isTrue);
    final stageLine3RectAtHandover = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_3')),
    );
    final stageLine4RectAtHandover = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_4')),
    );
    final stageLine4TextAtHandover = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyrics_panel_line_text_4')),
    );
    expect(
      stageLine3RectAtHandover.top,
      closeTo(morphT1Line3RectAtHandover.top, 0.01),
    );
    expect(
      stageLine4RectAtHandover.top,
      closeTo(morphT1Line4RectAtHandover.top, 0.01),
    );
    expect(
      stageLine4TextAtHandover.style!.fontSize,
      closeTo(morphT1Line4FontAtHandover, 0.01),
    );

    await tester.pumpAndSettle();
    expect(state.isLyricSlideAnimating, isFalse);
    final stageLine4TextSettled = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyrics_panel_line_text_4')),
    );
    expect(stageLine4TextSettled.style!.fontSize, closeTo(22.0, 0.001));
  });

  testWidgets(
      'Stage Mode for Settled Lyrics Panel (p = 0) & 1.2x Lyric Line-Height Pitch: Rest mode (distance > 1 opacity 0, identical slot heights), Explore mode (ladder opacities), 4s single return motion with countdown/mid-return touch cancellation, line change in Rest mode, and 1.2x two-row pitch',
      (WidgetTester tester) async {
    final localProvider = LocalMusicProvider();
    final downloaderProvider = DownloaderProvider();
    addTearDown(localProvider.dispose);
    addTearDown(downloaderProvider.dispose);

    // 1. Verify 1.2x lyric line-height pitch across all size steps (22, 20, 18, 14.5, 13.5)
    // and with romaji macrons / descenders ("Yūgure no sora o miagete gypj")
    expect(MusEveePalette.lyricLineHeight, 1.2);
    for (final size in <double>[
      MusEveePalette.lyricActiveMaxFontSize, // 22.0
      MusEveePalette.lyricActiveMidFontSize, // 20.0
      MusEveePalette.lyricActiveMinFontSize, // 18.0
      MusEveePalette.lyricPanelSecondaryFontSize, // 14.5
      MusEveePalette.lyricSecondaryFontSize, // 13.5
    ]) {
      final isAct = size >= MusEveePalette.lyricActiveMinFontSize;
      final twoRowMetrics = NowPlayingView.measureLyricLineAtWidth(
        'Yūgure no sora o miagete hōkiboshi gypj',
        containerWidth: 160.0,
        fontSize: size,
        isActiveRole: isAct,
      );
      expect(twoRowMetrics.lineHeight, 1.2);
      expect(twoRowMetrics.wrappedLineCount, greaterThanOrEqualTo(2));
      final rowPitch =
          twoRowMetrics.rows[1].localTop - twoRowMetrics.rows[0].localTop;
      expect(rowPitch, closeTo(1.2 * size, 1e-4));
      expect(twoRowMetrics.rows[0].height, closeTo(1.2 * size, 1e-4));
    }

    final stageSong = _mockSong(
      1,
      lyrics: '[00:05.00] Line Zero Intro Opening\n'
          '[00:10.00] Line One Neighbor Above\n'
          '[00:15.00] Yūgure no sora o miagete hōkiboshi\n'
          '[00:20.00] Line Three Neighbor Below\n'
          '[00:25.00] Line Four Distance Two\n'
          '[00:30.00] Line Five Distance Three\n'
          '[00:35.00] Line Six Distance Four',
    );

    localProvider.seedSongsForTesting([stageSong]);
    await localProvider.playSong(stageSong, queueContext: [stageSong]);
    await localProvider.togglePlayPause();

    final npKey = GlobalKey<NowPlayingViewState>();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          devicePixelRatio: 1.0,
        ),
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<LocalMusicProvider>.value(
              value: localProvider,
            ),
            ChangeNotifierProvider<DownloaderProvider>.value(
              value: downloaderProvider,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
            ),
            home: Scaffold(
              body: NowPlayingView(
                key: npKey,
                onNavigateToDownloader: () {},
                onNavigateToFolders: () {},
                onMoveLocalSongFolder: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();

    final state = npKey.currentState!;

    // 2. Verify two-row rendered lyric line pitch on Home (p = 1.0) equals 1.2 * fontSize
    localProvider.handleNativePosition(
      positionMs: 16000, // Line 2 ("Yūgure no sora o miagete hōkiboshi") active
      durationMs: 180000,
      isPlaying: false,
    );
    await tester.pumpAndSettle();
    final homeRow0Rect = tester.getRect(
      find.byKey(const ValueKey<String>('home_lyric_active_row_0')),
    );
    final homeRow1Rect = tester.getRect(
      find.byKey(const ValueKey<String>('home_lyric_active_row_1')),
    );
    final homeActiveText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('home_lyric_active_row_text_1')),
    );
    expect(homeActiveText.style!.height, closeTo(1.2, 1e-4));
    expect(
      homeRow1Rect.top - homeRow0Rect.top,
      closeTo(1.2 * homeActiveText.style!.fontSize!, 0.01),
    );

    // 3. Arrive at Panel 0 (p = 0.0) -> settles in REST mode
    state.debugSetPanelProgress(0.0);
    await tester.pumpAndSettle();
    expect(state.isLyricsPanelInExploreMode, isFalse);
    expect(state.lyricsPanelExploreBlend, closeTo(0.0, 1e-4));

    // Verify two-row rendered lyric line pitch on Panel 0 also equals 1.2 * fontSize
    final panelRow0Rect = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_2_row_0')),
    );
    final panelRow1Rect = tester.getRect(
      find.byKey(const ValueKey<String>('lyrics_panel_line_2_row_1')),
    );
    final panelActiveText = tester.widget<Text>(
      find.byKey(const ValueKey<String>('lyrics_panel_line_text_2')),
    );
    expect(panelActiveText.style!.height, closeTo(1.2, 1e-4));
    expect(
      panelRow1Rect.top - panelRow0Rect.top,
      closeTo(1.2 * panelActiveText.style!.fontSize!, 0.01),
    );

    // Record all slot heights and positions in Rest mode (active = 2)
    final restSlotRects = List<Rect>.generate(
      7,
      (i) => tester.getRect(
        find.byKey(ValueKey<String>('lyrics_panel_line_$i')),
      ),
    );

    double lineOpacity(int i) => tester
        .widget<AnimatedOpacity>(
          find.byKey(ValueKey<String>('lyrics_panel_line_opacity_$i')),
        )
        .opacity;

    bool isLineIgnoringPointer(int i) => tester
        .widget<IgnorePointer>(
          find.byKey(ValueKey<String>('lyrics_panel_line_pointer_$i')),
        )
        .ignoring;

    // In Rest mode (active = 2): lines 1, 2, 3 are visible (0.90, 1.0, 0.90) & tappable;
    // lines 0, 4, 5, 6 (distance > 1) have opacity EXACTLY 0.0 & IgnorePointer == true
    expect(lineOpacity(2), 1.0);
    expect(lineOpacity(1), 0.90);
    expect(lineOpacity(3), 0.90);
    expect(lineOpacity(0), 0.0);
    expect(lineOpacity(4), 0.0);
    expect(lineOpacity(5), 0.0);
    expect(lineOpacity(6), 0.0);
    expect(isLineIgnoringPointer(1), isFalse);
    expect(isLineIgnoringPointer(2), isFalse);
    expect(isLineIgnoringPointer(3), isFalse);
    expect(isLineIgnoringPointer(0), isTrue);
    expect(isLineIgnoringPointer(4), isTrue);
    expect(isLineIgnoringPointer(5), isTrue);

    // Tapping an invisible distant line (line 5, 30000ms) in Rest mode is ignored
    await tester.tap(
      find.byKey(const ValueKey<String>('lyrics_panel_line_5')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(localProvider.positionMs, 16000);
    expect(state.isLyricsPanelInExploreMode, isFalse);

    // 4. Line change while in Rest mode (2 -> 3 at 20500ms):
    // stays in Rest mode, distant lines never flash > 0.0
    localProvider.handleNativePosition(
      positionMs: 20500,
      durationMs: 180000,
      isPlaying: true,
    );
    await tester.pump();
    expect(state.isLyricsPanelInExploreMode, isFalse);
    expect(lineOpacity(0), 0.0);
    expect(lineOpacity(1), 0.0);
    expect(lineOpacity(5), 0.0);
    expect(lineOpacity(6), 0.0);
    await tester.pump(const Duration(milliseconds: 150));
    expect(state.isLyricsPanelInExploreMode, isFalse);
    expect(lineOpacity(0), 0.0);
    expect(lineOpacity(1), 0.0);
    expect(lineOpacity(5), 0.0);
    await tester.pump(const Duration(milliseconds: 200));

    // Seek back to line 2 (16000ms) via tap on visible neighbor line 2 in Rest mode -> stays in Rest mode
    await localProvider.togglePlayPause(); // pause ticker
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(
      find.byKey(const ValueKey<String>('lyrics_panel_line_2')),
    );
    await tester.pumpAndSettle();
    expect(localProvider.positionMs, 15000);
    expect(state.isLyricsPanelInExploreMode, isFalse);

    // 5. Enter Explore mode via user drag -> restores ladder opacities immediately,
    // and slot heights in Explore mode equal Rest mode slot heights (zero layout shift!)
    await tester.drag(
      find.byKey(const ValueKey<String>('lyrics_panel_scroll_view')),
      const Offset(0, -60),
    );
    await tester.pump();
    expect(state.isLyricsPanelInExploreMode, isTrue);
    expect(state.lyricsPanelExploreBlend, closeTo(1.0, 1e-4));
    expect(lineOpacity(2), 1.0);
    expect(lineOpacity(1), 0.90);
    expect(lineOpacity(3), 0.90);
    expect(lineOpacity(0), 0.65);
    expect(lineOpacity(4), 0.65);
    expect(lineOpacity(5), 0.45);
    expect(lineOpacity(6), 0.45);
    expect(isLineIgnoringPointer(5), isFalse);

    // Every single line's slot height and width in Explore mode is identical to Rest mode
    for (int i = 0; i < 7; i++) {
      final exploreRect = tester.getRect(
        find.byKey(ValueKey<String>('lyrics_panel_line_$i')),
      );
      expect(exploreRect.height, closeTo(restSlotRects[i].height, 1e-4));
      expect(exploreRect.width, closeTo(restSlotRects[i].width, 1e-4));
    }

    // 6. Countdown cancellation on touch: wait 2.5s (< 4s), then touch/drag -> does NOT return at 4.0s total
    await tester.pump(const Duration(milliseconds: 2500));
    expect(state.isLyricsPanelInExploreMode, isTrue);
    expect(lineOpacity(5), 0.45);

    // Touch during countdown restarts the 4s timer
    await tester.drag(
      find.byKey(const ValueKey<String>('lyrics_panel_scroll_view')),
      const Offset(0, -20),
    );
    await tester.pump();
    // 2.0s after the second touch (4.5s total since first scroll, but only 2.0s idle): still in Explore mode!
    await tester.pump(const Duration(milliseconds: 2000));
    expect(state.isLyricsPanelInExploreMode, isTrue);
    expect(state.isLyricsPanelReturningToRest, isFalse);
    expect(lineOpacity(5), 0.45);

    // 7. After full 4.0s idle (pump remaining 2050ms), the 300ms single return motion starts:
    // scroll glides back toward center AND distant lines fade toward 0.0 simultaneously!
    final scrollBeforeReturn = state.lyricsPanelScrollController.offset;
    await tester.pump(const Duration(milliseconds: 2050));
    expect(state.isLyricsPanelReturningToRest, isTrue);

    // Advance 120ms into the 300ms return animation: both scroll and distant opacity are mid-flight
    await tester.pump(const Duration(milliseconds: 120));
    expect(state.isLyricsPanelReturningToRest, isTrue);
    final midReturnScroll = state.lyricsPanelScrollController.offset;
    final midReturnOp5 = lineOpacity(5);
    expect(midReturnScroll, lessThan(scrollBeforeReturn));
    expect(midReturnOp5, lessThan(0.45));
    expect(midReturnOp5, greaterThan(0.0));

    // 8. Touch DURING the 300ms return animation cancels the return immediately
    // and re-enters Explore mode at the current scroll position (no jump, no snap!)
    final TestGesture interruptGesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey<String>('lyrics_panel_scroll_view')),
      ),
    );
    await tester.pump();
    expect(state.isLyricsPanelReturningToRest, isFalse);
    expect(state.isLyricsPanelInExploreMode, isTrue);
    expect(lineOpacity(5), 0.45);
    expect(
      state.lyricsPanelScrollController.offset,
      closeTo(midReturnScroll, 0.01),
    );
    await interruptGesture.up();
    await tester.pump();

    // 9. Let the full 4s countdown + 300ms return complete untouched -> back in Rest mode (opacity 0.0)
    await tester.pump(
      const Duration(
        seconds: MusEveePalette.lyricsManualScrollResumeDelaySeconds,
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(state.isLyricsPanelReturningToRest, isFalse);
    expect(state.isLyricsPanelInExploreMode, isFalse);
    expect(lineOpacity(0), 0.0);
    expect(lineOpacity(4), 0.0);
    expect(lineOpacity(5), 0.0);
    expect(lineOpacity(6), 0.0);
    expect(lineOpacity(2), 1.0);
    expect(lineOpacity(1), 0.90);
    expect(lineOpacity(3), 0.90);
  });

  testWidgets(
    'MusEvee Phase 1.9: Intro Stack (C), Promotion/Demotion (C), Plain-Lyrics (D), Home Gesture Rule (E), Panel Line-Change Glide + No-Overlap (A) & Arrival Directly in Rest (B)',
    (WidgetTester tester) async {
      final localProvider = LocalMusicProvider();
      final downloaderProvider = DownloaderProvider();
      addTearDown(localProvider.dispose);
      addTearDown(downloaderProvider.dispose);

      final syncedSong = _mockSong(
        1,
        lyrics: '[00:10.00] First intro line wrapping across the stage now\n'
            '[00:15.00] Second intro line waiting in the middle slot\n'
            '[00:20.00] Third intro line resting in the bottom slot\n'
            '[00:25.00] Fourth verse line ready to glide in cleanly\n'
            '[00:30.00] Fifth verse line with extra words so active wraps two rows\n'
            '[00:35.00] Sixth verse line following behind\n'
            '[00:40.00] Seventh verse line at the tail',
      );

      final plainSong = _mockSong(
        2,
        lyrics: 'Plain opening line in top slot\n'
            'Plain second line in middle slot\n'
            'Plain third line in bottom slot\n'
            'Plain fourth line in panel list\n'
            'Plain fifth line in panel list\n'
            'Plain sixth line in panel list\n'
            'Plain seventh line in panel list\n'
            'Plain eighth line in panel list\n'
            'Plain ninth line in panel list\n'
            'Plain tenth line in panel list\n'
            'Plain eleventh line in panel list\n'
            'Plain twelfth line in panel list\n'
            'Plain thirteenth line in panel list\n'
            'Plain fourteenth line in panel list\n'
            'Plain fifteenth line in panel list',
      );

      localProvider.seedSongsForTesting([syncedSong, plainSong]);
      await localProvider.playSong(
        syncedSong,
        queueContext: [syncedSong, plainSong],
      );
      await localProvider.togglePlayPause();

      // Start before first lyric timestamp (3000ms < 10000ms -> effectiveIdx == -1)
      localProvider.handleNativePosition(
        positionMs: 3000,
        durationMs: 240000,
        isPlaying: false,
      );

      final npKey = GlobalKey<NowPlayingViewState>();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            devicePixelRatio: 1.0,
          ),
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<LocalMusicProvider>.value(
                value: localProvider,
              ),
              ChangeNotifierProvider<DownloaderProvider>.value(
                value: downloaderProvider,
              ),
            ],
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: const <ThemeExtension<dynamic>>[
                  MusEveePalette.light,
                ],
              ),
              home: Scaffold(
                body: NowPlayingView(
                  key: npKey,
                  onNavigateToDownloader: () {},
                  onNavigateToFolders: () {},
                  onMoveLocalSongFolder: (_) async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pumpAndSettle();

      final state = npKey.currentState!;
      const palette = MusEveePalette.light;

      // =======================================================================
      // (a) Intro stack on Home (effectiveIdx == -1)
      // =======================================================================
      expect(state.currentPanelProgress, 1.0);
      final prevSlotFinder = find.byKey(
        const ValueKey<String>('lyric_slot_previous'),
      );
      final midSlotFinder = find.byKey(
        const ValueKey<String>('lyric_slot_active'),
      );
      final nextSlotFinder = find.byKey(
        const ValueKey<String>('lyric_slot_next'),
      );
      final line0Finder = find.byKey(
        const ValueKey<String>(
          'lyric_line_upcoming_0_First intro line wrapping across the stage now',
        ),
      );
      final line1Finder = find.byKey(
        const ValueKey<String>(
          'lyric_line_upcoming_1_Second intro line waiting in the middle slot',
        ),
      );
      final line2Finder = find.byKey(
        const ValueKey<String>(
          'lyric_line_upcoming_2_Third intro line resting in the bottom slot',
        ),
      );
      expect(line0Finder, findsOneWidget);
      expect(line1Finder, findsOneWidget);
      expect(line2Finder, findsOneWidget);

      // Verify lines 0, 1, 2 sit inside top, middle, and bottom slots respectively
      expect(
        find.descendant(of: prevSlotFinder, matching: line0Finder),
        findsOneWidget,
      );
      expect(
        find.descendant(of: midSlotFinder, matching: line1Finder),
        findsOneWidget,
      );
      expect(
        find.descendant(of: nextSlotFinder, matching: line2Finder),
        findsOneWidget,
      );

      // Verify all three use secondary font size (13.5pt) & secondary color
      for (final f in <Finder>[line0Finder, line1Finder, line2Finder]) {
        final txt = tester.widget<Text>(f);
        expect(
          txt.style!.fontSize,
          closeTo(MusEveePalette.lyricSecondaryFontSize, 0.001),
        );
        expect(txt.style!.color, palette.nowPlayingSecondary);
      }

      // Verify opacity hierarchy 1.0 / 0.72 / 0.48 on the 3 slots
      final topSlotOpacity = tester
          .widget<Opacity>(
            find.ancestor(of: prevSlotFinder, matching: find.byType(Opacity)).first,
          )
          .opacity;
      final midSlotOpacity = tester
          .widget<Opacity>(
            find.ancestor(of: midSlotFinder, matching: find.byType(Opacity)).first,
          )
          .opacity;
      final botSlotOpacity = tester
          .widget<Opacity>(
            find.ancestor(of: nextSlotFinder, matching: find.byType(Opacity)).first,
          )
          .opacity;
      expect(topSlotOpacity, closeTo(MusEveePalette.homeIntroLine0Opacity, 1e-4));
      expect(midSlotOpacity, closeTo(MusEveePalette.homeIntroLine1Opacity, 1e-4));
      expect(botSlotOpacity, closeTo(MusEveePalette.homeIntroLine2Opacity, 1e-4));

      final introLine0TopY = tester.getRect(prevSlotFinder).top;
      final introLine1TopY = tester.getRect(midSlotFinder).top;
      final introLine2TopY = tester.getRect(nextSlotFinder).top;
      expect(introLine0TopY, lessThan(introLine1TopY));
      expect(introLine1TopY, lessThan(introLine2TopY));

      // =======================================================================
      // (e.1) Home tap & long-press in Intro Stack state open the Full Lyrics Sheet and never seek
      // =======================================================================
      await tester.tap(line0Finder);
      await tester.pumpAndSettle();
      expect(localProvider.positionMs, 3000);
      expect(state.currentPanelProgress, closeTo(1.0, 1e-4));
      expect(find.byType(BottomSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(NowPlayingView))).pop();
      await tester.pumpAndSettle();

      await tester.longPress(line1Finder);
      await tester.pumpAndSettle();
      expect(localProvider.positionMs, 3000);
      expect(state.currentPanelProgress, closeTo(1.0, 1e-4));
      expect(find.byType(BottomSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(NowPlayingView))).pop();
      await tester.pumpAndSettle();

      // =======================================================================
      // (b) Promotion (-1 -> 0) sampled mid-transition (~200ms into 400ms)
      // =======================================================================
      localProvider.handleNativePosition(
        positionMs: 10200,
        durationMs: 240000,
        isPlaying: false,
      );
      await tester.pump(); // Frame 0 of Promotion

      final activeLine0Finder = find.byKey(
        const ValueKey<String>(
          'lyric_line_active_0_First intro line wrapping across the stage now',
        ),
      );
      expect(activeLine0Finder, findsOneWidget);

      // Sample across the 400ms Promotion window at 100ms intervals
      double? midPromotionLine0Y;
      double? midPromotionLine0Font;
      double? midPromotionLine1Y;
      for (int step = 1; step <= 3; step++) {
        await tester.pump(const Duration(milliseconds: 100));
        final r0 = tester.getRect(midSlotFinder);
        final r1 = tester.getRect(nextSlotFinder);
        // Non-overlap check between promoting Line 0 and Line 1, and outgoing Line 2
        expect(r0.bottom, lessThanOrEqualTo(r1.top + 0.01));
        final out2Finder = find.byKey(
          const ValueKey<String>('lyric_slot_outgoing_intro_2'),
        );
        if (out2Finder.evaluate().isNotEmpty) {
          final r2 = tester.getRect(out2Finder);
          expect(r1.bottom, lessThanOrEqualTo(r2.top + 0.01));
        }
        if (step == 2) {
          midPromotionLine0Y = r0.top;
          midPromotionLine0Font =
              tester.widget<Text>(activeLine0Finder).style!.fontSize!;
          midPromotionLine1Y = r1.top;
        }
      }

      await tester.pumpAndSettle();
      final settledActiveLine0Y = tester.getRect(midSlotFinder).top;
      final settledActiveLine0Font =
          tester.widget<Text>(activeLine0Finder).style!.fontSize!;
      final settledNextLine1Y = tester.getRect(nextSlotFinder).top;

      // At ~200ms into the 400ms window, Line 0's y and font size were strictly between start and end,
      // and Line 1's y was strictly between middle slot and bottom slot!
      expect(midPromotionLine0Y, greaterThan(introLine0TopY + 1.0));
      expect(midPromotionLine0Y, lessThan(settledActiveLine0Y - 0.5));
      expect(
        midPromotionLine0Font,
        greaterThan(MusEveePalette.lyricSecondaryFontSize + 0.2),
      );
      expect(midPromotionLine0Font, lessThan(settledActiveLine0Font - 0.1));
      expect(midPromotionLine1Y, greaterThan(introLine1TopY + 1.0));
      expect(midPromotionLine1Y, lessThan(settledNextLine1Y - 0.5));

      // At completion: Line 0 is active in middle slot, Line 1 in bottom slot at 1.0, top slot empty
      expect(
        tester.widget<Text>(activeLine0Finder).style!.color,
        palette.nowPlayingPrimary,
      );
      final settledNextOpacity = tester
          .widget<Opacity>(
            find.ancestor(of: nextSlotFinder, matching: find.byType(Opacity)).first,
          )
          .opacity;
      expect(settledNextOpacity, closeTo(1.0, 1e-4));
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('lyric_line_previous')),
            )
            .data,
        isEmpty,
      );

      // =======================================================================
      // (e.2) Home tap in normal active state (tapping all 3 slots) opens Full Lyrics Sheet and never seeks
      // =======================================================================
      localProvider.handleNativePosition(
        positionMs: 16000,
        durationMs: 240000,
        isPlaying: false,
      ); // Active line 1
      await tester.pumpAndSettle();
      expect(localProvider.positionMs, 16000);
      for (final slotText in <Finder>[
        find.byKey(const ValueKey<String>('lyric_line_previous')),
        find.byKey(
          const ValueKey<String>(
            'lyric_line_active_1_Second intro line waiting in the middle slot',
          ),
        ),
        find.byKey(const ValueKey<String>('lyric_line_next')),
      ]) {
        await tester.tap(slotText);
        await tester.pumpAndSettle();
        expect(localProvider.positionMs, 16000);
        expect(state.currentPanelProgress, closeTo(1.0, 1e-4));
        expect(find.byType(BottomSheet), findsOneWidget);
        Navigator.of(tester.element(find.byType(NowPlayingView))).pop();
        await tester.pumpAndSettle();
      }

      // =======================================================================
      // (c) Demotion (0 -> -1) on seek back before first timestamp
      // =======================================================================
      localProvider.handleNativePosition(
        positionMs: 11000,
        durationMs: 240000,
        isPlaying: false,
      ); // Active line 0
      await tester.pumpAndSettle();
      localProvider.handleNativePosition(
        positionMs: 2000,
        durationMs: 240000,
        isPlaying: false,
      ); // Seek before first timestamp (10000ms)
      await tester.pump(); // Frame 0 of Demotion
      await tester.pump(const Duration(milliseconds: 200)); // Mid-demotion
      final midDemotionLine0Y = tester.getRect(prevSlotFinder).top;
      final midDemotionLine1Y = tester.getRect(midSlotFinder).top;
      expect(midDemotionLine0Y, greaterThan(introLine0TopY + 0.5));
      expect(midDemotionLine0Y, lessThan(settledActiveLine0Y - 1.0));
      expect(
        tester.getRect(prevSlotFinder).bottom,
        lessThanOrEqualTo(midDemotionLine1Y + 0.01),
      );

      await tester.pumpAndSettle();
      expect(tester.getRect(prevSlotFinder).top, closeTo(introLine0TopY, 0.5));
      expect(tester.getRect(midSlotFinder).top, closeTo(introLine1TopY, 0.5));
      expect(tester.getRect(nextSlotFinder).top, closeTo(introLine2TopY, 0.5));

      // =======================================================================
      // (g) Arrival at panel lands directly in Rest (no explore ladder frame)
      // =======================================================================
      localProvider.handleNativePosition(
        positionMs: 21000,
        durationMs: 240000,
        isPlaying: false,
      ); // Active line 2
      await tester.pumpAndSettle();
      state.animateToPagerPanel(NowPlayingView.lyricsPanelIndex);
      await tester.pump();
      // Step through the 300ms morph and check extra lines during morph & on FIRST settled frame
      while (state.currentPanelProgress > 0.0) {
        await tester.pump(const Duration(milliseconds: 50));
        if (state.currentPanelProgress > 0.0) {
          // During morph (0 < p < 1), distant lines |i - 2| > 1 have Rest target opacity 0.0
          for (final distantIdx in <int>[0, 4, 5, 6]) {
            final opFinder = find.byKey(
              ValueKey<String>('morph_lyric_opacity_$distantIdx'),
            );
            if (opFinder.evaluate().isNotEmpty) {
              expect(tester.widget<Opacity>(opFinder).opacity, 0.0);
            }
          }
        }
      }
      // First frame where p == 0.0: every line with |i - 2| > 1 MUST already have opacity 0.0!
      expect(state.currentPanelProgress, 0.0);
      expect(state.isLyricsPanelInExploreMode, isFalse);
      for (int i = 0; i < 7; i++) {
        final op = tester
            .widget<AnimatedOpacity>(
              find.byKey(ValueKey<String>('lyrics_panel_line_opacity_$i')),
            )
            .opacity;
        if ((i - 2).abs() <= 1) {
          expect(op, greaterThan(0.0));
        } else {
          expect(op, 0.0, reason: 'Line $i must be 0.0 on first settled frame at p=0');
        }
      }
      await tester.pumpAndSettle();

      // =======================================================================
      // (f) Lyrics-panel line-change 400ms interpolated slide + no-overlap in BOTH Rest & Explore
      // =======================================================================
      // 1. In Rest mode: advance active line 2 -> 3 (at 25200ms) and sample at 20fps (50ms intervals)
      final startY2Rest = tester
          .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_2')))
          .top;
      final startY3Rest = tester
          .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_3')))
          .top;
      final startFont2Rest = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_text_2')),
          )
          .style!
          .fontSize!;
      final startFont3Rest = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_text_3')),
          )
          .style!
          .fontSize!;
      final startColor2Rest = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_text_2')),
          )
          .style!
          .color!;
      final startColor3Rest = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_text_3')),
          )
          .style!
          .color!;

      localProvider.handleNativePosition(
        positionMs: 25200,
        durationMs: 240000,
        isPlaying: false,
      );
      await tester.pump(); // Frame 0 (0ms): 0.0px jump & 0.0pt font jump!
      final frame0Y2Rest = tester
          .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_2')))
          .top;
      final frame0Y3Rest = tester
          .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_3')))
          .top;
      final frame0Font2Rest = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_text_2')),
          )
          .style!
          .fontSize!;
      final frame0Font3Rest = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_text_3')),
          )
          .style!
          .fontSize!;
      expect((frame0Y2Rest - startY2Rest).abs(), lessThan(0.5));
      expect((frame0Y3Rest - startY3Rest).abs(), lessThan(0.5));
      expect(frame0Font2Rest, closeTo(startFont2Rest, 0.01));
      expect(frame0Font3Rest, closeTo(startFont3Rest, 0.01));

      final intermediateY2Rest = <double>[];
      final intermediateY3Rest = <double>[];
      int intermediateStyleFramesRest = 0;
      for (int sample = 1; sample <= 7; sample++) {
        await tester.pump(const Duration(milliseconds: 50));
        intermediateY2Rest.add(
          tester
              .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_2')))
              .top,
        );
        intermediateY3Rest.add(
          tester
              .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_3')))
              .top,
        );
        final curFont2 = tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('lyrics_panel_line_text_2')),
            )
            .style!
            .fontSize!;
        final curFont3 = tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('lyrics_panel_line_text_3')),
            )
            .style!
            .fontSize!;
        final curColor3 = tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('lyrics_panel_line_text_3')),
            )
            .style!
            .color!;
        // Never both lines at final active typography
        expect(
          curFont2 >= startFont2Rest - 0.05 &&
              curFont3 >= startFont2Rest - 0.05,
          isFalse,
        );
        if (curFont3 > startFont3Rest + 0.05 &&
            curFont2 < startFont2Rest - 0.05 &&
            curColor3 != startColor3Rest &&
            curColor3 != startColor2Rest) {
          intermediateStyleFramesRest++;
        }
        // Verify exactly 1 copy of each line & NO overlap between any adjacent lines on this frame
        for (int i = 0; i < 6; i++) {
          expect(
            find.byKey(ValueKey<String>('lyrics_panel_line_$i')),
            findsOneWidget,
          );
          final rectI = tester.getRect(
            find.byKey(ValueKey<String>('lyrics_panel_line_$i')),
          );
          final rectNext = tester.getRect(
            find.byKey(ValueKey<String>('lyrics_panel_line_${i + 1}')),
          );
          expect(
            rectI.bottom,
            lessThanOrEqualTo(rectNext.top + 0.01),
            reason: 'Lines $i and ${i + 1} must never overlap during Rest slide',
          );
        }
      }
      await tester.pumpAndSettle();
      final endY2Rest = tester
          .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_2')))
          .top;
      final endY3Rest = tester
          .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_3')))
          .top;

      int strictlyBetweenCountRest = 0;
      for (int s = 0; s < intermediateY2Rest.length; s++) {
        if (intermediateY2Rest[s] < startY2Rest - 1.0 &&
            intermediateY2Rest[s] > endY2Rest + 0.5 &&
            intermediateY3Rest[s] < startY3Rest - 1.0 &&
            intermediateY3Rest[s] > endY3Rest + 0.5) {
          strictlyBetweenCountRest++;
        }
      }
      expect(
        strictlyBetweenCountRest,
        greaterThanOrEqualTo(4),
        reason:
            'startY2=$startY2Rest midY2=$intermediateY2Rest endY2=$endY2Rest | startY3=$startY3Rest midY3=$intermediateY3Rest endY3=$endY3Rest | scrollOff=${state.lyricsPanelScrollController.offset}',
      );
      expect(intermediateStyleFramesRest, greaterThanOrEqualTo(4));

      // 2. In Explore mode: scroll slightly to enter Explore mode, then advance 3 -> 4 (at 30200ms)
      await tester.drag(
        find.byKey(const ValueKey<String>('lyrics_panel_scroll_view')),
        const Offset(0.0, -30.0),
      );
      await tester.pump();
      expect(state.isLyricsPanelInExploreMode, isTrue);

      final startY3Explore = tester
          .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_3')))
          .top;
      final startY4Explore = tester
          .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_4')))
          .top;
      final startFont3Explore = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_text_3')),
          )
          .style!
          .fontSize!;
      final startFont4Explore = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_text_4')),
          )
          .style!
          .fontSize!;

      localProvider.handleNativePosition(
        positionMs: 30200,
        durationMs: 240000,
        isPlaying: false,
      );
      await tester.pump(); // Frame 0 in Explore mode

      final intermediateY3Explore = <double>[];
      final intermediateY4Explore = <double>[];
      int intermediateStyleFramesExplore = 0;
      for (int sample = 1; sample <= 7; sample++) {
        await tester.pump(const Duration(milliseconds: 50));
        intermediateY3Explore.add(
          tester
              .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_3')))
              .top,
        );
        intermediateY4Explore.add(
          tester
              .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_4')))
              .top,
        );
        final curFont3 = tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('lyrics_panel_line_text_3')),
            )
            .style!
            .fontSize!;
        final curFont4 = tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('lyrics_panel_line_text_4')),
            )
            .style!
            .fontSize!;
        if (curFont4 > startFont4Explore + 0.05 &&
            curFont3 < startFont3Explore - 0.05) {
          intermediateStyleFramesExplore++;
        }
        for (int i = 0; i < 6; i++) {
          final rectI = tester.getRect(
            find.byKey(ValueKey<String>('lyrics_panel_line_$i')),
          );
          final rectNext = tester.getRect(
            find.byKey(ValueKey<String>('lyrics_panel_line_${i + 1}')),
          );
          expect(
            rectI.bottom,
            lessThanOrEqualTo(rectNext.top + 0.01),
            reason:
                'Lines $i and ${i + 1} must never overlap during Explore slide',
          );
        }
      }
      await tester.pump(const Duration(milliseconds: 200));
      final endY3Explore = tester
          .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_3')))
          .top;
      final endY4Explore = tester
          .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_4')))
          .top;

      int strictlyBetweenCountExplore = 0;
      for (int s = 0; s < intermediateY3Explore.length; s++) {
        if (intermediateY3Explore[s] < startY3Explore - 1.0 &&
            intermediateY3Explore[s] > endY3Explore + 0.5 &&
            intermediateY4Explore[s] < startY4Explore - 1.0 &&
            intermediateY4Explore[s] > endY4Explore + 0.5) {
          strictlyBetweenCountExplore++;
        }
      }
      expect(strictlyBetweenCountExplore, greaterThanOrEqualTo(4));
      expect(intermediateStyleFramesExplore, greaterThanOrEqualTo(4));

      // Verify tap-to-seek inside the Lyrics panel (p = 0) seeks AND slides over ~400ms with >= 4 intermediate frames!
      final startY5Tap = tester
          .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_5')))
          .top;
      final startFont5Tap = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_text_5')),
          )
          .style!
          .fontSize!;
      await tester.tap(find.byKey(const ValueKey<String>('lyrics_panel_line_5')));
      await tester.pump();
      expect(localProvider.positionMs, 35000);
      final intermediateY5Tap = <double>[];
      int tapIntermediateStyleCount = 0;
      for (int sample = 1; sample <= 7; sample++) {
        await tester.pump(const Duration(milliseconds: 50));
        intermediateY5Tap.add(
          tester
              .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_5')))
              .top,
        );
        final curFont5 = tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('lyrics_panel_line_text_5')),
            )
            .style!
            .fontSize!;
        if (curFont5 > startFont5Tap + 0.05) {
          tapIntermediateStyleCount++;
        }
      }
      await tester.pumpAndSettle();
      final endY5Tap = tester
          .getRect(find.byKey(const ValueKey<String>('lyrics_panel_line_5')))
          .top;
      int tapIntermediateCount = 0;
      for (final y in intermediateY5Tap) {
        if (y < startY5Tap - 1.0 && y > endY5Tap + 0.5) {
          tapIntermediateCount++;
        }
      }
      expect(tapIntermediateCount, greaterThanOrEqualTo(4));
      expect(tapIntermediateStyleCount, greaterThanOrEqualTo(4));

      // =======================================================================
      // (d) Plain-text (unsynced) lyrics treatment on Home & Lyrics panel
      // =======================================================================
      state.debugSetPanelProgress(1.0);
      await localProvider.playSong(plainSong, queueContext: [syncedSong, plainSong]);
      await localProvider.togglePlayPause();
      localProvider.handleNativePosition(
        positionMs: 45000,
        durationMs: 180000,
        isPlaying: false,
      );
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pumpAndSettle();

      // Home (p = 1.0): permanent 3-line Intro Stack regardless of playback position (45s)
      final plain0 = find.byKey(
        const ValueKey<String>(
          'lyric_line_upcoming_0_Plain opening line in top slot',
        ),
      );
      final plain1 = find.byKey(
        const ValueKey<String>(
          'lyric_line_upcoming_1_Plain second line in middle slot',
        ),
      );
      final plain2 = find.byKey(
        const ValueKey<String>(
          'lyric_line_upcoming_2_Plain third line in bottom slot',
        ),
      );
      expect(plain0, findsOneWidget);
      expect(plain1, findsOneWidget);
      expect(plain2, findsOneWidget);
      for (final pf in <Finder>[plain0, plain1, plain2]) {
        final txt = tester.widget<Text>(pf);
        expect(
          txt.style!.fontSize,
          closeTo(MusEveePalette.lyricSecondaryFontSize, 0.001),
        );
        expect(txt.style!.color, palette.nowPlayingSecondary);
      }

      // (e.3) Tapping plain-text Home column opens Full Lyrics Sheet and never seeks
      await tester.tap(plain1);
      await tester.pumpAndSettle();
      expect(localProvider.positionMs, 45000);
      expect(state.currentPanelProgress, closeTo(1.0, 1e-4));
      expect(find.byType(BottomSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(NowPlayingView))).pop();
      await tester.pumpAndSettle();

      // Lyrics panel (p = 0.0): uniform styling (14.5pt, height 1.2) and NO idle auto-return timer
      state.debugSetPanelProgress(0.0);
      await tester.pumpAndSettle();
      final plainListFinder = find.byKey(
        const ValueKey<String>('lyrics_panel_plain_list'),
      );
      expect(plainListFinder, findsOneWidget);

      await tester.drag(plainListFinder, const Offset(0.0, -180.0));
      await tester.pumpAndSettle();
      final plainScrollable = find.descendant(
        of: plainListFinder,
        matching: find.byType(Scrollable),
      );
      final scrolledOffset =
          tester.state<ScrollableState>(plainScrollable).position.pixels;
      expect(scrolledOffset, greaterThan(50.0));

      // Advance 10 full seconds: plain-text panel must NOT auto-return!
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(plainScrollable).position.pixels,
        closeTo(scrolledOffset, 0.01),
      );
    },
  );

  testWidgets(
    'Lyrics Font Size 11.5pt Preset: 5-step overflow cycle (11.5/13.5/15.5/18.0/20.5), smaller active line at 11.5pt vs 13.5pt across Home/Morph/Panel 0/Sheet, and legacy session migration',
    (WidgetTester tester) async {
      final localProvider = LocalMusicProvider();
      final downloaderProvider = DownloaderProvider();
      addTearDown(localProvider.dispose);
      addTearDown(downloaderProvider.dispose);

      // 1. Default preset & 5-element preset list
      expect(
        LocalMusicProvider.fontSizePresets,
        const <double>[11.5, 13.5, 15.5, 18.0, 20.5],
      );
      expect(localProvider.lyricsFontSize, 15.5);

      // 2. Legacy session migration: old 4-element indices 0..3 -> 13.5, 15.5, 18.0, 20.5
      localProvider.restoreFontSizeFromSessionMap(<String, dynamic>{
        'fontSizeIndex': 0,
      });
      expect(localProvider.lyricsFontSize, 13.5);
      localProvider.restoreFontSizeFromSessionMap(<String, dynamic>{
        'fontSizeIndex': 1,
      });
      expect(localProvider.lyricsFontSize, 15.5);
      localProvider.restoreFontSizeFromSessionMap(<String, dynamic>{
        'fontSizeIndex': 2,
      });
      expect(localProvider.lyricsFontSize, 18.0);
      localProvider.restoreFontSizeFromSessionMap(<String, dynamic>{
        'fontSizeIndex': 3,
      });
      expect(localProvider.lyricsFontSize, 20.5);
      localProvider.restoreFontSizeFromSessionMap(<String, dynamic>{
        'lyricsFontSizePt': 11.5,
        'fontSizeIndex': 0,
      });
      expect(localProvider.lyricsFontSize, 11.5);
      // Reset to default 15.5pt
      localProvider.restoreFontSizeFromSessionMap(<String, dynamic>{
        'lyricsFontSizePt': 15.5,
      });
      expect(localProvider.lyricsFontSize, 15.5);

      final song = _mockSong(
        701,
        lyrics: '[00:05.00] First line\n'
            '[00:10.00] Active lyric line\n'
            '[00:15.00] Third line',
      );
      localProvider.seedSongsForTesting([song]);
      await localProvider.playSong(song, queueContext: [song]);
      await localProvider.togglePlayPause();

      final npKey = GlobalKey<NowPlayingViewState>();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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
            theme: ThemeData.light().copyWith(
              extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
            ),
            home: Scaffold(
              body: NowPlayingView(
                key: npKey,
                onNavigateToDownloader: () {},
                onNavigateToFolders: () {},
                onMoveLocalSongFolder: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 950));
      localProvider.handleNativePosition(
        positionMs: 11000,
        durationMs: 180000,
        isPlaying: false,
      );
      await tester.pumpAndSettle();

      double currentHomeActiveFontSize() {
        return tester
            .widget<Text>(
              find.byKey(
                const ValueKey<String>('lyric_line_active_1_Active lyric line'),
              ),
            )
            .style!
            .fontSize!;
      }

      // Default 15.5pt -> active line renders at 22.0pt
      expect(currentHomeActiveFontSize(), 22.0);

      // 3. Open overflow menu and cycle through all 5 presets: 15.5 -> 18.0 -> 20.5 -> 11.5 -> 13.5 -> 15.5
      await tester.tap(
        find.byKey(const ValueKey<String>('now_playing_overflow_button')),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -280),
      );
      await tester.pumpAndSettle();
      expect(find.text('15.5 pt'), findsOneWidget);

      await tester.tap(find.text('Ukuran Font Lirik'));
      await tester.pump();
      expect(localProvider.lyricsFontSize, 18.0);
      expect(find.text('18.0 pt'), findsOneWidget);

      await tester.tap(find.text('Ukuran Font Lirik'));
      await tester.pump();
      expect(localProvider.lyricsFontSize, 20.5);
      expect(find.text('20.5 pt'), findsOneWidget);

      await tester.tap(find.text('Ukuran Font Lirik'));
      await tester.pump();
      expect(localProvider.lyricsFontSize, 11.5);
      expect(find.text('11.5 pt'), findsOneWidget);

      Navigator.of(tester.element(find.byType(NowPlayingView))).pop();
      await tester.pumpAndSettle();

      // At 11.5pt (offset -4.0), Home active line renders at 18.0pt
      final homeFontAt115 = currentHomeActiveFontSize();
      expect(homeFontAt115, 18.0);

      // Panel 0 at 11.5pt also renders active line at 18.0pt
      final state = npKey.currentState!;
      state.debugSetPanelProgress(0.0);
      await tester.pump();
      final panel0FontAt115 = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_text_1')),
          )
          .style!
          .fontSize!;
      expect(panel0FontAt115, 18.0);

      // Cycle to 13.5pt (offset -2.0) -> Home & Panel 0 active line renders at 20.0pt (> 18.0pt at 11.5pt)
      localProvider.cycleLyricsFontSize();
      expect(localProvider.lyricsFontSize, 13.5);
      await tester.pump();
      final panel0FontAt135 = tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('lyrics_panel_line_text_1')),
          )
          .style!
          .fontSize!;
      expect(panel0FontAt135, 20.0);
      expect(panel0FontAt115, lessThan(panel0FontAt135));

      state.debugSetPanelProgress(1.0);
      await tester.pump();
      final homeFontAt135 = currentHomeActiveFontSize();
      expect(homeFontAt135, 20.0);
      expect(homeFontAt115, lessThan(homeFontAt135));

      // Cycle back to 15.5pt -> 22.0pt
      localProvider.cycleLyricsFontSize();
      expect(localProvider.lyricsFontSize, 15.5);
      await tester.pump();
      expect(currentHomeActiveFontSize(), 22.0);
    },
  );
}

class _OfflineTestRomajiService extends RomajiService {
  int convertCallCount = 0;

  @override
  Future<String> romanizeLyrics(String rawLyrics) async {
    convertCallCount++;
    final lines = rawLyrics.replaceAll('\r\n', '\n').split('\n');
    final out = <String>[];
    for (final line in lines) {
      final parsed = RomajiService.parseLyricLine(line);
      if (!parsed.hasLyricContent) {
        out.add(line);
        continue;
      }
      final converted = parsed.lyricContent
          .replaceAll('夢の旅路', 'Yume no tabiji')
          .replaceAll('星空の約束', 'Hoshizora no yakusoku')
          .replaceAll('ライン', 'rain ');
      if (parsed.timestampPrefix.isNotEmpty) {
        out.add('${parsed.timestampPrefix} ${converted.trim()}');
      } else {
        out.add(converted.trim());
      }
    }
    return out.join('\n');
  }

  @override
  Future<String> romanizeText(String text) async {
    return text
        .replaceAll('夢の旅路', 'Yume no tabiji')
        .replaceAll('星空の約束', 'Hoshizora no yakusoku');
  }

  @override
  Future<TrackMetadata> romanizeTrackInfo(TrackMetadata metadata) async {
    return metadata.copyWith(
      title: await romanizeText(metadata.title),
      artist: await romanizeText(metadata.artist),
      album: await romanizeText(metadata.album),
    );
  }
}

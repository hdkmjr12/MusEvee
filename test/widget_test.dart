import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spotmeta_downloader/main.dart';
import 'package:spotmeta_downloader/models/local_song.dart';
import 'package:spotmeta_downloader/providers/downloader_provider.dart';
import 'package:spotmeta_downloader/providers/local_music_provider.dart';
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
  testWidgets(
      'MusEveeApp renders 6-tab Musicolet UI, switches to Downloader tab, and opens Queue/History Modal Sheet',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MusEveeApp());
    await tester.pump();

    // Default tab is Musicolet Now Playing (Tab 1)
    expect(find.text('MusEvee Player'), findsOneWidget);
    expect(find.text('Cari & Unduh Lagu'), findsOneWidget);

    // Switch to Downloader tab (Tab 4: Cloud Download icon in MusicoletBottomStrip)
    await tester.tap(find.byIcon(Icons.cloud_download_outlined).last);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'MusEvee All-in-One Downloader (MP3 320kbps + USLT Lyrics)',
      ),
      findsOneWidget,
    );
    expect(find.text('YOASOBI - Idol'), findsOneWidget);

    // Tap the compact Queue & History button next to the Downloader Omnibox
    await tester.tap(find.byTooltip('Antrean & Riwayat Unduhan'));
    await tester.pumpAndSettle();

    expect(find.text('Antrean & Riwayat Unduhan'), findsOneWidget);
  });

  test(
      'True Queue-Order Shuffle advances linearly along visual queue and restores original order',
      () async {
    final provider = LocalMusicProvider();
    addTearDown(provider.dispose);

    final songs = List.generate(8, (i) => _mockSong(i + 1));
    await provider.playSong(songs[2], queueContext: songs);

    expect(provider.currentIndex, 2);
    expect(provider.currentSong?.title, 'Song 3');

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

    // Turning Shuffle OFF restores exact original queue order while keeping current active song
    final activeBeforeRestore = provider.currentSong!.title;
    provider.toggleShuffle();
    expect(provider.isShuffle, isFalse);
    expect(
      provider.queueEntries.map((e) => e.song.title).toList(),
      songs.map((s) => s.title).toList(),
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
}

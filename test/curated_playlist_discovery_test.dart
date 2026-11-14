import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spotmeta_downloader/main.dart';
import 'package:spotmeta_downloader/models/curated_playlist.dart';
import 'package:spotmeta_downloader/models/download_item.dart';
import 'package:spotmeta_downloader/models/local_song.dart';
import 'package:spotmeta_downloader/models/track_metadata.dart';
import 'package:spotmeta_downloader/providers/downloader_provider.dart';
import 'package:spotmeta_downloader/providers/local_music_provider.dart';
import 'package:spotmeta_downloader/providers/settings_provider.dart';
import 'package:spotmeta_downloader/screens/home_screen.dart';
import 'package:spotmeta_downloader/services/folder_service.dart';
import 'package:spotmeta_downloader/services/lyrics_service.dart';
import 'package:spotmeta_downloader/services/metadata_service.dart';
import 'package:spotmeta_downloader/services/tagging_service.dart';
import 'package:spotmeta_downloader/theme/musevee_palette.dart';
import 'package:spotmeta_downloader/utils/app_strings.dart';
import 'package:spotmeta_downloader/widgets/batch_playlist_sheet.dart';
import 'package:spotmeta_downloader/widgets/local_library_views.dart';
import 'package:spotmeta_downloader/widgets/musevee_logo.dart';
import 'package:spotmeta_downloader/widgets/musicolet_mini_player.dart';
import 'package:spotmeta_downloader/widgets/pressable_scale.dart';
import 'package:spotmeta_downloader/widgets/queue_history_view.dart';
import 'package:spotmeta_downloader/widgets/search_result_tile.dart';
import 'package:spotmeta_downloader/widgets/tag_editor_sheet.dart';
import 'package:spotmeta_downloader/widgets/track_preview_sheet.dart';

class _LifecycleProbe extends StatefulWidget {
  final VoidCallback onInit;
  final VoidCallback onDispose;
  final String label;

  const _LifecycleProbe({
    required this.onInit,
    required this.onDispose,
    required this.label,
  });

  @override
  State<_LifecycleProbe> createState() => _LifecycleProbeState();
}

class _LifecycleProbeState extends State<_LifecycleProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 50,
      alignment: Alignment.center,
      child: Text(widget.label),
    );
  }
}

TrackMetadata _track(int id, {String title = '', String artist = ''}) {
  final t = title.isNotEmpty ? title : 'Track $id';
  final a = artist.isNotEmpty ? artist : 'Artist $id';
  return TrackMetadata(
    spotifyUrl: 'https://www.deezer.com/track/$id',
    title: t,
    artist: a,
    album: 'Album $id',
    releaseYear: '2026',
    durationSeconds: 185,
    coverUrl: '',
  );
}

void main() {
  test(
    'FolderService.findDuplicateFoldersBatchInDirectories scans folders once and matches mp3, flac, and numbered duplicates while skipping <16KB files',
    () async {
      final root = await Directory.systemTemp.createTemp('musevee_dup_batch_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final musicDir = await Directory('${root.path}/Music').create();
      final jpopDir = await Directory('${root.path}/J-Pop').create();

      final validBytes = Uint8List(20 * 1024); // >= 16KB threshold
      final corruptBytes = Uint8List(4 * 1024); // < 16KB corrupt stub

      await File('${musicDir.path}/Conan Gray - Memories.flac')
          .writeAsBytes(validBytes);
      await File('${jpopDir.path}/YOASOBI - Idol (1).mp3')
          .writeAsBytes(validBytes);
      await File('${musicDir.path}/Corrupt Artist - Tiny File.mp3')
          .writeAsBytes(corruptBytes);

      final service = FolderService();
      final result = await service.findDuplicateFoldersBatchInDirectories(
        <String>[
          'Conan Gray - Memories.mp3',
          'YOASOBI - Idol.mp3',
          'Corrupt Artist - Tiny File.mp3',
          'Nonexistent - Missing.mp3',
        ],
        <String, Directory>{
          'Music': musicDir,
          'J-Pop': jpopDir,
        },
      );

      expect(result['conan gray - memories.mp3'], 'Music');
      expect(result['yoasobi - idol.mp3'], 'J-Pop');
      expect(result.containsKey('corrupt artist - tiny file.mp3'), isFalse);
      expect(result.containsKey('nonexistent - missing.mp3'), isFalse);
    },
  );

  test(
    'MetadataService Deezer collection detection & playlist title normalization work accurately',
    () {
      final service = MetadataService();
      expect(
        service.isDeezerCollectionInput(
          'https://www.deezer.com/playlist/15234906703',
        ),
        isTrue,
      );
      expect(
        service.isDeezerCollectionInput(
          'https://deezer.com/en/album/12345678',
        ),
        isTrue,
      );
      expect(
        service.isCollectionInput(
          'https://www.deezer.com/playlist/15234906703',
        ),
        isTrue,
      );
      expect(
        service.isCollectionInput(
          'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
        ),
        isTrue,
      );
      expect(service.isDeezerCollectionInput('yoasobi idol'), isFalse);

      expect(
        MetadataService.formatPlaylistTitle('LAGU TOP HITS INDONESIA 2026'),
        'Lagu Top Hits Indonesia 2026',
      );
      expect(
        MetadataService.formatPlaylistTitle('chill lofi'),
        'Chill Lofi',
      );
      expect(
        MetadataService.formatPlaylistTitle('Top J-Pop'),
        'Top J-Pop',
      );
    },
  );

  testWidgets(
    'PressableScale preserves child state (no blink/remount) and suppresses taps when enabled toggles to false',
    (WidgetTester tester) async {
      int initCount = 0;
      int disposeCount = 0;
      int tapCount = 0;
      bool enabled = true;

      Widget buildWidget() {
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: PressableScale(
                enabled: enabled,
                onTap: () => tapCount++,
                child: _LifecycleProbe(
                  label: 'Playlist Card',
                  onInit: () => initCount++,
                  onDispose: () => disposeCount++,
                ),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildWidget());
      expect(initCount, 1);
      expect(disposeCount, 0);

      await tester.tap(find.text('Playlist Card'));
      await tester.pumpAndSettle();
      expect(tapCount, 1);

      // Simulate provider.isBusy flipping enabled -> false during tap feedback
      enabled = false;
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      expect(initCount, 1);
      expect(disposeCount, 0);

      await tester.tap(find.text('Playlist Card'));
      await tester.pumpAndSettle();
      expect(tapCount, 1);

      // Re-enable without unmounting child
      enabled = true;
      await tester.pumpWidget(buildWidget());
      await tester.pump();
      expect(initCount, 1);
      expect(disposeCount, 0);
    },
  );

  testWidgets(
    'BatchPlaylistSheet opens immediately in loading state, populates tracks reactively, and handles preloaded playlists with matching title and count',
    (WidgetTester tester) async {
      final settingsProvider = SettingsProvider();
      final provider = DownloaderProvider(settingsProvider: settingsProvider);
      addTearDown(settingsProvider.dispose);
      addTearDown(provider.dispose);

      // 1. Preloaded playlist resolves instantaneously with exact title & count
      final preloadedPlaylist = CuratedPlaylist(
        id: 'test_playlist',
        deezerPlaylistId: '4403076402',
        title: 'TikTok Hits World',
        songCount: 3,
        spotifyUrl: 'https://www.deezer.com/playlist/4403076402',
        preloadedTracks: <TrackMetadata>[
          _track(1, title: 'Song One', artist: 'Artist A'),
          _track(2, title: 'Song Two', artist: 'Artist B'),
          _track(3, title: 'Song Three', artist: 'Artist C'),
        ],
      );

      final loadedOk = await provider.loadCuratedPlaylist(preloadedPlaylist);
      expect(loadedOk, isTrue);
      expect(provider.state, DownloaderState.readyToDownload);
      expect(provider.currentCollection?.title, 'TikTok Hits World');
      expect(provider.currentCollection?.tracks.length, 3);

      // 2. Opening BatchPlaylistSheet before collection arrives shows spinner + Retry if error
      int retryCount = 0;
      await tester.pumpWidget(
        ChangeNotifierProvider<DownloaderProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.light,
              extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
            ),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      // Trigger loading without awaiting network first
                      provider.reset();
                      BatchPlaylistSheet.show(
                        ctx,
                        initialTitle: 'Lagu Galau Indonesia 2026',
                        onRetry: () async {
                          retryCount++;
                          return provider
                              .loadCuratedPlaylist(preloadedPlaylist);
                        },
                        onCreateNewFolder: (_) async {},
                      );
                    },
                    child: const Text('Open Async Sheet'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Async Sheet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Lagu Galau Indonesia 2026'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Populate tracks while sheet is already open -> reacts immediately
      await provider.loadCuratedPlaylist(preloadedPlaylist);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Song One'), findsOneWidget);
      expect(find.text('Song Two'), findsOneWidget);
      expect(find.text('Song Three'), findsOneWidget);
      expect(find.text('TikTok Hits World'), findsOneWidget);
      expect(retryCount, 0);
    },
  );

  testWidgets(
    'Downloader tab at 360px shows all 3 search pills without clipping and opens preloaded playlist card on first tap without flicker',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const systemChannel = MethodChannel('com.spotmeta.downloader/system');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(systemChannel, (MethodCall call) async {
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(systemChannel, null);
      });

      final settingsProvider = SettingsProvider();
      final localProvider = LocalMusicProvider()
        ..debugEnableNativeChannelInTests = true;
      final downloaderProvider = DownloaderProvider(
        settingsProvider: settingsProvider,
      );
      addTearDown(settingsProvider.dispose);
      addTearDown(localProvider.dispose);
      addTearDown(downloaderProvider.dispose);

      downloaderProvider.seedDiscoveryCarouselsForTesting(
        forYou: <TrackMetadata>[_track(10, title: 'For You Track')],
        globalTrending: <TrackMetadata>[
          for (int i = 0; i < 6; i++) _track(20 + i, title: 'Global Track $i'),
        ],
        indonesiaTrending: <TrackMetadata>[_track(30, title: 'Indo Track')],
        newReleases: <TrackMetadata>[_track(40, title: 'Fresh Single')],
        playlists: <CuratedPlaylist>[
          CuratedPlaylist(
            id: 'galau',
            deezerPlaylistId: '15234906703',
            title: 'Lagu Galau Indonesia 2026',
            songCount: 2,
            spotifyUrl: 'https://www.deezer.com/playlist/15234906703',
            preloadedTracks: <TrackMetadata>[
              _track(101, title: 'Galau Track A', artist: 'Fajar Noor'),
              _track(102, title: 'Galau Track B', artist: 'Lyodra'),
            ],
          ),
          CuratedPlaylist(
            id: 'jpop_favorites',
            deezerPlaylistId: '6049895724',
            title: 'Top J-Pop',
            songCount: 1,
            spotifyUrl: 'https://www.deezer.com/playlist/6049895724',
            preloadedTracks: <TrackMetadata>[
              _track(201, title: 'Yoru ni Kakeru', artist: 'YOASOBI'),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
              value: settingsProvider,
            ),
            ChangeNotifierProvider<LocalMusicProvider>.value(
              value: localProvider,
            ),
            ChangeNotifierProvider<DownloaderProvider>.value(
              value: downloaderProvider,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.light,
              fontFamily: 'Poppins',
              extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
            ),
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Navigate to Downloader tab
      await tester.tap(find.byTooltip(AppStrings.tabDownloaderTooltip));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // All 3 search pills must fit inside 360px viewport without right-edge clipping
      final titlePill = find.text(AppStrings.searchTitleArtistPill);
      final ytPill = find.text(AppStrings.linkYoutubePill);
      final spotifyPill = find.text(AppStrings.linkSpotifyPill);
      expect(titlePill, findsOneWidget);
      expect(ytPill, findsOneWidget);
      expect(spotifyPill, findsOneWidget);
      expect(tester.getRect(spotifyPill).right, lessThanOrEqualTo(360.0));

      // Horizontal discovery ListViews must span full viewport width (0..360)
      // while keeping x=14px content alignment via ListView padding so scrolled
      // items glide to the screen edge instead of clipping at x=14px.
      final trendingListFinder = find.descendant(
        of: find.byKey(const ValueKey('carousel_global_trending')),
        matching: find.byType(ListView),
      );
      expect(tester.getRect(trendingListFinder).left, 0.0);
      expect(tester.getRect(trendingListFinder).right, 360.0);
      final firstRankFinder = find.descendant(
        of: find.byKey(const ValueKey('carousel_global_trending')),
        matching: find.text('1.'),
      );
      expect(tester.getRect(firstRankFinder).left, 14.0);
      await tester.drag(trendingListFinder, const Offset(-28, 0));
      await tester.pump();
      expect(tester.getRect(firstRankFinder).left, lessThan(14.0));
      expect(tester.getRect(firstRankFinder).left, greaterThan(0.0));

      for (final carouselKey in const <String>[
        'carousel_for_you',
        'carousel_playlists_for_you',
      ]) {
        final sectionFinder = find.byKey(ValueKey(carouselKey));
        await tester.scrollUntilVisible(
          sectionFinder,
          120,
          scrollable: find.byType(Scrollable).first,
        );
        final listFinder = find.descendant(
          of: sectionFinder,
          matching: find.byType(ListView),
        );
        final rect = tester.getRect(listFinder);
        expect(rect.left, 0.0);
        expect(rect.right, 360.0);
      }

      // Tap curated playlist once -> BatchPlaylistSheet opens immediately with matching title & songs
      await tester.scrollUntilVisible(
        find.text('Lagu Galau Indonesia 2026'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Lagu Galau Indonesia 2026'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Galau Track A'), findsOneWidget);
      expect(find.text('Galau Track B'), findsOneWidget);

      // Dismiss sheet and verify bottom discovery carousels also span 0..360.
      Navigator.of(
        tester.element(find.byType(BatchPlaylistSheet)),
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      for (final carouselKey in const <String>[
        'carousel_new_releases',
        'carousel_indonesia_trending',
      ]) {
        final sectionFinder = find.byKey(ValueKey(carouselKey));
        await tester.scrollUntilVisible(
          sectionFinder,
          140,
          scrollable: find.byType(Scrollable).first,
        );
        final listFinder = find.descendant(
          of: sectionFinder,
          matching: find.byType(ListView),
        );
        final rect = tester.getRect(listFinder);
        expect(rect.left, 0.0);
        expect(rect.right, 360.0);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Redesigned monochrome TrackPreviewSheet renders English & Indonesian via AppStrings, keeps Album•Year•Duration, uses custom assets, and switches folders/modes at 360px Light & Dark without overflow',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() {
        AppStrings.debugLanguageCodeOverride = null;
      });

      final settingsProvider = SettingsProvider();
      final provider = DownloaderProvider(settingsProvider: settingsProvider);
      addTearDown(settingsProvider.dispose);
      addTearDown(provider.dispose);

      const sampleTrack = TrackMetadata(
        spotifyUrl: 'https://open.spotify.com/track/sample123',
        title: 'Memories',
        artist: 'Conan Gray',
        album: 'Superache',
        releaseYear: '2026',
        durationSeconds: 248,
        coverUrl: '',
        previewAudioUrl: 'https://cdn-preview.example.com/memories.mp3',
        syncedLyrics: '[00:00.65] One, Two\n[00:04.20] Three, Four',
        plainLyrics: 'One, Two\nThree, Four',
      );
      const sampleCandidate = LyricsCandidate(
        id: 'cand_1',
        trackName: 'Memories',
        artistName: 'Conan Gray',
        albumName: 'Superache',
        durationSeconds: 248,
        syncedLyrics: '[00:00.65] One, Two\n[00:04.20] Three, Four',
        plainLyrics: 'One, Two\nThree, Four',
        languageTag: '[Inggris/Lainnya]',
        score: 100,
      );
      provider.seedTrackMetadataForTesting(
        sampleTrack,
        folders: <String>['Music Barat', 'Music Japan', 'Pop Hits'],
        selectedFolder: 'Music Barat',
        lyricsCandidates: const <LyricsCandidate>[sampleCandidate],
        selectedLyricsCandidate: sampleCandidate,
      );

      bool newFolderCalled = false;

      Future<void> pumpSheet({
        required String lang,
        required ThemeMode mode,
      }) async {
        AppStrings.debugLanguageCodeOverride = lang;
        final palette =
            mode == ThemeMode.dark ? MusEveePalette.dark : MusEveePalette.light;
        await tester.pumpWidget(
          ChangeNotifierProvider<DownloaderProvider>.value(
            value: provider,
            child: MaterialApp(
              themeMode: mode,
              theme: ThemeData.light(useMaterial3: true).copyWith(
                extensions: const <ThemeExtension<dynamic>>[
                  MusEveePalette.light,
                ],
              ),
              darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
                extensions: const <ThemeExtension<dynamic>>[
                  MusEveePalette.dark
                ],
              ),
              home: Scaffold(
                backgroundColor: palette.nowPlayingBg,
                body: TrackPreviewSheet(
                  onCreateNewFolder: (_) async {
                    newFolderCalled = true;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      // 1. English Light Mode verification
      await pumpSheet(lang: 'en', mode: ThemeMode.light);

      expect(find.text('Memories'), findsOneWidget);
      expect(find.text('Conan Gray'), findsOneWidget);
      expect(find.text('Superache • 2026 • 04:08'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('track_preview_play_btn')), findsOneWidget);
      final previewPlayIcon = tester.widget<Icon>(
        find.byKey(const ValueKey('preview_play_icon')),
      );
      expect(previewPlayIcon.icon, Icons.play_arrow_rounded);
      expect(
          find.byKey(const ValueKey('track_preview_edit_btn')), findsOneWidget);
      expect(find.text('Audio source: Automatic'), findsOneWidget);
      expect(find.text('Change Source'), findsOneWidget);
      expect(find.text('Synced lyrics'), findsOneWidget);
      expect(find.text('Plain lyrics'), findsOneWidget);
      expect(find.text('[English/other]'), findsOneWidget);
      expect(find.textContaining('[['), findsNothing);
      expect(find.textContaining('Inggris/Lainnya'), findsNothing);
      expect(find.text('Change lyrics'), findsOneWidget);
      expect(find.textContaining('[00:00.65] One, Two'), findsOneWidget);
      expect(find.text('Folder destination'), findsOneWidget);
      expect(find.text('New folder'), findsOneWidget);
      expect(find.text('Save to Music Barat'), findsOneWidget);
      expect(find.text('Add to download list'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Toggle to Plain lyrics segment -> switches preview text cleanly
      await tester.tap(find.text('Plain lyrics'));
      await tester.pumpAndSettle();
      expect(provider.preferSyncedLyrics, isFalse);

      // Switch folder chip -> updates Save CTA label dynamically
      await tester.tap(find.text('Music Japan'));
      await tester.pumpAndSettle();
      expect(provider.selectedFolder, 'Music Japan');
      expect(find.text('Save to Music Japan'), findsOneWidget);

      // Tap "+ New folder"
      await tester
          .tap(find.byKey(const ValueKey('track_preview_new_folder_btn')));
      await tester.pumpAndSettle();
      expect(newFolderCalled, isTrue);

      // 2. Indonesian Dark Mode verification + Pencil Edit trigger
      await pumpSheet(lang: 'id', mode: ThemeMode.dark);
      expect(find.text('Sumber Audio: Otomatis'), findsOneWidget);
      expect(find.text('Ganti Sumber'), findsOneWidget);
      expect(find.text('Lirik Berjalan'), findsOneWidget);
      expect(find.text('Lirik Biasa'), findsOneWidget);
      expect(find.text('[Inggris/Lainnya]'), findsOneWidget);
      expect(find.textContaining('[['), findsNothing);
      expect(find.text('Ganti Lirik'), findsOneWidget);
      expect(find.text('Folder Tujuan'), findsOneWidget);
      expect(find.text('Folder baru'), findsOneWidget);
      expect(find.text('Simpan ke Music Japan'), findsOneWidget);
      expect(find.text('Masukkan ke antrean'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Tapping pencil edit button opens monochrome TagEditorSheet (Dark ID)
      await tester.tap(find.byKey(const ValueKey('track_preview_edit_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TagEditorSheet), findsOneWidget);
      expect(find.text('Edit Info & Lirik'), findsOneWidget);
      expect(find.text('Simpan'), findsOneWidget);
      final saveButtonDark = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Simpan'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(
        saveButtonDark.style?.backgroundColor?.resolve(const <WidgetState>{}),
        MusEveePalette.dark.nowPlayingPrimary,
      );
      expect(tester.takeException(), isNull);

      // Verify English Light Mode TagEditorSheet monochrome & localization
      Navigator.of(tester.element(find.byType(TagEditorSheet))).pop();
      await tester.pumpAndSettle();
      await pumpSheet(lang: 'en', mode: ThemeMode.light);
      await tester.tap(find.byKey(const ValueKey('track_preview_edit_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Edit Info & Lyrics'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      final saveButtonLight = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Save'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(
        saveButtonLight.style?.backgroundColor?.resolve(const <WidgetState>{}),
        MusEveePalette.light.nowPlayingPrimary,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'AppStrings.isIndonesianInContext and MusEveeApp follow system locale (en/id/in) live across all tabs without overflow',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      addTearDown(() {
        AppStrings.debugLanguageCodeOverride = null;
      });

      AppStrings.debugLanguageCodeOverride = null;
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');

      await tester.pumpWidget(const MusEveeApp());
      await tester.pump();
      await tester.pumpAndSettle();

      // Context inside MaterialApp (default supportedLocales: [en_US]) still obeys platform locale
      final ctxEn = tester.element(find.byType(HomeScreen));
      expect(AppStrings.isIndonesianInContext(ctxEn), isFalse);

      // Now Playing empty state (EN)
      expect(find.text('MusEvee Player'), findsOneWidget);
      expect(find.byTooltip('Playback Queue'), findsOneWidget);
      expect(find.byTooltip('Music Folders'), findsOneWidget);
      expect(find.byTooltip('Search & Download'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);

      // Tab 0: Queue (EN)
      await tester.tap(find.byTooltip('Playback Queue'));
      await tester.pumpAndSettle();
      expect(find.text('Playback queue is empty'), findsOneWidget);
      expect(find.text('Antrean putar masih kosong'), findsNothing);

      // Tab 3: Playlists (EN)
      await tester.tap(find.byTooltip('Playlists'));
      await tester.pumpAndSettle();
      expect(find.text('Your playlists'), findsOneWidget);
      expect(find.text('New Playlist'), findsOneWidget);
      expect(find.text('Playlist kamu'), findsNothing);
      expect(find.text('Playlist Baru'), findsNothing);

      // Tab 4: Downloader (EN)
      await tester.tap(find.byTooltip('Search & Download'));
      await tester.pumpAndSettle();
      expect(find.text('Title/Artist'), findsOneWidget);
      expect(find.text('YouTube/YT Music Link'), findsOneWidget);
      expect(find.text('Link Yotube/YT Music'), findsNothing);
      expect(find.text('Spotify Link'), findsOneWidget);
      expect(find.text("This week's top songs"), findsOneWidget);
      expect(find.text('For You'), findsOneWidget);
      expect(find.text('Playlists for you'), findsOneWidget);
      expect(find.byTooltip('Download Queue & History'), findsOneWidget);

      // Open Download Queue & History sheet (EN)
      await tester.tap(find.byTooltip('Download Queue & History'));
      await tester.pumpAndSettle();
      expect(find.byType(QueueHistoryView), findsOneWidget);
      expect(find.text('Download Queue & History'), findsOneWidget);
      expect(find.text('Active Download Queue'), findsOneWidget);
      expect(find.text('Download History'), findsOneWidget);
      expect(find.text('No active downloads right now.'), findsOneWidget);
      expect(find.text('No download history in this session yet.'),
          findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('Antrean & Riwayat Unduhan'), findsNothing);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // Scroll Downloader to verify lower section headings (EN)
      await tester.drag(find.byType(ListView).first, const Offset(0, -520));
      await tester.pumpAndSettle();
      expect(find.text('New releases'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('Top Indonesian songs'), findsOneWidget);

      // Tab 5: Settings (EN)
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('App Theme'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Best — 320 kbps'), findsOneWidget);
      expect(find.text('Tampilan'), findsNothing);

      // Open Theme dropdown in EN to verify Auto / Dark / Light items, then close it
      await tester.tap(find.byKey(const ValueKey('theme_mode_dropdown')));
      await tester.pumpAndSettle();
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('theme_mode_system')));
      await tester.pumpAndSettle();

      // Live system locale change: EN -> ID (Android 'id' and legacy Android 'in')
      tester.platformDispatcher.localeTestValue = const Locale('id', 'ID');
      await tester.pumpAndSettle();

      final ctxId = tester.element(find.byType(HomeScreen));
      expect(AppStrings.isIndonesianInContext(ctxId), isTrue);
      expect(find.text('Tampilan'), findsOneWidget);
      expect(find.text('Tema Aplikasi'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Terbaik — 320 kbps'), findsOneWidget);
      expect(find.byTooltip('Pengaturan'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('theme_mode_dropdown')));
      await tester.pumpAndSettle();
      expect(find.text('Gelap'), findsOneWidget);
      expect(find.text('Terang'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('theme_mode_system')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cari & Unduh Lagu (Downloader)'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 950));
      await tester.pumpAndSettle();
      expect(find.text('Judul/Artis'), findsOneWidget);
      expect(find.text('Lagu teratas minggu ini'), findsOneWidget);
      expect(find.text('Untukmu'), findsOneWidget);
      expect(find.text('Playlist untukmu'), findsOneWidget);

      // Legacy Android Indonesian locale code ('in') must also resolve to Indonesian
      tester.platformDispatcher.localeTestValue = const Locale('in', 'ID');
      await tester.pumpAndSettle();
      expect(
        AppStrings.isIndonesianInContext(
            tester.element(find.byType(HomeScreen))),
        isTrue,
      );
      expect(find.text('Judul/Artis'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'BatchPlaylistSheet localizes song counts, folder chips, and CTAs cleanly in English at 360px',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() {
        AppStrings.debugLanguageCodeOverride = null;
      });

      AppStrings.debugLanguageCodeOverride = 'en';
      final settingsProvider = SettingsProvider();
      final provider = DownloaderProvider(
        settingsProvider: settingsProvider,
      );
      addTearDown(settingsProvider.dispose);
      addTearDown(provider.dispose);

      provider.seedDiscoveryCarouselsForTesting(
        playlists: <CuratedPlaylist>[
          CuratedPlaylist(
            id: 'galau',
            deezerPlaylistId: '15234906703',
            title: 'Lagu Galau Indonesia 2026',
            songCount: 2,
            spotifyUrl: 'https://www.deezer.com/playlist/15234906703',
            preloadedTracks: <TrackMetadata>[
              _track(101, title: 'Galau Track A', artist: 'Fajar Noor'),
              _track(102, title: 'Galau Track B', artist: 'Lyodra'),
            ],
          ),
        ],
      );
      await provider.loadCuratedPlaylist(provider.curatedPlaylists.first);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(
              value: settingsProvider,
            ),
            ChangeNotifierProvider<DownloaderProvider>.value(
              value: provider,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.light,
              fontFamily: 'Poppins',
              extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
            ),
            home: Scaffold(
              body: BatchPlaylistSheet(
                initialTitle: 'Lagu Galau Indonesia 2026',
                onCreateNewFolder: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('2 curated songs by MusEvee • 2 Songs'),
        findsOneWidget,
      );
      expect(find.text('Save 2 Songs to MusEvee'), findsOneWidget);
      expect(find.text('Deselect All'), findsOneWidget);
      expect(find.text('Target Folder:'), findsOneWidget);
      expect(find.text('+ New'), findsOneWidget);
      expect(find.textContaining('2 lagu'), findsNothing);
      expect(find.textContaining('Folder Tujuan'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'QueueHistoryView uses monochrome palette instead of accent blue in Light and Dark themes',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsProvider = SettingsProvider();
      final provider = DownloaderProvider(
        settingsProvider: settingsProvider,
      );
      addTearDown(settingsProvider.dispose);
      addTearDown(provider.dispose);
      provider.seedQueueItemsForTesting([
        DownloadItem(
          id: 'active_1',
          metadata: _track(201, title: 'Active Track', artist: 'Artist One'),
          targetFolderName: 'Pop',
          status: DownloadItemStatus.downloading,
          progress: 0.48,
          statusDetail: 'Downloading audio...',
          createdAt: DateTime(2026, 11, 13, 10, 0),
        ),
        DownloadItem(
          id: 'done_1',
          metadata: _track(202, title: 'Completed Track', artist: 'Artist Two'),
          targetFolderName: 'Pop',
          status: DownloadItemStatus.completed,
          progress: 1.0,
          statusDetail: 'Completed',
          savedFilePath: '/tmp/Pop/Completed Track.mp3',
          createdAt: DateTime(2026, 11, 13, 9, 55),
        ),
      ]);

      for (final isDark in <bool>[false, true]) {
        final palette = isDark ? MusEveePalette.dark : MusEveePalette.light;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(
                value: settingsProvider,
              ),
              ChangeNotifierProvider<DownloaderProvider>.value(
                value: provider,
              ),
            ],
            child: MaterialApp(
              key: ValueKey<bool>(isDark),
              theme: ThemeData(
                useMaterial3: true,
                brightness: isDark ? Brightness.dark : Brightness.light,
                fontFamily: 'Poppins',
                extensions: <ThemeExtension<dynamic>>[palette],
              ),
              home: Scaffold(
                body: QueueHistoryView(
                  provider: provider,
                  onMoveFolder: (_, __) async {},
                  onPlaySavedFile: (_) async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final downloadingIcon = tester.widget<Icon>(
          find.byIcon(Icons.downloading_rounded),
        );
        expect(downloadingIcon.color, equals(palette.nowPlayingPrimary));
        expect(downloadingIcon.color, isNot(equals(palette.accent)));

        final historyIcon = tester.widget<Icon>(
          find.byIcon(Icons.history_rounded),
        );
        expect(historyIcon.color, equals(palette.nowPlayingPrimary));
        expect(historyIcon.color, isNot(equals(palette.accent)));

        final moveIcon = tester.widget<Icon>(
          find.byIcon(Icons.drive_file_move_outlined),
        );
        expect(moveIcon.color, equals(palette.nowPlayingPrimary));
        expect(moveIcon.color, isNot(equals(palette.accent)));

        final playIcon = tester.widget<Icon>(
          find.byIcon(Icons.play_arrow_rounded),
        );
        expect(playIcon.color, equals(palette.nowPlayingOnPrimary));
        expect(playIcon.color, isNot(equals(palette.accent)));

        final progressBar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(
          (progressBar.valueColor as AlwaysStoppedAnimation<Color>).value,
          equals(palette.nowPlayingPrimary),
        );

        final pctText = tester.widget<Text>(find.text('48%'));
        expect(pctText.style?.color, equals(palette.nowPlayingPrimary));

        final queueRootContainer = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(QueueHistoryView),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(queueRootContainer.color, equals(palette.nowPlayingBg));
        expect(
          progressBar.backgroundColor,
          equals(palette.nowPlayingPrimary.withValues(alpha: 0.14)),
        );
        for (final cardTitle in <String>['Active Track', 'Completed Track']) {
          final cardBox = tester.widget<Container>(
            find
                .ancestor(
                  of: find.text(cardTitle),
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is Container &&
                        w.decoration is BoxDecoration &&
                        (w.decoration as BoxDecoration).borderRadius ==
                            BorderRadius.circular(8),
                  ),
                )
                .first,
          );
          expect(
            (cardBox.decoration! as BoxDecoration).color,
            equals(palette.surfaceSubtle),
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Point 1 monochrome cleanup: PlaybackQueueView empty state, showAddToPlaylistSheet, and MusEveeLogo fallback avoid legacy accent blue in Light & Dark themes',
    (WidgetTester tester) async {
      AppStrings.debugLanguageCodeOverride = 'id';
      addTearDown(() {
        AppStrings.debugLanguageCodeOverride = null;
      });

      const dummySong = LocalSong(
        filePath: '/storage/emulated/0/Music/Pop/Sample.mp3',
        fileName: 'Sample.mp3',
        folderName: 'Pop',
        title: 'Sample Song',
        artist: 'Sample Artist',
        album: 'Sample Album',
        year: '2026',
        durationMs: 180000,
        sizeBytes: 3000000,
        bitrateKbps: 320,
        sampleRateHz: 44100,
        lastModifiedMs: 1700000000000,
      );

      for (final isDark in <bool>[false, true]) {
        final palette = isDark ? MusEveePalette.dark : MusEveePalette.light;
        final localProvider = LocalMusicProvider();
        addTearDown(localProvider.dispose);

        Future<void> pumpHarness() async {
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<LocalMusicProvider>.value(
                  value: localProvider,
                ),
              ],
              child: MaterialApp(
                key: ValueKey<bool>(isDark),
                theme: ThemeData(
                  useMaterial3: true,
                  brightness: isDark ? Brightness.dark : Brightness.light,
                  fontFamily: 'Poppins',
                  extensions: <ThemeExtension<dynamic>>[palette],
                ),
                home: Scaffold(
                  body: Column(
                    children: [
                      DefaultAssetBundle(
                        bundle: _MissingAssetBundle(),
                        child: const MusEveeLogo(size: 32),
                      ),
                      Builder(
                        builder: (btnCtx) => TextButton(
                          onPressed: () {
                            showAddToPlaylistSheet(
                              btnCtx,
                              localProvider: localProvider,
                              song: dummySong,
                            );
                          },
                          child: const Text('Open Playlist Sheet'),
                        ),
                      ),
                      Expanded(
                        child: PlaybackQueueView(
                          onOpenNowPlaying: () {},
                          onNavigateToDownloader: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await pumpHarness();

        // 1. MusEveeLogo fallback icon uses monochrome nowPlayingPrimary
        final logoFallbackIcon = tester.widget<Icon>(
          find.byIcon(Icons.music_note_rounded),
        );
        expect(logoFallbackIcon.color, equals(palette.nowPlayingPrimary));
        expect(logoFallbackIcon.color, isNot(equals(palette.accent)));

        // 2. PlaybackQueueView empty state ("Cari & Unduh Lagu") uses monochrome tokens
        expect(find.text('Cari & Unduh Lagu'), findsOneWidget);
        final emptyBtnNoSongs = tester.widget<ElevatedButton>(
          find.byKey(const ValueKey('queue_empty_primary_button')),
        );
        expect(
          emptyBtnNoSongs.style?.backgroundColor?.resolve(
            const <WidgetState>{},
          ),
          equals(palette.nowPlayingPrimary),
        );
        expect(
          emptyBtnNoSongs.style?.backgroundColor?.resolve(
            const <WidgetState>{},
          ),
          isNot(equals(palette.accent)),
        );
        expect(
          emptyBtnNoSongs.style?.foregroundColor?.resolve(
            const <WidgetState>{},
          ),
          equals(palette.nowPlayingOnPrimary),
        );

        // 3. PlaybackQueueView with local songs ("Putar Semua Lagu Lokal")
        localProvider.seedSongsForTesting([dummySong]);
        await tester.pumpAndSettle();
        expect(find.text('Putar Semua Lagu Lokal'), findsOneWidget);
        final emptyBtnWithSongs = tester.widget<ElevatedButton>(
          find.byKey(const ValueKey('queue_empty_primary_button')),
        );
        expect(
          emptyBtnWithSongs.style?.backgroundColor?.resolve(
            const <WidgetState>{},
          ),
          equals(palette.nowPlayingPrimary),
        );
        expect(
          emptyBtnWithSongs.style?.foregroundColor?.resolve(
            const <WidgetState>{},
          ),
          equals(palette.nowPlayingOnPrimary),
        );

        // 4. showAddToPlaylistSheet ("Playlist Baru…") uses monochrome nowPlayingPrimary
        await tester.tap(find.text('Open Playlist Sheet'));
        await tester.pumpAndSettle();
        final newPlaylistIcon = tester.widget<Icon>(
          find.byIcon(Icons.playlist_add_rounded),
        );
        expect(newPlaylistIcon.color, equals(palette.nowPlayingPrimary));
        expect(newPlaylistIcon.color, isNot(equals(palette.accent)));

        final newPlaylistText = tester.widget<Text>(find.text('Playlist Baru…'));
        expect(newPlaylistText.style?.color, equals(palette.nowPlayingPrimary));
        expect(newPlaylistText.style?.color, isNot(equals(palette.accent)));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Downloader queue circular button progress track uses high-contrast monochrome onPrimary alpha in Dark mode',
    (WidgetTester tester) async {
      AppStrings.debugLanguageCodeOverride = 'en';
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(() {
        AppStrings.debugLanguageCodeOverride = null;
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
      });

      await tester.pumpWidget(const MusEveeApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search & Download'));
      await tester.pumpAndSettle();

      final homeEl = tester.element(find.byType(HomeScreen));
      final downloaderProvider = Provider.of<DownloaderProvider>(
        homeEl,
        listen: false,
      );
      downloaderProvider.seedQueueItemsForTesting([
        DownloadItem(
          id: 'dark_contrast_1',
          metadata: _track(301, title: 'Dark Ring Track', artist: 'Monochrome'),
          targetFolderName: 'Pop',
          status: DownloadItemStatus.downloading,
          progress: 0.45,
          statusDetail: 'Downloading...',
          createdAt: DateTime(2026, 11, 14, 0, 5),
        ),
      ]);
      await tester.pump();

      final indicatorFinder = find.descendant(
        of: find.byTooltip('Download Queue & History'),
        matching: find.byType(CircularProgressIndicator),
      );
      expect(indicatorFinder, findsOneWidget);
      final indicator = tester.widget<CircularProgressIndicator>(indicatorFinder);
      expect(
        indicator.backgroundColor,
        equals(MusEveePalette.dark.nowPlayingOnPrimary.withValues(alpha: 0.24)),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Point 2 consistency: PlaybackQueueView localized header without counters and unified dialog/bottomSheet/popupMenu themes',
    (WidgetTester tester) async {
      addTearDown(() {
        AppStrings.debugLanguageCodeOverride = null;
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
      });

      const song = LocalSong(
        filePath: '/storage/emulated/0/Music/Pop/Track.mp3',
        fileName: 'Track.mp3',
        folderName: 'Pop',
        title: 'Track Title',
        artist: 'Track Artist',
        album: 'Track Album',
        year: '2026',
        durationMs: 180000,
        sizeBytes: 3000000,
        bitrateKbps: 320,
        sampleRateHz: 44100,
        lastModifiedMs: 1700000000000,
      );

      for (final isDark in <bool>[false, true]) {
        final palette = isDark ? MusEveePalette.dark : MusEveePalette.light;
        tester.platformDispatcher.platformBrightnessTestValue =
            isDark ? Brightness.dark : Brightness.light;
        AppStrings.debugLanguageCodeOverride = isDark ? 'en' : 'id';

        await tester.pumpWidget(MusEveeApp(key: ValueKey<bool>(isDark)));
        await tester.pumpAndSettle();

        final appWidget = tester.widget<MaterialApp>(find.byType(MaterialApp));
        final activeTheme = isDark ? appWidget.darkTheme! : appWidget.theme!;

        expect(activeTheme.dialogTheme.backgroundColor, equals(palette.nowPlayingBg));
        expect(
          activeTheme.dialogTheme.shape,
          equals(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: palette.hairline, width: 0.8),
            ),
          ),
        );
        expect(
          activeTheme.bottomSheetTheme.backgroundColor,
          equals(palette.nowPlayingBg),
        );
        expect(
          activeTheme.bottomSheetTheme.shape,
          equals(
            const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
          ),
        );
        expect(
          activeTheme.popupMenuTheme.color,
          equals(palette.surfaceCard),
        );
        expect(
          activeTheme.popupMenuTheme.shape,
          equals(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: palette.hairline, width: 0.8),
            ),
          ),
        );

        final queueTooltip =
            isDark ? 'Playback Queue' : 'Antrean Putar (Queue)';
        await tester.tap(find.byTooltip(queueTooltip));
        await tester.pumpAndSettle();

        final expectedHeader = isDark ? 'Playback Queue' : 'Antrean Putar';
        expect(find.text(expectedHeader), findsOneWidget);
        expect(find.text('Now Playing Queue (0)'), findsNothing);

        final homeEl = tester.element(find.byType(HomeScreen));
        final localProvider = Provider.of<LocalMusicProvider>(
          homeEl,
          listen: false,
        );
        await localProvider.playSong(song, queueContext: [song]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text(expectedHeader), findsOneWidget);
        expect(find.textContaining('(1/1)'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  test(
    'Point 4: AppStrings & TrackMetadata branding and copy consistency (ID & EN)',
    () {
      addTearDown(() {
        AppStrings.debugLanguageCodeOverride = null;
      });

      for (final lang in <String>['id', 'en']) {
        AppStrings.debugLanguageCodeOverride = lang;
        final isId = lang == 'id';

        expect(AppStrings.themeDarkSubtitle, contains('MusEvee'));
        expect(AppStrings.themeDarkSubtitle, isNot(contains('Musicolet')));
        expect(
          AppStrings.hiResAddonModalSubtitle,
          isNot(contains('(Tried in this order)')),
        );
        expect(
          AppStrings.hiResAddonDownloadsAllowed,
          equals(isId ? 'Unduhan diizinkan' : 'Downloads allowed'),
        );
        expect(
          AppStrings.hiResAddonStreamingOnly,
          equals(isId ? 'Hanya streaming' : 'Streaming only'),
        );
        expect(
          AppStrings.previewMetadataRomajiConverted,
          equals(
            isId
                ? 'Judul & artis dikonversi ke Romaji.'
                : 'Title & artist converted to Romaji.',
          ),
        );
        expect(AppStrings.noActiveDownloads, isNot(contains('FFmpeg')));
        expect(
          AppStrings.editorLyricsHeader,
          equals(isId ? 'Lirik Tertanam:' : 'Embedded Lyrics:'),
        );
        expect(
          AppStrings.searchResultsHeader(5),
          equals(isId ? 'Hasil pencarian (5 lagu)' : 'Search results (5 songs)'),
        );
        expect(
          AppStrings.searchResultsHeader(1),
          equals(isId ? 'Hasil pencarian (1 lagu)' : 'Search results (1 song)'),
        );
      }

      const emptyTrack = TrackMetadata(
        spotifyUrl: '',
        title: '',
        artist: '',
        album: '',
        releaseYear: '',
        durationSeconds: 180,
        coverUrl: '',
      );
      expect(emptyTrack.sanitizedBaseName, isNot(contains('SpotMeta')));
    },
  );

  testWidgets(
    'Point 3 & 4: Queue empty state removes emojis & uses SemiBold w600, elevated buttons default to w600, and live locale updates mini player, search tile, and TagEditorSheet',
    (WidgetTester tester) async {
      AppStrings.debugLanguageCodeOverride = null;
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(() {
        AppStrings.debugLanguageCodeOverride = null;
        tester.platformDispatcher.clearLocaleTestValue();
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
      });

      await tester.pumpWidget(const MusEveeApp());
      await tester.pumpAndSettle();

      final appWidget = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        appWidget.theme?.elevatedButtonTheme.style?.textStyle?.resolve({})
            ?.fontWeight,
        equals(FontWeight.w600),
      );
      expect(
        appWidget.darkTheme?.elevatedButtonTheme.style?.textStyle?.resolve({})
            ?.fontWeight,
        equals(FontWeight.w600),
      );

      // Navigate to Queue tab (empty state)
      await tester.tap(find.byTooltip('Playback Queue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('📁'), findsNothing);
      expect(find.textContaining('⬇'), findsNothing);
      final emptyTitle = tester.widget<Text>(
        find.text('Playback queue is empty'),
      );
      expect(emptyTitle.style?.fontWeight, equals(FontWeight.w600));

      // Seed active song -> verify MusicoletMiniPlayer uses w600 title and responds to live locale switch
      final homeEl = tester.element(find.byType(HomeScreen));
      final localProvider = Provider.of<LocalMusicProvider>(
        homeEl,
        listen: false,
      );
      final downloaderProvider = Provider.of<DownloaderProvider>(
        homeEl,
        listen: false,
      );
      const song = LocalSong(
        filePath: '/storage/emulated/0/Music/Pop/Neon.mp3',
        fileName: 'Neon.mp3',
        folderName: 'Pop',
        title: 'Neon Monochrome',
        artist: 'MusEvee Artist',
        album: 'Monochrome Album',
        year: '2026',
        durationMs: 185000,
        sizeBytes: 3000000,
        bitrateKbps: 320,
        sampleRateHz: 44100,
        lastModifiedMs: 1700000000000,
      );
      await localProvider.playSong(song, queueContext: [song]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final miniPlayerTitle = tester.widget<Text>(
        find.descendant(
          of: find.byType(MusicoletMiniPlayer),
          matching: find.text('Neon Monochrome'),
        ),
      );
      expect(miniPlayerTitle.style?.fontWeight, equals(FontWeight.w600));
      expect(
        find.descendant(
          of: find.byType(MusicoletMiniPlayer),
          matching: find.byTooltip('Next'),
        ),
        findsOneWidget,
      );

      // Switch live locale EN -> ID without unmounting
      tester.platformDispatcher.localeTestValue = const Locale('id', 'ID');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Antrean Putar'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MusicoletMiniPlayer),
          matching: find.byTooltip('Berikutnya'),
        ),
        findsOneWidget,
      );

      // Verify SearchResultTile & TagEditorSheet Mograph + typography + live locale
      final track = _track(901, title: 'Search Tile Song', artist: 'Artist X');
      await tester.pumpWidget(
        ChangeNotifierProvider<DownloaderProvider>.value(
          value: downloaderProvider,
          child: SystemLocaleScope(
            languageCode: 'id',
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: const <ThemeExtension<dynamic>>[
                  MusEveePalette.light,
                ],
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      SearchResultTile(
                        track: track,
                        duplicateFolder: 'Pop',
                        onTap: () {},
                      ),
                      TagEditorSheet(
                        provider: downloaderProvider,
                        track: track,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final tileTitleFinder = find.descendant(
        of: find.byType(SearchResultTile),
        matching: find.text('Search Tile Song'),
      );
      final tileTitle = tester.widget<Text>(tileTitleFinder);
      expect(tileTitle.style?.fontWeight, equals(FontWeight.w600));
      expect(
        find.ancestor(
          of: tileTitleFinder,
          matching: find.byType(MographSpringTap),
        ),
        findsOneWidget,
      );
      expect(find.text('Edit Info & Lirik'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Edit Info & Lirik')).style?.fontWeight,
        equals(FontWeight.w600),
      );
      expect(find.text('Lirik Tertanam:'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Batal'),
          matching: find.byType(MographSpringTap),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.text('Simpan'),
          matching: find.byType(MographSpringTap),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Point 5: LocalSong, DownloadItem, BrowsedDirectoryEntry, and AppStrings are format-aware & neutral for MP3/FLAC',
    () {
      addTearDown(() {
        AppStrings.debugLanguageCodeOverride = null;
      });

      const flacSong = LocalSong(
        filePath: '/storage/emulated/0/Music/Hi-Res/Yoasobi - Idol.FLAC',
        fileName: 'Yoasobi - Idol.FLAC',
        folderName: 'Hi-Res',
        title: 'Idol',
        artist: 'YOASOBI',
        album: 'The Book 3',
        year: '2023',
        durationMs: 213000,
        sizeBytes: 28000000,
        bitrateKbps: 1411,
        sampleRateHz: 48000,
        lastModifiedMs: 1700000000000,
      );
      const mp3Song = LocalSong(
        filePath: '/storage/emulated/0/Music/Pop/Neon.mp3',
        fileName: 'Neon.mp3',
        folderName: 'Pop',
        title: 'Neon',
        artist: 'Artist',
        album: 'Album',
        year: '2026',
        durationMs: 180000,
        sizeBytes: 5000000,
        bitrateKbps: 320,
        sampleRateHz: 44100,
        lastModifiedMs: 1700000000000,
      );

      expect(flacSong.isFlac, isTrue);
      expect(flacSong.audioFormatLabel, equals('FLAC'));
      expect(mp3Song.isFlac, isFalse);
      expect(mp3Song.audioFormatLabel, equals('MP3'));

      final now = DateTime(2026, 11, 14);
      final meta = _track(990, title: 'Idol', artist: 'YOASOBI');
      final flacByPath = DownloadItem(
        id: 'dl_flac_path',
        metadata: meta,
        targetFolderName: 'Hi-Res',
        status: DownloadItemStatus.completed,
        progress: 1.0,
        statusDetail: 'Done',
        savedFilePath: '/storage/emulated/0/Music/Hi-Res/YOASOBI - Idol.flac',
        createdAt: now,
      );
      final flacByDetail = DownloadItem(
        id: 'dl_flac_detail',
        metadata: meta,
        targetFolderName: 'Hi-Res',
        status: DownloadItemStatus.tagging,
        progress: 0.9,
        statusDetail: 'Menyematkan tag FLAC...',
        createdAt: now,
      );
      final mp3Item = DownloadItem(
        id: 'dl_mp3',
        metadata: meta,
        targetFolderName: 'Pop',
        status: DownloadItemStatus.completed,
        progress: 1.0,
        statusDetail: 'Selesai',
        savedFilePath: '/storage/emulated/0/Music/Pop/YOASOBI - Idol.mp3',
        createdAt: now,
      );

      expect(flacByPath.isFlac, isTrue);
      expect(flacByPath.audioFormatLabel, equals('FLAC'));
      expect(flacByDetail.isFlac, isTrue);
      expect(flacByDetail.audioFormatLabel, equals('FLAC'));
      expect(mp3Item.isFlac, isFalse);
      expect(mp3Item.audioFormatLabel, equals('MP3'));

      const entry = BrowsedDirectoryEntry(
        name: 'Hi-Res',
        path: '/storage/emulated/0/Music/Hi-Res',
        audioCount: 4,
      );
      expect(entry.audioCount, equals(4));
      expect(entry.mp3Count, equals(4));

      for (final lang in <String>['id', 'en']) {
        AppStrings.debugLanguageCodeOverride = lang;
        final isId = lang == 'id';

        expect(
          AppStrings.editorTitle(true),
          equals(
            isId ? 'Edit Tag & Lirik Tertanam' : 'Edit Tags & Embedded Lyrics',
          ),
        );
        expect(
          AppStrings.editorSubtitle(true, formatLabel: 'FLAC'),
          contains('FLAC'),
        );
        expect(AppStrings.editorSubtitle(true, formatLabel: 'FLAC'), isNot(contains('ID3')));
        expect(
          AppStrings.editorSubtitle(true, formatLabel: 'MP3'),
          contains('MP3'),
        );
        expect(AppStrings.editorSavedId3('FLAC'), contains('FLAC'));
        expect(AppStrings.editorSavedId3('FLAC'), isNot(contains('ID3')));
        expect(
          AppStrings.editorLyricsHeader,
          equals(isId ? 'Lirik Tertanam:' : 'Embedded Lyrics:'),
        );
        expect(AppStrings.downloaderCardTitle, contains('MP3 / Hi-Res FLAC'));
        expect(AppStrings.downloaderCardDesc, isNot(contains('MP3 secara native')));
        expect(AppStrings.dpLocalMp3PathUnavailable, isNot(contains('MP3')));
      }
    },
  );

  test(
    'Point 5: DownloaderProvider keeps .flac and .mp3 duplicate cache synchronized across syncWithLocalLibrary, retagCompletedItem, and moveItemToFolder',
    () async {
      final fakeTagging = _FakePoint5TaggingService();
      final fakeFolder = _FakePoint5FolderService();
      final provider = DownloaderProvider(
        taggingService: fakeTagging,
        folderService: fakeFolder,
      );

      final initialTrack = _track(
        995,
        title: 'Old Song',
        artist: 'Old Artist',
      );
      const localFlac = LocalSong(
        filePath: '/storage/emulated/0/Music/Pop/Old Artist - Old Song.flac',
        fileName: 'Old Artist - Old Song.flac',
        folderName: 'Pop',
        title: 'Old Song',
        artist: 'Old Artist',
        album: 'Album 995',
        year: '2026',
        durationMs: 185000,
        sizeBytes: 24000000,
        bitrateKbps: 1411,
        sampleRateHz: 48000,
        lastModifiedMs: 1700000000000,
      );

      provider.syncWithLocalLibrary(
        songs: <LocalSong>[localFlac],
        folders: const <String>['Pop', 'Hi-Res'],
      );
      expect(provider.duplicateFolderFor(initialTrack), equals('Pop'));

      provider.seedQueueItemsForTesting(<DownloadItem>[
        DownloadItem(
          id: 'item_flac_1',
          metadata: initialTrack,
          targetFolderName: 'Pop',
          status: DownloadItemStatus.completed,
          progress: 1.0,
          statusDetail: 'Selesai',
          savedFilePath: localFlac.filePath,
          createdAt: DateTime(2026, 11, 14),
        ),
      ]);

      final retaggedPath = await provider.retagCompletedItem(
        itemId: 'item_flac_1',
        title: 'New Title',
        artist: 'New Artist',
        album: 'New Album',
        releaseYear: '2026',
        lyricsText: '[00:01.00] Hello world',
        preferSyncedLyrics: true,
      );

      expect(fakeTagging.lastFilePath, equals(localFlac.filePath));
      expect(retaggedPath, endsWith('New Artist - New Title.flac'));
      expect(provider.duplicateFolderFor(initialTrack), isNull);

      final renamedTrack = initialTrack.copyWith(
        title: 'New Title',
        artist: 'New Artist',
        album: 'New Album',
      );
      expect(provider.duplicateFolderFor(renamedTrack), equals('Pop'));

      final movedPath = await provider.moveItemToFolder(
        itemId: 'item_flac_1',
        newFolderName: 'Hi-Res',
      );
      expect(fakeFolder.lastMoveCurrentPath, equals(retaggedPath));
      expect(fakeFolder.lastMoveTargetFolder, equals('Hi-Res'));
      expect(
        movedPath,
        equals('/storage/emulated/0/Music/Hi-Res/New Artist - New Title.flac'),
      );
      expect(provider.duplicateFolderFor(renamedTrack), equals('Hi-Res'));
      expect(provider.queueItems.first.targetFolderName, equals('Hi-Res'));
      expect(provider.queueItems.first.savedFilePath, equals(movedPath));
    },
  );

  testWidgets(
    'Point 5: TagEditorSheet renders format-aware FLAC subtitle and neutral embedded-lyrics copy (ID & EN)',
    (WidgetTester tester) async {
      AppStrings.debugLanguageCodeOverride = null;
      addTearDown(() {
        AppStrings.debugLanguageCodeOverride = null;
        tester.platformDispatcher.clearLocaleTestValue();
      });

      final provider = DownloaderProvider(
        taggingService: _FakePoint5TaggingService(),
        folderService: _FakePoint5FolderService(),
      );
      const flacSong = LocalSong(
        filePath: '/storage/emulated/0/Music/Hi-Res/Yoasobi - Idol.flac',
        fileName: 'Yoasobi - Idol.flac',
        folderName: 'Hi-Res',
        title: 'Idol',
        artist: 'YOASOBI',
        album: 'The Book 3',
        year: '2023',
        durationMs: 213000,
        sizeBytes: 28000000,
        bitrateKbps: 1411,
        sampleRateHz: 48000,
        lastModifiedMs: 1700000000000,
        usltLyrics: '[00:05.00] Muteki no egao',
        hasLyricsFlag: true,
        hasSyncedLyricsFlag: true,
      );

      for (final lang in <String>['id', 'en']) {
        tester.platformDispatcher.localeTestValue =
            lang == 'id' ? const Locale('id', 'ID') : const Locale('en', 'US');
        await tester.pumpWidget(
          SystemLocaleScope(
            languageCode: lang,
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: const <ThemeExtension<dynamic>>[
                  MusEveePalette.light,
                ],
              ),
              home: Scaffold(
                body: TagEditorSheet(
                  provider: provider,
                  track: flacSong.toTrackMetadata(),
                  localSong: flacSong,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        if (lang == 'id') {
          expect(find.text('Edit Tag & Lirik Tertanam'), findsOneWidget);
          expect(
            find.text(
              'Menulis ulang tag & lirik tertanam langsung ke file FLAC',
            ),
            findsOneWidget,
          );
          expect(find.text('Lirik Tertanam:'), findsOneWidget);
        } else {
          expect(find.text('Edit Tags & Embedded Lyrics'), findsOneWidget);
          expect(
            find.text(
              'Rewrite tags & embedded lyrics directly into the FLAC file',
            ),
            findsOneWidget,
          );
          expect(find.text('Embedded Lyrics:'), findsOneWidget);
        }
        expect(find.textContaining('USLT'), findsNothing);
        expect(find.textContaining('ID3'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  test(
    'Point 6: assets cleanup & Android monochrome cold-start splash resources match Light/Dark palette',
    () {
      final root = Directory.current;
      final pubspecText = File('${root.path}/pubspec.yaml').readAsStringSync();

      const keptAssetFiles = <String>[
        'assets/check.png',
        'assets/folder_picker.png',
        'assets/folder.png',
        'assets/icons/folder.png',
      ];
      for (final assetPath in keptAssetFiles) {
        expect(
          File('${root.path}/$assetPath').existsSync(),
          isTrue,
          reason: '$assetPath must exist after asset cleanup',
        );
      }
      for (final pubspecEntry in const <String>[
        'assets/check.png',
        'assets/folder_picker.png',
        'assets/folder.png',
        'assets/icons/',
      ]) {
        expect(
          pubspecText,
          contains(pubspecEntry),
          reason: '$pubspecEntry must remain listed in pubspec.yaml',
        );
      }

      const removedAssets = <String>[
        'assets/check (1).png',
        'assets/folder (3).png',
        'assets/back.png',
        'assets/equalizer.png',
        'assets/sorting.png',
        'assets/add-to-playlist.png',
        'assets/arrow.png',
        'assets/dot.png',
        'assets/downloading.png',
        'assets/music-album.png',
        'assets/play.png',
        'assets/repeat.png',
        'assets/settings.png',
      ];
      for (final assetPath in removedAssets) {
        expect(
          File('${root.path}/$assetPath').existsSync(),
          isFalse,
          reason: '$assetPath should have been removed during asset cleanup',
        );
        expect(
          pubspecText,
          isNot(contains(assetPath)),
          reason: '$assetPath must not be listed in pubspec.yaml',
        );
      }

      final lightColors = File(
        '${root.path}/android/app/src/main/res/values/colors.xml',
      ).readAsStringSync();
      final darkColors = File(
        '${root.path}/android/app/src/main/res/values-night/colors.xml',
      ).readAsStringSync();
      expect(lightColors, contains('#F7F8FA'));
      expect(lightColors, contains('#FFFFFF'));
      expect(darkColors, contains('#0E1014'));
      expect(darkColors, contains('#0A0C10'));

      for (final rel in const <String>[
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-v21/launch_background.xml',
      ]) {
        final xml = File('${root.path}/$rel').readAsStringSync();
        expect(xml, contains('@color/launch_bg'));
        expect(xml, isNot(contains('<bitmap')));
      }

      final v27Light = File(
        '${root.path}/android/app/src/main/res/values-v27/styles.xml',
      ).readAsStringSync();
      final v27Dark = File(
        '${root.path}/android/app/src/main/res/values-night-v27/styles.xml',
      ).readAsStringSync();
      final v31Light = File(
        '${root.path}/android/app/src/main/res/values-v31/styles.xml',
      ).readAsStringSync();
      final v31Dark = File(
        '${root.path}/android/app/src/main/res/values-night-v31/styles.xml',
      ).readAsStringSync();

      expect(v27Light, contains('windowLightNavigationBar">true<'));
      expect(v27Dark, contains('windowLightNavigationBar">false<'));
      expect(v31Light, contains('windowSplashScreenBackground">@color/launch_bg<'));
      expect(v31Light, contains('windowLightNavigationBar">true<'));
      expect(v31Dark, contains('windowSplashScreenBackground">@color/launch_bg<'));
      expect(v31Dark, contains('windowLightNavigationBar">false<'));
    },
  );
}

class _MissingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key.contains('AssetManifest')) {
      return rootBundle.load(key);
    }
    return Future<ByteData>.error(FlutterError('Missing test asset: $key'));
  }
}

class _FakePoint5TaggingService extends TaggingService {
  String? lastFilePath;

  @override
  Future<String> retagExistingAudio({
    required String filePath,
    required TrackMetadata updatedMetadata,
    required bool preferSyncedLyrics,
  }) async {
    lastFilePath = filePath;
    final slash = filePath.lastIndexOf('/');
    final dir = slash > 0 ? filePath.substring(0, slash) : '/storage/emulated/0/Music/Pop';
    return '$dir/${updatedMetadata.sanitizedFlacFileName}';
  }
}

class _FakePoint5FolderService extends FolderService {
  String? lastMoveCurrentPath;
  String? lastMoveTargetFolder;

  @override
  Future<List<String>> listAvailableFolders() async =>
      const <String>['Pop', 'Hi-Res'];

  @override
  Future<Map<String, int>> getFolderSongCounts(List<String> folders) async =>
      <String, int>{for (final f in folders) f: 1};

  @override
  Future<String> moveDownloadedFile({
    required String currentFilePath,
    required String targetFolderName,
  }) async {
    lastMoveCurrentPath = currentFilePath;
    lastMoveTargetFolder = targetFolderName;
    final fileName = currentFilePath.split('/').last;
    return '/storage/emulated/0/Music/$targetFolderName/$fileName';
  }
}

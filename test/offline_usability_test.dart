import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spotmeta_downloader/models/download_item.dart';
import 'package:spotmeta_downloader/models/local_song.dart';
import 'package:spotmeta_downloader/models/track_metadata.dart';
import 'package:spotmeta_downloader/providers/downloader_provider.dart';
import 'package:spotmeta_downloader/providers/local_music_provider.dart';
import 'package:spotmeta_downloader/services/folder_service.dart';
import 'package:spotmeta_downloader/services/romaji_service.dart';
import 'package:spotmeta_downloader/services/tagging_service.dart';
import 'package:spotmeta_downloader/theme/musevee_palette.dart';
import 'package:spotmeta_downloader/utils/app_strings.dart';
import 'package:spotmeta_downloader/widgets/now_playing_view.dart';
import 'package:spotmeta_downloader/widgets/tag_editor_sheet.dart';

LocalSong _offlineSong(
  int id, {
  String ext = 'mp3',
  String title = 'Track',
  String? usltLyrics,
}) {
  final fileName = 'Song_$id.$ext';
  return LocalSong(
    filePath: '/storage/emulated/0/Music/Music Japan/$fileName',
    fileName: fileName,
    folderName: 'Music Japan',
    title: '$title $id',
    artist: 'Artist $id',
    album: 'Album $id',
    year: '2026',
    durationMs: 180000,
    sizeBytes: 4096000,
    bitrateKbps: ext == 'flac' ? 1411 : 320,
    sampleRateHz: 44100,
    usltLyrics: usltLyrics,
    lastModifiedMs: 1700000000000 + id,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppStrings.debugLanguageCodeOverride = null;
  });

  group('Offline Usability & Background Engine Contracts', () {
    test(
      'AndroidManifest and Kotlin playback engine declare wake-lock, noisy headset pause, sleep timer, and Recents persistence',
      () {
        final root = Directory.current;
        final manifest = File(
          '${root.path}/android/app/src/main/AndroidManifest.xml',
        ).readAsStringSync();
        expect(
          manifest,
          contains('android.permission.WAKE_LOCK'),
        );
        expect(
          manifest,
          contains('MusEveePlaybackService'),
        );
        expect(
          manifest,
          contains('android:stopWithTask="false"'),
        );

        final engineKt = File(
          '${root.path}/android/app/src/main/kotlin/com/example/spotmeta_downloader/MusEveeAudioEngine.kt',
        ).readAsStringSync();
        expect(engineKt, contains('PARTIAL_WAKE_LOCK'));
        expect(engineKt, contains('ACTION_AUDIO_BECOMING_NOISY'));
        expect(engineKt, contains('fun setSleepTimer'));
        expect(engineKt, contains('fun cancelSleepTimer'));
        expect(engineKt, contains('fun getPlaybackSnapshot'));
        expect(engineKt, contains('fun syncQueue'));
        expect(engineKt, contains('onSleepTimerExpired'));

        final notifierKt = File(
          '${root.path}/android/app/src/main/kotlin/com/example/spotmeta_downloader/MusEveeMediaNotifier.kt',
        ).readAsStringSync();
        expect(notifierKt, contains('MusEveeAudioEngine.isActivelyPlaying()'));

        final mainActivityKt = File(
          '${root.path}/android/app/src/main/kotlin/com/example/spotmeta_downloader/MainActivity.kt',
        ).readAsStringSync();
        expect(mainActivityKt, contains('syncNativePlaybackQueue'));
        expect(mainActivityKt, contains('getNativePlaybackSnapshot'));
        expect(mainActivityKt, contains('setSleepTimer'));
        expect(mainActivityKt, contains('cancelSleepTimer'));
        expect(mainActivityKt, contains('musevee_romaji_cache_v1.json'));
      },
    );

    test(
      'All 7 scanned audio extensions have symmetric format labels, stem stripping, and safe non-MP3/FLAC tag guard',
      () async {
        const expected = <String, String>{
          'mp3': 'MP3',
          'flac': 'FLAC',
          'm4a': 'M4A',
          'wav': 'WAV',
          'ogg': 'OGG',
          'aac': 'AAC',
          'opus': 'OPUS',
        };

        for (final entry in expected.entries) {
          final ext = entry.key;
          final label = entry.value;
          final upperName = 'Track_Name.${ext.toUpperCase()}';

          expect(
            FolderService.isSupportedAudioFilePath('/music/$upperName'),
            isTrue,
            reason: 'Extension .$ext must be recognized',
          );
          expect(
            FolderService.stripAudioExtension(upperName),
            equals('Track_Name'),
          );

          final song = _offlineSong(1, ext: ext);
          expect(song.audioFormatLabel, equals(label));
          expect(
            song.supportsDirectTagEditing,
            equals(ext == 'mp3' || ext == 'flac'),
          );

          final item = DownloadItem(
            id: 'dl_$ext',
            metadata: const TrackMetadata(
              spotifyUrl: 'search:track',
              title: 'Song',
              artist: 'Artist',
              album: 'Album',
              releaseYear: '2026',
              durationSeconds: 180,
              coverUrl: '',
            ),
            targetFolderName: 'Music Barat',
            status: DownloadItemStatus.completed,
            progress: 1.0,
            statusDetail: 'Done',
            savedFilePath: '/storage/emulated/0/Music/Music Barat/Song.$ext',
            createdAt: DateTime(2026),
          );
          expect(item.audioFormatLabel, equals(label));
          expect(
            item.supportsDirectTagEditing,
            equals(ext == 'mp3' || ext == 'flac'),
          );
        }

        expect(FolderService.isSupportedAudioFilePath('notes.txt'), isFalse);
        expect(FolderService.isSupportedAudioFilePath('lyrics.lrc'), isFalse);

        // Ensure TaggingService refuses to write ID3 bytes onto non-MP3/FLAC formats.
        final taggingService = TaggingService();
        const dummyMeta = TrackMetadata(
          spotifyUrl: 'search:dummy',
          title: 'Safe Title',
          artist: 'Safe Artist',
          album: 'Album',
          releaseYear: '2026',
          durationSeconds: 180,
          coverUrl: '',
        );
        AppStrings.debugLanguageCodeOverride = 'en';
        await expectLater(
          () => taggingService.retagExistingAudio(
            filePath: '/storage/emulated/0/Music/Demo/song.m4a',
            updatedMetadata: dummyMeta,
            preferSyncedLyrics: true,
          ),
          throwsA(
            isA<TaggingException>().having(
              (e) => e.message,
              'message',
              allOf(contains('M4A'), contains('MP3 & FLAC')),
            ),
          ),
        );

        AppStrings.debugLanguageCodeOverride = 'id';
        await expectLater(
          () => taggingService.retagExistingAudio(
            filePath: '/storage/emulated/0/Music/Demo/song.opus',
            updatedMetadata: dummyMeta,
            preferSyncedLyrics: false,
          ),
          throwsA(
            isA<TaggingException>().having(
              (e) => e.message,
              'message',
              allOf(contains('OPUS'), contains('MP3 & FLAC')),
            ),
          ),
        );
      },
    );

    test(
      'RomajiService persists Kanji conversions to disk cache and converts Kana + previously cached Kanji 100% offline',
      () async {
        final tempDir =
            Directory.systemTemp.createTempSync('musevee_romaji_cache_test_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final cacheFile = File('${tempDir.path}/musevee_romaji_cache_v1.json');

        // 1. Offline Dio (throws SocketException on any HTTP request)
        final offlineDio = Dio();
        offlineDio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException.connectionError(
                  requestOptions: options,
                  reason: 'Simulated offline airplane mode',
                  error: const SocketException('Network unreachable'),
                ),
              );
            },
          ),
        );

        final offlineService = RomajiService(
          dio: offlineDio,
          cacheFile: cacheFile,
        );

        // Pure Kana converts 100% offline with lastConversionLeftUnconvertedKanji == false
        const kanaLrc =
            '[00:05.00] きみのなまえをよぶ\n[00:10.00] アイラブユー';
        final kanaOut = await offlineService.romanizeLyrics(kanaLrc);
        expect(kanaOut, contains('[00:05.00] kiminonamaeoyobu'));
        expect(kanaOut, contains('[00:10.00] airabuyu'));
        expect(RomajiService.containsJapanese(kanaOut), isFalse);
        expect(offlineService.lastConversionLeftUnconvertedKanji, isFalse);

        // Uncached Kanji while offline marks lastConversionLeftUnconvertedKanji == true
        const uncachedKanji = '[00:12.00] 夢の灯りを探して';
        final offlineKanjiOut =
            await offlineService.romanizeLyrics(uncachedKanji);
        expect(offlineKanjiOut, contains('夢'));
        expect(offlineService.lastConversionLeftUnconvertedKanji, isTrue);

        // 2. Online Dio populates and flushes persistent disk segment cache
        final onlineDio = Dio();
        onlineDio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    [
                      [null, null, null, 'yume no akari o sagashite']
                    ]
                  ],
                ),
              );
            },
          ),
        );

        final onlineService = RomajiService(
          dio: onlineDio,
          cacheFile: cacheFile,
        );
        final onlineConverted =
            await onlineService.romanizeLyrics(uncachedKanji);
        expect(onlineConverted, '[00:12.00] yume no akari o sagashite');
        expect(onlineService.lastConversionLeftUnconvertedKanji, isFalse);
        expect(cacheFile.existsSync(), isTrue);
        expect(cacheFile.readAsStringSync(), contains('yume no akari o sagashite'));

        // 3. New offline RomajiService instance reads the persisted cache without network
        final coldOfflineService = RomajiService(
          dio: offlineDio,
          cacheFile: cacheFile,
        );
        final cachedOfflineOut =
            await coldOfflineService.romanizeLyrics(uncachedKanji);
        expect(cachedOfflineOut, '[00:12.00] yume no akari o sagashite');
        expect(coldOfflineService.lastConversionLeftUnconvertedKanji, isFalse);
      },
    );

    test(
      'LocalMusicProvider handles Sleep Timer presets, End of Current Track stop, cancel, and native snapshot restore',
      () async {
        final methodCalls = <MethodCall>[];
        const channel = MethodChannel('com.spotmeta.downloader/system');

        final song1 = _offlineSong(1, title: 'First Track');
        final song2 = _offlineSong(2, title: 'Second Track');

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          methodCalls.add(call);
          if (call.method == 'getNativePlaybackSnapshot') {
            return <String, dynamic>{
              'hasActiveTrack': true,
              'isPlaying': true,
              'path': song2.filePath,
              'index': 1,
              'positionMs': 64200,
              'durationMs': 180000,
              'sessionId': 42,
              'volume': 0.8,
              'preAmpDb': 1.5,
              'sleepRemainingMs': 125000,
              'sleepAfterCurrentTrack': false,
              'playModeIndex': 0,
            };
          }
          if (call.method == 'localPlayFile' ||
              call.method == 'setVolume' ||
              call.method == 'syncNativePlaybackQueue' ||
              call.method == 'setSleepTimer' ||
              call.method == 'cancelSleepTimer') {
            return true;
          }
          return null;
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final lp = LocalMusicProvider();
        addTearDown(lp.dispose);
        lp.debugEnableNativeChannelInTests = true;
        lp.seedSongsForTesting([song1, song2]);

        await lp.playSong(song1, queueContext: [song1, song2]);
        expect(lp.isPlaying, isTrue);
        expect(lp.currentSong?.filePath, song1.filePath);

        // Sleep timer 15m preset
        await lp.startSleepTimer(const Duration(minutes: 15));
        expect(lp.hasActiveSleepTimer, isTrue);
        expect(lp.isSleepAfterCurrentTrack, isFalse);
        expect(lp.remainingSleepTimer, isNotNull);
        expect(
          methodCalls.any(
            (c) =>
                c.method == 'setSleepTimer' &&
                c.arguments is Map &&
                c.arguments['durationMs'] == 900000 &&
                c.arguments['afterCurrentTrack'] == false,
          ),
          isTrue,
        );

        // Cancel Sleep Timer
        await lp.cancelSleepTimer();
        expect(lp.hasActiveSleepTimer, isFalse);
        expect(
          methodCalls.any((c) => c.method == 'cancelSleepTimer'),
          isTrue,
        );

        // End of current track mode stops at auto-completion instead of advancing
        await lp.setSleepAfterCurrentTrack();
        expect(lp.hasActiveSleepTimer, isTrue);
        expect(lp.isSleepAfterCurrentTrack, isTrue);

        await lp.playNext(fromAutoComplete: true);
        expect(lp.isPlaying, isFalse);
        expect(lp.hasActiveSleepTimer, isFalse);
        expect(lp.currentSong?.filePath, song1.filePath);

        // Native background snapshot restoration aligns session, track, position & timer
        final restored = await lp.syncWithNativePlaybackSnapshot();
        expect(restored, isTrue);
        expect(lp.currentSong?.filePath, song2.filePath);
        expect(lp.isPlaying, isTrue);
        expect(lp.positionMs, equals(64200));
        expect(lp.volume, closeTo(0.8, 0.001));
        expect(lp.preAmpGainDb, closeTo(1.5, 0.001));
        expect(lp.hasActiveSleepTimer, isTrue);

        // Position tick carrying restored sessionId = 42 is accepted cleanly
        lp.handleNativePosition(
          positionMs: 65000,
          durationMs: 180000,
          isPlaying: true,
          sessionId: 42,
          path: song2.filePath,
        );
        expect(lp.positionMs, equals(65000));
      },
    );

    testWidgets(
      'TagEditorSheet shows non-destructive read-only warning and disables Save for M4A files (Light & Dark)',
      (WidgetTester tester) async {
        final downloaderProvider = DownloaderProvider();
        final m4aSong = _offlineSong(7, ext: 'm4a', title: 'Local Audio');
        addTearDown(downloaderProvider.dispose);

        for (final isDark in [false, true]) {
          AppStrings.debugLanguageCodeOverride = isDark ? 'en' : 'id';
          await tester.pumpWidget(
            MaterialApp(
              theme: (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
                extensions: <ThemeExtension<dynamic>>[
                  isDark ? MusEveePalette.dark : MusEveePalette.light,
                ],
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: TagEditorSheet(
                    provider: downloaderProvider,
                    track: m4aSong.toTrackMetadata(),
                    localSong: m4aSong,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);

          expect(
            find.textContaining('M4A'),
            findsWidgets,
          );
          final elevatedButton = tester.widget<ElevatedButton>(
            find.byType(ElevatedButton),
          );
          expect(elevatedButton.onPressed, isNull);
        }
      },
    );

    testWidgets(
      'NowPlayingView overflow Audio group exposes Sleep Timer sheet, live TopBar pill, and cancel flow (Light ID & Dark EN)',
      (WidgetTester tester) async {
        const channel = MethodChannel('com.spotmeta.downloader/system');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => true);
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        for (final isDark in [false, true]) {
          AppStrings.debugLanguageCodeOverride = isDark ? 'en' : 'id';
          final lp = LocalMusicProvider();
          final dp = DownloaderProvider();
          addTearDown(lp.dispose);
          addTearDown(dp.dispose);

          final song = _offlineSong(10, title: 'Midnight Track');
          lp.seedSongsForTesting([song]);
          await lp.playSong(song, queueContext: [song]);

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<LocalMusicProvider>.value(value: lp),
                ChangeNotifierProvider<DownloaderProvider>.value(value: dp),
              ],
              child: MaterialApp(
                theme: (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
                  extensions: <ThemeExtension<dynamic>>[
                    isDark ? MusEveePalette.dark : MusEveePalette.light,
                  ],
                ),
                home: Scaffold(
                  body: NowPlayingView(
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

          // Initially Sleep Timer pill is hidden
          expect(
            find.byKey(const ValueKey<String>('now_playing_sleep_pill')),
            findsNothing,
          );

          // Open overflow menu -> find Sleep Timer row
          await tester.tap(
            find.byKey(const ValueKey<String>('now_playing_overflow_button')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          final sleepTileFinder = find.byKey(
            const ValueKey<String>('overflow_sleep_timer_tile'),
          );
          await tester.ensureVisible(sleepTileFinder);
          await tester.pump(const Duration(milliseconds: 200));
          expect(sleepTileFinder, findsOneWidget);

          // Tap Sleep Timer row to open Sleep Timer modal sheet
          await tester.tap(sleepTileFinder);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          expect(
            find.byKey(const ValueKey<String>('sleep_timer_preset_15')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey<String>('sleep_timer_end_of_track')),
            findsOneWidget,
          );

          // Activate 15 min preset -> top-bar pill becomes visible
          await tester.tap(
            find.byKey(const ValueKey<String>('sleep_timer_preset_15')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          expect(lp.hasActiveSleepTimer, isTrue);
          final topPill =
              find.byKey(const ValueKey<String>('now_playing_sleep_pill'));
          expect(topPill, findsOneWidget);

          // Reopen via top-bar pill and turn off
          await tester.tap(topPill);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final turnOffFinder =
              find.byKey(const ValueKey<String>('sleep_timer_turn_off'));
          expect(turnOffFinder, findsOneWidget);
          await tester.tap(turnOffFinder);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          expect(lp.hasActiveSleepTimer, isFalse);
          expect(topPill, findsNothing);
        }
      },
    );
  });
}

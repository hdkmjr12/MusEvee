import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spotmeta_downloader/models/local_song.dart';
import 'package:spotmeta_downloader/providers/downloader_provider.dart';
import 'package:spotmeta_downloader/providers/local_music_provider.dart';
import 'package:spotmeta_downloader/providers/settings_provider.dart';
import 'package:spotmeta_downloader/services/tagging_service.dart';
import 'package:spotmeta_downloader/theme/musevee_palette.dart';
import 'package:spotmeta_downloader/utils/app_strings.dart';
import 'package:spotmeta_downloader/widgets/now_playing_view.dart';
import 'package:spotmeta_downloader/widgets/settings_view.dart';
import 'package:spotmeta_downloader/widgets/track_preview_sheet.dart';

void main() {
  setUp(() {
    AppStrings.debugLanguageCodeOverride = 'id';
  });

  tearDown(() {
    AppStrings.debugLanguageCodeOverride = null;
  });

  group('SettingsProvider & DownloadQuality Unit Tests', () {
    test('1. Default quality is DownloadQuality.best (320 kbps)', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'musevee_settings_default_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final provider = SettingsProvider(storageDirectory: tempDir);
      addTearDown(provider.dispose);
      await provider.initialized;

      expect(provider.downloadQuality, DownloadQuality.best);
      expect(provider.downloadBitrateKbps, 320);
    });

    test(
        '2. DownloadQuality enum to bitrateKbps mapping and TaggingService validation are accurate',
        () {
      expect(DownloadQuality.best.bitrateKbps, 320);
      expect(DownloadQuality.balanced.bitrateKbps, 192);
      expect(DownloadQuality.efficient.bitrateKbps, 128);

      expect(TaggingService.normalizeBitrateKbps(320), 320);
      expect(TaggingService.normalizeBitrateKbps(192), 192);
      expect(TaggingService.normalizeBitrateKbps(128), 128);
      expect(TaggingService.normalizeBitrateKbps(256), 320);
      expect(TaggingService.normalizeBitrateKbps(0), 320);
      expect(TaggingService.normalizeBitrateKbps(-64), 320);
    });

    test(
        '3. JSON save and load round-trip preserves selected DownloadQuality and syncs with DownloaderProvider',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'musevee_settings_roundtrip_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final writer = SettingsProvider(storageDirectory: tempDir);
      await writer.initialized;
      await writer.setDownloadQuality(DownloadQuality.balanced);
      expect(writer.downloadQuality, DownloadQuality.balanced);
      expect(writer.downloadBitrateKbps, 192);
      writer.dispose();

      final settingsFile = File(
        '${tempDir.path}${Platform.pathSeparator}${SettingsProvider.settingsFileName}',
      );
      expect(await settingsFile.exists(), isTrue);

      final reader = SettingsProvider(storageDirectory: tempDir);
      addTearDown(reader.dispose);
      await reader.initialized;

      expect(reader.downloadQuality, DownloadQuality.balanced);
      expect(reader.downloadBitrateKbps, 192);

      final dlProvider = DownloaderProvider(settingsProvider: reader);
      addTearDown(dlProvider.dispose);
      expect(dlProvider.activeDownloadBitrateKbps, 192);

      await reader.setDownloadQuality(DownloadQuality.efficient);
      expect(dlProvider.activeDownloadBitrateKbps, 128);
    });

    test(
        '4. Corrupted or missing JSON file safely falls back to DownloadQuality.best without throwing',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'musevee_settings_corrupt_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final settingsFile = File(
        '${tempDir.path}${Platform.pathSeparator}${SettingsProvider.settingsFileName}',
      );
      await settingsFile.writeAsString('{invalid_json: true, broken');

      final providerFromCorrupt = SettingsProvider(storageDirectory: tempDir);
      addTearDown(providerFromCorrupt.dispose);
      await expectLater(providerFromCorrupt.initialized, completes);
      expect(providerFromCorrupt.downloadQuality, DownloadQuality.best);
      expect(providerFromCorrupt.downloadBitrateKbps, 320);

      // Unknown enum value inside valid JSON also falls back to best (320)
      await settingsFile.writeAsString('{"downloadQuality": "ultra_lossless"}');
      final providerFromUnknown = SettingsProvider(storageDirectory: tempDir);
      addTearDown(providerFromUnknown.dispose);
      await expectLater(providerFromUnknown.initialized, completes);
      expect(providerFromUnknown.downloadQuality, DownloadQuality.best);
      expect(providerFromUnknown.downloadBitrateKbps, 320);
      expect(providerFromUnknown.themeMode, ThemeMode.dark);
    });

    test(
        '5. SettingsProvider reads v4.7 JSON file without "themeMode" key as ThemeMode.dark and persists Light/Dark toggles',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'musevee_settings_v47_compat_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final settingsFile = File(
        '${tempDir.path}${Platform.pathSeparator}${SettingsProvider.settingsFileName}',
      );
      // Simulate a v4.7 JSON file that only has downloadQuality
      await settingsFile.writeAsString('{"downloadQuality": "balanced"}');

      final provider = SettingsProvider(storageDirectory: tempDir);
      await provider.initialized;
      expect(provider.downloadQuality, DownloadQuality.balanced);
      expect(provider.themeMode, ThemeMode.dark);
      expect(provider.isDarkMode, isTrue);

      await provider.setThemeMode(ThemeMode.light);
      expect(provider.themeMode, ThemeMode.light);
      expect(provider.isDarkMode, isFalse);
      provider.dispose();

      final reloaded = SettingsProvider(storageDirectory: tempDir);
      addTearDown(reloaded.dispose);
      await reloaded.initialized;
      expect(reloaded.downloadQuality, DownloadQuality.balanced);
      expect(reloaded.themeMode, ThemeMode.light);
      expect(reloaded.isDarkMode, isFalse);
    });
  });

  testWidgets(
      '6. SettingsView renders in both Dark and Light themes without error and toggling theme updates MaterialApp.themeMode and SettingsProvider',
      (WidgetTester tester) async {
    final settingsProvider = SettingsProvider();
    addTearDown(settingsProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settingsProvider,
        child: Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            return MaterialApp(
              themeMode: settings.themeMode,
              theme: ThemeData.light(useMaterial3: true).copyWith(
                scaffoldBackgroundColor: MusEveePalette.light.bgCanvas,
                extensions: const <ThemeExtension<dynamic>>[
                  MusEveePalette.light,
                ],
              ),
              darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
                scaffoldBackgroundColor: MusEveePalette.dark.bgCanvas,
                extensions: const <ThemeExtension<dynamic>>[
                  MusEveePalette.dark,
                ],
              ),
              home: const Scaffold(
                body: SettingsView(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tampilan'), findsOneWidget);
    expect(find.text('Tema Aplikasi'), findsOneWidget);
    expect(find.text('Gelap'), findsOneWidget);
    expect(find.text('Terang'), findsOneWidget);
    expect(find.text('Unduhan'), findsOneWidget);
    expect(find.text('Terbaik — 320 kbps'), findsOneWidget);
    expect(find.text('Seimbang — 192 kbps'), findsOneWidget);
    expect(find.text('Hemat — 128 kbps'), findsOneWidget);
    expect(find.text('MusEvee v4.8'), findsOneWidget);

    MaterialApp appWidget = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(appWidget.themeMode, ThemeMode.dark);
    expect(settingsProvider.themeMode, ThemeMode.dark);
    expect(settingsProvider.downloadQuality, DownloadQuality.best);

    // Tap "Terang" theme option -> switches MaterialApp.themeMode to ThemeMode.light
    await tester.tap(find.byKey(const ValueKey('theme_mode_light')));
    await tester.pumpAndSettle();

    appWidget = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(appWidget.themeMode, ThemeMode.light);
    expect(settingsProvider.themeMode, ThemeMode.light);
    expect(tester.takeException(), isNull);

    // Tap "Hemat — 128 kbps" option while in Light theme
    await tester.tap(find.textContaining('Hemat'));
    await tester.pumpAndSettle();

    expect(settingsProvider.downloadQuality, DownloadQuality.efficient);
    expect(settingsProvider.downloadBitrateKbps, 128);

    // Tap "Gelap" theme option -> switches back to ThemeMode.dark
    await tester.tap(find.byKey(const ValueKey('theme_mode_dark')));
    await tester.pumpAndSettle();

    appWidget = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(appWidget.themeMode, ThemeMode.dark);
    expect(settingsProvider.themeMode, ThemeMode.dark);
  });

  testWidgets(
      '7. MusEveePalette copyWith/lerp and NowPlayingView (with active song & synced lyrics) + TrackPreviewSheet render cleanly in Light Mode',
      (WidgetTester tester) async {
    // Verify copyWith and lerp on MusEveePalette
    final copied = MusEveePalette.dark.copyWith(
      bgCanvas: const Color(0xFF112233),
    );
    expect(copied.bgCanvas, const Color(0xFF112233));
    expect(copied.accent, MusEveePalette.dark.accent);

    final lerpedMid = MusEveePalette.dark.lerp(MusEveePalette.light, 0.5);
    expect(
      lerpedMid.bgCanvas,
      Color.lerp(MusEveePalette.dark.bgCanvas, MusEveePalette.light.bgCanvas, 0.5),
    );

    final localProvider = LocalMusicProvider();
    final dlProvider = DownloaderProvider();
    addTearDown(localProvider.dispose);
    addTearDown(dlProvider.dispose);

    const song = LocalSong(
      filePath: '/storage/emulated/0/Music/Music Japan/Idol.mp3',
      fileName: 'Idol.mp3',
      folderName: 'Music Japan',
      title: 'Idol',
      artist: 'YOASOBI',
      album: 'THE BOOK 3',
      year: '2023',
      durationMs: 213000,
      sizeBytes: 8500000,
      bitrateKbps: 320,
      sampleRateHz: 44100,
      dominantColorValue: 0xFF7B2CBF,
      usltLyrics: '[00:01.00] Muteki no egao de arasu media\n[00:05.00] Shiritai sono himitsu mysterious',
      lastModifiedMs: 1700000000000,
    );
    localProvider.seedSongsForTesting([song]);
    await localProvider.playSong(song, queueContext: [song]);
    localProvider.handleNativePosition(
      positionMs: 2000,
      durationMs: 213000,
      isPlaying: false,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalMusicProvider>.value(value: localProvider),
          ChangeNotifierProvider<DownloaderProvider>.value(value: dlProvider),
        ],
        child: MaterialApp(
          themeMode: ThemeMode.light,
          theme: ThemeData.light(useMaterial3: true).copyWith(
            scaffoldBackgroundColor: MusEveePalette.light.bgCanvas,
            extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
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
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Idol'), findsWidgets);
    expect(find.text('YOASOBI'), findsWidgets);
    expect(
      find.textContaining('Muteki no egao'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Open TrackPreviewSheet in Light Mode
    final BuildContext scaffoldContext = tester.element(find.byType(Scaffold));
    // ignore: unawaited_futures
    showModalBottomSheet<void>(
      context: scaffoldContext,
      isScrollControlled: true,
      builder: (_) => TrackPreviewSheet(
        onCreateNewFolder: (_) async {},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TrackPreviewSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

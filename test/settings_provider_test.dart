// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:spotmeta_downloader/models/local_song.dart';
import 'package:spotmeta_downloader/models/track_metadata.dart';
import 'package:spotmeta_downloader/providers/downloader_provider.dart';
import 'package:spotmeta_downloader/providers/local_music_provider.dart';
import 'package:spotmeta_downloader/providers/settings_provider.dart';
import 'package:spotmeta_downloader/services/hires_addon_service.dart';
import 'package:spotmeta_downloader/services/tagging_service.dart';
import 'package:spotmeta_downloader/theme/musevee_palette.dart';
import 'package:spotmeta_downloader/utils/app_strings.dart';
import 'package:spotmeta_downloader/widgets/local_library_views.dart';
import 'package:spotmeta_downloader/widgets/now_playing_view.dart';
import 'package:spotmeta_downloader/widgets/pressable_scale.dart';
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
      expect(providerFromUnknown.themeMode, ThemeMode.system);
    });

    test(
        '5. SettingsProvider reads v4.7 JSON file without "themeMode" key as ThemeMode.system (Auto) and persists System/Light/Dark toggles',
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
      expect(provider.themeMode, ThemeMode.system);

      await provider.setThemeMode(ThemeMode.light);
      expect(provider.themeMode, ThemeMode.light);
      expect(provider.isDarkMode, isFalse);

      await provider.setThemeMode(ThemeMode.dark);
      expect(provider.themeMode, ThemeMode.dark);
      expect(provider.isDarkMode, isTrue);

      await provider.setThemeMode(ThemeMode.system);
      expect(provider.themeMode, ThemeMode.system);
      provider.dispose();

      final reloaded = SettingsProvider(storageDirectory: tempDir);
      addTearDown(reloaded.dispose);
      await reloaded.initialized;
      expect(reloaded.downloadQuality, DownloadQuality.balanced);
      expect(reloaded.themeMode, ThemeMode.system);
    });
  });

  testWidgets(
      '6. SettingsView renders monochrome dropdowns in Auto/Dark/Light modes, follows system brightness in Auto mode, and updates MaterialApp.themeMode and SettingsProvider',
      (WidgetTester tester) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue);

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
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Mengikuti tema sistem (Gelap)'), findsOneWidget);
    expect(find.text('Unduhan'), findsOneWidget);
    expect(find.text('Terbaik — 320 kbps'), findsOneWidget);
    expect(find.text('MusEvee v4.9'), findsOneWidget);

    // Verify monochrome colors (no blue accent on section title or manage badge)
    final appearanceHeader = tester.widget<Text>(find.text('Tampilan'));
    expect(appearanceHeader.style?.color, isNot(MusEveePalette.dark.accent));
    expect(appearanceHeader.style?.color, isNot(MusEveePalette.light.accent));
    final manageButtonLabel = tester.widget<Text>(find.text('Kelola'));
    expect(manageButtonLabel.style?.color,
        MusEveePalette.dark.nowPlayingOnPrimary);

    MaterialApp appWidget =
        tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(appWidget.themeMode, ThemeMode.system);
    expect(settingsProvider.themeMode, ThemeMode.system);
    expect(settingsProvider.downloadQuality, DownloadQuality.best);

    // System brightness flips Light while Auto is active -> UI follows system automatically
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpAndSettle();
    expect(find.text('Mengikuti tema sistem (Terang)'), findsOneWidget);

    // Open App Theme dropdown and select "Terang" -> ThemeMode.light
    await tester.tap(find.byKey(const ValueKey('theme_mode_dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('Gelap'), findsOneWidget);
    expect(find.text('Terang'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('theme_mode_light')));
    await tester.pumpAndSettle();

    appWidget = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(appWidget.themeMode, ThemeMode.light);
    expect(settingsProvider.themeMode, ThemeMode.light);
    expect(tester.takeException(), isNull);

    // Open Download Quality dropdown while in Light theme and select "Hemat — 128 kbps"
    final qualityDropdown = find.byKey(
      const ValueKey('download_quality_dropdown'),
    );
    await tester.ensureVisible(qualityDropdown);
    await tester.pumpAndSettle();
    await tester.tap(qualityDropdown);
    await tester.pumpAndSettle();
    expect(find.text('Hi-Res Lossless — FLAC'), findsOneWidget);
    expect(find.text('Seimbang — 192 kbps'), findsOneWidget);
    expect(find.text('Hemat — 128 kbps'), findsOneWidget);

    final efficientItem = find.byKey(
      const ValueKey('download_quality_efficient'),
    );
    await tester.tap(efficientItem);
    await tester.pumpAndSettle();

    expect(settingsProvider.downloadQuality, DownloadQuality.efficient);
    expect(settingsProvider.downloadBitrateKbps, 128);

    // Open App Theme dropdown and select "Gelap" -> ThemeMode.dark
    final themeDropdown = find.byKey(const ValueKey('theme_mode_dropdown'));
    await tester.ensureVisible(themeDropdown);
    await tester.pumpAndSettle();
    await tester.tap(themeDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme_mode_dark')));
    await tester.pumpAndSettle();

    appWidget = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(appWidget.themeMode, ThemeMode.dark);
    expect(settingsProvider.themeMode, ThemeMode.dark);

    // Switch back to "Auto" -> ThemeMode.system
    await tester.tap(themeDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme_mode_system')));
    await tester.pumpAndSettle();

    appWidget = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(appWidget.themeMode, ThemeMode.system);
    expect(settingsProvider.themeMode, ThemeMode.system);
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
      Color.lerp(
          MusEveePalette.dark.bgCanvas, MusEveePalette.light.bgCanvas, 0.5),
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
      usltLyrics:
          '[00:01.00] Muteki no egao de arasu media\n[00:05.00] Shiritai sono himitsu mysterious',
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
          ChangeNotifierProvider<LocalMusicProvider>.value(
              value: localProvider),
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

  group('v4.9 Hi-Res Lossless FLAC & Add-on Source Manager Tests', () {
    test(
        '8. Default presets include Monochrome + all 7 BitChord preset URLs enabled by default, and support toggle/reorder/add/remove/reset + JSON persistence',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'musevee_hires_addons_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final provider = SettingsProvider(storageDirectory: tempDir);
      addTearDown(provider.dispose);
      await provider.initialized;

      final urls = provider.hiResAddons.map((a) => a.url).toList();
      expect(urls, contains('https://tracks.monochrome.st'));
      expect(urls, contains('https://bit-chord-addon.vercel.app'));
      expect(
        urls,
        contains('https://addon-2.aurix.dpdns.org/free_rLnRPnC6oZF5gvAx'),
      );
      expect(
        urls,
        contains('https://eljohnzc-addon.de.deplexo.com/59efe06a96'),
      );
      expect(urls, contains('https://bitchord-hires-addon.de.deplexo.com'));
      expect(urls, contains('https://soundfean-musics.onrender.com/a'));
      expect(urls, contains('https://eljohnzc-mono.de.deplexo.com'));
      expect(urls, contains('https://8spine-modules.vercel.app/index.json'));
      expect(provider.hiResAddons.every((a) => a.enabled), isTrue);

      // Select DownloadQuality.hiResFlac
      await provider.setDownloadQuality(DownloadQuality.hiResFlac);
      expect(provider.downloadQuality, DownloadQuality.hiResFlac);
      expect(provider.downloadQuality.isLosslessFlac, isTrue);

      final dlProvider = DownloaderProvider(settingsProvider: provider);
      addTearDown(dlProvider.dispose);
      expect(dlProvider.isHiResFlacSelected, isTrue);

      // Toggle off the 2nd add-on
      final secondId = provider.hiResAddons[1].id;
      await provider.toggleAddonEnabled(secondId);
      expect(
        provider.hiResAddons.firstWhere((a) => a.id == secondId).enabled,
        isFalse,
      );

      // Reorder #0 to #2
      final firstId = provider.hiResAddons.first.id;
      await provider.reorderAddons(0, 3);
      expect(provider.hiResAddons[2].id, firstId);

      // Add custom URL
      final added = await provider.addAddonUrl(
        'https://custom-hires.example.com/module',
      );
      expect(added, isNotNull);
      expect(
        provider.hiResAddons.any(
          (a) => a.url == 'https://custom-hires.example.com/module',
        ),
        isTrue,
      );

      // Reload from disk and verify persistence
      final reloaded = SettingsProvider(storageDirectory: tempDir);
      addTearDown(reloaded.dispose);
      await reloaded.initialized;
      expect(reloaded.downloadQuality, DownloadQuality.hiResFlac);
      expect(
        reloaded.hiResAddons.firstWhere((a) => a.id == secondId).enabled,
        isFalse,
      );
      expect(
        reloaded.hiResAddons.any(
          (a) => a.url == 'https://custom-hires.example.com/module',
        ),
        isTrue,
      );

      // Reset to default presets
      await reloaded.resetAddonsToDefaultPresets();
      expect(
        reloaded.hiResAddons.length,
        SettingsProvider.defaultHiResAddonPresets.length,
      );
      expect(reloaded.hiResAddons.every((a) => a.enabled), isTrue);
    });

    test(
        '9. HiResAddonService header verification, index.json expansion, and TaggingService binary FLAC metadata writer',
        () async {
      expect(
        HiResAddonService.isFlacHeaderBytes([0x66, 0x4C, 0x61, 0x43, 0x00]),
        isTrue,
      );
      expect(
        HiResAddonService.isFlacHeaderBytes([0x49, 0x44, 0x33, 0x04]),
        isFalse,
      );

      final expanded = HiResAddonService.parseIndexCatalogModules([
        {
          'name': 'Module Alpha',
          'url': 'https://alpha.example.com',
          'version': '2.0.0',
          'streamingOnly': false,
        },
        {
          'title': 'Module Beta',
          'endpoint': 'https://beta.example.com',
          'downloadsAllowed': false,
        },
      ]);
      expect(expanded.length, 2);
      expect(expanded[0].name, 'Module Alpha');
      expect(expanded[0].downloadsAllowed, isTrue);
      expect(expanded[1].name, 'Module Beta');
      expect(expanded[1].downloadsAllowed, isFalse);

      // Verify binary FLAC VORBIS_COMMENT + PICTURE block writer
      final tempDir = await Directory.systemTemp.createTemp(
        'musevee_flac_tag_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dummyFlac = File('${tempDir.path}/test.flac');
      // Minimal valid FLAC stream: 'fLaC' + last-block STREAMINFO (type 0, length 34) + 4 dummy audio frame bytes
      final rawBytes = BytesBuilder(copy: false)
        ..add([0x66, 0x4C, 0x61, 0x43])
        ..add([0x80, 0x00, 0x00, 0x22])
        ..add(List<int>.filled(34, 0))
        ..add([0xFF, 0xF8, 0x69, 0x18]);
      await dummyFlac.writeAsBytes(rawBytes.takeBytes(), flush: true);

      const meta = TrackMetadata(
        spotifyUrl: 'search:Idol',
        title: 'Idol',
        artist: 'YOASOBI',
        album: 'THE BOOK 3',
        releaseYear: '2023',
        durationSeconds: 213,
        coverUrl: '',
        syncedLyrics: '[00:01.00] Muteki no egao',
      );

      await TaggingService().writeCompleteFlacMetadataBlocks(
        flacFile: dummyFlac,
        metadata: meta,
        preferSyncedLyrics: true,
        coverBytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]),
      );

      final taggedBytes = await dummyFlac.readAsBytes();
      expect(HiResAddonService.isFlacHeaderBytes(taggedBytes), isTrue);
      final asciiView = String.fromCharCodes(taggedBytes);
      expect(asciiView, contains('TITLE=Idol'));
      expect(asciiView, contains('ARTIST=YOASOBI'));
      expect(asciiView, contains('LYRICS=[00:01.00] Muteki no egao'));
      expect(asciiView, contains('image/jpeg'));
    });

    testWidgets(
        '10. SettingsView opens Kelola Sumber Add-on Hi-Res modal sheet, toggles switch, and adds custom add-on URL',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settingsProvider = SettingsProvider();
      addTearDown(settingsProvider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settingsProvider,
          child: MaterialApp(
            themeMode: ThemeMode.dark,
            darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
              scaffoldBackgroundColor: MusEveePalette.dark.bgCanvas,
              extensions: const <ThemeExtension<dynamic>>[MusEveePalette.dark],
            ),
            home: const Scaffold(
              body: SettingsView(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Download Quality dropdown and select Hi-Res Lossless — FLAC
      await tester.tap(find.byKey(const ValueKey('download_quality_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('download_quality_hiResFlac')),
      );
      await tester.pumpAndSettle();
      expect(settingsProvider.downloadQuality, DownloadQuality.hiResFlac);

      // Tap "Sumber Add-on Hi-Res (X Aktif) [Kelola >]" shortcut card
      final manageCard = find.byKey(const ValueKey('hires_addon_manage_card'));
      await tester.ensureVisible(manageCard);
      await tester.pumpAndSettle();
      await tester.tap(manageCard);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('hires_addon_manager_sheet')),
        findsOneWidget,
      );
      expect(find.text('Kelola Sumber Add-on Hi-Res'), findsOneWidget);
      expect(find.text('Monochrome [Qobuz · Tidal]'), findsOneWidget);
      expect(find.text('Qobuz [Heisenbergg]'), findsOneWidget);

      // Toggle off the first add-on switch
      final firstAddonId = settingsProvider.hiResAddons.first.id;
      await tester.tap(
        find.byKey(ValueKey('hires_addon_switch_$firstAddonId')),
      );
      await tester.pumpAndSettle();
      expect(settingsProvider.hiResAddons.first.enabled, isFalse);

      // Tap Reset Preset button -> re-enables all presets
      await tester.tap(find.byKey(const ValueKey('hires_addon_reset_btn')));
      await tester.pumpAndSettle();
      expect(settingsProvider.hiResAddons.first.enabled, isTrue);

      // Verify Add-on Manager switch & sync icon use monochrome Dark tokens
      final addonSwitch = tester.widget<Switch>(
        find.byKey(ValueKey('hires_addon_switch_$firstAddonId')),
      );
      expect(
        addonSwitch.activeThumbColor,
        equals(MusEveePalette.dark.nowPlayingOnPrimary),
      );
      expect(
        addonSwitch.activeTrackColor,
        equals(MusEveePalette.dark.nowPlayingPrimary),
      );
      final syncIcon = tester.widget<Icon>(find.byIcon(Icons.sync_rounded));
      expect(syncIcon.color, equals(MusEveePalette.dark.nowPlayingPrimary));
      expect(syncIcon.color, isNot(equals(MusEveePalette.dark.accent)));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '11. PlaybackQueueView uses assets/icons/arrow.png for Shuffle, localizes Bersihkan/Clear, and uses nowPlayingPrimary for Equalizer and active row highlight',
        (WidgetTester tester) async {
      final localProvider = LocalMusicProvider();
      addTearDown(localProvider.dispose);

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
        lastModifiedMs: 1700000000000,
      );
      const song2 = LocalSong(
        filePath: '/storage/emulated/0/Music/Music Japan/Yoru ni Kakeru.mp3',
        fileName: 'Yoru ni Kakeru.mp3',
        folderName: 'Music Japan',
        title: 'Yoru ni Kakeru',
        artist: 'YOASOBI',
        album: 'THE BOOK',
        year: '2021',
        durationMs: 261000,
        sizeBytes: 9500000,
        bitrateKbps: 320,
        sampleRateHz: 44100,
        lastModifiedMs: 1700000000001,
      );
      localProvider.seedSongsForTesting([song, song2]);
      await localProvider.playSong(song, queueContext: [song, song2]);

      AppStrings.debugLanguageCodeOverride = 'en';

      await tester.pumpWidget(
        ChangeNotifierProvider<LocalMusicProvider>.value(
          value: localProvider,
          child: MaterialApp(
            themeMode: ThemeMode.light,
            theme: ThemeData.light(useMaterial3: true).copyWith(
              scaffoldBackgroundColor: MusEveePalette.light.bgCanvas,
              extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
            ),
            home: Scaffold(
              body: PlaybackQueueView(
                onOpenNowPlaying: () {},
                onNavigateToDownloader: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify Queue header is localized without counters and uses SemiBold (w600), active song title uses SemiBold (w600), inactive song title uses Medium (w500)
      final queueHeaderText = tester.widget<Text>(find.text('Playback Queue'));
      expect(queueHeaderText.style?.fontWeight, FontWeight.w600);
      final activeSongTitle = tester.widget<Text>(find.text('Idol'));
      expect(activeSongTitle.style?.fontWeight, FontWeight.w600);
      final inactiveSongTitle =
          tester.widget<Text>(find.text('Yoru ni Kakeru'));
      expect(inactiveSongTitle.style?.fontWeight, FontWeight.w500);

      // Verify English "Clear" button label
      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('Bersihkan'), findsNothing);

      // Verify Shuffle button uses assets/icons/arrow.png and toggles shuffle state
      final shuffleBtn = find.byKey(
        const ValueKey('queue_header_shuffle_button'),
      );
      expect(shuffleBtn, findsOneWidget);
      Image shuffleImg = tester.widget<Image>(
        find.descendant(of: shuffleBtn, matching: find.byType(Image)),
      );
      expect(
        (shuffleImg.image as AssetImage).assetName,
        'assets/icons/arrow.png',
      );
      expect(shuffleImg.color, MusEveePalette.light.nowPlayingInactiveIcon);

      await tester.tap(shuffleBtn);
      await tester.pump();
      expect(localProvider.isShuffle, isTrue);
      shuffleImg = tester.widget<Image>(
        find.descendant(of: shuffleBtn, matching: find.byType(Image)),
      );
      expect(shuffleImg.color, MusEveePalette.light.nowPlayingPrimary);

      // Verify AnimatedEqualizerIcon uses nowPlayingPrimary (black in Light Mode)
      final eqWidget = tester.widget<AnimatedEqualizerIcon>(
        find.byType(AnimatedEqualizerIcon),
      );
      expect(eqWidget.color, MusEveePalette.light.nowPlayingPrimary);

      // Verify active row highlight uses nowPlayingPrimary with alpha 0.06 in Light Mode (not blue accent)
      final activeQueueId = localProvider.currentQueueEntry!.queueId;
      final rowMaterial = tester.widget<Material>(
        find.byKey(ValueKey(activeQueueId)),
      );
      expect(
        rowMaterial.color,
        MusEveePalette.light.nowPlayingPrimary.withValues(alpha: 0.06),
      );
    });

    test(
        '12. HiResAddonService automatically resumes interrupted FLAC stream using HTTP Range (206 Partial Content) without resetting to 0 MB',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'musevee_flac_resume_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      // Build a 320 KB valid FLAC payload ('fLaC' magic + sequential bytes, >= minValidFlacBytes 262 KB)
      const totalLen = 320 * 1024;
      const halfLen = 160 * 1024;
      final fullFlacBytes = Uint8List(totalLen);
      fullFlacBytes[0] = 0x66; // 'f'
      fullFlacBytes[1] = 0x4C; // 'L'
      fullFlacBytes[2] = 0x61; // 'a'
      fullFlacBytes[3] = 0x43; // 'C'
      for (int i = 4; i < totalLen; i++) {
        fullFlacBytes[i] = i & 0xFF;
      }

      int trackRequestCount = 0;
      String? observedRangeHeader;

      final mockClient = MockClient.streaming((request, bodyStream) async {
        final path = request.url.path;
        if (path.endsWith('/search/tracks')) {
          final jsonBytes = utf8.encode(
            jsonEncode({
              'tracks': [
                {
                  'id': '111',
                  'trackId': '111',
                  'recordingId': '222',
                  'title': 'Idol',
                  'artistNames': ['YOASOBI'],
                  'playable': true,
                  'duration': 213000,
                },
              ],
            }),
          );
          return http.StreamedResponse(
            Stream.value(jsonBytes),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (path.endsWith('/track/111')) {
          trackRequestCount++;
          if (trackRequestCount == 1) {
            // First request drops mid-stream after 160 KB (out of 320 KB)
            final firstHalf = fullFlacBytes.sublist(0, halfLen);
            Stream<List<int>> dropStream() async* {
              yield firstHalf;
              throw const SocketException('Simulated connection drop at 50%');
            }

            return http.StreamedResponse(
              dropStream(),
              200,
              contentLength: totalLen,
              headers: {
                'content-type': 'application/octet-stream',
                'accept-ranges': 'bytes',
              },
            );
          } else {
            // Second request must carry Range: bytes=163840- and return 206 Partial Content
            observedRangeHeader =
                request.headers['Range'] ?? request.headers['range'];
            final secondHalf = fullFlacBytes.sublist(halfLen);
            return http.StreamedResponse(
              Stream.value(secondHalf),
              206,
              contentLength: secondHalf.length,
              headers: {
                'content-type': 'application/octet-stream',
                'content-range': 'bytes $halfLen-${totalLen - 1}/$totalLen',
                'accept-ranges': 'bytes',
              },
            );
          }
        }

        return http.StreamedResponse(const Stream.empty(), 404);
      });

      final service = HiResAddonService(
        httpClient: mockClient,
        tempDirResolver: () async => tempDir,
      );

      final progressFractions = <double>[];
      const track = TrackMetadata(
        spotifyUrl: 'search:Idol',
        title: 'Idol',
        artist: 'YOASOBI',
        album: 'THE BOOK 3',
        releaseYear: '2023',
        durationSeconds: 213,
        coverUrl: '',
      );

      final result = await service.resolveAndDownloadHiResFlac(
        track,
        const <HiResAddonSource>[
          HiResAddonSource(
            id: 'preset_monochrome',
            url: 'https://tracks.monochrome.st',
            name: 'Monochrome [Qobuz · Tidal]',
            version: '2.10',
            capabilities: <String>['FLAC', 'Lossless', 'Hi-Res'],
            downloadsAllowed: true,
            enabled: true,
          ),
        ],
        onProgress: (frac, _) => progressFractions.add(frac),
      );

      expect(result, isNotNull);
      expect(trackRequestCount, 2);
      expect(observedRangeHeader, 'bytes=$halfLen-');
      expect(result!.sizeBytes, totalLen);
      final downloadedBytes = await result.flacFile.readAsBytes();
      expect(downloadedBytes.length, totalLen);
      expect(downloadedBytes, equals(fullFlacBytes));
      // Progress must monotonically advance (0.05 search -> 0.5 -> 1.0) without resetting to 0
      expect(progressFractions, [0.05, 0.5, 1.0]);
    });

    test(
        '13. HiResAddonService.scoreCandidateTrack rejects wrong-artist lookalikes and matches cross-script titles (Propose by 9Lana vs Naisho no Pierced Earrings)',
        () {
      const targetWithIsrc = TrackMetadata(
        spotifyUrl: 'https://www.deezer.com/track/2936968281',
        title: 'propose',
        artist: '9Lana',
        album: 'propose',
        releaseYear: '2024',
        durationSeconds: 234,
        coverUrl: '',
        isrc: 'JPU902402382',
      );
      const targetWithoutIsrc = TrackMetadata(
        spotifyUrl: 'search:9Lana - propose',
        title: 'propose',
        artist: '9Lana',
        album: 'propose',
        releaseYear: '2024',
        durationSeconds: 234,
        coverUrl: '',
      );

      final wrongOriginalArtist = <String, dynamic>{
        'trackId': '169340596832452608',
        'title': 'Propose',
        'artistNames': <String>['Naisho no Pierced Earrings'],
        'duration': 232106,
        'isrc': 'JPZ922307420',
      };
      final wrongDifferentSong = <String, dynamic>{
        'trackId': '189356387309649920',
        'title': 'プロポーズ',
        'artistNames': <String>['natori'],
        'duration': 178380,
        'isrc': 'JPU902501948',
      };
      final rightArtistInstrumental = <String, dynamic>{
        'trackId': '154037892321120256',
        'title': 'プロポーズ - Instrumental',
        'artistNames': <String>['9Lana'],
        'duration': 234120,
        'isrc': 'JPU902402487',
      };
      final right9LanaTrack = <String, dynamic>{
        'trackId': '170697937989402624',
        'title': 'プロポーズ',
        'artistNames': <String>['9Lana'],
        'duration': 234400,
        'isrc': 'JPU902402382',
      };

      // Both with and without ISRC, wrong-artist & instrumental tracks must score 0
      expect(
        HiResAddonService.scoreCandidateTrack(
            targetWithIsrc, wrongOriginalArtist),
        0,
      );
      expect(
        HiResAddonService.scoreCandidateTrack(
            targetWithoutIsrc, wrongOriginalArtist),
        0,
      );
      expect(
        HiResAddonService.scoreCandidateTrack(
            targetWithoutIsrc, wrongDifferentSong),
        0,
      );
      expect(
        HiResAddonService.scoreCandidateTrack(
            targetWithIsrc, rightArtistInstrumental),
        0,
      );

      // Exact artist + ISRC or cross-script Katakana ("プロポーズ") loanword match wins cleanly (>= 55)
      expect(
        HiResAddonService.scoreCandidateTrack(targetWithIsrc, right9LanaTrack),
        greaterThanOrEqualTo(150),
      );
      expect(
        HiResAddonService.scoreCandidateTrack(
            targetWithoutIsrc, right9LanaTrack),
        greaterThanOrEqualTo(100),
      );
    });
  });
}

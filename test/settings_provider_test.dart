import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spotmeta_downloader/providers/downloader_provider.dart';
import 'package:spotmeta_downloader/providers/settings_provider.dart';
import 'package:spotmeta_downloader/services/tagging_service.dart';
import 'package:spotmeta_downloader/utils/app_strings.dart';
import 'package:spotmeta_downloader/widgets/settings_view.dart';

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
    });
  });

  testWidgets(
      '5. SettingsView displays 3 download quality options and selecting "Hemat" updates SettingsProvider state',
      (WidgetTester tester) async {
    final settingsProvider = SettingsProvider();
    addTearDown(settingsProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settingsProvider,
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsView(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unduhan'), findsOneWidget);
    expect(find.text('Terbaik — 320 kbps'), findsOneWidget);
    expect(find.text('Seimbang — 192 kbps'), findsOneWidget);
    expect(find.text('Hemat — 128 kbps'), findsOneWidget);
    expect(find.text('MusEvee v4.7'), findsOneWidget);
    expect(settingsProvider.downloadQuality, DownloadQuality.best);

    // Tap "Hemat — 128 kbps" option
    await tester.tap(find.textContaining('Hemat'));
    await tester.pumpAndSettle();

    expect(settingsProvider.downloadQuality, DownloadQuality.efficient);
    expect(settingsProvider.downloadBitrateKbps, 128);
  });
}

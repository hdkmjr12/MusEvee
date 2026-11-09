import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotmeta_downloader/main.dart';
import 'package:spotmeta_downloader/models/local_song.dart';
import 'package:spotmeta_downloader/providers/local_music_provider.dart';

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
    final provider = LocalMusicProvider();
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
}

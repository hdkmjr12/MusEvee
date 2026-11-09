import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/local_song.dart';
import '../providers/downloader_provider.dart';
import '../providers/local_music_provider.dart';
import '../theme/musevee_palette.dart';
import 'local_library_views.dart';
import 'pressable_scale.dart';
import 'tag_editor_sheet.dart';

class NowPlayingView extends StatefulWidget {
  final VoidCallback onNavigateToDownloader;
  final VoidCallback onNavigateToFolders;
  final Future<void> Function(LocalSong song) onMoveLocalSongFolder;

  const NowPlayingView({
    super.key,
    required this.onNavigateToDownloader,
    required this.onNavigateToFolders,
    required this.onMoveLocalSongFolder,
  });

  @override
  State<NowPlayingView> createState() => _NowPlayingViewState();
}

class _NowPlayingViewState extends State<NowPlayingView> {
  final ScrollController _syncedScrollController = ScrollController();
  int _lastAutoScrolledIndex = -1;
  String? _lastSongPath;
  String? _requestedOnDemandLyricsPath;
  double? _dragSeekMs;

  static const double _lyricItemExtent = 44.0;

  @override
  void dispose() {
    _syncedScrollController.dispose();
    super.dispose();
  }

  void _syncAutoScrollIfNeeded({
    required LocalSong? song,
    required int activeIndex,
    required bool autoScroll,
    required double viewportHeight,
  }) {
    if (song == null) return;
    if (_lastSongPath != song.filePath) {
      _lastSongPath = song.filePath;
      _lastAutoScrolledIndex = -1;
    }
    if (!autoScroll || activeIndex < 0) return;
    if (activeIndex == _lastAutoScrolledIndex) return;

    _lastAutoScrolledIndex = activeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_syncedScrollController.hasClients) return;
      final maxExtent = _syncedScrollController.position.maxScrollExtent;
      // List has top padding = viewportHeight * 0.38 so index 0 can also sit near center
      final topPadding = viewportHeight * 0.36;
      final itemCenter =
          topPadding + (activeIndex * _lyricItemExtent) + (_lyricItemExtent / 2);
      final targetOffset =
          (itemCenter - (viewportHeight / 2)).clamp(0.0, maxExtent);
      _syncedScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Computes the Dynamic Ambient Background gradient from the Cover Art's
  /// dominant color:
  /// - Dark Mode: darkens and tones the dominant color toward `#0A0C10`.
  /// - Light Mode: blends the dominant color 82% toward white
  ///   (`Color.lerp(raw, Colors.white, 0.82)!`) and grades to `palette.bgCanvas`
  ///   (`#F6F7F9`).
  List<Color> _buildAmbientGradientColors(
    BuildContext context,
    LocalSong? song,
  ) {
    final palette = context.palette;
    final isDark = context.isDarkMode;

    if (!isDark) {
      if (song == null) {
        return [
          const Color(0xFFEEF1F6),
          const Color(0xFFF3F5F8),
          palette.bgCanvas,
        ];
      }
      final raw = Color(song.dominantColorValue);
      final tunedTop = Color.lerp(raw, Colors.white, 0.82)!;
      final tunedMid = Color.lerp(tunedTop, palette.bgCanvas, 0.56)!;
      return [tunedTop, tunedMid, palette.bgCanvas];
    }

    const baseBottom = Color(0xFF0A0C10);
    if (song == null) {
      return const [
        Color(0xFF1C2230),
        Color(0xFF12151D),
        baseBottom,
      ];
    }

    final raw = Color(song.dominantColorValue);
    final hsl = HSLColor.fromColor(raw);
    final tunedTop = hsl
        .withSaturation((hsl.saturation * 0.72).clamp(0.12, 0.58))
        .withLightness(hsl.lightness.clamp(0.16, 0.27))
        .toColor();
    final tunedMid = Color.lerp(tunedTop, const Color(0xFF0E1015), 0.56)!;

    return [tunedTop, tunedMid, baseBottom];
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<LocalMusicProvider, DownloaderProvider>(
      builder: (context, localProvider, downloaderProvider, _) {
        final song = localProvider.currentSong;
        final gradientColors = _buildAmbientGradientColors(context, song);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.54, 1.0],
              colors: gradientColors,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ==========================================================
                  // 1. AREA ATAS — COVER ART & PANEL `Embedded lyrics` MUSICOLET
                  // ==========================================================
                  Expanded(
                    child: _buildCoverAndLyricsPanel(
                      context: context,
                      localProvider: localProvider,
                      downloaderProvider: downloaderProvider,
                      song: song,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ==========================================================
                  // 2. AREA TENGAH — JUDUL, ARTIS, ALBUM & BARIS UTILITAS
                  // ==========================================================
                  _buildTrackInfoSection(song),
                  const SizedBox(height: 8),
                  _buildMusicoletUtilityRow(
                    context: context,
                    localProvider: localProvider,
                    downloaderProvider: downloaderProvider,
                    song: song,
                  ),
                  const SizedBox(height: 4),

                  // ==========================================================
                  // 3. AREA BAWAH — SEEKBAR & TRANSPORT CONTROLS MUSICOLET
                  // ==========================================================
                  _buildSeekbarRow(localProvider, song),
                  _buildTransportControlsRow(context, localProvider, song),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // TOP PANEL: COVER ART + MUSICOLET `Embedded lyrics` OVERLAY
  // ---------------------------------------------------------------------------
  Widget _buildCoverAndLyricsPanel({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required DownloaderProvider downloaderProvider,
    required LocalSong? song,
  }) {
    if (song == null) {
      return _buildEmptyLibraryPanel(localProvider);
    }

    final showOverlay = localProvider.showLyricsOverlay;

    return LayoutBuilder(
      builder: (context, constraints) {
        final panelHeight = constraints.maxHeight;
        final viewportHeight = (panelHeight - 40).clamp(120.0, 800.0);

        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Base Layer: Cover Art with Mograph Dynamic Artwork Scale (1.0 Playing <-> 0.90 Paused)
              GestureDetector(
                onTap: () {
                  if (!showOverlay) {
                    localProvider.setShowLyricsOverlay(true);
                  }
                },
                child: RepaintBoundary(
                  child: AnimatedScale(
                    scale: localProvider.isPlaying ? 1.0 : 0.90,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutBack,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: localProvider.isPlaying ? 0.36 : 0.50,
                            ),
                            blurRadius: localProvider.isPlaying ? 16 : 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildCoverArtImage(localProvider, song),
                      ),
                    ),
                  ),
                ),
              ),

              // Subtle top-left badge to re-open lyrics when overlay is closed
              if (!showOverlay)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => localProvider.setShowLyricsOverlay(true),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lyrics_outlined,
                              size: 14,
                              color: Colors.white,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Embedded lyrics',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Musicolet Semi-Transparent Dark Lyrics Overlay
              if (showOverlay)
                Container(
                  color: Colors.black.withValues(alpha: 0.60),
                  child: Column(
                    children: [
                      // Musicolet Overlay Top-Bar:
                      // Left: `Embedded lyrics ⌄`
                      // Right: `✎`, `⊙`, `TT`, `✕`
                      _buildLyricsOverlayTopBar(
                        context: context,
                        localProvider: localProvider,
                        downloaderProvider: downloaderProvider,
                        song: song,
                      ),
                      Divider(
                        height: 1,
                        thickness: 0.6,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      Expanded(
                        child: ValueListenableBuilder<int>(
                          valueListenable:
                              localProvider.activeLyricIndexNotifier,
                          builder: (context, activeIdx, _) {
                            if (localProvider.lyricsDisplayMode ==
                                    EmbeddedLyricsDisplayMode.synced &&
                                song.hasSyncedLyrics) {
                              _syncAutoScrollIfNeeded(
                                song: song,
                                activeIndex: activeIdx,
                                autoScroll: localProvider.autoScrollLyrics,
                                viewportHeight: viewportHeight,
                              );
                            }
                            return _buildLyricsOverlayBody(
                              context: context,
                              localProvider: localProvider,
                              downloaderProvider: downloaderProvider,
                              song: song,
                              activeIndex: activeIdx,
                              viewportHeight: viewportHeight,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

              if (localProvider.isProcessingLocalTag)
                Container(
                  color: Colors.black.withValues(alpha: 0.55),
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Memperbarui tag MP3...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCoverArtImage(LocalMusicProvider localProvider, LocalSong song) {
    final fullBytes = localProvider.currentFullCoverBytes;
    if (fullBytes != null && fullBytes.isNotEmpty) {
      return Image.memory(
        fullBytes,
        fit: BoxFit.cover,
        cacheWidth: 960,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            _buildThumbnailOrDefaultCoverArt(song),
      );
    }
    return _buildThumbnailOrDefaultCoverArt(song);
  }

  Widget _buildThumbnailOrDefaultCoverArt(LocalSong song) {
    if (song.hasCover) {
      return Image.file(
        File(song.coverFilePath!),
        fit: BoxFit.cover,
        cacheWidth: 960,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            _buildDefaultCoverArt(song),
      );
    }
    return _buildDefaultCoverArt(song);
  }

  Widget _buildDefaultCoverArt(LocalSong song) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(song.dominantColorValue),
            const Color(0xFF141821),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.album_rounded,
        size: 96,
        color: Colors.white.withValues(alpha: 0.20),
      ),
    );
  }

  Widget _buildLyricsOverlayTopBar({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required DownloaderProvider downloaderProvider,
    required LocalSong song,
  }) {
    final autoSync = localProvider.autoScrollLyrics;
    final modeLabel =
        localProvider.lyricsDisplayMode == EmbeddedLyricsDisplayMode.synced &&
                song.hasSyncedLyrics
            ? 'Embedded lyrics'
            : (song.hasLyrics ? 'Unsynced lyrics' : 'Embedded lyrics');

    return SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // Left: `Embedded lyrics ⌄` Dropdown
            PopupMenuButton<String>(
              tooltip: 'Mode & Sumber Lirik',
              color: context.palette.surfaceSubtle,
              offset: const Offset(0, 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: context.palette.hairline,
                  width: 0.8,
                ),
              ),
              onSelected: (value) async {
                if (value == 'synced') {
                  localProvider
                      .setLyricsDisplayMode(EmbeddedLyricsDisplayMode.synced);
                } else if (value == 'plain') {
                  localProvider
                      .setLyricsDisplayMode(EmbeddedLyricsDisplayMode.plain);
                } else if (value == 'lrclib') {
                  await _showLrclibCandidatesSheet(
                    context,
                    localProvider,
                    song,
                  );
                } else if (value == 'romaji') {
                  final ok = await localProvider.autoRomanizeLocalSong(song);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Lirik berhasil dikonversi ke Romaji (tanpa duplikat).'
                              : 'Gagal mengonversi atau menyimpan lirik Romaji.',
                        ),
                      ),
                    );
                  }
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem<String>(
                  value: 'synced',
                  child: Row(
                    children: [
                      Icon(
                        localProvider.lyricsDisplayMode ==
                                EmbeddedLyricsDisplayMode.synced
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 16,
                        color: context.palette.textPrimary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Lirik Berjalan (Synced)',
                        style: TextStyle(
                          color: context.palette.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'plain',
                  child: Row(
                    children: [
                      Icon(
                        localProvider.lyricsDisplayMode ==
                                EmbeddedLyricsDisplayMode.plain
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 16,
                        color: context.palette.textPrimary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Lirik Polos (Plain)',
                        style: TextStyle(
                          color: context.palette.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'lrclib',
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_download_outlined,
                        size: 16,
                        color: context.palette.accent,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Ganti Kandidat Lirik (LRCLIB)',
                        style: TextStyle(
                          color: context.palette.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'romaji',
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: context.palette.accent,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '✨ Auto-Romaji Lirik',
                        style: TextStyle(
                          color: context.palette.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      modeLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // Right 1: Pencil (`✎`) -> Opens TagEditorSheet with Auto-Romaji
            _buildTopOverlayIconButton(
              tooltip: 'Edit Tag & Lirik (✎)',
              onTap: () => TagEditorSheet.showForLocalSong(
                context,
                downloaderProvider: downloaderProvider,
                localProvider: localProvider,
                song: song,
              ),
              child: const Icon(
                Icons.edit_outlined,
                size: 17,
                color: Colors.white70,
              ),
            ),

            // Right 2: Check Circle (`⊙`) -> Toggle Auto-Scroll Sync
            _buildTopOverlayIconButton(
              tooltip: autoSync
                  ? 'Sinkronisasi Waktu Aktif'
                  : 'Sinkronisasi Waktu Nonaktif',
              onTap: localProvider.toggleAutoScrollLyrics,
              child: Icon(
                autoSync
                    ? Icons.check_circle_rounded
                    : Icons.check_circle_outline_rounded,
                size: 17,
                color: autoSync ? Colors.white : Colors.white38,
              ),
            ),

            // Right 3: `TT` -> Cycle Lyrics Font Size
            _buildTopOverlayIconButton(
              tooltip: 'Ukuran Font Lirik (TT)',
              onTap: localProvider.cycleLyricsFontSize,
              child: const Text(
                'TT',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),

            // Right 4: `✕` -> Close Overlay to View Full Cover Art
            _buildTopOverlayIconButton(
              tooltip: 'Tutup Lirik (Lihat Cover Art)',
              onTap: () => localProvider.setShowLyricsOverlay(false),
              child: const Icon(
                Icons.close_rounded,
                size: 18,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopOverlayIconButton({
    required String tooltip,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 32,
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildLyricsOverlayBody({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required DownloaderProvider downloaderProvider,
    required LocalSong song,
    required int activeIndex,
    required double viewportHeight,
  }) {
    final fontSize = localProvider.lyricsFontSize;

    if (song.hasLyrics && !song.isLyricsLoadedInMemory) {
      if (_requestedOnDemandLyricsPath != song.filePath) {
        _requestedOnDemandLyricsPath = song.filePath;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            localProvider.ensureSongLyricsLoaded(song);
          }
        });
      }
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white54,
          ),
        ),
      );
    }

    // 1. Synced LRC Mode with Musicolet Ribbon Highlight & Tap-to-Seek
    if (localProvider.lyricsDisplayMode == EmbeddedLyricsDisplayMode.synced &&
        song.hasSyncedLyrics) {
      final entries = song.parsedSyncedLyrics;
      final verticalPad = viewportHeight * 0.36;
      final isDark = context.isDarkMode;
      final activeRibbonColor = isDark
          ? Colors.black.withValues(alpha: 0.45)
          : Colors.white.withValues(alpha: 0.65);
      final activeTextColor =
          isDark ? Colors.white : MusEveePalette.light.textPrimary;

      return ListView.builder(
        controller: _syncedScrollController,
        itemExtent: _lyricItemExtent,
        padding: EdgeInsets.symmetric(vertical: verticalPad),
        itemCount: entries.length,
        itemBuilder: (context, idx) {
          final entry = entries[idx];
          final isActive = idx == activeIndex;
          final displayLine = entry.text.isEmpty ? '♪' : entry.text;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => localProvider.seekTo(entry.timeMs),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                // Musicolet signature horizontal ribbon on active line
                color: isActive ? activeRibbonColor : Colors.transparent,
              ),
              alignment: Alignment.center,
              child: Text(
                displayLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive
                      ? activeTextColor
                      : Colors.white.withValues(alpha: 0.46),
                  fontSize: isActive ? fontSize + 0.5 : fontSize - 0.5,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  height: 1.22,
                ),
              ),
            ),
          );
        },
      );
    }

    // 2. Plain USLT Lyrics Mode
    if (song.hasLyrics) {
      final lines = song.plainLyricLines;
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        itemCount: lines.length,
        itemBuilder: (context, idx) {
          final line = lines[idx];
          if (line.isEmpty) {
            return const SizedBox(height: 12);
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text(
              line,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                height: 1.38,
              ),
            ),
          );
        },
      );
    }

    // 3. No Embedded Lyrics Yet
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 32,
              color: Colors.white.withValues(alpha: 0.38),
            ),
            const SizedBox(height: 10),
            Text(
              'Belum ada lirik tertanam (USLT) pada file MP3 ini.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  onPressed: () => _showLrclibCandidatesSheet(
                    context,
                    localProvider,
                    song,
                  ),
                  icon: const Icon(Icons.search_rounded, size: 15),
                  label: const Text(
                    'Cari Lirik LRCLIB',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  onPressed: () => TagEditorSheet.showForLocalSong(
                    context,
                    downloaderProvider: downloaderProvider,
                    localProvider: localProvider,
                    song: song,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text(
                    'Isi Manual',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyLibraryPanel(LocalMusicProvider localProvider) {
    final palette = context.palette;
    final isDark = context.isDarkMode;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.38)
            : palette.surfaceCard.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: palette.hairline,
          width: 0.8,
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_note_rounded,
            size: 52,
            color: palette.textMuted.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 12),
          Text(
            'Belum ada lagu yang sedang diputar',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            localProvider.isLoadingLibrary
                ? 'Memindai folder Music Barat, Music Japan, dan Music Random...'
                : 'Pilih lagu dari tab Folders (📁) atau unduh lagu baru dengan lirik otomatis di tab Downloader (⬇).',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.textPrimary,
                  backgroundColor: palette.surfaceSubtle.withValues(
                    alpha: isDark ? 0.35 : 0.75,
                  ),
                  side: BorderSide(
                    color: palette.hairline,
                    width: 0.8,
                  ),
                ),
                onPressed: widget.onNavigateToFolders,
                icon: const Icon(Icons.folder_open_rounded, size: 17),
                label: const Text('Buka Folder'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
                ),
                onPressed: widget.onNavigateToDownloader,
                icon: const Icon(Icons.cloud_download_outlined, size: 17),
                label: const Text('Cari & Unduh Lagu'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MIDDLE SECTION: TRACK INFO + MUSICOLET UTILITY ICON ROW
  // ---------------------------------------------------------------------------
  Widget _buildTrackInfoSection(LocalSong? song) {
    final palette = context.palette;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Column(
        key: ValueKey<String>(song?.filePath ?? '__empty__'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            song?.title ?? 'MusEvee Player',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            song?.artist ?? 'Pilih atau unduh lagu untuk mulai memutar',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textPrimary.withValues(alpha: 0.82),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            song != null ? song.album : '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMusicoletUtilityRow({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required DownloaderProvider downloaderProvider,
    required LocalSong? song,
  }) {
    final palette = context.palette;
    final isFav = song != null && localProvider.isFavorite(song.filePath);
    final playMode = localProvider.playMode;
    final isShuffle = localProvider.isShuffle;

    return SizedBox(
      height: 38,
      child: Row(
        children: [
          // Left 1: Heart (Favorite)
          _buildUtilityIcon(
            tooltip: 'Favorit',
            enabled: song != null,
            onTap: song == null
                ? null
                : () => localProvider.toggleFavorite(song.filePath),
            child: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 20,
              color: isFav ? const Color(0xFFFF5A6E) : palette.textMuted,
            ),
          ),

          // Left 2: `(i)` File Info & Folder Path
          _buildUtilityIcon(
            tooltip: 'Info File & Path Folder',
            enabled: song != null,
            onTap:
                song == null ? null : () => _showSongInfoDialog(context, song),
            child: Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: palette.textMuted,
            ),
          ),

          // Left 3: `=+` Add to Queue
          _buildUtilityIcon(
            tooltip: 'Tambah ke Antrean (=+)',
            enabled: song != null,
            onTap: song == null
                ? null
                : () {
                    localProvider.addToQueue(song, playNext: true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Ditambahkan ke urutan berikutnya: ${song.title}',
                        ),
                      ),
                    );
                  },
            child: Icon(
              Icons.playlist_add_rounded,
              size: 22,
              color: palette.textMuted,
            ),
          ),

          const SizedBox(width: 4),

          // Left 4: `[...]` Musicolet Bordered Box Quick Menu
          Tooltip(
            message: 'Menu Cepat Lagu',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: song == null
                  ? null
                  : () => _showQuickSongMenuSheet(
                        context: context,
                        localProvider: localProvider,
                        downloaderProvider: downloaderProvider,
                        song: song,
                      ),
              child: Container(
                width: 30,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: song != null
                        ? palette.textMuted.withValues(alpha: 0.65)
                        : palette.hairline,
                    width: 1.0,
                  ),
                ),
                child: Icon(
                  Icons.more_horiz_rounded,
                  size: 16,
                  color: song != null
                      ? palette.textMuted
                      : palette.textMuted.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),

          const Spacer(),

          // Right 1: Musicolet Play Mode (`1→` / Repeat All / Repeat One / Queue Once)
          _buildUtilityIcon(
            tooltip: _playModeTooltip(playMode),
            enabled: true,
            onTap: localProvider.cyclePlayMode,
            child: _buildPlayModeGlyph(playMode, palette),
          ),

          // Right 2: Shuffle (`🔀`)
          _buildUtilityIcon(
            tooltip: isShuffle ? 'Shuffle Aktif' : 'Shuffle Nonaktif',
            enabled: true,
            onTap: localProvider.toggleShuffle,
            child: Icon(
              Icons.shuffle_rounded,
              size: 20,
              color: isShuffle
                  ? palette.textPrimary
                  : palette.textMuted.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUtilityIcon({
    required String tooltip,
    required bool enabled,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 38,
            height: 36,
            child: Center(
              child: Opacity(
                opacity: enabled ? 1.0 : 0.35,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _playModeTooltip(MusicoletPlayMode mode) {
    switch (mode) {
      case MusicoletPlayMode.repeatAll:
        return 'Repeat All (Ulangi Antrean)';
      case MusicoletPlayMode.repeatOne:
        return 'Repeat One (Ulangi 1 Lagu)';
      case MusicoletPlayMode.playSingleStop:
        return '1→ (Putar 1 Lagu lalu Berhenti)';
      case MusicoletPlayMode.playQueueOnce:
        return 'Putar Antrean Sekali lalu Berhenti';
    }
  }

  Widget _buildPlayModeGlyph(
    MusicoletPlayMode mode,
    MusEveePalette palette,
  ) {
    switch (mode) {
      case MusicoletPlayMode.repeatAll:
        return Icon(
          Icons.repeat_rounded,
          size: 20,
          color: palette.textPrimary,
        );
      case MusicoletPlayMode.repeatOne:
        return Icon(
          Icons.repeat_one_rounded,
          size: 20,
          color: palette.textPrimary,
        );
      case MusicoletPlayMode.playSingleStop:
        // Musicolet's iconic `1→` indicator
        return Text(
          '1→',
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        );
      case MusicoletPlayMode.playQueueOnce:
        return Icon(
          Icons.trending_flat_rounded,
          size: 20,
          color: palette.textMuted,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // BOTTOM SECTION: SEEKBAR & TRANSPORT CONTROLS
  // ---------------------------------------------------------------------------
  Widget _buildSeekbarRow(LocalMusicProvider localProvider, LocalSong? song) {
    final palette = context.palette;
    return ValueListenableBuilder<PlaybackProgress>(
      valueListenable: localProvider.progressNotifier,
      builder: (context, progress, _) {
        final rawTotal =
            progress.durationMs > 0 ? progress.durationMs : localProvider.durationMs;
        final totalMs = rawTotal > 0 ? rawTotal : 1;
        final currentMs = (_dragSeekMs ?? progress.positionMs.toDouble())
            .clamp(0.0, totalMs.toDouble());

        return Row(
          children: [
            SizedBox(
              width: 38,
              child: Text(
                LocalSong.formatMillis(currentMs.round()),
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 11.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.4,
                  activeTrackColor: palette.textPrimary,
                  inactiveTrackColor:
                      palette.textPrimary.withValues(alpha: 0.24),
                  thumbColor: palette.textPrimary,
                  overlayColor: palette.textPrimary.withValues(alpha: 0.14),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6.2),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  min: 0.0,
                  max: totalMs.toDouble(),
                  value: song == null ? 0.0 : currentMs,
                  onChangeStart: song == null
                      ? null
                      : (val) {
                          setState(() => _dragSeekMs = val);
                        },
                  onChanged: song == null
                      ? null
                      : (val) {
                          setState(() => _dragSeekMs = val);
                        },
                  onChangeEnd: song == null
                      ? null
                      : (val) {
                          localProvider.seekTo(val.round());
                          setState(() => _dragSeekMs = null);
                        },
                ),
              ),
            ),
            SizedBox(
              width: 38,
              child: Text(
                song != null ? LocalSong.formatMillis(rawTotal) : '0:00',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 11.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTransportControlsRow(
    BuildContext context,
    LocalMusicProvider localProvider,
    LocalSong? song,
  ) {
    final palette = context.palette;
    final vol = localProvider.volume;
    final IconData volIcon = vol <= 0.01
        ? Icons.volume_off_rounded
        : (vol < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded);

    return SizedBox(
      height: 56,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Speaker / Volume Slider
          PressableScale(
            child: IconButton(
              tooltip: 'Volume Audio',
              onPressed: () => _showVolumeSheet(context, localProvider),
              icon: Icon(volIcon, color: palette.textMuted, size: 22),
            ),
          ),

          // Center: Previous (`|◀`), Large Play/Pause (`▶`/`||` WITHOUT circle bg), Next (`▶|`)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PressableScale(
                child: IconButton(
                  tooltip: 'Lagu Sebelumnya',
                  onPressed:
                      song == null ? null : () => localProvider.playPrevious(),
                  iconSize: 34,
                  icon: Icon(
                    Icons.skip_previous_rounded,
                    color: song == null
                        ? palette.textMuted.withValues(alpha: 0.35)
                        : palette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Musicolet signature large Play/Pause icon WITHOUT circular background (Mograph Vector Morph!)
              PressableScale(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: localProvider.allSongs.isEmpty && song == null
                      ? widget.onNavigateToDownloader
                      : () => localProvider.togglePlayPause(),
                  child: SizedBox(
                    width: 56,
                    height: 52,
                    child: Center(
                      child: MographPlayPauseIcon(
                        isPlaying: localProvider.isPlaying,
                        size: 46,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              PressableScale(
                child: IconButton(
                  tooltip: 'Lagu Berikutnya',
                  onPressed:
                      song == null ? null : () => localProvider.playNext(),
                  iconSize: 34,
                  icon: Icon(
                    Icons.skip_next_rounded,
                    color: song == null
                        ? palette.textMuted.withValues(alpha: 0.35)
                        : palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          // Right: System Equalizer (`📊`)
          PressableScale(
            child: IconButton(
              tooltip: 'Equalizer Sistem Android',
              onPressed: () async {
                final opened = await localProvider.openSystemEqualizer();
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Equalizer bawaan sistem tidak ditemukan di perangkat ini.',
                      ),
                    ),
                  );
                }
              },
              icon: Icon(
                Icons.equalizer_rounded,
                color: palette.textMuted,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DIALOGS & SHEETS: FILE INFO `(i)`, `[...]` MENU, VOLUME, LRCLIB PICKER
  // ---------------------------------------------------------------------------
  void _showSongInfoDialog(BuildContext context, LocalSong song) {
    final palette = context.palette;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: palette.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: palette.hairline,
              width: 0.8,
            ),
          ),
          title: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: palette.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Informasi File & Tag ID3',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _infoRow(palette, 'Judul', song.title),
                _infoRow(palette, 'Artis', song.artist),
                _infoRow(palette, 'Album', song.album),
                if (song.year.isNotEmpty) _infoRow(palette, 'Tahun', song.year),
                _infoRow(palette, 'Folder', song.folderName),
                _infoRow(palette, 'Path File', song.filePath),
                _infoRow(palette, 'Durasi', song.formattedDuration),
                _infoRow(palette, 'Ukuran', song.formattedFileSize),
                _infoRow(
                  palette,
                  'Kualitas Audio',
                  '${song.bitrateKbps} kbps • ${song.sampleRateHz} Hz',
                ),
                _infoRow(
                  palette,
                  'Tag Sampul (APIC)',
                  song.hasCover ? 'Tersedia (Embedded)' : 'Tidak ada',
                ),
                _infoRow(
                  palette,
                  'Tag Lirik (USLT)',
                  song.hasSyncedLyrics
                      ? 'Synced LRC [mm:ss.xx]'
                      : (song.hasLyrics ? 'Plain Lyrics' : 'Tidak ada'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Tutup',
                style: TextStyle(color: palette.accent),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _infoRow(MusEveePalette palette, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1.5),
          SelectableText(
            value,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  void _showVolumeSheet(
    BuildContext context,
    LocalMusicProvider localProvider,
  ) {
    final palette = context.palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        return Consumer<LocalMusicProvider>(
          builder: (ctx, lp, _) {
            final pct = (lp.volume * 100).round();
            final boostDb = lp.preAmpGainDb;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Gain Player & Pre-Amp Audio',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (lp.volume < 1.0 || boostDb > 0.0)
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: palette.accent,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              lp.setVolume(1.0);
                              lp.setPreAmpGainDb(0.0);
                            },
                            child: const Text(
                              'Reset 100% (0 dB)',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () =>
                              lp.setVolume(lp.volume > 0 ? 0.0 : 1.0),
                          icon: Icon(
                            lp.volume <= 0.01
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            color: palette.textPrimary,
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(ctx).copyWith(
                              activeTrackColor: palette.textPrimary,
                              inactiveTrackColor:
                                  palette.textMuted.withValues(alpha: 0.30),
                              thumbColor: palette.textPrimary,
                            ),
                            child: Slider(
                              min: 0.0,
                              max: 1.0,
                              value: lp.volume,
                              onChanged: lp.setVolume,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '$pct%',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            color: palette.accent,
                            size: 22,
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(ctx).copyWith(
                              activeTrackColor: palette.accent,
                              inactiveTrackColor:
                                  palette.textMuted.withValues(alpha: 0.30),
                              thumbColor: palette.accent,
                            ),
                            child: Slider(
                              min: 0.0,
                              max: 6.0,
                              divisions: 12,
                              value: boostDb,
                              onChanged: lp.setPreAmpGainDb,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '+${boostDb.toStringAsFixed(1)}dB',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: palette.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showQuickSongMenuSheet({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required DownloaderProvider downloaderProvider,
    required LocalSong song,
  }) {
    final palette = context.palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.textMuted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${song.artist} • ${song.folderName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Divider(color: palette.hairline, height: 1),
                ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.playlist_add_rounded,
                    color: palette.accent,
                  ),
                  title: Text(
                    'Tambah ke Playlist',
                    style: TextStyle(color: palette.textPrimary, fontSize: 13.5),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    showAddToPlaylistSheet(
                      context,
                      localProvider: localProvider,
                      song: song,
                    );
                  },
                ),
                ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.drive_file_move_outlined,
                    color: palette.accent,
                  ),
                  title: Text(
                    'Pindah Folder',
                    style: TextStyle(color: palette.textPrimary, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    'Saat ini di ${song.folderName}',
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    widget.onMoveLocalSongFolder(song);
                  },
                ),
                ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.edit_outlined,
                    color: palette.textMuted,
                  ),
                  title: Text(
                    'Edit Tag & Embedded Lyrics',
                    style: TextStyle(color: palette.textPrimary, fontSize: 13.5),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    TagEditorSheet.showForLocalSong(
                      context,
                      downloaderProvider: downloaderProvider,
                      localProvider: localProvider,
                      song: song,
                    );
                  },
                ),
                ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.lyrics_outlined,
                    color: palette.textMuted,
                  ),
                  title: Text(
                    'Ganti Lirik dari LRCLIB',
                    style: TextStyle(color: palette.textPrimary, fontSize: 13.5),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showLrclibCandidatesSheet(context, localProvider, song);
                  },
                ),
                ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.auto_awesome_rounded,
                    color: palette.accent,
                  ),
                  title: Text(
                    '✨ Auto-Romaji Lirik & Judul Jepang',
                    style: TextStyle(color: palette.textPrimary, fontSize: 13.5),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final ok = await localProvider.autoRomanizeLocalSong(
                      song,
                      includeMetadata: true,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Tag & lirik berhasil dikonversi ke Romaji.'
                                : 'Gagal menyimpan perubahan Romaji ke file MP3.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: MusEveePalette.error,
                  ),
                  title: const Text(
                    'Hapus File Lagu',
                    style: TextStyle(
                      color: MusEveePalette.error,
                      fontSize: 13.5,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _confirmDeleteSong(context, localProvider, song);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showLrclibCandidatesSheet(
    BuildContext context,
    LocalMusicProvider localProvider,
    LocalSong song,
  ) async {
    final palette = context.palette;
    localProvider.loadLyricsCandidatesForSong(song);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Consumer<LocalMusicProvider>(
          builder: (ctx, lp, _) {
            final cands = lp.localLyricsCandidates;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.textMuted.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Pilih Kandidat Lirik (LRCLIB)',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${song.artist} — ${song.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (lp.isLoadingLyricsCandidates)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: palette.accent,
                          ),
                        ),
                      )
                    else if (cands.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'Kandidat lirik tidak ditemukan di LRCLIB untuk lagu ini.',
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: cands.length,
                          separatorBuilder: (ctx, idx) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, idx) {
                            final cand = cands[idx];
                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () async {
                                Navigator.of(ctx).pop();
                                try {
                                  await lp.applyLyricsCandidateToSong(
                                    song,
                                    cand,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Lirik ${cand.languageTag} berhasil ditanamkan ke MP3.',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Gagal menanamkan lirik ke MP3: $e',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: palette.surfaceSubtle,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: palette.hairline,
                                    width: 0.8,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          cand.languageTag,
                                          style: TextStyle(
                                            color: palette.accent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${cand.hasSynced ? 'Synced LRC' : 'Plain'} • ${cand.formattedDuration}',
                                          style: TextStyle(
                                            color: palette.textMuted,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      cand.previewTwoLines,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontSize: 12,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteSong(
    BuildContext context,
    LocalMusicProvider localProvider,
    LocalSong song,
  ) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: palette.surfaceCard,
          title: Text(
            'Hapus File Lagu?',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'Hapus permanen "${song.title}" dari folder ${song.folderName}?',
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Batal',
                style: TextStyle(color: palette.textMuted),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: MusEveePalette.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && context.mounted) {
      final ok = await localProvider.deleteLocalSong(song);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok ? 'File lagu berhasil dihapus.' : 'Gagal menghapus file lagu.',
            ),
          ),
        );
      }
    }
  }
}

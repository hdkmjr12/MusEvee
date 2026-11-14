import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/local_playlist.dart';
import '../models/local_song.dart';
import '../providers/downloader_provider.dart';
import '../providers/local_music_provider.dart';
import '../theme/musevee_palette.dart';
import '../utils/app_strings.dart';
import 'pressable_scale.dart';
import 'tag_editor_sheet.dart';

// Shared Musicolet Dark Surface Palette

// =============================================================================
// TAB 0: PLAYBACK QUEUE (`=♪`)
// =============================================================================
class PlaybackQueueView extends StatelessWidget {
  final VoidCallback onOpenNowPlaying;
  final VoidCallback onNavigateToDownloader;

  const PlaybackQueueView({
    super.key,
    required this.onOpenNowPlaying,
    required this.onNavigateToDownloader,
  });

  @override
  Widget build(BuildContext context) {
    SystemLocaleScope.watch(context);
    return Consumer<LocalMusicProvider>(
      builder: (context, localProvider, _) {
        final entries = localProvider.queueEntries;
        final currentIdx = localProvider.currentIndex;

        return Container(
          color: context.palette.nowPlayingBg,
          child: Column(
            children: [
              // Clean Monochrome Queue Header matching Folders & Playlists
              Container(
                padding: statusBarHeaderPadding(context),
                decoration: cleanMonochromeHeaderDecoration(context),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Row(
                    children: [
                      MographStatePop(
                        stateKey: entries.isNotEmpty,
                        scaleBoost: 0.16,
                        child: Image.asset(
                          'assets/icons/add-to-playlist.png',
                          width: 19,
                          height: 19,
                          fit: BoxFit.contain,
                          color: context.palette.textPrimary,
                          colorBlendMode: BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppStrings.tr(
                            'Antrean Putar',
                            'Playback Queue',
                            context,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.palette.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (entries.isNotEmpty) ...[
                        MographSpringTap(
                          pressedScale: 0.80,
                          tapRotationRad: 0.22,
                          child: MographStatePop(
                            stateKey: localProvider.isShuffle,
                            scaleBoost: 0.22,
                            rotationKickRad: -0.38,
                            child: IconButton(
                              key:
                                  const ValueKey('queue_header_shuffle_button'),
                              visualDensity: VisualDensity.compact,
                              tooltip: localProvider.isShuffle
                                  ? AppStrings.tr(
                                      'Shuffle Aktif',
                                      'Shuffle On',
                                      context,
                                    )
                                  : AppStrings.tr(
                                      'Acak (Shuffle)',
                                      'Shuffle',
                                      context,
                                    ),
                              onPressed: localProvider.toggleShuffle,
                              icon: Image.asset(
                                'assets/icons/arrow.png',
                                width: 19,
                                height: 19,
                                fit: BoxFit.contain,
                                color: localProvider.isShuffle
                                    ? context.palette.nowPlayingPrimary
                                    : context.palette.nowPlayingInactiveIcon,
                                colorBlendMode: BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                        MographSpringTap(
                          pressedScale: 0.88,
                          child: TextButton(
                            key: const ValueKey('queue_header_clear_button'),
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  context.palette.nowPlayingSecondary,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: localProvider.clearQueue,
                            child: Text(
                              AppStrings.tr('Bersihkan', 'Clear', context),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              Expanded(
                child: entries.isEmpty
                    ? Center(
                        key: const ValueKey('queue_empty_state'),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutBack,
                          builder: (context, animVal, child) {
                            return Transform.scale(
                              scale: 0.90 + (0.10 * animVal),
                              child: child,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.queue_music_rounded,
                                  size: 42,
                                  color: context.palette.textMuted,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  AppStrings.tr(
                                    'Antrean putar masih kosong',
                                    'Playback queue is empty',
                                    context,
                                  ),
                                  style: TextStyle(
                                    color: context.palette.textPrimary,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  AppStrings.tr(
                                    'Pilih lagu dari Folders atau unduh lagu baru di Downloader.',
                                    'Pick songs from Folders or download new tracks in Downloader.',
                                    context,
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: context.palette.textMuted,
                                    fontSize: 12.5,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                MographSpringTap(
                                  pressedScale: 0.92,
                                  child: ElevatedButton.icon(
                                    key: const ValueKey(
                                      'queue_empty_primary_button',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          context.palette.nowPlayingPrimary,
                                      foregroundColor:
                                          context.palette.nowPlayingOnPrimary,
                                      elevation: 0,
                                    ),
                                    onPressed: localProvider.allSongs.isNotEmpty
                                        ? () {
                                            localProvider.playSong(
                                              localProvider.allSongs.first,
                                              queueContext:
                                                  localProvider.allSongs,
                                            );
                                            onOpenNowPlaying();
                                          }
                                        : onNavigateToDownloader,
                                    icon: Icon(
                                      localProvider.allSongs.isNotEmpty
                                          ? Icons.play_arrow_rounded
                                          : Icons.cloud_download_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      localProvider.allSongs.isNotEmpty
                                          ? AppStrings.tr(
                                              'Putar Semua Lagu Lokal',
                                              'Play All Local Songs',
                                              context,
                                            )
                                          : AppStrings.tr(
                                              'Cari & Unduh Lagu',
                                              'Search & Download',
                                              context,
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        key: const ValueKey('queue_reorderable_list'),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        buildDefaultDragHandles: false,
                        proxyDecorator: (child, index, animation) {
                          final curved = Curves.easeOutBack.transform(
                            animation.value.clamp(0.0, 1.0),
                          );
                          final dragScale = 1.0 + (0.03 * curved);
                          return Transform.scale(
                            scale: dragScale,
                            child: Material(
                              color: context.palette.surfaceCard,
                              elevation: 8 * animation.value,
                              shadowColor: context.palette.discShadow,
                              borderRadius: BorderRadius.circular(10),
                              child: child,
                            ),
                          );
                        },
                        itemCount: entries.length,
                        onReorderItem: localProvider.reorderQueueItem,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final song = entry.song;
                          final isCurrent = index == currentIdx;

                          return Material(
                            key: ValueKey(entry.queueId),
                            color: isCurrent
                                ? context.palette.nowPlayingPrimary.withValues(
                                    alpha: context.isDarkMode ? 0.08 : 0.06,
                                  )
                                : Colors.transparent,
                            child: MographSpringTap(
                              pressedScale: 0.975,
                              child: InkWell(
                                onTap: () {
                                  localProvider.playQueueIndex(index);
                                  onOpenNowPlaying();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        child: MographAnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          beginScale: 0.65,
                                          child: isCurrent
                                              ? Center(
                                                  key: const ValueKey(
                                                    'eq_icon',
                                                  ),
                                                  child: AnimatedEqualizerIcon(
                                                    isPlaying:
                                                        localProvider.isPlaying,
                                                    size: 17,
                                                    color: context.palette
                                                        .nowPlayingPrimary,
                                                  ),
                                                )
                                              : Text(
                                                  '${index + 1}',
                                                  key: ValueKey('idx_$index'),
                                                  style: TextStyle(
                                                    color: context.palette
                                                        .nowPlayingSecondary,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                        ),
                                      ),
                                      _LocalCoverThumb(
                                        coverPath: song.coverFilePath,
                                        size: 42,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              song.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isCurrent
                                                    ? context.palette
                                                        .nowPlayingPrimary
                                                    : context
                                                        .palette.textPrimary,
                                                fontSize: 13.5,
                                                fontWeight: isCurrent
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${song.artist} • ${song.formattedDuration}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: context.palette
                                                    .nowPlayingSecondary,
                                                fontSize: 11.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      MographSpringTap(
                                        pressedScale: 0.78,
                                        tapRotationRad: 0.24,
                                        child: IconButton(
                                          visualDensity: VisualDensity.compact,
                                          tooltip: AppStrings.tr(
                                            'Hapus dari antrean',
                                            'Remove from queue',
                                            context,
                                          ),
                                          onPressed: () => localProvider
                                              .removeFromQueue(index),
                                          icon: Icon(
                                            Icons.close_rounded,
                                            size: 17,
                                            color: context.palette.textMuted,
                                          ),
                                        ),
                                      ),
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: MographSpringTap(
                                          pressedScale: 0.84,
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.drag_handle_rounded,
                                              size: 18,
                                              color: context.palette.textMuted,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// TAB 2: FOLDERS EXPLORER (`📁`)
// =============================================================================

/// Adds the system status bar height onto a tab header's top padding so the
/// header surface extends seamlessly behind a transparent Android status bar.
EdgeInsets statusBarHeaderPadding(
  BuildContext context, {
  double left = 16,
  double top = 10,
  double right = 12,
  double bottom = 10,
}) {
  return EdgeInsets.fromLTRB(
    left,
    top + MediaQuery.paddingOf(context).top,
    right,
    bottom,
  );
}

/// Shared monochrome curved header decoration (`bottomBar`, 18px bottom radius,
/// hairline border, and soft elevation shadow) used across library and settings tabs.
BoxDecoration cleanMonochromeHeaderDecoration(BuildContext context) {
  final palette = context.palette;
  return BoxDecoration(
    color: palette.bottomBar,
    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
    border: Border(
      bottom: BorderSide(
        color: palette.hairline.withValues(
          alpha: context.isDarkMode ? 0.14 : 0.06,
        ),
        width: 0.7,
      ),
    ),
    boxShadow: [
      BoxShadow(
        color: palette.discShadow.withValues(
          alpha: context.isDarkMode ? 0.28 : 0.08,
        ),
        blurRadius: 12,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

InputDecoration _monochromeSearchInputDecoration(
  BuildContext context, {
  required String hintText,
  required bool showClearButton,
  required VoidCallback onClear,
  Key? clearButtonKey,
}) {
  final palette = context.palette;
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(
      color: palette.nowPlayingSecondary,
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
    ),
    filled: true,
    fillColor: palette.surfaceSubtle,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 14,
      vertical: 10,
    ),
    prefixIcon: Padding(
      padding: const EdgeInsets.only(left: 14, right: 10),
      child: Image.asset(
        'assets/search.png',
        width: 17,
        height: 17,
        fit: BoxFit.contain,
        color: palette.nowPlayingArtist,
        colorBlendMode: BlendMode.srcIn,
      ),
    ),
    prefixIconConstraints: const BoxConstraints(
      minWidth: 40,
      minHeight: 40,
    ),
    suffixIcon: showClearButton
        ? MographSpringTap(
            pressedScale: 0.78,
            tapRotationRad: 0.24,
            child: IconButton(
              key: clearButtonKey,
              tooltip: AppStrings.clearTooltip,
              icon: Icon(
                Icons.close_rounded,
                size: 17,
                color: palette.nowPlayingSecondary,
              ),
              onPressed: onClear,
            ),
          )
        : null,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: palette.nowPlayingPrimary.withValues(alpha: 0.22),
        width: 0.8,
      ),
    ),
  );
}

class LocalFoldersView extends StatefulWidget {
  final VoidCallback onOpenNowPlaying;
  final Future<void> Function(DownloaderProvider provider) onCreateNewFolder;
  final Future<void> Function(LocalSong song) onMoveLocalSongFolder;
  final VoidCallback? onOpenAllSongsSearch;

  const LocalFoldersView({
    super.key,
    required this.onOpenNowPlaying,
    required this.onCreateNewFolder,
    required this.onMoveLocalSongFolder,
    this.onOpenAllSongsSearch,
  });

  @override
  State<LocalFoldersView> createState() => LocalFoldersViewState();
}

class LocalFoldersViewState extends State<LocalFoldersView> {
  String? _openedFolder;
  bool _isSelectionMode = false;
  final Set<String> _selectedFolders = <String>{};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final TextEditingController _folderSongsSearchController =
      TextEditingController();
  String _folderSongsSearchQuery = '';
  bool _isFolderSongsSelectionMode = false;
  final Set<String> _selectedSongPaths = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    _folderSongsSearchController.dispose();
    super.dispose();
  }

  void _closeOpenedFolder() {
    setState(() {
      _openedFolder = null;
      _isFolderSongsSelectionMode = false;
      _selectedSongPaths.clear();
      _folderSongsSearchController.clear();
      _folderSongsSearchQuery = '';
    });
  }

  void _toggleFolderSongSelection(String filePath) {
    setState(() {
      if (_selectedSongPaths.contains(filePath)) {
        _selectedSongPaths.remove(filePath);
        if (_selectedSongPaths.isEmpty) {
          _isFolderSongsSelectionMode = false;
        }
      } else {
        _selectedSongPaths.add(filePath);
        _isFolderSongsSelectionMode = true;
      }
    });
  }

  void _exitFolderSongsSelectionMode() {
    if (!_isFolderSongsSelectionMode && _selectedSongPaths.isEmpty) return;
    setState(() {
      _isFolderSongsSelectionMode = false;
      _selectedSongPaths.clear();
    });
  }

  /// Handles system back navigation inside the Folders tab:
  /// 1. Inside an opened folder: exits song selection, clears folder search,
  ///    or closes the opened folder back to the main Folders list.
  /// 2. At Folders root: exits Multi-Folder selection mode or clears inline search.
  /// Returns `true` if a sub-state was popped, `false` if already at root.
  bool handleBack() {
    if (_openedFolder != null) {
      if (_isFolderSongsSelectionMode) {
        _exitFolderSongsSelectionMode();
        return true;
      }
      if (_folderSongsSearchQuery.isNotEmpty) {
        _folderSongsSearchController.clear();
        setState(() => _folderSongsSearchQuery = '');
        FocusScope.of(context).unfocus();
        return true;
      }
      _closeOpenedFolder();
      return true;
    }
    if (_isSelectionMode) {
      _exitSelectionMode();
      return true;
    }
    if (_searchQuery.isNotEmpty) {
      _searchController.clear();
      setState(() => _searchQuery = '');
      FocusScope.of(context).unfocus();
      return true;
    }
    return false;
  }

  List<LocalSong> _matchingSongsForQuery(
    List<LocalSong> allSongs,
    String rawQuery,
  ) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return allSongs.where((song) {
      return song.title.toLowerCase().contains(q) ||
          song.artist.toLowerCase().contains(q) ||
          song.album.toLowerCase().contains(q) ||
          song.folderName.toLowerCase().contains(q);
    }).toList();
  }

  void _toggleFolderSelection(String folder) {
    setState(() {
      if (_selectedFolders.contains(folder)) {
        _selectedFolders.remove(folder);
        if (_selectedFolders.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedFolders.add(folder);
        _isSelectionMode = true;
      }
    });
  }

  void _exitSelectionMode() {
    if (!_isSelectionMode && _selectedFolders.isEmpty) return;
    setState(() {
      _isSelectionMode = false;
      _selectedFolders.clear();
    });
  }

  int _countUniqueSongsForFolders(
    Map<String, List<LocalSong>> folderMap,
    Iterable<String> folders,
  ) {
    final seen = <String>{};
    for (final f in folders) {
      final list = folderMap[f] ?? const [];
      for (final s in list) {
        seen.add(s.filePath);
      }
    }
    return seen.length;
  }

  Future<void> _showManageFoldersSheet(
    BuildContext context,
    LocalMusicProvider localProvider,
  ) async {
    final palette = context.palette;
    final hairline = palette.hairline;
    final initialDetected = localProvider.detectedFoldersInfo;
    final Set<String> draftHiddenPaths = <String>{
      for (final info in initialDetected)
        if (info.isHidden) info.folderPath,
    };
    bool draftOnlyMusic = localProvider.onlyMusicFolders;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.nowPlayingBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Consumer<LocalMusicProvider>(
              builder: (ctx, provider, _) {
                final modalPalette = ctx.palette;
                final detected = provider.detectedFoldersInfo;
                final draftHiddenCount = detected
                    .where((f) => draftHiddenPaths.contains(f.folderPath))
                    .length;

                int changedFoldersCount = 0;
                for (final info in detected) {
                  final isDraftHidden = draftHiddenPaths.contains(
                    info.folderPath,
                  );
                  if (isDraftHidden != info.isHidden) {
                    changedFoldersCount++;
                  }
                }
                final bool hasDraftChanges = changedFoldersCount > 0 ||
                    draftOnlyMusic != provider.onlyMusicFolders;

                return SafeArea(
                  top: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.82,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            margin: const EdgeInsets.only(top: 10, bottom: 8),
                            decoration: BoxDecoration(
                              color:
                                  modalPalette.nowPlayingSecondary.withValues(
                                alpha: 0.35,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 6, 12, 12),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: modalPalette.surfaceSubtle,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Image.asset(
                                  'assets/folder.png',
                                  width: 18,
                                  height: 18,
                                  fit: BoxFit.contain,
                                  color: modalPalette.nowPlayingPrimary,
                                  colorBlendMode: BlendMode.srcIn,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppStrings.tr(
                                        'Kelola / Sembunyikan Folder',
                                        'Manage / Hide Folders',
                                        ctx,
                                      ),
                                      style: TextStyle(
                                        color: modalPalette.nowPlayingPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      AppStrings.tr(
                                        'Pilih folder lalu ketuk Terapkan untuk memperbarui pustaka & antrean.',
                                        'Select folders then tap Apply to update library & queue.',
                                        ctx,
                                      ),
                                      style: TextStyle(
                                        color: modalPalette.nowPlayingSecondary,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (draftHiddenCount > 0 || draftOnlyMusic)
                                MographSpringTap(
                                  pressedScale: 0.90,
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          modalPalette.nowPlayingPrimary,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () {
                                      setModalState(() {
                                        draftHiddenPaths.clear();
                                        draftOnlyMusic = false;
                                      });
                                    },
                                    child: Text(
                                      AppStrings.tr(
                                        'Tampilkan Semua ($draftHiddenCount)',
                                        'Show All ($draftHiddenCount)',
                                        ctx,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Divider(height: 1, thickness: 0.8, color: hairline),
                        // Draft Quick-Filter: Only folders containing "Music"
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                          child: MographSpringTap(
                            pressedScale: 0.985,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: draftOnlyMusic
                                    ? modalPalette.nowPlayingPrimary.withValues(
                                        alpha: ctx.isDarkMode ? 0.12 : 0.06,
                                      )
                                    : modalPalette.surfaceSubtle.withValues(
                                        alpha: 0.6,
                                      ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: draftOnlyMusic
                                      ? modalPalette.nowPlayingPrimary
                                          .withValues(
                                          alpha: 0.35,
                                        )
                                      : hairline,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                children: [
                                  MographStatePop(
                                    stateKey: draftOnlyMusic,
                                    scaleBoost: 0.20,
                                    rotationKickRad: -0.25,
                                    child: Icon(
                                      Icons.filter_alt_outlined,
                                      color: draftOnlyMusic
                                          ? modalPalette.nowPlayingPrimary
                                          : modalPalette.nowPlayingSecondary,
                                      size: 19,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          AppStrings.tr(
                                            'Filter kata "Music"',
                                            'Filter "Music" folders',
                                            ctx,
                                          ),
                                          style: TextStyle(
                                            color:
                                                modalPalette.nowPlayingPrimary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          AppStrings.tr(
                                            'Sembunyikan otomatis folder tanpa kata "Music"',
                                            'Auto-hide folders without "Music" in name',
                                            ctx,
                                          ),
                                          style: TextStyle(
                                            color: modalPalette
                                                .nowPlayingSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch.adaptive(
                                    key: const ValueKey(
                                      'manage_folders_only_music_switch',
                                    ),
                                    value: draftOnlyMusic,
                                    activeThumbColor:
                                        modalPalette.nowPlayingOnPrimary,
                                    activeTrackColor:
                                        modalPalette.nowPlayingPrimary,
                                    onChanged: (onlyMusic) {
                                      setModalState(() {
                                        draftOnlyMusic = onlyMusic;
                                        if (onlyMusic) {
                                          for (final info in detected) {
                                            if (!info.folderName
                                                .toLowerCase()
                                                .contains('music')) {
                                              draftHiddenPaths.add(
                                                info.folderPath,
                                              );
                                            }
                                          }
                                        } else {
                                          for (final info in detected) {
                                            if (!info.folderName
                                                .toLowerCase()
                                                .contains('music')) {
                                              draftHiddenPaths.remove(
                                                info.folderPath,
                                              );
                                            }
                                          }
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (detected.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 32,
                            ),
                            child: Center(
                              child: Text(
                                AppStrings.tr(
                                  'Belum ada folder audio yang terdeteksi di penyimpanan.',
                                  'No audio folders detected on device storage yet.',
                                  ctx,
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: modalPalette.nowPlayingSecondary,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          )
                        else
                          Flexible(
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                              itemCount: detected.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (itemCtx, idx) {
                                final info = detected[idx];
                                final isVisible = !draftHiddenPaths.contains(
                                  info.folderPath,
                                );
                                final isModifiedInDraft =
                                    (!isVisible) != info.isHidden;
                                return MographSpringTap(
                                  pressedScale: 0.985,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isVisible
                                          ? modalPalette.surfaceSubtle
                                              .withValues(alpha: 0.65)
                                          : modalPalette.surfaceSubtle
                                              .withValues(alpha: 0.28),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isModifiedInDraft
                                            ? modalPalette.nowPlayingPrimary
                                                .withValues(alpha: 0.48)
                                            : hairline,
                                        width: isModifiedInDraft ? 1.0 : 0.8,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        MographAnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 240,
                                          ),
                                          rotationTurns: -0.18,
                                          child: isVisible
                                              ? Image.asset(
                                                  'assets/folder.png',
                                                  key: const ValueKey(
                                                    'folder_visible_icon',
                                                  ),
                                                  width: 19,
                                                  height: 19,
                                                  fit: BoxFit.contain,
                                                  color: modalPalette
                                                      .nowPlayingPrimary,
                                                  colorBlendMode:
                                                      BlendMode.srcIn,
                                                )
                                              : Icon(
                                                  Icons.folder_off_outlined,
                                                  key: const ValueKey(
                                                    'folder_hidden_icon',
                                                  ),
                                                  color: modalPalette
                                                      .nowPlayingSecondary,
                                                  size: 20,
                                                ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      info.folderName,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: isVisible
                                                            ? modalPalette
                                                                .nowPlayingPrimary
                                                            : modalPalette
                                                                .nowPlayingSecondary,
                                                        fontSize: 13.5,
                                                        fontWeight: isVisible
                                                            ? FontWeight.w600
                                                            : FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 1.5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: modalPalette
                                                          .nowPlayingBg
                                                          .withValues(
                                                              alpha: 0.75),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        5,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      AppStrings
                                                          .songsCountLabel(
                                                        info.songCount,
                                                        ctx,
                                                      ),
                                                      style: TextStyle(
                                                        color: modalPalette
                                                            .nowPlayingSecondary,
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                info.folderPath,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: modalPalette
                                                      .nowPlayingSecondary,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Switch.adaptive(
                                          key: ValueKey(
                                            'folder_visibility_switch_${info.folderName}',
                                          ),
                                          value: isVisible,
                                          activeThumbColor:
                                              modalPalette.nowPlayingOnPrimary,
                                          activeTrackColor:
                                              modalPalette.nowPlayingPrimary,
                                          onChanged: (showFolder) {
                                            setModalState(() {
                                              if (showFolder) {
                                                draftHiddenPaths.remove(
                                                  info.folderPath,
                                                );
                                              } else {
                                                draftHiddenPaths.add(
                                                  info.folderPath,
                                                );
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        Divider(height: 1, thickness: 0.8, color: hairline),
                        // Bottom Action Bar: Batal + Mograph Spring "Terapkan" Button
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: PressableScale(
                                  child: OutlinedButton(
                                    key: const ValueKey(
                                      'manage_folders_cancel_button',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor:
                                          modalPalette.nowPlayingPrimary,
                                      side: BorderSide(
                                        color: hairline,
                                        width: 0.9,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 11,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: () =>
                                        Navigator.of(sheetCtx).pop(),
                                    child: Text(
                                      AppStrings.tr('Batal', 'Cancel', ctx),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween<double>(
                                    begin: 0.0,
                                    end: hasDraftChanges ? 1.0 : 0.0,
                                  ),
                                  duration: const Duration(milliseconds: 340),
                                  curve: Curves.easeOutBack,
                                  builder: (context, animVal, child) {
                                    final bounce = hasDraftChanges
                                        ? (1.0 + (animVal - 1.0) * 0.35)
                                            .clamp(0.92, 1.08)
                                        : 1.0;
                                    return Transform.scale(
                                      scale: bounce,
                                      child: child,
                                    );
                                  },
                                  child: PressableScale(
                                    child: ElevatedButton.icon(
                                      key: const ValueKey(
                                        'manage_folders_apply_button',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: hasDraftChanges
                                            ? modalPalette.nowPlayingPrimary
                                            : modalPalette.surfaceSubtle,
                                        foregroundColor: hasDraftChanges
                                            ? modalPalette.nowPlayingOnPrimary
                                            : modalPalette.nowPlayingPrimary,
                                        elevation: hasDraftChanges ? 2 : 0,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 11,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          side: BorderSide(
                                            color: hasDraftChanges
                                                ? modalPalette.nowPlayingPrimary
                                                : hairline,
                                            width: 0.9,
                                          ),
                                        ),
                                      ),
                                      onPressed: () async {
                                        final visibilityMap = <String, bool>{
                                          for (final info in detected)
                                            info.folderPath: !draftHiddenPaths
                                                .contains(info.folderPath),
                                        };
                                        await provider
                                            .applyFolderVisibilityChanges(
                                          folderVisibilityByPath: visibilityMap,
                                          onlyMusicFolders: draftOnlyMusic,
                                        );
                                        if (mounted) {
                                          final currentFolders =
                                              provider.folderSongsMap;
                                          setState(() {
                                            if (_openedFolder != null &&
                                                !currentFolders.containsKey(
                                                  _openedFolder,
                                                )) {
                                              _openedFolder = null;
                                            }
                                            _selectedFolders.removeWhere(
                                              (f) => !currentFolders
                                                  .containsKey(f),
                                            );
                                            if (_selectedFolders.isEmpty) {
                                              _isSelectionMode = false;
                                            }
                                          });
                                        }
                                        if (sheetCtx.mounted) {
                                          Navigator.of(sheetCtx).pop();
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.check_circle_outline_rounded,
                                        size: 17,
                                      ),
                                      label: Text(
                                        changedFoldersCount > 0
                                            ? '${AppStrings.tr('Terapkan', 'Apply', ctx)} ($changedFoldersCount)'
                                            : AppStrings.tr(
                                                'Terapkan',
                                                'Apply',
                                                ctx,
                                              ),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
      },
    );
  }

  Future<void> _confirmDeleteSelectedSongs({
    required BuildContext context,
    required String folderName,
    required List<LocalSong> selectedSongs,
    required LocalMusicProvider localProvider,
  }) async {
    if (selectedSongs.isEmpty) return;
    final palette = context.palette;
    final count = selectedSongs.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.nowPlayingBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.hairline, width: 0.8),
        ),
        title: Text(
          AppStrings.tr(
            'Hapus File Lagu?',
            'Delete Song Files?',
            ctx,
          ),
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          AppStrings.tr(
            'Hapus permanen $count file lagu terpilih dari folder $folderName?',
            'Permanently delete $count selected song files from $folderName?',
            ctx,
          ),
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 13,
          ),
        ),
        actions: [
          MographSpringTap(
            pressedScale: 0.90,
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                AppStrings.tr('Batal', 'Cancel', ctx),
                style: TextStyle(color: palette.textMuted),
              ),
            ),
          ),
          MographSpringTap(
            pressedScale: 0.90,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: MusEveePalette.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(AppStrings.tr('Hapus', 'Delete', ctx)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    int deletedCount = 0;
    for (final song in selectedSongs) {
      final ok = await localProvider.deleteLocalSong(song);
      if (ok) {
        deletedCount++;
        _selectedSongPaths.remove(song.filePath);
      }
    }
    if (!mounted) return;
    _exitFolderSongsSelectionMode();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deletedCount > 0
              ? AppStrings.tr(
                  '$deletedCount file lagu berhasil dihapus.',
                  '$deletedCount song files deleted.',
                  context,
                )
              : AppStrings.tr(
                  'Penghapusan dibatalkan atau izin ditolak.',
                  'Deletion cancelled or permission denied.',
                  context,
                ),
        ),
      ),
    );
  }

  Widget _buildOpenedFolderView({
    required BuildContext context,
    required String folderName,
    required List<LocalSong> allFolderSongs,
    required LocalMusicProvider localProvider,
    required DownloaderProvider downloaderProvider,
  }) {
    final palette = context.palette;
    final hairline = palette.hairline;

    final validPaths = <String>{for (final s in allFolderSongs) s.filePath};
    _selectedSongPaths.removeWhere((p) => !validPaths.contains(p));
    final selectedSongs = allFolderSongs
        .where((s) => _selectedSongPaths.contains(s.filePath))
        .toList();

    final q = _folderSongsSearchQuery.trim().toLowerCase();
    final displayedSongs = (!_isFolderSongsSelectionMode && q.isNotEmpty)
        ? allFolderSongs.where((s) {
            return s.title.toLowerCase().contains(q) ||
                s.artist.toLowerCase().contains(q) ||
                s.album.toLowerCase().contains(q);
          }).toList()
        : allFolderSongs;

    return Container(
      key: ValueKey('opened_folder_view_$folderName'),
      color: palette.nowPlayingBg,
      child: Stack(
        children: [
          Column(
            children: [
              // Clean Monochrome Header matching `design/folder redesign - 2.png`
              Container(
                padding: statusBarHeaderPadding(context, left: 8),
                decoration: cleanMonochromeHeaderDecoration(context),
                child: Row(
                  children: [
                    MographAnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      rotationTurns: -0.18,
                      child: _isFolderSongsSelectionMode
                          ? Padding(
                              key: const ValueKey('opened_folder_select_icon'),
                              padding: const EdgeInsets.only(left: 8, right: 8),
                              child: Icon(
                                Icons.library_add_check_rounded,
                                color: palette.textPrimary,
                                size: 19,
                              ),
                            )
                          : Row(
                              key: const ValueKey('opened_folder_back_wrap'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                MographSpringTap(
                                  pressedScale: 0.80,
                                  tapOffsetKick: const Offset(-3.5, 0.0),
                                  child: IconButton(
                                    key: const ValueKey(
                                      'opened_folder_back_button',
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _closeOpenedFolder,
                                    icon: Icon(
                                      Icons.arrow_back_rounded,
                                      color: palette.textPrimary,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                            ),
                    ),
                    Expanded(
                      child: Text(
                        _isFolderSongsSelectionMode
                            ? '${selectedSongs.length} ${AppStrings.tr('Lagu Dipilih', 'Selected', context)}'
                            : folderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (_isFolderSongsSelectionMode) ...[
                      if (displayedSongs.length > 1)
                        MographSpringTap(
                          pressedScale: 0.90,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: palette.textPrimary,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                final allSelected = displayedSongs.every(
                                  (s) =>
                                      _selectedSongPaths.contains(s.filePath),
                                );
                                if (allSelected) {
                                  _selectedSongPaths.clear();
                                } else {
                                  _selectedSongPaths.addAll(
                                    displayedSongs.map((s) => s.filePath),
                                  );
                                }
                              });
                            },
                            child: Text(
                              displayedSongs.every(
                                (s) => _selectedSongPaths.contains(s.filePath),
                              )
                                  ? 'Reset'
                                  : AppStrings.tr('Semua', 'All', context),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      MographSpringTap(
                        pressedScale: 0.80,
                        tapRotationRad: 0.24,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: AppStrings.tr(
                            'Batal Pilih',
                            'Cancel selection',
                            context,
                          ),
                          onPressed: _exitFolderSongsSelectionMode,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 19,
                            color: palette.nowPlayingSecondary,
                          ),
                        ),
                      ),
                    ] else if (allFolderSongs.isNotEmpty) ...[
                      MographSpringTap(
                        pressedScale: 0.82,
                        tapOffsetKick: const Offset(0.0, -2.5),
                        child: IconButton(
                          key: const ValueKey('opened_folder_add_queue_button'),
                          visualDensity: VisualDensity.compact,
                          tooltip: AppStrings.tr(
                            'Tambahkan Semua ke Antrean',
                            'Add All to Queue',
                            context,
                          ),
                          onPressed: () async {
                            final added =
                                await localProvider.playCombinedFolders(
                              [folderName],
                              appendToCurrentQueue: true,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    added > 0
                                        ? AppStrings.tr(
                                            '$added lagu dari "$folderName" ditambahkan ke akhir antrean.',
                                            '$added songs from "$folderName" added to queue.',
                                            context,
                                          )
                                        : AppStrings.tr(
                                            'Semua lagu dari "$folderName" sudah ada di antrean.',
                                            'All songs from "$folderName" are already in queue.',
                                            context,
                                          ),
                                  ),
                                ),
                              );
                            }
                          },
                          icon: Icon(
                            Icons.playlist_add_rounded,
                            color: palette.textPrimary,
                            size: 21,
                          ),
                        ),
                      ),
                      MographSpringTap(
                        pressedScale: 0.82,
                        tapRotationRad: 0.22,
                        child: IconButton(
                          key: const ValueKey('opened_folder_shuffle_button'),
                          visualDensity: VisualDensity.compact,
                          tooltip: AppStrings.tr(
                            'Acak Semua',
                            'Shuffle All',
                            context,
                          ),
                          onPressed: () {
                            localProvider.playFolder(folderName, shuffle: true);
                            widget.onOpenNowPlaying();
                          },
                          icon: Image.asset(
                            'assets/icons/arrow.png',
                            width: 19,
                            height: 19,
                            fit: BoxFit.contain,
                            color: palette.textPrimary,
                            colorBlendMode: BlendMode.srcIn,
                          ),
                        ),
                      ),
                      MographSpringTap(
                        pressedScale: 0.82,
                        tapOffsetKick: const Offset(3.0, 0.0),
                        child: IconButton(
                          key: const ValueKey('opened_folder_play_all_button'),
                          visualDensity: VisualDensity.compact,
                          tooltip: AppStrings.tr(
                            'Putar Semua',
                            'Play All',
                            context,
                          ),
                          onPressed: () {
                            localProvider.playFolder(folderName,
                                shuffle: false);
                            widget.onOpenNowPlaying();
                          },
                          icon: Icon(
                            Icons.play_arrow_rounded,
                            color: palette.textPrimary,
                            size: 26,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Inline Search Bar inside Opened Folder ("Search songs/artist in this folder")
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: _isFolderSongsSelectionMode
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                        child: SizedBox(
                          height: 44,
                          child: TextField(
                            key: const ValueKey('folder_songs_search_field'),
                            controller: _folderSongsSearchController,
                            style: TextStyle(
                              color: palette.nowPlayingPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                            onChanged: (value) {
                              setState(() => _folderSongsSearchQuery = value);
                            },
                            decoration: InputDecoration(
                              hintText:
                                  AppStrings.folderSongsSearchHint(context),
                              hintStyle: TextStyle(
                                color: palette.nowPlayingSecondary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w400,
                              ),
                              filled: true,
                              fillColor: palette.surfaceSubtle,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              prefixIcon: Padding(
                                padding: const EdgeInsets.only(
                                  left: 14,
                                  right: 10,
                                ),
                                child: Image.asset(
                                  'assets/search.png',
                                  width: 17,
                                  height: 17,
                                  fit: BoxFit.contain,
                                  color: palette.nowPlayingArtist,
                                  colorBlendMode: BlendMode.srcIn,
                                ),
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              suffixIcon: _folderSongsSearchQuery.isNotEmpty
                                  ? MographSpringTap(
                                      pressedScale: 0.78,
                                      tapRotationRad: 0.24,
                                      child: IconButton(
                                        key: const ValueKey(
                                          'folder_songs_search_clear_button',
                                        ),
                                        tooltip: AppStrings.clearTooltip,
                                        icon: Icon(
                                          Icons.close_rounded,
                                          size: 17,
                                          color: palette.nowPlayingSecondary,
                                        ),
                                        onPressed: () {
                                          _folderSongsSearchController.clear();
                                          setState(
                                            () => _folderSongsSearchQuery = '',
                                          );
                                        },
                                      ),
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: palette.nowPlayingPrimary.withValues(
                                    alpha: 0.22,
                                  ),
                                  width: 0.8,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),

              Expanded(
                child: displayedSongs.isEmpty
                    ? _EmptyLocalHint(
                        icon: q.isNotEmpty
                            ? Icons.search_off_rounded
                            : Icons.music_off_rounded,
                        message: q.isNotEmpty
                            ? AppStrings.localSearchNoMatch
                            : AppStrings.tr(
                                'Folder ini belum berisi file lagu.',
                                'This folder does not contain audio files yet.',
                                context,
                              ),
                      )
                    : ListView.separated(
                        key: const ValueKey('opened_folder_songs_list'),
                        padding: EdgeInsets.fromLTRB(
                          0,
                          6,
                          0,
                          _isFolderSongsSelectionMode ? 108 : 88,
                        ),
                        itemCount: displayedSongs.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          thickness: 0.7,
                          indent: 18,
                          endIndent: 18,
                          color: hairline,
                        ),
                        itemBuilder: (context, idx) {
                          final song = displayedSongs[idx];
                          final isSelected =
                              _selectedSongPaths.contains(song.filePath);
                          return _MographSelectionCard(
                            isSelected: isSelected,
                            isSelectionMode: _isFolderSongsSelectionMode,
                            child: _LocalSongTile(
                              song: song,
                              queueContext: displayedSongs,
                              localProvider: localProvider,
                              downloaderProvider: downloaderProvider,
                              onMoveLocalSongFolder:
                                  widget.onMoveLocalSongFolder,
                              onOpenNowPlaying: widget.onOpenNowPlaying,
                              cleanMonochromeStyle: true,
                              minimalFolderSongStyle: true,
                              isSelectionMode: _isFolderSongsSelectionMode,
                              isSelected: isSelected,
                              onTapOverride: _isFolderSongsSelectionMode
                                  ? () =>
                                      _toggleFolderSongSelection(song.filePath)
                                  : null,
                              onLongPress: () =>
                                  _toggleFolderSongSelection(song.filePath),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          if (allFolderSongs.isNotEmpty)
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: _MorphingMergeActionBar(
                fabKey: const ValueKey('folder_songs_merge_fab'),
                isExpanded: _isFolderSongsSelectionMode,
                idleTooltip: AppStrings.tr(
                  'Pilih Banyak Lagu',
                  'Select Multiple Songs',
                  context,
                ),
                label: selectedSongs.isEmpty
                    ? AppStrings.selectSongsLabel(context)
                    : AppStrings.songsCountLabel(selectedSongs.length, context),
                hasSelection: selectedSongs.isNotEmpty,
                monochromeStyle: true,
                useCheckAssetIcon: true,
                onOpen: () =>
                    setState(() => _isFolderSongsSelectionMode = true),
                onCancel: _exitFolderSongsSelectionMode,
                onPlayCombined: () async {
                  if (selectedSongs.isEmpty) return;
                  final targets = List<LocalSong>.from(selectedSongs);
                  _exitFolderSongsSelectionMode();
                  await localProvider.playCombinedSongs(
                    targets,
                    shuffle: false,
                  );
                  widget.onOpenNowPlaying();
                },
                onShuffleCombined: () async {
                  if (selectedSongs.isEmpty) return;
                  final targets = List<LocalSong>.from(selectedSongs);
                  _exitFolderSongsSelectionMode();
                  await localProvider.playCombinedSongs(
                    targets,
                    shuffle: true,
                  );
                  widget.onOpenNowPlaying();
                },
                onAppendQueue: () async {
                  if (selectedSongs.isEmpty) return;
                  final targets = List<LocalSong>.from(selectedSongs);
                  _exitFolderSongsSelectionMode();
                  final added = await localProvider.playCombinedSongs(
                    targets,
                    appendToCurrentQueue: true,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          added > 0
                              ? AppStrings.tr(
                                  '$added lagu terpilih ditambahkan ke akhir antrean.',
                                  '$added selected songs added to queue.',
                                  context,
                                )
                              : AppStrings.tr(
                                  'Semua lagu terpilih sudah ada di antrean.',
                                  'All selected songs are already in queue.',
                                  context,
                                ),
                        ),
                      ),
                    );
                  }
                },
                onDeleteSelected: () => _confirmDeleteSelectedSongs(
                  context: context,
                  folderName: folderName,
                  selectedSongs: List<LocalSong>.from(selectedSongs),
                  localProvider: localProvider,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemLocaleScope.watch(context);
    final palette = context.palette;
    final hairline = palette.hairline;

    return Consumer2<LocalMusicProvider, DownloaderProvider>(
      builder: (context, localProvider, downloaderProvider, _) {
        final folderMap = localProvider.folderSongsMap;

        final bool showOpenedFolder =
            _openedFolder != null && folderMap.containsKey(_openedFolder);
        if (!showOpenedFolder && _openedFolder != null) {
          _openedFolder = null;
          _isFolderSongsSelectionMode = false;
          _selectedSongPaths.clear();
          _folderSongsSearchController.clear();
          _folderSongsSearchQuery = '';
        }

        final folderNames = folderMap.keys.toList();
        final hiddenCount = localProvider.hiddenFoldersCount;
        // Prune any selected folder that is no longer visible
        _selectedFolders.removeWhere((f) => !folderMap.containsKey(f));
        final selectedList = _selectedFolders.toList();
        final selectedSongCount =
            _countUniqueSongsForFolders(folderMap, selectedList);

        final isSearching = !_isSelectionMode && _searchQuery.trim().isNotEmpty;
        final matchingSongs = isSearching
            ? _matchingSongsForQuery(localProvider.allSongs, _searchQuery)
            : const <LocalSong>[];

        final Widget activeView = showOpenedFolder
            ? _buildOpenedFolderView(
                context: context,
                folderName: _openedFolder!,
                allFolderSongs: folderMap[_openedFolder!] ?? const [],
                localProvider: localProvider,
                downloaderProvider: downloaderProvider,
              )
            : Container(
                key: const ValueKey('folders_root_view'),
                color: palette.nowPlayingBg,
                child: Stack(
                  children: [
                    Column(
                      children: [
                        // Redesigned Folders Header (Clean Monochrome + Soft Shadow, Typography Aligned with Queue)
                        Container(
                          padding: statusBarHeaderPadding(context),
                          decoration: cleanMonochromeHeaderDecoration(context),
                          child: Row(
                            children: [
                              MographAnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                rotationTurns: -0.20,
                                child: _isSelectionMode
                                    ? Icon(
                                        Icons.library_add_check_rounded,
                                        key: const ValueKey(
                                          'folders_select_icon',
                                        ),
                                        color: palette.textPrimary,
                                        size: 19,
                                      )
                                    : Image.asset(
                                        'assets/folder.png',
                                        key:
                                            const ValueKey('folders_root_icon'),
                                        width: 19,
                                        height: 19,
                                        fit: BoxFit.contain,
                                        color: palette.textPrimary,
                                        colorBlendMode: BlendMode.srcIn,
                                      ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isSelectionMode
                                      ? '${selectedList.length} ${AppStrings.tr('Folder Dipilih', 'Selected', context)} (${AppStrings.songsCountLabel(selectedSongCount, context)})'
                                      : 'Folders',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              if (_isSelectionMode && folderNames.length > 1)
                                MographSpringTap(
                                  pressedScale: 0.90,
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor: palette.textPrimary,
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        if (_selectedFolders.length ==
                                            folderNames.length) {
                                          _selectedFolders.clear();
                                        } else {
                                          _selectedFolders.addAll(folderNames);
                                        }
                                      });
                                    },
                                    child: Text(
                                      _selectedFolders.length ==
                                              folderNames.length
                                          ? 'Reset'
                                          : AppStrings.tr(
                                              'Semua',
                                              'All',
                                              context,
                                            ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              if (!_isSelectionMode)
                                MographSpringTap(
                                  pressedScale: 0.90,
                                  child: TextButton(
                                    key: const ValueKey(
                                      'folders_manage_button',
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: palette.nowPlayingArtist,
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                    ),
                                    onPressed: () => _showManageFoldersSheet(
                                      context,
                                      localProvider,
                                    ),
                                    child: Text(
                                      hiddenCount > 0
                                          ? '${AppStrings.foldersManageAction(context)} ($hiddenCount)'
                                          : AppStrings.foldersManageAction(
                                              context,
                                            ),
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ),
                              if (_isSelectionMode)
                                MographSpringTap(
                                  pressedScale: 0.80,
                                  tapRotationRad: 0.24,
                                  child: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: AppStrings.tr(
                                      'Batal Pilih',
                                      'Cancel selection',
                                      context,
                                    ),
                                    onPressed: _exitSelectionMode,
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 19,
                                      color: palette.nowPlayingSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Inline Rounded Search Bar ("Search songs, artist, album...")
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: _isSelectionMode
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    22,
                                    16,
                                    22,
                                    8,
                                  ),
                                  child: SizedBox(
                                    height: 44,
                                    child: TextField(
                                      key: const ValueKey(
                                        'folders_search_field',
                                      ),
                                      controller: _searchController,
                                      style: TextStyle(
                                        color: palette.nowPlayingPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      onChanged: (value) {
                                        setState(() => _searchQuery = value);
                                      },
                                      decoration: InputDecoration(
                                        hintText: AppStrings.foldersSearchHint(
                                          context,
                                        ),
                                        hintStyle: TextStyle(
                                          color: palette.nowPlayingSecondary,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w400,
                                        ),
                                        filled: true,
                                        fillColor: palette.surfaceSubtle,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        prefixIcon: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 14,
                                            right: 10,
                                          ),
                                          child: Image.asset(
                                            'assets/search.png',
                                            width: 17,
                                            height: 17,
                                            fit: BoxFit.contain,
                                            color: palette.nowPlayingArtist,
                                            colorBlendMode: BlendMode.srcIn,
                                          ),
                                        ),
                                        prefixIconConstraints:
                                            const BoxConstraints(
                                          minWidth: 40,
                                          minHeight: 40,
                                        ),
                                        suffixIcon: _searchQuery.isNotEmpty
                                            ? MographSpringTap(
                                                pressedScale: 0.78,
                                                tapRotationRad: 0.24,
                                                child: IconButton(
                                                  key: const ValueKey(
                                                    'folders_search_clear_button',
                                                  ),
                                                  tooltip:
                                                      AppStrings.clearTooltip,
                                                  icon: Icon(
                                                    Icons.close_rounded,
                                                    size: 17,
                                                    color: palette
                                                        .nowPlayingSecondary,
                                                  ),
                                                  onPressed: () {
                                                    _searchController.clear();
                                                    setState(
                                                      () => _searchQuery = '',
                                                    );
                                                  },
                                                ),
                                              )
                                            : null,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: BorderSide.none,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: BorderSide.none,
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                            color: palette.nowPlayingPrimary
                                                .withValues(alpha: 0.22),
                                            width: 0.8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                        ),

                        Expanded(
                          child: MographAnimatedSwitcher(
                            stackFit: StackFit.expand,
                            duration: const Duration(milliseconds: 160),
                            reverseDuration: const Duration(milliseconds: 110),
                            beginScale: 0.985,
                            child: isSearching
                                ? (matchingSongs.isEmpty
                                    ? KeyedSubtree(
                                        key: const ValueKey(
                                          'folders_search_empty',
                                        ),
                                        child: _EmptyLocalHint(
                                          icon: Icons.search_off_rounded,
                                          message: localProvider
                                                  .allSongs.isEmpty
                                              ? AppStrings
                                                  .localSearchEmptyLibrary
                                              : AppStrings.localSearchNoMatch,
                                        ),
                                      )
                                    : ListView.separated(
                                        key: const ValueKey(
                                          'folders_inline_search_results',
                                        ),
                                        padding: const EdgeInsets.fromLTRB(
                                          0,
                                          4,
                                          0,
                                          24,
                                        ),
                                        itemCount: matchingSongs.length,
                                        separatorBuilder: (context, index) =>
                                            Divider(
                                          height: 1,
                                          thickness: 0.7,
                                          indent: 18,
                                          endIndent: 18,
                                          color: hairline,
                                        ),
                                        itemBuilder: (context, idx) {
                                          return _LocalSongTile(
                                            song: matchingSongs[idx],
                                            queueContext: matchingSongs,
                                            localProvider: localProvider,
                                            downloaderProvider:
                                                downloaderProvider,
                                            onMoveLocalSongFolder:
                                                widget.onMoveLocalSongFolder,
                                            onOpenNowPlaying:
                                                widget.onOpenNowPlaying,
                                            cleanMonochromeStyle: true,
                                          );
                                        },
                                      ))
                                : folderNames.isEmpty
                                    ? Center(
                                        key: const ValueKey(
                                          'folders_empty_state',
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 28,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Image.asset(
                                                'assets/folder.png',
                                                width: 40,
                                                height: 40,
                                                fit: BoxFit.contain,
                                                color:
                                                    palette.nowPlayingSecondary,
                                                colorBlendMode: BlendMode.srcIn,
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                hiddenCount > 0
                                                    ? AppStrings.tr(
                                                        'Semua folder sedang disembunyikan ($hiddenCount folder)',
                                                        'All folders are currently hidden ($hiddenCount folders)',
                                                        context,
                                                      )
                                                    : AppStrings.tr(
                                                        'Belum ada folder berisi lagu yang terdeteksi',
                                                        'No folders with audio files detected yet',
                                                        context,
                                                      ),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color:
                                                      palette.nowPlayingPrimary,
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                AppStrings.tr(
                                                  'Unduh lagu lewat tab Downloader atau pindai ulang penyimpanan perangkat Anda.',
                                                  'Download tracks via Downloader or rescan your device storage.',
                                                  context,
                                                ),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: palette
                                                      .nowPlayingSecondary,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              if (hiddenCount > 0) ...[
                                                const SizedBox(height: 14),
                                                MographSpringTap(
                                                  pressedScale: 0.92,
                                                  child: OutlinedButton.icon(
                                                    style: OutlinedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          Colors.transparent,
                                                      foregroundColor: palette
                                                          .nowPlayingPrimary,
                                                      side: BorderSide(
                                                        color: palette
                                                            .nowPlayingPrimary
                                                            .withValues(
                                                          alpha: 0.45,
                                                        ),
                                                        width: 0.9,
                                                      ),
                                                    ),
                                                    onPressed: () =>
                                                        _showManageFoldersSheet(
                                                      context,
                                                      localProvider,
                                                    ),
                                                    icon: const Icon(
                                                      Icons.visibility_rounded,
                                                      size: 16,
                                                    ),
                                                    label: Text(
                                                      AppStrings.tr(
                                                        'Kelola Folder Tersembunyi',
                                                        'Manage Hidden Folders',
                                                        context,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      )
                                    : ListView.separated(
                                        key: const ValueKey(
                                          'folders_list_view',
                                        ),
                                        padding: EdgeInsets.fromLTRB(
                                          0,
                                          6,
                                          0,
                                          _isSelectionMode ? 108 : 88,
                                        ),
                                        itemCount: folderNames.length,
                                        separatorBuilder: (context, index) =>
                                            Divider(
                                          height: 1,
                                          thickness: 0.7,
                                          indent: 18,
                                          endIndent: 18,
                                          color: hairline,
                                        ),
                                        itemBuilder: (context, idx) {
                                          final folder = folderNames[idx];
                                          final songs =
                                              folderMap[folder] ?? const [];
                                          final folderPath = songs.isNotEmpty
                                              ? songs.first.folderPath
                                              : '/storage/emulated/0/Music/$folder';
                                          final isSelected =
                                              _selectedFolders.contains(folder);

                                          return _MographSelectionCard(
                                            isSelected: isSelected,
                                            isSelectionMode: _isSelectionMode,
                                            child: MographSpringTap(
                                              pressedScale: 0.98,
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                curve: Curves.easeOutCubic,
                                                color: isSelected
                                                    ? palette.nowPlayingPrimary
                                                        .withValues(
                                                        alpha:
                                                            context.isDarkMode
                                                                ? 0.08
                                                                : 0.05,
                                                      )
                                                    : Colors.transparent,
                                                child: Material(
                                                  color: Colors.transparent,
                                                  child: InkWell(
                                                    onTap: () {
                                                      if (_isSelectionMode) {
                                                        _toggleFolderSelection(
                                                          folder,
                                                        );
                                                      } else {
                                                        setState(
                                                          () => _openedFolder =
                                                              folder,
                                                        );
                                                      }
                                                    },
                                                    onLongPress: () =>
                                                        _toggleFolderSelection(
                                                      folder,
                                                    ),
                                                    child: Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 20,
                                                        vertical: 11,
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          _MographSelectCheckbox(
                                                            isVisible:
                                                                _isSelectionMode,
                                                            isSelected:
                                                                isSelected,
                                                            monochromeStyle:
                                                                true,
                                                          ),
                                                          _FolderCoverCollage(
                                                            songs: songs,
                                                            size: 48,
                                                          ),
                                                          const SizedBox(
                                                            width: 16,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              folder,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                color: palette
                                                                    .textPrimary,
                                                                fontSize: 13.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                            ),
                                                          ),
                                                          if (!_isSelectionMode &&
                                                              songs
                                                                  .isNotEmpty) ...[
                                                            MographSpringTap(
                                                              pressedScale:
                                                                  0.82,
                                                              tapOffsetKick:
                                                                  const Offset(
                                                                2.5,
                                                                0.0,
                                                              ),
                                                              child: IconButton(
                                                                key: ValueKey(
                                                                  'folder_play_button_$folder',
                                                                ),
                                                                visualDensity:
                                                                    VisualDensity
                                                                        .compact,
                                                                tooltip:
                                                                    AppStrings
                                                                        .tr(
                                                                  'Putar Folder $folder',
                                                                  'Play Folder $folder',
                                                                  context,
                                                                ),
                                                                onPressed: () {
                                                                  localProvider
                                                                      .playFolder(
                                                                    folder,
                                                                  );
                                                                  widget
                                                                      .onOpenNowPlaying();
                                                                },
                                                                icon: Icon(
                                                                  Icons
                                                                      .play_arrow_rounded,
                                                                  color: palette
                                                                      .textPrimary,
                                                                  size: 24,
                                                                ),
                                                              ),
                                                            ),
                                                            MographSpringTap(
                                                              pressedScale:
                                                                  0.82,
                                                              tapRotationRad:
                                                                  0.16,
                                                              child:
                                                                  PopupMenuButton<
                                                                      String>(
                                                                key: ValueKey(
                                                                  'folder_more_button_$folder',
                                                                ),
                                                                icon: Icon(
                                                                  Icons
                                                                      .more_vert_rounded,
                                                                  size: 19,
                                                                  color: palette
                                                                      .textPrimary,
                                                                ),
                                                                color: palette
                                                                    .surfaceCard,
                                                                onSelected: (
                                                                  value,
                                                                ) async {
                                                                  if (value ==
                                                                      'shuffle') {
                                                                    localProvider
                                                                        .playFolder(
                                                                      folder,
                                                                      shuffle:
                                                                          true,
                                                                    );
                                                                    widget
                                                                        .onOpenNowPlaying();
                                                                  } else if (value ==
                                                                      'add_queue') {
                                                                    final added =
                                                                        await localProvider
                                                                            .playCombinedFolders(
                                                                      [folder],
                                                                      appendToCurrentQueue:
                                                                          true,
                                                                    );
                                                                    if (context
                                                                        .mounted) {
                                                                      ScaffoldMessenger
                                                                          .of(
                                                                        context,
                                                                      ).showSnackBar(
                                                                        SnackBar(
                                                                          content:
                                                                              Text(
                                                                            added > 0
                                                                                ? AppStrings.tr(
                                                                                    '$added lagu dari "$folder" ditambahkan ke antrean.',
                                                                                    '$added songs from "$folder" added to queue.',
                                                                                    context,
                                                                                  )
                                                                                : AppStrings.tr(
                                                                                    'Semua lagu dari "$folder" sudah ada di antrean.',
                                                                                    'All songs from "$folder" are already in queue.',
                                                                                    context,
                                                                                  ),
                                                                          ),
                                                                        ),
                                                                      );
                                                                    }
                                                                  } else if (value ==
                                                                      'multi_select') {
                                                                    _toggleFolderSelection(
                                                                      folder,
                                                                    );
                                                                  } else if (value ==
                                                                      'hide') {
                                                                    await localProvider
                                                                        .setFolderHidden(
                                                                      folderPath,
                                                                      folderName:
                                                                          folder,
                                                                      hidden:
                                                                          true,
                                                                    );
                                                                    if (context
                                                                        .mounted) {
                                                                      ScaffoldMessenger
                                                                          .of(
                                                                        context,
                                                                      ).showSnackBar(
                                                                        SnackBar(
                                                                          content:
                                                                              Text(
                                                                            AppStrings.tr(
                                                                              'Folder "$folder" disembunyikan dari pustaka.',
                                                                              'Folder "$folder" hidden from library.',
                                                                              context,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      );
                                                                    }
                                                                  }
                                                                },
                                                                itemBuilder:
                                                                    (_) => [
                                                                  PopupMenuItem(
                                                                    value:
                                                                        'shuffle',
                                                                    child: Text(
                                                                      AppStrings
                                                                          .tr(
                                                                        'Acak Folder (Shuffle)',
                                                                        'Shuffle Folder',
                                                                        context,
                                                                      ),
                                                                      style:
                                                                          TextStyle(
                                                                        color: palette
                                                                            .textPrimary,
                                                                        fontSize:
                                                                            13,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  PopupMenuItem(
                                                                    value:
                                                                        'add_queue',
                                                                    child: Text(
                                                                      AppStrings
                                                                          .tr(
                                                                        'Tambahkan ke Antrean Saat Ini (+ Queue)',
                                                                        'Add to Current Queue (+ Queue)',
                                                                        context,
                                                                      ),
                                                                      style:
                                                                          TextStyle(
                                                                        color: palette
                                                                            .textPrimary,
                                                                        fontSize:
                                                                            13,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  PopupMenuItem(
                                                                    value:
                                                                        'multi_select',
                                                                    child: Text(
                                                                      AppStrings
                                                                          .tr(
                                                                        'Pilih untuk Digabung (Multi-Folder)',
                                                                        'Select to Merge (Multi-Folder)',
                                                                        context,
                                                                      ),
                                                                      style:
                                                                          TextStyle(
                                                                        color: palette
                                                                            .nowPlayingPrimary,
                                                                        fontSize:
                                                                            13,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  PopupMenuItem(
                                                                    value:
                                                                        'hide',
                                                                    child: Text(
                                                                      AppStrings
                                                                          .tr(
                                                                        'Sembunyikan Folder Ini',
                                                                        'Hide This Folder',
                                                                        context,
                                                                      ),
                                                                      style:
                                                                          TextStyle(
                                                                        color: palette
                                                                            .textMuted,
                                                                        fontSize:
                                                                            13,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                          ),
                        ),
                      ],
                    ),
                    if (folderNames.isNotEmpty &&
                        (_isSelectionMode || !isSearching))
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 14,
                        child: _MorphingMergeActionBar(
                          isExpanded: _isSelectionMode,
                          idleTooltip: AppStrings.tr(
                            'Gabung / Pilih Banyak Folder',
                            'Merge / Select Multiple Folders',
                            context,
                          ),
                          label: selectedList.isEmpty
                              ? AppStrings.selectFoldersLabel(context)
                              : '${selectedList.length} ${AppStrings.tr('Folder', selectedList.length == 1 ? 'Folder' : 'Folders', context)} • ${AppStrings.songsCountLabel(selectedSongCount, context)}',
                          hasSelection: selectedList.isNotEmpty,
                          monochromeStyle: true,
                          useCheckAssetIcon: true,
                          onOpen: () => setState(() => _isSelectionMode = true),
                          onCancel: _exitSelectionMode,
                          onPlayCombined: () async {
                            if (selectedList.isEmpty) return;
                            final targets = List<String>.from(selectedList);
                            _exitSelectionMode();
                            await localProvider.playCombinedFolders(
                              targets,
                              shuffle: false,
                            );
                            widget.onOpenNowPlaying();
                          },
                          onShuffleCombined: () async {
                            if (selectedList.isEmpty) return;
                            final targets = List<String>.from(selectedList);
                            _exitSelectionMode();
                            await localProvider.playCombinedFolders(
                              targets,
                              shuffle: true,
                            );
                            widget.onOpenNowPlaying();
                          },
                          onAppendQueue: () async {
                            if (selectedList.isEmpty) return;
                            final targets = List<String>.from(selectedList);
                            _exitSelectionMode();
                            final added =
                                await localProvider.playCombinedFolders(
                              targets,
                              appendToCurrentQueue: true,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    added > 0
                                        ? AppStrings.tr(
                                            '$added lagu dari ${targets.length} folder ditambahkan ke akhir antrean.',
                                            '$added songs from ${targets.length} folders added to queue.',
                                            context,
                                          )
                                        : AppStrings.tr(
                                            'Semua lagu dari folder terpilih sudah ada di antrean.',
                                            'All songs from selected folders are already in queue.',
                                            context,
                                          ),
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                  ],
                ),
              );

        return MographAnimatedSwitcher(
          stackFit: StackFit.expand,
          duration: const Duration(milliseconds: 210),
          reverseDuration: const Duration(milliseconds: 130),
          beginScale: 0.985,
          slideOffset: showOpenedFolder
              ? const Offset(0.04, 0.0)
              : const Offset(-0.03, 0.0),
          child: activeView,
        );
      },
    );
  }
}

// =============================================================================
// TAB 3: PLAYLISTS (`musicevee_playlists_v1.json`) — replaces Albums & Artists
// =============================================================================
class LocalPlaylistsView extends StatefulWidget {
  final VoidCallback onOpenNowPlaying;
  final Future<void> Function(LocalSong song) onMoveLocalSongFolder;
  final VoidCallback? onOpenAllSongsSearch;
  final int openAllSongsSearchRequestId;

  const LocalPlaylistsView({
    super.key,
    required this.onOpenNowPlaying,
    required this.onMoveLocalSongFolder,
    this.onOpenAllSongsSearch,
    this.openAllSongsSearchRequestId = 0,
  });

  @override
  State<LocalPlaylistsView> createState() => LocalPlaylistsViewState();
}

class LocalPlaylistsViewState extends State<LocalPlaylistsView> {
  String? _openedPlaylistId;
  bool _isSelectionMode = false;
  final Set<String> _selectedPlaylistIds = <String>{};
  final TextEditingController _allSongsSearchController =
      TextEditingController();
  final FocusNode _allSongsSearchFocusNode = FocusNode();
  bool _shouldAutoFocusAllSongsSearch = false;

  final TextEditingController _playlistSongsSearchController =
      TextEditingController();
  String _playlistSongsSearchQuery = '';
  bool _isPlaylistSongsSelectionMode = false;
  final Set<String> _selectedPlaylistSongPaths = <String>{};

  void _closeOpenedPlaylist(LocalMusicProvider localProvider) {
    if (_openedPlaylistId == SmartPlaylistId.allSongs) {
      _shouldAutoFocusAllSongsSearch = false;
      _allSongsSearchController.clear();
      localProvider.setLocalSearchQuery('');
      if (localProvider.filterFavoritesOnly) {
        localProvider.toggleFilterFavoritesOnly();
      }
    }
    _playlistSongsSearchController.clear();
    setState(() {
      _openedPlaylistId = null;
      _playlistSongsSearchQuery = '';
      _isPlaylistSongsSelectionMode = false;
      _selectedPlaylistSongPaths.clear();
    });
  }

  void _togglePlaylistSongSelection(String filePath) {
    setState(() {
      if (_selectedPlaylistSongPaths.contains(filePath)) {
        _selectedPlaylistSongPaths.remove(filePath);
        if (_selectedPlaylistSongPaths.isEmpty) {
          _isPlaylistSongsSelectionMode = false;
        }
      } else {
        _selectedPlaylistSongPaths.add(filePath);
        _isPlaylistSongsSelectionMode = true;
      }
    });
  }

  void _exitPlaylistSongsSelectionMode() {
    if (!_isPlaylistSongsSelectionMode && _selectedPlaylistSongPaths.isEmpty) {
      return;
    }
    setState(() {
      _isPlaylistSongsSelectionMode = false;
      _selectedPlaylistSongPaths.clear();
    });
  }

  /// Handles system back navigation inside the Playlists tab:
  /// 1. Inside an opened playlist: exits song selection, clears local playlist
  ///    search (non-All-songs), or closes the opened playlist (clearing All
  ///    songs query/filter if needed).
  /// 2. At Playlists root: exits Multi-Playlist selection mode if active.
  /// Returns `true` if a sub-state was popped, `false` if already at root.
  bool handleBack() {
    if (_openedPlaylistId != null) {
      if (_isPlaylistSongsSelectionMode) {
        _exitPlaylistSongsSelectionMode();
        return true;
      }
      if (_openedPlaylistId != SmartPlaylistId.allSongs &&
          _playlistSongsSearchQuery.isNotEmpty) {
        _playlistSongsSearchController.clear();
        setState(() => _playlistSongsSearchQuery = '');
        FocusScope.of(context).unfocus();
        return true;
      }
      _closeOpenedPlaylist(context.read<LocalMusicProvider>());
      return true;
    }
    if (_isSelectionMode) {
      _exitSelectionMode();
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    if (widget.openAllSongsSearchRequestId > 0) {
      _openedPlaylistId = SmartPlaylistId.allSongs;
      _shouldAutoFocusAllSongsSearch = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _allSongsSearchFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant LocalPlaylistsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openAllSongsSearchRequestId !=
            oldWidget.openAllSongsSearchRequestId &&
        widget.openAllSongsSearchRequestId > 0) {
      _openAllSongsAndFocusSearch();
    }
  }

  @override
  void dispose() {
    _allSongsSearchController.dispose();
    _allSongsSearchFocusNode.dispose();
    _playlistSongsSearchController.dispose();
    super.dispose();
  }

  void _openAllSongsAndFocusSearch() {
    setState(() {
      _isSelectionMode = false;
      _selectedPlaylistIds.clear();
      _isPlaylistSongsSelectionMode = false;
      _selectedPlaylistSongPaths.clear();
      _playlistSongsSearchController.clear();
      _playlistSongsSearchQuery = '';
      _shouldAutoFocusAllSongsSearch = true;
      _openedPlaylistId = SmartPlaylistId.allSongs;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _allSongsSearchFocusNode.requestFocus();
      }
    });
  }

  Widget _buildAllSongsSearchBar(
    LocalMusicProvider localProvider,
  ) {
    final palette = context.palette;
    if (localProvider.localSearchQuery.isEmpty &&
        _allSongsSearchController.text.isNotEmpty) {
      _allSongsSearchController.clear();
    } else if (localProvider.localSearchQuery.isNotEmpty &&
        _allSongsSearchController.text != localProvider.localSearchQuery) {
      _allSongsSearchController.value = TextEditingValue(
        text: localProvider.localSearchQuery,
        selection: TextSelection.collapsed(
          offset: localProvider.localSearchQuery.length,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                key: const ValueKey('all_songs_search_field'),
                controller: _allSongsSearchController,
                focusNode: _allSongsSearchFocusNode,
                autofocus: _shouldAutoFocusAllSongsSearch,
                style: TextStyle(
                  color: palette.nowPlayingPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
                onChanged: localProvider.setLocalSearchQuery,
                decoration: _monochromeSearchInputDecoration(
                  context,
                  hintText: AppStrings.localSearchHint,
                  showClearButton: localProvider.localSearchQuery.isNotEmpty,
                  clearButtonKey:
                      const ValueKey('all_songs_search_clear_button'),
                  onClear: () {
                    _allSongsSearchController.clear();
                    localProvider.setLocalSearchQuery('');
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          MographSpringTap(
            pressedScale: 0.88,
            child: Tooltip(
              message: AppStrings.filterFavoritesTooltip,
              child: Material(
                color: localProvider.filterFavoritesOnly
                    ? palette.favoriteActive.withValues(alpha: 0.14)
                    : palette.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('all_songs_favorites_filter_button'),
                  onTap: localProvider.toggleFilterFavoritesOnly,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: localProvider.filterFavoritesOnly
                            ? palette.favoriteActive.withValues(alpha: 0.65)
                            : Colors.transparent,
                        width: 0.9,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: MographStatePop(
                      stateKey: localProvider.filterFavoritesOnly,
                      scaleBoost: 0.22,
                      child: Icon(
                        localProvider.filterFavoritesOnly
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 19,
                        color: localProvider.filterFavoritesOnly
                            ? palette.favoriteActive
                            : palette.nowPlayingSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistSongsSearchBar() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
      child: SizedBox(
        height: 44,
        child: TextField(
          key: const ValueKey('playlist_songs_search_field'),
          controller: _playlistSongsSearchController,
          style: TextStyle(
            color: palette.nowPlayingPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
          onChanged: (value) {
            setState(() => _playlistSongsSearchQuery = value);
          },
          decoration: _monochromeSearchInputDecoration(
            context,
            hintText: AppStrings.playlistSongsSearchHint(context),
            showClearButton: _playlistSongsSearchQuery.isNotEmpty,
            clearButtonKey:
                const ValueKey('playlist_songs_search_clear_button'),
            onClear: () {
              _playlistSongsSearchController.clear();
              setState(() => _playlistSongsSearchQuery = '');
            },
          ),
        ),
      ),
    );
  }

  void _togglePlaylistSelection(String playlistId) {
    // Only user-created playlists (`Your playlists`) may be selected in Merge Mode!
    if (SmartPlaylistId.isSmartId(playlistId)) return;
    setState(() {
      if (_selectedPlaylistIds.contains(playlistId)) {
        _selectedPlaylistIds.remove(playlistId);
        if (_selectedPlaylistIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedPlaylistIds.add(playlistId);
        _isSelectionMode = true;
      }
    });
  }

  void _exitSelectionMode() {
    if (!_isSelectionMode && _selectedPlaylistIds.isEmpty) return;
    setState(() {
      _isSelectionMode = false;
      _selectedPlaylistIds.clear();
    });
  }

  int _countUniqueSongsForPlaylists(
    LocalMusicProvider localProvider,
    Iterable<String> playlistIds,
  ) {
    final seen = <String>{};
    for (final id in playlistIds) {
      for (final s in localProvider.songsForPlaylistId(id)) {
        seen.add(s.filePath);
      }
    }
    return seen.length;
  }

  Widget _buildSmartCardIcon(String smartId, MusEveePalette palette) {
    switch (smartId) {
      case SmartPlaylistId.favorites:
        return Image.asset(
          'assets/heart.png',
          width: 20,
          height: 20,
          fit: BoxFit.contain,
        );
      case SmartPlaylistId.recentlyAdded:
        return Icon(
          Icons.more_time_rounded,
          color: palette.nowPlayingPrimary,
          size: 21,
        );
      case SmartPlaylistId.recentlyPlayed:
        return Image.asset(
          'assets/recently.png',
          width: 20,
          height: 20,
          fit: BoxFit.contain,
          color: palette.nowPlayingPrimary,
          colorBlendMode: BlendMode.srcIn,
        );
      case SmartPlaylistId.mostPlayed:
        return Image.asset(
          'assets/fire.png',
          width: 20,
          height: 20,
          fit: BoxFit.contain,
          color: palette.nowPlayingPrimary,
          colorBlendMode: BlendMode.srcIn,
        );
      case SmartPlaylistId.notPlayed:
        return Image.asset(
          'assets/not-allowed.png',
          width: 20,
          height: 20,
          fit: BoxFit.contain,
          color: palette.nowPlayingPrimary,
          colorBlendMode: BlendMode.srcIn,
        );
      default:
        return Icon(
          Icons.queue_music_rounded,
          color: palette.nowPlayingPrimary,
          size: 20,
        );
    }
  }

  static String _smartPlaylistEmptyHint(String smartId) =>
      AppStrings.smartPlaylistEmptyHint(smartId);

  Future<void> _executeSmartPlaylistAction(
    LocalMusicProvider localProvider,
    String smartId,
    String title,
    String value,
  ) async {
    if (value == 'play') {
      localProvider.playPlaylist(smartId);
      widget.onOpenNowPlaying();
    } else if (value == 'shuffle') {
      localProvider.playPlaylist(smartId, shuffle: true);
      widget.onOpenNowPlaying();
    } else if (value == 'add_queue') {
      final added = await localProvider.playCombinedPlaylists(
        [smartId],
        appendToCurrentQueue: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              added > 0
                  ? AppStrings.tr(
                      '$added lagu dari "$title" ditambahkan ke antrean.',
                      '$added songs from "$title" added to queue.',
                      context,
                    )
                  : AppStrings.tr(
                      'Semua lagu dari "$title" sudah ada di antrean.',
                      'All songs from "$title" are already in queue.',
                      context,
                    ),
            ),
          ),
        );
      }
    }
  }

  List<PopupMenuEntry<String>> _buildSmartPlaylistMenuItems(
    MusEveePalette palette,
  ) =>
      [
        PopupMenuItem(
          value: 'play',
          child: Text(
            AppStrings.tr('Putar Semua', 'Play All', context),
            style: TextStyle(color: palette.textPrimary, fontSize: 13),
          ),
        ),
        PopupMenuItem(
          value: 'shuffle',
          child: Text(
            AppStrings.tr(
              'Acak Playlist (Shuffle)',
              'Shuffle Playlist',
              context,
            ),
            style: TextStyle(color: palette.textPrimary, fontSize: 13),
          ),
        ),
        PopupMenuItem(
          value: 'add_queue',
          child: Text(
            AppStrings.tr(
              'Tambahkan ke Antrean Saat Ini (+ Queue)',
              'Add to Current Queue (+ Queue)',
              context,
            ),
            style: TextStyle(color: palette.textPrimary, fontSize: 13),
          ),
        ),
      ];

  Future<void> _showSmartCardLongPressMenu(
    BuildContext cardContext,
    LocalMusicProvider localProvider,
    String smartId,
    String title,
  ) async {
    final overlay =
        Overlay.of(cardContext).context.findRenderObject() as RenderBox?;
    final box = cardContext.findRenderObject() as RenderBox?;
    if (overlay == null || box == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final palette = cardContext.palette;
    final selected = await showMenu<String>(
      context: cardContext,
      position: position,
      color: palette.surfaceCard,
      items: _buildSmartPlaylistMenuItems(palette),
    );
    if (selected != null && mounted) {
      await _executeSmartPlaylistAction(
          localProvider, smartId, title, selected);
    }
  }

  Future<void> _promptRename(
    LocalMusicProvider provider,
    LocalPlaylist playlist,
  ) async {
    final name = await showPlaylistNameDialog(
      context,
      title: AppStrings.tr('Ganti Nama Playlist', 'Rename Playlist', context),
      initialValue: playlist.name,
      confirmLabel: AppStrings.tr('Simpan', 'Save', context),
    );
    if (name != null) await provider.renamePlaylist(playlist.id, name);
  }

  Future<void> _promptDelete(
    LocalMusicProvider provider,
    LocalPlaylist playlist,
  ) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.nowPlayingBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.hairline, width: 0.8),
        ),
        title: Text(
          AppStrings.tr('Hapus Playlist?', 'Delete Playlist?', context),
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          AppStrings.tr(
            'Playlist "${playlist.name}" akan dihapus. File lagu di HP tetap aman.',
            'Playlist "${playlist.name}" will be deleted. Audio files on your device stay safe.',
            context,
          ),
          style: TextStyle(color: palette.nowPlayingSecondary, fontSize: 13),
        ),
        actions: [
          MographSpringTap(
            pressedScale: 0.92,
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                AppStrings.tr('Batal', 'Cancel', context),
                style: TextStyle(color: palette.nowPlayingSecondary),
              ),
            ),
          ),
          MographSpringTap(
            pressedScale: 0.92,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: MusEveePalette.error,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(AppStrings.tr('Hapus', 'Delete', context)),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (_openedPlaylistId == playlist.id && mounted) {
        _closeOpenedPlaylist(provider);
      }
      _selectedPlaylistIds.remove(playlist.id);
      await provider.deletePlaylist(playlist.id);
    }
  }

  Widget _buildOpenedPlaylistView({
    required BuildContext context,
    required String playlistId,
    required String title,
    required bool isAllSongsSmart,
    required List<LocalSong> baseSongs,
    required LocalMusicProvider localProvider,
    required DownloaderProvider downloaderProvider,
    required String emptyMessage,
    Future<void> Function(LocalSong song)? onRemoveFromPlaylist,
  }) {
    final palette = context.palette;
    final hairline = palette.hairline;

    final q =
        isAllSongsSmart ? '' : _playlistSongsSearchQuery.trim().toLowerCase();
    final displayedSongs = (!_isPlaylistSongsSelectionMode && q.isNotEmpty)
        ? baseSongs.where((s) {
            return s.title.toLowerCase().contains(q) ||
                s.artist.toLowerCase().contains(q) ||
                s.album.toLowerCase().contains(q);
          }).toList()
        : baseSongs;

    final validPaths = <String>{for (final s in displayedSongs) s.filePath};
    _selectedPlaylistSongPaths.removeWhere((p) => !validPaths.contains(p));
    final selectedSongs = displayedSongs
        .where((s) => _selectedPlaylistSongPaths.contains(s.filePath))
        .toList();

    final hasAllSongsFilter = isAllSongsSmart &&
        (localProvider.localSearchQuery.trim().isNotEmpty ||
            localProvider.filterFavoritesOnly);

    return Container(
      key: ValueKey('opened_playlist_view_$playlistId'),
      color: palette.nowPlayingBg,
      child: Stack(
        children: [
          Column(
            children: [
              // Clean Monochrome Header matching Opened Folder View
              Container(
                padding: statusBarHeaderPadding(context, left: 8),
                decoration: cleanMonochromeHeaderDecoration(context),
                child: Row(
                  children: [
                    MographAnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      rotationTurns: -0.18,
                      child: _isPlaylistSongsSelectionMode
                          ? Padding(
                              key:
                                  const ValueKey('opened_playlist_select_icon'),
                              padding: const EdgeInsets.only(left: 8, right: 8),
                              child: Icon(
                                Icons.library_add_check_rounded,
                                color: palette.textPrimary,
                                size: 19,
                              ),
                            )
                          : Row(
                              key: const ValueKey('opened_playlist_back_wrap'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                MographSpringTap(
                                  pressedScale: 0.80,
                                  tapOffsetKick: const Offset(-3.5, 0.0),
                                  child: IconButton(
                                    key: const ValueKey(
                                      'opened_playlist_back_button',
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        _closeOpenedPlaylist(localProvider),
                                    icon: Icon(
                                      Icons.arrow_back_rounded,
                                      color: palette.textPrimary,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                            ),
                    ),
                    Expanded(
                      child: Text(
                        _isPlaylistSongsSelectionMode
                            ? '${selectedSongs.length} ${AppStrings.tr('Lagu Dipilih', 'Selected', context)}'
                            : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (_isPlaylistSongsSelectionMode) ...[
                      if (displayedSongs.length > 1)
                        MographSpringTap(
                          pressedScale: 0.90,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: palette.textPrimary,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                final allSelected = displayedSongs.every(
                                  (s) => _selectedPlaylistSongPaths
                                      .contains(s.filePath),
                                );
                                if (allSelected) {
                                  _selectedPlaylistSongPaths.clear();
                                } else {
                                  _selectedPlaylistSongPaths.addAll(
                                    displayedSongs.map((s) => s.filePath),
                                  );
                                }
                              });
                            },
                            child: Text(
                              displayedSongs.every(
                                (s) => _selectedPlaylistSongPaths
                                    .contains(s.filePath),
                              )
                                  ? 'Reset'
                                  : AppStrings.tr('Semua', 'All', context),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      MographSpringTap(
                        pressedScale: 0.80,
                        tapRotationRad: 0.24,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: AppStrings.tr(
                            'Batal Pilih',
                            'Cancel selection',
                            context,
                          ),
                          onPressed: _exitPlaylistSongsSelectionMode,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 19,
                            color: palette.nowPlayingSecondary,
                          ),
                        ),
                      ),
                    ] else if (displayedSongs.isNotEmpty) ...[
                      MographSpringTap(
                        pressedScale: 0.82,
                        tapOffsetKick: const Offset(0.0, -2.5),
                        child: IconButton(
                          key: const ValueKey(
                              'opened_playlist_add_queue_button'),
                          visualDensity: VisualDensity.compact,
                          tooltip: AppStrings.tr(
                            'Tambahkan Semua ke Antrean',
                            'Add All to Queue',
                            context,
                          ),
                          onPressed: () async {
                            final added = hasAllSongsFilter
                                ? await localProvider.playCombinedSongs(
                                    displayedSongs,
                                    appendToCurrentQueue: true,
                                  )
                                : await localProvider.playCombinedPlaylists(
                                    [playlistId],
                                    appendToCurrentQueue: true,
                                  );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    added > 0
                                        ? AppStrings.tr(
                                            '$added lagu dari "$title" ditambahkan ke akhir antrean.',
                                            '$added songs from "$title" added to queue.',
                                            context,
                                          )
                                        : AppStrings.tr(
                                            'Semua lagu dari "$title" sudah ada di antrean.',
                                            'All songs from "$title" are already in queue.',
                                            context,
                                          ),
                                  ),
                                ),
                              );
                            }
                          },
                          icon: Icon(
                            Icons.playlist_add_rounded,
                            color: palette.textPrimary,
                            size: 21,
                          ),
                        ),
                      ),
                      MographSpringTap(
                        pressedScale: 0.82,
                        tapRotationRad: 0.22,
                        child: IconButton(
                          key: const ValueKey('opened_playlist_shuffle_button'),
                          visualDensity: VisualDensity.compact,
                          tooltip: AppStrings.tr(
                            'Acak Semua',
                            'Shuffle All',
                            context,
                          ),
                          onPressed: () {
                            if (hasAllSongsFilter) {
                              localProvider.playSong(
                                displayedSongs.first,
                                queueContext: displayedSongs,
                              );
                              if (!localProvider.isShuffle) {
                                localProvider.toggleShuffle();
                              }
                            } else {
                              localProvider.playPlaylist(
                                playlistId,
                                shuffle: true,
                              );
                            }
                            widget.onOpenNowPlaying();
                          },
                          icon: Image.asset(
                            'assets/icons/arrow.png',
                            width: 19,
                            height: 19,
                            fit: BoxFit.contain,
                            color: palette.textPrimary,
                            colorBlendMode: BlendMode.srcIn,
                          ),
                        ),
                      ),
                      MographSpringTap(
                        pressedScale: 0.82,
                        tapOffsetKick: const Offset(3.0, 0.0),
                        child: IconButton(
                          key:
                              const ValueKey('opened_playlist_play_all_button'),
                          visualDensity: VisualDensity.compact,
                          tooltip: AppStrings.tr(
                            'Putar Semua',
                            'Play All',
                            context,
                          ),
                          onPressed: () {
                            if (hasAllSongsFilter) {
                              localProvider.playSong(
                                displayedSongs.first,
                                queueContext: displayedSongs,
                              );
                            } else {
                              localProvider.playPlaylist(playlistId);
                            }
                            widget.onOpenNowPlaying();
                          },
                          icon: Icon(
                            Icons.play_arrow_rounded,
                            color: palette.textPrimary,
                            size: 26,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Inline Search Bar inside Opened Playlist
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: _isPlaylistSongsSelectionMode
                    ? const SizedBox.shrink()
                    : (isAllSongsSmart
                        ? _buildAllSongsSearchBar(localProvider)
                        : _buildPlaylistSongsSearchBar()),
              ),

              Expanded(
                child: displayedSongs.isEmpty
                    ? _EmptyLocalHint(
                        icon: (q.isNotEmpty || hasAllSongsFilter)
                            ? Icons.search_off_rounded
                            : Icons.music_off_rounded,
                        message: q.isNotEmpty
                            ? AppStrings.localSearchNoMatch
                            : emptyMessage,
                      )
                    : ListView.separated(
                        key: ValueKey('opened_playlist_songs_list_$playlistId'),
                        padding: EdgeInsets.fromLTRB(
                          0,
                          6,
                          0,
                          _isPlaylistSongsSelectionMode ? 108 : 88,
                        ),
                        itemCount: displayedSongs.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          thickness: 0.7,
                          indent: 18,
                          endIndent: 18,
                          color: hairline,
                        ),
                        itemBuilder: (context, idx) {
                          final song = displayedSongs[idx];
                          final isSelected = _selectedPlaylistSongPaths
                              .contains(song.filePath);
                          return _MographSelectionCard(
                            isSelected: isSelected,
                            isSelectionMode: _isPlaylistSongsSelectionMode,
                            child: _LocalSongTile(
                              song: song,
                              queueContext: displayedSongs,
                              localProvider: localProvider,
                              downloaderProvider: downloaderProvider,
                              onMoveLocalSongFolder:
                                  widget.onMoveLocalSongFolder,
                              onOpenNowPlaying: widget.onOpenNowPlaying,
                              onRemoveFromPlaylist: onRemoveFromPlaylist,
                              cleanMonochromeStyle: true,
                              minimalFolderSongStyle: true,
                              isSelectionMode: _isPlaylistSongsSelectionMode,
                              isSelected: isSelected,
                              onTapOverride: _isPlaylistSongsSelectionMode
                                  ? () => _togglePlaylistSongSelection(
                                        song.filePath,
                                      )
                                  : null,
                              onLongPress: () => _togglePlaylistSongSelection(
                                song.filePath,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          if (displayedSongs.isNotEmpty)
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: _MorphingMergeActionBar(
                fabKey: const ValueKey('playlist_songs_merge_fab'),
                isExpanded: _isPlaylistSongsSelectionMode,
                idleTooltip: AppStrings.tr(
                  'Pilih Banyak Lagu',
                  'Select Multiple Songs',
                  context,
                ),
                label: selectedSongs.isEmpty
                    ? AppStrings.selectSongsLabel(context)
                    : AppStrings.songsCountLabel(selectedSongs.length, context),
                hasSelection: selectedSongs.isNotEmpty,
                monochromeStyle: true,
                useCheckAssetIcon: true,
                onOpen: () =>
                    setState(() => _isPlaylistSongsSelectionMode = true),
                onCancel: _exitPlaylistSongsSelectionMode,
                onPlayCombined: () async {
                  if (selectedSongs.isEmpty) return;
                  final targets = List<LocalSong>.from(selectedSongs);
                  _exitPlaylistSongsSelectionMode();
                  await localProvider.playCombinedSongs(
                    targets,
                    shuffle: false,
                  );
                  widget.onOpenNowPlaying();
                },
                onShuffleCombined: () async {
                  if (selectedSongs.isEmpty) return;
                  final targets = List<LocalSong>.from(selectedSongs);
                  _exitPlaylistSongsSelectionMode();
                  await localProvider.playCombinedSongs(
                    targets,
                    shuffle: true,
                  );
                  widget.onOpenNowPlaying();
                },
                onAppendQueue: () async {
                  if (selectedSongs.isEmpty) return;
                  final targets = List<LocalSong>.from(selectedSongs);
                  _exitPlaylistSongsSelectionMode();
                  final added = await localProvider.playCombinedSongs(
                    targets,
                    appendToCurrentQueue: true,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          added > 0
                              ? AppStrings.tr(
                                  '$added lagu terpilih ditambahkan ke akhir antrean.',
                                  '$added selected songs added to queue.',
                                  context,
                                )
                              : AppStrings.tr(
                                  'Semua lagu terpilih sudah ada di antrean.',
                                  'All selected songs are already in queue.',
                                  context,
                                ),
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemLocaleScope.watch(context);
    final palette = context.palette;
    final hairline = palette.hairline;

    return Consumer2<LocalMusicProvider, DownloaderProvider>(
      builder: (context, localProvider, downloaderProvider, _) {
        final playlists = localProvider.playlists;
        const horizontalSmartIds = <String>[
          SmartPlaylistId.favorites,
          SmartPlaylistId.recentlyAdded,
          SmartPlaylistId.recentlyPlayed,
          SmartPlaylistId.mostPlayed,
          SmartPlaylistId.notPlayed,
        ];

        // Multi-Select / Mix Playlist ONLY applies to `Your playlists` (user-created playlists)
        final validIds = <String>{
          ...playlists.map((p) => p.id),
        };
        _selectedPlaylistIds.removeWhere((id) => !validIds.contains(id));
        final selectedIds = _selectedPlaylistIds.toList();
        final selectedSongCount =
            _countUniqueSongsForPlaylists(localProvider, selectedIds);

        final openedId = _openedPlaylistId;
        final isOpenedSmart =
            openedId != null && SmartPlaylistId.isSmartId(openedId);
        final openedUserPlaylist = (openedId != null && !isOpenedSmart)
            ? localProvider.playlistById(openedId)
            : null;

        final Widget body;
        if (isOpenedSmart) {
          final isAllSongsSmart = openedId == SmartPlaylistId.allSongs;
          final smartTitle = AppStrings.smartPlaylistTitle(openedId, context);
          final songs = isAllSongsSmart
              ? localProvider.filteredLocalSongs
              : localProvider.songsForSmartPlaylist(openedId);
          body = KeyedSubtree(
            key: ValueKey('smart_pl_detail_$openedId'),
            child: _buildOpenedPlaylistView(
              context: context,
              playlistId: openedId,
              title: smartTitle,
              isAllSongsSmart: isAllSongsSmart,
              baseSongs: songs,
              localProvider: localProvider,
              downloaderProvider: downloaderProvider,
              emptyMessage: isAllSongsSmart
                  ? (localProvider.allSongs.isEmpty
                      ? AppStrings.localSearchEmptyLibrary
                      : AppStrings.localSearchNoMatch)
                  : _smartPlaylistEmptyHint(openedId),
            ),
          );
        } else if (openedUserPlaylist != null) {
          final songs = localProvider.songsForPlaylist(openedUserPlaylist);
          body = KeyedSubtree(
            key: ValueKey('pl_detail_${openedUserPlaylist.id}'),
            child: _buildOpenedPlaylistView(
              context: context,
              playlistId: openedUserPlaylist.id,
              title: openedUserPlaylist.name,
              isAllSongsSmart: false,
              baseSongs: songs,
              localProvider: localProvider,
              downloaderProvider: downloaderProvider,
              emptyMessage: AppStrings.tr(
                'Playlist masih kosong. Tambahkan lagu via menu ⋮ → "Tambah ke Playlist".',
                'Playlist is empty. Add songs via ⋮ menu → "Add to Playlist".',
                context,
              ),
              onRemoveFromPlaylist: (song) =>
                  localProvider.removeSongFromPlaylist(
                openedUserPlaylist.id,
                song.filePath,
              ),
            ),
          );
        } else {
          final allSongsList =
              localProvider.songsForSmartPlaylist(SmartPlaylistId.allSongs);
          final allSongsTitle =
              AppStrings.smartPlaylistTitle(SmartPlaylistId.allSongs, context);

          body = Container(
            key: const ValueKey('pl_list'),
            color: palette.nowPlayingBg,
            child: Stack(
              children: [
                Column(
                  children: [
                    // Redesigned Playlists Header (Clean Monochrome + Soft Shadow)
                    Container(
                      padding: statusBarHeaderPadding(context),
                      decoration: cleanMonochromeHeaderDecoration(context),
                      child: Row(
                        children: [
                          MographAnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            rotationTurns: -0.20,
                            child: _isSelectionMode
                                ? Icon(
                                    Icons.library_add_check_rounded,
                                    key: const ValueKey(
                                      'playlists_select_icon',
                                    ),
                                    color: palette.textPrimary,
                                    size: 19,
                                  )
                                : Image.asset(
                                    'assets/album.png',
                                    key: const ValueKey('playlists_root_icon'),
                                    width: 19,
                                    height: 19,
                                    fit: BoxFit.contain,
                                    color: palette.textPrimary,
                                    colorBlendMode: BlendMode.srcIn,
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isSelectionMode
                                  ? '${selectedIds.length} ${AppStrings.tr('Playlist Dipilih', 'Selected', context)} (${AppStrings.songsCountLabel(selectedSongCount, context)})'
                                  : AppStrings.tabPlaylistsTooltip,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          if (_isSelectionMode) ...[
                            if (validIds.length > 1)
                              MographSpringTap(
                                pressedScale: 0.90,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: palette.textPrimary,
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      if (_selectedPlaylistIds.length ==
                                          validIds.length) {
                                        _selectedPlaylistIds.clear();
                                      } else {
                                        _selectedPlaylistIds.addAll(validIds);
                                      }
                                    });
                                  },
                                  child: Text(
                                    _selectedPlaylistIds.length ==
                                            validIds.length
                                        ? 'Reset'
                                        : AppStrings.tr(
                                            'Semua', 'All', context),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            MographSpringTap(
                              pressedScale: 0.80,
                              tapRotationRad: 0.24,
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: AppStrings.tr(
                                  'Batal Pilih',
                                  'Cancel selection',
                                  context,
                                ),
                                onPressed: _exitSelectionMode,
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 19,
                                  color: palette.nowPlayingSecondary,
                                ),
                              ),
                            ),
                          ] else
                            MographSpringTap(
                              pressedScale: 0.84,
                              child: IconButton(
                                key: const ValueKey(
                                  'playlists_search_shortcut_button',
                                ),
                                visualDensity: VisualDensity.compact,
                                tooltip: AppStrings.localSearchShortcutTooltip,
                                onPressed: () {
                                  if (widget.onOpenAllSongsSearch != null) {
                                    widget.onOpenAllSongsSearch!();
                                  } else {
                                    _openAllSongsAndFocusSearch();
                                  }
                                },
                                icon: Image.asset(
                                  'assets/search.png',
                                  width: 19,
                                  height: 19,
                                  fit: BoxFit.contain,
                                  color: palette.textPrimary,
                                  colorBlendMode: BlendMode.srcIn,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          0,
                          10,
                          0,
                          _isSelectionMode ? 112 : 90,
                        ),
                        children: [
                          // ===================================================
                          // 1. ALL SONGS ROW + HORIZONTAL SMART PLAYLIST CARDS
                          //    (Non-selectable in Merge Mode)
                          // ===================================================
                          AnimatedOpacity(
                            opacity: _isSelectionMode ? 0.38 : 1.0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: IgnorePointer(
                              ignoring: _isSelectionMode,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  MographSpringTap(
                                    pressedScale: 0.985,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          setState(() {
                                            _shouldAutoFocusAllSongsSearch =
                                                false;
                                            _openedPlaylistId =
                                                SmartPlaylistId.allSongs;
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            20,
                                            10,
                                            8,
                                            10,
                                          ),
                                          child: Row(
                                            children: [
                                              Image.asset(
                                                'assets/vinyl.png',
                                                width: 28,
                                                height: 28,
                                                fit: BoxFit.contain,
                                                color:
                                                    palette.nowPlayingPrimary,
                                                colorBlendMode: BlendMode.srcIn,
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Text(
                                                  allSongsTitle,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: palette.textPrimary,
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '${allSongsList.length}',
                                                style: TextStyle(
                                                  color: palette
                                                      .nowPlayingSecondary,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                              PopupMenuButton<String>(
                                                icon: Icon(
                                                  Icons.more_vert_rounded,
                                                  size: 18,
                                                  color: palette.textPrimary,
                                                ),
                                                color: palette.surfaceCard,
                                                onSelected: (value) =>
                                                    _executeSmartPlaylistAction(
                                                  localProvider,
                                                  SmartPlaylistId.allSongs,
                                                  allSongsTitle,
                                                  value,
                                                ),
                                                itemBuilder: (_) =>
                                                    _buildSmartPlaylistMenuItems(
                                                  palette,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    thickness: 0.7,
                                    indent: 18,
                                    endIndent: 18,
                                    color: hairline,
                                  ),
                                  SizedBox(
                                    height: 126,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 14,
                                      ),
                                      itemCount: horizontalSmartIds.length,
                                      separatorBuilder: (context, index) =>
                                          const SizedBox(width: 10),
                                      itemBuilder: (context, idx) {
                                        final smartId = horizontalSmartIds[idx];
                                        final title =
                                            AppStrings.smartPlaylistTitle(
                                          smartId,
                                          context,
                                        );
                                        final songs = localProvider
                                            .songsForSmartPlaylist(smartId);

                                        return Builder(
                                          builder: (cardCtx) =>
                                              MographSpringTap(
                                            pressedScale: 0.94,
                                            child: Material(
                                              color: palette.surfaceSubtle,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              clipBehavior: Clip.antiAlias,
                                              child: InkWell(
                                                onTap: () {
                                                  setState(() {
                                                    _shouldAutoFocusAllSongsSearch =
                                                        false;
                                                    _openedPlaylistId = smartId;
                                                  });
                                                },
                                                onLongPress: () =>
                                                    _showSmartCardLongPressMenu(
                                                  cardCtx,
                                                  localProvider,
                                                  smartId,
                                                  title,
                                                ),
                                                child: SizedBox(
                                                  width: 86,
                                                  height: 98,
                                                  child: Padding(
                                                    padding: const EdgeInsets
                                                        .fromLTRB(
                                                      10,
                                                      12,
                                                      10,
                                                      8,
                                                    ),
                                                    child: Column(
                                                      children: [
                                                        Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          children: [
                                                            _buildSmartCardIcon(
                                                              smartId,
                                                              palette,
                                                            ),
                                                            Text(
                                                              '${songs.length}',
                                                              style: TextStyle(
                                                                color: palette
                                                                    .nowPlayingSecondary,
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w400,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const Spacer(),
                                                        Divider(
                                                          height: 10,
                                                          thickness: 0.7,
                                                          color: hairline,
                                                        ),
                                                        SizedBox(
                                                          height: 28,
                                                          child: Center(
                                                            child: Text(
                                                              title,
                                                              maxLines: 2,
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                color: palette
                                                                    .textPrimary,
                                                                fontSize: 11,
                                                                height: 1.15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    thickness: 0.7,
                                    indent: 18,
                                    endIndent: 18,
                                    color: hairline,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // ===================================================
                          // 2. YOUR PLAYLISTS + "+ NEW PLAYLIST" + 2-COL GRID
                          // ===================================================
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.yourPlaylists,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: MographSpringTap(
                                    pressedScale: 0.94,
                                    child: Material(
                                      color: palette.nowPlayingBg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(
                                          color: hairline,
                                          width: 0.9,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: () async {
                                          final name =
                                              await showPlaylistNameDialog(
                                            context,
                                            title: AppStrings.tr(
                                              'Playlist Baru',
                                              'New Playlist',
                                              context,
                                            ),
                                          );
                                          if (name != null) {
                                            await localProvider
                                                .createPlaylist(name);
                                          }
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 7,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Image.asset(
                                                'assets/add.png',
                                                width: 12,
                                                height: 12,
                                                fit: BoxFit.contain,
                                                color: palette.textPrimary,
                                                colorBlendMode: BlendMode.srcIn,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                AppStrings.newPlaylist,
                                                style: TextStyle(
                                                  color: palette.textPrimary,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (playlists.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    child: Text(
                                      AppStrings.noUserPlaylistsHint,
                                      style: TextStyle(
                                        color: palette.nowPlayingSecondary,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  )
                                else
                                  GridView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: playlists.length,
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      mainAxisExtent: 66,
                                    ),
                                    itemBuilder: (context, idx) {
                                      final playlist = playlists[idx];
                                      final resolved = localProvider
                                          .songsForPlaylist(playlist);
                                      final isSelected = _selectedPlaylistIds
                                          .contains(playlist.id);

                                      return _MographSelectionCard(
                                        isSelected: isSelected,
                                        isSelectionMode: _isSelectionMode,
                                        child: MographSpringTap(
                                          pressedScale: 0.96,
                                          child: Material(
                                            color: isSelected
                                                ? palette.nowPlayingPrimary
                                                    .withValues(
                                                    alpha: context.isDarkMode
                                                        ? 0.14
                                                        : 0.09,
                                                  )
                                                : palette.surfaceSubtle,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              side: BorderSide(
                                                color: isSelected
                                                    ? palette.nowPlayingPrimary
                                                        .withValues(alpha: 0.65)
                                                    : Colors.transparent,
                                                width: isSelected ? 1.1 : 0.0,
                                              ),
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: InkWell(
                                              onTap: () {
                                                if (_isSelectionMode) {
                                                  _togglePlaylistSelection(
                                                    playlist.id,
                                                  );
                                                } else {
                                                  setState(
                                                    () => _openedPlaylistId =
                                                        playlist.id,
                                                  );
                                                }
                                              },
                                              onLongPress: () =>
                                                  _togglePlaylistSelection(
                                                playlist.id,
                                              ),
                                              child: Padding(
                                                padding: EdgeInsets.fromLTRB(
                                                  8,
                                                  8,
                                                  _isSelectionMode ? 8 : 2,
                                                  8,
                                                ),
                                                child: Row(
                                                  children: [
                                                    _MographSelectCheckbox(
                                                      isVisible:
                                                          _isSelectionMode,
                                                      isSelected: isSelected,
                                                      monochromeStyle: true,
                                                    ),
                                                    _FolderCoverCollage(
                                                      songs: resolved,
                                                      size: 44,
                                                      customCoverPath: playlist
                                                          .customCoverPath,
                                                      emptyAssetPath:
                                                          'assets/album.png',
                                                      emptyBackgroundColor:
                                                          palette.nowPlayingBg
                                                              .withValues(
                                                        alpha: 0.78,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 9),
                                                    Expanded(
                                                      child: Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            playlist.name,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              color: palette
                                                                  .textPrimary,
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 1,
                                                          ),
                                                          Text(
                                                            AppStrings
                                                                .songsCountLabel(
                                                              resolved.length,
                                                              context,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              color: palette
                                                                  .nowPlayingSecondary,
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w400,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    if (!_isSelectionMode)
                                                      SizedBox(
                                                        width: 28,
                                                        height: 34,
                                                        child: PopupMenuButton<
                                                            String>(
                                                          padding:
                                                              EdgeInsets.zero,
                                                          iconSize: 17,
                                                          icon: Icon(
                                                            Icons
                                                                .more_vert_rounded,
                                                            size: 17,
                                                            color: palette
                                                                .textPrimary,
                                                          ),
                                                          color: palette
                                                              .surfaceCard,
                                                          onSelected:
                                                              (value) async {
                                                            if (value ==
                                                                'rename') {
                                                              await _promptRename(
                                                                localProvider,
                                                                playlist,
                                                              );
                                                            } else if (value ==
                                                                'shuffle') {
                                                              localProvider
                                                                  .playPlaylist(
                                                                playlist.id,
                                                                shuffle: true,
                                                              );
                                                              widget
                                                                  .onOpenNowPlaying();
                                                            } else if (value ==
                                                                'add_queue') {
                                                              final added =
                                                                  await localProvider
                                                                      .playCombinedPlaylists(
                                                                [playlist.id],
                                                                appendToCurrentQueue:
                                                                    true,
                                                              );
                                                              if (context
                                                                  .mounted) {
                                                                ScaffoldMessenger
                                                                    .of(
                                                                  context,
                                                                ).showSnackBar(
                                                                  SnackBar(
                                                                    content:
                                                                        Text(
                                                                      added > 0
                                                                          ? AppStrings
                                                                              .tr(
                                                                              '$added lagu dari "${playlist.name}" ditambahkan ke antrean.',
                                                                              '$added songs from "${playlist.name}" added to queue.',
                                                                              context,
                                                                            )
                                                                          : AppStrings
                                                                              .tr(
                                                                              'Semua lagu dari "${playlist.name}" sudah ada di antrean.',
                                                                              'All songs from "${playlist.name}" are already in queue.',
                                                                              context,
                                                                            ),
                                                                    ),
                                                                  ),
                                                                );
                                                              }
                                                            } else if (value ==
                                                                'multi_select') {
                                                              _togglePlaylistSelection(
                                                                playlist.id,
                                                              );
                                                            } else if (value ==
                                                                'delete') {
                                                              await _promptDelete(
                                                                localProvider,
                                                                playlist,
                                                              );
                                                            }
                                                          },
                                                          itemBuilder: (_) => [
                                                            PopupMenuItem(
                                                              value: 'shuffle',
                                                              child: Text(
                                                                AppStrings.tr(
                                                                  'Acak Playlist (Shuffle)',
                                                                  'Shuffle Playlist',
                                                                  context,
                                                                ),
                                                                style:
                                                                    TextStyle(
                                                                  color: palette
                                                                      .textPrimary,
                                                                  fontSize: 13,
                                                                ),
                                                              ),
                                                            ),
                                                            PopupMenuItem(
                                                              value:
                                                                  'add_queue',
                                                              child: Text(
                                                                AppStrings.tr(
                                                                  'Tambahkan ke Antrean Saat Ini (+ Queue)',
                                                                  'Add to Current Queue (+ Queue)',
                                                                  context,
                                                                ),
                                                                style:
                                                                    TextStyle(
                                                                  color: palette
                                                                      .textPrimary,
                                                                  fontSize: 13,
                                                                ),
                                                              ),
                                                            ),
                                                            PopupMenuItem(
                                                              value:
                                                                  'multi_select',
                                                              child: Text(
                                                                AppStrings.tr(
                                                                  'Pilih untuk Digabung (Multi-Playlist)',
                                                                  'Select to Merge (Multi-Playlist)',
                                                                  context,
                                                                ),
                                                                style:
                                                                    TextStyle(
                                                                  color: palette
                                                                      .textPrimary,
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ),
                                                            PopupMenuItem(
                                                              value: 'rename',
                                                              child: Text(
                                                                AppStrings.tr(
                                                                  'Ganti Nama',
                                                                  'Rename',
                                                                  context,
                                                                ),
                                                                style:
                                                                    TextStyle(
                                                                  color: palette
                                                                      .textPrimary,
                                                                  fontSize: 13,
                                                                ),
                                                              ),
                                                            ),
                                                            PopupMenuItem(
                                                              value: 'delete',
                                                              child: Text(
                                                                AppStrings.tr(
                                                                  'Hapus Playlist',
                                                                  'Delete Playlist',
                                                                  context,
                                                                ),
                                                                style:
                                                                    const TextStyle(
                                                                  color:
                                                                      MusEveePalette
                                                                          .error,
                                                                  fontSize: 13,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: _MorphingMergeActionBar(
                    fabKey: const ValueKey('playlists_merge_fab'),
                    isExpanded: _isSelectionMode,
                    idleTooltip: AppStrings.tr(
                      'Gabung / Pilih Banyak Playlist',
                      'Merge / Select Multiple Playlists',
                      context,
                    ),
                    label: selectedIds.isEmpty
                        ? AppStrings.selectPlaylistsLabel(context)
                        : '${selectedIds.length} Playlist • ${AppStrings.songsCountLabel(selectedSongCount, context)}',
                    hasSelection: selectedIds.isNotEmpty,
                    monochromeStyle: true,
                    useCheckAssetIcon: true,
                    onOpen: () => setState(() => _isSelectionMode = true),
                    onCancel: _exitSelectionMode,
                    onPlayCombined: () async {
                      if (selectedIds.isEmpty) return;
                      final targets = List<String>.from(selectedIds);
                      _exitSelectionMode();
                      await localProvider.playCombinedPlaylists(
                        targets,
                        shuffle: false,
                      );
                      widget.onOpenNowPlaying();
                    },
                    onShuffleCombined: () async {
                      if (selectedIds.isEmpty) return;
                      final targets = List<String>.from(selectedIds);
                      _exitSelectionMode();
                      await localProvider.playCombinedPlaylists(
                        targets,
                        shuffle: true,
                      );
                      widget.onOpenNowPlaying();
                    },
                    onAppendQueue: () async {
                      if (selectedIds.isEmpty) return;
                      final targets = List<String>.from(selectedIds);
                      _exitSelectionMode();
                      final added = await localProvider.playCombinedPlaylists(
                        targets,
                        appendToCurrentQueue: true,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              added > 0
                                  ? AppStrings.tr(
                                      '$added lagu dari ${targets.length} playlist ditambahkan ke akhir antrean.',
                                      '$added songs from ${targets.length} playlists added to end of queue.',
                                      context,
                                    )
                                  : AppStrings.tr(
                                      'Semua lagu dari playlist terpilih sudah ada di antrean.',
                                      'All songs from selected playlists are already in queue.',
                                      context,
                                    ),
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        }

        return MographAnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          reverseDuration: const Duration(milliseconds: 160),
          beginScale: 0.98,
          child: body,
        );
      },
    );
  }
}

/// Shared text-input dialog for creating / renaming playlists.
Future<String?> showPlaylistNameDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String? confirmLabel,
}) async {
  final controller = TextEditingController(text: initialValue);
  final palette = context.palette;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.nowPlayingBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.hairline, width: 0.8),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(color: palette.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: AppStrings.tr('Nama playlist', 'Playlist name', context),
          hintStyle: TextStyle(color: palette.nowPlayingSecondary),
          filled: true,
          fillColor: palette.surfaceSubtle,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        MographSpringTap(
          pressedScale: 0.92,
          child: TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              AppStrings.tr('Batal', 'Cancel', context),
              style: TextStyle(color: palette.nowPlayingSecondary),
            ),
          ),
        ),
        MographSpringTap(
          pressedScale: 0.92,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.nowPlayingPrimary,
              foregroundColor: palette.nowPlayingOnPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(confirmLabel ?? AppStrings.tr('Buat', 'Create', ctx)),
          ),
        ),
      ],
    ),
  );
  final trimmed = result?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// Bottom sheet listing all playlists (+ "Playlist Baru") to add [song] into.
Future<void> showAddToPlaylistSheet(
  BuildContext context, {
  required LocalMusicProvider localProvider,
  required LocalSong song,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final selected = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: context.palette.nowPlayingBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      final playlists = localProvider.playlists;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Text(
                  AppStrings.tr(
                    'Tambah "${song.title}" ke Playlist',
                    'Add "${song.title}" to Playlist',
                    ctx,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.playlist_add_rounded,
                    color: ctx.palette.nowPlayingPrimary),
                title: Text(
                  AppStrings.tr('Playlist Baru…', 'New Playlist…', ctx),
                  style: TextStyle(
                      color: ctx.palette.nowPlayingPrimary,
                      fontWeight: FontWeight.w600),
                ),
                onTap: () => Navigator.of(ctx).pop('__new__'),
              ),
              Divider(height: 1, color: context.palette.hairline),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in playlists)
                      ListTile(
                        leading: Icon(
                          p.songPaths.contains(song.filePath)
                              ? Icons.check_circle_rounded
                              : Icons.queue_music_rounded,
                          color: p.songPaths.contains(song.filePath)
                              ? MusEveePalette.emerald
                              : context.palette.textMuted,
                        ),
                        title: Text(
                          p.name,
                          style: TextStyle(
                              color: context.palette.textPrimary, fontSize: 14),
                        ),
                        subtitle: Text(
                          AppStrings.songsCountLabel(p.songCount, ctx),
                          style: TextStyle(
                              color: context.palette.textMuted, fontSize: 11.5),
                        ),
                        onTap: () => Navigator.of(ctx).pop(p.id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (selected == null) return;

  String? targetId = selected;
  String targetName = '';
  if (selected == '__new__') {
    if (!context.mounted) return;
    final name = await showPlaylistNameDialog(
      context,
      title: AppStrings.tr('Playlist Baru', 'New Playlist', context),
    );
    if (name == null) return;
    final created = await localProvider.createPlaylist(name);
    targetId = created.id;
    targetName = created.name;
  } else {
    targetName = localProvider.playlistById(selected)?.name ?? '';
  }

  final added = await localProvider.addSongToPlaylist(targetId, song.filePath);
  final bool useId;
  if (context.mounted) {
    useId = AppStrings.isIndonesianInContext(context);
  } else {
    useId = AppStrings.isIndonesian;
  }
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        added
            ? (useId
                ? 'Ditambahkan ke playlist "$targetName".'
                : 'Added to playlist "$targetName".')
            : (useId
                ? 'Lagu sudah ada di playlist "$targetName".'
                : 'Song is already in playlist "$targetName".'),
      ),
    ),
  );
}

// =============================================================================
// SHARED SONG TILE & COLLAGE WIDGETS
// =============================================================================
class _LocalSongTile extends StatelessWidget {
  final LocalSong song;
  final List<LocalSong> queueContext;
  final LocalMusicProvider localProvider;
  final DownloaderProvider downloaderProvider;
  final Future<void> Function(LocalSong song) onMoveLocalSongFolder;
  final VoidCallback onOpenNowPlaying;
  final Future<void> Function(LocalSong song)? onRemoveFromPlaylist;
  final bool cleanMonochromeStyle;
  final bool minimalFolderSongStyle;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onTapOverride;
  final VoidCallback? onLongPress;

  const _LocalSongTile({
    required this.song,
    required this.queueContext,
    required this.localProvider,
    required this.downloaderProvider,
    required this.onMoveLocalSongFolder,
    required this.onOpenNowPlaying,
    this.onRemoveFromPlaylist,
    this.cleanMonochromeStyle = false,
    this.minimalFolderSongStyle = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onTapOverride,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isCurrent = localProvider.currentSong?.filePath == song.filePath;
    final hairline = palette.hairline;

    final Widget tileCard = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: cleanMonochromeStyle
          ? BoxDecoration(
              color: isSelected
                  ? palette.nowPlayingPrimary.withValues(
                      alpha: context.isDarkMode ? 0.12 : 0.08,
                    )
                  : isCurrent
                      ? palette.nowPlayingPrimary.withValues(
                          alpha: context.isDarkMode ? 0.08 : 0.05,
                        )
                      : Colors.transparent,
            )
          : ShapeDecoration(
              color: isSelected
                  ? palette.nowPlayingPrimary.withValues(
                      alpha: context.isDarkMode ? 0.12 : 0.08,
                    )
                  : isCurrent
                      ? palette.nowPlayingPrimary.withValues(
                          alpha: context.isDarkMode ? 0.08 : 0.05,
                        )
                      : palette.surfaceCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: isCurrent
                      ? palette.nowPlayingPrimary.withValues(
                          alpha: context.isDarkMode ? 0.28 : 0.22,
                        )
                      : hairline,
                  width: 0.8,
                ),
              ),
            ),
      clipBehavior: cleanMonochromeStyle ? Clip.none : Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTapOverride ??
              () {
                localProvider.playSong(song, queueContext: queueContext);
                onOpenNowPlaying();
              },
          onLongPress: onLongPress,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: cleanMonochromeStyle ? 20 : 10,
              vertical: cleanMonochromeStyle ? 10 : 8,
            ),
            child: Row(
              children: [
                if (minimalFolderSongStyle)
                  _MographSelectCheckbox(
                    isVisible: isSelectionMode,
                    isSelected: isSelected,
                    monochromeStyle: true,
                  ),
                _LocalCoverThumb(
                  coverPath: song.coverFilePath,
                  size: 46,
                  borderRadius: cleanMonochromeStyle ? 8 : 5,
                ),
                SizedBox(width: cleanMonochromeStyle ? 12 : 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isCurrent && !minimalFolderSongStyle) ...[
                            AnimatedEqualizerIcon(
                              isPlaying: localProvider.isPlaying,
                              size: 15,
                              color: palette.nowPlayingPrimary,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cleanMonochromeStyle
                                    ? (isCurrent
                                        ? palette.nowPlayingPrimary
                                        : palette.textPrimary)
                                    : palette.textPrimary,
                                fontSize: 13.5,
                                fontWeight: cleanMonochromeStyle
                                    ? (isCurrent
                                        ? FontWeight.w600
                                        : FontWeight.w500)
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        minimalFolderSongStyle
                            ? '${song.artist} • ${song.formattedDuration}'
                            : '${song.artist} • ${song.folderName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cleanMonochromeStyle
                              ? palette.nowPlayingSecondary
                              : palette.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                      if (!minimalFolderSongStyle && song.hasLyrics) ...[
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: MusEveePalette.emerald,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              song.hasSyncedLyrics
                                  ? AppStrings.tr(
                                      'LRC Berjalan',
                                      'Synced LRC',
                                      context,
                                    )
                                  : AppStrings.tr(
                                      'Lirik Tertanam',
                                      'Embedded Lyrics',
                                      context,
                                    ),
                              style: const TextStyle(
                                color: MusEveePalette.emerald,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (minimalFolderSongStyle)
                  MographAnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    beginScale: 0.65,
                    child: isCurrent
                        ? Padding(
                            key: const ValueKey('song_tile_eq'),
                            padding: EdgeInsets.only(
                              left: 8,
                              right: isSelectionMode ? 0 : 4,
                            ),
                            child: AnimatedEqualizerIcon(
                              isPlaying: localProvider.isPlaying,
                              size: 17,
                              color: palette.nowPlayingPrimary,
                            ),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('song_tile_no_eq'),
                          ),
                  ),
                if (!minimalFolderSongStyle) ...[
                  const SizedBox(width: 6),
                  Text(
                    song.formattedDuration,
                    style: TextStyle(
                      color: cleanMonochromeStyle
                          ? palette.nowPlayingSecondary
                          : palette.textMuted,
                      fontSize: 11.5,
                      fontWeight: cleanMonochromeStyle
                          ? FontWeight.w400
                          : FontWeight.w600,
                    ),
                  ),
                ],
                if (!isSelectionMode)
                  MographSpringTap(
                    enabled: cleanMonochromeStyle,
                    pressedScale: 0.82,
                    tapRotationRad: 0.16,
                    child: PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: cleanMonochromeStyle ? 19 : 18,
                        color: minimalFolderSongStyle
                            ? palette.textPrimary
                            : palette.textMuted,
                      ),
                      color: palette.surfaceCard,
                      onSelected: (value) async {
                        if (value == 'play_next') {
                          localProvider.addToQueue(song, playNext: true);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppStrings.tr(
                                  'Diputar berikutnya: ${song.title}',
                                  'Playing next: ${song.title}',
                                  context,
                                ),
                              ),
                            ),
                          );
                        } else if (value == 'add_queue') {
                          localProvider.addToQueue(song);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppStrings.tr(
                                  'Ditambahkan ke antrean: ${song.title}',
                                  'Added to queue: ${song.title}',
                                  context,
                                ),
                              ),
                            ),
                          );
                        } else if (value == 'add_playlist') {
                          await showAddToPlaylistSheet(
                            context,
                            localProvider: localProvider,
                            song: song,
                          );
                        } else if (value == 'remove_playlist') {
                          await onRemoveFromPlaylist?.call(song);
                        } else if (value == 'edit_tag') {
                          TagEditorSheet.showForLocalSong(
                            context,
                            downloaderProvider: downloaderProvider,
                            localProvider: localProvider,
                            song: song,
                          );
                        } else if (value == 'move') {
                          await onMoveLocalSongFolder(song);
                        } else if (value == 'delete') {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: palette.nowPlayingBg,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: palette.hairline,
                                  width: 0.8,
                                ),
                              ),
                              title: Text(
                                AppStrings.tr(
                                  'Hapus File Lagu?',
                                  'Delete Song File?',
                                  ctx,
                                ),
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              content: Text(
                                AppStrings.tr(
                                  'Hapus permanen "${song.title}" dari folder ${song.folderName}?',
                                  'Permanently delete "${song.title}" from folder ${song.folderName}?',
                                  ctx,
                                ),
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                              actions: [
                                MographSpringTap(
                                  pressedScale: 0.90,
                                  child: TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: Text(
                                      AppStrings.tr('Batal', 'Cancel', ctx),
                                      style:
                                          TextStyle(color: palette.textMuted),
                                    ),
                                  ),
                                ),
                                MographSpringTap(
                                  pressedScale: 0.90,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: MusEveePalette.error,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: Text(
                                      AppStrings.tr('Hapus', 'Delete', ctx),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && context.mounted) {
                            final ok =
                                await localProvider.deleteLocalSong(song);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? AppStrings.tr(
                                            'File lagu berhasil dihapus.',
                                            'Song file deleted.',
                                            context,
                                          )
                                        : AppStrings.tr(
                                            'Penghapusan dibatalkan atau izin ditolak.',
                                            'Deletion cancelled or permission denied.',
                                            context,
                                          ),
                                  ),
                                ),
                              );
                            }
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'play_next',
                          child: Text(
                            AppStrings.tr(
                              'Putar Berikutnya',
                              'Play Next',
                              context,
                            ),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'add_queue',
                          child: Text(
                            AppStrings.tr(
                              'Tambah ke Antrean (=+)',
                              'Add to Queue (=+)',
                              context,
                            ),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'add_playlist',
                          child: Text(
                            AppStrings.tr(
                              'Tambah ke Playlist',
                              'Add to Playlist',
                              context,
                            ),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (onRemoveFromPlaylist != null)
                          PopupMenuItem(
                            value: 'remove_playlist',
                            child: Text(
                              AppStrings.tr(
                                'Keluarkan dari Playlist',
                                'Remove from Playlist',
                                context,
                              ),
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        PopupMenuItem(
                          value: 'edit_tag',
                          child: Text(
                            AppStrings.tr(
                              'Edit Tag & Auto-Romaji (✎)',
                              'Edit Tags & Auto-Romaji (✎)',
                              context,
                            ),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'move',
                          child: Text(
                            AppStrings.tr(
                              'Pindah Folder',
                              'Move Folder',
                              context,
                            ),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            AppStrings.tr('Hapus File', 'Delete File', context),
                            style: const TextStyle(
                              color: Color(0xFFF04438),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (cleanMonochromeStyle) {
      return MographSpringTap(
        pressedScale: 0.98,
        child: tileCard,
      );
    }
    return tileCard;
  }
}

class _LocalCoverThumb extends StatelessWidget {
  final String? coverPath;
  final double size;
  final double borderRadius;

  const _LocalCoverThumb({
    required this.coverPath,
    required this.size,
    this.borderRadius = 5,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final palette = context.palette;

    if (coverPath != null && coverPath!.isNotEmpty) {
      final targetCachePx = (size * 3).round().clamp(96, 256);
      return ClipRRect(
        borderRadius: radius,
        child: Image.file(
          File(coverPath!),
          width: size,
          height: size,
          cacheWidth: targetCachePx,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              _fallback(radius, palette),
        ),
      );
    }
    return _fallback(radius, palette);
  }

  Widget _fallback(BorderRadius radius, MusEveePalette palette) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.surfaceSubtle,
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        color: palette.textMuted,
        size: size * 0.42,
      ),
    );
  }
}

/// 2x2 album cover collage thumbnail for redesigned folder and playlist rows.
/// Collects up to 4 distinct album cover files from [songs] with adaptive
/// fallback for 0, 1, or 2-3 available covers.
class _FolderCoverCollage extends StatelessWidget {
  final List<LocalSong> songs;
  final double size;
  final String? customCoverPath;
  final String emptyAssetPath;
  final Color? emptyBackgroundColor;

  const _FolderCoverCollage({
    required this.songs,
    this.size = 48,
    this.customCoverPath,
    this.emptyAssetPath = 'assets/folder.png',
    this.emptyBackgroundColor,
  });

  List<String> _extractDistinctCoverPaths() {
    final custom = customCoverPath?.trim() ?? '';
    if (custom.isNotEmpty) return <String>[custom];

    final covers = <String>[];
    final seen = <String>{};
    for (final song in songs) {
      final path = song.coverFilePath?.trim() ?? '';
      if (path.isNotEmpty && seen.add(path)) {
        covers.add(path);
        if (covers.length == 4) break;
      }
    }
    return covers;
  }

  Widget _buildTile(String path, double tileSize, MusEveePalette palette) {
    final cachePx = (tileSize * 2.5).round().clamp(64, 192);
    return Image.file(
      File(path),
      width: tileSize,
      height: tileSize,
      cacheWidth: cachePx,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => Container(
        width: tileSize,
        height: tileSize,
        color: emptyBackgroundColor ?? palette.surfaceSubtle,
        alignment: Alignment.center,
        child: Icon(
          Icons.music_note_rounded,
          color: palette.nowPlayingSecondary,
          size: tileSize * 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = BorderRadius.circular(8);
    final covers = _extractDistinctCoverPaths();

    if (covers.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: emptyBackgroundColor ?? palette.surfaceSubtle,
          borderRadius: radius,
        ),
        alignment: Alignment.center,
        child: Image.asset(
          emptyAssetPath,
          width: size * 0.44,
          height: size * 0.44,
          fit: BoxFit.contain,
          color: palette.nowPlayingSecondary,
          colorBlendMode: BlendMode.srcIn,
        ),
      );
    }

    if (covers.length == 1) {
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: size,
          height: size,
          child: _buildTile(covers.first, size, palette),
        ),
      );
    }

    final quad = covers.length == 2
        ? <String>[covers[0], covers[1], covers[1], covers[0]]
        : covers.length == 3
            ? <String>[covers[0], covers[1], covers[2], covers[0]]
            : covers;
    final half = size * 0.5;

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            Row(
              children: [
                _buildTile(quad[0], half, palette),
                _buildTile(quad[1], half, palette),
              ],
            ),
            Row(
              children: [
                _buildTile(quad[2], half, palette),
                _buildTile(quad[3], half, palette),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLocalHint extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyLocalHint({
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: context.palette.textMuted),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mograph card wrapper that performs a subtle spring scale-bounce whenever
/// [isSelected] toggles during Merge Selection Mode.
class _MographSelectionCard extends StatefulWidget {
  final bool isSelected;
  final bool isSelectionMode;
  final Widget child;

  const _MographSelectionCard({
    required this.isSelected,
    required this.isSelectionMode,
    required this.child,
  });

  @override
  State<_MographSelectionCard> createState() => _MographSelectionCardState();
}

class _MographSelectionCardState extends State<_MographSelectionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void didUpdateWidget(covariant _MographSelectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      _bounceController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _bounceController,
        builder: (context, child) {
          final t = _bounceController.value;
          if (t == 0.0 || t == 1.0) {
            return child!;
          }
          // Spring impulse: quick dip to 0.965 then overshoot to 1.018 then settle at 1.0
          final wave = math.sin(t * math.pi * 2.0) * (1.0 - t);
          final scale = 1.0 - (wave * 0.032);
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Mograph checkbox indicator for Merge Selection Mode:
/// - Expands horizontally with `Curves.easeOutBack` when selection mode turns on.
/// - When checked (`isSelected == true`), pops in with Scale + Quarter-Turn Rotation (`-0.25 turns -> 0.0`).
class _MographSelectCheckbox extends StatelessWidget {
  final bool isVisible;
  final bool isSelected;
  final bool monochromeStyle;

  const _MographSelectCheckbox({
    required this.isVisible,
    required this.isSelected,
    this.monochromeStyle = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final uncheckedColor =
        monochromeStyle ? palette.nowPlayingSecondary : palette.textMuted;
    final checkedColor = palette.nowPlayingPrimary;

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      alignment: Alignment.centerLeft,
      child: !isVisible
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(right: 10),
              child: TweenAnimationBuilder<double>(
                key: ValueKey<bool>(isSelected),
                tween: Tween<double>(
                  begin: isSelected ? 0.0 : 1.0,
                  end: isSelected ? 1.0 : 0.0,
                ),
                duration: const Duration(milliseconds: 300),
                curve: isSelected ? Curves.easeOutBack : Curves.easeOutCubic,
                builder: (context, t, _) {
                  if (!isSelected && t < 0.05) {
                    return Icon(
                      Icons.radio_button_unchecked_rounded,
                      color: uncheckedColor,
                      size: 22,
                    );
                  }
                  final clamped = t.clamp(0.0, 1.0);
                  final scale = 0.55 + (t * 0.45);
                  final angle = (1.0 - clamped) * (-math.pi * 0.5);

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: (1.0 - clamped).clamp(0.0, 1.0),
                        child: Icon(
                          Icons.radio_button_unchecked_rounded,
                          color: uncheckedColor,
                          size: 22,
                        ),
                      ),
                      Transform.rotate(
                        angle: angle,
                        child: Transform.scale(
                          scale: scale.clamp(0.0, 1.35),
                          child: Opacity(
                            opacity: clamped,
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: checkedColor,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

/// Single continuous Mograph Liquid Shape-Morphing container:
/// - Idle (`isExpanded == false`): Icon-Only circle anchored at the bottom-right.
/// - Active (`isExpanded == true`): Morphs leftward into the full-width
///   Floating Action Bar (`Curves.easeOutBack`, `~380ms`), while its internal
///   controls (`▶ Putar`, `🔀 Shuffle`, `➕ Queue`, optional red Delete box, and `✕`)
///   pop in with Staggered Scale + Slide Pop-Up!
class _MorphingMergeActionBar extends StatefulWidget {
  final Key? fabKey;
  final bool isExpanded;
  final String idleTooltip;
  final String label;
  final bool hasSelection;
  final bool monochromeStyle;
  final bool useCheckAssetIcon;
  final VoidCallback onOpen;
  final VoidCallback onCancel;
  final VoidCallback onPlayCombined;
  final VoidCallback onShuffleCombined;
  final VoidCallback onAppendQueue;
  final VoidCallback? onDeleteSelected;

  const _MorphingMergeActionBar({
    this.fabKey,
    required this.isExpanded,
    required this.idleTooltip,
    required this.label,
    required this.hasSelection,
    this.monochromeStyle = true,
    this.useCheckAssetIcon = false,
    required this.onOpen,
    required this.onCancel,
    required this.onPlayCombined,
    required this.onShuffleCombined,
    required this.onAppendQueue,
    this.onDeleteSelected,
  });

  @override
  State<_MorphingMergeActionBar> createState() =>
      _MorphingMergeActionBarState();
}

class _MorphingMergeActionBarState extends State<_MorphingMergeActionBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double _idleSize = 56.0;
  static const double _monochromeIdleSize = 52.0;
  static const double _expandedHeight = 88.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 300),
      value: widget.isExpanded ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant _MorphingMergeActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _staggeredSpring(double rawT, double start, double end) {
    final normalized = ((rawT - start) / (end - start)).clamp(0.0, 1.0);
    if (normalized <= 0.0) return 0.0;
    return Curves.easeOutBack.transform(normalized);
  }

  Widget _buildStaggeredItem({
    required double rawT,
    required double start,
    required double end,
    required Widget child,
  }) {
    final linear = ((rawT - start) / (end - start)).clamp(0.0, 1.0);
    if (linear <= 0.01) {
      return const SizedBox.shrink();
    }
    final spring = _staggeredSpring(rawT, start, end);
    final slideY = (1.0 - spring) * 14.0;
    final scale = (0.65 + (spring * 0.35)).clamp(0.0, 1.25);

    return Opacity(
      opacity: linear,
      child: Transform.translate(
        offset: Offset(0.0, slideY),
        child: Transform.scale(
          scale: scale,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final idleSize = widget.monochromeStyle ? _monochromeIdleSize : _idleSize;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 24;

        return Align(
          alignment: Alignment.bottomRight,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final rawT = _controller.value;
                final shapeT = widget.isExpanded
                    ? Curves.easeOutBack.transform(rawT)
                    : Curves.easeInOutCubic.transform(rawT);

                final currentWidth =
                    (idleSize + ((maxWidth - idleSize) * shapeT))
                        .clamp(48.0, maxWidth);
                final currentHeight =
                    (idleSize + ((_expandedHeight - idleSize) * shapeT))
                        .clamp(48.0, 102.0);
                final idleRadius = idleSize * 0.5;
                final currentRadius =
                    (idleRadius + ((14.0 - idleRadius) * rawT))
                        .clamp(12.0, 32.0);

                final bgColor = widget.monochromeStyle
                    ? Color.lerp(
                        palette.nowPlayingPrimary,
                        palette.surfaceCard,
                        rawT,
                      )!
                    : Color.lerp(
                        palette.surfaceSubtle,
                        palette.surfaceCard,
                        rawT,
                      )!;
                final borderColor = widget.monochromeStyle
                    ? Color.lerp(
                        palette.nowPlayingPrimary,
                        palette.hairline,
                        rawT,
                      )!
                    : Color.lerp(
                        palette.nowPlayingPrimary.withValues(alpha: 0.50),
                        palette.hairline,
                        rawT,
                      )!;

                final showIdleIcon = rawT < 0.42;
                final showExpandedContent = rawT >= 0.22;

                final badgeBg = widget.monochromeStyle
                    ? palette.nowPlayingPrimary.withValues(alpha: 0.10)
                    : palette.nowPlayingPrimary.withValues(alpha: 0.18);
                final badgeFg = palette.nowPlayingPrimary;
                final playBg = palette.nowPlayingPrimary;
                final playFg = palette.nowPlayingOnPrimary;

                return Material(
                  color: bgColor,
                  elevation:
                      widget.monochromeStyle ? 4 + (rawT * 6) : 10 + (rawT * 4),
                  shadowColor: Colors.black.withValues(
                    alpha: context.isDarkMode ? 0.65 : 0.20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(currentRadius),
                    side: BorderSide(color: borderColor, width: 1.0),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: currentWidth,
                    height: currentHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 1. IDLE ICON-ONLY CIRCLE
                        if (showIdleIcon)
                          IgnorePointer(
                            ignoring: widget.isExpanded,
                            child: Tooltip(
                              message: widget.idleTooltip,
                              child: MographSpringTap(
                                pressedScale: 0.86,
                                child: InkWell(
                                  key: widget.fabKey ??
                                      (widget.useCheckAssetIcon
                                          ? const ValueKey('folders_merge_fab')
                                          : null),
                                  onTap: widget.onOpen,
                                  customBorder: const CircleBorder(),
                                  child: Center(
                                    child: Transform.rotate(
                                      angle: rawT * math.pi * 0.85,
                                      child: Transform.scale(
                                        scale: (1.0 - (rawT * 2.1)).clamp(
                                          0.0,
                                          1.0,
                                        ),
                                        child: widget.useCheckAssetIcon
                                            ? SizedBox(
                                                width: _monochromeIdleSize,
                                                height: _monochromeIdleSize,
                                                child: Stack(
                                                  alignment: Alignment.center,
                                                  children: [
                                                    Container(
                                                      width: 42,
                                                      height: 42,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: palette
                                                            .nowPlayingOnPrimary,
                                                      ),
                                                    ),
                                                    Image.asset(
                                                      'assets/check.png',
                                                      width:
                                                          _monochromeIdleSize,
                                                      height:
                                                          _monochromeIdleSize,
                                                      fit: BoxFit.contain,
                                                      color: palette
                                                          .nowPlayingPrimary,
                                                      colorBlendMode:
                                                          BlendMode.srcIn,
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : Icon(
                                                Icons.library_add_check_rounded,
                                                size: 26,
                                                color: widget.monochromeStyle
                                                    ? palette
                                                        .nowPlayingOnPrimary
                                                    : palette.nowPlayingPrimary,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // 2. MORPHED ACTION BAR WITH STAGGERED SCALE + SLIDE POP-UP BUTTONS
                        if (showExpandedContent)
                          IgnorePointer(
                            ignoring: !widget.isExpanded,
                            child: OverflowBox(
                              minWidth: maxWidth,
                              maxWidth: maxWidth,
                              minHeight: _expandedHeight,
                              maxHeight: _expandedHeight,
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  9,
                                  10,
                                  9,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildStaggeredItem(
                                      rawT: rawT,
                                      start: 0.22,
                                      end: 0.72,
                                      child: Row(
                                        children: [
                                          MographStatePop(
                                            stateKey: widget.label,
                                            scaleBoost: 0.14,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: badgeBg,
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                              ),
                                              child: Text(
                                                widget.label,
                                                style: TextStyle(
                                                  color: badgeFg,
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          MographSpringTap(
                                            pressedScale: 0.78,
                                            tapRotationRad: 0.24,
                                            child: InkWell(
                                              onTap: widget.onCancel,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(4),
                                                child: Transform.rotate(
                                                  angle: (1.0 - rawT) *
                                                      (-math.pi * 0.5),
                                                  child: Icon(
                                                    Icons.close_rounded,
                                                    size: 17,
                                                    color: palette.textMuted,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Opacity(
                                      opacity: widget.hasSelection ? 1.0 : 0.45,
                                      child: IgnorePointer(
                                        ignoring: !widget.hasSelection,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: _buildStaggeredItem(
                                                rawT: rawT,
                                                start: 0.34,
                                                end: 0.82,
                                                child: _ActionPillButton(
                                                  icon:
                                                      Icons.play_arrow_rounded,
                                                  label: AppStrings.tr(
                                                    'Putar',
                                                    'Play',
                                                    context,
                                                  ),
                                                  backgroundColor: playBg,
                                                  foregroundColor: playFg,
                                                  onTap: widget.onPlayCombined,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 7),
                                            Expanded(
                                              child: _buildStaggeredItem(
                                                rawT: rawT,
                                                start: 0.44,
                                                end: 0.91,
                                                child: _ActionPillButton(
                                                  icon: Icons.shuffle_rounded,
                                                  label: 'Shuffle',
                                                  backgroundColor:
                                                      palette.surfaceSubtle,
                                                  foregroundColor:
                                                      palette.textPrimary,
                                                  borderColor: palette.hairline,
                                                  onTap:
                                                      widget.onShuffleCombined,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 7),
                                            Expanded(
                                              child: _buildStaggeredItem(
                                                rawT: rawT,
                                                start: 0.54,
                                                end: 1.00,
                                                child: _ActionPillButton(
                                                  icon: Icons
                                                      .playlist_add_rounded,
                                                  label: 'Queue',
                                                  backgroundColor:
                                                      palette.surfaceSubtle,
                                                  foregroundColor:
                                                      palette.textPrimary,
                                                  borderColor: palette.hairline,
                                                  onTap: widget.onAppendQueue,
                                                ),
                                              ),
                                            ),
                                            if (widget.onDeleteSelected !=
                                                null) ...[
                                              const SizedBox(width: 7),
                                              _buildStaggeredItem(
                                                rawT: rawT,
                                                start: 0.58,
                                                end: 1.00,
                                                child: Tooltip(
                                                  message: AppStrings.tr(
                                                    'Hapus lagu terpilih',
                                                    'Delete selected songs',
                                                    context,
                                                  ),
                                                  child: PressableScale(
                                                    pressedScale: 0.84,
                                                    onTap:
                                                        widget.onDeleteSelected,
                                                    child: Container(
                                                      key: const ValueKey(
                                                        'folder_songs_delete_selected_button',
                                                      ),
                                                      width: 36,
                                                      height: 36,
                                                      decoration: BoxDecoration(
                                                        color: MusEveePalette
                                                            .error,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                          8,
                                                        ),
                                                      ),
                                                      alignment:
                                                          Alignment.center,
                                                      child: const Icon(
                                                        Icons
                                                            .delete_outline_rounded,
                                                        size: 18,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ActionPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final VoidCallback onTap;

  const _ActionPillButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: borderColor != null
              ? Border.all(color: borderColor!, width: 0.8)
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: foregroundColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

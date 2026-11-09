import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/local_playlist.dart';
import '../models/local_song.dart';
import '../providers/downloader_provider.dart';
import '../providers/local_music_provider.dart';
import 'pressable_scale.dart';
import 'tag_editor_sheet.dart';

// Shared Musicolet Dark Surface Palette
const Color _kBg = Color(0xFF0E1014);
const Color _kCard = Color(0xFF17191E);
const Color _kSubtle = Color(0xFF22252D);
const Color _kAccent = Color(0xFF3898EC);
const Color _kText = Color(0xFFF2F4F7);
const Color _kMuted = Color(0xFF98A2B3);
const Color _kEmerald = Color(0xFF10B981);

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
    final hairline = Colors.white.withValues(alpha: 0.08);

    return Consumer<LocalMusicProvider>(
      builder: (context, localProvider, _) {
        final entries = localProvider.queueEntries;
        final currentIdx = localProvider.currentIndex;

        return Container(
          color: _kBg,
          child: Column(
            children: [
              // Musicolet Queue Sub-Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                decoration: BoxDecoration(
                  color: _kCard,
                  border: Border(
                    bottom: BorderSide(color: hairline, width: 0.8),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.queue_music_rounded,
                      color: Colors.white,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entries.isEmpty
                          ? 'Now Playing Queue (0)'
                          : 'Queue (${currentIdx >= 0 ? currentIdx + 1 : 0}/${entries.length})',
                      style: const TextStyle(
                        color: _kText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    if (entries.isNotEmpty) ...[
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Acak (Shuffle)',
                        onPressed: localProvider.toggleShuffle,
                        icon: Icon(
                          Icons.shuffle_rounded,
                          size: 18,
                          color: localProvider.isShuffle ? _kAccent : _kMuted,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: _kMuted,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: localProvider.clearQueue,
                        child: const Text(
                          'Bersihkan',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.queue_music_rounded,
                                size: 42,
                                color: _kMuted,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Antrean putar masih kosong',
                                style: TextStyle(
                                  color: _kText,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Pilih lagu dari Folders (📁) atau unduh lagu baru di Downloader (⬇).',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _kMuted,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 14),
                              if (localProvider.allSongs.isNotEmpty)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _kAccent,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () {
                                    localProvider.playSong(
                                      localProvider.allSongs.first,
                                      queueContext: localProvider.allSongs,
                                    );
                                    onOpenNowPlaying();
                                  },
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Putar Semua Lagu Lokal'),
                                )
                              else
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _kAccent,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: onNavigateToDownloader,
                                  icon: const Icon(
                                    Icons.cloud_download_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Cari & Unduh Lagu'),
                                ),
                            ],
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        buildDefaultDragHandles: false,
                        itemCount: entries.length,
                        onReorderItem: localProvider.reorderQueueItem,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final song = entry.song;
                          final isCurrent = index == currentIdx;

                          return Material(
                            key: ValueKey(entry.queueId),
                            color: isCurrent
                                ? _kAccent.withValues(alpha: 0.12)
                                : Colors.transparent,
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
                                      child: isCurrent
                                          ? Center(
                                              child: AnimatedEqualizerIcon(
                                                isPlaying:
                                                    localProvider.isPlaying,
                                                size: 17,
                                                color: _kAccent,
                                              ),
                                            )
                                          : Text(
                                              '${index + 1}',
                                              style: const TextStyle(
                                                color: _kMuted,
                                                fontSize: 12,
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
                                                  ? Colors.white
                                                  : _kText,
                                              fontSize: 13.5,
                                              fontWeight: isCurrent
                                                  ? FontWeight.w700
                                                  : FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${song.artist} • ${song.formattedDuration}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: _kMuted,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'Hapus dari antrean',
                                      onPressed: () =>
                                          localProvider.removeFromQueue(index),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 17,
                                        color: _kMuted,
                                      ),
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.drag_handle_rounded,
                                          size: 18,
                                          color: _kMuted,
                                        ),
                                      ),
                                    ),
                                  ],
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
class LocalFoldersView extends StatefulWidget {
  final VoidCallback onOpenNowPlaying;
  final Future<void> Function(DownloaderProvider provider) onCreateNewFolder;
  final Future<void> Function(LocalSong song) onMoveLocalSongFolder;

  const LocalFoldersView({
    super.key,
    required this.onOpenNowPlaying,
    required this.onCreateNewFolder,
    required this.onMoveLocalSongFolder,
  });

  @override
  State<LocalFoldersView> createState() => _LocalFoldersViewState();
}

class _LocalFoldersViewState extends State<LocalFoldersView> {
  String? _openedFolder;
  bool _isSelectionMode = false;
  final Set<String> _selectedFolders = <String>{};

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
    final hairline = Colors.white.withValues(alpha: 0.09);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: hairline, width: 0.8),
      ),
      builder: (sheetCtx) {
        return Consumer<LocalMusicProvider>(
          builder: (ctx, provider, _) {
            final detected = provider.detectedFoldersInfo;
            final hiddenCount = provider.hiddenFoldersCount;

            return SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.78,
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
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 12, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _kSubtle,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.tune_rounded,
                              color: _kAccent,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Kelola / Sembunyikan Folder',
                                  style: TextStyle(
                                    color: _kText,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Sembunyikan folder dari pustaka tanpa menghapus file fisik.',
                                  style: TextStyle(
                                    color: _kMuted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (hiddenCount > 0)
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: _kAccent,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => provider.showAllHiddenFolders(),
                              child: Text(
                                'Tampilkan Semua ($hiddenCount)',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Divider(height: 1, thickness: 0.8, color: hairline),
                    if (detected.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 32,
                        ),
                        child: Center(
                          child: Text(
                            'Belum ada folder audio yang terdeteksi di penyimpanan.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _kMuted, fontSize: 12.5),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                          itemCount: detected.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 6),
                          itemBuilder: (itemCtx, idx) {
                            final info = detected[idx];
                            final isVisible = !info.isHidden;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: _kSubtle.withValues(
                                  alpha: isVisible ? 0.65 : 0.3,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: hairline, width: 0.8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isVisible
                                        ? Icons.folder_rounded
                                        : Icons.folder_off_outlined,
                                    color: isVisible ? _kAccent : _kMuted,
                                    size: 21,
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
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: isVisible
                                                      ? _kText
                                                      : _kMuted,
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 1.5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.black26,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '${info.songCount} lagu',
                                                style: const TextStyle(
                                                  color: _kMuted,
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w600,
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
                                          style: const TextStyle(
                                            color: _kMuted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: isVisible,
                                    activeThumbColor: _kAccent,
                                    activeTrackColor:
                                        _kAccent.withValues(alpha: 0.35),
                                    onChanged: (showFolder) {
                                      provider.setFolderHidden(
                                        info.folderPath,
                                        folderName: info.folderName,
                                        hidden: !showFolder,
                                      );
                                    },
                                  ),
                                ],
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

  @override
  Widget build(BuildContext context) {
    final hairline = Colors.white.withValues(alpha: 0.08);

    return Consumer2<LocalMusicProvider, DownloaderProvider>(
      builder: (context, localProvider, downloaderProvider, _) {
        final folderMap = localProvider.folderSongsMap;

        if (_openedFolder != null && folderMap.containsKey(_openedFolder)) {
          final folderName = _openedFolder!;
          final songs = folderMap[folderName] ?? const [];
          final folderPath = songs.isNotEmpty
              ? songs.first.folderPath
              : '/storage/emulated/0/Music/$folderName';
          return _buildSongDrillDownView(
            context: context,
            title: folderName,
            subtitle: '$folderPath • ${songs.length} lagu',
            songs: songs,
            localProvider: localProvider,
            downloaderProvider: downloaderProvider,
            onBack: () => setState(() => _openedFolder = null),
            onPlayAll: () {
              localProvider.playFolder(folderName, shuffle: false);
              widget.onOpenNowPlaying();
            },
            onShuffleAll: () {
              localProvider.playFolder(folderName, shuffle: true);
              widget.onOpenNowPlaying();
            },
            onAddAllToQueue: () async {
              final added = await localProvider.playCombinedFolders(
                [folderName],
                appendToCurrentQueue: true,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      added > 0
                          ? '$added lagu dari "$folderName" ditambahkan ke akhir antrean.'
                          : 'Semua lagu dari "$folderName" sudah ada di antrean.',
                    ),
                  ),
                );
              }
            },
            onMoveLocalSongFolder: widget.onMoveLocalSongFolder,
            onOpenNowPlaying: widget.onOpenNowPlaying,
          );
        }

        final folderNames = folderMap.keys.toList();
        final hiddenCount = localProvider.hiddenFoldersCount;
        // Prune any selected folder that is no longer visible
        _selectedFolders.removeWhere((f) => !folderMap.containsKey(f));
        final selectedList = _selectedFolders.toList();
        final selectedSongCount =
            _countUniqueSongsForFolders(folderMap, selectedList);

        return Container(
          color: _kBg,
          child: Stack(
            children: [
              Column(
                children: [
                  // Folders Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: _kCard,
                      border: Border(
                        bottom: BorderSide(color: hairline, width: 0.8),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isSelectionMode
                              ? Icons.library_add_check_rounded
                              : Icons.folder_rounded,
                          color: _isSelectionMode ? _kAccent : Colors.white,
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isSelectionMode
                                ? '${selectedList.length} Folder Dipilih ($selectedSongCount lagu)'
                                : 'Folders (${folderNames.length})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _kText,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_isSelectionMode && folderNames.length > 1)
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: _kAccent,
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
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
                              _selectedFolders.length == folderNames.length
                                  ? 'Reset'
                                  : 'Semua',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor:
                                hiddenCount > 0 ? _kAccent : _kText,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () =>
                              _showManageFoldersSheet(context, localProvider),
                          icon: Icon(
                            hiddenCount > 0
                                ? Icons.folder_off_outlined
                                : Icons.tune_rounded,
                            size: 15,
                          ),
                          label: Text(
                            hiddenCount > 0
                                ? 'Kelola Folder ($hiddenCount)'
                                : 'Kelola Folder',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_isSelectionMode)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Batal Pilih',
                            onPressed: _exitSelectionMode,
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: _kMuted,
                            ),
                          ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: folderNames.isEmpty
                        ? Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.folder_open_rounded,
                                    size: 42,
                                    color: _kMuted,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    hiddenCount > 0
                                        ? 'Semua folder sedang disembunyikan ($hiddenCount folder)'
                                        : 'Belum ada folder berisi lagu yang terdeteksi',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _kText,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Unduh lagu lewat tab Downloader atau pindai ulang penyimpanan perangkat Anda.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _kMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (hiddenCount > 0) ...[
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _kAccent,
                                        side: const BorderSide(
                                          color: _kAccent,
                                          width: 0.9,
                                        ),
                                      ),
                                      onPressed: () => _showManageFoldersSheet(
                                        context,
                                        localProvider,
                                      ),
                                      icon: const Icon(
                                        Icons.visibility_rounded,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Kelola Folder Tersembunyi',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              14,
                              12,
                              14,
                              _isSelectionMode ? 104 : 80,
                            ),
                            itemCount: folderNames.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, idx) {
                              final folder = folderNames[idx];
                              final songs = folderMap[folder] ?? const [];
                              final folderPath = songs.isNotEmpty
                                  ? songs.first.folderPath
                                  : '/storage/emulated/0/Music/$folder';
                              final isSelected =
                                  _selectedFolders.contains(folder);

                              return Material(
                                color: isSelected
                                    ? _kAccent.withValues(alpha: 0.14)
                                    : _kCard,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isSelected
                                        ? _kAccent.withValues(alpha: 0.75)
                                        : hairline,
                                    width: isSelected ? 1.1 : 0.8,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () {
                                    if (_isSelectionMode) {
                                      _toggleFolderSelection(folder);
                                    } else {
                                      setState(() => _openedFolder = folder);
                                    }
                                  },
                                  onLongPress: () =>
                                      _toggleFolderSelection(folder),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        if (_isSelectionMode)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 10,
                                            ),
                                            child: Icon(
                                              isSelected
                                                  ? Icons.check_circle_rounded
                                                  : Icons
                                                      .radio_button_unchecked_rounded,
                                              color: isSelected
                                                  ? _kAccent
                                                  : _kMuted,
                                              size: 22,
                                            ),
                                          ),
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? _kAccent
                                                    .withValues(alpha: 0.22)
                                                : _kSubtle,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.folder_rounded,
                                            color: _kAccent,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                folder,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: isSelected
                                                      ? Colors.white
                                                      : _kText,
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${songs.length} lagu • $folderPath',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: _kMuted,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!_isSelectionMode &&
                                            songs.isNotEmpty) ...[
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            tooltip: 'Putar Folder $folder',
                                            onPressed: () {
                                              localProvider.playFolder(folder);
                                              widget.onOpenNowPlaying();
                                            },
                                            icon: const Icon(
                                              Icons.play_circle_fill_rounded,
                                              color: Colors.white,
                                              size: 27,
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            icon: const Icon(
                                              Icons.more_vert_rounded,
                                              size: 18,
                                              color: _kMuted,
                                            ),
                                            color: _kSubtle,
                                            onSelected: (value) async {
                                              if (value == 'shuffle') {
                                                localProvider.playFolder(
                                                  folder,
                                                  shuffle: true,
                                                );
                                                widget.onOpenNowPlaying();
                                              } else if (value == 'add_queue') {
                                                final added = await localProvider
                                                    .playCombinedFolders(
                                                  [folder],
                                                  appendToCurrentQueue: true,
                                                );
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        added > 0
                                                            ? '$added lagu dari "$folder" ditambahkan ke antrean.'
                                                            : 'Semua lagu dari "$folder" sudah ada di antrean.',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              } else if (value ==
                                                  'multi_select') {
                                                _toggleFolderSelection(folder);
                                              } else if (value == 'hide') {
                                                await localProvider
                                                    .setFolderHidden(
                                                  folderPath,
                                                  folderName: folder,
                                                  hidden: true,
                                                );
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Folder "$folder" disembunyikan dari pustaka.',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                            itemBuilder: (_) => const [
                                              PopupMenuItem(
                                                value: 'shuffle',
                                                child: Text(
                                                  'Acak Folder (Shuffle)',
                                                  style: TextStyle(
                                                    color: _kText,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'add_queue',
                                                child: Text(
                                                  'Tambahkan ke Antrean Saat Ini (+ Queue)',
                                                  style: TextStyle(
                                                    color: _kText,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'multi_select',
                                                child: Text(
                                                  'Pilih untuk Digabung (Multi-Folder)',
                                                  style: TextStyle(
                                                    color: _kAccent,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'hide',
                                                child: Text(
                                                  'Sembunyikan Folder Ini',
                                                  style: TextStyle(
                                                    color: _kMuted,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),

              if (!_isSelectionMode && folderNames.isNotEmpty)
                Positioned(
                  right: 16,
                  bottom: 14,
                  child: _FloatingMergeFab(
                    tooltip: 'Gabung / Pilih Banyak Folder',
                    onTap: () => setState(() => _isSelectionMode = true),
                  ),
                ),

              if (_isSelectionMode)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: _MultiSelectQueueActionBar(
                    label: selectedList.isEmpty
                        ? 'Pilih 2+ Folder untuk digabung'
                        : '${selectedList.length} Folder • $selectedSongCount lagu unik',
                    hasSelection: selectedList.isNotEmpty,
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
                      final added = await localProvider.playCombinedFolders(
                        targets,
                        appendToCurrentQueue: true,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              added > 0
                                  ? '$added lagu dari ${targets.length} folder ditambahkan ke akhir antrean.'
                                  : 'Semua lagu dari folder terpilih sudah ada di antrean.',
                            ),
                          ),
                        );
                      }
                    },
                    onCancel: _exitSelectionMode,
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
// TAB 3: PLAYLISTS (`musicevee_playlists_v1.json`) — replaces Albums & Artists
// =============================================================================
class LocalPlaylistsView extends StatefulWidget {
  final VoidCallback onOpenNowPlaying;
  final Future<void> Function(LocalSong song) onMoveLocalSongFolder;

  const LocalPlaylistsView({
    super.key,
    required this.onOpenNowPlaying,
    required this.onMoveLocalSongFolder,
  });

  @override
  State<LocalPlaylistsView> createState() => _LocalPlaylistsViewState();
}

class _LocalPlaylistsViewState extends State<LocalPlaylistsView> {
  String? _openedPlaylistId;
  bool _isSelectionMode = false;
  final Set<String> _selectedPlaylistIds = <String>{};

  void _togglePlaylistSelection(String playlistId) {
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
      final pl = localProvider.playlistById(id);
      if (pl == null) continue;
      for (final s in localProvider.songsForPlaylist(pl)) {
        seen.add(s.filePath);
      }
    }
    return seen.length;
  }

  Future<void> _promptRename(
    LocalMusicProvider provider,
    LocalPlaylist playlist,
  ) async {
    final name = await showPlaylistNameDialog(
      context,
      title: 'Ganti Nama Playlist',
      initialValue: playlist.name,
      confirmLabel: 'Simpan',
    );
    if (name != null) await provider.renamePlaylist(playlist.id, name);
  }

  Future<void> _promptDelete(
    LocalMusicProvider provider,
    LocalPlaylist playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text(
          'Hapus Playlist?',
          style: TextStyle(
            color: _kText,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Playlist "${playlist.name}" akan dihapus. File lagu di HP tetap aman.',
          style: const TextStyle(color: Color(0xFFD0D5DD), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal', style: TextStyle(color: _kMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF04438),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (_openedPlaylistId == playlist.id && mounted) {
        setState(() => _openedPlaylistId = null);
      }
      _selectedPlaylistIds.remove(playlist.id);
      await provider.deletePlaylist(playlist.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hairline = Colors.white.withValues(alpha: 0.08);

    return Consumer2<LocalMusicProvider, DownloaderProvider>(
      builder: (context, localProvider, downloaderProvider, _) {
        final playlists = localProvider.playlists;
        final validIds = playlists.map((p) => p.id).toSet();
        _selectedPlaylistIds.removeWhere((id) => !validIds.contains(id));
        final selectedIds = _selectedPlaylistIds.toList();
        final selectedSongCount =
            _countUniqueSongsForPlaylists(localProvider, selectedIds);

        final opened = _openedPlaylistId != null
            ? localProvider.playlistById(_openedPlaylistId!)
            : null;

        Widget body;
        if (opened != null) {
          final songs = localProvider.songsForPlaylist(opened);
          body = KeyedSubtree(
            key: ValueKey('pl_detail_${opened.id}'),
            child: _buildSongDrillDownView(
              context: context,
              title: opened.name,
              subtitle: 'Playlist • ${songs.length} lagu',
              songs: songs,
              localProvider: localProvider,
              downloaderProvider: downloaderProvider,
              onBack: () => setState(() => _openedPlaylistId = null),
              onPlayAll: () {
                localProvider.playPlaylist(opened.id);
                widget.onOpenNowPlaying();
              },
              onShuffleAll: () {
                localProvider.playPlaylist(opened.id, shuffle: true);
                widget.onOpenNowPlaying();
              },
              onAddAllToQueue: () async {
                final added = await localProvider.playCombinedPlaylists(
                  [opened.id],
                  appendToCurrentQueue: true,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        added > 0
                            ? '$added lagu dari "${opened.name}" ditambahkan ke akhir antrean.'
                            : 'Semua lagu dari "${opened.name}" sudah ada di antrean.',
                      ),
                    ),
                  );
                }
              },
              onMoveLocalSongFolder: widget.onMoveLocalSongFolder,
              onOpenNowPlaying: widget.onOpenNowPlaying,
              emptyMessage:
                  'Playlist masih kosong. Tambahkan lagu via menu ⋮ → "Tambah ke Playlist".',
              onRemoveFromPlaylist: (song) =>
                  localProvider.removeSongFromPlaylist(opened.id, song.filePath),
            ),
          );
        } else {
          body = Container(
            key: const ValueKey('pl_list'),
            color: _kBg,
            child: Stack(
              children: [
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
                      decoration: BoxDecoration(
                        color: _kCard,
                        border: Border(
                          bottom: BorderSide(color: hairline, width: 0.8),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isSelectionMode
                                ? Icons.library_add_check_rounded
                                : Icons.queue_music_rounded,
                            color: _isSelectionMode ? _kAccent : Colors.white,
                            size: 19,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isSelectionMode
                                  ? '${selectedIds.length} Playlist Dipilih ($selectedSongCount lagu)'
                                  : 'Playlists (${playlists.length})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _kText,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_isSelectionMode && playlists.length > 1)
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: _kAccent,
                                visualDensity: VisualDensity.compact,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                              ),
                              onPressed: () {
                                setState(() {
                                  if (_selectedPlaylistIds.length ==
                                      playlists.length) {
                                    _selectedPlaylistIds.clear();
                                  } else {
                                    _selectedPlaylistIds.addAll(
                                      playlists.map((p) => p.id),
                                    );
                                  }
                                });
                              },
                              child: Text(
                                _selectedPlaylistIds.length == playlists.length
                                    ? 'Reset'
                                    : 'Semua',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (!_isSelectionMode)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: _kAccent,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                final name = await showPlaylistNameDialog(
                                  context,
                                  title: 'Playlist Baru',
                                );
                                if (name != null) {
                                  await localProvider.createPlaylist(name);
                                }
                              },
                              icon: const Icon(
                                Icons.playlist_add_rounded,
                                size: 17,
                              ),
                              label: const Text(
                                'Playlist Baru',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          else
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Batal Pilih',
                              onPressed: _exitSelectionMode,
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: _kMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: playlists.isEmpty
                          ? const _EmptyLocalHint(
                              icon: Icons.queue_music_outlined,
                              message:
                                  'Belum ada playlist. Buat playlist baru, atau unduh Album/Playlist Spotify agar playlist dibuat otomatis.',
                            )
                          : ListView.separated(
                              padding: EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                _isSelectionMode ? 104 : 80,
                              ),
                              itemCount: playlists.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, idx) {
                                final playlist = playlists[idx];
                                final resolved =
                                    localProvider.songsForPlaylist(playlist);
                                final isSelected =
                                    _selectedPlaylistIds.contains(playlist.id);

                                return PressableScale(
                                  pressedScale: 0.98,
                                  child: Material(
                                    color: isSelected
                                        ? _kAccent.withValues(alpha: 0.14)
                                        : _kCard,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: isSelected
                                            ? _kAccent.withValues(alpha: 0.75)
                                            : hairline,
                                        width: isSelected ? 1.1 : 0.8,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () {
                                        if (_isSelectionMode) {
                                          _togglePlaylistSelection(playlist.id);
                                        } else {
                                          setState(
                                            () =>
                                                _openedPlaylistId = playlist.id,
                                          );
                                        }
                                      },
                                      onLongPress: () =>
                                          _togglePlaylistSelection(playlist.id),
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Row(
                                          children: [
                                            if (_isSelectionMode)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 10,
                                                ),
                                                child: Icon(
                                                  isSelected
                                                      ? Icons
                                                          .check_circle_rounded
                                                      : Icons
                                                          .radio_button_unchecked_rounded,
                                                  color: isSelected
                                                      ? _kAccent
                                                      : _kMuted,
                                                  size: 22,
                                                ),
                                              ),
                                            _LocalCoverThumb(
                                              coverPath: localProvider
                                                  .playlistCoverPath(playlist),
                                              size: 48,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    playlist.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: isSelected
                                                          ? Colors.white
                                                          : _kText,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    '${resolved.length} lagu',
                                                    style: const TextStyle(
                                                      color: _kMuted,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (!_isSelectionMode &&
                                                resolved.isNotEmpty)
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                tooltip: 'Putar Playlist',
                                                onPressed: () {
                                                  localProvider.playPlaylist(
                                                    playlist.id,
                                                  );
                                                  widget.onOpenNowPlaying();
                                                },
                                                icon: const Icon(
                                                  Icons
                                                      .play_circle_fill_rounded,
                                                  color: Colors.white,
                                                  size: 27,
                                                ),
                                              ),
                                            if (!_isSelectionMode)
                                              PopupMenuButton<String>(
                                                icon: const Icon(
                                                  Icons.more_vert_rounded,
                                                  size: 18,
                                                  color: _kMuted,
                                                ),
                                                color: _kSubtle,
                                                onSelected: (value) async {
                                                  if (value == 'rename') {
                                                    await _promptRename(
                                                      localProvider,
                                                      playlist,
                                                    );
                                                  } else if (value ==
                                                      'shuffle') {
                                                    localProvider.playPlaylist(
                                                      playlist.id,
                                                      shuffle: true,
                                                    );
                                                    widget.onOpenNowPlaying();
                                                  } else if (value ==
                                                      'add_queue') {
                                                    final added =
                                                        await localProvider
                                                            .playCombinedPlaylists(
                                                      [playlist.id],
                                                      appendToCurrentQueue:
                                                          true,
                                                    );
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            added > 0
                                                                ? '$added lagu dari "${playlist.name}" ditambahkan ke antrean.'
                                                                : 'Semua lagu dari "${playlist.name}" sudah ada di antrean.',
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
                                                itemBuilder: (_) => const [
                                                  PopupMenuItem(
                                                    value: 'shuffle',
                                                    child: Text(
                                                      'Acak Playlist (Shuffle)',
                                                      style: TextStyle(
                                                        color: _kText,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'add_queue',
                                                    child: Text(
                                                      'Tambahkan ke Antrean Saat Ini (+ Queue)',
                                                      style: TextStyle(
                                                        color: _kText,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'multi_select',
                                                    child: Text(
                                                      'Pilih untuk Digabung (Multi-Playlist)',
                                                      style: TextStyle(
                                                        color: _kAccent,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'rename',
                                                    child: Text(
                                                      'Ganti Nama',
                                                      style: TextStyle(
                                                        color: _kText,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'delete',
                                                    child: Text(
                                                      'Hapus Playlist',
                                                      style: TextStyle(
                                                        color:
                                                            Color(0xFFF04438),
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                ],
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

                if (!_isSelectionMode && playlists.isNotEmpty)
                  Positioned(
                    right: 16,
                    bottom: 14,
                    child: _FloatingMergeFab(
                      tooltip: 'Gabung / Pilih Banyak Playlist',
                      onTap: () => setState(() => _isSelectionMode = true),
                    ),
                  ),

                if (_isSelectionMode)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: _MultiSelectQueueActionBar(
                      label: selectedIds.isEmpty
                          ? 'Pilih 2+ Playlist untuk digabung'
                          : '${selectedIds.length} Playlist • $selectedSongCount lagu unik',
                      hasSelection: selectedIds.isNotEmpty,
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
                                    ? '$added lagu dari ${targets.length} playlist ditambahkan ke akhir antrean.'
                                    : 'Semua lagu dari playlist terpilih sudah ada di antrean.',
                              ),
                            ),
                          );
                        }
                      },
                      onCancel: _exitSelectionMode,
                    ),
                  ),
              ],
            ),
          );
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
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
  String confirmLabel = 'Buat',
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _kCard,
      title: Text(
        title,
        style: const TextStyle(
          color: _kText,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: _kText, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Nama playlist',
          hintStyle: const TextStyle(color: _kMuted),
          filled: true,
          fillColor: _kSubtle,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Batal', style: TextStyle(color: _kMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kAccent,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  controller.dispose();
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
    backgroundColor: _kCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                  'Tambah "${song.title}" ke Playlist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded, color: _kAccent),
                title: const Text(
                  'Playlist Baru…',
                  style: TextStyle(color: _kAccent, fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.of(ctx).pop('__new__'),
              ),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
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
                              ? _kEmerald
                              : _kMuted,
                        ),
                        title: Text(
                          p.name,
                          style: const TextStyle(color: _kText, fontSize: 14),
                        ),
                        subtitle: Text(
                          '${p.songCount} lagu',
                          style: const TextStyle(color: _kMuted, fontSize: 11.5),
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
    final name = await showPlaylistNameDialog(context, title: 'Playlist Baru');
    if (name == null) return;
    final created = await localProvider.createPlaylist(name);
    targetId = created.id;
    targetName = created.name;
  } else {
    targetName = localProvider.playlistById(selected)?.name ?? '';
  }

  final added = await localProvider.addSongToPlaylist(targetId, song.filePath);
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        added
            ? 'Ditambahkan ke playlist "$targetName".'
            : 'Lagu sudah ada di playlist "$targetName".',
      ),
    ),
  );
}

// =============================================================================
// TAB 7: SEARCH LOKAL (`🔍`)
// =============================================================================
class LocalSearchView extends StatefulWidget {
  final VoidCallback onOpenNowPlaying;
  final Future<void> Function(LocalSong song) onMoveLocalSongFolder;

  const LocalSearchView({
    super.key,
    required this.onOpenNowPlaying,
    required this.onMoveLocalSongFolder,
  });

  @override
  State<LocalSearchView> createState() => _LocalSearchViewState();
}

class _LocalSearchViewState extends State<LocalSearchView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hairline = Colors.white.withValues(alpha: 0.08);

    return Consumer2<LocalMusicProvider, DownloaderProvider>(
      builder: (context, localProvider, downloaderProvider, _) {
        final filtered = localProvider.filteredLocalSongs;

        return Container(
          color: _kBg,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: _kCard,
                  border: Border(
                    bottom: BorderSide(color: hairline, width: 0.8),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: _kText, fontSize: 13.5),
                        onChanged: localProvider.setLocalSearchQuery,
                        decoration: InputDecoration(
                          hintText:
                              'Cari lagu, artis, album, atau folder di HP...',
                          hintStyle:
                              const TextStyle(color: _kMuted, fontSize: 13),
                          filled: true,
                          fillColor: _kSubtle,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: _kMuted,
                            size: 19,
                          ),
                          suffixIcon:
                              localProvider.localSearchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 17,
                                        color: _kMuted,
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                        localProvider.setLocalSearchQuery('');
                                      },
                                    )
                                  : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: hairline, width: 0.8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: hairline, width: 0.8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: _kAccent,
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: localProvider.filterFavoritesOnly,
                      showCheckmark: false,
                      backgroundColor: _kSubtle,
                      selectedColor: const Color(0xFFFF5A6E).withValues(alpha: 0.20),
                      side: BorderSide(
                        color: localProvider.filterFavoritesOnly
                            ? const Color(0xFFFF5A6E)
                            : hairline,
                        width: 0.8,
                      ),
                      label: Icon(
                        localProvider.filterFavoritesOnly
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 16,
                        color: localProvider.filterFavoritesOnly
                            ? const Color(0xFFFF5A6E)
                            : _kMuted,
                      ),
                      onSelected: (_) =>
                          localProvider.toggleFilterFavoritesOnly(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _EmptyLocalHint(
                        icon: Icons.search_off_rounded,
                        message: localProvider.allSongs.isEmpty
                            ? 'Belum ada lagu lokal yang tersimpan di perangkat.'
                            : 'Tidak ada lagu lokal yang cocok dengan pencarian.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 6),
                        itemBuilder: (context, idx) {
                          final song = filtered[idx];
                          return _LocalSongTile(
                            song: song,
                            queueContext: filtered,
                            localProvider: localProvider,
                            downloaderProvider: downloaderProvider,
                            onMoveLocalSongFolder: widget.onMoveLocalSongFolder,
                            onOpenNowPlaying: widget.onOpenNowPlaying,
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
// SHARED DRILL-DOWN SONG LIST & TILE WIDGETS
// =============================================================================
Widget _buildSongDrillDownView({
  required BuildContext context,
  required String title,
  required String subtitle,
  required List<LocalSong> songs,
  required LocalMusicProvider localProvider,
  required DownloaderProvider downloaderProvider,
  required VoidCallback onBack,
  required VoidCallback onPlayAll,
  required VoidCallback onShuffleAll,
  required Future<void> Function(LocalSong song) onMoveLocalSongFolder,
  required VoidCallback onOpenNowPlaying,
  VoidCallback? onAddAllToQueue,
  String emptyMessage = 'Folder ini belum berisi file MP3.',
  Future<void> Function(LocalSong song)? onRemoveFromPlaylist,
}) {
  final hairline = Colors.white.withValues(alpha: 0.08);

  return Container(
    color: _kBg,
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
          decoration: BoxDecoration(
            color: _kCard,
            border: Border(bottom: BorderSide(color: hairline, width: 0.8)),
          ),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onBack,
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kText,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _kMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              if (songs.isNotEmpty) ...[
                if (onAddAllToQueue != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Tambahkan Semua ke Antrean (+ Queue)',
                    onPressed: onAddAllToQueue,
                    icon: const Icon(
                      Icons.playlist_add_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Acak Semua',
                  onPressed: onShuffleAll,
                  icon: const Icon(
                    Icons.shuffle_rounded,
                    color: Colors.white70,
                    size: 19,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Putar Semua',
                  onPressed: onPlayAll,
                  icon: const Icon(
                    Icons.play_circle_fill_rounded,
                    color: _kAccent,
                    size: 26,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: songs.isEmpty
              ? _EmptyLocalHint(
                  icon: Icons.music_off_rounded,
                  message: emptyMessage,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                  itemCount: songs.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 6),
                  itemBuilder: (context, idx) {
                    return _LocalSongTile(
                      song: songs[idx],
                      queueContext: songs,
                      localProvider: localProvider,
                      downloaderProvider: downloaderProvider,
                      onMoveLocalSongFolder: onMoveLocalSongFolder,
                      onOpenNowPlaying: onOpenNowPlaying,
                      onRemoveFromPlaylist: onRemoveFromPlaylist,
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class _LocalSongTile extends StatelessWidget {
  final LocalSong song;
  final List<LocalSong> queueContext;
  final LocalMusicProvider localProvider;
  final DownloaderProvider downloaderProvider;
  final Future<void> Function(LocalSong song) onMoveLocalSongFolder;
  final VoidCallback onOpenNowPlaying;
  final Future<void> Function(LocalSong song)? onRemoveFromPlaylist;

  const _LocalSongTile({
    required this.song,
    required this.queueContext,
    required this.localProvider,
    required this.downloaderProvider,
    required this.onMoveLocalSongFolder,
    required this.onOpenNowPlaying,
    this.onRemoveFromPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = localProvider.currentSong?.filePath == song.filePath;
    final hairline = Colors.white.withValues(alpha: 0.07);

    return Material(
      color: isCurrent ? _kAccent.withValues(alpha: 0.14) : _kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isCurrent ? _kAccent.withValues(alpha: 0.45) : hairline,
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          localProvider.playSong(song, queueContext: queueContext);
          onOpenNowPlaying();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              _LocalCoverThumb(coverPath: song.coverFilePath, size: 46),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isCurrent) ...[
                          AnimatedEqualizerIcon(
                            isPlaying: localProvider.isPlaying,
                            size: 15,
                            color: _kAccent,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent ? Colors.white : _kText,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${song.artist} • ${song.folderName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _kMuted, fontSize: 11.5),
                    ),
                    if (song.hasLyrics) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: _kEmerald,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            song.hasSyncedLyrics ? 'Synced LRC' : 'USLT Lyrics',
                            style: const TextStyle(
                              color: _kEmerald,
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
              const SizedBox(width: 6),
              Text(
                song.formattedDuration,
                style: const TextStyle(
                  color: _kMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: _kMuted,
                ),
                color: _kSubtle,
                onSelected: (value) async {
                  if (value == 'play_next') {
                    localProvider.addToQueue(song, playNext: true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Diputar berikutnya: ${song.title}'),
                      ),
                    );
                  } else if (value == 'add_queue') {
                    localProvider.addToQueue(song);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Ditambahkan ke antrean: ${song.title}'),
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
                        backgroundColor: _kCard,
                        title: const Text(
                          'Hapus File Lagu?',
                          style: TextStyle(
                            color: _kText,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        content: Text(
                          'Hapus permanen "${song.title}" dari folder ${song.folderName}?',
                          style: const TextStyle(
                            color: Color(0xFFD0D5DD),
                            fontSize: 13,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text(
                              'Batal',
                              style: TextStyle(color: _kMuted),
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF04438),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Hapus'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      final ok = await localProvider.deleteLocalSong(song);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'File lagu berhasil dihapus.'
                                  : 'Penghapusan dibatalkan atau izin ditolak.',
                            ),
                          ),
                        );
                      }
                    }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'play_next',
                    child: Text(
                      'Putar Berikutnya',
                      style: TextStyle(color: _kText, fontSize: 13),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'add_queue',
                    child: Text(
                      'Tambah ke Antrean (=+)',
                      style: TextStyle(color: _kText, fontSize: 13),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'add_playlist',
                    child: Text(
                      'Tambah ke Playlist',
                      style: TextStyle(color: _kText, fontSize: 13),
                    ),
                  ),
                  if (onRemoveFromPlaylist != null)
                    const PopupMenuItem(
                      value: 'remove_playlist',
                      child: Text(
                        'Keluarkan dari Playlist',
                        style: TextStyle(color: _kText, fontSize: 13),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'edit_tag',
                    child: Text(
                      'Edit Tag & Auto-Romaji (✎)',
                      style: TextStyle(color: _kText, fontSize: 13),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'move',
                    child: Text(
                      'Pindah Folder',
                      style: TextStyle(color: _kText, fontSize: 13),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Hapus File',
                      style: TextStyle(color: Color(0xFFF04438), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalCoverThumb extends StatelessWidget {
  final String? coverPath;
  final double size;

  const _LocalCoverThumb({
    required this.coverPath,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(5);

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
          errorBuilder: (context, error, stackTrace) => _fallback(radius),
        ),
      );
    }
    return _fallback(radius);
  }

  Widget _fallback(BorderRadius radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _kSubtle,
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        color: _kMuted,
        size: size * 0.42,
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
            Icon(icon, size: 38, color: _kMuted),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingMergeFab extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;

  const _FloatingMergeFab({
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hairline = Colors.white.withValues(alpha: 0.16);
    return PressableScale(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: const Color(0xFF1F242E),
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.65),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: hairline, width: 0.9),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.library_add_check_rounded,
                  size: 17,
                  color: _kAccent,
                ),
                SizedBox(width: 7),
                Text(
                  'Gabung',
                  style: TextStyle(
                    color: _kText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MultiSelectQueueActionBar extends StatelessWidget {
  final String label;
  final bool hasSelection;
  final VoidCallback onPlayCombined;
  final VoidCallback onShuffleCombined;
  final VoidCallback onAppendQueue;
  final VoidCallback onCancel;

  const _MultiSelectQueueActionBar({
    required this.label,
    this.hasSelection = true,
    required this.onPlayCombined,
    required this.onShuffleCombined,
    required this.onAppendQueue,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final hairline = Colors.white.withValues(alpha: 0.14);
    return Material(
      color: const Color(0xFF1D2129),
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: hairline, width: 0.9),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: _kAccent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Gabungkan ke Antrean (Deduplikasi Otomatis)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _kMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
                InkWell(
                  onTap: onCancel,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: _kMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: hasSelection ? 1.0 : 0.45,
              child: IgnorePointer(
                ignoring: !hasSelection,
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionPillButton(
                        icon: Icons.play_arrow_rounded,
                        label: 'Putar',
                        backgroundColor: _kAccent,
                        foregroundColor: Colors.white,
                        onTap: onPlayCombined,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _ActionPillButton(
                        icon: Icons.shuffle_rounded,
                        label: 'Shuffle Mix',
                        backgroundColor: const Color(0xFF282D38),
                        foregroundColor: _kText,
                        borderColor: Colors.white.withValues(alpha: 0.14),
                        onTap: onShuffleCombined,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _ActionPillButton(
                        icon: Icons.playlist_add_rounded,
                        label: '+ Queue',
                        backgroundColor: const Color(0xFF282D38),
                        foregroundColor: _kText,
                        borderColor: Colors.white.withValues(alpha: 0.14),
                        onTap: onAppendQueue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

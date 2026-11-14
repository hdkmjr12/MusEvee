import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track_metadata.dart';
import '../providers/downloader_provider.dart';
import '../services/metadata_service.dart';
import '../theme/musevee_palette.dart';
import '../utils/app_strings.dart';
import 'pressable_scale.dart';

class BatchPlaylistSheet extends StatefulWidget {
  final SpotifyCollectionResult? collection;
  final String? initialTitle;
  final String? initialCoverUrl;
  final Future<bool> Function()? onRetry;
  final Future<void> Function(DownloaderProvider provider) onCreateNewFolder;

  const BatchPlaylistSheet({
    super.key,
    this.collection,
    this.initialTitle,
    this.initialCoverUrl,
    this.onRetry,
    required this.onCreateNewFolder,
  });

  static Future<void> show(
    BuildContext context, {
    SpotifyCollectionResult? collection,
    String? initialTitle,
    String? initialCoverUrl,
    Future<bool> Function()? onRetry,
    required Future<void> Function(DownloaderProvider provider)
        onCreateNewFolder,
  }) {
    final palette = context.palette;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.nowPlayingBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => BatchPlaylistSheet(
        collection: collection,
        initialTitle: initialTitle,
        initialCoverUrl: initialCoverUrl,
        onRetry: onRetry,
        onCreateNewFolder: onCreateNewFolder,
      ),
    );
  }

  @override
  State<BatchPlaylistSheet> createState() => _BatchPlaylistSheetState();
}

class _BatchPlaylistSheetState extends State<BatchPlaylistSheet> {
  final Set<int> _selectedIndices = <int>{};
  SpotifyCollectionResult? _syncedCollection;

  @override
  void initState() {
    super.initState();
    _syncSelectionForCollection(widget.collection);
  }

  void _syncSelectionForCollection(SpotifyCollectionResult? active) {
    if (identical(_syncedCollection, active)) return;
    _syncedCollection = active;
    _selectedIndices.clear();
    if (active != null && active.tracks.isNotEmpty) {
      _selectedIndices.addAll(
        List<int>.generate(active.tracks.length, (i) => i),
      );
    }
  }

  void _toggleSelectAll(List<TrackMetadata> tracks) {
    setState(() {
      if (_selectedIndices.length == tracks.length) {
        _selectedIndices.clear();
      } else {
        _selectedIndices
          ..clear()
          ..addAll(List<int>.generate(tracks.length, (i) => i));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    SystemLocaleScope.watch(context);
    final palette = context.palette;
    final screenHeight = MediaQuery.of(context).size.height;
    final hairline = palette.hairline;

    return Consumer<DownloaderProvider>(
      builder: (context, provider, _) {
        final activeCollection =
            widget.collection ?? provider.currentCollection;
        _syncSelectionForCollection(activeCollection);

        if (activeCollection == null || activeCollection.tracks.isEmpty) {
          final isError = provider.state == DownloaderState.error;
          final headerTitle = widget.initialTitle?.trim().isNotEmpty == true
              ? widget.initialTitle!.trim()
              : 'Playlist';
          final coverUrl = widget.initialCoverUrl?.trim() ?? '';

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: screenHeight * 0.72),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: palette.surfaceSubtle,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: hairline, width: 0.8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: coverUrl.isNotEmpty
                              ? Image.network(
                                  coverUrl,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _buildPlaceholder(56, palette),
                                )
                              : _buildPlaceholder(56, palette),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PLAYLIST',
                                style: TextStyle(
                                  color: palette.nowPlayingPrimary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                headerTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    if (isError) ...[
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 36,
                        color: MusEveePalette.error,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        provider.errorMessage ?? AppStrings.batchLoadFailed,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: MographSpringTap(
                              pressedScale: 0.96,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: palette.textPrimary,
                                  side: BorderSide(color: hairline),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  minimumSize: const Size.fromHeight(44),
                                ),
                                child: Text(AppStrings.closeLabel),
                              ),
                            ),
                          ),
                          if (widget.onRetry != null) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: MographSpringTap(
                                pressedScale: 0.96,
                                child: ElevatedButton(
                                  onPressed: () => widget.onRetry!.call(),
                                  style: ElevatedButton.styleFrom(
                                    elevation: 0,
                                    backgroundColor: palette.nowPlayingPrimary,
                                    foregroundColor:
                                        palette.nowPlayingOnPrimary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                  child: Text(AppStrings.retryLabel),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ] else ...[
                      Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: palette.nowPlayingPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        provider.statusMessage.isNotEmpty
                            ? provider.statusMessage
                            : AppStrings.batchLoadingTracks,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        final tracks = activeCollection.tracks;
        final allSelected =
            tracks.isNotEmpty && _selectedIndices.length == tracks.length;

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screenHeight * 0.86),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag Handle (36x4px)
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
                  const SizedBox(height: 16),

                  // Collection Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: palette.surfaceSubtle,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: hairline, width: 0.8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: activeCollection.coverUrl.isNotEmpty
                              ? Image.network(
                                  activeCollection.coverUrl,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _buildPlaceholder(56, palette),
                                )
                              : _buildPlaceholder(56, palette),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: palette.nowPlayingPrimary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      activeCollection.collectionType == 'album'
                                          ? 'ALBUM'
                                          : 'PLAYLIST',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.nowPlayingPrimary,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                activeCollection.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${activeCollection.subtitle.isNotEmpty ? "${activeCollection.subtitle} • " : ""}${AppStrings.songCountTitle(tracks.length)}',
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
                        const SizedBox(width: 4),
                        MographSpringTap(
                          pressedScale: 0.92,
                          child: TextButton(
                            onPressed: () => _toggleSelectAll(tracks),
                            style: TextButton.styleFrom(
                              foregroundColor: palette.nowPlayingPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: Text(
                              allSelected
                                  ? AppStrings.batchDeselectAll
                                  : AppStrings.batchSelectAll,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Track List with Checkboxes
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Material(
                        color: palette.surfaceSubtle,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: hairline, width: 0.8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: tracks.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1,
                            color: hairline,
                          ),
                          itemBuilder: (context, index) {
                            final track = tracks[index];
                            final isChecked = _selectedIndices.contains(index);
                            final dupFolder =
                                provider.duplicateFolderFor(track);

                            return CheckboxListTile(
                              value: isChecked,
                              dense: true,
                              activeColor: palette.nowPlayingPrimary,
                              checkColor: palette.nowPlayingOnPrimary,
                              checkboxShape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedIndices.add(index);
                                  } else {
                                    _selectedIndices.remove(index);
                                  }
                                });
                              },
                              title: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${track.artist} • ${track.formattedDuration}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (dupFolder != null) ...[
                                    const SizedBox(height: 3),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 5,
                                          height: 5,
                                          decoration: const BoxDecoration(
                                            color: MusEveePalette.amber,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          AppStrings.batchAlreadyInFolder(
                                            dupFolder,
                                          ),
                                          style: const TextStyle(
                                            color: MusEveePalette.amber,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Target Folder Selector Row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      AppStrings.batchTargetFolderLabel,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        ...provider.availableFolders.map((folder) {
                          final isSelected = folder == provider.selectedFolder;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: MographSpringTap(
                              pressedScale: 0.94,
                              child: ChoiceChip(
                                selected: isSelected,
                                showCheckmark: false,
                                backgroundColor: palette.surfaceSubtle,
                                selectedColor: palette.nowPlayingPrimary,
                                side: BorderSide(
                                  color: isSelected
                                      ? palette.nowPlayingPrimary
                                      : hairline,
                                  width: 0.8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                label: Text(
                                  folder,
                                  style: TextStyle(
                                    color: isSelected
                                        ? palette.nowPlayingOnPrimary
                                        : palette.textPrimary,
                                    fontSize: 12.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                                onSelected: (_) =>
                                    provider.selectFolder(folder),
                              ),
                            ),
                          );
                        }),
                        MographSpringTap(
                          pressedScale: 0.94,
                          child: ActionChip(
                            backgroundColor: palette.surfaceCard,
                            side: BorderSide(color: hairline, width: 0.8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            label: Text(
                              AppStrings.batchNewFolderChip,
                              style: TextStyle(
                                color: palette.nowPlayingPrimary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: () =>
                                widget.onCreateNewFolder(provider),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Primary Batch Queue Button (10px radius)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: 48,
                      child: MographSpringTap(
                        pressedScale: 0.97,
                        enabled: _selectedIndices.isNotEmpty,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: palette.nowPlayingPrimary,
                            foregroundColor: palette.nowPlayingOnPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _selectedIndices.isEmpty
                              ? null
                              : () async {
                                  final sortedIndices =
                                      _selectedIndices.toList()..sort();
                                  final chosenTracks = <TrackMetadata>[
                                    for (final idx in sortedIndices)
                                      tracks[idx],
                                  ];
                                  final targetFolder = provider.selectedFolder;
                                  final playlistName =
                                      activeCollection.title.trim();
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  Navigator.of(context).pop();
                                  final skipped =
                                      await provider.enqueueBatchTracks(
                                    chosenTracks,
                                    folderName: targetFolder,
                                    playlistName: playlistName,
                                  );
                                  final queued = chosenTracks.length - skipped;
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppStrings.batchQueuedResult(
                                          queued: queued,
                                          targetFolder: targetFolder,
                                          skipped: skipped,
                                          playlistName: playlistName,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.playlist_add_check_rounded),
                          label: Text(
                            AppStrings.batchSaveSelectedToFolder(
                              _selectedIndices.length,
                              provider.selectedFolder,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder(double size, MusEveePalette palette) {
    return Container(
      width: size,
      height: size,
      color: palette.surfaceSubtle,
      alignment: Alignment.center,
      child: Icon(
        Icons.album_outlined,
        color: palette.textMuted,
        size: size * 0.42,
      ),
    );
  }
}

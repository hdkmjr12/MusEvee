import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track_metadata.dart';
import '../providers/downloader_provider.dart';
import '../services/metadata_service.dart';

class BatchPlaylistSheet extends StatefulWidget {
  final SpotifyCollectionResult collection;
  final Future<void> Function(DownloaderProvider provider) onCreateNewFolder;

  const BatchPlaylistSheet({
    super.key,
    required this.collection,
    required this.onCreateNewFolder,
  });

  static Future<void> show(
    BuildContext context, {
    required SpotifyCollectionResult collection,
    required Future<void> Function(DownloaderProvider provider)
        onCreateNewFolder,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => BatchPlaylistSheet(
        collection: collection,
        onCreateNewFolder: onCreateNewFolder,
      ),
    );
  }

  @override
  State<BatchPlaylistSheet> createState() => _BatchPlaylistSheetState();
}

class _BatchPlaylistSheetState extends State<BatchPlaylistSheet> {
  static const Color _surfaceCard = Color(0xFFFFFFFF);
  static const Color _surfaceSubtle = Color(0xFFF2F4F7);
  static const Color _primaryBlue = Color(0xFF1677B8);
  static const Color _textDark = Color(0xFF15181E);
  static const Color _textMuted = Color(0xFF68717C);
  static const Color _amberDot = Color(0xFFD97706);

  late final Set<int> _selectedIndices;

  @override
  void initState() {
    super.initState();
    _selectedIndices = Set<int>.from(
      List<int>.generate(widget.collection.tracks.length, (i) => i),
    );
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIndices.length == widget.collection.tracks.length) {
        _selectedIndices.clear();
      } else {
        _selectedIndices.addAll(
          List<int>.generate(widget.collection.tracks.length, (i) => i),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final tracks = widget.collection.tracks;
    final allSelected =
        tracks.isNotEmpty && _selectedIndices.length == tracks.length;
    final hairline = Colors.black.withValues(alpha: 0.07);

    return Consumer<DownloaderProvider>(
      builder: (context, provider, _) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screenHeight * 0.86),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
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
                        color: Colors.black.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Collection Header
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: _surfaceSubtle,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: hairline, width: 0.8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: widget.collection.coverUrl.isNotEmpty
                            ? Image.network(
                                widget.collection.coverUrl,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildPlaceholder(64),
                              )
                            : _buildPlaceholder(64),
                      ),
                      const SizedBox(width: 12),
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
                                  decoration: const BoxDecoration(
                                    color: _primaryBlue,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  widget.collection.collectionType == 'album'
                                      ? 'ALBUM'
                                      : 'PLAYLIST',
                                  style: const TextStyle(
                                    color: _primaryBlue,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.collection.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textDark,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${widget.collection.subtitle.isNotEmpty ? "${widget.collection.subtitle} • " : ""}${tracks.length} Lagu',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _toggleSelectAll,
                        style: TextButton.styleFrom(
                          foregroundColor: _primaryBlue,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Text(
                          allSelected ? 'Batal Pilih' : 'Pilih Semua',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Track List with Checkboxes
                  Flexible(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _surfaceSubtle,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: hairline, width: 0.8),
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
                          final dupFolder = provider.duplicateFolderFor(track);

                          return CheckboxListTile(
                            value: isChecked,
                            dense: true,
                            activeColor: _primaryBlue,
                            checkColor: _surfaceCard,
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
                              style: const TextStyle(
                                color: _textDark,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
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
                                  style: const TextStyle(
                                    color: _textMuted,
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
                                          color: _amberDot,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Sudah ada di $dupFolder',
                                        style: const TextStyle(
                                          color: _amberDot,
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
                  const SizedBox(height: 14),

                  // Target Folder Selector Row
                  const Text(
                    'Folder Tujuan:',
                    style: TextStyle(
                      color: _textDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ...provider.availableFolders.map((folder) {
                          final isSelected = folder == provider.selectedFolder;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              selected: isSelected,
                              showCheckmark: false,
                              backgroundColor: _surfaceSubtle,
                              selectedColor: _primaryBlue,
                              side: BorderSide(
                                color: isSelected ? _primaryBlue : hairline,
                                width: 0.8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              label: Text(
                                folder,
                                style: TextStyle(
                                  color: isSelected ? _surfaceCard : _textDark,
                                  fontSize: 12.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                              onSelected: (_) => provider.selectFolder(folder),
                            ),
                          );
                        }),
                        ActionChip(
                          backgroundColor: _surfaceCard,
                          side: BorderSide(color: hairline, width: 0.8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          label: const Text(
                            '+ Baru',
                            style: TextStyle(
                              color: _primaryBlue,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: () => widget.onCreateNewFolder(provider),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Primary Batch Queue Button (10px radius)
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryBlue,
                        foregroundColor: _surfaceCard,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _selectedIndices.isEmpty
                          ? null
                          : () {
                              final sortedIndices = _selectedIndices.toList()
                                ..sort();
                              final chosenTracks = <TrackMetadata>[
                                for (final idx in sortedIndices) tracks[idx],
                              ];
                              final targetFolder = provider.selectedFolder;
                              Navigator.of(context).pop();
                              provider.enqueueBatchTracks(
                                chosenTracks,
                                folderName: targetFolder,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${chosenTracks.length} lagu ditambahkan ke antrean ($targetFolder).',
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.playlist_add_check_rounded),
                      label: Text(
                        'Simpan ${_selectedIndices.length} Lagu ke ${provider.selectedFolder}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
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

  Widget _buildPlaceholder(double size) {
    return Container(
      width: size,
      height: size,
      color: _surfaceSubtle,
      alignment: Alignment.center,
      child: Icon(
        Icons.album_outlined,
        color: _textMuted,
        size: size * 0.42,
      ),
    );
  }
}

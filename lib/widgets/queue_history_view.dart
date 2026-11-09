import 'package:flutter/material.dart';

import '../models/download_item.dart';
import '../providers/downloader_provider.dart';
import '../theme/musevee_palette.dart';
import 'tag_editor_sheet.dart';

class QueueHistoryView extends StatelessWidget {
  final DownloaderProvider provider;
  final Future<void> Function(DownloaderProvider provider, DownloadItem item)
      onMoveFolder;
  final Future<void> Function(String savedFilePath)? onPlaySavedFile;

  const QueueHistoryView({
    super.key,
    required this.provider,
    required this.onMoveFolder,
    this.onPlaySavedFile,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final activeQueueItems = provider.queueItems
        .where(
          (item) =>
              item.status == DownloadItemStatus.queued ||
              item.status == DownloadItemStatus.downloading ||
              item.status == DownloadItemStatus.tagging,
        )
        .toList();

    final completedItems = provider.queueItems
        .where(
          (item) =>
              item.status == DownloadItemStatus.completed ||
              item.status == DownloadItemStatus.failed,
        )
        .toList();

    final isDirectDownloadActive =
        provider.state == DownloaderState.downloadingAudio ||
        provider.state == DownloaderState.taggingAudio;

    return Container(
      color: palette.bgCanvas,
      child: CustomScrollView(
        slivers: [
          // SEKSI ATAS: ANTREAN AKTIF
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(
                    palette: palette,
                    icon: Icons.downloading_rounded,
                    title: 'Antrean Unduhan Aktif',
                    count: activeQueueItems.length +
                        (isDirectDownloadActive ? 1 : 0),
                  ),
                  const SizedBox(height: 10),
                  if (!isDirectDownloadActive && activeQueueItems.isEmpty)
                    _buildEmptyActiveCard(palette)
                  else ...[
                    if (isDirectDownloadActive &&
                        provider.trackMetadata != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildDirectActiveCard(provider, palette),
                      ),
                    ...activeQueueItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildActiveQueueCard(item, palette),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // SEKSI BAWAH: RIWAYAT UNDUHAN
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSectionHeader(
                      palette: palette,
                      icon: Icons.history_rounded,
                      title: 'Riwayat Unduhan Selesai',
                      count: completedItems.length,
                    ),
                  ),
                  if (completedItems.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: palette.textMuted,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: provider.clearCompletedQueueItems,
                      child: const Text(
                        'Bersihkan',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          if (completedItems.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                child: _buildEmptyHistoryCard(provider, palette),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
              sliver: SliverList.separated(
                itemCount: completedItems.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = completedItems[index];
                  return _buildCompletedItemCard(context, item, palette);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required MusEveePalette palette,
    required IconData icon,
    required String title,
    required int count,
  }) {
    final hairline = palette.hairline;
    return Row(
      children: [
        Icon(icon, size: 18, color: palette.accent),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: palette.surfaceSubtle,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: hairline, width: 0.8),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyActiveCard(MusEveePalette palette) {
    final hairline = palette.hairline;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hairline, width: 0.8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: palette.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tidak ada unduhan FFmpeg yang sedang berjalan.',
              style: TextStyle(color: palette.textMuted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectActiveCard(
    DownloaderProvider provider,
    MusEveePalette palette,
  ) {
    final track = provider.trackMetadata!;
    final pct = (provider.progress * 100).round();
    final hairline = palette.hairline;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: palette.accent.withValues(alpha: 0.45),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: palette.surfaceSubtle,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: hairline, width: 0.8),
                ),
                clipBehavior: Clip.antiAlias,
                child: track.coverUrl.isNotEmpty
                    ? Image.network(
                        track.coverUrl,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildPlaceholder(46, palette),
                      )
                    : _buildPlaceholder(46, palette),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${track.artist} • ${provider.selectedFolder}',
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
              const SizedBox(width: 8),
              Text(
                '$pct%',
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: provider.progress.clamp(0.0, 1.0),
            minHeight: 3.5,
            borderRadius: BorderRadius.circular(2),
            backgroundColor: palette.surfaceSubtle,
            valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
          ),
          const SizedBox(height: 7),
          Text(
            provider.statusMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textMuted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveQueueCard(DownloadItem item, MusEveePalette palette) {
    final isQueued = item.status == DownloadItemStatus.queued;
    final pct = (item.progress * 100).round();
    final hairline = palette.hairline;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hairline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: palette.surfaceSubtle,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: hairline, width: 0.8),
                ),
                clipBehavior: Clip.antiAlias,
                child: item.metadata.coverUrl.isNotEmpty
                    ? Image.network(
                        item.metadata.coverUrl,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildPlaceholder(46, palette),
                      )
                    : _buildPlaceholder(46, palette),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.metadata.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.metadata.artist} • ${item.targetFolderName}',
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
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isQueued ? MusEveePalette.amber : palette.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isQueued ? 'Menunggu' : '$pct%',
                    style: TextStyle(
                      color: isQueued ? MusEveePalette.amber : palette.accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (!isQueued) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: item.progress.clamp(0.0, 1.0),
              minHeight: 3.5,
              borderRadius: BorderRadius.circular(2),
              backgroundColor: palette.surfaceSubtle,
              valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
            ),
          ],
          const SizedBox(height: 7),
          Text(
            item.statusDetail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textMuted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedItemCard(
    BuildContext context,
    DownloadItem item,
    MusEveePalette palette,
  ) {
    final isFailed = item.status == DownloadItemStatus.failed;
    final hasLyrics = (item.metadata.cleanPlainLyrics != null &&
            item.metadata.cleanPlainLyrics!.trim().isNotEmpty) ||
        item.metadata.hasSyncedLyrics;
    final hairline = palette.hairline;

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hairline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Cover Art 50x50 (Tap to play directly in MusEvee!)
              GestureDetector(
                onTap: (!isFailed &&
                        item.savedFilePath != null &&
                        onPlaySavedFile != null)
                    ? () => onPlaySavedFile!(item.savedFilePath!)
                    : null,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: palette.surfaceSubtle,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: hairline, width: 0.8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: item.metadata.coverUrl.isNotEmpty
                      ? Image.network(
                          item.metadata.coverUrl,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildPlaceholder(50, palette),
                        )
                      : _buildPlaceholder(50, palette),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.metadata.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.metadata.artist} • ${item.metadata.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5.5,
                              height: 5.5,
                              decoration: BoxDecoration(
                                color: isFailed
                                    ? MusEveePalette.error
                                    : palette.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isFailed ? 'Gagal' : item.targetFolderName,
                              style: TextStyle(
                                color: isFailed
                                    ? MusEveePalette.error
                                    : palette.textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (hasLyrics && !isFailed)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5.5,
                                height: 5.5,
                                decoration: const BoxDecoration(
                                  color: MusEveePalette.emerald,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                'USLT Lyrics',
                                style: TextStyle(
                                  color: MusEveePalette.emerald,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isFailed && item.savedFilePath != null) ...[
                const SizedBox(width: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onPlaySavedFile != null) ...[
                      IconButton(
                        tooltip: 'Putar di Now Playing',
                        style: IconButton.styleFrom(
                          backgroundColor:
                              palette.accent.withValues(alpha: 0.16),
                          minimumSize: const Size(32, 32),
                          padding: const EdgeInsets.all(5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: () => onPlaySavedFile!(item.savedFilePath!),
                        icon: Icon(
                          Icons.play_arrow_rounded,
                          size: 18,
                          color: palette.accent,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    IconButton(
                      tooltip: 'Edit Tag Ulang',
                      style: IconButton.styleFrom(
                        backgroundColor: palette.surfaceSubtle,
                        minimumSize: const Size(32, 32),
                        padding: const EdgeInsets.all(6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: BorderSide(color: hairline, width: 0.8),
                        ),
                      ),
                      onPressed: () => TagEditorSheet.showForHistoryItem(
                        context,
                        provider: provider,
                        item: item,
                      ),
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 15,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 5),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: palette.surfaceSubtle,
                        foregroundColor: palette.textPrimary,
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        side: BorderSide(color: hairline, width: 0.8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: () => onMoveFolder(provider, item),
                      icon: Icon(
                        Icons.drive_file_move_outlined,
                        size: 14,
                        color: palette.accent,
                      ),
                      label: const Text(
                        'Pindah',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (isFailed) ...[
                const SizedBox(width: 6),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.textPrimary,
                    backgroundColor: palette.surfaceSubtle,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: () => provider.enqueueTrack(
                    item.metadata,
                    folderName: item.targetFolderName,
                    preferSynced: item.preferSyncedLyrics,
                  ),
                  child: const Text(
                    'Ulangi',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ],
          ),
          if (isFailed && item.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              item.errorMessage!,
              style: const TextStyle(
                color: MusEveePalette.error,
                fontSize: 11.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyHistoryCard(
    DownloaderProvider provider,
    MusEveePalette palette,
  ) {
    final counts = provider.folderSongCounts;
    final hairline = palette.hairline;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hairline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: palette.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Belum ada riwayat unduhan pada sesi ini.',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (provider.availableFolders.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: hairline),
            const SizedBox(height: 10),
            Text(
              'Ringkasan Koleksi Folder Lokal:',
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: provider.availableFolders.map((folder) {
                final count = counts[folder] ?? 0;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: palette.surfaceSubtle,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: hairline, width: 0.8),
                  ),
                  child: Text(
                    '$folder: $count Lagu',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlaceholder(double size, MusEveePalette palette) {
    return Container(
      width: size,
      height: size,
      color: palette.surfaceSubtle,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        color: palette.textMuted,
        size: size * 0.38,
      ),
    );
  }
}

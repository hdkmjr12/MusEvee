import 'package:flutter/material.dart';

import '../models/download_item.dart';
import '../providers/downloader_provider.dart';
import 'tag_editor_sheet.dart';

class QueueHistoryView extends StatelessWidget {
  final DownloaderProvider provider;
  final Future<void> Function(DownloaderProvider provider, DownloadItem item)
      onMoveFolder;

  const QueueHistoryView({
    super.key,
    required this.provider,
    required this.onMoveFolder,
  });

  static const Color _surfaceCard = Color(0xFFFFFFFF);
  static const Color _surfaceSubtle = Color(0xFFF2F4F7);
  static const Color _primaryBlue = Color(0xFF1677B8);
  static const Color _textDark = Color(0xFF15181E);
  static const Color _textMuted = Color(0xFF68717C);
  static const Color _emeraldDot = Color(0xFF10B981);
  static const Color _amberDot = Color(0xFFD97706);
  static const Color _redDot = Color(0xFFD92D20);

  @override
  Widget build(BuildContext context) {
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

    return CustomScrollView(
      slivers: [
        // SEKSI ATAS: ANTREAN AKTIF
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(
                  icon: Icons.downloading_rounded,
                  title: 'Antrean Aktif',
                  count: activeQueueItems.length +
                      (isDirectDownloadActive ? 1 : 0),
                ),
                const SizedBox(height: 10),
                if (!isDirectDownloadActive && activeQueueItems.isEmpty)
                  _buildEmptyActiveCard()
                else ...[
                  if (isDirectDownloadActive && provider.trackMetadata != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildDirectActiveCard(provider),
                    ),
                  ...activeQueueItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildActiveQueueCard(item),
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: _buildSectionHeader(
                    icon: Icons.library_music_outlined,
                    title: 'Riwayat Unduhan',
                    count: completedItems.length,
                  ),
                ),
                if (completedItems.isNotEmpty)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: _textMuted,
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: _buildEmptyHistoryCard(provider),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            sliver: SliverList.separated(
              itemCount: completedItems.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = completedItems[index];
                return _buildCompletedItemCard(context, item);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required int count,
  }) {
    final hairline = Colors.black.withValues(alpha: 0.07);
    return Row(
      children: [
        Icon(icon, size: 18, color: _primaryBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: _textDark,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: _surfaceSubtle,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: hairline, width: 0.8),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: _textDark,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyActiveCard() {
    final hairline = Colors.black.withValues(alpha: 0.07);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hairline, width: 0.8),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: _textMuted,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tidak ada unduhan yang sedang berjalan.',
              style: TextStyle(color: _textMuted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectActiveCard(DownloaderProvider provider) {
    final track = provider.trackMetadata!;
    final pct = (provider.progress * 100).round();
    final hairline = Colors.black.withValues(alpha: 0.07);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _primaryBlue.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _surfaceSubtle,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: hairline, width: 0.8),
                ),
                clipBehavior: Clip.antiAlias,
                child: track.coverUrl.isNotEmpty
                    ? Image.network(
                        track.coverUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildPlaceholder(48),
                      )
                    : _buildPlaceholder(48),
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
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${track.artist} • ${provider.selectedFolder}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$pct%',
                style: const TextStyle(
                  color: _primaryBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: provider.progress.clamp(0.0, 1.0),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
            backgroundColor: _surfaceSubtle,
            valueColor: const AlwaysStoppedAnimation<Color>(_primaryBlue),
          ),
          const SizedBox(height: 8),
          Text(
            provider.statusMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveQueueCard(DownloadItem item) {
    final isQueued = item.status == DownloadItemStatus.queued;
    final pct = (item.progress * 100).round();
    final hairline = Colors.black.withValues(alpha: 0.07);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hairline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _surfaceSubtle,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: hairline, width: 0.8),
                ),
                clipBehavior: Clip.antiAlias,
                child: item.metadata.coverUrl.isNotEmpty
                    ? Image.network(
                        item.metadata.coverUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildPlaceholder(48),
                      )
                    : _buildPlaceholder(48),
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
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.metadata.artist} • ${item.targetFolderName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12.5,
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
                      color: isQueued ? _amberDot : _primaryBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isQueued ? 'Menunggu' : '$pct%',
                    style: TextStyle(
                      color: isQueued ? _amberDot : _primaryBlue,
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
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
              backgroundColor: _surfaceSubtle,
              valueColor: const AlwaysStoppedAnimation<Color>(_primaryBlue),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            item.statusDetail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedItemCard(BuildContext context, DownloadItem item) {
    final isFailed = item.status == DownloadItemStatus.failed;
    final hasLyrics = (item.metadata.cleanPlainLyrics != null &&
            item.metadata.cleanPlainLyrics!.trim().isNotEmpty) ||
        item.metadata.hasSyncedLyrics;
    final hairline = Colors.black.withValues(alpha: 0.07);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hairline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Cover Art 52x52 (6px micro-radius)
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _surfaceSubtle,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: hairline, width: 0.8),
                ),
                clipBehavior: Clip.antiAlias,
                child: item.metadata.coverUrl.isNotEmpty
                    ? Image.network(
                        item.metadata.coverUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildPlaceholder(52),
                      )
                    : _buildPlaceholder(52),
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
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.metadata.artist} • ${item.metadata.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Modern Dot Indicators (Folder + Lirik Tersedia)
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isFailed ? _redDot : _primaryBlue,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isFailed ? 'Gagal' : item.targetFolderName,
                              style: TextStyle(
                                color: isFailed ? _redDot : _textDark,
                                fontSize: 11.5,
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
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: _emeraldDot,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Lirik Tersedia',
                                style: TextStyle(
                                  color: _emeraldDot,
                                  fontSize: 11.5,
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
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit Info & Lirik',
                      style: IconButton.styleFrom(
                        backgroundColor: _surfaceSubtle,
                        minimumSize: const Size(34, 34),
                        padding: const EdgeInsets.all(7),
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
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _surfaceSubtle,
                        foregroundColor: _textDark,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 7,
                        ),
                        side: BorderSide(color: hairline, width: 0.8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: () => onMoveFolder(provider, item),
                      icon: const Icon(
                        Icons.drive_file_move_outlined,
                        size: 15,
                        color: _primaryBlue,
                      ),
                      label: const Text(
                        'Pindah',
                        style: TextStyle(
                          fontSize: 11.5,
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
                color: _redDot,
                fontSize: 11.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyHistoryCard(DownloaderProvider provider) {
    final counts = provider.folderSongCounts;
    final hairline = Colors.black.withValues(alpha: 0.07);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hairline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: _textMuted),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Belum ada riwayat unduhan.',
                  style: TextStyle(
                    color: _textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          if (provider.availableFolders.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: hairline),
            const SizedBox(height: 10),
            const Text(
              'Koleksi Folder:',
              style: TextStyle(
                color: _textMuted,
                fontSize: 12,
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
                    color: _surfaceSubtle,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: hairline, width: 0.8),
                  ),
                  child: Text(
                    '$folder: $count Lagu',
                    style: const TextStyle(
                      color: _textDark,
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

  Widget _buildPlaceholder(double size) {
    return Container(
      width: size,
      height: size,
      color: _surfaceSubtle,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        color: _textMuted,
        size: size * 0.38,
      ),
    );
  }
}

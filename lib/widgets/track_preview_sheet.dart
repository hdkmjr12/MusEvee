import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/downloader_provider.dart';
import '../services/romaji_service.dart';
import '../theme/musevee_palette.dart';
import 'tag_editor_sheet.dart';

class TrackPreviewSheet extends StatefulWidget {
  final Future<void> Function(DownloaderProvider provider) onCreateNewFolder;

  const TrackPreviewSheet({
    super.key,
    required this.onCreateNewFolder,
  });

  static Future<void> show(
    BuildContext context, {
    required Future<void> Function(DownloaderProvider provider)
        onCreateNewFolder,
  }) async {
    final provider = context.read<DownloaderProvider>();
    final palette = context.palette;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: palette.surfaceCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => TrackPreviewSheet(onCreateNewFolder: onCreateNewFolder),
      );
    } finally {
      await provider.stopPreviewAudio();
    }
  }

  @override
  State<TrackPreviewSheet> createState() => _TrackPreviewSheetState();
}

class _TrackPreviewSheetState extends State<TrackPreviewSheet> {
  bool _showYoutubeCandidates = false;
  bool _showLyricsCandidates = false;

  void _toggleYoutubePicker(DownloaderProvider provider) {
    setState(() {
      _showYoutubeCandidates = !_showYoutubeCandidates;
    });
    if (_showYoutubeCandidates &&
        provider.youtubeCandidates.isEmpty &&
        !provider.isSearchingYoutubeCandidates) {
      provider.loadYoutubeCandidates();
    }
  }

  void _toggleLyricsPicker(DownloaderProvider provider) {
    setState(() {
      _showLyricsCandidates = !_showLyricsCandidates;
    });
    if (_showLyricsCandidates &&
        provider.lyricsCandidates.isEmpty &&
        !provider.isSearchingLyricsCandidates) {
      provider.loadLyricsCandidates();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hairline = palette.hairline;

    return Consumer<DownloaderProvider>(
      builder: (context, provider, _) {
        final track = provider.trackMetadata;
        if (track == null) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    provider.statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final duplicateFolder = provider.duplicateFolderFor(track);
        final isFetchingLyrics =
            provider.state == DownloaderState.fetchingLyrics;
        final isDownloadingNow =
            provider.state == DownloaderState.downloadingAudio ||
            provider.state == DownloaderState.taggingAudio;

        final hasSynced = track.hasSyncedLyrics;
        final useSynced = provider.preferSyncedLyrics && hasSynced;
        final previewLyricsText = useSynced
            ? (track.normalizedSyncedLyrics ?? '')
            : (track.cleanPlainLyrics ?? track.normalizedSyncedLyrics ?? '');
        final hasAnyLyrics = previewLyricsText.trim().isNotEmpty;

        final previewUrl = track.previewAudioUrl?.trim() ?? '';
        final hasPreviewAudio = previewUrl.isNotEmpty;
        final isPlayingThisPreview =
            provider.isPreviewPlaying && provider.activePreviewUrl == previewUrl;

        final hasJapanese = RomajiService.trackHasJapanese(track);
        final hasJapaneseLyrics = RomajiService.trackLyricsHasJapanese(track) ||
            RomajiService.containsJapanese(previewLyricsText);
        final selectedCandidate = provider.selectedYoutubeCandidate;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: SingleChildScrollView(
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

                  // 1. HEADER LAGU (Cover Art 88x88 + Preview 30s + Metadata + Auto-Romaji)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: palette.surfaceSubtle,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: hairline, width: 0.8),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: track.coverUrl.isNotEmpty
                                ? Image.network(
                                    track.coverUrl,
                                    width: 88,
                                    height: 88,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            _buildPlaceholder(88, palette),
                                  )
                                : _buildPlaceholder(88, palette),
                          ),
                          if (hasPreviewAudio)
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Material(
                                color: isPlayingThisPreview
                                    ? palette.accent
                                    : palette.surfaceCard.withValues(
                                        alpha: 0.94,
                                      ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  side: BorderSide(
                                    color: hairline,
                                    width: 0.8,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () =>
                                      provider.togglePreviewAudio(previewUrl),
                                  child: Padding(
                                    padding: const EdgeInsets.all(5),
                                    child: Icon(
                                      isPlayingThisPreview
                                          ? Icons.stop_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 19,
                                      color: isPlayingThisPreview
                                          ? Colors.white
                                          : palette.accent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.accent,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${track.album} • ${track.releaseYear} • ${track.formattedDuration}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textMuted,
                                fontSize: 12,
                              ),
                            ),
                            if (duplicateFolder != null ||
                                hasJapanese ||
                                isPlayingThisPreview) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 10,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (isPlayingThisPreview)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: palette.accent,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Memutar Cuplikan...',
                                          style: TextStyle(
                                            color: palette.accent,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (duplicateFolder != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: MusEveePalette.amber,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            'Sudah ada di $duplicateFolder',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: MusEveePalette.amber,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (hasJapanese)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: provider.isRomanizing
                                          ? null
                                          : () async {
                                              final ok = await provider
                                                  .autoRomanizeCurrentTrack();
                                              if (ok && context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Judul & Artis dikonversi ke Romaji.',
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: palette.surfaceSubtle,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: hairline,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          provider.isRomanizing
                                              ? 'Mengonversi...'
                                              : '✨ Auto-Romaji',
                                          style: TextStyle(
                                            color: palette.accent,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // 1B. PEMILIH SUMBER YOUTUBE MANUAL
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surfaceSubtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: hairline, width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.ondemand_video_rounded,
                              size: 16,
                              color: palette.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                selectedCandidate == null
                                    ? 'Sumber Audio: Otomatis'
                                    : 'Sumber: ${selectedCandidate.title} (${selectedCandidate.formattedDuration})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => _toggleYoutubePicker(provider),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Text(
                                  _showYoutubeCandidates
                                      ? 'Tutup'
                                      : 'Ganti Sumber',
                                  style: TextStyle(
                                    color: palette.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_showYoutubeCandidates) ...[
                          const SizedBox(height: 8),
                          Divider(height: 1, color: hairline),
                          const SizedBox(height: 8),
                          if (provider.isSearchingYoutubeCandidates)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: palette.accent,
                                  ),
                                ),
                              ),
                            )
                          else if (provider.youtubeCandidates.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                'Sumber lain tidak ditemukan, menggunakan pilihan otomatis.',
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            )
                          else
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 165),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: provider.youtubeCandidates.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 4),
                                itemBuilder: (context, idx) {
                                  final cand = provider.youtubeCandidates[idx];
                                  final isChosen = selectedCandidate != null
                                      ? selectedCandidate.videoId ==
                                          cand.videoId
                                      : cand.isBestMatch;
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () {
                                      provider.selectYoutubeCandidate(cand);
                                      setState(() {
                                        _showYoutubeCandidates = false;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isChosen
                                            ? palette.accent.withValues(
                                                alpha: 0.08,
                                              )
                                            : palette.surfaceCard,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isChosen
                                              ? palette.accent
                                              : hairline,
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isChosen
                                                ? Icons.radio_button_checked
                                                : Icons.radio_button_off,
                                            size: 15,
                                            color: isChosen
                                                ? palette.accent
                                                : palette.textMuted,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  cand.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: palette.textPrimary,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: -0.2,
                                                  ),
                                                ),
                                                Text(
                                                  '${cand.channelName} • ${cand.formattedDuration}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: palette.textMuted,
                                                    fontSize: 11,
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
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 2. SEKSI LIRIK & EDIT INFO (Modern Dot Indicator + Micro-Radius)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: palette.surfaceSubtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: hairline, width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isFetchingLyrics)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 11,
                                    height: 11,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                      color: palette.accent,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Mengambil lirik...',
                                    style: TextStyle(
                                      color: palette.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            else if (hasAnyLyrics)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: MusEveePalette.emerald,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Lirik Tersedia',
                                    style: TextStyle(
                                      color: MusEveePalette.emerald,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (provider.selectedLyricsCandidate !=
                                      null) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      provider
                                          .selectedLyricsCandidate!.languageTag,
                                      style: TextStyle(
                                        color: palette.accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            else
                              Text(
                                'Lirik Lagu',
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            const Spacer(),
                            if (!isFetchingLyrics)
                              InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => _toggleLyricsPicker(provider),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    _showLyricsCandidates
                                        ? 'Tutup'
                                        : 'Ganti Lirik',
                                    style: TextStyle(
                                      color: palette.accent,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 4),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: palette.surfaceCard,
                                minimumSize: const Size(0, 32),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                side: BorderSide(color: hairline, width: 0.8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              onPressed: isFetchingLyrics
                                  ? null
                                  : () => TagEditorSheet.show(
                                        context,
                                        provider: provider,
                                        track: track,
                                      ),
                              icon: Icon(
                                Icons.edit_outlined,
                                size: 14,
                                color: palette.textPrimary,
                              ),
                              label: Text(
                                'Edit Info & Lirik',
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Expandable manual LRCLIB Lyrics Candidate Picker ("Ganti Lirik")
                        if (_showLyricsCandidates) ...[
                          const SizedBox(height: 8),
                          Divider(height: 1, color: hairline),
                          const SizedBox(height: 8),
                          if (provider.isSearchingLyricsCandidates)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: palette.accent,
                                  ),
                                ),
                              ),
                            )
                          else if (provider.lyricsCandidates.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                'Versi lirik lain tidak ditemukan di LRCLIB.',
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            )
                          else
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 195),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: provider.lyricsCandidates.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 5),
                                itemBuilder: (context, idx) {
                                  final cand = provider.lyricsCandidates[idx];
                                  final isChosen =
                                      provider.selectedLyricsCandidate != null
                                          ? provider.selectedLyricsCandidate!
                                                  .id ==
                                              cand.id
                                          : idx == 0;
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () {
                                      provider.selectLyricsCandidate(cand);
                                      setState(() {
                                        _showLyricsCandidates = false;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isChosen
                                            ? palette.accent.withValues(
                                                alpha: 0.08,
                                              )
                                            : palette.surfaceCard,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isChosen
                                              ? palette.accent
                                              : hairline,
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Icon(
                                              isChosen
                                                  ? Icons.radio_button_checked
                                                  : Icons.radio_button_off,
                                              size: 15,
                                              color: isChosen
                                                  ? palette.accent
                                                  : palette.textMuted,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      cand.languageTag,
                                                      style: TextStyle(
                                                        color: palette.accent,
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      '${cand.hasSynced ? 'LRC' : 'Biasa'} • ${cand.formattedDuration}',
                                                      style: TextStyle(
                                                        color:
                                                            palette.textMuted,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  cand.previewTwoLines,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: palette.textPrimary,
                                                    fontSize: 11.5,
                                                    height: 1.35,
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
                              ),
                            ),
                        ],

                        // Toggle: Lirik Berjalan | Lirik Biasa + Auto-Romaji Lirik
                        if (!isFetchingLyrics && hasAnyLyrics) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: palette.surfaceCard,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: hairline,
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildLyricsModeSegment(
                                      palette: palette,
                                      label: 'Lirik Berjalan',
                                      selected: useSynced,
                                      enabled: hasSynced,
                                      onTap: hasSynced
                                          ? () =>
                                              provider.setPreferSyncedLyrics(
                                                true,
                                              )
                                          : null,
                                    ),
                                    _buildLyricsModeSegment(
                                      palette: palette,
                                      label: 'Lirik Biasa',
                                      selected: !useSynced,
                                      enabled: true,
                                      onTap: () =>
                                          provider.setPreferSyncedLyrics(
                                        false,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              if (hasJapaneseLyrics)
                                InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: provider.isRomanizing
                                      ? null
                                      : () async {
                                          final ok = await provider
                                              .autoRomanizeCurrentLyrics();
                                          if (ok && context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Lirik berhasil dikonversi ke Romaji.',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: palette.surfaceCard,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: hairline,
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      provider.isRomanizing
                                          ? 'Mengonversi...'
                                          : '✨ Auto-Romaji',
                                      style: TextStyle(
                                        color: palette.accent,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 8),
                        Text(
                          isFetchingLyrics
                              ? 'Mengambil lirik...'
                              : hasAnyLyrics
                                  ? previewLyricsText
                                  : 'Belum ada lirik. Ketuk "Edit Info & Lirik" untuk mengisi manual.',
                          maxLines: 8,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hasAnyLyrics
                                ? palette.textPrimary
                                : palette.textMuted,
                            fontSize: 12,
                            height: 1.45,
                            fontStyle: hasAnyLyrics
                                ? FontStyle.normal
                                : FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 3. PEMILIH FOLDER TUJUAN (ChoiceChip Micro-Radius 6px)
                  Text(
                    'Folder Tujuan:',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...provider.availableFolders.map((folder) {
                        final isSelected = folder == provider.selectedFolder;
                        return ChoiceChip(
                          selected: isSelected,
                          showCheckmark: false,
                          backgroundColor: palette.surfaceSubtle,
                          selectedColor: palette.accent,
                          side: BorderSide(
                            color: isSelected ? palette.accent : hairline,
                            width: 0.8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.folder_rounded
                                    : Icons.folder_outlined,
                                size: 15,
                                color: isSelected
                                    ? Colors.white
                                    : palette.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                folder,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : palette.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          onSelected: (_) => provider.selectFolder(folder),
                        );
                      }),
                      ActionChip(
                        backgroundColor: palette.surfaceCard,
                        side: BorderSide(color: hairline, width: 0.8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        avatar: Icon(
                          Icons.add_rounded,
                          size: 15,
                          color: palette.accent,
                        ),
                        label: Text(
                          'Baru',
                          style: TextStyle(
                            color: palette.accent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: () => widget.onCreateNewFolder(provider),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // 4. TOMBOL AKSI UTAMA (BorderRadius 10px)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: isFetchingLyrics
                          ? null
                          : () {
                              final selectedFolder = provider.selectedFolder;
                              Navigator.of(context).pop();
                              if (isDownloadingNow) {
                                provider.enqueueTrack(
                                  track,
                                  folderName: selectedFolder,
                                  preferSynced: provider.preferSyncedLyrics,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Ditambahkan ke antrean ($selectedFolder): ${track.title}',
                                    ),
                                  ),
                                );
                              } else {
                                provider.downloadTrack();
                              }
                            },
                      icon: Icon(
                        isDownloadingNow
                            ? Icons.playlist_add_rounded
                            : Icons.download_rounded,
                        size: 19,
                      ),
                      label: Text(
                        isDownloadingNow
                            ? 'Masukkan ke Antrean'
                            : 'Simpan ke ${provider.selectedFolder}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),

                  if (!isDownloadingNow) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: palette.textMuted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: isFetchingLyrics
                            ? null
                            : () {
                                final selectedFolder = provider.selectedFolder;
                                Navigator.of(context).pop();
                                provider.enqueueTrack(
                                  track,
                                  folderName: selectedFolder,
                                  preferSynced: provider.preferSyncedLyrics,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Ditambahkan ke antrean ($selectedFolder): ${track.title}',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.playlist_add_rounded, size: 17),
                        label: const Text(
                          'Masukkan ke Antrean',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLyricsModeSegment({
    required MusEveePalette palette,
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? palette.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : enabled
                    ? palette.textPrimary
                    : palette.textMuted,
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
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

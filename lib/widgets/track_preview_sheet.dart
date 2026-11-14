import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/downloader_provider.dart';
import '../services/romaji_service.dart';
import '../theme/musevee_palette.dart';
import '../utils/app_strings.dart';
import 'pressable_scale.dart';
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
        backgroundColor: palette.nowPlayingBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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
    SystemLocaleScope.watch(context);
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
                      color: palette.nowPlayingPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    provider.statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
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
        final isPlayingThisPreview = provider.isPreviewPlaying &&
            provider.activePreviewUrl == previewUrl;

        final hasJapanese = RomajiService.trackHasJapanese(track);
        final hasJapaneseLyrics = RomajiService.trackLyricsHasJapanese(track) ||
            RomajiService.containsJapanese(previewLyricsText);
        final selectedCandidate = provider.selectedYoutubeCandidate;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag Handle (38x4px)
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.textMuted.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 1. HEADER LAGU (Cover Art + Play Preview + Title/Artist/Album•Year•Duration + Edit Pencil)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              color: palette.surfaceSubtle,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: track.coverUrl.isNotEmpty
                                ? Image.network(
                                    track.coverUrl,
                                    width: 92,
                                    height: 92,
                                    fit: BoxFit.cover,
                                    cacheWidth: 240,
                                    cacheHeight: 240,
                                    gaplessPlayback: true,
                                    errorBuilder: (
                                      context,
                                      error,
                                      stackTrace,
                                    ) =>
                                        _buildPlaceholder(92, palette),
                                  )
                                : _buildPlaceholder(92, palette),
                          ),
                          if (hasPreviewAudio)
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: MographSpringTap(
                                pressedScale: 0.86,
                                child: Material(
                                  key: const ValueKey('track_preview_play_btn'),
                                  color: isPlayingThisPreview
                                      ? palette.nowPlayingPrimary
                                      : palette.surfaceCard.withValues(
                                          alpha: 0.96,
                                        ),
                                  borderRadius: BorderRadius.circular(7),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () =>
                                        provider.togglePreviewAudio(previewUrl),
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: Center(
                                        child: MographAnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          child: isPlayingThisPreview
                                              ? Icon(
                                                  Icons.stop_rounded,
                                                  key: const ValueKey(
                                                    'preview_stop_icon',
                                                  ),
                                                  size: 16,
                                                  color: palette
                                                      .nowPlayingOnPrimary,
                                                )
                                              : Icon(
                                                  Icons.play_arrow_rounded,
                                                  key: const ValueKey(
                                                    'preview_play_icon',
                                                  ),
                                                  size: 20,
                                                  color: palette.textPrimary,
                                                ),
                                        ),
                                      ),
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
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              track.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: palette.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                                height: 1.22,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: palette.textMuted,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${track.album} • ${track.releaseYear} • ${track.formattedDuration}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: palette.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                height: 1.25,
                              ),
                            ),
                            if (duplicateFolder != null ||
                                hasJapanese ||
                                isPlayingThisPreview) ...[
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 8,
                                runSpacing: 5,
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
                                            color: palette.nowPlayingPrimary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          AppStrings.previewPlayingSample,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            color: palette.textPrimary,
                                            fontSize: 11,
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
                                        const SizedBox(width: 5),
                                        Flexible(
                                          child: Text(
                                            AppStrings.previewAlreadyInFolder(
                                              duplicateFolder,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontFamily: 'Poppins',
                                              color: MusEveePalette.amber,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (hasJapanese)
                                    PressableScale(
                                      enabled: !provider.isRomanizing,
                                      pressedScale: 0.92,
                                      onTap: () async {
                                        final ok = await provider
                                            .autoRomanizeCurrentTrack();
                                        if (ok && context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                AppStrings
                                                    .previewMetadataRomajiConverted,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: palette.surfaceSubtle,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          provider.isRomanizing
                                              ? AppStrings
                                                  .previewConvertingRomaji
                                              : AppStrings.previewAutoRomaji,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            color: palette.textPrimary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
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
                      const SizedBox(width: 10),
                      Tooltip(
                        message: AppStrings.previewEditInfoTooltip,
                        child: PressableScale(
                          key: const ValueKey('track_preview_edit_btn'),
                          enabled: !isFetchingLyrics,
                          pressedScale: 0.90,
                          onTap: () => TagEditorSheet.show(
                            context,
                            provider: provider,
                            track: track,
                          ),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: palette.surfaceSubtle,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Image.asset(
                              'assets/pencil.png',
                              width: 17,
                              height: 17,
                              color: isFetchingLyrics
                                  ? palette.textMuted
                                  : palette.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // 2. BARIS SUMBER AUDIO (Audio source: Automatic | Change Source)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surfaceSubtle,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Image.asset(
                              'assets/audio.png',
                              width: 17,
                              height: 17,
                              color: palette.textPrimary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                selectedCandidate == null
                                    ? AppStrings.previewAudioSourceAuto
                                    : AppStrings.previewAudioSourceCustom(
                                        selectedCandidate.title,
                                        selectedCandidate.formattedDuration,
                                      ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: palette.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            PressableScale(
                              key: const ValueKey(
                                'track_preview_change_source_btn',
                              ),
                              pressedScale: 0.94,
                              onTap: () => _toggleYoutubePicker(provider),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: Text(
                                  _showYoutubeCandidates
                                      ? AppStrings.previewClose
                                      : AppStrings.previewChangeSource,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    color: palette.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_showYoutubeCandidates) ...[
                          const SizedBox(height: 10),
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
                                    color: palette.nowPlayingPrimary,
                                  ),
                                ),
                              ),
                            )
                          else if (provider.youtubeCandidates.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                AppStrings.previewNoOtherSources,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
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
                                    const SizedBox(height: 5),
                                itemBuilder: (context, idx) {
                                  final cand = provider.youtubeCandidates[idx];
                                  final isChosen = selectedCandidate != null
                                      ? selectedCandidate.videoId ==
                                          cand.videoId
                                      : cand.isBestMatch;
                                  return MographSpringTap(
                                    pressedScale: 0.97,
                                    child: Material(
                                      color: palette.surfaceCard,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(
                                          color: isChosen
                                              ? palette.nowPlayingPrimary
                                              : hairline,
                                          width: isChosen ? 1.2 : 0.8,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: () {
                                          provider.selectYoutubeCandidate(cand);
                                          setState(() {
                                            _showYoutubeCandidates = false;
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 7,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                isChosen
                                                    ? Icons.radio_button_checked
                                                    : Icons.radio_button_off,
                                                size: 16,
                                                color: isChosen
                                                    ? palette.nowPlayingPrimary
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
                                                        fontFamily: 'Poppins',
                                                        color:
                                                            palette.textPrimary,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    Text(
                                                      '${cand.channelName} • ${cand.formattedDuration}',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontFamily: 'Poppins',
                                                        color:
                                                            palette.textMuted,
                                                        fontSize: 11,
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
                                },
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 3. KOTAK LIRIK MONOKROM (Segmented Synced/Plain + Language Tag + Change lyrics)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: palette.surfaceSubtle,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Segmented Toggle: [Synced lyrics | Plain lyrics]
                            Flexible(
                              flex: 3,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: palette.surfaceCard,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildLyricsModeSegment(
                                        palette: palette,
                                        label: AppStrings.previewSyncedLyrics,
                                        selected: useSynced,
                                        enabled: hasSynced && !isFetchingLyrics,
                                        onTap: (hasSynced && !isFetchingLyrics)
                                            ? () => provider
                                                .setPreferSyncedLyrics(true)
                                            : null,
                                      ),
                                      _buildLyricsModeSegment(
                                        palette: palette,
                                        label: AppStrings.previewPlainLyrics,
                                        selected: !useSynced,
                                        enabled: !isFetchingLyrics,
                                        onTap: !isFetchingLyrics
                                            ? () => provider
                                                .setPreferSyncedLyrics(false)
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: isFetchingLyrics
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 1.8,
                                                color:
                                                    palette.nowPlayingPrimary,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              AppStrings.previewFetchingLyrics,
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                color: palette.textMuted,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (provider
                                                    .selectedLyricsCandidate !=
                                                null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 6,
                                                ),
                                                child: Text(
                                                  AppStrings
                                                      .formatLyricsLanguageTag(
                                                    provider
                                                        .selectedLyricsCandidate!
                                                        .languageTag,
                                                  ),
                                                  maxLines: 1,
                                                  style: TextStyle(
                                                    fontFamily: 'Poppins',
                                                    color: palette.textMuted,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            PressableScale(
                                              key: const ValueKey(
                                                'track_preview_change_lyrics_btn',
                                              ),
                                              pressedScale: 0.94,
                                              onTap: () =>
                                                  _toggleLyricsPicker(provider),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 2,
                                                  vertical: 3,
                                                ),
                                                child: Text(
                                                  _showLyricsCandidates
                                                      ? AppStrings.previewClose
                                                      : AppStrings
                                                          .previewChangeLyrics,
                                                  maxLines: 1,
                                                  style: TextStyle(
                                                    fontFamily: 'Poppins',
                                                    color: palette.textPrimary,
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w600,
                                                  ),
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

                        // Contextual Auto-Romaji action for Japanese lyrics
                        if (!isFetchingLyrics &&
                            hasAnyLyrics &&
                            hasJapaneseLyrics) ...[
                          const SizedBox(height: 8),
                          PressableScale(
                            enabled: !provider.isRomanizing,
                            pressedScale: 0.94,
                            onTap: () async {
                              final ok =
                                  await provider.autoRomanizeCurrentLyrics();
                              if (ok && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      AppStrings.previewRomajiConverted,
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: palette.surfaceCard,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                provider.isRomanizing
                                    ? AppStrings.previewConvertingRomaji
                                    : AppStrings.previewAutoRomaji,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: palette.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],

                        // Expandable manual LRCLIB Lyrics Candidate Picker
                        if (_showLyricsCandidates) ...[
                          const SizedBox(height: 10),
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
                                    color: palette.nowPlayingPrimary,
                                  ),
                                ),
                              ),
                            )
                          else if (provider.lyricsCandidates.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                AppStrings.previewNoLyricsCandidates,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
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
                                  return MographSpringTap(
                                    pressedScale: 0.97,
                                    child: Material(
                                      color: palette.surfaceCard,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(
                                          color: isChosen
                                              ? palette.nowPlayingPrimary
                                              : hairline,
                                          width: isChosen ? 1.2 : 0.8,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: () {
                                          provider.selectLyricsCandidate(cand);
                                          setState(() {
                                            _showLyricsCandidates = false;
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 7,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 2,
                                                ),
                                                child: Icon(
                                                  isChosen
                                                      ? Icons
                                                          .radio_button_checked
                                                      : Icons.radio_button_off,
                                                  size: 16,
                                                  color: isChosen
                                                      ? palette
                                                          .nowPlayingPrimary
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
                                                          AppStrings
                                                              .formatLyricsLanguageTag(
                                                            cand.languageTag,
                                                          ),
                                                          style: TextStyle(
                                                            fontFamily:
                                                                'Poppins',
                                                            color: palette
                                                                .textPrimary,
                                                            fontSize: 11.5,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        Text(
                                                          '${cand.hasSynced ? 'LRC' : (AppStrings.isIndonesian ? 'Biasa' : 'Plain')} • ${cand.formattedDuration}',
                                                          style: TextStyle(
                                                            fontFamily:
                                                                'Poppins',
                                                            color: palette
                                                                .textMuted,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w500,
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
                                                        fontFamily: 'Poppins',
                                                        color:
                                                            palette.textPrimary,
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
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],

                        const SizedBox(height: 10),
                        Text(
                          isFetchingLyrics
                              ? AppStrings.previewFetchingLyrics
                              : hasAnyLyrics
                                  ? previewLyricsText
                                  : AppStrings.previewNoLyricsPlaceholder,
                          maxLines: 9,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: hasAnyLyrics
                                ? palette.textPrimary
                                : palette.textMuted,
                            fontSize: 11.5,
                            height: 1.5,
                            fontStyle: hasAnyLyrics
                                ? FontStyle.normal
                                : FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 4. FOLDER DESTINATION (Monochrome Chips + New folder)
                  Text(
                    AppStrings.previewFolderDestination,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: palette.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...provider.availableFolders.map((folder) {
                        final isSelected = folder == provider.selectedFolder;
                        return PressableScale(
                          pressedScale: 0.94,
                          onTap: () => provider.selectFolder(folder),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? palette.nowPlayingPrimary
                                  : palette.surfaceSubtle,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/folder_picker.png',
                                  width: 15,
                                  height: 15,
                                  color: isSelected
                                      ? palette.nowPlayingOnPrimary
                                      : palette.textPrimary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  folder,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    color: isSelected
                                        ? palette.nowPlayingOnPrimary
                                        : palette.textPrimary,
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      PressableScale(
                        key: const ValueKey('track_preview_new_folder_btn'),
                        pressedScale: 0.94,
                        onTap: () => widget.onCreateNewFolder(provider),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: palette.surfaceCard,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: hairline, width: 1.0),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/add.png',
                                width: 13,
                                height: 13,
                                color: palette.textPrimary,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                AppStrings.previewNewFolder,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: palette.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 5. PRIMARY & SECONDARY ACTION BUTTONS (Save to ... / Add to download list)
                  PressableScale(
                    enabled: !isFetchingLyrics,
                    pressedScale: 0.97,
                    onTap: () {
                      final selectedFolder = provider.selectedFolder;
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      Navigator.of(context).pop();
                      if (isDownloadingNow) {
                        provider.enqueueTrack(
                          track,
                          folderName: selectedFolder,
                          preferSynced: provider.preferSyncedLyrics,
                        );
                        messenger?.showSnackBar(
                          SnackBar(
                            content: Text(
                              AppStrings.previewAddedToQueue(
                                selectedFolder,
                                track.title,
                              ),
                            ),
                          ),
                        );
                      } else {
                        provider.downloadTrack();
                      }
                    },
                    child: Container(
                      key: const ValueKey('track_preview_save_btn'),
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isFetchingLyrics
                            ? palette.nowPlayingPrimary.withValues(alpha: 0.4)
                            : palette.nowPlayingPrimary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            isDownloadingNow
                                ? 'assets/add-list.png'
                                : 'assets/download.png',
                            width: 18,
                            height: 18,
                            color: palette.nowPlayingOnPrimary,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              isDownloadingNow
                                  ? AppStrings.previewAddToDownloadList
                                  : AppStrings.previewSaveToFolder(
                                      provider.selectedFolder,
                                    ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: palette.nowPlayingOnPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (!isDownloadingNow) ...[
                    const SizedBox(height: 8),
                    PressableScale(
                      enabled: !isFetchingLyrics,
                      pressedScale: 0.96,
                      onTap: () {
                        final selectedFolder = provider.selectedFolder;
                        final messenger = ScaffoldMessenger.maybeOf(context);
                        Navigator.of(context).pop();
                        provider.enqueueTrack(
                          track,
                          folderName: selectedFolder,
                          preferSynced: provider.preferSyncedLyrics,
                        );
                        messenger?.showSnackBar(
                          SnackBar(
                            content: Text(
                              AppStrings.previewAddedToQueue(
                                selectedFolder,
                                track.title,
                              ),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        key: const ValueKey('track_preview_add_list_btn'),
                        width: double.infinity,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/add-list.png',
                              width: 18,
                              height: 18,
                              color: isFetchingLyrics
                                  ? palette.textMuted
                                  : palette.textPrimary,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                AppStrings.previewAddToDownloadList,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: isFetchingLyrics
                                      ? palette.textMuted
                                      : palette.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
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
    return PressableScale(
      enabled: enabled && onTap != null,
      pressedScale: 0.94,
      onTap: onTap ?? () {},
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? palette.nowPlayingPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: selected
                ? palette.nowPlayingOnPrimary
                : enabled
                    ? palette.textPrimary
                    : palette.textMuted,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
      child: Image.asset(
        'assets/album.png',
        width: size * 0.42,
        height: size * 0.42,
        color: palette.textMuted,
      ),
    );
  }
}

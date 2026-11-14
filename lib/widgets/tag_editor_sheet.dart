import 'package:flutter/material.dart';

import '../models/download_item.dart';
import '../models/local_song.dart';
import '../models/track_metadata.dart';
import '../providers/downloader_provider.dart';
import '../providers/local_music_provider.dart';
import '../services/lyrics_service.dart';
import '../services/romaji_service.dart';
import '../theme/musevee_palette.dart';
import '../utils/app_strings.dart';
import 'pressable_scale.dart';

class TagEditorSheet extends StatefulWidget {
  final DownloaderProvider provider;
  final TrackMetadata track;
  final DownloadItem? historyItem;
  final LocalSong? localSong;
  final LocalMusicProvider? localProvider;

  const TagEditorSheet({
    super.key,
    required this.provider,
    required this.track,
    this.historyItem,
    this.localSong,
    this.localProvider,
  });

  static Future<void> show(
    BuildContext context, {
    required DownloaderProvider provider,
    required TrackMetadata track,
  }) {
    final palette = context.palette;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.nowPlayingBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => TagEditorSheet(provider: provider, track: track),
    );
  }

  static Future<void> showForHistoryItem(
    BuildContext context, {
    required DownloaderProvider provider,
    required DownloadItem item,
  }) {
    final palette = context.palette;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.nowPlayingBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => TagEditorSheet(
        provider: provider,
        track: item.metadata,
        historyItem: item,
      ),
    );
  }

  static Future<void> showForLocalSong(
    BuildContext context, {
    required DownloaderProvider downloaderProvider,
    required LocalMusicProvider localProvider,
    required LocalSong song,
  }) async {
    final hydratedSong = await localProvider.ensureSongLyricsLoaded(song);
    if (!context.mounted) return;
    final palette = context.palette;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.nowPlayingBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => TagEditorSheet(
        provider: downloaderProvider,
        localProvider: localProvider,
        localSong: hydratedSong,
        track: hydratedSong.toTrackMetadata(),
      ),
    );
  }

  @override
  State<TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<TagEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _yearController;
  late final TextEditingController _lyricsController;

  bool _preferSyncedLyrics = true;
  bool _isConvertingRomaji = false;
  bool _isSaving = false;
  String? _syncedLyricsOverride;
  bool _showLyricsCandidates = false;
  String? _selectedCandidateId;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.track.title);
    _artistController = TextEditingController(text: widget.track.artist);
    _albumController = TextEditingController(text: widget.track.album);
    _yearController = TextEditingController(text: widget.track.releaseYear);

    if (widget.localSong != null) {
      _preferSyncedLyrics = widget.localSong!.hasSyncedLyrics;
    } else if (widget.historyItem != null) {
      _preferSyncedLyrics = widget.historyItem!.preferSyncedLyrics;
    } else {
      _preferSyncedLyrics = widget.provider.preferSyncedLyrics;
    }
    _selectedCandidateId = widget.provider.selectedLyricsCandidate?.id;

    final initialLyrics = (_preferSyncedLyrics && widget.track.hasSyncedLyrics)
        ? (widget.track.normalizedSyncedLyrics ?? '')
        : (widget.track.cleanPlainLyrics ??
            widget.track.normalizedSyncedLyrics ??
            '');
    _lyricsController = TextEditingController(text: initialLyrics);

    if (widget.localSong != null &&
        widget.localProvider != null &&
        widget.localSong!.hasLyrics &&
        !widget.localSong!.isLyricsLoadedInMemory) {
      widget.localProvider!.ensureSongLyricsLoaded(widget.localSong!).then((
        hydrated,
      ) {
        if (!mounted) return;
        if (_lyricsController.text.trim().isEmpty &&
            hydrated.usltLyrics != null &&
            hydrated.usltLyrics!.trim().isNotEmpty) {
          setState(() {
            _preferSyncedLyrics = hydrated.hasSyncedLyrics;
            _lyricsController.text = hydrated.usltLyrics!;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _yearController.dispose();
    _lyricsController.dispose();
    super.dispose();
  }

  bool get _hasJapaneseInFields =>
      RomajiService.containsJapanese(_titleController.text) ||
      RomajiService.containsJapanese(_artistController.text) ||
      RomajiService.containsJapanese(_albumController.text);

  bool get _canConvertLyricsToRomaji =>
      _lyricsController.text.trim().isNotEmpty ||
      RomajiService.trackLyricsHasJapanese(widget.track);

  Future<void> _toggleLyricsPicker() async {
    setState(() {
      _showLyricsCandidates = !_showLyricsCandidates;
    });
    if (_showLyricsCandidates &&
        (widget.provider.lyricsCandidates.isEmpty ||
            widget.historyItem != null ||
            widget.localSong != null) &&
        !widget.provider.isSearchingLyricsCandidates) {
      final lookupTrack = widget.track.copyWith(
        title: _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : widget.track.title,
        artist: _artistController.text.trim().isNotEmpty
            ? _artistController.text.trim()
            : widget.track.artist,
        album: _albumController.text.trim().isNotEmpty
            ? _albumController.text.trim()
            : widget.track.album,
      );
      await widget.provider.loadLyricsCandidates(forTrack: lookupTrack);
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _applyLyricsCandidate(LyricsCandidate cand) {
    final textToUse =
        cand.hasSynced ? (cand.syncedLyrics ?? '') : (cand.plainLyrics ?? '');
    if (widget.historyItem == null && widget.localSong == null) {
      widget.provider.selectLyricsCandidate(cand);
    }
    setState(() {
      _selectedCandidateId = cand.id;
      _preferSyncedLyrics = cand.hasSynced;
      _syncedLyricsOverride = cand.syncedLyrics;
      _lyricsController.text = textToUse;
      _showLyricsCandidates = false;
    });
  }

  Future<void> _convertFieldsToRomaji() async {
    if (_isConvertingRomaji) return;
    setState(() => _isConvertingRomaji = true);
    try {
      final tempTrack = widget.track.copyWith(
        title: _titleController.text,
        artist: _artistController.text,
        album: _albumController.text,
      );
      final converted =
          await widget.provider.romajiService.romanizeTrackInfo(tempTrack);
      if (!mounted) return;
      setState(() {
        _titleController.text = converted.title;
        _artistController.text = converted.artist;
        _albumController.text = converted.album;
      });
    } finally {
      if (mounted) {
        setState(() => _isConvertingRomaji = false);
      }
    }
  }

  Future<void> _convertLyricsToRomaji() async {
    if (_isConvertingRomaji) return;
    setState(() => _isConvertingRomaji = true);
    try {
      final currentEditorText = _lyricsController.text;
      final hasLrcInEditor = RegExp(
        r'\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]',
      ).hasMatch(currentEditorText);

      if (hasLrcInEditor) {
        final romanizedSynced = await widget.provider.romajiService
            .romanizeLyrics(currentEditorText);
        if (!mounted) return;
        setState(() {
          _syncedLyricsOverride = romanizedSynced;
          _preferSyncedLyrics = true;
          _lyricsController.text = romanizedSynced;
        });
      } else if (widget.track.hasSyncedLyrics &&
          RomajiService.containsJapanese(widget.track.syncedLyrics!)) {
        final romanizedSynced = await widget.provider.romajiService
            .romanizeLyrics(widget.track.syncedLyrics!);
        if (!mounted) return;
        setState(() {
          _syncedLyricsOverride = romanizedSynced;
          _preferSyncedLyrics = true;
          _lyricsController.text = romanizedSynced;
        });
      } else {
        final romanizedPlain = await widget.provider.romajiService
            .romanizeLyrics(currentEditorText);
        if (!mounted) return;
        setState(() {
          _syncedLyricsOverride = null;
          _lyricsController.text = romanizedPlain;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isConvertingRomaji = false);
      }
    }
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      if (widget.localSong != null && widget.localProvider != null) {
        await widget.localProvider!.retagLocalSong(
          song: widget.localSong!,
          title: _titleController.text,
          artist: _artistController.text,
          album: _albumController.text,
          releaseYear: _yearController.text,
          lyricsText: _lyricsController.text,
          preferSyncedLyrics: _preferSyncedLyrics,
          syncedLyrics: _syncedLyricsOverride,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.editorSavedId3(widget.localSong!.audioFormatLabel),
            ),
          ),
        );
      } else if (widget.historyItem != null) {
        await widget.provider.retagCompletedItem(
          itemId: widget.historyItem!.id,
          title: _titleController.text,
          artist: _artistController.text,
          album: _albumController.text,
          releaseYear: _yearController.text,
          lyricsText: _lyricsController.text,
          preferSyncedLyrics: _preferSyncedLyrics,
          syncedLyrics: _syncedLyricsOverride,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.editorUpdatedHistory),
          ),
        );
      } else {
        widget.provider.setPreferSyncedLyrics(_preferSyncedLyrics);
        await widget.provider.updatePreviewMetadata(
          title: _titleController.text,
          artist: _artistController.text,
          album: _albumController.text,
          releaseYear: _yearController.text,
          plainLyrics: _lyricsController.text,
          syncedLyrics: _syncedLyricsOverride,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.editorSavedMetadata),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.editorSaveFailed(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemLocaleScope.watch(context);
    final palette = context.palette;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isLocalOrHistory =
        widget.localSong != null || widget.historyItem != null;
    final hairline = palette.hairline;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, bottomInset + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.nowPlayingSecondary.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header + Auto-Romaji Chip
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: palette.surfaceSubtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: hairline, width: 0.8),
                    ),
                    alignment: Alignment.center,
                    child: Image.asset(
                      'assets/pencil.png',
                      width: 17,
                      height: 17,
                      color: palette.nowPlayingPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.editorTitle(isLocalOrHistory),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: palette.textPrimary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppStrings.editorSubtitle(
                            isLocalOrHistory,
                            formatLabel: widget.localSong?.audioFormatLabel ??
                                widget.historyItem?.audioFormatLabel,
                          ),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: palette.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_hasJapaneseInFields)
                    MographSpringTap(
                      pressedScale: 0.94,
                      enabled: !_isConvertingRomaji,
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: palette.surfaceSubtle,
                        side: BorderSide(color: hairline, width: 0.8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onPressed: _isConvertingRomaji
                            ? null
                            : _convertFieldsToRomaji,
                        label: Text(
                          _isConvertingRomaji
                              ? AppStrings.editorProcessingRomaji
                              : AppStrings.previewAutoRomaji,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: palette.nowPlayingPrimary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              _buildField(
                controller: _titleController,
                label: AppStrings.editorSongTitleLabel,
                icon: Icons.music_note_rounded,
                palette: palette,
              ),
              const SizedBox(height: 10),
              _buildField(
                controller: _artistController,
                label: AppStrings.editorArtistLabel,
                icon: Icons.person_outline_rounded,
                palette: palette,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildField(
                      controller: _albumController,
                      label: AppStrings.editorAlbumLabel,
                      icon: Icons.album_outlined,
                      palette: palette,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildField(
                      controller: _yearController,
                      label: AppStrings.editorYearLabel,
                      icon: Icons.calendar_today_outlined,
                      palette: palette,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Lyrics Header with Ganti Lirik & Auto-Romaji buttons
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    AppStrings.editorLyricsHeader,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: palette.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      PressableScale(
                        pressedScale: 0.94,
                        onTap: _toggleLyricsPicker,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          child: Text(
                            _showLyricsCandidates
                                ? AppStrings.previewClose
                                : AppStrings.previewChangeLyrics,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: palette.nowPlayingPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (_canConvertLyricsToRomaji)
                        PressableScale(
                          pressedScale: 0.94,
                          enabled: !_isConvertingRomaji,
                          onTap: _convertLyricsToRomaji,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Text(
                              _isConvertingRomaji
                                  ? AppStrings.previewConvertingRomaji
                                  : AppStrings.previewAutoRomaji,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: palette.nowPlayingPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              if (_showLyricsCandidates) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.surfaceSubtle,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: hairline, width: 0.8),
                  ),
                  child: widget.provider.isSearchingLyricsCandidates
                      ? Padding(
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
                      : widget.provider.lyricsCandidates.isEmpty
                          ? Text(
                              AppStrings.previewNoLyricsCandidates,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: palette.textMuted,
                                fontSize: 11.5,
                              ),
                            )
                          : ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 185),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount:
                                    widget.provider.lyricsCandidates.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 5),
                                itemBuilder: (context, idx) {
                                  final cand =
                                      widget.provider.lyricsCandidates[idx];
                                  final isChosen = _selectedCandidateId != null
                                      ? _selectedCandidateId == cand.id
                                      : idx == 0;
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () => _applyLyricsCandidate(cand),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isChosen
                                            ? palette.surfaceCard
                                            : palette.nowPlayingBg,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isChosen
                                              ? palette.nowPlayingPrimary
                                              : hairline,
                                          width: isChosen ? 1.1 : 0.8,
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
                                              size: 16,
                                              color: isChosen
                                                  ? palette.nowPlayingPrimary
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
                                                        fontFamily: 'Poppins',
                                                        color:
                                                            palette.textPrimary,
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      '${cand.hasSynced ? 'LRC' : (AppStrings.isIndonesian ? 'Biasa' : 'Plain')} • ${cand.formattedDuration}',
                                                      style: TextStyle(
                                                        fontFamily: 'Poppins',
                                                        color:
                                                            palette.textMuted,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
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
                ),
              ],
              const SizedBox(height: 6),
              TextField(
                controller: _lyricsController,
                maxLines: 7,
                cursorColor: palette.nowPlayingPrimary,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 12.5,
                  height: 1.45,
                ),
                decoration: InputDecoration(
                  hintText: AppStrings.editorLyricsHint,
                  hintStyle:
                      TextStyle(color: palette.textMuted, fontSize: 12.5),
                  filled: true,
                  fillColor: palette.surfaceSubtle,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: hairline, width: 0.8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: hairline, width: 0.8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: palette.nowPlayingPrimary,
                      width: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: MographSpringTap(
                      pressedScale: 0.96,
                      enabled: !_isSaving,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.textPrimary,
                          backgroundColor: palette.surfaceSubtle,
                          side: BorderSide(color: hairline, width: 0.8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          minimumSize: const Size(0, 46),
                        ),
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(
                          AppStrings.editorCancelButton,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: MographSpringTap(
                      pressedScale: 0.97,
                      enabled: !_isSaving,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: palette.nowPlayingPrimary,
                          foregroundColor: palette.nowPlayingOnPrimary,
                          minimumSize: const Size(0, 46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _isSaving ? null : _saveChanges,
                        icon: _isSaving
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: palette.nowPlayingOnPrimary,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          AppStrings.editorSaveButton,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required MusEveePalette palette,
  }) {
    final hairline = palette.hairline;
    return TextField(
      controller: controller,
      cursorColor: palette.nowPlayingPrimary,
      onChanged: (_) => setState(() {}),
      style: TextStyle(color: palette.textPrimary, fontSize: 13.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: palette.textMuted, fontSize: 12.5),
        floatingLabelStyle: TextStyle(
          color: palette.nowPlayingPrimary,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: Icon(icon, size: 18, color: palette.textMuted),
        filled: true,
        fillColor: palette.surfaceSubtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: hairline, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: hairline, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.nowPlayingPrimary, width: 1.2),
        ),
      ),
    );
  }
}

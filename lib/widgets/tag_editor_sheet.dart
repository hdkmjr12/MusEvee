import 'package:flutter/material.dart';

import '../models/download_item.dart';
import '../models/local_song.dart';
import '../models/track_metadata.dart';
import '../providers/downloader_provider.dart';
import '../providers/local_music_provider.dart';
import '../services/lyrics_service.dart';
import '../services/romaji_service.dart';
import '../theme/musevee_palette.dart';

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
      backgroundColor: palette.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
      backgroundColor: palette.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
      backgroundColor: palette.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
    final textToUse = cand.hasSynced
        ? (cand.syncedLyrics ?? '')
        : (cand.plainLyrics ?? '');
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
          const SnackBar(
            content: Text('Tag ID3 & Embedded Lyrics berhasil disimpan ke MP3.'),
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
          const SnackBar(
            content: Text('Info lagu & lirik berhasil diperbarui.'),
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
          const SnackBar(
            content: Text('Info lagu & lirik berhasil disimpan.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan perubahan: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.textMuted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header + Auto-Romaji Chip
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: palette.surfaceSubtle,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: hairline, width: 0.8),
                    ),
                    child: Icon(
                      Icons.edit_outlined,
                      color: palette.accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isLocalOrHistory
                              ? 'Edit Tag & Embedded Lyrics'
                              : 'Edit Info & Lirik',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isLocalOrHistory
                              ? 'Menulis ulang tag ID3v2.4 & USLT langsung ke file MP3'
                              : 'Sesuaikan judul, artis, dan lirik lagu sebelum unduh',
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_hasJapaneseInFields)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: palette.surfaceSubtle,
                      side: BorderSide(color: hairline, width: 0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      onPressed:
                          _isConvertingRomaji ? null : _convertFieldsToRomaji,
                      label: Text(
                        _isConvertingRomaji ? 'Proses...' : '✨ Auto-Romaji',
                        style: TextStyle(
                          color: palette.accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              _buildField(
                controller: _titleController,
                label: 'Judul Lagu',
                icon: Icons.music_note_rounded,
                palette: palette,
              ),
              const SizedBox(height: 10),
              _buildField(
                controller: _artistController,
                label: 'Artis',
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
                      label: 'Album',
                      icon: Icons.album_outlined,
                      palette: palette,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildField(
                      controller: _yearController,
                      label: 'Tahun',
                      icon: Icons.calendar_today_outlined,
                      palette: palette,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Lyrics Header with Ganti Lirik & Auto-Romaji buttons
              Row(
                children: [
                  Text(
                    'Embedded Lyrics (USLT):',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _toggleLyricsPicker,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      child: Text(
                        _showLyricsCandidates ? 'Tutup Pilihan' : 'Ganti Lirik',
                        style: TextStyle(
                          color: palette.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (_canConvertLyricsToRomaji) ...[
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap:
                          _isConvertingRomaji ? null : _convertLyricsToRomaji,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Text(
                          _isConvertingRomaji
                              ? 'Mengonversi...'
                              : '✨ Auto-Romaji',
                          style: TextStyle(
                            color: palette.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
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
                                color: palette.accent,
                              ),
                            ),
                          ),
                        )
                      : widget.provider.lyricsCandidates.isEmpty
                          ? Text(
                              'Versi lirik lain tidak ditemukan di LRCLIB.',
                              style: TextStyle(
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
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () => _applyLyricsCandidate(cand),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isChosen
                                            ? palette.accent.withValues(
                                                alpha: 0.14,
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
                                                        color: palette.textMuted,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
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
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 12.5,
                  height: 1.45,
                ),
                decoration: InputDecoration(
                  hintText:
                      'Tulis atau tempel lirik lagu ([mm:ss.xx] atau polos)...',
                  hintStyle: TextStyle(color: palette.textMuted, fontSize: 12.5),
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
                    borderSide: BorderSide(color: palette.accent, width: 1.2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.textPrimary,
                        backgroundColor: palette.surfaceSubtle,
                        side: BorderSide(color: hairline, width: 0.8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed:
                          _isSaving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _isSaving ? null : _saveChanges,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Simpan'),
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
      onChanged: (_) => setState(() {}),
      style: TextStyle(color: palette.textPrimary, fontSize: 13.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: palette.textMuted, fontSize: 12.5),
        prefixIcon: Icon(icon, size: 18, color: palette.textMuted),
        filled: true,
        fillColor: palette.surfaceSubtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
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
          borderSide: BorderSide(color: palette.accent, width: 1.2),
        ),
      ),
    );
  }
}

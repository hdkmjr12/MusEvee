import 'package:flutter/material.dart';

import '../models/download_item.dart';
import '../models/track_metadata.dart';
import '../providers/downloader_provider.dart';
import '../services/romaji_service.dart';

class TagEditorSheet extends StatefulWidget {
  final DownloaderProvider provider;
  final TrackMetadata track;
  final DownloadItem? historyItem;

  const TagEditorSheet({
    super.key,
    required this.provider,
    required this.track,
    this.historyItem,
  });

  static Future<void> show(
    BuildContext context, {
    required DownloaderProvider provider,
    required TrackMetadata track,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFFFFF),
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFFFFF),
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

  @override
  State<TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<TagEditorSheet> {
  static const Color _surfaceCard = Color(0xFFFFFFFF);
  static const Color _surfaceSubtle = Color(0xFFF2F4F7);
  static const Color _primaryBlue = Color(0xFF1677B8);
  static const Color _textDark = Color(0xFF15181E);
  static const Color _textMuted = Color(0xFF68717C);

  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _yearController;
  late final TextEditingController _lyricsController;

  bool _preferSyncedLyrics = true;
  bool _isConvertingRomaji = false;
  bool _isSaving = false;
  String? _syncedLyricsOverride;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.track.title);
    _artistController = TextEditingController(text: widget.track.artist);
    _albumController = TextEditingController(text: widget.track.album);
    _yearController = TextEditingController(text: widget.track.releaseYear);

    _preferSyncedLyrics = widget.historyItem != null
        ? widget.historyItem!.preferSyncedLyrics
        : widget.provider.preferSyncedLyrics;

    final initialLyrics = (_preferSyncedLyrics && widget.track.hasSyncedLyrics)
        ? (widget.track.normalizedSyncedLyrics ?? '')
        : (widget.track.cleanPlainLyrics ??
            widget.track.normalizedSyncedLyrics ??
            '');
    _lyricsController = TextEditingController(text: initialLyrics);
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

  bool get _hasJapaneseInLyrics =>
      RomajiService.containsJapanese(_lyricsController.text) ||
      RomajiService.trackLyricsHasJapanese(widget.track);

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
      if (widget.historyItem != null) {
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isHistoryMode = widget.historyItem != null;
    final hairline = Colors.black.withValues(alpha: 0.07);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, bottomInset + 20),
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
                    color: Colors.black.withValues(alpha: 0.14),
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
                      color: _surfaceSubtle,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: hairline, width: 0.8),
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      color: _primaryBlue,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isHistoryMode
                              ? 'Edit Info & Lirik Lagu'
                              : 'Edit Info & Lirik',
                          style: const TextStyle(
                            color: _textDark,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isHistoryMode
                              ? 'Simpan perubahan langsung ke lagu'
                              : 'Sesuaikan judul, artis, dan lirik lagu',
                          style: const TextStyle(
                            color: _textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_hasJapaneseInFields)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: _surfaceSubtle,
                      side: BorderSide(color: hairline, width: 0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      onPressed:
                          _isConvertingRomaji ? null : _convertFieldsToRomaji,
                      label: Text(
                        _isConvertingRomaji ? 'Proses...' : '✨ Auto-Romaji',
                        style: const TextStyle(
                          color: _primaryBlue,
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
              ),
              const SizedBox(height: 10),
              _buildField(
                controller: _artistController,
                label: 'Artis',
                icon: Icons.person_outline_rounded,
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
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildField(
                      controller: _yearController,
                      label: 'Tahun',
                      icon: Icons.calendar_today_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Lyrics Header with Romaji button if Japanese lyrics detected
              Row(
                children: [
                  const Text(
                    'Lirik Lagu:',
                    style: TextStyle(
                      color: _textDark,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  if (_hasJapaneseInLyrics)
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap:
                          _isConvertingRomaji ? null : _convertLyricsToRomaji,
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        child: Text(
                          '✨ Lirik ke Romaji',
                          style: TextStyle(
                            color: _primaryBlue,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _lyricsController,
                maxLines: 6,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 12.5,
                  height: 1.45,
                ),
                decoration: InputDecoration(
                  hintText: 'Tulis atau tempel lirik lagu di sini...',
                  filled: true,
                  fillColor: _surfaceSubtle,
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
                    borderSide:
                        const BorderSide(color: _primaryBlue, width: 1.2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
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
                        backgroundColor: _primaryBlue,
                        foregroundColor: _surfaceCard,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isSaving ? null : _saveChanges,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _surfaceCard,
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
  }) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: _textDark, fontSize: 13.5),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: _textMuted),
        filled: true,
        fillColor: _surfaceSubtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }
}

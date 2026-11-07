import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/download_item.dart';
import '../models/track_metadata.dart';
import '../providers/downloader_provider.dart';
import '../widgets/batch_playlist_sheet.dart';
import '../widgets/musevee_logo.dart';
import '../widgets/queue_history_view.dart';
import '../widgets/search_result_tile.dart';
import '../widgets/track_preview_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const MethodChannel _systemChannel = MethodChannel(
    'com.spotmeta.downloader/system',
  );

  // Palet Modern Architectural UI (dhaauu.web.id + Linear/Vercel Surface Depth)
  static const Color _bgCanvas = Color(0xFFF8FAFC);
  static const Color _surfaceCard = Color(0xFFFFFFFF);
  static const Color _surfaceSubtle = Color(0xFFF2F4F7);
  static const Color _primaryBlue = Color(0xFF1677B8);
  static const Color _textDark = Color(0xFF15181E);
  static const Color _textMuted = Color(0xFF68717C);
  static const Color _redDot = Color(0xFFD92D20);

  static const List<String> _sampleSearches = [
    'YOASOBI - Idol',
    'Katy Perry - The One That Got Away',
    'Ado - Show',
    'Kenshi Yonezu - KICK BACK',
    'Hindia - Evaluasi',
    'Taylor Swift - Style',
  ];

  final TextEditingController _inputController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _setupShareIntentListener();
  }

  void _setupShareIntentListener() {
    _systemChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        final sharedText = (call.arguments as String?)?.trim() ?? '';
        if (sharedText.isNotEmpty && mounted) {
          await _handleIncomingSharedText(sharedText);
        }
      } else if (call.method == 'onPreviewStateChanged') {
        if (!mounted) return;
        final args = call.arguments;
        bool isPlaying = false;
        String? url;
        if (args is Map) {
          isPlaying = args['isPlaying'] == true;
          url = args['url']?.toString();
        }
        context.read<DownloaderProvider>().handleNativePreviewStateChanged(
              isPlaying: isPlaying,
              url: url,
            );
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final initialShared = await _systemChannel.invokeMethod<String>(
          'getInitialSharedText',
        );
        if (initialShared != null &&
            initialShared.trim().isNotEmpty &&
            mounted) {
          await _handleIncomingSharedText(initialShared.trim());
        }
      } catch (_) {}
    });
  }

  Future<void> _handleIncomingSharedText(String sharedText) async {
    _inputController.text = sharedText;
    setState(() => _selectedTabIndex = 0);

    final provider = context.read<DownloaderProvider>();
    final isCollection = provider.isSpotifyCollectionInput(sharedText);
    await provider.submitSmartInput(sharedText);
    if (!mounted) return;

    if (isCollection && provider.currentCollection != null) {
      await _openBatchPlaylistSheet(provider);
    } else if (provider.trackMetadata != null) {
      await _openTrackPreviewSheet(provider);
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pasteAndSubmit(DownloaderProvider provider) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;

    _inputController.text = text;
    setState(() {});
    await _submitOmnibox(provider);
  }

  Future<void> _submitOmnibox(DownloaderProvider provider) async {
    final raw = _inputController.text.trim();
    if (raw.isEmpty || provider.isBusy) return;
    FocusScope.of(context).unfocus();

    final isCollection = provider.isSpotifyCollectionInput(raw);
    final isSpotifyTrack = provider.isSpotifyTrackInput(raw) ||
        raw.contains('spotify.com') ||
        raw.startsWith('spotify:track:');

    await provider.submitSmartInput(raw);
    if (!mounted) return;

    if (isCollection && provider.currentCollection != null) {
      await _openBatchPlaylistSheet(provider);
    } else if (isSpotifyTrack && provider.trackMetadata != null) {
      await _openTrackPreviewSheet(provider);
    }
  }

  Future<void> _onTapSearchResult(
    DownloaderProvider provider,
    TrackMetadata selected,
  ) async {
    final future = provider.selectSearchResult(selected);
    await _openTrackPreviewSheet(provider);
    await future;
  }

  Future<void> _openTrackPreviewSheet(DownloaderProvider provider) async {
    if (!mounted) return;
    await TrackPreviewSheet.show(
      context,
      onCreateNewFolder: _showCreateFolderDialog,
    );
  }

  Future<void> _openBatchPlaylistSheet(DownloaderProvider provider) async {
    final collection = provider.currentCollection;
    if (!mounted || collection == null) return;
    await BatchPlaylistSheet.show(
      context,
      collection: collection,
      onCreateNewFolder: _showCreateFolderDialog,
    );
  }

  Future<void> _showCreateFolderDialog(DownloaderProvider provider) async {
    final folderController = TextEditingController();
    final hairline = Colors.black.withValues(alpha: 0.07);
    final createdName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: hairline, width: 0.8),
          ),
          title: const Text(
            'Buat Folder Baru',
            style: TextStyle(
              color: _textDark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Masukkan nama folder musik baru:',
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: folderController,
                autofocus: true,
                style: const TextStyle(color: _textDark, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Contoh: Music Anime / Music Indo',
                  prefixIcon: Icon(
                    Icons.create_new_folder_outlined,
                    color: _primaryBlue,
                    size: 19,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Batal',
                style: TextStyle(color: _textMuted),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final text = folderController.text.trim();
                if (text.isNotEmpty) {
                  Navigator.of(ctx).pop(text);
                }
              },
              child: const Text('Buat'),
            ),
          ],
        );
      },
    );

    if (createdName != null && createdName.isNotEmpty && mounted) {
      final result = await provider.createAndSelectFolder(createdName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Folder "$result" dipilih sebagai tujuan.'),
          ),
        );
      }
    }
  }

  Future<void> _showMoveFolderSheet(
    DownloaderProvider provider,
    DownloadItem item,
  ) async {
    final hairline = Colors.black.withValues(alpha: 0.07);
    final chosenFolder = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final folders = provider.availableFolders;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const Text(
                  'Pindah Folder',
                  style: TextStyle(
                    color: _textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.metadata.artist} — ${item.metadata.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _textMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...folders.map((folder) {
                      final isCurrent = folder == item.targetFolderName;
                      return ChoiceChip(
                        selected: isCurrent,
                        showCheckmark: false,
                        backgroundColor: _surfaceSubtle,
                        selectedColor: _primaryBlue,
                        side: BorderSide(
                          color: isCurrent ? _primaryBlue : hairline,
                          width: 0.8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isCurrent
                                  ? Icons.folder_rounded
                                  : Icons.folder_outlined,
                              size: 15,
                              color: isCurrent ? _surfaceCard : _textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isCurrent ? '$folder (Saat Ini)' : folder,
                              style: TextStyle(
                                color: isCurrent ? _surfaceCard : _textDark,
                                fontSize: 12.5,
                                fontWeight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        onSelected: isCurrent
                            ? null
                            : (_) => Navigator.of(ctx).pop(folder),
                      );
                    }),
                    ActionChip(
                      backgroundColor: _surfaceCard,
                      side: BorderSide(color: hairline, width: 0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      avatar: const Icon(
                        Icons.add_rounded,
                        size: 15,
                        color: _primaryBlue,
                      ),
                      label: const Text(
                        'Folder Baru',
                        style: TextStyle(
                          color: _primaryBlue,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => Navigator.of(ctx).pop('__NEW__'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (chosenFolder == null || !mounted) return;

    String targetFolder = chosenFolder;
    if (chosenFolder == '__NEW__') {
      await _showCreateFolderDialog(provider);
      targetFolder = provider.selectedFolder;
      if (targetFolder == item.targetFolderName) return;
    }

    try {
      await provider.moveItemToFolder(
        itemId: item.id,
        newFolderName: targetFolder,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Berhasil dipindahkan ke $targetFolder.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memindahkan lagu: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hairline = Colors.black.withValues(alpha: 0.07);

    return Consumer<DownloaderProvider>(
      builder: (context, provider, _) {
        final activeQueueCount = provider.activeQueueCount;
        final isDirectDownloadActive =
            provider.state == DownloaderState.downloadingAudio ||
            provider.state == DownloaderState.taggingAudio;
        final totalActiveCount =
            activeQueueCount + (isDirectDownloadActive ? 1 : 0);

        return Scaffold(
          backgroundColor: _bgCanvas,
          appBar: _buildAppBar(provider),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: _selectedTabIndex,
                    children: [
                      _buildSearchAndDownloadTab(provider),
                      QueueHistoryView(
                        provider: provider,
                        onMoveFolder: _showMoveFolderSheet,
                      ),
                    ],
                  ),
                ),

                // Floating Mini Progress Banner tepat di atas BottomNavigationBar
                if (provider.isBusy ||
                    activeQueueCount > 0 ||
                    provider.state == DownloaderState.error)
                  _buildFloatingMiniProgressBanner(provider),
              ],
            ),
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: hairline, width: 0.8),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _selectedTabIndex,
              onDestinationSelected: (idx) {
                setState(() => _selectedTabIndex = idx);
              },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.search_rounded),
                  selectedIcon: Icon(Icons.search_rounded),
                  label: 'Cari & Unduh',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible:
                        totalActiveCount > 0 || provider.queueItems.isNotEmpty,
                    backgroundColor: totalActiveCount > 0
                        ? _primaryBlue
                        : _surfaceSubtle,
                    textColor:
                        totalActiveCount > 0 ? _surfaceCard : _textDark,
                    label: Text(
                      totalActiveCount > 0
                          ? '$totalActiveCount'
                          : '${provider.queueItems.length}',
                    ),
                    child: const Icon(Icons.library_music_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible:
                        totalActiveCount > 0 || provider.queueItems.isNotEmpty,
                    backgroundColor: _primaryBlue,
                    textColor: _surfaceCard,
                    label: Text(
                      totalActiveCount > 0
                          ? '$totalActiveCount'
                          : '${provider.queueItems.length}',
                    ),
                    child: const Icon(Icons.library_music_rounded),
                  ),
                  label: 'Antrean & Koleksi',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(DownloaderProvider provider) {
    final hairline = Colors.black.withValues(alpha: 0.07);
    return AppBar(
      titleSpacing: 16,
      backgroundColor: _surfaceCard,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, thickness: 0.8, color: hairline),
      ),
      title: const Row(
        children: [
          // Logo Vektor MusEvee Tanpa Background/Border (100% Transparan)
          MusEveeLogo(size: 26),
          SizedBox(width: 10),
          Text(
            'MusEvee',
            style: TextStyle(
              color: _textDark,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
      actions: [
        if (provider.trackMetadata != null)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryBlue,
                backgroundColor: _surfaceSubtle,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                side: BorderSide(color: hairline, width: 0.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: () => _openTrackPreviewSheet(provider),
              icon: const Icon(Icons.music_note_rounded, size: 15),
              label: const Text(
                'Lagu Aktif',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // TAB 1: CARI & UNDUH (Modern Architectural UI Omnibox + Folder Chips + List)
  // ===========================================================================
  Widget _buildSearchAndDownloadTab(DownloaderProvider provider) {
    final results = provider.searchResults;
    final rawText = _inputController.text.trim();
    final isSpotify =
        rawText.contains('spotify.com') || rawText.startsWith('spotify:track:');
    final hairline = Colors.black.withValues(alpha: 0.07);

    return Column(
      children: [
        // Sticky Header: Omnibox (10px radius) + Folder Chips (6px radius)
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: _surfaceCard,
            border: Border(
              bottom: BorderSide(color: hairline, width: 0.8),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      focusNode: _searchFocusNode,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submitOmnibox(provider),
                      decoration: InputDecoration(
                        hintText: 'Cari judul lagu atau tempel tautan Spotify...',
                        fillColor: _surfaceSubtle,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        prefixIcon: Icon(
                          isSpotify ? Icons.link_rounded : Icons.search_rounded,
                          color: isSpotify ? _primaryBlue : _textMuted,
                          size: 19,
                        ),
                        suffixIcon: rawText.isEmpty
                            ? TextButton(
                                style: TextButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                onPressed: provider.isBusy
                                    ? null
                                    : () => _pasteAndSubmit(provider),
                                child: const Text(
                                  'Tempel',
                                  style: TextStyle(
                                    color: _primaryBlue,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            : IconButton(
                                tooltip: 'Bersihkan',
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: _textMuted,
                                  size: 18,
                                ),
                                onPressed: () {
                                  _inputController.clear();
                                  setState(() {});
                                },
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: hairline,
                            width: 0.8,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: hairline,
                            width: 0.8,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: _primaryBlue,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (rawText.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 45,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryBlue,
                          foregroundColor: _surfaceCard,
                          minimumSize: const Size(0, 45),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: provider.isBusy
                            ? null
                            : () => _submitOmnibox(provider),
                        child: Text(
                          isSpotify ? 'Buka' : 'Cari',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),

              // Baris Default Target Folder (Micro-Radius 6px)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Icon(
                      Icons.folder_outlined,
                      size: 15,
                      color: _textMuted,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Simpan ke:',
                      style: TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ...provider.availableFolders.map((folder) {
                      final isSelected = folder == provider.selectedFolder;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          selected: isSelected,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
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
                              fontSize: 12,
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
                      visualDensity: VisualDensity.compact,
                      backgroundColor: _surfaceCard,
                      side: BorderSide(color: hairline, width: 0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      label: const Text(
                        '+ Baru',
                        style: TextStyle(
                          color: _primaryBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => _showCreateFolderDialog(provider),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Area Utama Tab 1: Daftar Hasil Pencarian (spasi 8px lega) atau Empty State
        Expanded(
          child: provider.state == DownloaderState.searchingCatalog
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: _primaryBlue,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Memuat info...',
                        style: TextStyle(color: _textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : results.isNotEmpty
                  ? ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: results.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final track = results[index];
                        return SearchResultTile(
                          track: track,
                          duplicateFolder: provider.duplicateFolderFor(track),
                          onTap: () => _onTapSearchResult(provider, track),
                        );
                      },
                    )
                  : _buildMinimalEmptyState(provider),
        ),
      ],
    );
  }

  Widget _buildMinimalEmptyState(DownloaderProvider provider) {
    final hairline = Colors.black.withValues(alpha: 0.07);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _surfaceCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: hairline, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ketik judul lagu atau tempel tautan Spotify untuk mulai mengunduh.',
                style: TextStyle(
                  color: _textDark,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Pencarian Cepat:',
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
                children: _sampleSearches.map((query) {
                  return ActionChip(
                    backgroundColor: _surfaceSubtle,
                    side: BorderSide(color: hairline, width: 0.8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    label: Text(
                      query,
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onPressed: provider.isBusy
                        ? null
                        : () {
                            _inputController.text = query;
                            setState(() {});
                            _submitOmnibox(provider);
                          },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // FLOATING MINI PROGRESS BANNER DI ATAS BOTTOM NAVIGATION BAR
  // ===========================================================================
  Widget _buildFloatingMiniProgressBanner(DownloaderProvider provider) {
    final isError = provider.state == DownloaderState.error;
    final pct = (provider.progress * 100).round();
    final hairline = Colors.black.withValues(alpha: 0.07);

    return Material(
      color: _surfaceCard,
      child: InkWell(
        onTap: () => setState(() => _selectedTabIndex = 1),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: hairline, width: 0.8),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (provider.isBusy)
                LinearProgressIndicator(
                  value: provider.progress.clamp(0.0, 1.0),
                  minHeight: 2.5,
                  backgroundColor: _surfaceSubtle,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(_primaryBlue),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    if (provider.isBusy)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _primaryBlue,
                        ),
                      )
                    else
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isError ? _redDot : _primaryBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        provider.statusMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isError ? _redDot : _textDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (provider.isBusy) ...[
                      const SizedBox(width: 8),
                      Text(
                        '$pct%',
                        style: const TextStyle(
                          color: _primaryBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

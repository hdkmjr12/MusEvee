import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/download_item.dart';
import '../models/local_song.dart';
import '../models/track_metadata.dart';
import '../providers/downloader_provider.dart';
import '../providers/local_music_provider.dart';
import '../widgets/batch_playlist_sheet.dart';
import '../widgets/local_library_views.dart';
import '../widgets/musevee_logo.dart';
import '../widgets/musicolet_bottom_strip.dart';
import '../widgets/musicolet_mini_player.dart';
import '../widgets/now_playing_view.dart';
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

  // Musicolet Tab Indices
  static const int _tabNowPlaying = 1;
  static const int _tabFolders = 2;
  static const int _tabDownloader = 5;
  static const int _tabDownloadHistory = 6;

  // Dark Musicolet Surface Palette
  static const Color _bgCanvas = Color(0xFF0E1014);
  static const Color _surfaceCard = Color(0xFF17191E);
  static const Color _surfaceSubtle = Color(0xFF22252D);
  static const Color _primaryAccent = Color(0xFF3898EC);
  static const Color _textPrimary = Color(0xFFF2F4F7);
  static const Color _textMuted = Color(0xFF98A2B3);
  static const Color _redDot = Color(0xFFF04438);

  static const List<String> _sampleSearches = [
    'YOASOBI - Idol',
    'ASCA - RESISTER',
    'Ado - Show',
    'Kenshi Yonezu - KICK BACK',
    'Katy Perry - The One That Got Away',
    'Hindia - Evaluasi',
  ];

  final TextEditingController _inputController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Default to Now Playing (Tab 1) just like Musicolet!
  int _selectedTabIndex = _tabNowPlaying;

  @override
  void initState() {
    super.initState();
    _setupUnifiedSystemChannelListener();
  }

  /// Single unified MethodChannel router dispatching both Downloader (Share Intent,
  /// 30s Preview) and Local Player (`MediaPlayer` position, state, completion) callbacks.
  void _setupUnifiedSystemChannelListener() {
    _systemChannel.setMethodCallHandler((call) async {
      if (!mounted) return;

      switch (call.method) {
        case 'onSharedText':
          final sharedText = (call.arguments as String?)?.trim() ?? '';
          if (sharedText.isNotEmpty) {
            await _handleIncomingSharedText(sharedText);
          }
          break;

        case 'onPreviewStateChanged':
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
          break;

        case 'onLocalPosition':
          final args = call.arguments;
          if (args is Map) {
            context.read<LocalMusicProvider>().handleNativePosition(
                  positionMs: (args['positionMs'] as num?)?.toInt() ?? 0,
                  durationMs: (args['durationMs'] as num?)?.toInt() ?? 0,
                  isPlaying: args['isPlaying'] == true,
                );
          }
          break;

        case 'onLocalPlayerState':
          final args = call.arguments;
          if (args is Map) {
            context.read<LocalMusicProvider>().handleNativePlayerState(
                  isPlaying: args['isPlaying'] == true,
                  positionMs: (args['positionMs'] as num?)?.toInt() ?? 0,
                  durationMs: (args['durationMs'] as num?)?.toInt() ?? 0,
                );
          }
          break;

        case 'onLocalTrackCompleted':
          context.read<LocalMusicProvider>().handleNativeTrackCompleted();
          break;
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
    setState(() => _selectedTabIndex = _tabDownloader);

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
    final hairline = Colors.white.withValues(alpha: 0.09);
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
            'Buat Folder Musik Baru',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Masukkan nama folder baru di /storage/emulated/0/Music:',
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
                style: const TextStyle(color: _textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Contoh: Music Anime / Music Indo',
                  prefixIcon: Icon(
                    Icons.create_new_folder_outlined,
                    color: _primaryAccent,
                    size: 19,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
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
        await context.read<LocalMusicProvider>().refreshLibrary();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Folder "$result" siap digunakan.'),
          ),
        );
      }
    }
  }

  Future<void> _showMoveFolderSheet(
    DownloaderProvider provider,
    DownloadItem item,
  ) async {
    final chosenFolder = await _pickTargetFolderModal(
      title: 'Pindah Folder Lagu',
      subtitle: '${item.metadata.artist} — ${item.metadata.title}',
      currentFolder: item.targetFolderName,
      availableFolders: provider.availableFolders,
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

  Future<void> _showMoveLocalSongFolderSheet(LocalSong song) async {
    final downloader = context.read<DownloaderProvider>();
    final localMusic = context.read<LocalMusicProvider>();

    final chosenFolder = await _pickTargetFolderModal(
      title: 'Pindah Folder Lagu Lokal',
      subtitle: '${song.artist} — ${song.title}',
      currentFolder: song.folderName,
      availableFolders: localMusic.availableFolders,
    );

    if (chosenFolder == null || !mounted) return;

    String targetFolder = chosenFolder;
    if (chosenFolder == '__NEW__') {
      await _showCreateFolderDialog(downloader);
      targetFolder = downloader.selectedFolder;
      if (targetFolder == song.folderName) return;
    }

    try {
      await localMusic.moveLocalSongToFolder(
        song: song,
        targetFolderName: targetFolder,
      );
      await downloader.refreshFolders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lagu berhasil dipindahkan ke folder $targetFolder.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memindahkan lagu lokal: $e')),
        );
      }
    }
  }

  Future<String?> _pickTargetFolderModal({
    required String title,
    required String subtitle,
    required String currentFolder,
    required List<String> availableFolders,
  }) {
    final hairline = Colors.white.withValues(alpha: 0.09);
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
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
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _textMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...availableFolders.map((folder) {
                      final isCurrent = folder == currentFolder;
                      return ChoiceChip(
                        selected: isCurrent,
                        showCheckmark: false,
                        backgroundColor: _surfaceSubtle,
                        selectedColor: _primaryAccent,
                        side: BorderSide(
                          color: isCurrent ? _primaryAccent : hairline,
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
                              color: isCurrent ? Colors.white : _textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isCurrent ? '$folder (Saat Ini)' : folder,
                              style: TextStyle(
                                color: isCurrent ? Colors.white : _textPrimary,
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
                        color: _primaryAccent,
                      ),
                      label: const Text(
                        'Folder Baru',
                        style: TextStyle(
                          color: _primaryAccent,
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
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloaderProvider>(
      builder: (context, provider, _) {
        final activeQueueCount = provider.activeQueueCount;
        final isDirectDownloadActive =
            provider.state == DownloaderState.downloadingAudio ||
            provider.state == DownloaderState.taggingAudio;
        final totalActiveCount =
            activeQueueCount + (isDirectDownloadActive ? 1 : 0);

        final isOnNowPlaying = _selectedTabIndex == _tabNowPlaying;

        return Scaffold(
          backgroundColor: _bgCanvas,
          // Full-bleed Now Playing without AppBar (1:1 Musicolet!), compact header on other tabs
          appBar: isOnNowPlaying ? null : _buildMusicEveeAppBar(provider),
          body: Column(
            children: [
              Expanded(
                child: IndexedStack(
                  index: _selectedTabIndex,
                  children: [
                    // 0: Queue (`=♪`)
                    PlaybackQueueView(
                      onOpenNowPlaying: () =>
                          setState(() => _selectedTabIndex = _tabNowPlaying),
                      onNavigateToDownloader: () =>
                          setState(() => _selectedTabIndex = _tabDownloader),
                    ),

                    // 1: Now Playing (`▶` in circle — 1:1 Musicolet)
                    NowPlayingView(
                      onNavigateToDownloader: () =>
                          setState(() => _selectedTabIndex = _tabDownloader),
                      onNavigateToFolders: () =>
                          setState(() => _selectedTabIndex = _tabFolders),
                      onMoveLocalSongFolder: _showMoveLocalSongFolderSheet,
                    ),

                    // 2: Folders (`📁`)
                    LocalFoldersView(
                      onOpenNowPlaying: () =>
                          setState(() => _selectedTabIndex = _tabNowPlaying),
                      onCreateNewFolder: _showCreateFolderDialog,
                      onMoveLocalSongFolder: _showMoveLocalSongFolderSheet,
                    ),

                    // 3: Albums (`💿`)
                    LocalAlbumsView(
                      onOpenNowPlaying: () =>
                          setState(() => _selectedTabIndex = _tabNowPlaying),
                      onMoveLocalSongFolder: _showMoveLocalSongFolderSheet,
                    ),

                    // 4: Artists (`👤`)
                    LocalArtistsView(
                      onOpenNowPlaying: () =>
                          setState(() => _selectedTabIndex = _tabNowPlaying),
                      onMoveLocalSongFolder: _showMoveLocalSongFolderSheet,
                    ),

                    // 5: Downloader (`⬇` Cloud Download — Smart Omnibox)
                    _buildSearchAndDownloadTab(provider),

                    // 6: Download Queue & History (`📋`)
                    QueueHistoryView(
                      provider: provider,
                      onMoveFolder: _showMoveFolderSheet,
                      onPlaySavedFile: (savedPath) async {
                        await context
                            .read<LocalMusicProvider>()
                            .playSongByPath(savedPath);
                        if (mounted) {
                          setState(() => _selectedTabIndex = _tabNowPlaying);
                        }
                      },
                    ),

                    // 7: Search Lokal (`🔍`)
                    LocalSearchView(
                      onOpenNowPlaying: () =>
                          setState(() => _selectedTabIndex = _tabNowPlaying),
                      onMoveLocalSongFolder: _showMoveLocalSongFolderSheet,
                    ),
                  ],
                ),
              ),

              // Thin Download Progress Banner when FFmpeg / Downloader is active
              if (provider.isBusy ||
                  activeQueueCount > 0 ||
                  provider.state == DownloaderState.error)
                _buildFloatingMiniProgressBanner(provider),

              // Musicolet Thin Mini Player on all non-Now-Playing tabs
              if (!isOnNowPlaying)
                MusicoletMiniPlayer(
                  onTapOpenNowPlaying: () =>
                      setState(() => _selectedTabIndex = _tabNowPlaying),
                ),
            ],
          ),
          bottomNavigationBar: MusicoletBottomStrip(
            selectedIndex: _selectedTabIndex,
            activeDownloadBadgeCount: totalActiveCount,
            onTabSelected: (idx) {
              setState(() => _selectedTabIndex = idx);
            },
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildMusicEveeAppBar(DownloaderProvider provider) {
    final hairline = Colors.white.withValues(alpha: 0.08);
    return AppBar(
      toolbarHeight: 48,
      titleSpacing: 14,
      backgroundColor: const Color(0xFF12151C),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, thickness: 0.7, color: hairline),
      ),
      title: Row(
        children: [
          const MusEveeLogo(size: 22),
          const SizedBox(width: 9),
          const Text(
            'MusicEvee',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: _surfaceSubtle,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: hairline, width: 0.8),
            ),
            child: const Text(
              'v4.0',
              style: TextStyle(
                color: _primaryAccent,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (provider.trackMetadata != null &&
            (_selectedTabIndex == _tabDownloader ||
                _selectedTabIndex == _tabDownloadHistory))
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryAccent,
                backgroundColor: _surfaceSubtle,
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                side: BorderSide(color: hairline, width: 0.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: () => _openTrackPreviewSheet(provider),
              icon: const Icon(Icons.music_note_rounded, size: 14),
              label: const Text(
                'Pratinjau Aktif',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // TAB 5: DOWNLOADER (`⬇` — Smart Omnibox + Folder Chips + Search Results)
  // ===========================================================================
  Widget _buildSearchAndDownloadTab(DownloaderProvider provider) {
    final results = provider.searchResults;
    final rawText = _inputController.text.trim();
    final isSpotify =
        rawText.contains('spotify.com') || rawText.startsWith('spotify:track:');
    final hairline = Colors.white.withValues(alpha: 0.08);

    return Container(
      color: _bgCanvas,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
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
                          color: _textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _submitOmnibox(provider),
                        decoration: InputDecoration(
                          hintText:
                              'Cari judul lagu atau tempel link Spotify...',
                          fillColor: _surfaceSubtle,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          prefixIcon: Icon(
                            isSpotify
                                ? Icons.link_rounded
                                : Icons.cloud_download_outlined,
                            color: isSpotify ? _primaryAccent : _textMuted,
                            size: 19,
                          ),
                          suffixIcon: rawText.isEmpty
                              ? TextButton(
                                  onPressed: provider.isBusy
                                      ? null
                                      : () => _pasteAndSubmit(provider),
                                  child: const Text(
                                    'Tempel',
                                    style: TextStyle(
                                      color: _primaryAccent,
                                      fontSize: 12,
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
                        ),
                      ),
                    ),
                    if (rawText.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 43,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryAccent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 43),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: provider.isBusy
                              ? null
                              : () => _submitOmnibox(provider),
                          child: Text(
                            isSpotify ? 'Buka' : 'Cari',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 9),

                // Target Folder Chips (`Music Barat`, `Music Japan`, `Music Random`, `+ Baru`)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.folder_outlined,
                        size: 14,
                        color: _textMuted,
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Simpan ke:',
                        style: TextStyle(
                          color: _textMuted,
                          fontSize: 11.5,
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
                            selectedColor: _primaryAccent,
                            side: BorderSide(
                              color: isSelected ? _primaryAccent : hairline,
                              width: 0.8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            label: Text(
                              folder,
                              style: TextStyle(
                                color:
                                    isSelected ? Colors.white : _textPrimary,
                                fontSize: 11.5,
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
                            color: _primaryAccent,
                            fontSize: 11.5,
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
                            color: _primaryAccent,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Mencari katalog lagu...',
                          style: TextStyle(color: _textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : results.isNotEmpty
                    ? ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                        itemCount: results.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 7),
                        itemBuilder: (context, index) {
                          final track = results[index];
                          return SearchResultTile(
                            track: track,
                            duplicateFolder:
                                provider.duplicateFolderFor(track),
                            onTap: () => _onTapSearchResult(provider, track),
                          );
                        },
                      )
                    : _buildDownloaderEmptyState(provider),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloaderEmptyState(DownloaderProvider provider) {
    final hairline = Colors.white.withValues(alpha: 0.08);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surfaceCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hairline, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.cloud_download_rounded,
                    color: _primaryAccent,
                    size: 19,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'MusicEvee All-in-One Downloader (MP3 320kbps + USLT Lyrics)',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Ketik judul lagu (Deezer/iTunes) atau tempel tautan Track / Album / Playlist Spotify. Lirik otomatis diprioritaskan ke bahasa asli & tertanam langsung ke tag USLT MP3.',
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Pencarian Cepat:',
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 11.5,
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
                        color: _textPrimary,
                        fontSize: 12,
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
  // FLOATING MINI DOWNLOAD PROGRESS BANNER
  // ===========================================================================
  Widget _buildFloatingMiniProgressBanner(DownloaderProvider provider) {
    final isError = provider.state == DownloaderState.error;
    final pct = (provider.progress * 100).round();
    final hairline = Colors.white.withValues(alpha: 0.08);

    return Material(
      color: const Color(0xFF181C24),
      child: InkWell(
        onTap: () => setState(() => _selectedTabIndex = _tabDownloadHistory),
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
                  minHeight: 2.0,
                  backgroundColor: _surfaceSubtle,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(_primaryAccent),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                child: Row(
                  children: [
                    if (provider.isBusy)
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _primaryAccent,
                        ),
                      )
                    else
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isError ? _redDot : _primaryAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        provider.statusMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isError ? _redDot : _textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (provider.isBusy) ...[
                      const SizedBox(width: 8),
                      Text(
                        '$pct%',
                        style: const TextStyle(
                          color: _primaryAccent,
                          fontSize: 11.5,
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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/download_item.dart';
import '../models/local_song.dart';
import '../models/track_metadata.dart';
import '../providers/downloader_provider.dart';
import '../providers/local_music_provider.dart';
import '../services/folder_service.dart';
import '../theme/musevee_palette.dart';
import '../utils/app_strings.dart';
import '../widgets/batch_playlist_sheet.dart';
import '../widgets/local_library_views.dart';
import '../widgets/musicolet_bottom_strip.dart';
import '../widgets/musicolet_mini_player.dart';
import '../widgets/now_playing_view.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/queue_history_view.dart';
import '../widgets/search_result_tile.dart';
import '../widgets/settings_view.dart';
import '../widgets/track_preview_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const MethodChannel _systemChannel = MethodChannel(
    'com.spotmeta.downloader/system',
  );

  // Musicolet 6-Tab Indices
  static const int _tabNowPlaying = 1;
  static const int _tabFolders = 2;
  static const int _tabPlaylists = 3;
  static const int _tabDownloader = 4;
  // ignore: unused_field
  static const int _tabSettings = 5;

  // Dark Musicolet Surface Palette

  static const List<TrackMetadata> _fallbackForYouTracks = [
    TrackMetadata(
      spotifyUrl: 'search:YOASOBI - Idol',
      title: 'Idol',
      artist: 'YOASOBI',
      album: 'THE BOOK 3',
      releaseYear: '2023',
      durationSeconds: 213,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/71/42/e6/7142e695-a7f7-f562-b1c9-0a8a3d8d910f/197188749316.jpg/300x300bb.jpg',
    ),
    TrackMetadata(
      spotifyUrl: 'search:ASCA - RESISTER',
      title: 'RESISTER',
      artist: 'ASCA',
      album: '百歌繚乱',
      releaseYear: '2019',
      durationSeconds: 227,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/68/97/2e/68972e45-5f2b-47ea-82cd-2110796d386f/jacket_VVXX00409B00Z_550.jpg/300x300bb.jpg',
    ),
    TrackMetadata(
      spotifyUrl: 'search:Ado - Show',
      title: 'Show',
      artist: 'Ado',
      album: 'Zanmu',
      releaseYear: '2023',
      durationSeconds: 189,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/4a/1f/3c/4a1f3c68-2d53-91b7-0991-03a511e5d612/23UM1IM10688.rgb.jpg/300x300bb.jpg',
    ),
    TrackMetadata(
      spotifyUrl: 'search:Kenshi Yonezu - KICK BACK',
      title: 'KICK BACK',
      artist: 'Kenshi Yonezu',
      album: 'LOST CORNER',
      releaseYear: '2022',
      durationSeconds: 193,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music122/v4/f3/2b/99/f32b9921-1c9d-9b34-8d87-e55d53184998/4547366591347.jpg/300x300bb.jpg',
    ),
  ];

  static const List<TrackMetadata> _fallbackGlobalTrendingTracks = [
    TrackMetadata(
      spotifyUrl: 'search:Lady Gaga & Bruno Mars - Die With A Smile',
      title: 'Die With A Smile',
      artist: 'Lady Gaga & Bruno Mars',
      album: 'Die With A Smile',
      releaseYear: '2024',
      durationSeconds: 251,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/11/55/be/1155be56-2f5a-9870-8941-72b0933b2e33/24UMGIM85348.rgb.jpg/300x300bb.jpg',
    ),
    TrackMetadata(
      spotifyUrl: 'search:Billie Eilish - BIRDS OF A FEATHER',
      title: 'BIRDS OF A FEATHER',
      artist: 'Billie Eilish',
      album: 'HIT ME HARD AND SOFT',
      releaseYear: '2024',
      durationSeconds: 210,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/92/9f/69/929f69f1-9977-3a44-d674-11f70c852d1b/24UMGIM36186.rgb.jpg/300x300bb.jpg',
    ),
    TrackMetadata(
      spotifyUrl: 'search:ROSÉ & Bruno Mars - APT.',
      title: 'APT.',
      artist: 'ROSÉ & Bruno Mars',
      album: 'rosie',
      releaseYear: '2024',
      durationSeconds: 169,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/8d/2c/0e/8d2c0e61-4d75-6217-1052-8e4e6e622382/075679630384.jpg/300x300bb.jpg',
    ),
    TrackMetadata(
      spotifyUrl: 'search:Katy Perry - The One That Got Away',
      title: 'The One That Got Away',
      artist: 'Katy Perry',
      album: 'Teenage Dream',
      releaseYear: '2010',
      durationSeconds: 227,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/7b/58/c2/7b58c21a-2b51-2bb2-e59d-9bb9b96ad8c3/00602527491769.rgb.jpg/300x300bb.jpg',
    ),
  ];

  static const List<TrackMetadata> _fallbackIndonesiaTrendingTracks = [
    TrackMetadata(
      spotifyUrl: 'search:Bernadya - Satu Bulan',
      title: 'Satu Bulan',
      artist: 'Bernadya',
      album: 'Sialnya, Hidup Harus Tetap Berjalan',
      releaseYear: '2024',
      durationSeconds: 200,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/7e/68/95/7e68952f-168a-510d-772b-a21c333b7a98/cover.jpg/300x300bb.jpg',
    ),
    TrackMetadata(
      spotifyUrl: 'search:Hindia - Evaluasi',
      title: 'Evaluasi',
      artist: 'Hindia',
      album: 'Menari Dengan Bayangan',
      releaseYear: '2019',
      durationSeconds: 194,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/91/06/29/9106299e-8b1e-1d06-2e82-9a9804393b0b/cover.jpg/300x300bb.jpg',
    ),
    TrackMetadata(
      spotifyUrl: 'search:Sal Priadi - Gala Bunga Matahari',
      title: 'Gala Bunga Matahari',
      artist: 'Sal Priadi',
      album: 'MARKERS AND SUCH PENS FLASHDISKS',
      releaseYear: '2024',
      durationSeconds: 209,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/b8/82/61/b882610c-5439-9942-3a89-243767349e13/cover.jpg/300x300bb.jpg',
    ),
    TrackMetadata(
      spotifyUrl: 'search:Mahalini - Mati-Matian',
      title: 'Mati-Matian',
      artist: 'Mahalini',
      album: 'Mati-Matian',
      releaseYear: '2024',
      durationSeconds: 242,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/c2/21/83/c2218314-8a42-3b69-7b92-360627051737/cover.jpg/300x300bb.jpg',
    ),
  ];

  final TextEditingController _inputController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  int _selectedTabIndex = _tabNowPlaying;
  int _allSongsSearchRequestId = 0;

  void _openAllSongsSearch() {
    setState(() {
      _selectedTabIndex = _tabPlaylists;
      _allSongsSearchRequestId++;
    });
  }

  void _triggerDiscoveryLoadIfNeeded({bool forceRefresh = false}) {
    if (!Platform.isAndroid && !forceRefresh) return;
    final dlProvider = context.read<DownloaderProvider>();
    final localProvider = context.read<LocalMusicProvider>();
    dlProvider.loadDiscoveryCarousels(
      localSongs: localProvider.allSongs,
      playCountResolver: localProvider.playCountFor,
      forceRefresh: forceRefresh,
    );
  }

  void _selectTab(int idx) {
    setState(() => _selectedTabIndex = idx);
    if (idx == _tabDownloader) {
      _triggerDiscoveryLoadIfNeeded();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupUnifiedSystemChannelListener();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<LocalMusicProvider>().checkPermissionsStatus(
            refreshIfNewlyGranted: true,
          );
    }
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
                  sessionId: (args['sessionId'] as num?)?.toInt(),
                  path: args['path']?.toString(),
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
                  sessionId: (args['sessionId'] as num?)?.toInt(),
                  path: args['path']?.toString(),
                );
          }
          break;

        case 'onLocalTrackCompleted':
          final args = call.arguments;
          context.read<LocalMusicProvider>().handleNativeTrackCompleted(
                sessionId:
                    args is Map ? (args['sessionId'] as num?)?.toInt() : null,
                path: args is Map ? args['path']?.toString() : null,
              );
          break;

        case 'onMediaNotificationAction':
          final args = call.arguments;
          if (args is Map) {
            final action = args['action']?.toString() ?? '';
            final posMs = (args['positionMs'] as num?)?.toInt() ?? 0;
            context.read<LocalMusicProvider>().handleMediaNotificationAction(
                  action: action,
                  positionMs: posMs,
                );
          }
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

    if (isCollection) {
      if (provider.state != DownloaderState.error &&
          provider.currentCollection != null &&
          provider.currentCollection!.tracks.isNotEmpty) {
        await _openBatchPlaylistSheet(provider);
      } else if (provider.state == DownloaderState.error) {
        await _showPrivatePlaylistErrorDialog(
          provider.errorMessage ??
              "Playlist Spotify ini berstatus Pribadi (Private) atau tidak dapat diakses. Silakan ubah pengaturan playlist di Spotify menjadi 'Publik' (Make Public) terlebih dahulu, lalu salin ulang link-nya.",
        );
      }
    } else if (provider.trackMetadata != null) {
      await _openTrackPreviewSheet(provider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    final isDirectLink = provider.isSpotifyTrackInput(raw) ||
        provider.isYoutubeInput(raw) ||
        raw.contains('spotify.com') ||
        raw.startsWith('spotify:track:');

    await provider.submitSmartInput(raw);
    if (!mounted) return;

    if (isCollection) {
      if (provider.state != DownloaderState.error &&
          provider.currentCollection != null &&
          provider.currentCollection!.tracks.isNotEmpty) {
        await _openBatchPlaylistSheet(provider);
      } else if (provider.state == DownloaderState.error) {
        await _showPrivatePlaylistErrorDialog(
          provider.errorMessage ??
              "Playlist Spotify ini berstatus Pribadi (Private) atau tidak dapat diakses. Silakan ubah pengaturan playlist di Spotify menjadi 'Publik' (Make Public) terlebih dahulu, lalu salin ulang link-nya.",
        );
      }
    } else if (isDirectLink && provider.trackMetadata != null) {
      await _openTrackPreviewSheet(provider);
    }
  }

  Future<void> _showPrivatePlaylistErrorDialog(String message) async {
    if (!mounted) return;
    final hairline = context.palette.hairline;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: context.palette.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: hairline, width: 0.8),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: Color(0xFFF79009),
                size: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Playlist Spotify Tidak Dapat Diakses',
                  style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: TextStyle(
              color: context.palette.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(
                'Mengerti',
                style: TextStyle(
                  color: context.palette.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
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
    if (!mounted ||
        collection == null ||
        collection.tracks.isEmpty ||
        provider.state == DownloaderState.error) {
      return;
    }
    await BatchPlaylistSheet.show(
      context,
      collection: collection,
      onCreateNewFolder: _showCreateFolderDialog,
    );
  }

  Future<void> _showCreateFolderDialog(DownloaderProvider provider) async {
    final hairline = context.palette.hairline;
    String currentDirPath = FolderService.baseMusicRoot;
    List<BrowsedDirectoryEntry> subDirs =
        await provider.folderService.browseStorageDirectories(currentDirPath);
    bool isLoadingDirs = false;

    if (!mounted) return;

    final pickedTarget = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> navigateToDir(String nextPath) async {
              setModalState(() {
                currentDirPath = nextPath;
                isLoadingDirs = true;
              });
              final loaded = await provider.folderService
                  .browseStorageDirectories(nextPath);
              if (ctx.mounted) {
                setModalState(() {
                  subDirs = loaded;
                  isLoadingDirs = false;
                });
              }
            }

            Future<void> promptNewSubfolder() async {
              final folderController = TextEditingController();
              final rawName = await showDialog<String>(
                context: ctx,
                builder: (dialogCtx) {
                  return AlertDialog(
                    backgroundColor: context.palette.surfaceCard,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: hairline, width: 0.8),
                    ),
                    title: Text(
                      'Buat Folder Musik Baru',
                      style: TextStyle(
                        color: context.palette.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Masukkan nama folder baru di $currentDirPath:',
                          style: TextStyle(
                            color: context.palette.textMuted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: folderController,
                          autofocus: true,
                          style: TextStyle(
                            color: context.palette.textPrimary,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Contoh: Music Anime / Music Indo',
                            prefixIcon: Icon(
                              Icons.create_new_folder_outlined,
                              color: context.palette.accent,
                              size: 19,
                            ),
                          ),
                          onSubmitted: (v) {
                            final t = v.trim();
                            if (t.isNotEmpty) Navigator.of(dialogCtx).pop(t);
                          },
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        child: Text(
                          'Batal',
                          style: TextStyle(color: context.palette.textMuted),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          final text = folderController.text.trim();
                          if (text.isNotEmpty) {
                            Navigator.of(dialogCtx).pop(text);
                          }
                        },
                        child: const Text('Buat & Pilih'),
                      ),
                    ],
                  );
                },
              );
              folderController.dispose();
              if (rawName != null && rawName.isNotEmpty && ctx.mounted) {
                final created = await provider.createAndSelectFolder(
                  rawName,
                  parentDirPath: currentDirPath,
                );
                if (ctx.mounted) {
                  Navigator.of(ctx).pop(created);
                }
              }
            }

            final canGoUp =
                currentDirPath.length > FolderService.baseStorageRoot.length &&
                currentDirPath.startsWith(FolderService.baseStorageRoot);
            final currentTargetLabel = FolderService.displayFolderChipLabel(
              provider.folderService.normalizePickedFolderTarget(currentDirPath),
            );

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.80,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: context.palette.textMuted.withValues(
                              alpha: 0.35,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.folder_open_rounded,
                            color: context.palette.accent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pilih atau Buat Folder Tujuan',
                              style: TextStyle(
                                color: context.palette.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: context.palette.accent,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: promptNewSubfolder,
                            icon: const Icon(
                              Icons.create_new_folder_outlined,
                              size: 16,
                            ),
                            label: const Text(
                              '+ Folder Baru',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Current Browsed Path Bar + Up Button
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: context.palette.surfaceSubtle,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: hairline, width: 0.8),
                        ),
                        child: Row(
                          children: [
                            if (canGoUp)
                              InkWell(
                                onTap: () {
                                  final lastSlash =
                                      currentDirPath.lastIndexOf('/');
                                  if (lastSlash > 0) {
                                    final parent = currentDirPath.substring(
                                      0,
                                      lastSlash,
                                    );
                                    navigateToDir(
                                      parent.isEmpty
                                          ? FolderService.baseStorageRoot
                                          : parent,
                                    );
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 17,
                                    color: context.palette.accent,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                currentDirPath,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.palette.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: context.palette.accent,
                                foregroundColor: Colors.white,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              onPressed: () async {
                                final chosen = await provider
                                    .selectOrAddCustomFolder(currentDirPath);
                                if (ctx.mounted) {
                                  Navigator.of(ctx).pop(chosen);
                                }
                              },
                              icon: const Icon(Icons.check_rounded, size: 15),
                              label: Text(
                                'Pilih "$currentTargetLabel"',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // System Folder Picker Option (`ACTION_OPEN_DOCUMENT_TREE`)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.palette.textPrimary,
                            backgroundColor: context.palette.bgCanvas,
                            side: BorderSide(color: hairline, width: 0.8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            final picked =
                                await provider.pickAndSelectSystemDirectory();
                            if (picked != null &&
                                picked.isNotEmpty &&
                                ctx.mounted) {
                              Navigator.of(ctx).pop(picked);
                            }
                          },
                          icon: Icon(
                            Icons.folder_copy_rounded,
                            size: 16,
                            color: context.palette.accent,
                          ),
                          label: const Text(
                            'Buka Pemilih Folder Sistem Android (Storage Explorer)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      Text(
                        'Subfolder di dalam direktori ini (ketuk untuk masuk, atau ketuk "Pilih"):',
                        style: TextStyle(
                          color: context.palette.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),

                      Flexible(
                        child: isLoadingDirs
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: context.palette.accent,
                                  ),
                                ),
                              )
                            : subDirs.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 18,
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Belum ada subfolder di $currentDirPath.\nKamu bisa memilih direktori ini langsung atau ketuk "+ Folder Baru".',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: context.palette.textMuted,
                                          fontSize: 12,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: subDirs.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 6),
                                    itemBuilder: (_, idx) {
                                      final entry = subDirs[idx];
                                      return Material(
                                        color: context.palette.surfaceSubtle,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          side: BorderSide(
                                            color: hairline,
                                            width: 0.8,
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          onTap: () =>
                                              navigateToDir(entry.path),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 9,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.folder_rounded,
                                                  color: context.palette.accent,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        entry.name,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color: context.palette.textPrimary,
                                                          fontSize: 13.5,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                      Text(
                                                        '${entry.mp3Count} file MP3',
                                                        style: TextStyle(
                                                          color: context.palette.textMuted,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                TextButton(
                                                  style: TextButton.styleFrom(
                                                    foregroundColor:
                                                        context.palette.accent,
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                  ),
                                                  onPressed: () async {
                                                    final chosen = await provider
                                                        .selectOrAddCustomFolder(
                                                      entry.path,
                                                    );
                                                    if (ctx.mounted) {
                                                      Navigator.of(ctx)
                                                          .pop(chosen);
                                                    }
                                                  },
                                                  child: const Text(
                                                    'Pilih',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (pickedTarget != null && pickedTarget.isNotEmpty && mounted) {
      context.read<LocalMusicProvider>().registerFolder(pickedTarget);
      final label = FolderService.displayFolderChipLabel(pickedTarget);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Folder tujuan "$label" siap digunakan.'),
        ),
      );
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
    final hairline = context.palette.hairline;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.surfaceCard,
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
                      color: context.palette.textMuted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.palette.textMuted, fontSize: 12.5),
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
                        backgroundColor: context.palette.surfaceSubtle,
                        selectedColor: context.palette.accent,
                        side: BorderSide(
                          color: isCurrent ? context.palette.accent : hairline,
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
                              color: isCurrent ? Colors.white : context.palette.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isCurrent ? '$folder (Saat Ini)' : folder,
                              style: TextStyle(
                                color: isCurrent ? Colors.white : context.palette.textPrimary,
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
                      backgroundColor: context.palette.surfaceCard,
                      side: BorderSide(color: hairline, width: 0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      avatar: Icon(
                        Icons.add_rounded,
                        size: 15,
                        color: context.palette.accent,
                      ),
                      label: Text(
                        'Folder Baru',
                        style: TextStyle(
                          color: context.palette.accent,
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
    return Consumer2<DownloaderProvider, LocalMusicProvider>(
      builder: (context, provider, localProvider, _) {
        final activeQueueCount = provider.activeQueueCount;
        final isDirectDownloadActive =
            provider.state == DownloaderState.downloadingAudio ||
            provider.state == DownloaderState.taggingAudio;
        final totalActiveCount =
            activeQueueCount + (isDirectDownloadActive ? 1 : 0);

        final isOnNowPlaying = _selectedTabIndex == _tabNowPlaying;

        return Scaffold(
          backgroundColor: context.palette.bgCanvas,
          body: SafeArea(
            top: !isOnNowPlaying,
            bottom: false,
            child: Column(
              children: [
                // Dismissible Dark Minimalist First-Run Permission Onboarding Banner
                if (!isOnNowPlaying &&
                    localProvider.shouldShowPermissionOnboarding)
                  _buildPermissionOnboardingBanner(localProvider),

                Expanded(
                  child: AnimatedIndexedStack(
                    index: _selectedTabIndex,
                    duration: const Duration(milliseconds: 200),
                    children: [
                      // 0: Queue (`=♪`)
                      PlaybackQueueView(
                        onOpenNowPlaying: () => _selectTab(_tabNowPlaying),
                        onNavigateToDownloader: () =>
                            _selectTab(_tabDownloader),
                      ),

                      // 1: Now Playing (MusEvee Phase 1 Redesign)
                      NowPlayingView(
                        isVisible: isOnNowPlaying,
                        onNavigateToDownloader: () =>
                            _selectTab(_tabDownloader),
                        onNavigateToFolders: () => _selectTab(_tabFolders),
                        onMoveLocalSongFolder: _showMoveLocalSongFolderSheet,
                      ),

                      // 2: Folders (`📁` + Multi-Folder Queue Merger)
                      LocalFoldersView(
                        onOpenNowPlaying: () => _selectTab(_tabNowPlaying),
                        onCreateNewFolder: _showCreateFolderDialog,
                        onMoveLocalSongFolder: _showMoveLocalSongFolderSheet,
                        onOpenAllSongsSearch: _openAllSongsSearch,
                      ),

                      // 3: Playlists (`musicevee_playlists_v1.json` + Multi-Playlist Queue Merger)
                      LocalPlaylistsView(
                        onOpenNowPlaying: () => _selectTab(_tabNowPlaying),
                        onMoveLocalSongFolder: _showMoveLocalSongFolderSheet,
                        onOpenAllSongsSearch: _openAllSongsSearch,
                        openAllSongsSearchRequestId: _allSongsSearchRequestId,
                      ),

                      // 4: Downloader (`⬇` Cloud Download — Smart Omnibox + 3 Discovery Carousels + Queue/History Sheet Trigger)
                      _buildSearchAndDownloadTab(
                        provider,
                        localProvider,
                        totalActiveCount,
                      ),

                      // 5: Settings (`⚙`)
                      const SettingsView(),
                    ],
                  ),
                ),

                // Thin Download Progress / Dismissible Warning Banner
                if (provider.shouldShowStatusBanner)
                  _buildFloatingMiniProgressBanner(provider),

                // Musicolet Thin Mini Player on all non-Now-Playing tabs
                if (!isOnNowPlaying)
                  MusicoletMiniPlayer(
                    onTapOpenNowPlaying: () => _selectTab(_tabNowPlaying),
                  ),
              ],
            ),
          ),
          bottomNavigationBar: MusicoletBottomStrip(
            selectedIndex: _selectedTabIndex,
            activeDownloadBadgeCount: totalActiveCount,
            onTabSelected: _selectTab,
          ),
        );
      },
    );
  }

  Widget _buildPermissionOnboardingBanner(LocalMusicProvider localProvider) {
    final hairline = context.palette.hairline;
    final missingAllFiles = !localProvider.hasAllFilesAccess;
    final missingNotif = !localProvider.hasNotificationPermission;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: context.palette.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: context.palette.accent.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: context.palette.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.verified_user_outlined,
                  color: context.palette.accent,
                  size: 15,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Setup Izin Cepat MusEvee',
                      style: TextStyle(
                        color: context.palette.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Aktifkan akses penuh agar fitur hapus lagu, pindah folder, edit tag/lirik berjalan 1 klik, serta notifikasi & Live Island tampil otomatis.',
                      style: TextStyle(
                        color: context.palette.textMuted,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                tooltip: 'Sembunyikan',
                onPressed: localProvider.dismissPermissionBanner,
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: context.palette.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (missingAllFiles)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.palette.textPrimary,
                    backgroundColor: context.palette.accent.withValues(alpha: 0.18),
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    side: BorderSide(
                      color: context.palette.accent.withValues(alpha: 0.6),
                      width: 0.8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: () =>
                      localProvider.requestAllFilesAccessPermission(),
                  icon: const Icon(Icons.folder_special_rounded, size: 14),
                  label: const Text(
                    'Aktifkan Akses File Penuh',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (missingNotif)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.palette.textPrimary,
                    backgroundColor: context.palette.surfaceSubtle,
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
                  onPressed: () =>
                      localProvider.requestNotificationAndLiveIslandPermission(),
                  icon: Icon(
                    Icons.notifications_active_outlined,
                    size: 14,
                    color: context.palette.accent,
                  ),
                  label: const Text(
                    'Aktifkan Notifikasi & Live Island',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // MODAL BOTTOM SHEET: ANTREAN & RIWAYAT UNDUHAN (88% TINGGI LAYAR)
  // ===========================================================================
  Future<void> _openDownloadQueueHistorySheet() async {
    if (!mounted) return;
    final hairline = context.palette.hairline;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
                decoration: BoxDecoration(
                  color: context.palette.surfaceCard,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  border: Border(
                    bottom: BorderSide(color: hairline, width: 0.8),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.palette.textMuted.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.downloading_rounded,
                          size: 18,
                          color: context.palette.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Antrean & Riwayat Unduhan',
                            style: TextStyle(
                              color: context.palette.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Tutup',
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 19,
                            color: context.palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Consumer<DownloaderProvider>(
                  builder: (ctx, dlProvider, _) {
                    return QueueHistoryView(
                      provider: dlProvider,
                      onMoveFolder: _showMoveFolderSheet,
                      onPlaySavedFile: (savedPath) async {
                        if (Navigator.of(sheetCtx).canPop()) {
                          Navigator.of(sheetCtx).pop();
                        }
                        await context
                            .read<LocalMusicProvider>()
                            .playSongByPath(savedPath);
                        if (mounted) {
                          setState(() => _selectedTabIndex = _tabNowPlaying);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDownloadQueueButton(
    DownloaderProvider provider,
    int totalActiveCount,
  ) {
    final hairline = context.palette.hairline;
    final hasHistory = provider.queueItems.isNotEmpty;
    final isActive = totalActiveCount > 0 || provider.isDownloading;

    return PressableScale(
      onTap: _openDownloadQueueHistorySheet,
      child: Tooltip(
        message: 'Antrean & Riwayat Unduhan',
        child: Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: isActive
                ? context.palette.accent.withValues(alpha: 0.16)
                : context.palette.surfaceSubtle,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? context.palette.accent.withValues(alpha: 0.55)
                  : hairline,
              width: 0.8,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (isActive)
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    value: provider.progress > 0.02 && provider.progress < 0.99
                        ? provider.progress.clamp(0.0, 1.0)
                        : null,
                    strokeWidth: 2.0,
                    color: context.palette.accent,
                    backgroundColor: context.palette.hairline,
                  ),
                ),
              Icon(
                isActive
                    ? Icons.downloading_rounded
                    : Icons.playlist_add_check_circle_outlined,
                size: isActive ? 16 : 20,
                color: isActive
                    ? context.palette.accent
                    : (hasHistory ? context.palette.textPrimary : context.palette.textMuted),
              ),
              if (totalActiveCount > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.5,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 15,
                    ),
                    decoration: BoxDecoration(
                      color: MusEveePalette.error,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: context.palette.surfaceCard, width: 1.2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      totalActiveCount > 99 ? '99+' : '$totalActiveCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ),
                )
              else if (hasHistory)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: context.palette.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 4: DOWNLOADER (`⬇` — Smart Omnibox + 3 Discovery Carousels + Search Results)
  // ===========================================================================
  Widget _buildSearchAndDownloadTab(
    DownloaderProvider provider,
    LocalMusicProvider localProvider,
    int totalActiveCount,
  ) {
    final results = provider.searchResults;
    final rawText = _inputController.text.trim();
    final isSpotify =
        rawText.contains('spotify.com') || rawText.startsWith('spotify:track:');
    final hairline = context.palette.hairline;

    return Container(
      color: context.palette.bgCanvas,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: context.palette.surfaceCard,
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
                        style: TextStyle(
                          color: context.palette.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                        onChanged: (_) {
                          provider.clearTransientErrorOnTyping();
                          setState(() {});
                        },
                        onSubmitted: (_) => _submitOmnibox(provider),
                        decoration: InputDecoration(
                          hintText: AppStrings.omniboxHint,
                          fillColor: context.palette.surfaceSubtle,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          prefixIcon: Icon(
                            isSpotify
                                ? Icons.link_rounded
                                : Icons.cloud_download_outlined,
                            color: isSpotify ? context.palette.accent : context.palette.textMuted,
                            size: 19,
                          ),
                          suffixIcon: rawText.isEmpty
                              ? TextButton(
                                  onPressed: provider.isBusy
                                      ? null
                                      : () => _pasteAndSubmit(provider),
                                  child: Text(
                                    AppStrings.pasteButton,
                                    style: TextStyle(
                                      color: context.palette.accent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  tooltip: AppStrings.clearTooltip,
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: context.palette.textMuted,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _inputController.clear();
                                    provider.clearTransientErrorOnTyping();
                                    if (provider.state ==
                                            DownloaderState.error ||
                                        provider.searchResults.isNotEmpty) {
                                      provider.reset();
                                    }
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
                            backgroundColor: context.palette.accent,
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
                            isSpotify
                                ? AppStrings.openButton
                                : AppStrings.searchButton,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    _buildDownloadQueueButton(provider, totalActiveCount),
                  ],
                ),
                const SizedBox(height: 8),

                // Supported Input Feature Badges (Search Title/Artist + Romaji, YouTube/YTM, Spotify Track/Album/Playlist)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildDownloaderCapabilityPill(
                        icon: Icons.music_note_rounded,
                        iconColor: context.palette.accent,
                        label: AppStrings.capabilityTitleArtist,
                        hairline: hairline,
                      ),
                      const SizedBox(width: 6),
                      _buildDownloaderCapabilityPill(
                        icon: Icons.play_circle_fill_rounded,
                        iconColor: const Color(0xFFFF4444),
                        label: AppStrings.capabilityYoutube,
                        hairline: hairline,
                      ),
                      const SizedBox(width: 6),
                      _buildDownloaderCapabilityPill(
                        icon: Icons.album_rounded,
                        iconColor: const Color(0xFF1ED760),
                        label: AppStrings.capabilitySpotify,
                        hairline: hairline,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Target Folder Chips (`Music Barat`, `Music Japan`, `Music Random`, `+`)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 14,
                        color: context.palette.textMuted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        AppStrings.saveToLabel,
                        style: TextStyle(
                          color: context.palette.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ...provider.availableFolders.map((folder) {
                        final isSelected = folder == provider.selectedFolder;
                        final chipLabel =
                            FolderService.displayFolderChipLabel(folder);
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            selected: isSelected,
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            backgroundColor: context.palette.surfaceSubtle,
                            selectedColor: context.palette.accent,
                            side: BorderSide(
                              color: isSelected ? context.palette.accent : hairline,
                              width: 0.8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            label: Text(
                              chipLabel,
                              style: TextStyle(
                                color:
                                    isSelected ? Colors.white : context.palette.textPrimary,
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
                        tooltip: 'Pilih atau Buat Folder Tujuan',
                        visualDensity: VisualDensity.compact,
                        backgroundColor: context.palette.surfaceCard,
                        side: BorderSide(color: hairline, width: 0.8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        avatar: Icon(
                          Icons.create_new_folder_rounded,
                          size: 14,
                          color: context.palette.accent,
                        ),
                        label: Text(
                          '+',
                          style: TextStyle(
                            color: context.palette.accent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
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
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: context.palette.accent,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          AppStrings.searchingCatalogStatus,
                          style: TextStyle(
                            color: context.palette.textMuted,
                            fontSize: 13,
                          ),
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
                    : _buildDownloaderEmptyState(provider, localProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloaderCapabilityPill({
    required IconData icon,
    required Color iconColor,
    required String label,
    required Color hairline,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.palette.surfaceSubtle.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: hairline, width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: iconColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: context.palette.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloaderEmptyState(
    DownloaderProvider provider,
    LocalMusicProvider localProvider,
  ) {
    final hairline = context.palette.hairline;
    final isOffline =
        provider.isDiscoveryOffline ||
        (provider.state == DownloaderState.error && provider.isOfflineError);

    final forYouItems = provider.forYouTracks.isNotEmpty
        ? provider.forYouTracks
        : _fallbackForYouTracks;
    final globalItems = provider.globalTrendingTracks.isNotEmpty
        ? provider.globalTrendingTracks
        : _fallbackGlobalTrendingTracks;
    final indonesiaItems = provider.indonesiaTrendingTracks.isNotEmpty
        ? provider.indonesiaTrendingTracks
        : _fallbackIndonesiaTrendingTracks;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        if (isOffline) ...[
          _buildOfflineStateCard(provider, hairline),
          const SizedBox(height: 12),
        ],

        // Header Info Card (compact)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: context.palette.surfaceCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hairline, width: 0.8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.cloud_download_rounded,
                color: context.palette.accent,
                size: 18,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.downloaderCardTitle,
                      style: TextStyle(
                        color: context.palette.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.downloaderCardDesc,
                      style: TextStyle(
                        color: context.palette.textMuted,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (provider.isLoadingDiscovery)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: context.palette.accent,
                    ),
                  ),
                )
              else
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: AppStrings.refreshRetryButton,
                  onPressed: () {
                    provider.dismissStatusBanner();
                    _triggerDiscoveryLoadIfNeeded(forceRefresh: true);
                  },
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: 17,
                    color: context.palette.textMuted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 1. FOR YOU / UNTUKMU HORIZONTAL CAROUSEL
        _buildDiscoveryCarouselSection(
          sectionKey: const ValueKey('carousel_for_you'),
          title: AppStrings.forYouTitle,
          subtitle: AppStrings.forYouSubtitle(provider.forYouSeedArtists),
          icon: Icons.auto_awesome_rounded,
          iconColor: context.palette.accent,
          tracks: forYouItems,
          provider: provider,
          hairline: hairline,
        ),
        const SizedBox(height: 14),

        // 2. GLOBAL TRENDING HORIZONTAL CAROUSEL
        _buildDiscoveryCarouselSection(
          sectionKey: const ValueKey('carousel_global_trending'),
          title: AppStrings.globalTrendingTitle,
          subtitle: AppStrings.globalTrendingSubtitle,
          icon: Icons.public_rounded,
          iconColor: const Color(0xFF1ED760),
          tracks: globalItems,
          provider: provider,
          hairline: hairline,
        ),
        const SizedBox(height: 14),

        // 3. INDONESIA TRENDING HORIZONTAL CAROUSEL
        _buildDiscoveryCarouselSection(
          sectionKey: const ValueKey('carousel_indonesia_trending'),
          title: AppStrings.indonesiaTrendingTitle,
          subtitle: AppStrings.indonesiaTrendingSubtitle,
          icon: Icons.local_fire_department_rounded,
          iconColor: const Color(0xFFFF7A45),
          tracks: indonesiaItems,
          provider: provider,
          hairline: hairline,
        ),
      ],
    );
  }

  Widget _buildOfflineStateCard(
    DownloaderProvider provider,
    Color hairline,
  ) {
    return Container(
      key: const ValueKey('downloader_offline_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: MusEveePalette.error.withValues(alpha: 0.45),
          width: 0.9,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: MusEveePalette.error.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.wifi_off_rounded,
              color: MusEveePalette.error,
              size: 18,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.offlineTitle,
                  style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  AppStrings.offlineSubtitle,
                  style: TextStyle(
                    color: context.palette.textMuted,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('downloader_offline_retry_button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.palette.textPrimary,
                    backgroundColor: context.palette.accent.withValues(alpha: 0.18),
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    side: BorderSide(
                      color: context.palette.accent.withValues(alpha: 0.65),
                      width: 0.8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: provider.isBusy
                      ? null
                      : () {
                          provider.dismissStatusBanner();
                          if (_inputController.text.trim().isNotEmpty) {
                            _submitOmnibox(provider);
                          } else {
                            _triggerDiscoveryLoadIfNeeded(forceRefresh: true);
                          }
                        },
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: Text(
                    AppStrings.refreshRetryButton,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveryCarouselSection({
    required Key sectionKey,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required List<TrackMetadata> tracks,
    required DownloaderProvider provider,
    required Color hairline,
  }) {
    return Column(
      key: sectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: context.palette.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.15,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.palette.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 154,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tracks.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final track = tracks[index];
              final duplicateFolder = provider.duplicateFolderFor(track);
              return _buildDiscoveryTrackCard(
                track: track,
                duplicateFolder: duplicateFolder,
                hairline: hairline,
                onTap: provider.isBusy
                    ? null
                    : () => _onTapSearchResult(provider, track),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDiscoveryTrackCard({
    required TrackMetadata track,
    required String? duplicateFolder,
    required Color hairline,
    required VoidCallback? onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 110,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: context.palette.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: hairline, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Compact 98x94 Album Art (decoded at 140x140 in RAM only — 0 KB persistent disk)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 98,
                height: 94,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (track.coverUrl.isNotEmpty)
                      Image.network(
                        track.coverUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 140,
                        cacheHeight: 140,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildCarouselCoverPlaceholder(),
                      )
                    else
                      _buildCarouselCoverPlaceholder(),
                    if (duplicateFolder != null)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            size: 11,
                            color: Color(0xFF4CAF50),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.palette.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.palette.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarouselCoverPlaceholder() {
    return Container(
      color: context.palette.surfaceSubtle,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        color: context.palette.textMuted,
        size: 26,
      ),
    );
  }

  // ===========================================================================
  // FLOATING MINI DOWNLOAD PROGRESS / DISMISSIBLE WARNING BANNER
  // ===========================================================================
  Widget _buildFloatingMiniProgressBanner(DownloaderProvider provider) {
    final isError = provider.state == DownloaderState.error;
    final pct = (provider.progress * 100).round();
    final hairline = context.palette.hairline;

    return Material(
      color: context.palette.surfaceCard,
      child: InkWell(
        onTap: _openDownloadQueueHistorySheet,
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
              if (provider.isDownloading)
                LinearProgressIndicator(
                  value: provider.progress.clamp(0.0, 1.0),
                  minHeight: 2.0,
                  backgroundColor: context.palette.surfaceSubtle,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(context.palette.accent),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    if (provider.isDownloading)
                      SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.palette.accent,
                        ),
                      )
                    else
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isError ? MusEveePalette.error : context.palette.accent,
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
                          color: isError ? MusEveePalette.error : context.palette.textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (provider.isDownloading) ...[
                      const SizedBox(width: 8),
                      Text(
                        '$pct%',
                        style: TextStyle(
                          color: context.palette.accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 4),
                      IconButton(
                        key: const ValueKey('dismiss_status_banner_button'),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        tooltip: AppStrings.closeTooltip,
                        onPressed: provider.dismissStatusBanner,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: context.palette.textMuted,
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

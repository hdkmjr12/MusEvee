import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/curated_playlist.dart';
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

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
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
      spotifyUrl: "search:Why Don't We - 8 Letters",
      title: '8 Letters',
      artist: "Why Don't We",
      album: '8 Letters',
      releaseYear: '2018',
      durationSeconds: 190,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/30/1e/8c/301e8c07-28d8-7917-7440-6923c8965f32/075679866387.jpg/300x300bb.jpg',
    ),
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
  ];

  static const List<TrackMetadata> _fallbackNewReleasesTracks = [
    TrackMetadata(
      spotifyUrl: 'search:Conan Gray - Memories',
      title: 'Memories',
      artist: 'Conan Gray',
      album: 'Superache',
      releaseYear: '2022',
      durationSeconds: 248,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/c6/16/e0/c616e0be-684a-38d7-5d29-c8167f1362e6/22UMGIM41457.rgb.jpg/300x300bb.jpg',
    ),
    TrackMetadata(
      spotifyUrl: 'search:9lana - Propose',
      title: 'Propose',
      artist: '9lana',
      album: 'Propose',
      releaseYear: '2024',
      durationSeconds: 195,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/72/75/a6/7275a6c1-ca19-a2e6-71d1-678c3cf0d9a6/jacket_VVXX01601B00Z_550.jpg/300x300bb.jpg',
    ),
    TrackMetadata(
      spotifyUrl: 'search:Tiara Andini - Maafkan Aku #terlanjurluka',
      title: 'Maafkan Aku #terlanjurluka',
      artist: 'Tiara Andini',
      album: 'Tiara Andini',
      releaseYear: '2020',
      durationSeconds: 224,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/96/98/9c/96989cb5-ef52-6582-8bc1-64d85250425a/20UMGIM46096.rgb.jpg/300x300bb.jpg',
    ),
    TrackMetadata(
      spotifyUrl: "search:Why Don't We - 8 Letters",
      title: '8 letters',
      artist: "Why Don't We",
      album: '8 Letters',
      releaseYear: '2018',
      durationSeconds: 190,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/30/1e/8c/301e8c07-28d8-7917-7440-6923c8965f32/075679866387.jpg/300x300bb.jpg',
    ),
    TrackMetadata(
      spotifyUrl: 'search:Bruno Mars - Locked Out of Heaven',
      title: 'Locked Out of Heaven',
      artist: 'Bruno Mars',
      album: 'Unorthodox Jukebox',
      releaseYear: '2012',
      durationSeconds: 233,
      coverUrl:
          'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/55/e8/e1/55e8e19e-e478-f7ef-b676-e82209930f3a/075679963772.jpg/300x300bb.jpg',
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
  final GlobalKey<LocalFoldersViewState> _foldersViewKey =
      GlobalKey<LocalFoldersViewState>();
  final GlobalKey<LocalPlaylistsViewState> _playlistsViewKey =
      GlobalKey<LocalPlaylistsViewState>();

  int _selectedTabIndex = _tabNowPlaying;
  int _allSongsSearchRequestId = 0;

  bool _isSearchExpanded = false;
  String _searchHint = AppStrings.searchGenericHint;
  late final AnimationController _searchBarAnimController;
  late final Animation<double> _searchBarAnimation;

  void _expandSearch({String? hint}) {
    setState(() {
      _isSearchExpanded = true;
      if (hint != null) _searchHint = hint;
    });
    _searchBarAnimController.forward();
    _searchFocusNode.requestFocus();
  }

  void _collapseSearch() {
    _searchFocusNode.unfocus();
    _searchBarAnimController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _isSearchExpanded = false;
          _searchHint = AppStrings.searchGenericHint;
        });
      }
    });
    final provider = context.read<DownloaderProvider>();
    if (_inputController.text.isEmpty &&
        (provider.state == DownloaderState.error ||
            provider.searchResults.isNotEmpty)) {
      provider.reset();
    }
  }

  Future<void> _handleBackNavigation() async {
    if (!mounted) return;
    if (_selectedTabIndex == _tabFolders &&
        (_foldersViewKey.currentState?.handleBack() ?? false)) {
      return;
    }
    if (_selectedTabIndex == _tabPlaylists &&
        (_playlistsViewKey.currentState?.handleBack() ?? false)) {
      return;
    }
    if (_selectedTabIndex == _tabDownloader) {
      if (_isSearchExpanded) {
        _collapseSearch();
        return;
      }
      final provider = context.read<DownloaderProvider>();
      if (provider.searchResults.isNotEmpty) {
        provider.reset();
        return;
      }
    }
    if (_selectedTabIndex != _tabNowPlaying) {
      _selectTab(_tabNowPlaying);
      return;
    }

    final isPlaying = context.read<LocalMusicProvider>().isPlaying;
    if (isPlaying) {
      try {
        await _systemChannel.invokeMethod<bool>('moveToBackground');
      } catch (_) {}
      return;
    }

    await SystemNavigator.pop();
  }

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
    _searchBarAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _searchBarAnimation = CurvedAnimation(
      parent: _searchBarAnimController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _setupUnifiedSystemChannelListener();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    super.didChangeLocales(locales);
    if (mounted) {
      setState(() {});
    }
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
    setState(() {
      _selectedTabIndex = _tabDownloader;
      _isSearchExpanded = true;
    });
    _searchBarAnimController.value = 1.0;

    final provider = context.read<DownloaderProvider>();
    final isCollection = provider.isCollectionInput(sharedText);
    await provider.submitSmartInput(sharedText);
    if (!mounted) return;

    if (isCollection) {
      if (provider.state != DownloaderState.error &&
          provider.currentCollection != null &&
          provider.currentCollection!.tracks.isNotEmpty) {
        await _openBatchPlaylistSheet(provider);
      } else if (provider.state == DownloaderState.error) {
        await _showPrivatePlaylistErrorDialog(
          provider.errorMessage ?? AppStrings.spotifyPrivatePlaylistMessage,
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
    _searchBarAnimController.dispose();
    super.dispose();
  }

  Future<void> _submitOmnibox(DownloaderProvider provider) async {
    final raw = _inputController.text.trim();
    if (raw.isEmpty || provider.isBusy) return;
    FocusScope.of(context).unfocus();

    final isCollection = provider.isCollectionInput(raw);
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
          provider.errorMessage ?? AppStrings.spotifyPrivatePlaylistMessage,
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
          backgroundColor: context.palette.nowPlayingBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: hairline, width: 0.8),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: MusEveePalette.amber,
                size: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppStrings.spotifyPrivatePlaylistTitle,
                  style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
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
            MographSpringTap(
              pressedScale: 0.90,
              child: TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: Text(
                  AppStrings.understoodLabel,
                  style: TextStyle(
                    color: context.palette.nowPlayingPrimary,
                    fontWeight: FontWeight.w600,
                  ),
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
      backgroundColor: context.palette.nowPlayingBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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
                    backgroundColor: context.palette.nowPlayingBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: hairline, width: 0.8),
                    ),
                    title: Text(
                      AppStrings.createMusicFolderTitle,
                      style: TextStyle(
                        color: context.palette.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.createMusicFolderPrompt(currentDirPath),
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
                          cursorColor: context.palette.nowPlayingPrimary,
                          style: TextStyle(
                            color: context.palette.textPrimary,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: AppStrings.createMusicFolderHint,
                            prefixIcon: Icon(
                              Icons.create_new_folder_outlined,
                              color: context.palette.nowPlayingPrimary,
                              size: 19,
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: context.palette.nowPlayingPrimary,
                                width: 1.4,
                              ),
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
                      MographSpringTap(
                        pressedScale: 0.90,
                        child: TextButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          child: Text(
                            AppStrings.cancelLabel,
                            style: TextStyle(color: context.palette.textMuted),
                          ),
                        ),
                      ),
                      MographSpringTap(
                        pressedScale: 0.94,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: context.palette.nowPlayingPrimary,
                            foregroundColor:
                                context.palette.nowPlayingOnPrimary,
                          ),
                          onPressed: () {
                            final text = folderController.text.trim();
                            if (text.isNotEmpty) {
                              Navigator.of(dialogCtx).pop(text);
                            }
                          },
                          child: Text(AppStrings.createAndSelectLabel),
                        ),
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
              provider.folderService
                  .normalizePickedFolderTarget(currentDirPath),
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
                            color: context.palette.nowPlayingPrimary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              AppStrings.pickOrCreateFolderTitle,
                              style: TextStyle(
                                color: context.palette.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          MographSpringTap(
                            pressedScale: 0.92,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    context.palette.nowPlayingPrimary,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: promptNewSubfolder,
                              icon: const Icon(
                                Icons.create_new_folder_outlined,
                                size: 16,
                              ),
                              label: Text(
                                AppStrings.plusNewFolderLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
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
                                    color: context.palette.nowPlayingPrimary,
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
                            MographSpringTap(
                              pressedScale: 0.94,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  backgroundColor:
                                      context.palette.nowPlayingPrimary,
                                  foregroundColor:
                                      context.palette.nowPlayingOnPrimary,
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
                                  AppStrings.selectTargetFolder(
                                    currentTargetLabel,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
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
                        child: MographSpringTap(
                          pressedScale: 0.98,
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
                              color: context.palette.nowPlayingPrimary,
                            ),
                            label: Text(
                              AppStrings.openAndroidFolderPickerLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      Text(
                        AppStrings.subfolderHintText,
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
                                    color: context.palette.nowPlayingPrimary,
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
                                        AppStrings.noSubfoldersText(
                                          currentDirPath,
                                        ),
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
                                                  color: context.palette
                                                      .nowPlayingPrimary,
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
                                                          color: context.palette
                                                              .textPrimary,
                                                          fontSize: 13.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      Text(
                                                        AppStrings.tr(
                                                          '${entry.audioCount} file audio',
                                                          '${entry.audioCount} ${entry.audioCount == 1 ? 'audio file' : 'audio files'}',
                                                          ctx,
                                                        ),
                                                        style: TextStyle(
                                                          color: context.palette
                                                              .textMuted,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                MographSpringTap(
                                                  child: TextButton(
                                                    style: TextButton.styleFrom(
                                                      foregroundColor: context
                                                          .palette
                                                          .nowPlayingPrimary,
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
                                                    child: Text(
                                                      AppStrings
                                                          .selectShortLabel,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
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
          content: Text(AppStrings.targetFolderReady(label)),
        ),
      );
    }
  }

  Future<void> _showMoveFolderSheet(
    DownloaderProvider provider,
    DownloadItem item,
  ) async {
    final chosenFolder = await _pickTargetFolderModal(
      title: AppStrings.moveSongFolderTitle,
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
            content: Text(AppStrings.movedToFolder(targetFolder)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.moveSongFailed(e))),
        );
      }
    }
  }

  Future<void> _showMoveLocalSongFolderSheet(LocalSong song) async {
    final downloader = context.read<DownloaderProvider>();
    final localMusic = context.read<LocalMusicProvider>();

    final chosenFolder = await _pickTargetFolderModal(
      title: AppStrings.moveLocalSongFolderTitle,
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
            content: Text(AppStrings.localSongMovedToFolder(targetFolder)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.moveLocalSongFailed(e))),
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
      backgroundColor: context.palette.nowPlayingBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.palette.textMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...availableFolders.map((folder) {
                      final isCurrent = folder == currentFolder;
                      return MographSpringTap(
                        enabled: !isCurrent,
                        child: ChoiceChip(
                          selected: isCurrent,
                          showCheckmark: false,
                          backgroundColor: context.palette.surfaceSubtle,
                          selectedColor: context.palette.nowPlayingPrimary,
                          side: BorderSide(
                            color: isCurrent
                                ? context.palette.nowPlayingPrimary
                                : hairline,
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
                                color: isCurrent
                                    ? context.palette.nowPlayingOnPrimary
                                    : context.palette.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isCurrent
                                    ? AppStrings.folderCurrentSuffix(folder)
                                    : folder,
                                style: TextStyle(
                                  color: isCurrent
                                      ? context.palette.nowPlayingOnPrimary
                                      : context.palette.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          onSelected: isCurrent
                              ? null
                              : (_) => Navigator.of(ctx).pop(folder),
                        ),
                      );
                    }),
                    MographSpringTap(
                      child: ActionChip(
                        backgroundColor: context.palette.nowPlayingBg,
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
                          color: context.palette.nowPlayingPrimary,
                        ),
                        label: Text(
                          AppStrings.newFolderLabel,
                          style: TextStyle(
                            color: context.palette.nowPlayingPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () => Navigator.of(ctx).pop('__NEW__'),
                      ),
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
    SystemLocaleScope.watch(context);
    return Consumer2<DownloaderProvider, LocalMusicProvider>(
      builder: (context, provider, localProvider, _) {
        final activeQueueCount = provider.activeQueueCount;
        final isDirectDownloadActive =
            provider.state == DownloaderState.downloadingAudio ||
                provider.state == DownloaderState.taggingAudio;
        final totalActiveCount =
            activeQueueCount + (isDirectDownloadActive ? 1 : 0);

        final isOnNowPlaying = _selectedTabIndex == _tabNowPlaying;
        final showOnboardingBanner =
            !isOnNowPlaying && localProvider.shouldShowPermissionOnboarding;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _handleBackNavigation();
          },
          child: Scaffold(
            backgroundColor: context.palette.bgCanvas,
            body: SafeArea(
              top: false,
              bottom: false,
              child: Column(
                children: [
                  // Dismissible Dark Minimalist First-Run Permission Onboarding Banner
                  if (showOnboardingBanner)
                    SafeArea(
                      bottom: false,
                      child: _buildPermissionOnboardingBanner(localProvider),
                    ),

                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: showOnboardingBanner,
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
                            onMoveLocalSongFolder:
                                _showMoveLocalSongFolderSheet,
                          ),

                          // 2: Folders (`📁` + Multi-Folder Queue Merger)
                          LocalFoldersView(
                            key: _foldersViewKey,
                            onOpenNowPlaying: () => _selectTab(_tabNowPlaying),
                            onCreateNewFolder: _showCreateFolderDialog,
                            onMoveLocalSongFolder:
                                _showMoveLocalSongFolderSheet,
                            onOpenAllSongsSearch: _openAllSongsSearch,
                          ),

                          // 3: Playlists (`musicevee_playlists_v1.json` + Multi-Playlist Queue Merger)
                          LocalPlaylistsView(
                            key: _playlistsViewKey,
                            onOpenNowPlaying: () => _selectTab(_tabNowPlaying),
                            onMoveLocalSongFolder:
                                _showMoveLocalSongFolderSheet,
                            onOpenAllSongsSearch: _openAllSongsSearch,
                            openAllSongsSearchRequestId:
                                _allSongsSearchRequestId,
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
          color: context.palette.nowPlayingPrimary.withValues(alpha: 0.28),
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
                  color: context.palette.surfaceSubtle,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.verified_user_outlined,
                  color: context.palette.nowPlayingPrimary,
                  size: 15,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.permissionBannerTitle,
                      style: TextStyle(
                        color: context.palette.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.permissionBannerBody,
                      style: TextStyle(
                        color: context.palette.textMuted,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              MographSpringTap(
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 26, minHeight: 26),
                  tooltip: AppStrings.hideLabel,
                  onPressed: localProvider.dismissPermissionBanner,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: context.palette.textMuted,
                  ),
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
                MographSpringTap(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.palette.nowPlayingOnPrimary,
                      backgroundColor: context.palette.nowPlayingPrimary,
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      side: BorderSide(
                        color: context.palette.nowPlayingPrimary,
                        width: 0.8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () =>
                        localProvider.requestAllFilesAccessPermission(),
                    icon: const Icon(Icons.folder_special_rounded, size: 14),
                    label: Text(
                      AppStrings.enableAllFilesAccessLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (missingNotif)
                MographSpringTap(
                  child: OutlinedButton.icon(
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
                    onPressed: () => localProvider
                        .requestNotificationAndLiveIslandPermission(),
                    icon: Icon(
                      Icons.notifications_active_outlined,
                      size: 14,
                      color: context.palette.nowPlayingPrimary,
                    ),
                    label: Text(
                      AppStrings.enableNotifLiveIslandLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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
      backgroundColor: context.palette.nowPlayingBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
                decoration: BoxDecoration(
                  color: context.palette.nowPlayingBg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
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
                          color: context.palette.nowPlayingPrimary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            AppStrings.downloadQueueTitle,
                            style: TextStyle(
                              color: context.palette.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        MographSpringTap(
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: AppStrings.closeLabel,
                            onPressed: () => Navigator.of(sheetCtx).pop(),
                            icon: Icon(
                              Icons.close_rounded,
                              size: 19,
                              color: context.palette.textMuted,
                            ),
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
    final hasHistory = provider.queueItems.isNotEmpty;
    final isActive = totalActiveCount > 0 || provider.isDownloading;
    final onPrimary = context.palette.nowPlayingOnPrimary;
    final primaryBg = context.palette.nowPlayingPrimary;

    return PressableScale(
      onTap: _openDownloadQueueHistorySheet,
      pressedScale: 0.90,
      child: Tooltip(
        message: AppStrings.downloadQueueTitle,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: primaryBg,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (isActive)
                SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(
                    value: provider.progress > 0.02 && provider.progress < 0.99
                        ? provider.progress.clamp(0.0, 1.0)
                        : null,
                    strokeWidth: 2.2,
                    color: MusEveePalette.emerald,
                    backgroundColor: onPrimary.withValues(alpha: 0.24),
                  ),
                ),
              Image.asset(
                'assets/download.png',
                width: 19,
                height: 19,
                color: onPrimary,
              ),
              if (totalActiveCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.5,
                      vertical: 1.5,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    decoration: BoxDecoration(
                      color: MusEveePalette.error,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: primaryBg,
                        width: 1.5,
                      ),
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
                  right: 3,
                  top: 3,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: MusEveePalette.emerald,
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
  // TAB 4: DOWNLOADER (`⬇` — Morphing Search Bar + 5 Discovery Sections)
  // ===========================================================================
  Widget _buildSearchAndDownloadTab(
    DownloaderProvider provider,
    LocalMusicProvider localProvider,
    int totalActiveCount,
  ) {
    final results = provider.searchResults;
    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      color: context.palette.nowPlayingBg,
      child: Column(
        children: [
          _buildSearchTopBar(provider, totalActiveCount, topInset),
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
                            color: context.palette.nowPlayingPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          AppStrings.searchingCatalogStatus,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: context.palette.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : results.isNotEmpty
                    ? _buildSearchResultsView(provider)
                    : _buildDownloaderDiscoveryView(provider, localProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTopBar(
    DownloaderProvider provider,
    int totalActiveCount,
    double topInset,
  ) {
    final palette = context.palette;

    return Container(
      padding: EdgeInsets.fromLTRB(14, 10 + topInset, 14, 12),
      decoration: BoxDecoration(
        color: palette.nowPlayingBg,
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _searchBarAnimation,
              builder: (context, child) {
                final anim = _searchBarAnimation.value;
                return SizedBox(
                  height: 42,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Collapsed State: [Search Glass Icon Button] + [3 Pills: Title/Artist, Link Yotube, Link Spotify]
                      if (anim < 1.0)
                        Opacity(
                          opacity: (1.0 - anim).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(-20.0 * anim, 0),
                            child: Row(
                              children: [
                                // Magnifying Glass Button
                                PressableScale(
                                  onTap: () => _expandSearch(
                                    hint: AppStrings.searchGenericHint,
                                  ),
                                  pressedScale: 0.90,
                                  child: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: palette.surfaceSubtle,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Image.asset(
                                      'assets/search.png',
                                      width: 16,
                                      height: 16,
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),

                                // 3 Pill Buttons fitted onto one row without clipping
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildSearchPill(
                                          label:
                                              AppStrings.searchTitleArtistPill,
                                          onTap: () => _expandSearch(
                                            hint: AppStrings
                                                .searchTitleArtistHint,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        _buildSearchPill(
                                          label: AppStrings.linkYoutubePill,
                                          onTap: () => _expandSearch(
                                            hint: AppStrings.searchYoutubeHint,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        _buildSearchPill(
                                          label: AppStrings.linkSpotifyPill,
                                          onTap: () => _expandSearch(
                                            hint: AppStrings.searchSpotifyHint,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Expanded State: Morphing Search Bar
                      if (anim > 0.0)
                        Opacity(
                          opacity: anim.clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(20.0 * (1.0 - anim), 0),
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: palette.surfaceSubtle,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 12, right: 8),
                                    child: Image.asset(
                                      'assets/search.png',
                                      width: 17,
                                      height: 17,
                                      color: palette.textMuted,
                                    ),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: _inputController,
                                      focusNode: _searchFocusNode,
                                      textInputAction: TextInputAction.search,
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontSize: 13,
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w500,
                                      ),
                                      onChanged: (_) {
                                        provider.clearTransientErrorOnTyping();
                                        setState(() {});
                                      },
                                      onSubmitted: (_) =>
                                          _submitOmnibox(provider),
                                      decoration: InputDecoration(
                                        hintText: _searchHint,
                                        hintStyle: TextStyle(
                                          color: palette.textMuted,
                                          fontSize: 12,
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w400,
                                        ),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_inputController.text.isNotEmpty)
                                    PressableScale(
                                      onTap: () {
                                        _inputController.clear();
                                        provider.clearTransientErrorOnTyping();
                                        if (provider.searchResults.isNotEmpty) {
                                          provider.reset();
                                        }
                                        setState(() {});
                                      },
                                      pressedScale: 0.85,
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 17,
                                          color: palette.textMuted,
                                        ),
                                      ),
                                    )
                                  else
                                    PressableScale(
                                      onTap: _collapseSearch,
                                      pressedScale: 0.85,
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Icon(
                                          Icons.arrow_back_rounded,
                                          size: 17,
                                          color: palette.textMuted,
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
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          _buildDownloadQueueButton(provider, totalActiveCount),
        ],
      ),
    );
  }

  Widget _buildSearchPill({
    required String label,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.94,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: context.palette.surfaceSubtle,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11.0,
            fontWeight: FontWeight.w500,
            color: context.palette.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultsView(DownloaderProvider provider) {
    final results = provider.searchResults;
    final palette = context.palette;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.searchResultsHeader(results.length),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              PressableScale(
                onTap: () {
                  _inputController.clear();
                  provider.reset();
                  _collapseSearch();
                },
                pressedScale: 0.88,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    AppStrings.previewClose,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.nowPlayingPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
            itemCount: results.length,
            separatorBuilder: (context, index) => const SizedBox(height: 7),
            itemBuilder: (context, index) {
              final track = results[index];
              return SearchResultTile(
                track: track,
                duplicateFolder: provider.duplicateFolderFor(track),
                onTap: () => _onTapSearchResult(provider, track),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDownloaderDiscoveryView(
    DownloaderProvider provider,
    LocalMusicProvider localProvider,
  ) {
    final hairline = context.palette.hairline;
    final isOffline = provider.isDiscoveryOffline ||
        (provider.state == DownloaderState.error && provider.isOfflineError);

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 24),
      children: [
        if (isOffline) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _buildOfflineStateCard(provider, hairline),
          ),
          const SizedBox(height: 14),
        ],

        // 1. THIS WEEK'S TOP SONGS (Horizontal scroll of 3-row columns with rank numbers)
        _buildThisWeeksTopSongsSection(provider),
        const SizedBox(height: 20),

        // 2. FOR YOU (Horizontal carousel of vertical cards)
        _buildForYouSection(provider),
        const SizedBox(height: 20),

        // 3. PLAYLISTS FOR YOU (2-row horizontal scroll of playlist cards with 2x2 collage + ⋮ menu)
        _buildPlaylistsForYouSection(provider),
        const SizedBox(height: 20),

        // 4. NEW RELEASES (Horizontal carousel of vertical cards)
        _buildNewReleasesSection(provider),
        const SizedBox(height: 20),

        // 5. TOP INDONESIAN SONGS (Horizontal carousel of vertical cards)
        _buildTopIndonesianSongsSection(provider),
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
                    fontWeight: FontWeight.w600,
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
                MographSpringTap(
                  enabled: !provider.isBusy,
                  child: OutlinedButton.icon(
                    key: const ValueKey('downloader_offline_retry_button'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.palette.nowPlayingOnPrimary,
                      backgroundColor: context.palette.nowPlayingPrimary,
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      side: BorderSide(
                        color: context.palette.nowPlayingPrimary,
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
                        fontWeight: FontWeight.w600,
                      ),
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

  Widget _buildDiscoverySectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: context.palette.textPrimary,
        ),
      ),
    );
  }

  // ===========================================================================
  // 1. THIS WEEK'S TOP SONGS (3-Item Column Horizontal Scrolling Grid)
  // ===========================================================================
  Widget _buildThisWeeksTopSongsSection(DownloaderProvider provider) {
    final palette = context.palette;
    final tracks = provider.globalTrendingTracks.isNotEmpty
        ? provider.globalTrendingTracks
        : _fallbackGlobalTrendingTracks;

    final columns = <List<MapEntry<int, TrackMetadata>>>[];
    for (int i = 0; i < tracks.length; i += 3) {
      final col = <MapEntry<int, TrackMetadata>>[];
      for (int j = 0; j < 3 && (i + j) < tracks.length; j++) {
        col.add(MapEntry(i + j + 1, tracks[i + j]));
      }
      columns.add(col);
    }

    return Column(
      key: const ValueKey('carousel_global_trending'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDiscoverySectionHeader(AppStrings.thisWeeksTopSongsTitle),
        const SizedBox(height: 10),
        SizedBox(
          height: 174,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: columns.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, colIndex) {
              final colEntries = columns[colIndex];
              return Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: colEntries.map((entry) {
                  final rank = entry.key;
                  final track = entry.value;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text(
                          '$rank.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildRankedSongCard(track, provider),
                    ],
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRankedSongCard(
    TrackMetadata track,
    DownloaderProvider provider,
  ) {
    final palette = context.palette;
    final duplicateFolder = provider.duplicateFolderFor(track);

    return PressableScale(
      enabled: !provider.isBusy,
      onTap: () => _onTapSearchResult(provider, track),
      pressedScale: 0.95,
      child: Container(
        width: 165,
        height: 52,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: palette.surfaceSubtle,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (track.coverUrl.isNotEmpty)
                      Image.network(
                        track.coverUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 140,
                        cacheHeight: 140,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildCoverFallbackIcon(),
                      )
                    else
                      _buildCoverFallbackIcon(),
                    if (duplicateFolder != null)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            size: 9,
                            color: MusEveePalette.emerald,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w400,
                      color: palette.textMuted,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 2. FOR YOU (Vertical Album Art Horizontal Carousel)
  // ===========================================================================
  Widget _buildForYouSection(DownloaderProvider provider) {
    final palette = context.palette;
    final tracks = provider.forYouTracks.isNotEmpty
        ? provider.forYouTracks
        : _fallbackForYouTracks;

    return Column(
      key: const ValueKey('carousel_for_you'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Text(
                AppStrings.forYouTitle,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.forYouSubtitle(provider.forYouSeedArtists),
                style: const TextStyle(fontSize: 0, height: 0),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: tracks.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final track = tracks[index];
              return _buildVerticalDiscoveryCard(track, provider);
            },
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 3. PLAYLISTS FOR YOU (2-Row Horizontal Scrolling Cards with 2x2 Collage)
  // ===========================================================================
  Widget _buildPlaylistsForYouSection(DownloaderProvider provider) {
    final playlists = provider.curatedPlaylists;

    final columns = <List<CuratedPlaylist>>[];
    for (int i = 0; i < playlists.length; i += 2) {
      final col = <CuratedPlaylist>[];
      for (int j = 0; j < 2 && (i + j) < playlists.length; j++) {
        col.add(playlists[i + j]);
      }
      columns.add(col);
    }

    return Column(
      key: const ValueKey('carousel_playlists_for_you'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDiscoverySectionHeader(AppStrings.playlistsForYouTitle),
        const SizedBox(height: 10),
        SizedBox(
          height: 138,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: columns.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, colIndex) {
              final colPlaylists = columns[colIndex];
              return Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: colPlaylists.map((pl) {
                  return _buildCuratedPlaylistCard(pl, provider);
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCuratedPlaylistCard(
    CuratedPlaylist playlist,
    DownloaderProvider provider,
  ) {
    final palette = context.palette;

    return PressableScale(
      enabled: !provider.isBusy,
      onTap: () => _openCuratedPlaylist(provider, playlist),
      pressedScale: 0.95,
      child: Container(
        width: 212,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: palette.surfaceSubtle,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            _buildPlaylistCollageCover(playlist),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppStrings.songCountLower(playlist.songCount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: palette.textMuted,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            PressableScale(
              onTap: () => _showCuratedPlaylistMenu(provider, playlist),
              pressedScale: 0.85,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: palette.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistCollageCover(CuratedPlaylist playlist) {
    final covers = playlist.sampleCovers;
    if (covers.length >= 4) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 46,
          height: 46,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildSmallNetworkCover(covers[0])),
                    Expanded(child: _buildSmallNetworkCover(covers[1])),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildSmallNetworkCover(covers[2])),
                    Expanded(child: _buildSmallNetworkCover(covers[3])),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 46,
        height: 46,
        color: context.palette.surfaceCard,
        child: covers.isNotEmpty
            ? _buildSmallNetworkCover(covers.first)
            : Image.asset(
                'assets/album.png',
                fit: BoxFit.cover,
                color: context.palette.textMuted,
              ),
      ),
    );
  }

  Widget _buildSmallNetworkCover(String url) {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      return Container(
        color: context.palette.surfaceCard,
        alignment: Alignment.center,
        child: Icon(
          Icons.music_note_rounded,
          size: 11,
          color: context.palette.textMuted,
        ),
      );
    }
    return Image.network(
      cleanUrl,
      fit: BoxFit.cover,
      cacheWidth: 120,
      cacheHeight: 120,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => Container(
        color: context.palette.surfaceCard,
        alignment: Alignment.center,
        child: Icon(
          Icons.music_note_rounded,
          size: 11,
          color: context.palette.textMuted,
        ),
      ),
    );
  }

  Future<void> _openCuratedPlaylist(
    DownloaderProvider provider,
    CuratedPlaylist playlist,
  ) async {
    final future = provider.loadCuratedPlaylist(playlist);
    if (!mounted) return;
    final initialCover = (playlist.coverUrl?.trim().isNotEmpty == true)
        ? playlist.coverUrl!.trim()
        : (playlist.sampleCovers.isNotEmpty
            ? playlist.sampleCovers.first
            : null);
    await BatchPlaylistSheet.show(
      context,
      initialTitle: playlist.title,
      initialCoverUrl: initialCover,
      onRetry: () => provider.loadCuratedPlaylist(playlist),
      onCreateNewFolder: _showCreateFolderDialog,
    );
    await future;
  }

  void _showCuratedPlaylistMenu(
    DownloaderProvider provider,
    CuratedPlaylist playlist,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.nowPlayingBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    Icons.download_rounded,
                    color: context.palette.nowPlayingPrimary,
                  ),
                  title: Text(
                    AppStrings.openAndDownloadPlaylist(playlist.songCount),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openCuratedPlaylist(provider, playlist);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.copy_rounded,
                    color: context.palette.textMuted,
                  ),
                  title: Text(
                    AppStrings.copyPlaylistLinkLabel,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Clipboard.setData(ClipboardData(text: playlist.spotifyUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppStrings.playlistLinkCopied(playlist.title),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 4. NEW RELEASES (Vertical Album Art Horizontal Carousel)
  // ===========================================================================
  Widget _buildNewReleasesSection(DownloaderProvider provider) {
    final tracks = provider.newReleasesTracks.isNotEmpty
        ? provider.newReleasesTracks
        : _fallbackNewReleasesTracks;

    return Column(
      key: const ValueKey('carousel_new_releases'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDiscoverySectionHeader(AppStrings.newReleasesTitle),
        const SizedBox(height: 10),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: tracks.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final track = tracks[index];
              return _buildVerticalDiscoveryCard(track, provider);
            },
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 5. TOP INDONESIAN SONGS (Vertical Album Art Horizontal Carousel)
  // ===========================================================================
  Widget _buildTopIndonesianSongsSection(DownloaderProvider provider) {
    final tracks = provider.indonesiaTrendingTracks.isNotEmpty
        ? provider.indonesiaTrendingTracks
        : _fallbackIndonesiaTrendingTracks;

    return Column(
      key: const ValueKey('carousel_indonesia_trending'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDiscoverySectionHeader(AppStrings.topIndonesianSongsTitle),
        const SizedBox(height: 10),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: tracks.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final track = tracks[index];
              return _buildVerticalDiscoveryCard(track, provider);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalDiscoveryCard(
    TrackMetadata track,
    DownloaderProvider provider,
  ) {
    final palette = context.palette;
    final duplicateFolder = provider.duplicateFolderFor(track);

    return PressableScale(
      enabled: !provider.isBusy,
      onTap: () => _onTapSearchResult(provider, track),
      pressedScale: 0.95,
      child: Container(
        width: 108,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: palette.surfaceSubtle,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (track.coverUrl.isNotEmpty)
                      Image.network(
                        track.coverUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 140,
                        cacheHeight: 140,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildCoverFallbackIcon(),
                      )
                    else
                      _buildCoverFallbackIcon(),
                    if (duplicateFolder != null)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            size: 10,
                            color: MusEveePalette.emerald,
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
                fontFamily: 'Poppins',
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: palette.textMuted,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverFallbackIcon() {
    return Container(
      color: context.palette.surfaceCard,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        color: context.palette.textMuted,
        size: 24,
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
                  valueColor: AlwaysStoppedAnimation<Color>(
                    context.palette.nowPlayingPrimary,
                  ),
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
                          color: context.palette.nowPlayingPrimary,
                        ),
                      )
                    else
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isError
                              ? MusEveePalette.error
                              : context.palette.nowPlayingPrimary,
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
                          color: isError
                              ? MusEveePalette.error
                              : context.palette.textPrimary,
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
                          color: context.palette.nowPlayingPrimary,
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

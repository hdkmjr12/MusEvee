import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/widgets.dart';

/// Propagates live Android system locale changes across the entire widget tree
/// (including `const` child widgets inside `IndexedStack`) when
/// `WidgetsBindingObserver.didChangeLocales` triggers a rebuild.
class SystemLocaleScope extends InheritedWidget {
  final String languageCode;

  const SystemLocaleScope({
    super.key,
    required this.languageCode,
    required super.child,
  });

  static void watch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<SystemLocaleScope>();
  }

  @override
  bool updateShouldNotify(SystemLocaleScope oldWidget) =>
      languageCode != oldWidget.languageCode;
}

/// Lightweight zero-config localization helper that automatically follows the
/// device's system language:
/// - Indonesian (`id` / `in`) -> Bahasa Indonesia
/// - All other system languages -> English (`en`)
class AppStrings {
  /// Optional override for unit/widget testing (`'id'` or `'en'`).
  @visibleForTesting
  static String? debugLanguageCodeOverride;

  /// Returns `true` when the active system locale is Indonesian (`id` or `in`).
  static bool get isIndonesian => isIndonesianInContext();

  static bool isIndonesianInContext([BuildContext? context]) {
    if (context != null) {
      try {
        SystemLocaleScope.watch(context);
      } catch (_) {}
    }
    final override = debugLanguageCodeOverride?.trim().toLowerCase();
    if (override != null && override.isNotEmpty) {
      return override == 'id' || override == 'in';
    }
    if (context != null) {
      try {
        final locale = Localizations.maybeLocaleOf(context);
        if (locale != null && locale.languageCode.trim().isNotEmpty) {
          final code = locale.languageCode.trim().toLowerCase();
          if (code == 'id' || code == 'in') {
            return true;
          }
        }
      } catch (_) {}
      try {
        final scope =
            context.dependOnInheritedWidgetOfExactType<SystemLocaleScope>();
        if (scope != null && scope.languageCode.trim().isNotEmpty) {
          final code = scope.languageCode.trim().toLowerCase();
          return code == 'id' || code == 'in';
        }
      } catch (_) {}
    }
    try {
      final sysCode = WidgetsBinding
          .instance.platformDispatcher.locale.languageCode
          .trim()
          .toLowerCase();
      return sysCode == 'id' || sysCode == 'in';
    } catch (_) {
      try {
        final fallbackCode = PlatformDispatcher.instance.locale.languageCode
            .trim()
            .toLowerCase();
        return fallbackCode == 'id' || fallbackCode == 'in';
      } catch (_) {
        return true;
      }
    }
  }

  /// Picks [id] when the system language is Indonesian, otherwise [en].
  static String tr(
    String id,
    String en, [
    BuildContext? context,
  ]) =>
      isIndonesianInContext(context) ? id : en;

  // ===========================================================================
  // BOTTOM NAVIGATION STRIP TOOLTIPS
  // ===========================================================================
  static String get tabQueueTooltip =>
      isIndonesian ? 'Antrean Putar (Queue)' : 'Playback Queue';
  static String get tabNowPlayingTooltip =>
      isIndonesian ? 'Sedang Diputar (Now Playing)' : 'Now Playing';
  static String get tabFoldersTooltip =>
      isIndonesian ? 'Folder Musik' : 'Music Folders';
  static String get tabPlaylistsTooltip => 'Playlists';
  static String get tabDownloaderTooltip =>
      isIndonesian ? 'Cari & Unduh Lagu (Downloader)' : 'Search & Download';
  static String get tabSearchLocalTooltip =>
      isIndonesian ? 'Cari Lagu Lokal' : 'Search Local Songs';
  static String get tabSettingsTooltip =>
      isIndonesian ? 'Pengaturan' : 'Settings';

  // ===========================================================================
  // LOCAL SEARCH (INSIDE ALL SONGS) & SHORTCUTS
  // ===========================================================================
  static String get localSearchShortcutTooltip =>
      isIndonesian ? 'Cari Lagu Lokal' : 'Search Local Songs';
  static String get localSearchHint => isIndonesian
      ? 'Cari lagu, artis, album, atau folder di HP...'
      : 'Search songs, artists, albums, or folders on device...';
  static String get filterFavoritesTooltip =>
      isIndonesian ? 'Filter Favorit' : 'Filter Favorites';
  static String get localSearchEmptyLibrary => isIndonesian
      ? 'Belum ada lagu lokal yang tersimpan di perangkat.'
      : 'No local songs saved on this device yet.';
  static String get localSearchNoMatch => isIndonesian
      ? 'Tidak ada lagu lokal yang cocok dengan pencarian.'
      : 'No local songs match your search.';

  // ===========================================================================
  // SETTINGS TAB (`SettingsView`)
  // ===========================================================================
  static String get settingsHeaderTitle =>
      isIndonesian ? 'Pengaturan' : 'Settings';
  static String get settingsAppearanceSection =>
      isIndonesian ? 'Tampilan' : 'Appearance';
  static String get settingsThemeTitle =>
      isIndonesian ? 'Tema Aplikasi' : 'App Theme';
  static String get themeAutoTitle => 'Auto';
  static String get themeAutoSubtitle => isIndonesian
      ? 'Mengikuti tema sistem perangkat'
      : 'Follows your device system theme';
  static String themeAutoResolvedSubtitle({required bool isDark}) =>
      isIndonesian
          ? 'Mengikuti tema sistem (${isDark ? 'Gelap' : 'Terang'})'
          : 'Follows device theme (${isDark ? 'Dark' : 'Light'})';
  static String get themeDarkTitle => isIndonesian ? 'Gelap' : 'Dark';
  static String get themeDarkSubtitle => isIndonesian
      ? 'Permukaan gelap khas MusEvee'
      : 'Signature MusEvee dark surface';
  static String get themeLightTitle => isIndonesian ? 'Terang' : 'Light';
  static String get themeLightSubtitle => isIndonesian
      ? 'Permukaan terang bersih berkonsep kontras tinggi'
      : 'Clean high-contrast light surface';

  static String get settingsDownloadsSection =>
      isIndonesian ? 'Unduhan' : 'Downloads';
  static String get settingsDownloadQualityTitle =>
      isIndonesian ? 'Kualitas Audio Unduhan' : 'Download Audio Quality';
  static String get qualityHiResTitle => 'Hi-Res Lossless — FLAC';
  static String get qualityHiResSubtitle => isIndonesian
      ? '16/24-bit · ~25–50 MB per lagu · Otomatis fallback ke 320 kbps jika tidak tersedia'
      : '16/24-bit · ~25–50 MB per song · Auto fallback to 320 kbps if unavailable';
  static String get qualityBestTitle =>
      isIndonesian ? 'Terbaik — 320 kbps' : 'Best — 320 kbps';
  static String get qualityBestSubtitle => isIndonesian
      ? 'MP3 · ~9-10 MB per lagu 4 menit'
      : 'MP3 · ~9-10 MB per 4-min song';
  static String get qualityBalancedTitle =>
      isIndonesian ? 'Seimbang — 192 kbps' : 'Balanced — 192 kbps';
  static String get qualityBalancedSubtitle => isIndonesian
      ? 'MP3 · ~5-6 MB per lagu 4 menit'
      : 'MP3 · ~5-6 MB per 4-min song';
  static String get qualityEfficientTitle =>
      isIndonesian ? 'Hemat — 128 kbps' : 'Efficient — 128 kbps';
  static String get qualityEfficientSubtitle => isIndonesian
      ? 'MP3 · ~3-4 MB per lagu 4 menit'
      : 'MP3 · ~3-4 MB per 4-min song';
  static String get settingsDownloadQualityNote => isIndonesian
      ? 'Pengaturan ini hanya memengaruhi ukuran file hasil unduhan, bukan penggunaan data saat mengunduh.'
      : 'This setting only affects the downloaded output file size, not data usage during download.';
  static String hiResAddonCardTitle(int activeCount) => isIndonesian
      ? 'Sumber Add-on Hi-Res ($activeCount Aktif)'
      : 'Hi-Res Add-on Sources ($activeCount Active)';
  static String get hiResAddonCardSubtitle => isIndonesian
      ? 'Prioritas modul lossless FLAC & urutan pencocokan'
      : 'Lossless FLAC module priority & waterfall order';
  static String get hiResAddonManageButton =>
      isIndonesian ? 'Kelola' : 'Manage';
  static String get hiResAddonModalTitle => isIndonesian
      ? 'Kelola Sumber Add-on Hi-Res'
      : 'Manage Hi-Res Add-on Sources';
  static String get hiResAddonModalSubtitle => isIndonesian
      ? 'Dicoba berurutan dari atas ke bawah'
      : 'Tried sequentially from top to bottom';
  static String get hiResAddonRefreshStatus =>
      isIndonesian ? 'Cek Status' : 'Check Status';
  static String get hiResAddonResetPresets =>
      isIndonesian ? 'Reset Preset' : 'Reset Presets';
  static String get hiResAddonAddUrlButton =>
      isIndonesian ? '+ Tambah URL Add-on' : '+ Add Add-on URL';
  static String get hiResAddonAddDialogTitle =>
      isIndonesian ? 'Tambah URL Add-on Hi-Res' : 'Add Hi-Res Add-on URL';
  static String get hiResAddonAddDialogHint =>
      'https://tracks.monochrome.st / https://.../index.json';
  static String get hiResAddonCancelButton => isIndonesian ? 'Batal' : 'Cancel';
  static String get hiResAddonSaveButton => isIndonesian ? 'Tambah' : 'Add';
  static String get hiResAddonDownloadsAllowed =>
      isIndonesian ? 'Unduhan diizinkan' : 'Downloads allowed';
  static String get hiResAddonStreamingOnly =>
      isIndonesian ? 'Hanya streaming' : 'Streaming only';
  static String get appVersionFooter => 'MusEvee v4.9';

  // ===========================================================================
  // SMART PLAYLISTS & PLAYLISTS TAB
  // ===========================================================================
  static String smartPlaylistTitle(String smartId, [BuildContext? context]) {
    final id = isIndonesianInContext(context);
    switch (smartId) {
      case 'smart_all_songs':
        return id ? 'Semua lagu' : 'All songs';
      case 'smart_favorites':
        return id ? 'Favorit' : 'Favorites';
      case 'smart_recently_added':
        return id ? 'Baru ditambahkan' : 'Recently added';
      case 'smart_recently_played':
        return id ? 'Baru diputar' : 'Recently played';
      case 'smart_most_played':
        return id ? 'Paling sering diputar' : 'Most played';
      case 'smart_not_played':
        return id ? 'Belum pernah diputar' : 'Not played';
      default:
        return smartId;
    }
  }

  static String smartPlaylistEmptyHint(
    String smartId, [
    BuildContext? context,
  ]) {
    final id = isIndonesianInContext(context);
    switch (smartId) {
      case 'smart_favorites':
        return id
            ? 'Belum ada lagu favorit. Ketuk ikon hati (♥) di layar Now Playing untuk menandai lagu.'
            : 'No favorite songs yet. Tap the heart icon (♥) in Now Playing to mark a track.';
      case 'smart_recently_played':
      case 'smart_most_played':
        return id
            ? 'Belum ada riwayat pemutaran lagu.'
            : 'No playback history yet.';
      case 'smart_not_played':
        return id
            ? 'Semua lagu di perpustakaan sudah pernah diputar!'
            : 'All songs in your library have been played!';
      default:
        return id
            ? 'Belum ada lagu di kategori ini.'
            : 'No songs in this category yet.';
    }
  }

  static String get yourPlaylists =>
      isIndonesian ? 'Playlist kamu' : 'Your playlists';
  static String get yourPlaylistsHeader => yourPlaylists;

  static String get newPlaylist =>
      isIndonesian ? 'Playlist Baru' : 'New Playlist';
  static String get newPlaylistButton => newPlaylist;

  static String get noUserPlaylistsHint => isIndonesian
      ? 'Belum ada playlist buatanmu. Ketuk "+ Playlist Baru" untuk membuat.'
      : 'No custom playlists yet. Tap "+ New Playlist" to create one.';

  static String songsCountLabel(int count, [BuildContext? context]) =>
      isIndonesianInContext(context) ? '$count lagu' : '$count songs';

  // ===========================================================================
  // FOLDERS TAB (`LocalFoldersView`)
  // ===========================================================================
  static String foldersManageAction([BuildContext? context]) =>
      tr('Kelola', 'Manage', context);

  static String foldersSearchHint([BuildContext? context]) => tr(
        'Cari lagu, artis, album...',
        'Search songs, artist, album...',
        context,
      );

  static String folderSongsSearchHint([BuildContext? context]) => tr(
        'Cari lagu/artis di folder ini',
        'Search songs/artist in this folder',
        context,
      );

  static String playlistSongsSearchHint([BuildContext? context]) => tr(
        'Cari lagu/artis di playlist ini',
        'Search songs/artist in this playlist',
        context,
      );

  static String selectFoldersLabel([BuildContext? context]) =>
      tr('Pilih folder', 'Select folders', context);

  static String selectPlaylistsLabel([BuildContext? context]) =>
      tr('Pilih playlist', 'Select playlists', context);

  static String selectSongsLabel([BuildContext? context]) =>
      tr('Pilih lagu', 'Select songs', context);

  // ===========================================================================
  // DOWNLOADER TAB & DISCOVERY CAROUSELS
  // ===========================================================================
  static String get omniboxHint => isIndonesian
      ? 'Cari lagu atau tempel link...'
      : 'Search songs or paste link...';

  static String get searchGenericHint => isIndonesian
      ? 'Cari judul/artis atau tempel link...'
      : 'Search title/artist or paste a link...';
  static String get searchTitleArtistHint => isIndonesian
      ? 'Cari berdasarkan judul atau artis...'
      : 'Search title/artist...';
  static String get searchYoutubeHint => isIndonesian
      ? 'Tempel link YouTube atau YT Music...'
      : 'Paste YouTube or YT Music link...';
  static String get searchSpotifyHint =>
      isIndonesian ? 'Tempel link Spotify...' : 'Paste Spotify link...';

  static String get searchTitleArtistPill =>
      isIndonesian ? 'Judul/Artis' : 'Title/Artist';
  static String get linkYoutubePill =>
      isIndonesian ? 'Link YouTube/YT Music' : 'YouTube/YT Music Link';
  static String get linkSpotifyPill =>
      isIndonesian ? 'Link Spotify' : 'Spotify Link';

  static String get thisWeeksTopSongsTitle =>
      isIndonesian ? 'Lagu teratas minggu ini' : "This week's top songs";
  static String get playlistsForYouTitle =>
      isIndonesian ? 'Playlist untukmu' : 'Playlists for you';
  static String get newReleasesTitle =>
      isIndonesian ? 'Rilis baru' : 'New releases';
  static String get topIndonesianSongsTitle =>
      isIndonesian ? 'Lagu Indonesia teratas' : 'Top Indonesian songs';

  // Common / Shared Labels
  static String get closeLabel => isIndonesian ? 'Tutup' : 'Close';
  static String get retryLabel => isIndonesian ? 'Coba Lagi' : 'Retry';
  static String get retryShortLabel => isIndonesian ? 'Ulangi' : 'Retry';
  static String get clearLabel => isIndonesian ? 'Bersihkan' : 'Clear';
  static String get cancelLabel => isIndonesian ? 'Batal' : 'Cancel';
  static String get hideLabel => isIndonesian ? 'Sembunyikan' : 'Hide';
  static String get waitingLabel => isIndonesian ? 'Menunggu' : 'Waiting';
  static String get failedLabel => isIndonesian ? 'Gagal' : 'Failed';
  static String get moveLabel => isIndonesian ? 'Pindah' : 'Move';
  static String get selectShortLabel => isIndonesian ? 'Pilih' : 'Select';
  static String songCountLower(int count) =>
      isIndonesian ? '$count lagu' : '$count ${count == 1 ? 'song' : 'songs'}';
  static String songCountTitle(int count) =>
      isIndonesian ? '$count Lagu' : '$count ${count == 1 ? 'Song' : 'Songs'}';

  // TrackPreviewSheet & TagEditorSheet feedback
  static String get previewRomajiConverted => isIndonesian
      ? 'Lirik berhasil dikonversi ke Romaji.'
      : 'Lyrics converted to Romaji.';
  static String get previewMetadataRomajiConverted => isIndonesian
      ? 'Judul & artis dikonversi ke Romaji.'
      : 'Title & artist converted to Romaji.';
  static String editorSavedId3(String formatLabel) => isIndonesian
      ? 'Tag & lirik tertanam berhasil disimpan ke file $formatLabel.'
      : 'Tags & embedded lyrics saved to $formatLabel file.';
  static String get editorUpdatedHistory => isIndonesian
      ? 'Info lagu & lirik berhasil diperbarui.'
      : 'Track info & lyrics updated.';
  static String get editorSavedMetadata => isIndonesian
      ? 'Info lagu & lirik berhasil disimpan.'
      : 'Track info & lyrics saved.';
  static String editorSaveFailed(Object error) => isIndonesian
      ? 'Gagal menyimpan perubahan: $error'
      : 'Failed to save changes: $error';

  // BatchPlaylistSheet
  static String get batchLoadFailed => isIndonesian
      ? 'Gagal memuat daftar lagu playlist.'
      : 'Failed to load playlist tracks.';
  static String get batchLoadingTracks =>
      isIndonesian ? 'Memuat daftar lagu...' : 'Loading tracks...';
  static String get batchDeselectAll =>
      isIndonesian ? 'Batal Pilih' : 'Deselect All';
  static String get batchSelectAll =>
      isIndonesian ? 'Pilih Semua' : 'Select All';
  static String batchAlreadyInFolder(String folder) =>
      isIndonesian ? 'Sudah ada di $folder' : 'Already in $folder';
  static String get batchTargetFolderLabel =>
      isIndonesian ? 'Folder Tujuan:' : 'Target Folder:';
  static String get batchNewFolderChip => isIndonesian ? '+ Baru' : '+ New';
  static String batchQueuedResult({
    required int queued,
    required String targetFolder,
    required int skipped,
    required String playlistName,
  }) {
    if (isIndonesian) {
      return '$queued lagu diantrekan ($targetFolder)'
          '${skipped > 0 ? ', $skipped sudah ada di HP (tidak diunduh ulang)' : ''}'
          '${playlistName.isNotEmpty ? ' • Playlist "$playlistName" tersinkron.' : '.'}';
    }
    return '$queued ${queued == 1 ? 'song' : 'songs'} queued ($targetFolder)'
        '${skipped > 0 ? ', $skipped already on device (skipped)' : ''}'
        '${playlistName.isNotEmpty ? ' • Playlist "$playlistName" synced.' : '.'}';
  }

  static String batchSaveSelectedToFolder(int count, String folder) =>
      isIndonesian
          ? 'Simpan $count Lagu ke $folder'
          : 'Save $count ${count == 1 ? 'Song' : 'Songs'} to $folder';

  // QueueHistoryView & HomeScreen Downloader UI
  static String get downloadQueueTitle =>
      isIndonesian ? 'Antrean & Riwayat Unduhan' : 'Download Queue & History';
  static String get activeDownloadQueueSection =>
      isIndonesian ? 'Antrean Unduhan Aktif' : 'Active Download Queue';
  static String get completedDownloadHistorySection =>
      isIndonesian ? 'Riwayat Unduhan Selesai' : 'Download History';
  static String get noActiveDownloads => isIndonesian
      ? 'Tidak ada unduhan yang sedang berjalan.'
      : 'No active downloads right now.';
  static String get playInNowPlayingTooltip =>
      isIndonesian ? 'Putar di Now Playing' : 'Play in Now Playing';
  static String get editTagAgainTooltip =>
      isIndonesian ? 'Edit Tag Ulang' : 'Edit Tags Again';
  static String get noDownloadHistory => isIndonesian
      ? 'Belum ada riwayat unduhan pada sesi ini.'
      : 'No download history in this session yet.';
  static String get localFolderCollectionSummary => isIndonesian
      ? 'Ringkasan Koleksi Folder Lokal:'
      : 'Local Folder Collection Summary:';
  static String folderSongCountChip(String folder, int count) => isIndonesian
      ? '$folder: $count Lagu'
      : '$folder: $count ${count == 1 ? 'Song' : 'Songs'}';

  static String get spotifyPrivatePlaylistTitle => isIndonesian
      ? 'Playlist Spotify Tidak Dapat Diakses'
      : 'Spotify Playlist Unavailable';
  static String get spotifyPrivatePlaylistMessage => isIndonesian
      ? "Playlist Spotify ini berstatus Pribadi (Private) atau tidak dapat diakses. Silakan ubah pengaturan playlist di Spotify menjadi 'Publik' (Make Public) terlebih dahulu, lalu salin ulang link-nya."
      : "This Spotify playlist is private or unavailable. Please set the playlist to 'Public' in Spotify first, then copy the link again.";
  static String get createMusicFolderTitle =>
      isIndonesian ? 'Buat Folder Musik Baru' : 'Create New Music Folder';
  static String createMusicFolderPrompt(String dirPath) => isIndonesian
      ? 'Masukkan nama folder baru di $dirPath:'
      : 'Enter a new folder name in $dirPath:';
  static String get createMusicFolderHint => isIndonesian
      ? 'Contoh: Music Anime / Music Indo'
      : 'Example: Music Anime / Chill Vibes';
  static String get createAndSelectLabel =>
      isIndonesian ? 'Buat & Pilih' : 'Create & Select';
  static String get pickOrCreateFolderTitle => isIndonesian
      ? 'Pilih atau Buat Folder Tujuan'
      : 'Choose or Create Target Folder';
  static String get plusNewFolderLabel =>
      isIndonesian ? '+ Folder Baru' : '+ New Folder';
  static String get newFolderLabel =>
      isIndonesian ? 'Folder Baru' : 'New Folder';
  static String selectTargetFolder(String label) =>
      isIndonesian ? 'Pilih "$label"' : 'Select "$label"';
  static String get openAndroidFolderPickerLabel => isIndonesian
      ? 'Buka Pemilih Folder Sistem Android (Storage Explorer)'
      : 'Open Android System Folder Picker (Storage Explorer)';
  static String get subfolderHintText => isIndonesian
      ? 'Subfolder di dalam direktori ini (ketuk untuk masuk, atau ketuk "Pilih"):'
      : 'Subfolders in this directory (tap to open, or tap "Select"):';
  static String noSubfoldersText(String dirPath) => isIndonesian
      ? 'Belum ada subfolder di $dirPath.\nKamu bisa memilih direktori ini langsung atau ketuk "+ Folder Baru".'
      : 'No subfolders in $dirPath yet.\nYou can select this directory directly or tap "+ New Folder".';
  static String targetFolderReady(String label) => isIndonesian
      ? 'Folder tujuan "$label" siap digunakan.'
      : 'Target folder "$label" is ready to use.';
  static String get moveSongFolderTitle =>
      isIndonesian ? 'Pindah Folder Lagu' : 'Move Song Folder';
  static String movedToFolder(String targetFolder) => isIndonesian
      ? 'Berhasil dipindahkan ke $targetFolder.'
      : 'Moved to $targetFolder.';
  static String moveSongFailed(Object error) => isIndonesian
      ? 'Gagal memindahkan lagu: $error'
      : 'Failed to move song: $error';
  static String get moveLocalSongFolderTitle =>
      isIndonesian ? 'Pindah Folder Lagu Lokal' : 'Move Local Song Folder';
  static String localSongMovedToFolder(String targetFolder) => isIndonesian
      ? 'Lagu berhasil dipindahkan ke folder $targetFolder.'
      : 'Song moved to folder $targetFolder.';
  static String moveLocalSongFailed(Object error) => isIndonesian
      ? 'Gagal memindahkan lagu lokal: $error'
      : 'Failed to move local song: $error';
  static String folderCurrentSuffix(String folder) =>
      isIndonesian ? '$folder (Saat Ini)' : '$folder (Current)';
  static String get permissionBannerTitle => isIndonesian
      ? 'Setup Izin Cepat MusEvee'
      : 'MusEvee Quick Permission Setup';
  static String get permissionBannerBody => isIndonesian
      ? 'Aktifkan akses penuh agar fitur hapus lagu, pindah folder, edit tag/lirik berjalan 1 klik, serta notifikasi & Live Island tampil otomatis.'
      : 'Grant full access so deleting songs, moving folders, and editing tags/lyrics work in one tap, and notifications & Live Island appear automatically.';
  static String get enableAllFilesAccessLabel =>
      isIndonesian ? 'Aktifkan Akses File Penuh' : 'Enable All Files Access';
  static String get enableNotifLiveIslandLabel => isIndonesian
      ? 'Aktifkan Notifikasi & Live Island'
      : 'Enable Notifications & Live Island';
  static String searchResultsHeader(int count) => isIndonesian
      ? 'Hasil pencarian ($count lagu)'
      : 'Search results ($count ${count == 1 ? 'song' : 'songs'})';
  static String openAndDownloadPlaylist(int count) => isIndonesian
      ? 'Buka & Unduh Playlist ($count lagu)'
      : 'Open & Download Playlist ($count ${count == 1 ? 'song' : 'songs'})';
  static String get copyPlaylistLinkLabel =>
      isIndonesian ? 'Salin Link Playlist' : 'Copy Playlist Link';
  static String playlistLinkCopied(String title) => isIndonesian
      ? 'Link playlist "$title" disalin ke clipboard.'
      : 'Playlist "$title" link copied to clipboard.';
  static String get understoodLabel => isIndonesian ? 'Mengerti' : 'Got it';

  // DownloaderProvider & Service progress / status / errors
  static String get dpReadyToSearch =>
      isIndonesian ? 'Siap mencari lagu.' : 'Ready to search songs.';
  static String dpCuratedSubtitle(int count) => isIndonesian
      ? '$count lagu kurasi MusEvee'
      : '$count curated songs by MusEvee';
  static String dpTracksFoundInPlaylist(int count, String title) => isIndonesian
      ? '$count lagu ditemukan di "$title".'
      : '$count ${count == 1 ? 'song' : 'songs'} found in "$title".';
  static String dpOpeningPlaylist(String title) => isIndonesian
      ? 'Membuka playlist $title...'
      : 'Opening playlist $title...';
  static String dpTracksLoadedForPlaylist(int count, String title) =>
      isIndonesian
          ? '$count lagu dimuat untuk "$title".'
          : '$count ${count == 1 ? 'song' : 'songs'} loaded for "$title".';
  static String dpPlaylistLoadFailed(String title) => isIndonesian
      ? 'Gagal memuat playlist "$title".'
      : 'Failed to load playlist "$title".';
  static String get dpLoadingInfo =>
      isIndonesian ? 'Memuat info...' : 'Loading info...';
  static String get dpLoadingYoutubeInfo =>
      isIndonesian ? 'Memuat info YouTube...' : 'Loading YouTube info...';
  static String dpSongsFoundCount(int count) => isIndonesian
      ? '$count lagu ditemukan'
      : '$count ${count == 1 ? 'song' : 'songs'} found';
  static String dpSongsLoadedCount(int count) => isIndonesian
      ? '$count lagu dimuat'
      : '$count ${count == 1 ? 'song' : 'songs'} loaded';
  static String get dpFetchingLyrics =>
      isIndonesian ? 'Mengambil lirik...' : 'Fetching lyrics...';
  static String dpReadyToSaveToFolder(String folder) =>
      isIndonesian ? 'Siap disimpan ke $folder' : 'Ready to save to $folder';
  static String get dpAlreadyOnDeviceLinked => isIndonesian
      ? 'Sudah ada di HP • ditautkan ke playlist'
      : 'Already on device • linked to playlist';
  static String get dpAlreadyOnDeviceSkipped => isIndonesian
      ? 'Sudah ada di HP • dilewati'
      : 'Already on device • skipped';
  static String get dpInQueue => isIndonesian ? 'Dalam antrean' : 'In queue';
  static String get dpSearchingHiRes => isIndonesian
      ? 'Mencari sumber Hi-Res FLAC...'
      : 'Searching Hi-Res FLAC source...';
  static String get dpDownloadingSong =>
      isIndonesian ? 'Mengunduh lagu...' : 'Downloading song...';
  static String get dpSavingHiRes =>
      isIndonesian ? 'Menyimpan Hi-Res FLAC...' : 'Saving Hi-Res FLAC...';
  static String dpDoneHiRes(String addonName) => isIndonesian
      ? 'Selesai • Hi-Res FLAC ($addonName)'
      : 'Done • Hi-Res FLAC ($addonName)';
  static String get dpHiResFallbackToMp3 => isIndonesian
      ? 'Hi-Res tidak tersedia, fallback ke MP3 320 kbps...'
      : 'Hi-Res unavailable, falling back to MP3 320 kbps...';
  static String get dpDownloadingFallbackMp3 => isIndonesian
      ? 'Mengunduh fallback MP3 320 kbps...'
      : 'Downloading fallback MP3 320 kbps...';
  static String get dpSavingFallbackMp3 => isIndonesian
      ? 'Menyimpan fallback MP3 320 kbps...'
      : 'Saving fallback MP3 320 kbps...';
  static String get dpDoneFallbackMp3 => isIndonesian
      ? 'Selesai (Fallback MP3 320 kbps)'
      : 'Done (Fallback MP3 320 kbps)';
  static String get dpSaving => isIndonesian ? 'Menyimpan...' : 'Saving...';
  static String get dpDone => isIndonesian ? 'Selesai' : 'Done';
  static String get dpHistoryItemNotFound => isIndonesian
      ? 'Item riwayat unduhan tidak ditemukan.'
      : 'Download history item not found.';
  static String get dpLocalMp3PathUnavailable => isIndonesian
      ? 'Path file audio lokal tidak tersedia.'
      : 'Local audio file path unavailable.';
  static String get dpDownloadItemNotFound => isIndonesian
      ? 'Item unduhan tidak ditemukan.'
      : 'Download item not found.';
  static String get dpFileUnavailable =>
      isIndonesian ? 'File tidak tersedia.' : 'File unavailable.';
  static String get dpUnknownError => isIndonesian
      ? 'Terjadi kesalahan yang tidak diketahui.'
      : 'An unknown error occurred.';

  // Services progress & error strings
  static String get svcNoInternet => isIndonesian
      ? 'Tidak ada koneksi internet. Periksa jaringan Anda lalu coba lagi.'
      : 'No internet connection. Check your network and try again.';
  static String svcDeezerLoadFailed(Object e) => isIndonesian
      ? 'Gagal memuat playlist Deezer: $e'
      : 'Failed to load Deezer playlist: $e';
  static String get svcFolderNameEmpty => isIndonesian
      ? 'Nama folder tidak boleh kosong.'
      : 'Folder name cannot be empty.';
  static String svcSourceFileNotFound(String path) => isIndonesian
      ? 'File asal tidak ditemukan: $path'
      : 'Source file not found: $path';
  static String svcFolderWriteFailed(String folder) => isIndonesian
      ? 'Gagal menulis file ke folder $folder. Pastikan izin penyimpanan diberikan.'
      : 'Failed to write file to folder $folder. Please grant storage permission.';
  static String get svcNoAudioStreamYet => isIndonesian
      ? 'Belum ada stream yang berhasil.'
      : 'No stream succeeded yet.';
  static String svcAudioDownloadAllFailed(String detail) => isIndonesian
      ? 'Gagal mengunduh stream audio di semua jalur ekstraksi. Detail terakhir: $detail'
      : 'Failed to download audio stream from all extractors. Last detail: $detail';
  static String svcDownloadingAudioProgress(
    String label,
    String downloadedMb, [
    String? totalMb,
  ]) {
    if (isIndonesian) {
      return totalMb != null
          ? 'Mengunduh audio ($label): $downloadedMb MB / $totalMb MB'
          : 'Mengunduh audio ($label): $downloadedMb MB';
    }
    return totalMb != null
        ? 'Downloading audio ($label): $downloadedMb MB / $totalMb MB'
        : 'Downloading audio ($label): $downloadedMb MB';
  }

  static String svcDownloadingHiResProgress(
    String downloadedMb,
    String? totalMb,
    String addonName,
  ) {
    if (isIndonesian) {
      return totalMb != null
          ? 'Mengunduh Hi-Res FLAC ($downloadedMb / $totalMb MB) • $addonName'
          : 'Mengunduh Hi-Res FLAC ($downloadedMb MB) • $addonName';
    }
    return totalMb != null
        ? 'Downloading Hi-Res FLAC ($downloadedMb / $totalMb MB) • $addonName'
        : 'Downloading Hi-Res FLAC ($downloadedMb MB) • $addonName';
  }

  static String get svcDownloadingHiResCover => isIndonesian
      ? 'Mengunduh cover art resolusi tinggi...'
      : 'Downloading high-res cover art...';
  static String svcSavingFormatToFolder(String format, String folder) =>
      isIndonesian
          ? 'Menyimpan file $format ke folder $folder...'
          : 'Saving $format file to folder $folder...';
  static String svcSavedAtPath(String path) =>
      isIndonesian ? 'Selesai! Tersimpan di: $path' : 'Done! Saved at: $path';
  static String svcTaggingFailed(String format, Object e) => isIndonesian
      ? 'Gagal memproses tagging $format: $e'
      : 'Failed to process $format tagging: $e';
  static String svcMp3TaggingFailed(Object e) => isIndonesian
      ? 'Gagal memproses konversi dan tagging MP3: $e'
      : 'Failed to convert and tag MP3: $e';
  static String svcRetagPermissionFailed(String format) => isIndonesian
      ? 'Gagal menyimpan tag ke file $format. Izinkan akses file musik jika diminta oleh sistem.'
      : 'Failed to save tags to $format file. Allow music file access if prompted by the system.';

  static String get pasteButton => isIndonesian ? 'Tempel' : 'Paste';
  static String get clearTooltip => isIndonesian ? 'Bersihkan' : 'Clear';
  static String get closeTooltip => isIndonesian ? 'Tutup' : 'Close';
  static String get searchButton => isIndonesian ? 'Cari' : 'Search';
  static String get openButton => isIndonesian ? 'Buka' : 'Open';
  static String get openLinkButton => openButton;
  static String get saveToLabel => isIndonesian ? 'Simpan ke:' : 'Save to:';

  static String get capabilityTitleArtist => isIndonesian
      ? 'Judul / Artis (Romaji J-Pop)'
      : 'Title / Artist (Romaji J-Pop)';

  static String get capabilityYoutube =>
      isIndonesian ? 'Link YouTube / YT Music' : 'YouTube / YT Music Link';

  static String get capabilitySpotify => isIndonesian
      ? 'Link Spotify (Track, Album & Playlist)'
      : 'Spotify Link (Track, Album & Playlist)';

  static String get searchingCatalogStatus =>
      isIndonesian ? 'Mencari katalog lagu...' : 'Searching music catalog...';

  static String get downloaderCardTitle =>
      'MusEvee All-in-One Downloader (MP3 / Hi-Res FLAC)';

  static String get downloaderCardDesc => isIndonesian
      ? 'Ketik judul lagu (Deezer/iTunes) atau tempel tautan Spotify / YouTube. Lirik otomatis diprioritaskan ke bahasa asli & tertanam ke file audio.'
      : 'Search by title/artist or paste a Spotify / YouTube link. Original-language lyrics are automatically embedded into the audio file.';

  static String get forYouTitle => isIndonesian ? 'Untukmu' : 'For You';
  static String get forYouCarouselTitle => forYouTitle;

  static String forYouSubtitle(List<String> seedArtists) {
    if (seedArtists.isEmpty) {
      return isIndonesian
          ? 'Rekomendasi pilihan untukmu'
          : 'Recommended tracks for you';
    }
    final joined = seedArtists.take(3).join(', ');
    return isIndonesian ? 'Berdasarkan $joined' : 'Based on $joined';
  }

  static String get globalTrendingTitle => 'Global Trending';
  static String get globalTrendingSubtitle => isIndonesian
      ? 'Lagu terpopuler di seluruh dunia saat ini'
      : 'Most popular tracks worldwide right now';

  static String get indonesiaTrendingTitle => 'Indonesia Trending';
  static String get indonesiaTrendingSubtitle => isIndonesian
      ? 'Lagu yang sedang naik daun di Indonesia'
      : 'Top trending songs in Indonesia';

  static String get offlineTitle =>
      isIndonesian ? 'Tidak Ada Koneksi Internet' : 'No Internet Connection';

  static String get offlineSubtitle => isIndonesian
      ? 'Periksa koneksi Wi-Fi atau data seluler Anda, lalu ketuk Segarkan untuk memuat ulang.'
      : 'Please check your Wi-Fi or mobile data connection, then tap Refresh to try again.';

  static String get refreshRetryButton =>
      isIndonesian ? 'Segarkan / Coba Lagi' : 'Refresh / Retry';

  static String noResultsFoundFor(String query) => isIndonesian
      ? 'Tidak ditemukan lagu untuk "$query".'
      : 'No songs found for "$query".';

  // ===========================================================================
  // TRACK PREVIEW & DOWNLOAD CONFIRMATION SHEET
  // ===========================================================================
  static String get previewAudioSourceAuto =>
      isIndonesian ? 'Sumber Audio: Otomatis' : 'Audio source: Automatic';

  static String previewAudioSourceCustom(String title, String duration) =>
      isIndonesian
          ? 'Sumber: $title ($duration)'
          : 'Source: $title ($duration)';

  static String get previewChangeSource =>
      isIndonesian ? 'Ganti Sumber' : 'Change Source';

  static String get previewClose => isIndonesian ? 'Tutup' : 'Close';

  static String get previewNoOtherSources => isIndonesian
      ? 'Sumber lain tidak ditemukan, menggunakan pilihan otomatis.'
      : 'No other sources found, using automatic match.';

  static String get previewSyncedLyrics =>
      isIndonesian ? 'Lirik Berjalan' : 'Synced lyrics';

  static String get previewPlainLyrics =>
      isIndonesian ? 'Lirik Biasa' : 'Plain lyrics';

  static String get previewChangeLyrics =>
      isIndonesian ? 'Ganti Lirik' : 'Change lyrics';

  static String get previewFetchingLyrics =>
      isIndonesian ? 'Mengambil lirik...' : 'Fetching lyrics...';

  static String get previewNoLyricsPlaceholder => isIndonesian
      ? 'Belum ada lirik. Ketuk ikon pensil untuk mengisi manual.'
      : 'No lyrics yet. Tap the edit icon to add manually.';

  static String get previewNoLyricsCandidates => isIndonesian
      ? 'Versi lirik lain tidak ditemukan di LRCLIB.'
      : 'No other lyrics found on LRCLIB.';

  static String get previewFolderDestination =>
      isIndonesian ? 'Folder Tujuan' : 'Folder destination';

  static String get previewNewFolder =>
      isIndonesian ? 'Folder baru' : 'New folder';

  static String previewSaveToFolder(String folder) =>
      isIndonesian ? 'Simpan ke $folder' : 'Save to $folder';

  static String get previewAddToDownloadList =>
      isIndonesian ? 'Masukkan ke antrean' : 'Add to download list';

  static String get previewPlayingSample =>
      isIndonesian ? 'Memutar cuplikan...' : 'Playing preview...';

  static String previewAlreadyInFolder(String folder) =>
      isIndonesian ? 'Sudah ada di $folder' : 'Already in $folder';

  static String get previewAutoRomaji => 'Auto-Romaji';

  static String get previewConvertingRomaji =>
      isIndonesian ? 'Mengonversi...' : 'Converting...';

  static String get previewEditInfoTooltip =>
      isIndonesian ? 'Edit Info & Lirik' : 'Edit Info & Lyrics';

  static String previewAddedToQueue(String folder, String title) => isIndonesian
      ? 'Ditambahkan ke antrean ($folder): $title'
      : 'Added to download list ($folder): $title';

  /// Formats a raw lyrics classification tag (e.g. `'[Inggris/Lainnya]'` or
  /// `'Inggris/Lainnya'`) with a single pair of brackets localized to the
  /// active language (`'[English/other]'` / `'[Japanese/Kanji]'` in English).
  static String formatLyricsLanguageTag(String rawTag) {
    final cleaned = rawTag.replaceAll('[', '').replaceAll(']', '').trim();
    final lower = cleaned.toLowerCase();
    final String localized;
    if (lower.isEmpty ||
        lower == 'inggris/lainnya' ||
        lower == 'english/other') {
      localized = isIndonesian ? 'Inggris/Lainnya' : 'English/other';
    } else if (lower == 'jepang/kanji' || lower == 'japanese/kanji') {
      localized = isIndonesian ? 'Jepang/Kanji' : 'Japanese/Kanji';
    } else {
      localized = cleaned;
    }
    return '[$localized]';
  }

  // ===========================================================================
  // TAG & LYRICS EDITOR SHEET
  // ===========================================================================
  static String editorTitle(bool isLocalOrHistory) => isLocalOrHistory
      ? (isIndonesian ? 'Edit Tag & Lirik Tertanam' : 'Edit Tags & Embedded Lyrics')
      : (isIndonesian ? 'Edit Info & Lirik' : 'Edit Info & Lyrics');

  static String editorSubtitle(bool isLocalOrHistory, {String? formatLabel}) {
    if (!isLocalOrHistory) {
      return isIndonesian
          ? 'Sesuaikan judul, artis, dan lirik lagu sebelum unduh'
          : 'Customize song title, artist, and lyrics before downloading';
    }
    final cleanFormat = formatLabel?.trim() ?? '';
    if (cleanFormat.isNotEmpty) {
      return isIndonesian
          ? 'Menulis ulang tag & lirik tertanam langsung ke file $cleanFormat'
          : 'Rewrite tags & embedded lyrics directly into the $cleanFormat file';
    }
    return isIndonesian
        ? 'Menulis ulang tag & lirik tertanam langsung ke file audio'
        : 'Rewrite tags & embedded lyrics directly into the audio file';
  }

  static String get editorSongTitleLabel =>
      isIndonesian ? 'Judul Lagu' : 'Song Title';

  static String get editorArtistLabel => isIndonesian ? 'Artis' : 'Artist';

  static String get editorAlbumLabel => 'Album';

  static String get editorYearLabel => isIndonesian ? 'Tahun' : 'Year';

  static String get editorLyricsHeader =>
      isIndonesian ? 'Lirik Tertanam:' : 'Embedded Lyrics:';

  static String get editorLyricsHint => isIndonesian
      ? 'Tempel lirik berjalan [00:12.34] ... atau lirik biasa di sini'
      : 'Paste synced lyrics [00:12.34] ... or plain lyrics here';

  static String get editorProcessingRomaji =>
      isIndonesian ? 'Proses...' : 'Working...';

  static String get editorCancelButton => isIndonesian ? 'Batal' : 'Cancel';

  static String get editorSaveButton => isIndonesian ? 'Simpan' : 'Save';
}

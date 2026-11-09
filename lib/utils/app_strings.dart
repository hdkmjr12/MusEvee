import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/widgets.dart';

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
    final override = debugLanguageCodeOverride?.trim().toLowerCase();
    if (override != null && override.isNotEmpty) {
      return override == 'id' || override == 'in';
    }
    if (context != null) {
      try {
        final locale = Localizations.maybeLocaleOf(context);
        if (locale != null && locale.languageCode.trim().isNotEmpty) {
          final code = locale.languageCode.trim().toLowerCase();
          return code == 'id' || code == 'in';
        }
      } catch (_) {}
    }
    try {
      final sysCode =
          PlatformDispatcher.instance.locale.languageCode.trim().toLowerCase();
      return sysCode == 'id' || sysCode == 'in';
    } catch (_) {
      return true;
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
  static String get settingsDownloadsSection =>
      isIndonesian ? 'Unduhan' : 'Downloads';
  static String get settingsDownloadQualityTitle =>
      isIndonesian ? 'Kualitas Audio Unduhan' : 'Download Audio Quality';
  static String get qualityBestTitle =>
      isIndonesian ? 'Terbaik — 320 kbps' : 'Best — 320 kbps';
  static String get qualityBestSubtitle =>
      isIndonesian ? '~9-10 MB per lagu 4 menit' : '~9-10 MB per 4-min song';
  static String get qualityBalancedTitle =>
      isIndonesian ? 'Seimbang — 192 kbps' : 'Balanced — 192 kbps';
  static String get qualityBalancedSubtitle =>
      isIndonesian ? '~5-6 MB per lagu 4 menit' : '~5-6 MB per 4-min song';
  static String get qualityEfficientTitle =>
      isIndonesian ? 'Hemat — 128 kbps' : 'Efficient — 128 kbps';
  static String get qualityEfficientSubtitle =>
      isIndonesian ? '~3-4 MB per lagu 4 menit' : '~3-4 MB per 4-min song';
  static String get settingsDownloadQualityNote => isIndonesian
      ? 'Pengaturan ini hanya memengaruhi ukuran file hasil unduhan, bukan penggunaan data saat mengunduh.'
      : 'This setting only affects the downloaded output file size, not data usage during download.';
  static String get appVersionFooter => 'MusEvee v4.7';

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
  // DOWNLOADER TAB & DISCOVERY CAROUSELS
  // ===========================================================================
  static String get omniboxHint => isIndonesian
      ? 'Cari lagu atau tempel link...'
      : 'Search songs or paste link...';

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

  static String get searchingCatalogStatus => isIndonesian
      ? 'Mencari katalog lagu...'
      : 'Searching music catalog...';

  static String get downloaderCardTitle =>
      'MusEvee All-in-One Downloader (MP3 320kbps + USLT Lyrics)';

  static String get downloaderCardDesc => isIndonesian
      ? 'Ketik judul lagu (Deezer/iTunes) atau tempel tautan Spotify / YouTube. Lirik otomatis diprioritaskan ke bahasa asli & tertanam ke tag USLT MP3.'
      : 'Search by title/artist or paste a Spotify / YouTube link. Original-language synced lyrics are automatically embedded into the MP3 USLT tag.';

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

  static String get offlineTitle => isIndonesian
      ? 'Tidak Ada Koneksi Internet'
      : 'No Internet Connection';

  static String get offlineSubtitle => isIndonesian
      ? 'Periksa koneksi Wi-Fi atau data seluler Anda, lalu ketuk Segarkan untuk memuat ulang.'
      : 'Please check your Wi-Fi or mobile data connection, then tap Refresh to try again.';

  static String get refreshRetryButton =>
      isIndonesian ? 'Segarkan / Coba Lagi' : 'Refresh / Retry';

  static String noResultsFoundFor(String query) => isIndonesian
      ? 'Tidak ditemukan lagu untuk "$query".'
      : 'No songs found for "$query".';
}

# MusicEvee — Project Context & AI Agent Rules (`AGENTS.md`)

> **MANDATORY WORKFLOW — SETIAP AI AGENT YANG MENGERJAKAN PROYEK INI WAJIB:**
> 1. Membaca `AGENTS.md` dan `CHANGELOG.md` terlebih dahulu sebelum menulis atau mengubah kode apa pun.
> 2. Menjaga 100% fitur Pemutar Lokal bergaya **Musicolet** maupun seluruh layanan **Downloader v3.x** (`MetadataService`, `LyricsService`, `AudioService`, `TaggingService`, `RomajiService`, `FolderService`) agar tidak mengalami regresi.
> 3. Setiap kali selesai memperbaiki bug, mengubah UI, atau menambah fitur baru, **WAJIB** memperbarui bagian **"Status Terkini"** di `AGENTS.md` dan menambahkan entri baru di bagian paling atas `CHANGELOG.md` sebelum melakukan `git commit` / `git push`.

---

## 1. Status Terkini Proyek

- **Nama & Versi Aplikasi Saat Ini:** **`MusicEvee` `v4.1`** (`pubspec.yaml` version `4.1.0+5`, badge UI `v4.1`)
- **Kondisi Build & CI/CD:** Aktif di `.github/workflows/build_apk.yml` — hanya menghasilkan **1 file APK ringan khusus ARM64 (`~20 MB`)** menggunakan `--split-per-abi --target-platform android-arm64`, `packaging.jniLibs.excludes` (`armeabi-v7a`, `x86`, `x86_64`), dan keystore permanen `android/app/musevee-release.jks`.
- **Update Terakhir (`v4.1` — True Queue-Order Shuffle, Incremental Library Cache, 200ms Ticker Isolation & Native AudioFocus):**
  - **True Queue-Order Shuffle & `QueueEntry` (`lib/models/local_song.dart`, `lib/providers/local_music_provider.dart`, `lib/widgets/local_library_views.dart`):** Antrean putar menggunakan `QueueEntry(queueId, song)` ber-ID unik dengan `ValueKey(entry.queueId)` dan `buildDefaultDragHandles: false` untuk mendukung duplikat lagu & drag-and-drop mulus; tombol Shuffle mengacak fisik `_queueEntries` menggunakan algoritma Fisher-Yates (menjaga lagu aktif di indeks `0`) dan memulihkan urutan asli `_originalQueueEntries` saat dimatikan; `playNext()` & `playPrevious()` selalu bergerak linier mengikuti urutan visual Queue; `playSongByPath` tidak lagi menimpa Queue aktif.
  - **Session Guard, Native `AudioFocusRequest` & Seekbar Snap-Back Guard (`MainActivity.kt`, `local_music_provider.dart`, `now_playing_view.dart`):** Penjaga `playbackSessionId` monotonik + validasi instance `mp === localPlayer` & `path` pada `OnCompletionListener` mencegah *double-skip*; dukungan penuh `AudioFocusRequest` (`AUDIOFOCUS_GAIN` dengan auto-pause saat telepon/aplikasi lain berbunyi & volume ducking, plus `AUDIOFOCUS_GAIN_TRANSIENT` & `resumeLocalAfterPreview` pada preview 30s); masa tenggang *seek guard* `350ms` menghilangkan gejala *seekbar snap-back*; sinkronisasi 2 arah instan `< 1ms` antara `LocalMusicProvider` dan `DownloaderProvider`.
  - **Instant Startup Hydrate (`< 50ms`) & Incremental Delta Sync (`MainActivity.kt`, `local_music_provider.dart`):** Menyimpan cache koleksi lokal di `musicevee_library_cache_v1.json`, sesi antrean terakhir di `musicevee_player_session.json`, serta sampul `APIC` permanen di `filesDir/covers`; handler native `scanLocalMusicLibraryDelta` hanya mengekstrak ulang file yang berubah (`lastModifiedMs` + `sizeBytes`) dan `upsertSingleSongByPath` menyisipkan lagu baru tanpa memindai ulang seluruh disk.
  - **Isolasi Rebuild 200ms (`ValueNotifier`), Memoisasi & Optimasi RAM Bitmap (`local_music_provider.dart`, `now_playing_view.dart`, `musicolet_mini_player.dart`, `local_library_views.dart`, `MainActivity.kt`):** Detak 5 Hz (`200ms`) diisolasi ke `progressNotifier` (`PlaybackProgress`) dan `activeLyricIndexNotifier` sehingga `IndexedStack` 8-tab tidak lagi di-rebuild 5x/detik; memoisasi `folderSongsMap`/`albumSongsMap`/`artistSongsMap` + `Expando` `parsedSyncedLyrics`; penghapusan `File.existsSync()` dari `build()`; penambahan `cacheWidth` proporsional (`144` thumbnail / `960` Now Playing) dan streaming parser `parseId3v2Tags` (`raf.seek()` melewati payload `APIC` multi-MB).

---

## 2. Identitas & Prinsip Desain (`MusicEvee` — Musicolet Dark UI)

- **Nama Aplikasi:** `MusicEvee` (sebelumnya `MusEvee` / `SpotMeta Downloader`).
- **Gaya Visual:** *1:1 Musicolet Dark UI/UX* dipadukan dengan kerapian *Architectural Hairline Borders*:
  - **Dynamic Ambient Background (Now Playing):** Gradasi gelap vertikal yang otomatis menyesuaikan warna dominan Cover Art lagu yang sedang diputar (misal ungu tua lembut untuk *YOASOBI - Idol*, abu-abu olive gelap untuk *ASCA - Resister*).
  - **Palet Warna Gelap (`Musicolet Dark Surface`):**
    - Canvas Background: `#0E1014` (Bottom Strip `#0A0C10`)
    - Surface Card / Sheet: `#17191E`
    - Surface Subtle / Input: `#22252D`
    - Primary Accent Blue: `#3898EC`
    - Text Primary Light: `#F2F4F7` / `#FFFFFF`
    - Text Muted: `#98A2B3`
    - Active Lyric Ribbon: `Colors.black.withValues(alpha: 0.45)` dengan teks putih **Bold**.
  - **Garis Batas (`Hairline Border`) & Radius:** Border tipis `0.7px–0.8px` (`Colors.white.withValues(alpha: 0.08–0.10)`) dan radius tegas `4px–10px` (modal bottom sheet top radius `16px`).
- **Logo & Ikon:**
  - Widget `MusEveeLogo` (`lib/widgets/musevee_logo.dart`) digambar menggunakan `CustomPainter` vektor murni dengan **100% background transparan**.

---

## 3. Arsitektur & Tech Stack

### Struktur Direktori Utama
```text
MusEvee/
├── AGENTS.md                                 # Cetak biru arsitektur MusicEvee & SOP wajib AI Agent
├── CHANGELOG.md                              # Rekam jejak kronologis terbalik perkembangan proyek (v1.0 -> v4.0)
├── .github/
│   ├── copilot-instructions.md               # Instruksi otomatis GitHub Copilot / Remote Agent
│   └── workflows/
│       └── build_apk.yml                     # CI/CD otomatis build APK ARM64 (~20 MB) & GitHub Release
├── .idx/
│   └── airules.md                            # Instruksi otomatis Project IDX / Gemini Agent
├── android/
│   └── app/
│       ├── build.gradle.kts                  # Konfigurasi Gradle Kotlin DSL, signing musevee-release.jks & filter ARM64
│       ├── musevee-release.jks               # Keystore permanen agar tanda tangan APK konsisten antar build CI
│       └── src/main/
│           ├── AndroidManifest.xml           # Label "MusicEvee", izin audio/penyimpanan/equalizer, & Share Intent
│           └── kotlin/com/example/spotmeta_downloader/
│               └── MainActivity.kt           # MethodChannel native: Local MediaPlayer, ID3v2 APIC/USLT reader, Equalizer, 30s Preview, MediaScanner, Share Intent
├── lib/
│   ├── main.dart                             # Entry point MusicEveeApp, MultiProvider (LocalMusicProvider + DownloaderProvider), & Dark Musicolet Theme
│   ├── models/
│   │   ├── download_item.dart                # Model item antrean & riwayat unduhan FFmpeg
│   │   ├── local_song.dart                   # Model lagu lokal + parser LRC [mm:ss.xx] SyncedLyricEntry & jembatan ke TrackMetadata
│   │   └── track_metadata.dart               # Model metadata unduhan, normalisasi lirik (\r\n), & pemilih payload USLT
│   ├── providers/
│   │   ├── downloader_provider.dart          # State management Downloader (pencarian katalog, lirik, Romaji, antrean unduh, retag)
│   │   └── local_music_provider.dart         # State management Pemutar Lokal Musicolet (library scan, queue, play mode 1→, sync lirik, retag/pindah/hapus lokal)
│   ├── screens/
│   │   └── home_screen.dart                  # Shell utama 8-Tab Musicolet + Unified MethodChannel Router + Smart Omnibox Downloader
│   ├── services/
│   │   ├── audio_service.dart                # Ekstraktor stream YouTube (YoutubeExplode multi-client) & 5 kandidat manual
│   │   ├── folder_service.dart               # Manajemen folder (/storage/emulated/0/Music/*), duplicate checker, & MediaScanner
│   │   ├── lyrics_service.dart               # Pencarian kandidat lirik LRCLIB dengan prioritas bahasa asli Jepang/Romaji + fallback lyrics.ovh
│   │   ├── metadata_service.dart             # Ekstraktor link Spotify (oEmbed/OpenGraph Track/Album/Playlist) & pencarian Deezer+iTunes
│   │   ├── romaji_service.dart               # Konversi Kanji/Kana ke Romaji baris-demi-baris + Anti Double-Romaji & Furigana Deduplication
│   │   └── tagging_service.dart              # Konversi FFmpeg MP3 320kbps, injeksi biner ID3v2.4.0 (APIC + USLT \r\n), & retag instan (-c:a copy)
│   └── widgets/
│       ├── batch_playlist_sheet.dart         # Bottom sheet pemilihan lagu massal dari Album/Playlist Spotify
│       ├── local_library_views.dart          # Tab lokal Musicolet: PlaybackQueueView, LocalFoldersView, LocalAlbumsView, LocalArtistsView, LocalSearchView
│       ├── musevee_logo.dart                 # CustomPainter logo vektor transparan MusicEvee
│       ├── musicolet_bottom_strip.dart       # Deretan 8 ikon navigasi bawah khas Musicolet dengan garis indikator putih
│       ├── musicolet_mini_player.dart        # Mini Player tipis ala Musicolet di atas bottom strip
│       ├── now_playing_view.dart             # Layar utama 1:1 Musicolet Now Playing + Embedded Lyrics Ribbon + Tap-to-Seek
│       ├── queue_history_view.dart           # Tab Download Queue & History beserta tombol Putar (▶), Pindah Folder, & Edit Tag Ulang
│       ├── search_result_tile.dart           # Tile hasil pencarian katalog lagu dengan indikator duplikat folder
│       ├── tag_editor_sheet.dart             # Modal editor tag ID3 & lirik (pra-unduh, riwayat unduhan, maupun lagu lokal yang sedang diputar!)
│       └── track_preview_sheet.dart          # Modal detail unduhan: preview 30s, pilih sumber YouTube, Ganti Lirik LRCLIB, Auto-Romaji, & pilih folder
└── test/
    ├── romaji_service_test.dart              # Unit test Romaji, deduplikasi bilingual, prioritas bahasa LyricsService, & parser USLT LocalSong
    └── widget_test.dart                      # Widget test layar NowPlayingView & navigasi 8-tab MusicEvee
```

### Integrasi Native Android (`MainActivity.kt`)
Menggunakan satu `MethodChannel('com.spotmeta.downloader/system')` terpadu yang di-routing di `HomeScreen`:
1. **Mesin Pemutar Lokal & AudioFocus:** `localPlayFile` (dengan `sessionId`), `localPause`, `localResume`, `localSeekTo`, `localStop`, `getVolume`, `setVolume`, `openEqualizer` (`AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL`), `AudioFocusRequest` (`AUDIOFOCUS_GAIN` + ducking + auto-resume setelah preview 30s), serta event real-time `onLocalPosition`, `onLocalPlayerState`, dan `onLocalTrackCompleted`.
2. **Pemindai Delta Inkremental & Pembaca Streaming Tag `USLT`/`APIC`:** `scanLocalMusicLibraryDelta`, `scanLocalMusicLibrary`, dan `readLocalTrackDetails` memadukan `MediaMetadataRetriever` dengan streaming parser `RandomAccessFile` ID3v2 (`v2.2`/`v2.3`/`v2.4`, melewati frame besar via `raf.seek()`), menyimpan sampul `APIC` permanen ke `filesDir/covers`, menghitung warna dominan Cover Art, dan membaca teks lirik `USLT`.
3. **MediaStore & File Sync:** `scanMediaFile` (`MediaScannerConnection.scanFile`) dan `deleteMediaFile` (`MediaStore.Audio.Media.EXTERNAL_CONTENT_URI`).
4. **Share Intent & 30s Preview Downloader:** `getInitialSharedText` / `onSharedText` serta `playPreviewUrl` / `stopPreview` / `onPreviewStateChanged` (otomatis menjeda lagu lokal saat memutar preview 30 detik agar suara tidak bertabrakan).

---

## 4. Daftar Fitur Inti yang Wajib Dijaga (Anti-Regresi)

1. **1:1 Musicolet Now Playing & Embedded Lyrics (`NowPlayingView` & `LocalMusicProvider`):**
   - Dynamic Ambient Background, panel `Embedded lyrics ⌄` dengan pita gelap aktif & *Tap-to-Seek*, tombol `✎`, `⊙`, `TT`, `✕`, baris utilitas (`♥`, `(i)`, `=+`, `[...]`, `1→` Play Mode, `🔀` Shuffle), seekbar putih bersih, kontrol transport tanpa lingkaran background pada tombol Play/Pause, dan Equalizer sistem Android.
2. **8-Tab Musicolet Bottom Icon Strip + Mini Player (`MusicoletBottomStrip` & `MusicoletMiniPlayer`):**
   - Tab `Queue`, `Now Playing`, `Folders`, `Albums`, `Artists`, `Downloader`, `Download Queue & History`, dan `Search Lokal`.
3. **100% Fitur All-in-One Downloader v3.x (`DownloaderProvider` & Services):**
   - Smart Omnibox (Deezer + iTunes + Link Spotify Track/Album/Playlist), chip folder tujuan (`Music Barat`, `Music Japan`, `Music Random`, `+ Baru`), deteksi duplikat lintas folder, Preview Audio 30s, Pemilih Sumber YouTube manual, `BatchPlaylistSheet`, Pindah Folder 1-klik, dan Retag MP3 instan (`-c:a copy` + biner ID3v2.4.0 `APIC` & `USLT` `\r\n` tanpa file `.lrc` eksternal).
4. **Anti Double-Romaji & Prioritas Bahasa Asli (`RomajiService` & `LyricsService`):**
   - Isolasi timestamp `[mm:ss.xx]` baris-demi-baris, normalisasi makron (`ū`/`ō`) & deduplikasi baris kembar bilingual/Romaji, penghapusan furigana inline, prioritas skor lirik Jepang/Romaji di atas terjemahan Inggris pada LRCLIB, serta pemilih manual **"Ganti Lirik"** di `NowPlayingView`, `TrackPreviewSheet`, dan `TagEditorSheet`.
5. **Build APK Ringan ARM64 (~20 MB) & Keystore Permanen (`.github/workflows/build_apk.yml`):**
   - Selalu gunakan `--split-per-abi --target-platform android-arm64` dan `android/app/musevee-release.jks`.

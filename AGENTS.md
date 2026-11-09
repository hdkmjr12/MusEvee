# MusEvee — Project Context & AI Agent Rules (`AGENTS.md`)

> **MANDATORY WORKFLOW — SETIAP AI AGENT YANG MENGERJAKAN PROYEK INI WAJIB:**
> 1. Membaca `AGENTS.md` dan `CHANGELOG.md` terlebih dahulu sebelum menulis atau mengubah kode apa pun.
> 2. Menjaga 100% fitur Pemutar Lokal bergaya **Musicolet** maupun seluruh layanan **Downloader v3.x** (`MetadataService`, `LyricsService`, `AudioService`, `TaggingService`, `RomajiService`, `FolderService`) agar tidak mengalami regresi.
> 3. Setiap kali selesai memperbaiki bug, mengubah UI, atau menambah fitur baru, **WAJIB** memperbarui bagian **"Status Terkini"** di `AGENTS.md` dan menambahkan entri baru di bagian paling atas `CHANGELOG.md` sebelum melakukan `git commit` / `git push`.

---

## 1. Status Terkini Proyek

- **Nama Resmi & Permanen Aplikasi:** **`MusEvee`** (bukan *MusicEvee* / *SpotMeta Downloader*; `applicationId = "com.zte.as.music"` untuk dukungan native Live Island ZTE/nubia)
- **Versi Aplikasi Saat Ini:** **`MusEvee` `v4.5`** (`pubspec.yaml` version `4.5.0+10`, badge UI `v4.5`)
- **Kondisi Build & CI/CD:** Aktif di `.github/workflows/build_apk.yml` — menghasilkan **1 file APK ringan khusus ARM64 (`~20 MB`, `MusEvee-v4.5-arm64.apk`)** menggunakan `--split-per-abi --target-platform android-arm64`, `packaging.jniLibs.excludes` (`armeabi-v7a`, `x86`, `x86_64`), keystore permanen `android/app/musevee-release.jks`, wrapper Gradle (`gradle-wrapper.jar` + `gradle-9.3.1-bin.zip`) yang di-track langsung di Git bersama Google Cloud Maven Central mirror & HTTP retry hardening, serta publikasi otomatis ke **GitHub Releases (`v4.5.0`)** via `softprops/action-gh-release@v2`.
- **Update Terakhir (`v4.5` — Context-Aware & Rotated Queue, 6 Musicolet Smart Playlists + `Your playlists`, Fix Duplikasi Aplikasi di Recent Apps `singleTask`, & Interactive Folder Explorer pada Downloader):**
  - **Context-Aware & Rotated Queue (`local_music_provider.dart`, `local_library_views.dart`):** Ketika memilih lagu dari **Folder**, **Playlist** (Smart Playlist maupun User Playlist), atau **Search Lokal** (`localProvider.allSongs`), `queue` otomatis diganti dengan seluruh lagu dari konteks asal tersebut dan dirotasi sehingga lagu terpilih berada di urutan `#1` (`index 0`), diikuti lagu-lagu setelahnya (`index + 1 .. akhir`), dan lagu-lagu yang tadinya berada di atasnya (`0 .. index - 1`) dipindahkan ke bagian paling bawah antrean.
  - **Perombakan Halaman `Playlists` ala Musicolet (`local_library_views.dart`, `local_music_provider.dart`, `MainActivity.kt`):**
    - **6 Smart Playlists Otomatis di Bagian Atas:** `All songs`, `Favorites`, `Recently added`, `Recently played`, `Most played`, dan `Not played` dengan pelacakan `playCount` & `lastPlayedMs` persisten di `musevee_play_stats_v1.json` (ikut disinkronkan di `syncPersistentAppState()`).
    - **Bagian Bawah `Your playlists`:** Sub-header **`Your playlists`** berwarna hijau khas Musicolet (`#4CAF50`), tombol ber-border **`+ New Playlist`**, daftar playlist pengguna, serta dukungan penuh penggabungan lintas Smart Playlist dan User Playlist melalui tombol mengambang `_MorphingMergeActionBar` di kanan bawah.
  - **Fix Duplikasi Aplikasi di Android Recent Apps (`AndroidManifest.xml`, `MainActivity.kt`):** Mengubah `android:launchMode="singleTask"` pada `MainActivity` dan menghapus `android:taskAffinity=""` agar membuka aplikasi dari Launcher, membagikan link dari Spotify/YouTube (`ACTION_SEND`), maupun mengetuk notifikasi media / Live Island selalu diarahkan ke satu instance tunggal `MusEvee` tanpa pernah menggandakan kartu di Recent Apps.
  - **UI Downloader Lebih Informatif & Interactive Folder Picker pada Tombol `+` (`home_screen.dart`, `folder_service.dart`, `downloader_provider.dart`, `metadata_service.dart`, `MainActivity.kt`):**
    - Memperpendek `hintText` Omnibox menjadi `"Cari lagu atau tempel link..."` agar tidak pernah terpotong (`...`) dan menampilkan 3 badge fitur di bawah kolom pencarian (`Judul / Artis (Romaji J-Pop)`, `Link YouTube / YT Music`, `Link Spotify (Track, Album & Playlist)`), lengkap dengan dukungan ekstraksi langsung link YouTube / YT Music.
    - Mengetuk tombol **`+`** di baris **"Simpan ke:"** kini membuka **Interactive Folder Picker / Storage Explorer** yang memungkinkan pengguna memilih direktori `/storage/emulated/0/Music` secara langsung, menelusuri subfolder di penyimpanan internal, membuat subfolder baru, atau membuka *System Folder Picker* Android (`Intent.ACTION_OPEN_DOCUMENT_TREE`), lalu menyimpannya secara persisten di `musevee_custom_folders_v1.json`.
  - **Fitur Sebelumnya (`v4.4`):** Navigasi Bawah 6 Tab + Sliding Pill Indicator + Modal Bottom Sheet Antrean Unduhan `88%`, Mograph Motion & Liquid Shape Morphing (`_MorphingMergeActionBar`, `MographPlayPauseIcon`, Dynamic Artwork Scale), Multi-Folder & Multi-Playlist Queue Merger, Hi-Fi Unattenuated Audio Engine (`1.0` Volume) + Pre-Amp `LoudnessEnhancer`, serta sistem Draft + tombol **Terapkan** di Kelola Folder.
  - **Fitur Sebelumnya (`v4.3` & `v4.2`):** Universal Audio Folder Scanner + Strict Anti-Junk Filter (`>= 15s` / `>= 50 KB`, blacklist folder non-musik), fitur **"Kelola / Sembunyikan Folder"** (`musevee_hidden_folders_v1.json`), Smart Default Folders, First-Run Permission Onboarding & Info Dialog Live Island, perbaikan ekstraksi Playlist Spotify Private + dukungan token `?pt=`, logo transparan `assets/musevee_logo.png`, Native `MediaSession` Notification + ZTE/nubia Live Island Support (`applicationId = "com.zte.as.music"`), Scoped Storage Android 15, & Cross-Script Romaji J-Pop Search.

---

## 2. Identitas & Prinsip Desain (`MusEvee` — Musicolet Dark UI)

- **Nama Resmi & Permanen Aplikasi:** `MusEvee` (tanpa huruf *"ic"*).
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
  - Widget `MusEveeLogo` (`lib/widgets/musevee_logo.dart`) memuat aset `assets/musevee_logo.png` berlatar **100% transparan** yang identik dengan `mipmap-*/ic_launcher.png`.

---

## 3. Arsitektur & Tech Stack

### Struktur Direktori Utama
```text
MusEvee/
├── AGENTS.md                                 # Cetak biru arsitektur MusEvee & SOP wajib AI Agent
├── CHANGELOG.md                              # Rekam jejak kronologis terbalik perkembangan proyek (v1.0 -> v4.4)
├── .github/
│   ├── copilot-instructions.md               # Instruksi otomatis GitHub Copilot / Remote Agent
│   └── workflows/
│       └── build_apk.yml                     # CI/CD otomatis build APK ARM64 (~20 MB) & GitHub Release (MusEvee-v4.4-arm64.apk)
├── .idx/
│   └── airules.md                            # Instruksi otomatis Project IDX / Gemini Agent
├── android/
│   └── app/
│       ├── build.gradle.kts                  # Konfigurasi Gradle Kotlin DSL, signing musevee-release.jks & filter ARM64
│       ├── musevee-release.jks               # Keystore permanen agar tanda tangan APK konsisten antar build CI
│       └── src/main/
│           ├── AndroidManifest.xml           # Label permanen "MusEvee", izin audio/penyimpanan/notifikasi/foregroundService, & Share Intent
│           └── kotlin/com/example/spotmeta_downloader/
│               ├── MainActivity.kt           # MethodChannel native: Local MediaPlayer, Universal Audio Scanner, ID3v2 APIC/USLT reader, Scoped Storage Delete/Write, Permission Onboarding, Equalizer, 30s Preview, MediaScanner, Share Intent
│               └── MusEveeMediaNotifier.kt   # Native MediaSession + Notification.MediaStyle + MusEveePlaybackService (lockscreen & notification seekbar/controls)
├── assets/
│   └── musevee_logo.png                      # Logo resmi MusEvee 512x512 berlatar 100% transparan
├── lib/
│   ├── main.dart                             # Entry point MusEveeApp, MultiProvider (LocalMusicProvider + DownloaderProvider), & Dark Musicolet Theme
│   ├── models/
│   │   ├── download_item.dart                # Model item antrean & riwayat unduhan FFmpeg (+ targetPlaylistId)
│   │   ├── local_playlist.dart               # Model playlist lokal (`musicevee_playlists_v1.json`)
│   │   ├── local_song.dart                   # Model lagu lokal (+ folderPath) + parser LRC [mm:ss.xx] SyncedLyricEntry & jembatan ke TrackMetadata
│   │   └── track_metadata.dart               # Model metadata unduhan, normalisasi identitas lintas-aksara, & pemilih payload USLT
│   ├── providers/
│   │   ├── downloader_provider.dart          # State management Downloader (pencarian katalog, lirik, Romaji, antrean unduh, Smart Deduplication, playlist sync)
│   │   └── local_music_provider.dart         # State management Pemutar Lokal Musicolet (library scan, hidden folders, permission status, queue, Multi-Folder/Playlist Queue Merger, playlists CRUD, play mode 1→, sync lirik, retag/pindah/hapus lokal)
│   ├── screens/
│   │   └── home_screen.dart                  # Shell utama 6-Tab Musicolet + Permission Onboarding Banner + Info/Live Island Dialog + Smart Omnibox Downloader + Modal Sheet Antrean Unduhan (88%)
│   ├── services/
│   │   ├── audio_service.dart                # Ekstraktor stream YouTube (YoutubeExplode multi-client) & 5 kandidat manual
│   │   ├── folder_service.dart               # Manajemen folder (/storage/emulated/0/Music/*), Scoped Storage delete/write, permission checks, cross-folder duplicate checker, & MediaScanner
│   │   ├── lyrics_service.dart               # Pencarian kandidat lirik LRCLIB dengan prioritas bahasa asli Jepang/Romaji + fallback lyrics.ovh
│   │   ├── metadata_service.dart             # Ekstraktor link Spotify + Mesin Pencari Lintas-Aksara (Google IME Romaji->Kanji + iTunes JP/Global + Deezer)
│   │   ├── romaji_service.dart               # Konversi Kanji/Kana ke Romaji baris-demi-baris + Anti Double-Romaji & Furigana Deduplication
│   │   └── tagging_service.dart              # Konversi FFmpeg MP3 320kbps, injeksi biner ID3v2.4.0 (APIC + USLT \r\n), & retag instan (-c:a copy)
│   └── widgets/
│       ├── batch_playlist_sheet.dart         # Bottom sheet pemilihan lagu massal dari Album/Playlist Spotify + auto-sync playlist lokal
│       ├── local_library_views.dart          # Tab lokal Musicolet: PlaybackQueueView, LocalFoldersView (+ Kelola/Sembunyikan Folder & Multi-Folder Merger), LocalPlaylistsView (+ Multi-Playlist Merger), LocalSearchView
│       ├── musevee_logo.dart                 # Widget logo transparan MusEvee (`assets/musevee_logo.png`)
│       ├── musicolet_bottom_strip.dart       # Deretan 6 ikon navigasi bawah khas Musicolet dengan Sliding Pill Indicator (`AnimatedPositioned` 240ms)
│       ├── musicolet_mini_player.dart        # Mini Player tipis ala Musicolet di atas bottom strip
│       ├── now_playing_view.dart             # Layar utama 1:1 Musicolet Now Playing + Embedded Lyrics Ribbon + Tap-to-Seek
│       ├── pressable_scale.dart              # Micro-animations: PressableScale (0.95 scale 100ms), AnimatedIndexedStack (Slide+Fade 200ms), & AnimatedEqualizerIcon (4 batang hidup)
│       ├── queue_history_view.dart           # View Antrean & Riwayat Unduhan beserta tombol Putar (▶), Pindah Folder, & Edit Tag Ulang
│       ├── search_result_tile.dart           # Tile hasil pencarian katalog lagu dengan indikator duplikat folder
│       ├── tag_editor_sheet.dart             # Modal editor tag ID3 & lirik (pra-unduh, riwayat unduhan, maupun lagu lokal yang sedang diputar!)
│       └── track_preview_sheet.dart          # Modal detail unduhan: preview 30s, pilih sumber YouTube, Ganti Lirik LRCLIB, Auto-Romaji, & pilih folder
└── test/
    ├── romaji_service_test.dart              # Unit test Romaji, deduplikasi bilingual, prioritas bahasa LyricsService, pencarian lintas-aksara, & parser USLT LocalSong
    └── widget_test.dart                      # Widget test layar NowPlayingView, True Queue-Order Shuffle, Multi-Folder Queue Merger, & navigasi 6-tab MusEvee
```

### Integrasi Native Android (`MainActivity.kt`)
Menggunakan satu `MethodChannel('com.spotmeta.downloader/system')` terpadu yang di-routing di `HomeScreen`:
1. **Mesin Pemutar Lokal & AudioFocus:** `localPlayFile` (dengan `sessionId`), `localPause`, `localResume`, `localSeekTo`, `localStop`, `getVolume`, `setVolume`, `openEqualizer` (`AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL`), `AudioFocusRequest` (`AUDIOFOCUS_GAIN` + ducking + auto-resume setelah preview 30s), serta event real-time `onLocalPosition`, `onLocalPlayerState`, dan `onLocalTrackCompleted`.
2. **Pemindai Universal Delta Inkremental & Pembaca Streaming Tag `USLT`/`APIC`:** `scanLocalMusicLibraryDelta`, `scanLocalMusicLibrary`, dan `readLocalTrackDetails` memindai seluruh folder musik di penyimpanan internal/eksternal dengan filter anti-sampah ketat (`>= 15s` atau `>= 50 KB`, blacklist folder non-musik), memadukan `MediaMetadataRetriever` dengan streaming parser `RandomAccessFile` ID3v2 (`v2.2`/`v2.3`/`v2.4`, melewati frame besar via `raf.seek()`), menyimpan sampul `APIC` permanen ke `filesDir/covers`, menghitung warna dominan Cover Art, dan membaca teks lirik `USLT`.
3. **Scoped Storage Android 11–15, Permission Onboarding & MediaStore Sync:** `deleteLocalAudioFile`, `writeBytesToMusicFile`, `hasAllFilesAccess`, `requestAllFilesAccess`, `hasNotificationPermission`, `requestNotificationPermission`, `openNotificationSettings`, `getPermissionsStatus`, `deleteMediaFile`, dan `scanMediaFile` (`MediaScannerConnection.scanFile` + `MediaStore.createDeleteRequest` / `MediaStore.createWriteRequest` + `MANAGE_EXTERNAL_STORAGE`).
4. **Share Intent & 30s Preview Downloader:** `getInitialSharedText` / `onSharedText` serta `playPreviewUrl` / `stopPreview` / `onPreviewStateChanged` (otomatis menjeda lagu lokal saat memutar preview 30 detik agar suara tidak bertabrakan).

---

## 4. Daftar Fitur Inti yang Wajib Dijaga (Anti-Regresi)

1. **1:1 Musicolet Now Playing & Embedded Lyrics (`NowPlayingView` & `LocalMusicProvider`):**
   - Dynamic Ambient Background, panel `Embedded lyrics ⌄` dengan pita gelap aktif & *Tap-to-Seek*, tombol `✎`, `⊙`, `TT`, `✕`, baris utilitas (`♥`, `(i)`, `=+`, `[...]`, `1→` Play Mode, `🔀` Shuffle), seekbar putih bersih, kontrol transport tanpa lingkaran background pada tombol Play/Pause, dan Equalizer sistem Android.
2. **6-Tab Musicolet Bottom Icon Strip + Sliding Pill Indicator + Mini Player (`MusicoletBottomStrip` & `MusicoletMiniPlayer`):**
   - Tab `Queue`, `Now Playing`, `Folders` (+ Kelola/Sembunyikan Folder & Multi-Folder Queue Merger), `Playlists` (`musicevee_playlists_v1.json` + Multi-Playlist Queue Merger), `Downloader` (+ tombol kompak Modal Sheet Antrean & Riwayat Unduhan `88%`), dan `Search Lokal`. Indikator putih `2.5px` bergeser mulus (`AnimatedPositioned`) tanpa fitur swipe horizontal pada Mini Player.
3. **100% Fitur All-in-One Downloader v3.x (`DownloaderProvider` & Services):**
   - Smart Omnibox (Deezer + iTunes + Link Spotify Track/Album/Playlist), chip folder tujuan (`Music Barat`, `Music Japan`, `Music Random`, atau `MusEvee` + `+ Baru`), deteksi duplikat lintas folder, Preview Audio 30s, Pemilih Sumber YouTube manual, `BatchPlaylistSheet`, Pindah Folder 1-klik, dan Retag MP3 instan (`-c:a copy` + biner ID3v2.4.0 `APIC` & `USLT` `\r\n` tanpa file `.lrc` eksternal).
4. **Anti Double-Romaji & Prioritas Bahasa Asli (`RomajiService` & `LyricsService`):**
   - Isolasi timestamp `[mm:ss.xx]` baris-demi-baris, normalisasi makron (`ū`/`ō`) & deduplikasi baris kembar bilingual/Romaji, penghapusan furigana inline, prioritas skor lirik Jepang/Romaji di atas terjemahan Inggris pada LRCLIB, serta pemilih manual **"Ganti Lirik"** di `NowPlayingView`, `TrackPreviewSheet`, dan `TagEditorSheet`.
5. **Build APK Ringan ARM64 (~20 MB) & Keystore Permanen (`.github/workflows/build_apk.yml`):**
   - Selalu gunakan `--split-per-abi --target-platform android-arm64`, `android/app/musevee-release.jks`, dan publikasi otomatis ke GitHub Releases.

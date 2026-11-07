# MusEvee — Project Context & AI Agent Rules (`AGENTS.md`)

> **MANDATORY WORKFLOW — SETIAP AI AGENT YANG MENGERJAKAN PROYEK INI WAJIB:**
> 1. Membaca `AGENTS.md` dan `CHANGELOG.md` terlebih dahulu sebelum menulis atau mengubah kode apa pun.
> 2. Menjaga 100% fitur Pemutar Lokal bergaya **Musicolet** maupun seluruh layanan **Downloader v3.x** (`MetadataService`, `LyricsService`, `AudioService`, `TaggingService`, `RomajiService`, `FolderService`) agar tidak mengalami regresi.
> 3. Setiap kali selesai memperbaiki bug, mengubah UI, atau menambah fitur baru, **WAJIB** memperbarui bagian **"Status Terkini"** di `AGENTS.md` dan menambahkan entri baru di bagian paling atas `CHANGELOG.md` sebelum melakukan `git commit` / `git push`.

---

## 1. Status Terkini Proyek

- **Nama Resmi & Permanen Aplikasi:** **`MusEvee`** (bukan *MusicEvee* / *SpotMeta Downloader*)
- **Versi Aplikasi Saat Ini:** **`MusEvee` `v4.2`** (`pubspec.yaml` version `4.2.0+6`, badge UI `v4.2`)
- **Kondisi Build & CI/CD:** Aktif di `.github/workflows/build_apk.yml` — hanya menghasilkan **1 file APK ringan khusus ARM64 (`~20 MB`)** menggunakan `--split-per-abi --target-platform android-arm64`, `packaging.jniLibs.excludes` (`armeabi-v7a`, `x86`, `x86_64`), dan keystore permanen `android/app/musevee-release.jks`.
- **Update Terakhir (`v4.2` — Rebranding Permanen `MusEvee`, Scoped Storage Android 15 File Delete/Retag/Move, Cross-Script Romaji J-Pop Search & Live Audit `Z2464N`):**
  - **Rebranding Permanen ke `MusEvee` (`AndroidManifest.xml`, `lib/main.dart`, `lib/screens/home_screen.dart`, `lib/widgets/now_playing_view.dart`, `pubspec.yaml`, `.github/workflows/build_apk.yml`):** Menetapkan **`MusEvee`** sebagai nama resmi dan permanen aplikasi di seluruh label sistem Android, header UI (`MusEvee v4.2`), widget `MusEveeApp`, berkas cache (`musevee_*.json` dengan migrasi otomatis dari cache lama), dokumentasi, dan pipeline rilis CI/CD.
  - **Penghapusan, Retag & Pindah Lagu Berlapis di Android 11–15 Scoped Storage (`MainActivity.kt`, `folder_service.dart`, `tagging_service.dart`, `local_music_provider.dart`, `local_library_views.dart`, `now_playing_view.dart`):** Menambahkan metode native `deleteLocalAudioFile`, `writeBytesToMusicFile`, `hasAllFilesAccess`, dan `requestAllFilesAccess` di `MainActivity.kt` yang melepaskan *file lock* `localPlayer` terlebih dahulu, mengeksekusi penghapusan/penulisan via `File` -> `MediaStore` (`ContentUris` `_ID` & `DATA=?`) -> dialog konfirmasi OS `MediaStore.createDeleteRequest` / `MediaStore.createWriteRequest` -> eskalasi `MANAGE_EXTERNAL_STORAGE` (`Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`), serta memverifikasi fisik `!File(path).exists()` sebelum memutakhirkan antrean, cache JSON, cover thumbnail yatim, file pendamping `.lrc`, dan `MediaScannerConnection`.
  - **Mesin Pencarian Lagu Jepang Lintas-Aksara Romaji -> Kanji/Kana (`lib/services/metadata_service.dart`, `test/romaji_service_test.dart`):** Mengembangkan `MetadataService.searchMusicTracks` (`searchTracks`) dengan ekspansi kueri paralel ke **Google Input Tools Japanese IME** (`itc=ja-t-i0-und` frasa utuh + per-kata) dan **Google Translate** (`gtx`), dikombinasikan dengan pencarian paralel `Future.wait` ke **iTunes Search API Japan (`country=JP&lang=ja_jp`)**, **iTunes Global (`country=ID`)**, dan **Deezer API**, lengkap dengan penilaian relevansi lintas-aksara dan penalti cover *orgel/music-box/karaoke* (sehingga pencarian `"heikousen sayuri"` langsung menemukan **`平行線` — `さユり`** di urutan teratas).
  - **Temuan & Perbaikan Live USB Debugging di Perangkat `Z2464N` Android 15 (`MainActivity.kt`, `folder_service.dart`, `local_music_provider.dart`):** Menyaring direktori nada dering sistem bawaan ZTE (`ringtones_music`, `ringtones`, `alarms`, `notifications`, `ui`, `.thumbnails`, filter `IS_MUSIC != 0`) serta stub file rusak `< 16 KB` agar tidak mengotori pustaka/antrean atau memicu error `MetadataRetrieverClient`, serta menambahkan fallback pembacaan & pemeliharaan file pendamping `.lrc` lama (`readCompanionLrcIfPresent` / `deleteCompanionLrcIfPresent`) bagi lagu warisan yang belum memiliki frame biner `USLT`.

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
  - Widget `MusEveeLogo` (`lib/widgets/musevee_logo.dart`) digambar menggunakan `CustomPainter` vektor murni dengan **100% background transparan**.

---

## 3. Arsitektur & Tech Stack

### Struktur Direktori Utama
```text
MusEvee/
├── AGENTS.md                                 # Cetak biru arsitektur MusEvee & SOP wajib AI Agent
├── CHANGELOG.md                              # Rekam jejak kronologis terbalik perkembangan proyek (v1.0 -> v4.2)
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
│           ├── AndroidManifest.xml           # Label permanen "MusEvee", izin audio/penyimpanan/equalizer, & Share Intent
│           └── kotlin/com/example/spotmeta_downloader/
│               └── MainActivity.kt           # MethodChannel native: Local MediaPlayer, ID3v2 APIC/USLT reader, Scoped Storage Delete/Write, Equalizer, 30s Preview, MediaScanner, Share Intent
├── lib/
│   ├── main.dart                             # Entry point MusEveeApp, MultiProvider (LocalMusicProvider + DownloaderProvider), & Dark Musicolet Theme
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
│   │   ├── folder_service.dart               # Manajemen folder (/storage/emulated/0/Music/*), Scoped Storage delete/write, duplicate checker, & MediaScanner
│   │   ├── lyrics_service.dart               # Pencarian kandidat lirik LRCLIB dengan prioritas bahasa asli Jepang/Romaji + fallback lyrics.ovh
│   │   ├── metadata_service.dart             # Ekstraktor link Spotify + Mesin Pencari Lintas-Aksara (Google IME Romaji->Kanji + iTunes JP/Global + Deezer)
│   │   ├── romaji_service.dart               # Konversi Kanji/Kana ke Romaji baris-demi-baris + Anti Double-Romaji & Furigana Deduplication
│   │   └── tagging_service.dart              # Konversi FFmpeg MP3 320kbps, injeksi biner ID3v2.4.0 (APIC + USLT \r\n), & retag instan (-c:a copy)
│   └── widgets/
│       ├── batch_playlist_sheet.dart         # Bottom sheet pemilihan lagu massal dari Album/Playlist Spotify
│       ├── local_library_views.dart          # Tab lokal Musicolet: PlaybackQueueView, LocalFoldersView, LocalAlbumsView, LocalArtistsView, LocalSearchView
│       ├── musevee_logo.dart                 # CustomPainter logo vektor transparan MusEvee
│       ├── musicolet_bottom_strip.dart       # Deretan 8 ikon navigasi bawah khas Musicolet dengan garis indikator putih
│       ├── musicolet_mini_player.dart        # Mini Player tipis ala Musicolet di atas bottom strip
│       ├── now_playing_view.dart             # Layar utama 1:1 Musicolet Now Playing + Embedded Lyrics Ribbon + Tap-to-Seek
│       ├── queue_history_view.dart           # Tab Download Queue & History beserta tombol Putar (▶), Pindah Folder, & Edit Tag Ulang
│       ├── search_result_tile.dart           # Tile hasil pencarian katalog lagu dengan indikator duplikat folder
│       ├── tag_editor_sheet.dart             # Modal editor tag ID3 & lirik (pra-unduh, riwayat unduhan, maupun lagu lokal yang sedang diputar!)
│       └── track_preview_sheet.dart          # Modal detail unduhan: preview 30s, pilih sumber YouTube, Ganti Lirik LRCLIB, Auto-Romaji, & pilih folder
└── test/
    ├── romaji_service_test.dart              # Unit test Romaji, deduplikasi bilingual, prioritas bahasa LyricsService, pencarian lintas-aksara, & parser USLT LocalSong
    └── widget_test.dart                      # Widget test layar NowPlayingView, True Queue-Order Shuffle, & navigasi 8-tab MusEvee
```

### Integrasi Native Android (`MainActivity.kt`)
Menggunakan satu `MethodChannel('com.spotmeta.downloader/system')` terpadu yang di-routing di `HomeScreen`:
1. **Mesin Pemutar Lokal & AudioFocus:** `localPlayFile` (dengan `sessionId`), `localPause`, `localResume`, `localSeekTo`, `localStop`, `getVolume`, `setVolume`, `openEqualizer` (`AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL`), `AudioFocusRequest` (`AUDIOFOCUS_GAIN` + ducking + auto-resume setelah preview 30s), serta event real-time `onLocalPosition`, `onLocalPlayerState`, dan `onLocalTrackCompleted`.
2. **Pemindai Delta Inkremental & Pembaca Streaming Tag `USLT`/`APIC`:** `scanLocalMusicLibraryDelta`, `scanLocalMusicLibrary`, dan `readLocalTrackDetails` memadukan `MediaMetadataRetriever` dengan streaming parser `RandomAccessFile` ID3v2 (`v2.2`/`v2.3`/`v2.4`, melewati frame besar via `raf.seek()`), menyimpan sampul `APIC` permanen ke `filesDir/covers`, menghitung warna dominan Cover Art, dan membaca teks lirik `USLT`.
3. **Scoped Storage Android 11–15 & MediaStore Sync:** `deleteLocalAudioFile`, `writeBytesToMusicFile`, `hasAllFilesAccess`, `requestAllFilesAccess`, `deleteMediaFile`, dan `scanMediaFile` (`MediaScannerConnection.scanFile` + `MediaStore.createDeleteRequest` / `MediaStore.createWriteRequest` + `MANAGE_EXTERNAL_STORAGE`).
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

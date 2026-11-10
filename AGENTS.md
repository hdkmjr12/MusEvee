# MusEvee — Project Context & AI Agent Rules (`AGENTS.md`)

> **MANDATORY WORKFLOW — SETIAP AI AGENT YANG MENGERJAKAN PROYEK INI WAJIB:**
> 1. Membaca `AGENTS.md` dan `CHANGELOG.md` terlebih dahulu sebelum menulis atau mengubah kode apa pun.
> 2. Menjaga 100% fitur Pemutar Lokal bergaya **Musicolet** maupun seluruh layanan **Downloader v3.x** (`MetadataService`, `LyricsService`, `AudioService`, `TaggingService`, `RomajiService`, `FolderService`) agar tidak mengalami regresi.
> 3. Setiap kali selesai memperbaiki bug, mengubah UI, atau menambah fitur baru, **WAJIB** memperbarui bagian **"Status Terkini"** di `AGENTS.md` dan menambahkan entri baru di bagian paling atas `CHANGELOG.md` sebelum melakukan `git commit` / `git push`.

---

## 1. Status Terkini Proyek

- **Nama Resmi & Permanen Aplikasi:** **`MusEvee`** (bukan *MusicEvee* / *SpotMeta Downloader*; `applicationId = "com.zte.as.music"` untuk dukungan native Live Island ZTE/nubia)
- **Versi Aplikasi Saat Ini:** **`MusEvee` `v4.8`** (`pubspec.yaml` version `4.8.0+13`, badge UI `v4.8`)
- **Kondisi Build & CI/CD:** Aktif di `.github/workflows/build_apk.yml` — menghasilkan **1 file APK ringan khusus ARM64 (`~20 MB`, `MusEvee-v4.8-arm64.apk`)** menggunakan `--split-per-abi --target-platform android-arm64`, `packaging.jniLibs.excludes` (`armeabi-v7a`, `x86`, `x86_64`), keystore permanen `android/app/musevee-release.jks`, wrapper Gradle (`gradle-wrapper.jar` + `gradle-9.3.1-bin.zip`) yang di-track langsung di Git bersama Google Cloud Maven Central mirror & HTTP retry hardening, serta publikasi otomatis ke **GitHub Releases (`v4.8.0`)** via `softprops/action-gh-release@v2`.
- **Update Terakhir (`v4.8 — Redesign Phase 1, Phase 1.5, Phase 1.6, Phase 1.7, Phase 1.8 & Phase 1.9`: Bundled Font `Poppins` Seluruh Aplikasi + Progress-Driven 3-Panel `Now Playing` Choreography (`p ∈ [0, 2]`) + Unified Row-Level Lyrics Morph (`p ∈ [0, 1]`, `180 ms` Row-Glide & `±8 px` Hysteresis) + 3-Line Intro Stack `effectiveIdx == -1` dengan Promosi/Demosi `400 ms` + Perlakuan Lirik Polos + Aturan Gestur `Home` Tanpa Seek + Glide Pergantian Baris Panel `Lyrics` `300 ms` + `Bottom Navigation Strip` + Skin `Mini Player`):**
  - **Font Bundled Resmi `Poppins` (`assets/fonts/Poppins-{Regular,Medium,SemiBold,Bold}.ttf`):** Seluruh aplikasi menggunakan keluarga font `Poppins` (`400`/`500`/`600`/`700`) yang di-bundle secara lokal untuk mode offline penuh (`fontFamily: 'Poppins'` pada `ThemeData` gelap & terang di `lib/main.dart`).
  - **Desain Baru `NowPlayingView` dengan Progress-Driven 3-Panel Scene (`p ∈ [0.0, 2.0]`, `lib/widgets/now_playing_view.dart`, `design/now playing redesign*.png`):** Mengganti tampilan `1:1 Musicolet` maupun kartu kaku `PageView` pada halaman Now Playing dengan satu *scene* tunggal berbasis nilai progres kontinu `p ∈ [0.0, 2.0]` (`0.0 = Lyrics`, `1.0 = Home`, `2.0 = Full Disc`, *settle* ke integer terdekat menggunakan `300 ms` `Curves.easeOutCubic` dengan *direction lock* `~10 px`):
    1. **Top Bar Bersih (2 Ikon):** Ikon menu overflow `...` (`assets/icons/dot.png`) di kiri atas dan ikon **Favorite Heart** di kanan atas (merah `#EC504D` saat aktif, outline abu-abu pucat saat nonaktif).
    2. **Zona Tengah — Progress-Driven 3-Panel Choreography (`[0] Lyrics` — `[1] Home` — `[2] Full Disc`), Unified Row-Level Lyrics Morph (`p ∈ [0, 1]`) + Indikator 3 Titik:**
       - **Satu Piringan Sampul Tunggal dengan Framing `Home` Konstan untuk Semua Lagu (`THE DISC`, `computeDiscGeometryForProgress`):** Hanya **satu** instance widget piringan yang ada di sepanjang waktu (tidak pernah di-*unmount* dan tidak pernah mereset sudut `_discAngleRad` / `_discTicker`). Pada `p = 0.0` (`Lyrics`), pusat piringan berada di luar tepi kanan layar lebih dari jari-jarinya (`centerX = screenWidth + radius + 24 px`). Pada `p = 1.0` (`Home`), framing piringan adalah **satu konstanta tetap untuk seluruh lagu** (`discDiameterFactor = 0.95` → `diameter = 0.95 × screenWidth`, `discLeftEdgeFactor = 0.60` → `left = 0.60 × screenWidth`, lubang tengah tepat di luar tepi kanan layar; varian geometri *Wide Lyrics* telah dipensiunkan sepenuhnya sehingga lebar kolom lirik `Home` selalu standar `max(110.0, 0.60 × screenWidth - 26.0 - 14.0)` untuk semua lagu). Pada `p = 2.0` (`Full Disc`), berada tepat di tengah horizontal (`centerX = screenWidth / 2`) dengan diameter penuh (`min(0.95 × screenWidth, zoneHeight - 8)`).
       - **Unified Row-Level Lyrics Morph, `180 ms` Row-Glide, `±8 px` Wrap Hysteresis & Animasi Pergantian Baris `400 ms` Selama Morph (`p ∈ [0.0, 1.0]`, `t = 1.0 - p`):** Menggunakan satu renderer berbasis baris terbungkus (`_buildLyricRowBlock` & `LyricRowMetrics`) untuk status *settled* `Lyrics` (`p = 0.0`), *morph* (`0.0 < p < 1.0`), maupun *settled* `Home` (`p = 1.0`). Setiap baris lirik dipecah menjadi baris-baris terbungkus (`rows`) menggunakan `TextPainter` dan diposisikan secara individual (`computeMorphRowOffsetX`) sehingga baris lanjutan (*continuation row* ke-2 / ke-3) ikut terpusat sempurna pada `t = 1.0` (`(stageWidth - rowWidth) / 2`) dan rata kiri (`0.0`) pada `t = 0.0`. Selama *morph* (`0 < p < 1`), baris tambahan (`|i - centerIdx| > 1`) menargetkan opasitas *Rest mode* (`0.0`) sehingga kedatangan di `p = 0.0` langsung mendarat di *Rest mode* pada frame pertama tanpa kilatan daftar penuh. Dilengkapi *wrap hysteresis* `±8.0 px` (`measureLyricLineWithHysteresis`), animasi *row-glide* `180 ms` (`Curves.easeOutCubic`) saat jumlah baris berubah, *physical pixel snapping* (`snapToPhysicalPixel`), serta **animasi pergantian baris aktif `400 ms` (`Curves.easeOutCubic`) di setiap nilai `p` (`0 < p < 1`)** yang berkomposisi secara simultan dengan `p`, melakukan *retarget* mulus dari state terinterpolasi saat terjadi pergantian baris berturut-turut, dan melakukan *handover* tanpa lompatan (`0.0 px` / `0.0 pt`) saat `p` *settle* ke `0.0` maupun `1.0` di tengah animasi baris.
       - **Tumpukan Intro 3 Baris (`effectiveIdx == -1`) Sebelum Timestamp Lirik Pertama, Promosi (`-1 → 0`), Demosi (`0 → -1`), & Perlakuan Lirik Polos:** Menggunakan `resolveActiveSyncedLyricIndex(entries, positionMs)` (`active = baris terakhir dengan startTime <= positionMs`, atau `-1` jika belum ada). Selama `effectiveIdx == -1`, kolom `Home` (`p = 1.0`) menampilkan **3 baris pertama lagu** mengisi slot atas (`Baris 0`, opasitas `1.0`), tengah (`Baris 1`, opasitas `0.72`), dan bawah (`Baris 2`, opasitas `0.48`) dengan gaya sekunder (`13.5 pt` `Poppins Regular w400`, `palette.nowPlayingSecondary`). Saat timestamp pertama tercapai (`-1 → 0`), seluruh tumpukan meluncur turun satu slot selama `400 ms` (`Curves.easeOutCubic`) sementara Baris `0` membesar ke ukuran/warna aktif di slot tengah, Baris `1` turun ke slot bawah (`0.72 → 1.0`), dan Baris `2` keluar di bawah (`0.48 → 0.0`); *seek* kembali ke sebelum timestamp pertama menjalankan demosi simetris (`0 → -1`, `400 ms`). Lagu berlirik polos (*plain-text / unsynced*) diperlakukan sebagai `effectiveIdx = -1` permanen di `Home` (tumpukan intro 3 baris permanen) dan sebagai daftar rata tengah berseragam `14.5 pt` (`height: 1.2`) dengan guliran murni manual tanpa timer kembali otomatis di panel `Lyrics` (`p = 0.0`).
       - **Transformasi Lirik Romaji Level Dokumen & Cache Metrik Berbasis Teks Tampilan (`LocalMusicProvider.syncedLyricsFor` / `plainLyricLinesFor` & `_computeEntriesTextSignature`):** Konversi Romaji wajib bekerja sebagai **satu transformasi level dokumen** (`_SongLyricsDocumentCache` per lagu + mode di `LocalMusicProvider`) yang menghasilkan satu daftar baris terkonversi tunggal yang dibaca oleh seluruh tampilan (`Home`, `Fluid Morph`, panel `Lyrics`, dan `Full Lyrics` sheet). Seluruh cache metrik baris lirik di `NowPlayingView` (`_ensureSongLyricMetricsCached`, `_ensurePanel0LyricsMetricsCached`, dan `_resolveLineMorphMetricsAndGlide` / `_LineMorphRowState`) wajib menyertakan tanda tangan teks yang ditampilkan (`_computeEntriesTextSignature` / `rawText`) agar metrik Kanji tidak pernah digunakan ulang untuk teks Romaji (maupun sebaliknya) di luar jendela *playhead*.
       - **Panel 0 (`Lyrics` — `p = 0.0`, `design/now playing redesign - 1.png`) dengan Stage Mode (`Rest Mode` 3 Baris vs `Explore Mode` Daftar Penuh) & Glide Pergantian Baris `300 ms` Bebas Tumpang Tindih:** Daftar lirik rata tengah dalam `Poppins Regular (w400)` dengan kerapatan baris `MusEveePalette.lyricLineHeight = 1.2` di seluruh tampilan lirik (baris aktif `22 → 20 → 18`, baris tidak aktif `14.5` via `MusEveePalette.lyricPanelSecondaryFontSize`) yang dapat digulir vertikal saat `p == 0.0` (`_DynamicInitialScrollController`). Beroperasi dalam dua mode visibilitas di atas satu tata letak dokumen tunggal (`top = targetScrollOffset + liveScreenTop[i]`):
         1. **Rest Mode (Default & Saat Tiba melalui Swipe):** Hanya menampilkan 3 baris panggung (`|index - centerIdx| <= 1`, opasitas `1.0` untuk baris tengah aktif dan `0.90` untuk `±1`, atau `0.90`/`0.65` untuk baris `0`/`1` saat `active == -1`); seluruh baris di luar panggung (`|index - centerIdx| > 1`) memiliki opasitas `0.0` dan `IgnorePointer` sambil tetap mereservasi tinggi slotnya (`0.0 px` pergeseran saat berganti mode).
         2. **Explore Mode (Saat Pengguna Menggulir):** Begitu pengguna menggulir/menyeret panel, mode langsung beralih ke *Explore mode* dan menampilkan seluruh daftar lirik dengan tangga opasitas keterbacaan (`0: 1.0`, `±1: 0.90`, `±2: 0.65`, `±3+: 0.45` *hard floor*) serta *top/bottom edge-fade* lembut pada `8%` tinggi atas/bawah panel (`lyricsPanelEdgeFadeHeightFactor = 0.08`). Setelah `4 detik` tanpa sentuhan (menggunakan ulang konstanta tunggal `MusEveePalette.lyricsManualScrollResumeDelaySeconds = 4`), panel kembali ke *Rest mode* dalam **satu gerakan tunggal `300 ms` (`Curves.easeOutCubic`)** yang menggulir panggung kembali ke baris aktif sekaligus memudarkan baris jauh menuju `0.0` (dan langsung dibatalkan di tempat tanpa *snap* jika disentuh di tengah hitung mundur atau di tengah animasi kembali).
         Dipadukan dengan penggerak perjalanan vertikal `_panel0TravelController` (`_onPanel0TravelTick` + `_panel0TravelExtraDyByLine`, `300 ms` `Curves.easeOutCubic`) saat pergantian baris aktif maupun *Tap-to-Seek* di kedua mode (*Rest* dan *Explore*) yang menggerakkan seluruh daftar naik satu langkah penuh dengan **tipografi terkunci sejak frame pertama** (tanpa interpolasi ukuran font kontinu, tanpa *rewrap* di tengah transisi, dan dengan jaminan 0% tumpang tindih baris di setiap frame), menyimpan `_frozenStageScrollOffsetAtDragStart` saat geseran horizontal dimulai dari `p = 0.0` untuk menjaga *handover* `0.0 px` ke *Fluid Morph*, *Tap-to-Seek* khusus di dalam panel `Lyrics` (hanya baris terlihat di *Rest mode*, seluruh baris di *Explore mode*), serta *direction lock* (`~10 px`).
       - **Panel 1 (`Home` — Default awal `p = 1.0`, `design/now playing redesign.png`):** Kolom kiri menampilkan tepat 3 baris lirik yang seluruhnya menggunakan `Poppins Regular (w400)` — baris aktif dibedakan **hanya** melalui ukuran font lebih besar (`22 → 20 → 18`, minimal `18`) dan warna primer (`palette.nowPlayingPrimary`), sedangkan baris tidak aktif (*previous* / *next* atau 3 baris tumpukan intro) menggunakan ukuran `13.5` (`MusEveePalette.lyricSecondaryFontSize`, memberikan rasio kontras default `22.0 / 13.5 ≈ 1.63× >= 1.55×`) dan warna sekunder (`palette.nowPlayingSecondary`) — terkunci di tepi kiri (`leftPad = 26 px`) dengan `CachedLyricLineMetrics` (`w400`). Mengetuk kolom lirik `Home` **tidak pernah** memicu *seek* (`seekTo`), melainkan menganimasikan perpindahan ke panel `Lyrics` (`p → 0.0`).
       - **Panel 2 (`Full Disc` — `p = 2.0`, `design/now playing redesign - 2.png`):** Piringan sampul tunggal meluncur mulus ke tengah layar (`centerX = screenWidth / 2.0`) sementara kolom lirik Home meluncur ke kiri dan memudar keluar.
       - **Indikator 3 Titik (`6 px`):** Terpusat tepat di bawah zona tengah dan di atas judul lagu (`active dot = round(p)`, diperbarui secara *live* selama geseran), serta pilihan panel bertahan lintas pergantian lagu sepanjang sesi.
    3. **Info Lagu (`SemiBold w600`), Seekbar Tipis & Baris Transport 5 Elemen:** Judul lagu terpusat dalam `Poppins SemiBold (w600)` + nama artis `Poppins Regular (w400)` di bawahnya, seekbar tipis `2.5 px` dengan label waktu di bawah ujung kiri-kanan, serta 5 tombol transport (`Shuffle` `assets/icons/arrow.png`, `Prev` mirror `assets/icons/play.png` `26 px`, `Play/Pause` lingkaran penuh `56 px` dengan glyph `26 px`, `Next` `assets/icons/play.png` `26 px`, dan `Repeat/Play Mode` `assets/icons/repeat.png`, seluruhnya memiliki touch target `>= 48×48 px`).
    4. **Menu Overflow `...` Lengkap (3 Grup — 0% Kehilangan Fitur):** Memindahkan seluruh fungsi utilitas lama ke dalam bottom sheet `...` yang terbagi atas grup **Song / File** (*Add to Queue*, *Add to Playlist*, *File Info & Folder Path*, *Open Folder*, *Move to Folder*, *Edit Tags & Lyrics*, *Delete Song File*), **Lyrics** (*Change Lyrics from LRCLIB*, *Auto-Romaji Lyrics & Title*, *Lyrics Font Size*, *Lyrics Auto-Sync*, *Lyrics Mode & Source*), dan **Audio** (*Android System Equalizer*, *Volume & Pre-Amp slider*).
  - **Desain Baru Navigasi Bawah & Skin Mini Player (`lib/widgets/musicolet_bottom_strip.dart`, `lib/widgets/musicolet_mini_player.dart`, `assets/icons/`):** Menggunakan ikon PNG kustom pemilik proyek (`add-to-playlist.png`, segitiga play polos `Icons.play_arrow_rounded` untuk `Now Playing`, `folder.png`, `music-album.png`, `downloading.png` + badge unduhan aktif, dan `settings.png`) tanpa label teks dengan **satu lingkaran indikator aktif `44 px` (`palette.nowPlayingPrimary`)** yang meluncur horizontal (`280 ms`, `Curves.easeOutCubic`) ke belakang tab yang sedang dipilih, serta menyelaraskan skin `MusicoletMiniPlayer` di kedua mode (`Light` & `Dark`) melalui token baru di `MusEveePalette`.
  - **Fitur Sebelumnya (`v4.8` Baseline):** Sentralisasi Token Warna `MusEveePalette` (`ThemeExtension`), Tema Gelap & Terang (`Dark` / `Light Mode`), serta Toggle Tema Persisten di Tab `Settings`.
  - **Fitur Sebelumnya (`v4.7`):** Tab Ke-6 `Settings`, Pilihan Kualitas Unduhan MP3 (`320` / `192` / `128 kbps`) via `SettingsProvider` (`musevee_settings_v1.json`), & Integrasi Pencarian Lokal ke Dalam `All songs` + Shortcut Cepat di Header `Folders` dan `Playlists`.
  - **Fitur Sebelumnya (`v4.6`):** Pembatasan Mix HANYA untuk `Your playlists`, 3 Horizontal Carousels Bersampul Kecil di Downloader (`For You`, `Global Trending`, `Indonesia Trending`), Deteksi Offline Akurat (`NetworkOfflineException`) & Error Banner yang Bisa Ditutup `✕`, Lokalisasi Otomatis Sistem `id`/`en` (`AppStrings`), serta Optimasi Data Pengguna `< 5 MB` + On-Demand USLT Lyrics.
  - **Fitur Sebelumnya (`v4.5`):** Context-Aware & Rotated Queue (`index 0` / `#1`), 6 Musicolet Smart Playlists + `Your playlists`, Fix Duplikasi Aplikasi di Recent Apps (`singleTask`), & Interactive Folder Explorer pada Downloader.
  - **Fitur Sebelumnya (`v4.4`):** Navigasi Bawah 6 Tab + Sliding Pill Indicator + Modal Bottom Sheet Antrean Unduhan `88%`, Mograph Motion & Liquid Shape Morphing (`_MorphingMergeActionBar`, `MographPlayPauseIcon`, Dynamic Artwork Scale), Multi-Folder & Multi-Playlist Queue Merger, Hi-Fi Unattenuated Audio Engine (`1.0` Volume) + Pre-Amp `LoudnessEnhancer`, serta sistem Draft + tombol **Terapkan** di Kelola Folder.
  - **Fitur Sebelumnya (`v4.3` & `v4.2`):** Universal Audio Folder Scanner + Strict Anti-Junk Filter (`>= 15s` / `>= 50 KB`, blacklist folder non-musik), fitur **"Kelola / Sembunyikan Folder"** (`musevee_hidden_folders_v1.json`), Smart Default Folders, First-Run Permission Onboarding & Info Dialog Live Island, perbaikan ekstraksi Playlist Spotify Private + dukungan token `?pt=`, logo transparan `assets/musevee_logo.png`, Native `MediaSession` Notification + ZTE/nubia Live Island Support (`applicationId = "com.zte.as.music"`), Scoped Storage Android 15, & Cross-Script Romaji J-Pop Search.

---

## 2. Identitas & Prinsip Desain (`MusEvee` — Redesign Phase 1 pada Now Playing & Navigasi + Musicolet UI pada Tab Lainnya)

- **Nama Resmi & Permanen Aplikasi:** `MusEvee` (tanpa huruf *"ic"*).
- **Aturan Desain per Area (Phase 1 Redesign):**
  - **Aturan `"1:1 Musicolet"` DIPENSIUNKAN khusus untuk `Now Playing` + `Bottom Navigation Strip` (+ skin `Mini Player`)**: Bagian ini kini menggunakan desain minimalis kustom pemilik proyek (`design/now playing redesign.png`) — latar bersih dengan ruang kosong lega (`nowPlayingBg`: `#FFFFFF` pada mode terang, `#0E1014` pada mode gelap), tipografi lirik 3 baris sebagai elemen utama di sisi kiri, piringan sampul besar berputar di sisi kanan (`0.95 × lebar layar`, `1 putaran / 25 detik`), teks aktif hitam/terang tebal (`nowPlayingPrimary`), elemen sekunder abu-abu pucat (`nowPlayingSecondary` / `nowPlayingInactiveIcon`), warna merah (`#EC504D`, `favoriteActive`) **hanya** untuk ikon favorit aktif, serta ikon PNG monokrom dari `assets/icons/`.
  - **Tab Lainnya (`Queue`, `Folders`, `Playlists`, `Downloader`, `Settings`) tetap mempertahankan aturan tampilan Musicolet sebelumnya** hingga fase desain ulang berikutnya.
  - **Palet Warna Terpusat (`MusEveePalette.dark` & `MusEveePalette.light` di `lib/theme/musevee_palette.dart`):**
    | Token (`MusEveePalette`) | Mode Gelap (`dark` — Default) | Mode Terang (`light`) |
    | :--- | :--- | :--- |
    | `bgCanvas` / `nowPlayingBg` | `#0E1014` / `#0E1014` | `#F6F7F9` / `#FFFFFF` |
    | `bottomBar` / `surfaceCard` | `#0A0C10` / `#17191E` | `#FFFFFF` / `#FFFFFF` |
    | `surfaceSubtle` | `#22252D` | `#ECEEF1` |
    | `accent` | `#3898EC` | `#1D74C6` |
    | `textPrimary` / `nowPlayingPrimary` | `#F2F4F7` / `#F2F4F7` | `#181A1F` / `#000000` |
    | `textMuted` / `nowPlayingSecondary` | `#98A2B3` / `#8A93A2` | `#667085` / `#88888D` |
    | `nowPlayingInactiveIcon` | `#4C5361` | `#D0D0D5` |
    | `seekbarInactive` / `discRingBorder` | `#262A34` / `#282D38` | `#E4E4E8` / `#DADADE` |
    | `favoriteActive` | `#EC504D` | `#EC504D` |
    | `hairline` | `Colors.white` alpha `0.09` (`#17FFFFFF`) | `Colors.black` alpha `0.09` (`#17000000`) |
    | `appBar` | `#12151C` | `#FFFFFF` |
  - **Warna Semantik & Garis Batas (`Hairline Border`):**
    - Semantik: `emerald` (`#10B981`), `amber` (`#F59E0B`), `error` (`#F04438`), `snackBarBg` (`#1F242F`).
    - Border tipis `0.7px–0.8px` (`context.palette.hairline`).
- **Logo & Ikon:**
  - Widget `MusEveeLogo` (`lib/widgets/musevee_logo.dart`) memuat aset `assets/musevee_logo.png` berlatar **100% transparan**, dan ikon navigasi/kontrol Now Playing memuat PNG transparan dari `assets/icons/`.

---

## 3. Arsitektur & Tech Stack

### Struktur Direktori Utama
```text
MusEvee/
├── AGENTS.md                                 # Cetak biru arsitektur MusEvee & SOP wajib AI Agent
├── CHANGELOG.md                              # Rekam jejak kronologis terbalik perkembangan proyek (v1.0 -> v4.8)
├── .github/
│   ├── copilot-instructions.md               # Instruksi otomatis GitHub Copilot / Remote Agent
│   └── workflows/
│       └── build_apk.yml                     # CI/CD otomatis build APK ARM64 (~20 MB) & GitHub Release (MusEvee-v4.8-arm64.apk)
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
│   ├── main.dart                             # Entry point MusEveeApp, MultiProvider (LocalMusicProvider + SettingsProvider + DownloaderProvider), & Dark/Light Musicolet Theme
│   ├── models/
│   │   ├── download_item.dart                # Model item antrean & riwayat unduhan FFmpeg (+ targetPlaylistId)
│   │   ├── local_playlist.dart               # Model playlist lokal (`musicevee_playlists_v1.json`)
│   │   ├── local_song.dart                   # Model lagu lokal (+ folderPath) + parser LRC [mm:ss.xx] SyncedLyricEntry & jembatan ke TrackMetadata
│   │   └── track_metadata.dart               # Model metadata unduhan, normalisasi identitas lintas-aksara, & pemilih payload USLT
│   ├── providers/
│   │   ├── downloader_provider.dart          # State management Downloader (pencarian katalog, lirik, Romaji, antrean unduh, kualitas bitrate, Smart Deduplication, playlist sync)
│   │   ├── local_music_provider.dart         # State management Pemutar Lokal Musicolet (library scan, hidden folders, permission status, queue, Multi-Folder/Playlist Queue Merger, playlists CRUD, play mode 1→, sync lirik, retag/pindah/hapus lokal)
│   │   └── settings_provider.dart            # State management Pengaturan (`musevee_settings_v1.json`, `ThemeMode`: dark/light & `DownloadQuality`: 320 / 192 / 128 kbps)
│   ├── screens/
│   │   └── home_screen.dart                  # Shell utama 6-Tab Musicolet + Permission Onboarding Banner + Info/Live Island Dialog + Smart Omnibox Downloader + Modal Sheet Antrean Unduhan (88%)
│   ├── services/
│   │   ├── audio_service.dart                # Ekstraktor stream YouTube (YoutubeExplode multi-client) & 5 kandidat manual
│   │   ├── folder_service.dart               # Manajemen folder (/storage/emulated/0/Music/*), Scoped Storage delete/write, permission checks, cross-folder duplicate checker, & MediaScanner
│   │   ├── lyrics_service.dart               # Pencarian kandidat lirik LRCLIB dengan prioritas bahasa asli Jepang/Romaji + fallback lyrics.ovh
│   │   ├── metadata_service.dart             # Ekstraktor link Spotify + Mesin Pencari Lintas-Aksara (Google IME Romaji->Kanji + iTunes JP/Global + Deezer)
│   │   ├── romaji_service.dart               # Konversi Kanji/Kana ke Romaji baris-demi-baris + Anti Double-Romaji & Furigana Deduplication
│   │   └── tagging_service.dart              # Konversi FFmpeg MP3 dengan bitrate dapat diatur (320/192/128kbps), injeksi biner ID3v2.4.0 (APIC + USLT \r\n), & retag instan (-c:a copy)
│   ├── theme/
│   │   └── musevee_palette.dart              # ThemeExtension MusEveePalette (dark & light tokens, semantic colors, context.palette & context.isDarkMode)
│   ├── utils/
│   │   └── app_strings.dart                  # Lokalisasi otomatis sesuai bahasa sistem perangkat (Bahasa Indonesia `id`/`in` vs English `en`)
│   └── widgets/
│       ├── batch_playlist_sheet.dart         # Bottom sheet pemilihan lagu massal dari Album/Playlist Spotify + auto-sync playlist lokal
│       ├── local_library_views.dart          # Tab lokal Musicolet: PlaybackQueueView, LocalFoldersView (+ Kelola/Sembunyikan Folder, Multi-Folder Merger & shortcut Search), LocalPlaylistsView (+ All songs Search Bar & Your playlists Merger)
│       ├── musevee_logo.dart                 # Widget logo transparan MusEvee (`assets/musevee_logo.png`)
│       ├── musicolet_bottom_strip.dart       # Deretan 6 ikon navigasi bawah khas Musicolet dengan Sliding Pill Indicator (`AnimatedPositioned` 240ms)
│       ├── musicolet_mini_player.dart        # Mini Player tipis ala Musicolet di atas bottom strip
│       ├── now_playing_view.dart             # Layar utama 1:1 Musicolet Now Playing + Embedded Lyrics Ribbon + Tap-to-Seek
│       ├── pressable_scale.dart              # Micro-animations: PressableScale (0.95 scale 100ms), AnimatedIndexedStack (Slide+Fade 200ms), & AnimatedEqualizerIcon (4 batang hidup)
│       ├── queue_history_view.dart           # View Antrean & Riwayat Unduhan beserta tombol Putar (▶), Pindah Folder, & Edit Tag Ulang
│       ├── search_result_tile.dart           # Tile hasil pencarian katalog lagu dengan indikator duplikat folder
│       ├── settings_view.dart                # Tab Pengaturan (Settings): pemilih tema Gelap/Terang, pilihan kualitas ukuran file unduhan MP3 (320 / 192 / 128 kbps) & info versi
│       ├── tag_editor_sheet.dart             # Modal editor tag ID3 & lirik (pra-unduh, riwayat unduhan, maupun lagu lokal yang sedang diputar!)
│       └── track_preview_sheet.dart          # Modal detail unduhan: preview 30s, pilih sumber YouTube, Ganti Lirik LRCLIB, Auto-Romaji, & pilih folder
└── test/
    ├── romaji_service_test.dart              # Unit test Romaji, deduplikasi bilingual, prioritas bahasa LyricsService, pencarian lintas-aksara, & parser USLT LocalSong
    ├── settings_provider_test.dart           # Unit & widget test SettingsProvider (`musevee_settings_v1.json`), ThemeMode Dark/Light, kualitas bitrate DownloaderProvider, & SettingsView
    └── widget_test.dart                      # Widget test layar NowPlayingView, True Queue-Order Shuffle, Multi-Folder Queue Merger, All songs Search, & navigasi 6-tab MusEvee (Dark & Light Mode)
```

### Integrasi Native Android (`MainActivity.kt`)
Menggunakan satu `MethodChannel('com.spotmeta.downloader/system')` terpadu yang di-routing di `HomeScreen`:
1. **Mesin Pemutar Lokal & AudioFocus:** `localPlayFile` (dengan `sessionId`), `localPause`, `localResume`, `localSeekTo`, `localStop`, `getVolume`, `setVolume`, `openEqualizer` (`AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL`), `AudioFocusRequest` (`AUDIOFOCUS_GAIN` + ducking + auto-resume setelah preview 30s), serta event real-time `onLocalPosition`, `onLocalPlayerState`, dan `onLocalTrackCompleted`.
2. **Pemindai Universal Delta Inkremental & Pembaca Streaming Tag `USLT`/`APIC`:** `scanLocalMusicLibraryDelta`, `scanLocalMusicLibrary`, dan `readLocalTrackDetails` memindai seluruh folder musik di penyimpanan internal/eksternal dengan filter anti-sampah ketat (`>= 15s` atau `>= 50 KB`, blacklist folder non-musik), memadukan `MediaMetadataRetriever` dengan streaming parser `RandomAccessFile` ID3v2 (`v2.2`/`v2.3`/`v2.4`, melewati frame besar via `raf.seek()`), menyimpan sampul `APIC` permanen ke `filesDir/covers`, menghitung warna dominan Cover Art, dan membaca teks lirik `USLT`.
3. **Scoped Storage Android 11–15, Permission Onboarding & MediaStore Sync:** `deleteLocalAudioFile`, `writeBytesToMusicFile`, `hasAllFilesAccess`, `requestAllFilesAccess`, `hasNotificationPermission`, `requestNotificationPermission`, `openNotificationSettings`, `getPermissionsStatus`, `deleteMediaFile`, dan `scanMediaFile` (`MediaScannerConnection.scanFile` + `MediaStore.createDeleteRequest` / `MediaStore.createWriteRequest` + `MANAGE_EXTERNAL_STORAGE`).
4. **Share Intent & 30s Preview Downloader:** `getInitialSharedText` / `onSharedText` serta `playPreviewUrl` / `stopPreview` / `onPreviewStateChanged` (otomatis menjeda lagu lokal saat memutar preview 30 detik agar suara tidak bertabrakan).

---

## 4. Daftar Fitur Inti yang Wajib Dijaga (Anti-Regresi)

1. **Redesigned Now Playing, Progress-Driven 3-Panel Scene (`p ∈ [0, 2]`), 3-Line Lyrics, Single Rotating Disc & `...` Menu (`NowPlayingView` & `LocalMusicProvider`):**
   - Top bar 2 ikon (`...` & Favorite Heart merah `#EC504D`), scene 3-panel berbasis progres kontinu `p ∈ [0.0, 2.0]` (`0 = Lyrics`, `1 = Home`, `2 = Full Disc`), seluruh lirik menggunakan `Poppins Regular (w400)` (baris aktif dibedakan hanya melalui ukuran font `19 → 17 → 15` dan warna primer `palette.nowPlayingPrimary`), judul lagu `Poppins SemiBold (w600)`, satu instance piringan sampul tunggal yang meluncur mulus antar panel (`25s` per putaran, *spin-down* `0.8s` saat jeda, *stop ticker* saat pindah tab/background), seekbar tipis `2.5px` dengan waktu di bawah ujungnya, 5 tombol transport (`Shuffle`, `Prev`, lingkaran `Play/Pause` `56px`, `Next`, `Repeat/Play Mode`), serta menu `...` lengkap 3 grup (*Song/File*, *Lyrics*, *Audio*).
2. **6-Tab Custom Icon Bottom Strip + Mini Player (`MusicoletBottomStrip` & `MusicoletMiniPlayer`):**
   - Tab `Queue`, `Now Playing` (lingkaran hitam/terang aktif dengan ikon play kontras), `Folders` (+ Kelola/Sembunyikan Folder, Multi-Folder Queue Merger, & tombol shortcut Search Lokal), `Playlists` (`musicevee_playlists_v1.json`, 6 Smart Playlists termasuk `All songs` dengan bar pencarian lokal permanen + filter Favorit `♥` di bagian atas, `Your playlists` Multi-Playlist Queue Merger, & tombol shortcut Search Lokal), `Downloader` (+ badge unduhan aktif & tombol kompak Modal Sheet Antrean & Riwayat Unduhan `88%`), dan `Settings` (`SettingsView` + `SettingsProvider` `musevee_settings_v1.json`).
3. **100% Fitur All-in-One Downloader v3.x (`DownloaderProvider` & Services):**
   - Smart Omnibox (Deezer + iTunes + Link Spotify Track/Album/Playlist), chip folder tujuan (`Music Barat`, `Music Japan`, `Music Random`, atau `MusEvee` + `+ Baru`), deteksi duplikat lintas folder, Preview Audio 30s, Pemilih Sumber YouTube manual, `BatchPlaylistSheet`, Pindah Folder 1-klik, konversi FFmpeg MP3 dengan kualitas bitrate yang dapat diatur (`320` / `192` / `128 kbps`, default `320 kbps` via `SettingsProvider`), dan Retag MP3 instan (`-c:a copy` + biner ID3v2.4.0 `APIC` & `USLT` `\r\n` tanpa file `.lrc` eksternal).
4. **Anti Double-Romaji & Prioritas Bahasa Asli (`RomajiService` & `LyricsService`):**
   - Isolasi timestamp `[mm:ss.xx]` baris-demi-baris, normalisasi makron (`ū`/`ō`) & deduplikasi baris kembar bilingual/Romaji, penghapusan furigana inline, prioritas skor lirik Jepang/Romaji di atas terjemahan Inggris pada LRCLIB, serta pemilih manual **"Ganti Lirik"** di `NowPlayingView`, `TrackPreviewSheet`, dan `TagEditorSheet`.
5. **Build APK Ringan ARM64 (~20 MB) & Keystore Permanen (`.github/workflows/build_apk.yml`):**
   - Selalu gunakan `--split-per-abi --target-platform android-arm64`, `android/app/musevee-release.jks`, dan publikasi otomatis ke GitHub Releases.

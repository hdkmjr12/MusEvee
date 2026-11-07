# MusEvee — Project Context & AI Agent Rules (`AGENTS.md`)

> **MANDATORY WORKFLOW — SETIAP AI AGENT YANG MENGERJAKAN PROYEK INI WAJIB:**
> 1. Membaca `AGENTS.md` dan `CHANGELOG.md` terlebih dahulu sebelum menulis atau mengubah kode.
> 2. Menjaga seluruh fitur dan gaya desain yang tercatat di `AGENTS.md` agar tidak mengalami regresi.
> 3. Setiap kali selesai memperbaiki bug, mengubah UI, atau menambah fitur baru, **WAJIB** memperbarui bagian **"Status Terkini"** di `AGENTS.md` dan menambahkan entri baru di bagian paling atas `CHANGELOG.md` sebelum melakukan `git commit` / `git push`.

---

## 1. Status Terkini Proyek

- **Versi Aplikasi Saat Ini:** `v3.0.1` (`pubspec.yaml` version `1.2.0+3`, badge UI `v1.2`)
- **Kondisi Build & CI/CD:** Aktif di `.github/workflows/build_apk.yml` — hanya menghasilkan **1 file APK ringan khusus ARM64 (`~20.1 MB`)** menggunakan `--split-per-abi --target-platform android-arm64`, `packaging.jniLibs.excludes` (`armeabi-v7a`, `x86`, `x86_64`), dan keystore permanen `android/app/musevee-release.jks`.
- **Update Terakhir (`v3.0.1`):**
  - Perbaikan menyeluruh `RomajiService` (`lib/services/romaji_service.dart`): isolasi timestamp `[mm:ss.xx]` baris-demi-baris (`ParsedLyricLine`), konversi Kanji+Kana per segmen secara paralel via endpoint `dt=rm` tanpa menggabungkan baris dan tanpa merusak teks bahasa Inggris di dalam kurung, serta sinkronisasi otomatis `syncedLyrics` dan `plainLyrics`.
  - Penambahan pembersihan otomatis file MP3 duplikat lama di disk & `MediaStore` Android (`deleteMediaFile` di `MainActivity.kt`, `folder_service.dart`, dan `tagging_service.dart`) serta penguncian keystore rilis permanen (`android/app/musevee-release.jks`).

---

## 2. Identitas & Prinsip Desain (`MusEvee`)

- **Nama Aplikasi:** `MusEvee` (sebelumnya `SpotMeta Downloader`).
- **Gaya Visual:** *Modern Architectural UI* (terinspirasi dari `dhaauu.web.id` serta kedalaman permukaan ala Linear/Vercel):
  - **Radius Sudut (`BorderRadius`):** Tegas dan presisi di rentang `6px–10px` (kartu utama `10px`, tombol/chip/input `6px–8px`, modal bottom sheet top radius `16px`). Jangan gunakan bentuk *pill* bulat penuh (`999px`) yang berlebihan.
  - **Garis Batas (`Hairline Border`):** Border tipis `0.8px` dengan warna `Colors.black.withValues(alpha: 0.07)` tanpa bayangan (*box-shadow*) tebal yang kabur.
  - **Palet Warna Clean (`Light Architectural Palette`):**
    - Background Canvas: `#F8FAFC`
    - Surface Card: `#FFFFFF`
    - Surface Subtle / Input Fill: `#F2F4F7`
    - Primary Accent Blue: `#1677B8`
    - Text Primary Dark: `#15181E`
    - Text Muted: `#68717C`
    - Status Dots: Emerald `#12B76A` (tersedia/selesai), Amber `#F79009` (duplikat), Red `#D92D20` (error/hapus).
- **Logo & Ikon:**
  - Widget `MusEveeLogo` (`lib/widgets/musevee_logo.dart`) digambar menggunakan `CustomPainter` vektor murni dengan **100% background transparan** tanpa kotak latar atau border pembungkus.
  - Launcher icon Android (`mipmap-*/ic_launcher.png`) menggunakan aset PNG transparan tanpa adaptive icon background (`mipmap-anydpi-v26` dihapus).
- **Copywriting UI:**
  - Gunakan bahasa Indonesia yang ringkas, natural, dan **bebas jargon teknis** (contoh: gunakan *"Lirik Berjalan"* alih-alih *"Synced LRC USLT"*, *"Lirik Biasa"* alih-alih *"Plain Unsynced Lyrics"*, *"Simpan"* / *"Unduh Lagu"* alih-alih istilah teknis FFmpeg/ID3v2.4).

---

## 3. Arsitektur & Tech Stack

### Struktur Direktori Utama
```text
MusEvee/
├── AGENTS.md                                 # Cetak biru konteks proyek & SOP wajib AI Agent
├── CHANGELOG.md                              # Rekam jejak kronologis terbalik perkembangan proyek
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
│           ├── AndroidManifest.xml           # Izin penyimpanan, internet, dan intent-filter ACTION_SEND
│           └── kotlin/com/example/spotmeta_downloader/
│               └── MainActivity.kt           # MethodChannel native: scanMediaFile, deleteMediaFile, Share Intent, & 30s Audio Preview
├── lib/
│   ├── main.dart                             # Entry point aplikasi, tema Modern Architectural UI, & ChangeNotifierProvider
│   ├── models/
│   │   ├── download_item.dart                # Model item antrean & riwayat unduhan (status, progress, preferSyncedLyrics)
│   │   └── track_metadata.dart               # Model metadata lagu, normalisasi lirik (\r\n), & pemilih payload USLT
│   ├── providers/
│   │   └── downloader_provider.dart          # State management utama (MVVM): pencarian, lirik, Romaji, antrean, & retag
│   ├── screens/
│   │   └── home_screen.dart                  # Layar utama 2-Tab (Cari & Unduh | Antrean & Riwayat) + Smart Omnibox
│   ├── services/
│   │   ├── audio_service.dart                # Ekstraktor stream YouTube (YoutubeExplode multi-client) & 5 kandidat manual
│   │   ├── folder_service.dart               # Manajemen folder (/storage/emulated/0/Music/*), duplicate checker, & MediaScanner
│   │   ├── lyrics_service.dart               # Pencarian lirik LRCLIB (/api/get & /api/search) + fallback lyrics.ovh
│   │   ├── metadata_service.dart             # Ekstraktor link Spotify (oEmbed/OpenGraph Track/Album/Playlist) & pencarian Deezer+iTunes
│   │   ├── romaji_service.dart               # Konversi Kanji/Kana Jepang ke Romaji (line-by-line timestamp isolation & dt=rm API)
│   │   └── tagging_service.dart              # Konversi FFmpeg MP3 320kbps, injeksi biner ID3v2.4.0 (APIC + USLT), & retag instan (-c:a copy)
│   └── widgets/
│       ├── batch_playlist_sheet.dart         # Bottom sheet pemilihan lagu massal dari Album/Playlist Spotify
│       ├── musevee_logo.dart                 # CustomPainter logo vektor transparan MusEvee
│       ├── queue_history_view.dart           # Tampilan tab Antrean & Riwayat beserta aksi Pindah Folder & Edit Tag Ulang
│       ├── search_result_tile.dart           # Tile hasil pencarian lagu dengan indikator duplikat folder & tombol unduh cepat
│       ├── tag_editor_sheet.dart             # Modal editor metadata & lirik (sebelum unduh maupun retag file lokal) + tombol Auto-Romaji
│       └── track_preview_sheet.dart          # Modal utama detail lagu: preview 30s, pilih sumber YouTube, toggle Lirik Berjalan/Biasa, Auto-Romaji, & pilih folder
└── test/
    ├── romaji_service_test.dart              # Unit test parser baris-demi-baris [mm:ss.xx] & konversi Kanji-ke-Romaji
    └── widget_test.dart                      # Smoke test komponen utama HomeScreen MusEvee
```

### Integrasi Native Android (`MainActivity.kt`)
Menggunakan `MethodChannel('com.spotmeta.downloader/system')` untuk 4 jembatan utama:
1. `scanMediaFile`: Memanggil `MediaScannerConnection.scanFile` setiap kali MP3 selesai dibuat, di-retag, atau dipindahkan agar langsung terbaca oleh **Musicolet** dalam <1 detik.
2. `deleteMediaFile`: Menghapus file MP3 duplikat lama dari sistem file sekaligus dari database `MediaStore.Audio.Media.EXTERNAL_CONTENT_URI` sebelum menulis file baru.
3. `getInitialSharedText` & callback `onSharedText`: Menangkap link Spotify yang dibagikan (*Share*) dari aplikasi eksternal.
4. `playPreviewUrl`, `stopPreview`, `isPreviewPlaying` & callback `onPreviewStateChanged`: Memutar cuplikan audio 30 detik secara native menggunakan Android `MediaPlayer`.

---

## 4. Daftar Fitur Inti yang Wajib Dijaga (Anti-Regresi)

1. **Smart Omnibox (`HomeScreen` & `MetadataService`):**
   - Satu kolom input yang otomatis mendeteksi apakah pengguna memasukkan:
     - Kata kunci pencarian lagu biasa (menggabungkan katalog **Deezer API** + **iTunes Search API** lengkap dengan Cover Art 1000×1000 dan Tahun Rilis).
     - Link **Spotify Track** (`open.spotify.com/track/...` atau `spotify.link/...`).
     - Link **Spotify Album / Playlist** (`open.spotify.com/album/...` atau `/playlist/...`) yang membuka `BatchPlaylistSheet`.
2. **Folder Selector & Cross-Folder Duplicate Checker (`FolderService`):**
   - Menyediakan 3 folder utama di `/storage/emulated/0/Music/`: `Music Barat`, `Music Japan`, dan `Music Random`, ditambah pemindaian otomatis subfolder lain serta pembuatan folder baru (`+ Folder`).
   - Mengecek secara lintas folder apakah file `{Artist} - {Title}.mp3` sudah pernah diunduh dan menampilkan indikator `Sudah ada di {Nama Folder}`.
3. **Pemilih Sumber Audio YouTube Manual & Preview Audio 30 Detik (`AudioService` & `TrackPreviewSheet`):**
   - Tombol play/stop di atas sampul album untuk memutar cuplikan lagu 30 detik dari Deezer/iTunes.
   - Panel **"Sumber Audio"** yang memungkinkan pengguna melihat dan memilih secara manual dari 5 kandidat video YouTube teratas jika ingin mengganti sumber audio default.
4. **Engine Lirik LRCLIB, Toggle USLT Musicolet, & Auto-Romaji (`LyricsService`, `RomajiService`, `TaggingService`):**
   - Mengambil `syncedLyrics` (`[mm:ss.xx]`) dan `plainLyrics` dari LRCLIB.
   - Toggle **Lirik Berjalan** vs **Lirik Biasa**: Keduanya disuntikkan langsung ke dalam frame biner **`USLT` ID3v2.4.0** ber-encoding UTF-8 dengan pemisah baris `\r\n` di dalam file `.mp3` (**tanpa** membuat file `.lrc` eksternal) sehingga langsung kompatibel dengan fitur *Embedded Synced Lyrics* di **Musicolet**.
   - **Auto-Romaji (`RomajiService`):**
     - Mengonversi Judul, Artis, dan Album berhuruf Jepang ke Romaji (memanfaatkan pencocokan katalog iTunes US + transliterasi morfologi).
     - Mengonversi lirik Jepang (Kanji, Hiragana, Katakana) ke Romaji **secara baris-demi-baris** menggunakan isolasi Regex `^((?:\[\d{2}:\d{2}(?:\.\d{1,3})?\])+)(.*)$` dan endpoint `translate.googleapis.com/...&dt=rm` per segmen Jepang sehingga timestamp `[mm:ss.xx]` tidak pernah hilang, baris tidak pernah menyatu menjadi satu paragraf, dan teks bahasa Inggris di dalam kurung tetap utuh.
     - Menyinkronkan `syncedLyrics` dan `plainLyrics` sekaligus (menurunkan `plainLyrics` via `RomajiService.stripTimestamps` tanpa memanggil API dua kali).
5. **Tag & Lyrics Editor + Retag MP3 Instan (`TagEditorSheet` & `TaggingService.retagExistingMp3`):**
   - Pengguna dapat mengedit Judul, Artis, Album, Tahun, dan Lirik (termasuk menekan tombol **Auto-Romaji** / **Lirik ke Romaji**) baik **sebelum mengunduh** maupun **setelah lagu selesai diunduh** lewat tab *Antrean & Riwayat*.
   - Fitur edit pada lagu yang sudah terunduh menggunakan penyalinan stream instan (`-c:a copy`) dan penulisan ulang header biner ID3v2.4.0 tanpa mengunduh atau meng-encode ulang audio.
6. **Build APK Ringan ARM64 (~20 MB) di GitHub Actions (`.github/workflows/build_apk.yml`):**
   - Workflow CI/CD hanya mem-build target `android-arm64` dengan `--split-per-abi` dan membuang pustaka native arsitektur lain (`armeabi-v7a`, `x86`, `x86_64`) agar ukuran APK selalu ringan (~20.1 MB) dan otomatis terbit di GitHub Releases.

# Changelog — MusEvee

Seluruh riwayat perubahan penting pada proyek **MusEvee** (sebelumnya *SpotMeta Downloader*) dicatat di dokumen ini secara kronologis terbalik (versi terbaru berada di paling atas).

> **Catatan untuk AI Agent:** Setiap kali Anda menyelesaikan perbaikan bug, perubahan UI, atau penambahan fitur baru, Anda **wajib** menambahkan entri baru di bagian paling atas file ini dan memperbarui bagian *Status Terkini* di `AGENTS.md` sebelum melakukan commit/push.

---

## [v3.0.1] — 2026-11-07 (Romaji Timestamp Alignment Fix, Anti-Duplicate MediaStore & Lightweight APK)

### Diperbaiki (Fixed)
- **Isolasi Timestamp `[mm:ss.xx]` & Pemrosesan Baris-demi-Baris pada `RomajiService` (`lib/services/romaji_service.dart`):**
  - Memperbaiki bug kritis di mana pengiriman seluruh lirik sekaligus ke endpoint `dt=rm` menyebabkan seluruh baris menyatu menjadi satu paragraf raksasa di baris pertama dan membuat baris berikutnya jatuh ke konverter Kana lokal yang membocorkan karakter Kanji (`誰mo教etekurenakatta`).
  - Menambahkan model `ParsedLyricLine` dan metode `RomajiService.parseLyricLine` dengan Regex `^((?:\[\d{2}:\d{2}(?:\.\d{1,3})?\])+)(.*)$` untuk memisahkan `timestampPrefix` dan `lyricContent` secara ketat di setiap baris (`split('\n')`).
  - Mengekstrak segmen huruf Jepang per baris menggunakan `_japaneseSegmentRegex` dan mengonversinya secara paralel (`Future.wait` per batch 8 segmen + mekanisme *retry* 3x ke endpoint `translate.googleapis.com/translate_a/single?client=gtx&sl=ja&tl=en&dt=rm`), sehingga teks bahasa Inggris di dalam kurung seperti `(Go to the outside of daydream)` atau `(Break your limits)` tetap utuh dan jumlah baris serta urutan timestamp 100% identik dengan lirik asli.
- **Sinkronisasi State `syncedLyrics` & `plainLyrics` (`lib/providers/downloader_provider.dart`, `lib/widgets/track_preview_sheet.dart`, `lib/widgets/tag_editor_sheet.dart`):**
  - Menambahkan metode `autoRomanizeCurrentLyrics()` di `DownloaderProvider` dan tombol **✨ Auto-Romaji** langsung pada kartu lirik di `TrackPreviewSheet` (selain tombol di header kartu lagu dan di dalam `TagEditorSheet`).
  - Saat lagu memiliki `syncedLyrics`, konversi Romaji dilakukan pada `syncedLyrics` dengan mempertahankan timestamp `[mm:ss.xx]`, lalu `plainLyrics` diturunkan langsung melalui `RomajiService.stripTimestamps()` tanpa memanggil API dua kali dan menjaga mode **Lirik Berjalan** tetap aktif.
- **Pembersihan Duplikat File MP3 Lama di Disk & Android MediaStore (`android/app/src/main/kotlin/com/example/spotmeta_downloader/MainActivity.kt`, `lib/services/folder_service.dart`, `lib/services/tagging_service.dart`):**
  - Menambahkan handler native `deleteMediaFile` di `MainActivity.kt` dan `FolderService.deleteMediaFile()` untuk menghapus file MP3 lama baik dari penyimpanan fisik maupun dari database `MediaStore.Audio.Media.EXTERNAL_CONTENT_URI` sebelum menulis ulang file baru, mencegah Musicolet memutar file lama yang masih tersimpan di cache.
  - Mengaktifkan permintaan izin runtime `Permission.audio`, `Permission.storage`, dan `Permission.manageExternalStorage` di `TaggingService.requestStoragePermissions()`.
- **Konsistensi Tanda Tangan APK & Ukuran Ringan ~20 MB (`android/app/build.gradle.kts`, `android/app/musevee-release.jks`, `.github/workflows/build_apk.yml`, `pubspec.yaml`, `lib/screens/home_screen.dart`):**
  - Menambahkan keystore permanen `android/app/musevee-release.jks` agar setiap APK hasil build GitHub Actions memiliki sertifikat tanda tangan yang konsisten dan dapat langsung di-update di Android tanpa konflik paket.
  - Mengunci build rilis pada `--split-per-abi --target-platform android-arm64` serta `packaging.jniLibs.excludes` (`**/armeabi-v7a/**`, `**/x86/**`, `**/x86_64/**`) sehingga hanya menghasilkan 1 file APK ringan (`~20.1 MB`).
  - Menampilkan badge versi `v1.2` di `AppBar` `HomeScreen` dan menambah kapasitas preview lirik di `TrackPreviewSheet` menjadi 8 baris.
  - Menambahkan unit test komprehensif di `test/romaji_service_test.dart` dan memperbarui `test/widget_test.dart`.

---

## [v3.0] — 2026-11-07 (Power Features, Rebranding MusEvee & CI/CD)

### Ditambahkan (Added)
- **Preview Audio 30 Detik Native (`android/app/src/main/kotlin/com/example/spotmeta_downloader/MainActivity.kt`, `lib/providers/downloader_provider.dart`, `lib/widgets/track_preview_sheet.dart`):**
  - Integrasi `MediaPlayer` native Android melalui `MethodChannel` (`playPreviewUrl`, `stopPreview`, `onPreviewStateChanged`) untuk memutar cuplikan audio 30 detik dari Deezer/iTunes langsung dari tombol di atas gambar sampul.
- **Pemilih Sumber Audio YouTube Manual (`lib/services/audio_service.dart`, `lib/widgets/track_preview_sheet.dart`):**
  - Menambahkan model `YoutubeCandidate` dan fungsi `searchYoutubeCandidates()` yang menampilkan 5 kandidat video YouTube teratas lengkap dengan durasi dan nama kanal agar pengguna bisa mengganti sumber audio secara manual sebelum mengunduh.
- **Toggle Lirik Berjalan (Synced LRC) vs Lirik Biasa di Tag `USLT` (`lib/models/track_metadata.dart`, `lib/services/tagging_service.dart`, `lib/widgets/track_preview_sheet.dart`):**
  - Menyuntikkan lirik ber-timestamp `[mm:ss.xx]` maupun lirik biasa langsung ke dalam frame biner `USLT` ID3v2.4.0 (`\r\n`) di dalam file MP3 tanpa membuat file `.lrc` terpisah, mendukung penuh fitur *Embedded Synced Lyrics* di Musicolet.
- **Fitur Auto-Romaji (`lib/services/romaji_service.dart`, `lib/widgets/track_preview_sheet.dart`, `lib/widgets/tag_editor_sheet.dart`):**
  - Deteksi otomatis karakter Jepang (Hiragana, Katakana, Kanji) pada metadata maupun lirik lagu serta tombol konversi cepat ke Romaji.
- **Unduh Massal Album & Playlist Spotify (`lib/services/metadata_service.dart`, `lib/widgets/batch_playlist_sheet.dart`, `lib/providers/downloader_provider.dart`):**
  - Ekstraksi daftar lagu dari link Album atau Playlist Spotify publik dan antrean unduhan massal (*Batch Queue*) melalui `BatchPlaylistSheet`.
- **Edit Tag & Lirik Ulang Instan Tanpa Unduh Ulang (`lib/services/tagging_service.dart`, `lib/widgets/tag_editor_sheet.dart`, `lib/widgets/queue_history_view.dart`):**
  - Fitur `retagExistingMp3()` menggunakan `-c:a copy` FFmpeg + penulisan ulang header ID3v2.4.0 untuk memperbarui metadata dan lirik pada file MP3 yang sudah selesai diunduh dalam waktu kurang dari 1 detik.
- **Rebranding ke `MusEvee` & CI/CD GitHub Actions (`lib/main.dart`, `lib/screens/home_screen.dart`, `lib/widgets/musevee_logo.dart`, `.github/workflows/build_apk.yml`):**
  - Mengubah identitas aplikasi menjadi **MusEvee** dengan gaya *Modern Architectural UI* (palet `dhaauu.web.id`, border tipis `0.8px`, sudut `6px–10px`), logo vektor transparan `MusEveeLogo`, dan workflow otomatis GitHub Actions (`build_apk.yml`).

---

## [v2.0] — 2026-11-06 (All-in-One Musicolet Workflow)

### Ditambahkan & Dirombak (Added & Changed)
- **Pencarian Musik Langsung (*Smart Omnibox* — `lib/services/metadata_service.dart`, `lib/screens/home_screen.dart`):**
  - Menggabungkan pencarian kata kunci langsung ke **Deezer Search API** dan **iTunes Search API** (untuk kelengkapan katalog lagu Barat, Indonesia, dan Jepang/J-Pop) serta deteksi otomatis link Spotify.
- **Pemilih Folder Tujuan & Deteksi Duplikat Lintas Folder (`lib/services/folder_service.dart`, `lib/providers/downloader_provider.dart`):**
  - Menambahkan pilihan folder cepat (`Music Barat`, `Music Japan`, `Music Random`), pemindaian subfolder otomatis di `/storage/emulated/0/Music/`, pembuatan folder baru, serta pengecekan lagu duplikat lintas folder (`findDuplicateFolder`).
- **Integrasi Android Share Intent & MediaScanner (`android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/com/example/spotmeta_downloader/MainActivity.kt`):**
  - Mendaftarkan `intent-filter` `android.intent.action.SEND` (`text/plain`) agar bisa menerima *Share* langsung dari aplikasi Spotify, serta memanggil `MediaScannerConnection.scanFile` agar lagu langsung muncul di Musicolet.
- **Antrean Unduhan, Riwayat, & Pindah Folder 1-Klik (`lib/models/download_item.dart`, `lib/widgets/queue_history_view.dart`, `lib/widgets/search_result_tile.dart`):**
  - Merombak tata letak menjadi 2 Tab utama (*Cari & Unduh* serta *Antrean & Riwayat*) ditambah modal bottom sheet (`TrackPreviewSheet` & `TagEditorSheet`) dan fitur pemindahan file antar folder.

---

## [v1.0] — 2026-11-05 (Initial SpotMeta Downloader)

### Ditambahkan (Added)
- **Fondasi Pipeline 5 Tahap (`lib/main.dart`, `lib/models/track_metadata.dart`, `lib/providers/downloader_provider.dart`):**
  1. `lib/services/metadata_service.dart`: Ekstraksi metadata publik dari link Spotify Track melalui endpoint oEmbed & parsing OpenGraph HTML, diperkaya dengan Deezer Public API (Cover Art HD 1000×1000, Album, Tahun Rilis, Durasi).
  2. `lib/services/lyrics_service.dart`: Pengambilan lirik `syncedLyrics` dan `plainLyrics` dari LRCLIB Public API.
  3. `lib/services/audio_service.dart`: Pencarian dan pengunduhan stream audio bitrate tertinggi dari YouTube menggunakan `youtube_explode_dart` dengan mekanisme *multi-client fallback*.
  4. `lib/services/tagging_service.dart`: Konversi audio ke MP3 320kbps menggunakan `ffmpeg_kit_flutter_new_audio` serta penyuntikan sampul album (`APIC`), tag teks (`TIT2`, `TPE1`, `TPE2`, `TALB`, `TDRC`), dan lirik (`USLT`) berstandar ID3v2.4.0.

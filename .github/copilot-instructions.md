# Instruksi Wajib AI Agent — Proyek MusEvee

SETIAP AI AGENT YANG MENGERJAKAN PROYEK INI WAJIB:
1. Membaca `AGENTS.md` dan `CHANGELOG.md` di root repositori terlebih dahulu sebelum menulis atau mengubah kode apa pun.
2. Menjaga 100% fitur **Pemutar Musik Lokal bergaya Musicolet (1:1)** maupun seluruh layanan **All-in-One Downloader** (`MetadataService`, `LyricsService`, `AudioService`, `TaggingService`, `RomajiService`, `FolderService`, Preview 30s, Pemilih Sumber YouTube, Batch Playlist Spotify, Pindah Folder, dan Retag MP3 Instan) yang tercatat di `AGENTS.md` agar tidak mengalami regresi.
3. Setiap kali selesai memperbaiki bug, mengubah UI, atau menambah fitur baru, **WAJIB** memperbarui bagian **"Status Terkini"** di `AGENTS.md` dan menambahkan entri baru di bagian paling atas `CHANGELOG.md` (lengkap dengan daftar file yang dimodifikasi) sebelum melakukan `git commit` / `git push`.

## Ringkasan Cepat Arsitektur & Aturan Teknis
- **Framework & State Management:** Flutter (MVVM dengan `MultiProvider`: `LocalMusicProvider` untuk pemutar/koleksi lokal Musicolet & `DownloaderProvider` untuk pencarian/unduhan lagu).
- **Navigasi 7-Tab Musicolet (`lib/screens/home_screen.dart` & `lib/widgets/musicolet_bottom_strip.dart`):** `0: Queue`, `1: Now Playing` (Dynamic Ambient Background + Embedded Lyrics Ribbon + Tap-to-Seek), `2: Folders`, `3: Playlists` (`musicevee_playlists_v1.json` + Spotify Batch Auto-Sync + Smart Deduplication), `4: Downloader`, `5: Download Queue & History`, `6: Search Lokal`, ditambah `MusicoletMiniPlayer` di luar tab Now Playing.
- **Native Android Channel (`com.spotmeta.downloader/system` di `MainActivity.kt` & `MusEveeMediaNotifier.kt`):** Menangani `MediaPlayer` lokal (`localPlayFile`, `localPause`, `localResume`, `localSeekTo`, `openEqualizer`), `MediaSession` + `Notification.MediaStyle` (`Notification.CATEGORY_TRANSPORT`) + `MusEveePlaybackService` (`applicationId = "com.zte.as.music"` untuk dukungan native Live Island ZTE/nubia), ekstraktor biner ID3v2 `APIC`/`USLT` & warna dominan (`scanLocalMusicLibraryDelta`, `readLocalTrackDetails`), Scoped Storage Android 11–15 (`deleteLocalAudioFile`, `writeBytesToMusicFile`), Share Intent, dan Preview Audio 30 detik.
- **Lirik & Romaji (`lib/services/lyrics_service.dart`, `lib/services/romaji_service.dart`, `lib/services/tagging_service.dart`):**
  - Lirik disuntikkan langsung ke dalam frame biner `USLT` ID3v2.4.0 (`\r\n`) di dalam file `.mp3` tanpa file `.lrc` eksternal.
  - Konversi Romaji wajib mempertahankan isolasi timestamp `[mm:ss.xx]` baris-demi-baris, menghapus duplikasi lirik bilingual/Romaji kembar (`normalizeForComparison` & `deduplicateRomajiLyrics`), dan memprioritaskan lirik bahasa asli Jepang/Romaji di atas terjemahan Inggris.
- **CI/CD & Ukuran APK (`.github/workflows/build_apk.yml` & `android/app/build.gradle.kts`):**
  - Selalu gunakan `--split-per-abi --target-platform android-arm64`, `packaging.jniLibs.excludes` non-ARM64, dan keystore permanen `android/app/musevee-release.jks` (`~20 MB`).

# SpotMeta Downloader

Aplikasi Android berbasis **Flutter (Material 3)** untuk mengunduh lagu dari link **Spotify** lengkap dengan **metadata ID3v2.3**, **cover art resolusi tinggi (1000×1000)**, dan **lirik tersinkronisasi (LRC / USLT)** 100% menggunakan **Public API gratis** tanpa API Key atau login.

---

## Fitur Utama & Pipeline 5 Tahap

1. **Tahap 1 — Spotify Public Extractor (`MetadataService`)**
   - Memvalidasi dan menormalisasi URL lagu Spotify (`https://open.spotify.com/track/...`).
   - Mengambil metadata awal melalui endpoint publik `https://open.spotify.com/oembed?url={url}` serta mem-parsing meta tag HTML OpenGraph (`og:title`, `og:description`, `og:image`, `music:duration`).
2. **Tahap 2 — Deezer Public API Enricher (`MetadataService`)**
   - Memperkaya metadata menggunakan `https://api.deezer.com/search?q=artist:"{artist}" track:"{title}"` (beserta fallback pencarian longgar `{artist} {title}`) dan detail album `/album/{id}`.
   - Melengkapi **Nama Album**, **Tahun Rilis**, **Durasi Presisi (detik)**, dan **Cover Art HD 1000×1000 (`cover_xl`)**.
3. **Tahap 3 — LRCLIB Public API (`LyricsService`)**
   - Mengambil lirik dari `https://lrclib.net/api/get` (dengan fallback ke `https://lrclib.net/api/search`) berdasarkan `track_name`, `artist_name`, `album_name`, dan `duration`.
   - Memprioritaskan `syncedLyrics` (format `.lrc` ber-timestamp) dengan cadangan `plainLyrics`. Jika lirik tidak tersedia, proses unduhan tetap berjalan normal.
4. **Tahap 4 — Audio Stream Extractor (`AudioService`)**
   - Mencari sumber audio resmi menggunakan `YoutubeExplode` dengan query `"{artist} - {title} Official Audio"` (hanya memeriksa 8 kandidat teratas dari batch pertama tanpa paginasi berulang).
   - Menggunakan **Multi-Client Fallback** (`ios`, `androidVr`, `androidSdkless`, `safari`, `tv`, `mweb`) dengan batas waktu 20 detik pada `getManifest`.
   - Memprioritaskan stream audio berkontainer `mp4`/`m4a` (serta fallback `audioOnly` lainnya dan `muxed`) dengan **chunk timeout 15 detik** untuk menghindari *throttling* 0 KB/s dari YouTube.
5. **Tahap 5 — FFmpeg Conversion & ID3v2 Tagging (`TaggingService`)**
   - Mengunduh gambar sampul `coverUrl` ke direktori sementara.
   - Mengeksekusi `FFmpegKit.executeWithArguments(List<String> arguments)` untuk mengonversi audio ke **MP3 320kbps** (`-c:a libmp3lame -b:a 320k`), menyematkan sampul album (`-c:v mjpeg -id3v2_version 3`), serta menyuntikkan tag metadata `title`, `artist`, `album`, `date`, `lyrics`, dan `USLT`.
   - Menyimpan file akhir dengan nama bersih `{Artist} - {Title}.mp3` ke `/storage/emulated/0/Music/SpotMeta` (dengan fallback otomatis ke direktori penyimpanan eksternal aplikasi).

---

## Struktur Direktori `lib/`

```text
lib/
├── main.dart                         # Entry point aplikasi, konfigurasi Material 3 Dark Theme & Provider
├── models/
│   └── track_metadata.dart           # Model data TrackMetadata & helper format durasi / preview lirik
├── providers/
│   └── downloader_provider.dart      # State management MVVM (ChangeNotifier) & siklus state unduhan
├── screens/
│   └── home_screen.dart              # UI Dark Mode (#121212, #1E1E1E, #1DB954), Preview Card & Stepper
└── services/
    ├── metadata_service.dart         # Ekstraktor publik Spotify oEmbed/HTML & pengayaan Deezer API
    ├── lyrics_service.dart           # Pengambil lirik tersinkronisasi & plain dari LRCLIB API
    ├── audio_service.dart            # Pencarian & pengunduhan AudioOnlyStreamInfo bitrate tertinggi
    └── tagging_service.dart          # Konversi MP3 320kbps, injeksi ID3v2 & cover art via FFmpeg
```

---

## Spesifikasi Package (`pubspec.yaml`)

- `provider: ^6.1.2`
- `dio: ^5.7.0`
- `html: ^0.15.4`
- `youtube_explode_dart: ^3.1.0`
- `ffmpeg_kit_flutter_new_audio: ^2.5.8` (pengganti aktif `ffmpeg_kit_flutter_audio` yang telah di-retire dari Maven Central)
- `path_provider: ^2.1.4`
- `permission_handler: ^11.3.1`

---

## Konfigurasi Sistem Android

- **`android/app/build.gradle.kts`**:
  - `minSdk = 24`
  - `multiDexEnabled = true`
- **`android/app/src/main/AndroidManifest.xml`**:
  - `android.permission.INTERNET`
  - `android.permission.READ_EXTERNAL_STORAGE` (`android:maxSdkVersion="32"`)
  - `android.permission.WRITE_EXTERNAL_STORAGE` (`android:maxSdkVersion="32"`)
  - `android.permission.READ_MEDIA_AUDIO`
  - `android:requestLegacyExternalStorage="true"` pada `<application>`

---

## Perintah Menjalankan & Membangun Aplikasi

```bash
flutter pub get
flutter analyze
flutter build apk --debug
flutter run
```

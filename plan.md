# Rencana Pengembangan (Implementation Plan): SpotMeta Music Downloader v2.0

Dokumen ini berisi cetak biru teknis untuk mengembangkan **SpotMeta Downloader** dari yang semula hanya mengandalkan link Spotify menjadi **All-in-One Music Search & Downloader** yang dirancang khusus agar menyatu sempurna dengan workflow **Musicolet** di Android.

---

## 1. Ringkasan Fitur Baru yang Akan Dibangun

1. **Pencarian Musik Langsung (*Direct Music Search* — Barat, Jepang/J-Pop, Indo, dll.)**
   - Satu kolom pintar (*Smart Omnibox*): bisa diketik **kata kunci judul/artis** (misal: `"Yoasobi Idol"`, `"Katy Perry The One That Got Away"`, `"Hindia"`) **ATAU** ditempel **link Spotify** (`open.spotify.com/track/...`).
   - Menggabungkan katalog **Deezer Public API** dan **iTunes Search API** (tanpa API Key) agar pencarian lagu Barat maupun lagu Jepang (*J-Pop / Anime / Vocaloid*) selalu lengkap beserta Cover Art 1000×1000, Album, dan Tahun Rilis.
2. **Pemilih Folder Tujuan (*Folder Selector*: `Music Barat`, `Music Japan`, `Music Random`)**
   - Deretan *Quick Folder Chips* di halaman utama untuk memilih folder tujuan sebelum mengunduh:
     - `/storage/emulated/0/Music/Music Barat`
     - `/storage/emulated/0/Music/Music Japan`
     - `/storage/emulated/0/Music/Music Random`
   - **Auto-Scan Subfolder**: Otomatis membaca semua subfolder yang ada di `/storage/emulated/0/Music/` di HP kamu + tombol **`+ Folder Baru`**.
   - **Ingat Folder Terakhir**: Menyimpan pilihan folder terakhir secara otomatis.
3. **Deteksi Lagu Duplikat (*Cross-Folder Duplicate Checker*)**
   - Saat hasil pencarian muncul atau lagu dipilih, aplikasi otomatis mengecek apakah file `Artis - Judul.mp3` sudah pernah diunduh di `Music Barat`, `Music Japan`, `Music Random`, atau subfolder lainnya.
   - Menampilkan badge **`Sudah ada di Music Japan`** (atau folder terkait) agar kamu tidak mengunduh lagu yang sama dua kali.
4. **Editor Metadata & Lirik Sebelum Download (*Quick Tag & Lyrics Editor*)**
   - Tombol **"Edit Tag & Lirik"** pada kartu preview lagu untuk mengubah `Judul`, `Artis`, `Album`, `Tahun`, atau `Teks Lirik (USLT)` sebelum file MP3 dibuat (sangat berguna untuk mengubah judul Kanji Jepang menjadi Romaji atau merapikan lirik).
5. **Integrasi "Share" dari Aplikasi Spotify (*Android Share Intent*)**
   - Mendaftarkan `intent-filter` `ACTION_SEND` (`text/plain`) di Android agar saat kamu menekan tombol **Share** di aplikasi Spotify, kamu bisa langsung memilih **SpotMeta Downloader** dan lagu otomatis diproses.
6. **Antrean Unduhan (*Download Queue*) & Riwayat Unduhan (*Pindah Folder 1-Klik*)**
   - Bisa memilih beberapa lagu dari hasil pencarian untuk masuk ke antrean (*Queue*) dan diunduh berurutan tanpa harus menunggu satu-satu.
   - Daftar riwayat unduhan di bawah layar dilengkapi tombol **"Pindah Folder"** jika kamu ingin memindahkan lagu yang sudah terunduh dari `Music Random` ke `Music Barat` / `Music Japan`.
7. **Sinkronisasi Instan ke Musicolet (*Android MediaScanner Native Channel*)**
   - Menambahkan `MethodChannel` di `MainActivity.kt` yang memanggil `MediaScannerConnection.scanFile` setiap kali file `.mp3` selesai disimpan atau dipindahkan, sehingga lagu langsung muncul di **Musicolet** detik itu juga beserta Cover Art dan Lirik `USLT` (ID3v2.4.0 tanpa file `.lrc`).

---

## 2. Rincian Perubahan Arsitektur & File

### A. Lapisan Native Android (`android/`)
1. `android/app/src/main/AndroidManifest.xml`
   - Menambahkan `<intent-filter>` untuk `android.intent.action.SEND` dengan `mimeType="text/plain"` pada `MainActivity` agar aplikasi muncul di menu **Share (Bagikan)** Spotify/YouTube Music.
2. `android/app/src/main/kotlin/com/example/spotmeta_downloader/MainActivity.kt`
   - Menambahkan `MethodChannel('com.spotmeta.downloader/system')` dengan 2 fungsi native:
     - `scanMediaFile(String path)`: Memicu `MediaScannerConnection.scanFile` agar Musicolet dan MediaStore Android langsung mendeteksi lagu baru/pindahan.
     - `getInitialSharedText()` & event stream `onSharedText`: Mengirim teks/link yang di-*share* dari aplikasi Spotify ke lapisan Flutter.

### B. Model Data (`lib/models/`)
1. `lib/models/track_metadata.dart`
   - Menambahkan properti opsional `previewAudioUrl` dan mempertahankan `cleanPlainLyrics` (format `\r\n` tanpa timestamp untuk frame `USLT` ID3v2.4.0).
2. `lib/models/download_item.dart` *(File Baru)*
   - Model untuk merepresentasikan item dalam **Antrean Unduhan (Queue)** dan **Riwayat Unduhan (History)**:
     - `id`, `metadata`, `targetFolderName`, `savedFilePath`, `status` (`queued`, `downloading`, `tagging`, `completed`, `failed`), `progress`, `statusDetail`.

### C. Lapisan Service (`lib/services/`)
1. `lib/services/metadata_service.dart`
   - Menambahkan metode `bool isSpotifyUrl(String input)` untuk membedakan antara input link Spotify dan kata kunci pencarian biasa.
   - Menambahkan metode `Future<List<TrackMetadata>> searchTracks(String query)`:
     - **Sumber 1 (Deezer Search API)**: Mengambil daftar lagu beserta cover `1000x1000` (`cover_xl`), nama album, dan durasi.
     - **Sumber 2 (iTunes Search API — `https://itunes.apple.com/search?entity=song`)**: Digabungkan/dipakai sebagai pengaya karena katalog lagu Jepang (`Music Japan`) dan rilisan tahun (`releaseDate`) di iTunes sangat lengkap dan langsung menyediakan artwork `1000x1000bb.jpg`.
2. `lib/services/folder_service.dart` *(File Baru)*
   - Mengelola daftar folder tujuan di `/storage/emulated/0/Music/`:
     - Memastikan 3 folder utama (`Music Barat`, `Music Japan`, `Music Random`) selalu tersedia di daftar pilihan.
     - Memindai subfolder lain yang sudah ada di `/storage/emulated/0/Music/`.
     - Menyediakan fungsi `createFolder(String folderName)`, `checkDuplicateAcrossFolders(String fileName)`, dan `moveDownloadedFile(String currentPath, String targetFolderName)`.
3. `lib/services/tagging_service.dart`
   - Memperbarui `convertAndTagAudio` agar menerima parameter `targetFolderName` (misal `'Music Barat'`, `'Music Japan'`, `'Music Random'`) dan menyimpan langsung ke `/storage/emulated/0/Music/{targetFolderName}/{Artis} - {Judul}.mp3`.
   - Memanggil `scanMediaFile` via `MethodChannel` segera setelah file `.mp3` ber-tag ID3v2.4.0 selesai ditulis.

### D. State Management (`lib/providers/`)
1. `lib/providers/downloader_provider.dart`
   - Menambahkan state dan aksi untuk:
     - `searchResults` (`List<TrackMetadata>`): Menyimpan daftar hasil pencarian lagu.
     - `availableFolders` & `selectedFolder`: Daftar folder (`Music Barat`, `Music Japan`, `Music Random`, dst.) dan folder aktif yang dipilih.
     - `duplicateFolderMap`: Informasi apakah lagu pada hasil pencarian/preview sudah ada di salah satu folder musik kamu.
     - `updatePreviewMetadata(...)`: Menyimpan hasil edit manual `Judul`, `Artis`, `Album`, `Tahun`, dan `Lirik` sebelum diunduh.
     - `downloadQueue` & `downloadHistory`: Mengelola antrean unduhan berurutan dan riwayat lagu yang selesai diunduh (termasuk aksi **Pindah Folder**).

### E. Antarmuka Pengguna (`lib/screens/`)
1. `lib/screens/home_screen.dart`
   - **Smart Search & Link Bar**: Kolom input dengan deteksi otomatis (*"Cari judul lagu / artis atau tempel link Spotify..."*).
   - **Daftar Hasil Pencarian Lagu**: List interaktif menampilkan thumbnail cover art, judul, artis, album, durasi, serta indikator jika lagu sudah pernah diunduh di salah satu folder.
   - **Folder Selector Bar**: Deretan *ChoiceChip* (`Music Barat`, `Music Japan`, `Music Random`, folder lain di `/Music`, serta tombol `+ Folder`).
   - **Kartu Preview Lagu + Tombol "Edit Tag & Lirik"**: Menampilkan detail lagu dan lirik dengan modal editor sebelum mengunduh.
   - **Panel Antrean & Riwayat Unduhan**: Menampilkan progres unduhan aktif, lokasi folder penyimpanan, dan tombol cepat untuk memindahkan lagu antar folder (`Music Barat` ↔ `Music Japan` ↔ `Music Random`).

---

## 3. Tahapan Verifikasi Setelah Disetujui
1. Menjalankan `flutter analyze` hingga bersih tanpa error/warning (`No issues found!`).
2. Mem-*build* APK (`flutter build apk --debug --target-platform android-arm64`) dan menginstalnya langsung ke HP kamu via ADB.
3. Menguji skenario lengkap:
   - Mencari lagu lewat kata kunci (lagu Barat & lagu Jepang) dan memilih dari daftar hasil pencarian.
   - Memilih folder tujuan (`Music Barat`, `Music Japan`, `Music Random`) dan mengunduh lagu.
   - Memastikan file `.mp3` masuk ke `/storage/emulated/0/Music/{Folder Pilihan}/` lengkap dengan Cover Art HD dan Lirik `USLT` ID3v2.4.0 yang langsung tampil di **Musicolet** tanpa file `.lrc`.


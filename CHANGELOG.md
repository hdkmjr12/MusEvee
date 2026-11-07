# Changelog — MusEvee

Seluruh riwayat perubahan penting pada proyek **MusEvee** (nama resmi dan permanen aplikasi; sebelumnya sempat menggunakan nama *SpotMeta Downloader*) dicatat di dokumen ini secara kronologis terbalik (versi terbaru berada di paling atas).

> **Catatan Wajib untuk AI Agent:** Setiap kali Anda menyelesaikan perbaikan bug, perubahan UI, atau penambahan fitur baru, Anda **wajib** menambahkan entri baru di bagian paling atas file ini dan memperbarui bagian *Status Terkini* di `AGENTS.md` sebelum melakukan `git commit` / `git push`.

---

## [v4.2] — 2026-11-07 (Permanent Rebranding to MusEvee, Android 15 Scoped Storage Delete/Retag/Move & Cross-Script Romaji J-Pop Search)

### Ditambahkan & Diperbaiki (Added & Fixed)
- **Rebranding Resmi & Permanen Kembali ke `MusEvee` (`android/app/src/main/AndroidManifest.xml`, `lib/main.dart`, `lib/screens/home_screen.dart`, `lib/widgets/now_playing_view.dart`, `lib/widgets/queue_history_view.dart`, `lib/providers/local_music_provider.dart`, `pubspec.yaml`, `.github/workflows/build_apk.yml`, `.github/copilot-instructions.md`, `.idx/airules.md`, `test/widget_test.dart`):**
  - Menetapkan **`MusEvee`** (`v4.2.0+6`, badge UI `v4.2`) sebagai nama resmi dan permanen aplikasi pada ikon peluncur Android, `MusEveeApp`, header aplikasi, layar `NowPlayingView` (`MusEvee Player`), berkas cache sesi/pustaka (`musevee_library_cache_v1.json`, `musevee_player_session.json`, `musevee_favorites.json` dengan migrasi otomatis dari cache lama), serta artefak CI/CD GitHub Actions.
- **Perbaikan Total Penghapusan, Retag & Pemindahan File Lagu di Android 15 Scoped Storage (`android/app/src/main/kotlin/com/example/spotmeta_downloader/MainActivity.kt`, `lib/services/folder_service.dart`, `lib/services/tagging_service.dart`, `lib/providers/local_music_provider.dart`, `lib/widgets/now_playing_view.dart`, `lib/widgets/local_library_views.dart`):**
  - **Pelepasan File Lock `MediaPlayer` Lebih Dulu:** Memastikan `localPlayer` dilepaskan penuh (`stop()` + `reset()` + `release()` melalui `await localStop`) sebelum file MP3 yang sedang aktif/dijeda dihapus, di-retag, atau dipindah folder, serta melanjutkan pemutaran otomatis ke lagu berikutnya di Queue setelah file berhasil dihapus.
  - **Penghapusan & Penulisan Berlapis Android 11–15 (`API 30–35`):** Menambahkan metode native `deleteLocalAudioFile`, `writeBytesToMusicFile`, `hasAllFilesAccess`, dan `requestAllFilesAccess` di `MainActivity.kt` yang menangani `File.delete()`/`FileOutputStream`, `ContentResolver` (`ContentUris` `_ID` & `DATA=?`), dialog konfirmasi sistem `MediaStore.createDeleteRequest` / `MediaStore.createWriteRequest`, serta eskalasi izin `MANAGE_EXTERNAL_STORAGE` (`Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`).
  - **Konsistensi State & Proteksi Exception:** Memperbaiki urutan `LocalMusicProvider.deleteLocalSong` agar hanya menghapus entri dari `_allSongs`, `_queueEntries`, cache JSON, dan cover thumbnail setelah file fisik terkonfirmasi terhapus (`!File(path).exists()`), menambahkan dialog konfirmasi + notifikasi SnackBar pada menu hapus di `LocalFoldersView`/`LocalAlbumsView`/`LocalArtistsView`/`LocalSearchView`, serta membungkus penanaman lirik LRCLIB & Auto-Romaji agar bebas `PathAccessException (errno = 13)`.
- **Mesin Pencarian Lagu Jepang Lintas-Aksara Romaji -> Kanji/Kana (`lib/services/metadata_service.dart`, `test/romaji_service_test.dart`):**
  - Menambahkan ekspansi kueri Romaji otomatis (`expandRomajiQueryForJapanese`) menggunakan **Google Input Tools Japanese IME** (`itc=ja-t-i0-und` untuk frasa utuh dan per-kata) serta **Google Translate** (`client=gtx&sl=en&tl=ja&dt=t`) secara paralel.
  - Menggabungkan pencarian paralel (`Future.wait`) ke **iTunes Search API Japan (`country=JP&lang=ja_jp`)**, **iTunes Search API Global (`country=ID`)**, dan **Deezer Search API** baik menggunakan kata kunci asli maupun hasil konversi Kanji/Kana, dilengkapi *relevance scoring* lintas-aksara dan penalti cover *orgel / music box / karaoke* — teruji langsung mengembalikan **`平行線` (`Heikousen`) — `さユり` (`Sayuri`)** di peringkat #1 untuk kueri `"heikousen sayuri"`.
- **Perbaikan Tambahan Hasil Live USB Debugging di Perangkat Android 15 `Z2464N` (`android/app/src/main/kotlin/com/example/spotmeta_downloader/MainActivity.kt`, `lib/services/folder_service.dart`, `lib/providers/local_music_provider.dart`):**
  - **Penyaringan Folder Sistem & Stub Audio Rusak (`< 16 KB`):** Mengecualikan subfolder sistem bawaan OS (`ringtones_music`, `ringtones`, `alarms`, `notifications`, `ui`, `.thumbnails`), menambahkan klausa `MediaStore.Audio.Media.IS_MUSIC != 0`, serta mengabaikan file stub rusak berukuran `< 16 KB` (seperti `au_uu_*.mp3` `1.1 KB`) baik di pemindai perpustakaan lokal maupun penghitung folder Downloader sehingga bebas dari polusi nada dering sistem dan error `MetadataRetrieverClient`.
  - **Dukungan Lirik Pendamping `.lrc` Warisan & Sinkronisasi Pindah/Hapus:** Menambahkan fallback `readCompanionLrcIfPresent` di `MainActivity.kt` (beserta pengecekan delta `hasLyrics`) agar koleksi MP3 lama yang masih menyimpan lirik di file `.lrc` pendamping tetap menampilkan *Synchronized Lyrics Ribbon* & mendukung Auto-Romaji, sekaligus menyalin/menghapus file `.lrc` pendamping secara otomatis saat lagu dipindah folder atau dihapus.

---

## [v4.1] — 2026-11-07 (True Queue-Order Shuffle, Incremental Library Cache, 200ms Ticker Isolation & Native AudioFocus)

### Diperbaiki & Dioptimalkan (Fixed & Optimized)
- **True Queue-Order Shuffle & `QueueEntry` Stabil (Bug #1 & #2 — `lib/models/local_song.dart`, `lib/providers/local_music_provider.dart`, `lib/widgets/local_library_views.dart`):**
  - Mengganti representasi antrean mentah dengan `QueueEntry(queueId, song)` ber-ID unik sehingga lagu duplikat di Queue tidak memicu bentrokan `ValueKey` dan mendukung *drag-and-drop* mulus (`buildDefaultDragHandles: false` + `ReorderableDragStartListener`).
  - Menyimpan cadangan `_originalQueueEntries` dan menerapkan **Musicolet True Queue-Order Shuffle** berbasis algoritma *Fisher-Yates* yang mengacak urutan fisik `_queueEntries` secara langsung (menjaga lagu aktif di indeks `0`) serta mengembalikan urutan asli saat Shuffle dimatikan.
  - Memastikan `playNext()` dan `playPrevious()` selalu bergerak linier mengikuti urutan daftar Queue visual (`_currentIndex + 1` dan `_currentIndex - 1`), serta memperbaiki `playSongByPath()` agar tidak menimpa Queue aktif saat memutar lagu dari tab Riwayat Unduhan.
- **Session Guard, Native `AudioFocusRequest` & Auto-Resume Preview 30s (Bug #2 & #6 — `android/app/src/main/kotlin/com/example/spotmeta_downloader/MainActivity.kt`, `lib/screens/home_screen.dart`):**
  - Menambahkan `playbackSessionId` monotonik serta validasi instance `mp === localPlayer` dan kecocokan `path` pada `OnPreparedListener`, `OnCompletionListener`, dan `positionTicker` untuk mencegah *race condition* atau *double-skip* saat berganti lagu cepat.
  - Mengimplementasikan manajemen `AudioFocusRequest` (`AUDIOFOCUS_GAIN` untuk pemutar lokal dan `AUDIOFOCUS_GAIN_TRANSIENT` untuk preview 30s) lengkap dengan *auto-pause* saat ada panggilan telepon/aplikasi media lain, *volume ducking* saat notifikasi masuk, serta `resumeLocalAfterPreview` agar lagu lokal otomatis lanjut berputar setelah preview 30 detik selesai.
- **Seekbar Snap-Back Guard & Sinkronisasi 2 Arah Instan (Bug #7 — `lib/providers/local_music_provider.dart`, `lib/providers/downloader_provider.dart`, `lib/widgets/now_playing_view.dart`, `lib/main.dart`):**
  - Menambahkan masa tenggang *seek guard* (`350ms`) pada `seekTo()` dan memperbaiki urutan `onChangeEnd` pada slider `NowPlayingView` agar thumb seekbar tidak memantul kembali ke posisi lama.
  - Menghubungkan sinkronisasi dua arah instan (`< 1ms` tanpa *rebuild storm* `ChangeNotifierProxyProvider`) antara `LocalMusicProvider` dan `DownloaderProvider` untuk seluruh operasi *download selesai (`upsertSingleSongByPath`), retag, rename, pindah folder,* maupun *hapus file* (termasuk pelepasan file handle `MediaPlayer` aktif dan pembersihan seluruh kemunculan lagu di Queue).
- **Instant Startup Hydrate (`< 50ms`) & Incremental Delta Sync Cache (Bug #3 — `MainActivity.kt`, `lib/providers/local_music_provider.dart`):**
  - Memindahkan penyimpanan thumbnail Cover Art dari `cacheDir/covers` ke direktori persisten `filesDir/covers` (dilengkapi pembersihan otomatis revisi cover lama) agar tidak dihapus sepihak oleh sistem Android.
  - Menyimpan indeks metadata perpustakaan lokal di `musicevee_library_cache_v1.json` serta sesi antrean/posisi putar terakhir di `musicevee_player_session.json` untuk *instant startup hydration* tanpa *loading spinner*.
  - Menambahkan metode native `scanLocalMusicLibraryDelta` yang membandingkan `lastModifiedMs` + `sizeBytes` + keberadaan file cover sehingga hanya file MP3 baru atau berubah yang menjalankan `MediaMetadataRetriever` dan ekstraksi tag ID3v2.
- **Isolasi Ticker 200ms (`ValueNotifier`), Memoisasi Koleksi & Optimasi RAM Bitmap/ID3v2 (Bug #4 & #5 — `local_music_provider.dart`, `local_song.dart`, `now_playing_view.dart`, `musicolet_mini_player.dart`, `local_library_views.dart`, `MainActivity.kt`):**
  - Mengisolasi pembaruan posisi `200ms` (`5 Hz`) ke `progressNotifier` (`ValueListenableBuilder<PlaybackProgress>`) dan `activeLyricIndexNotifier` (`ValueListenableBuilder<int>`) sehingga ke-8 tab di `IndexedStack` tidak lagi mengalami *global rebuild* 5 kali per detik.
  - Mememoisasi `folderSongsMap`, `albumSongsMap`, `artistSongsMap`, serta `Expando` `parsedSyncedLyrics`/`plainLyricLines`, dan menghapus seluruh pemanggilan sinkron `File.existsSync()` dari metode `build()`.
  - Menambahkan `cacheWidth` proporsional (`~144px` untuk thumbnail list/MiniPlayer dan `960px` untuk `NowPlayingView`) pada `Image.file()` serta mengoptimalkan `parseId3v2Tags` di `MainActivity.kt` agar membaca header frame secara *streaming* dan melompati payload gambar `APIC`/`PIC` besar menggunakan `raf.seek()` tanpa alokasi buffer multi-megabyte.

---

## [v4.0] — 2026-11-07 (MusicEvee: 1:1 Musicolet UI/UX Reverse Engineering + Integrated Downloader + Anti Double-Romaji)

### Ditambahkan & Dirombak (Added & Changed)
- **Rebranding & Transformasi Penuh ke `MusicEvee v4.0` (`android/app/src/main/AndroidManifest.xml`, `pubspec.yaml`, `lib/main.dart`, `.github/workflows/build_apk.yml`):**
  - Mengubah nama aplikasi menjadi **MusicEvee** (`v4.0.0+4`) dengan tema gelap khas **Musicolet** dan menghubungkan `LocalMusicProvider` dengan `DownloaderProvider` secara reaktif (`onLibraryChanged`) sehingga setiap lagu yang selesai diunduh, di-retag, atau dipindah folder langsung muncul di perpustakaan lokal.
- **Reverse Engineer 1:1 Layar "Now Playing" Musicolet (`lib/widgets/now_playing_view.dart`):**
  - **Dynamic Ambient Background:** Gradasi gelap dinamis yang otomatis menyesuaikan warna dominan dari Cover Art (`APIC`) lagu yang sedang diputar.
  - **Panel Overlay `Embedded lyrics` & Cover Art:** Dilengkapi top-bar khas Musicolet — kiri dropdown **`Embedded lyrics ⌄`** (beralih antara *Lirik Berjalan*, *Lirik Polos*, *Ganti Kandidat Lirik LRCLIB*, dan *✨ Auto-Romaji Lirik*), kanan ikon **`✎`** (membuka `TagEditorSheet` untuk mengedit tag/lirik file MP3 yang sedang diputar), **`⊙`** (toggle auto-scroll sinkronisasi waktu), **`TT`** (mengubah ukuran font lirik), dan **`✕`** (menutup overlay lirik untuk melihat Cover Art penuh).
  - **Highlight Pita Gelap & Tap-to-Seek:** Baris lirik aktif diposisikan otomatis di tengah vertikal dengan latar pita horizontal gelap transparan (`Colors.black.withValues(alpha: 0.45)`) dan teks putih **Bold**, mendukung *Tap-to-Seek* ke milidetik lirik yang diketuk.
  - **Informasi Lagu, Baris Utilitas, Seekbar & Transport Controls Musicolet:** Menampilkan Judul (`18sp` Bold Putih), Artis (`14sp`), dan Album (`13sp`), diikuti baris utilitas kiri (**Hati/Favorit**, **`(i)` Info File & Path Folder**, **`=+` Tambah ke Antrean**, dan kotak **`[...]`** menu cepat: Pindah Folder, Edit Tag, Ganti Lirik, Auto-Romaji, Hapus) serta kanan (**Mode Putar `1→` / Repeat All / Repeat One / Queue Once** dan **Shuffle `🔀`**), seekbar dengan thumb bulat putih bersih, tombol Volume, `|◀`, `▶/||` besar tanpa lingkaran background, `▶|`, dan Equalizer sistem Android (`📊`).
- **Navigasi Bottom Icon Strip 8-Tab Khas Musicolet & Mini Player (`lib/widgets/musicolet_bottom_strip.dart`, `lib/widgets/musicolet_mini_player.dart`, `lib/widgets/local_library_views.dart`, `lib/screens/home_screen.dart`):**
  - Membangun bar ikon navigasi bawah padat bergaya Musicolet dengan garis indikator putih tegas di bawah tab aktif: **1. Queue (`=♪`)**, **2. Now Playing (`▶`)**, **3. Folders (`📁`)**, **4. Albums (`💿`)**, **5. Artists (`👤`)**, **6. Downloader (`⬇` — Smart Omnibox Deezer/iTunes & Link Spotify)**, **7. Download Queue & History (`📋` — dilengkapi tombol `▶` Putar langsung, Pindah Folder 1-Klik, & Edit Tag Ulang)**, dan **8. Search Lokal (`🔍`)**.
  - Menampilkan `MusicoletMiniPlayer` tipis tepat di atas bar ikon bawah saat berada di luar layar Now Playing, serta menyatukan seluruh event native ke dalam router tunggal `MethodChannel('com.spotmeta.downloader/system')`.
- **Mesin Pemutar Lokal Native & Pembaca Biner `USLT`/`APIC` (`android/app/src/main/kotlin/com/example/spotmeta_downloader/MainActivity.kt`, `lib/models/local_song.dart`, `lib/providers/local_music_provider.dart`, `lib/widgets/tag_editor_sheet.dart`):**
  - Menambahkan `MediaPlayer` lokal khusus di `MainActivity.kt` (`localPlayFile`, `localPause`, `localResume`, `localSeekTo`, `localStop`, `getVolume`, `setVolume`, `openEqualizer` via `AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL`, serta ticker posisi real-time 200ms & auto-next).
  - Menambahkan pemindai perpustakaan lokal (`scanLocalMusicLibrary` & `readLocalTrackDetails`) dengan `MediaMetadataRetriever` + parser biner ID3v2 (`v2.2`/`v2.3`/`v2.4`) untuk mengekstrak sampul gambar `APIC` (di-cache ke `cacheDir/covers`), warna dominan sampul, dan lirik `USLT` secara instan dari folder `Music Barat`, `Music Japan`, dan `Music Random`.
  - Memperluas `TagEditorSheet.showForLocalSong()` agar file MP3 lokal yang sedang diputar dapat langsung diedit tag ID3, diganti lirik LRCLIB-nya, atau dikonversi Auto-Romaji secara instan.

### Diperbaiki (Fixed)
- **Penguatan Anti Double-Romaji & Prioritas Bahasa Asli (`lib/services/romaji_service.dart`, `lib/services/lyrics_service.dart`, `test/romaji_service_test.dart`, `test/widget_test.dart`):**
  - Menambahkan `RomajiService.stripInlineFurigana()` untuk membersihkan furigana dalam tanda kurung sebelum transliterasi, `deduplicateRomajiLyrics()` untuk menghapus baris Romaji kembar pada lirik yang sudah berhuruf Latin, serta penyempurnaan `isRomajiText()` agar partikel ambigu seperti `"no"`/`"to"` pada kalimat Bahasa Inggris tidak pernah salah terdeteksi sebagai Romaji.

---

## [v3.1] — 2026-11-07 (Bilingual Romaji Deduplication, Japanese Lyrics Priority & Manual Lyrics Picker)

### Ditambahkan & Diperbaiki (Added & Fixed)
- **Deduplikasi Otomatis Lirik Bilingual pada `RomajiService` (`lib/services/romaji_service.dart`):**
  - Menambahkan fungsi `RomajiService.normalizeForComparison(String text)` yang menormalisasi huruf kecil, mengubah vokal bermakron (`ā`, `ī`, `ū`, `ē`, `ō`) serta variasi vokal panjang (`ou`/`oo` -> `o`, `uu` -> `u`, `aa` -> `a`, `ii` -> `i`, `ee` -> `e`, `wo` -> `o`), dan menghapus tanda baca, apostrof (`'`), serta seluruh spasi.
  - Menambahkan deteksi otomatis pasangan baris bilingual berurutan (1 baris aslinya berhuruf Jepang Kanji/Kana dan 1 baris aslinya alfabet Latin/Romaji pada timestamp identik atau berselisih `< 1.0` detik, maupun baris inline bilingual `Kanji / Romaji`) dan menghapus baris duplikatnya dengan mempertahankan baris yang memiliki pemisahan spasi kata paling rapi (`_pickCleanerRomajiText`).
- **Filter Bahasa & Prioritas Lirik Asli di `LyricsService` (`lib/services/lyrics_service.dart`):**
  - Mengubah pipeline pengambilan lirik di `LyricsService.fetchLyricsWithCandidates()` agar mengambil kandidat dari `/api/get`, `/api/search?track_name=...&artist_name=...`, dan `/api/search?q=...` secara paralel sehingga tidak terjebak pada entri tunggal `/api/get` yang terkadang berisi *English Version* (seperti pada lagu *"YOASOBI - Idol"*).
  - Menambahkan klasifikasi bahasa otomatis `classifyLyricsLanguage()` (`[Jepang/Kanji]`, `[Romaji]`, `[Bilingual]`, `[Inggris/Lainnya]`) serta sistem penilaian skor prioritas berdasarkan kecocokan durasi (`<= 3` detik), ketersediaan `syncedLyrics`, dan prioritas tertinggi untuk lirik `[Jepang/Kanji]`, `[Bilingual]`, serta `[Romaji]` (kecuali judul lagu secara eksplisit meminta `"English Ver"`).
- **Pemilih Kandidat Lirik Manual ("Ganti Lirik") (`lib/providers/downloader_provider.dart`, `lib/widgets/track_preview_sheet.dart`, `lib/widgets/tag_editor_sheet.dart`):**
  - Menyimpan daftar `List<LyricsCandidate>` di `DownloaderProvider` lengkap dengan metode `loadLyricsCandidates()` dan `selectLyricsCandidate()`.
  - Menambahkan tombol **"Ganti Lirik"** di `TrackPreviewSheet` dan `TagEditorSheet` yang menampilkan daftar kandidat lirik LRCLIB beserta badge bahasa (`[Jepang/Kanji]`, `[Romaji]`, `[Bilingual]`, `[Inggris/Lainnya]`), indikator `LRC`/`Biasa` + durasi, serta preview 2 baris pertama lirik untuk pergantian versi lirik 1-klik.

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
  - Menambahkan handler native `deleteMediaFile` di `MainActivity.kt` dan `FolderService.deleteMediaFile()` untuk menghapus file MP3 lama baik dari penyimpanan fisik maupun dari database `MediaStore.Audio.Media.EXTERNAL_CONTENT_URI` sebelum menulis ulang file baru.
- **Konsistensi Tanda Tangan APK & Ukuran Ringan ~20 MB (`android/app/build.gradle.kts`, `android/app/musevee-release.jks`, `.github/workflows/build_apk.yml`, `pubspec.yaml`):**
  - Menambahkan keystore permanen `android/app/musevee-release.jks` dan mengunci build rilis pada `--split-per-abi --target-platform android-arm64` (`~20.1 MB`).

---

## [v3.0] — 2026-11-07 (Power Features, Rebranding MusEvee & CI/CD)

### Ditambahkan (Added)
- **Preview Audio 30 Detik Native (`MainActivity.kt`, `downloader_provider.dart`, `track_preview_sheet.dart`):** Pemutar cuplikan audio 30 detik dari Deezer/iTunes.
- **Pemilih Sumber Audio YouTube Manual (`audio_service.dart`, `track_preview_sheet.dart`):** Menampilkan 5 kandidat video YouTube teratas untuk dipilih manual.
- **Toggle Lirik Berjalan (Synced LRC) vs Lirik Biasa di Tag `USLT` (`track_metadata.dart`, `tagging_service.dart`):** Injeksi biner `USLT` ID3v2.4.0 (`\r\n`) langsung di dalam file `.mp3` tanpa file `.lrc` eksternal.
- **Fitur Auto-Romaji (`romaji_service.dart`) & Unduh Massal Album/Playlist Spotify (`batch_playlist_sheet.dart`).**
- **Edit Tag & Lirik Ulang Instan (`tagging_service.dart` — `retagExistingMp3` dengan `-c:a copy`).**

---

## [v2.0] — 2026-11-06 (All-in-One Musicolet Workflow)

### Ditambahkan & Dirombak (Added & Changed)
- **Smart Omnibox (`metadata_service.dart`, `home_screen.dart`):** Pencarian katalog Deezer + iTunes serta deteksi otomatis link Spotify.
- **Pemilih Folder Tujuan & Deteksi Duplikat Lintas Folder (`folder_service.dart`):** Pilihan cepat `Music Barat`, `Music Japan`, `Music Random`, pembuatan folder baru, Share Intent Android, dan `MediaScannerConnection`.

---

## [v1.0] — 2026-11-05 (Initial SpotMeta Downloader)

### Ditambahkan (Added)
- **Fondasi Pipeline Pengunduh Musik (`metadata_service.dart`, `lyrics_service.dart`, `audio_service.dart`, `tagging_service.dart`):** Ekstraksi metadata Spotify oEmbed/OpenGraph + Deezer Cover Art 1000×1000, lirik LRCLIB, unduhan stream YouTube bitrate tertinggi (`youtube_explode_dart`), serta konversi FFmpeg MP3 320kbps dengan tag ID3v2.4.0 (`APIC` + `USLT`).

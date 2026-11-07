# Instruksi Wajib AI Agent (Project IDX / Gemini) — Proyek MusEvee

SETIAP AI AGENT YANG MENGERJAKAN PROYEK INI WAJIB:
1. Membaca `AGENTS.md` dan `CHANGELOG.md` di root repositori terlebih dahulu sebelum menulis atau mengubah kode apa pun.
2. Menjaga seluruh fitur inti dan gaya desain (*Modern Architectural UI* dengan palet `dhaauu.web.id`, `BorderRadius` 6px–10px, hairline border `0.8px`, logo transparan, dan teks UI ringkas bebas jargon teknis) yang tercatat di `AGENTS.md` agar tidak mengalami regresi.
3. Setiap kali selesai memperbaiki bug, mengubah UI, atau menambah fitur baru, **WAJIB** memperbarui bagian **"Status Terkini"** di `AGENTS.md` dan menambahkan entri baru di bagian paling atas `CHANGELOG.md` (lengkap dengan daftar file yang dimodifikasi) sebelum melakukan `git commit` / `git push`.

## Ringkasan Cepat Arsitektur & Aturan Teknis
- **Framework & State Management:** Flutter (MVVM dengan `Provider` / `ChangeNotifier` di `lib/providers/downloader_provider.dart`).
- **Native Android Channel (`com.spotmeta.downloader/system`):** Berada di `android/app/src/main/kotlin/com/example/spotmeta_downloader/MainActivity.kt` untuk `scanMediaFile` (MediaScanner Musicolet), `deleteMediaFile` (pembersihan file MP3 lama di disk & MediaStore), Share Intent (`ACTION_SEND`), dan pemutar preview audio 30 detik.
- **Lirik & Romaji (`lib/services/lyrics_service.dart`, `lib/services/romaji_service.dart`, `lib/services/tagging_service.dart`):**
  - Lirik disuntikkan langsung ke dalam frame biner `USLT` ID3v2.4.0 (`\r\n`) di dalam file `.mp3` tanpa file `.lrc` eksternal.
  - Konversi Romaji pada lirik **wajib** mempertahankan isolasi timestamp `[mm:ss.xx]` baris-demi-baris (`ParsedLyricLine`) dan menyinkronkan `syncedLyrics` serta `plainLyrics`.
- **CI/CD & Ukuran APK (`.github/workflows/build_apk.yml` & `android/app/build.gradle.kts`):**
  - Selalu gunakan `--split-per-abi --target-platform android-arm64`, `packaging.jniLibs.excludes` untuk arsitektur non-ARM64, dan keystore permanen `android/app/musevee-release.jks` agar hanya menghasilkan 1 file APK ringan (`~20.1 MB`).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/track_metadata.dart';
import 'folder_service.dart';

class TaggingException implements Exception {
  final String message;
  const TaggingException(this.message);

  @override
  String toString() => message;
}

class TaggingService {
  final Dio _dio;

  TaggingService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
              ),
            );

  /// Checks storage / media permissions with a short timeout so it never hangs.
  Future<void> requestStoragePermissions() async {
    if (!Platform.isAndroid) return;

    try {
      final storageStatus = await Permission.storage.status
          .timeout(const Duration(seconds: 3));
      debugPrint('[AUTO_E2E] TAHAP_5: Permission.storage status = $storageStatus');
    } catch (e) {
      debugPrint('[AUTO_E2E] TAHAP_5: Pengecekan Permission.storage dilewati: $e');
    }
  }

  /// Downloads high-res cover art, converts [rawAudioFile] to 320kbps MP3 via FFmpeg,
  /// and writes a complete, standards-compliant ID3v2.4.0 tag header containing:
  /// - `APIC` (high-res JPEG front cover)
  /// - `TALB`, `TDRC`, `TIT2`, `TPE1`, `TPE2` (UTF-8 text frames)
  /// - `USLT` (UTF-8 embedded plain lyrics frame with language `'eng'`, no `.lrc` file needed)
  /// matching the exact binary structure recognized natively by Musicolet.
  Future<String> convertAndTagAudio({
    required File rawAudioFile,
    required TrackMetadata metadata,
    String targetFolderName = 'Music Barat',
    bool preferSyncedLyrics = true,
    void Function(double progress, String detail)? onProgress,
  }) async {
    debugPrint(
      '[AUTO_E2E] TAHAP_5: Memulai konversi & tagging untuk input: ${rawAudioFile.path} (${await rawAudioFile.length()} bytes)',
    );
    await requestStoragePermissions();

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final coverFile = File(
      '${tempDir.path}${Platform.pathSeparator}cover_$timestamp.jpg',
    );
    final tempOutputMp3 = File(
      '${tempDir.path}${Platform.pathSeparator}output_$timestamp.mp3',
    );

    Uint8List? coverBytes;

    try {
      // 1. Download high-res cover art to temporary directory
      if (metadata.coverUrl.trim().isNotEmpty) {
        onProgress?.call(0.15, 'Mengunduh cover art resolusi tinggi...');
        debugPrint('[AUTO_E2E] TAHAP_5: Mengunduh cover art dari ${metadata.coverUrl}');
        try {
          await _dio
              .download(metadata.coverUrl, coverFile.path)
              .timeout(const Duration(seconds: 15));
          if (await coverFile.exists() && await coverFile.length() > 0) {
            coverBytes = await coverFile.readAsBytes();
            debugPrint(
              '[AUTO_E2E] TAHAP_5: Cover art berhasil diunduh (${coverBytes.length} bytes)',
            );
          }
        } catch (e, s) {
          coverBytes = null;
          debugPrint('[AUTO_E2E] TAHAP_5: Gagal mengunduh cover art (lanjut tanpa cover): $e\n$s');
        }
      }

      // 2. Convert audio stream to 320kbps MP3 using FFmpeg
      onProgress?.call(
        0.45,
        'Mengonversi audio ke MP3 320kbps...',
      );

      final ffmpegArgs = <String>[
        '-y',
        '-i',
        rawAudioFile.path,
        '-vn',
        '-map_metadata',
        '-1',
        '-c:a',
        'libmp3lame',
        '-b:a',
        '320k',
        '-write_id3v1',
        '0',
        tempOutputMp3.path,
      ];

      debugPrint('[AUTO_E2E] TAHAP_5: Menjalankan FFmpeg konversi MP3 320kbps...');
      final session = await FFmpegKit.executeWithArguments(ffmpegArgs);
      final returnCode = await session.getReturnCode();
      final outputLog = (await session.getOutput()) ?? '';
      debugPrint('[AUTO_E2E] TAHAP_5: FFmpeg ReturnCode = $returnCode');

      if (!ReturnCode.isSuccess(returnCode) ||
          !await tempOutputMp3.exists() ||
          await tempOutputMp3.length() <= 10000) {
        debugPrint('[AUTO_E2E] TAHAP_5: FFmpeg gagal. Log:\n$outputLog');
        throw TaggingException(
          'FFmpeg gagal mengonversi audio ke MP3 320kbps. Log: $outputLog',
        );
      }

      // 3. Write complete ID3v2.4.0 header (APIC + TALB + TDRC + TIT2 + TPE1 + TPE2 + USLT)
      // directly into tempOutputMp3, matching the exact binary layout of Musicolet-compatible MP3s.
      onProgress?.call(
        0.75,
        'Menyuntikkan cover art HD & lirik USLT ke dalam MP3 (ID3v2.4)...',
      );
      await _writeCompleteId3v24Tag(
        mp3File: tempOutputMp3,
        metadata: metadata,
        coverBytes: coverBytes,
        preferSyncedLyrics: preferSyncedLyrics,
      );
      debugPrint(
        '[AUTO_E2E] TAHAP_5: Header ID3v2.4 (APIC + Metadata + USLT) berhasil ditulis (${await tempOutputMp3.length()} bytes)',
      );

      // 4. Save final MP3 file to /storage/emulated/0/Music/{targetFolderName} (without any .lrc file)
      onProgress?.call(
        0.88,
        'Menyimpan file MP3 ke folder $targetFolderName...',
      );
      final savedFilePath = await _saveToTargetDirectory(
        tempOutputMp3,
        metadata.sanitizedFileName,
        targetFolderName: targetFolderName,
      );

      await FolderService().scanMediaFile(savedFilePath);

      final savedFile = File(savedFilePath);
      final savedSize = await savedFile.exists() ? await savedFile.length() : 0;
      debugPrint(
        '[AUTO_E2E] TAHAP_5: File MP3 BERHASIL disimpan di: $savedFilePath (ukuran: $savedSize bytes)',
      );

      onProgress?.call(1.0, 'Selesai! Tersimpan di: $savedFilePath');
      return savedFilePath;
    } on TaggingException {
      rethrow;
    } catch (e, s) {
      debugPrint('[AUTO_E2E] TAHAP_5: Exception saat konversi/tagging: $e\n$s');
      throw TaggingException('Gagal memproses konversi dan tagging MP3: $e');
    } finally {
      // Cleanup temporary files
      for (final file in [rawAudioFile, coverFile, tempOutputMp3]) {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
  }

  /// Re-tags an existing local MP3 file in-place without re-downloading or
  /// re-encoding the audio stream (`-c:a copy`), updates its ID3v2.4 header
  /// (`APIC`, `TIT2`, `TPE1`, `TALB`, `TDRC`, `USLT`), and triggers MediaScanner
  /// so Musicolet reflects the changes in under 1 second.
  Future<String> retagExistingMp3({
    required String filePath,
    required TrackMetadata updatedMetadata,
    required bool preferSyncedLyrics,
  }) async {
    final existingFile = File(filePath);
    if (!await existingFile.exists()) {
      throw const TaggingException('File MP3 lokal tidak ditemukan di perangkat.');
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final coverFile = File(
      '${tempDir.path}${Platform.pathSeparator}retag_cover_$timestamp.jpg',
    );
    final tempCopyMp3 = File(
      '${tempDir.path}${Platform.pathSeparator}retag_copy_$timestamp.mp3',
    );

    Uint8List? coverBytes;

    try {
      // 1. Try downloading cover art if URL is available; otherwise extract existing APIC
      if (updatedMetadata.coverUrl.trim().isNotEmpty) {
        try {
          await _dio
              .download(updatedMetadata.coverUrl, coverFile.path)
              .timeout(const Duration(seconds: 10));
          if (await coverFile.exists() && await coverFile.length() > 0) {
            coverBytes = await coverFile.readAsBytes();
          }
        } catch (_) {
          coverBytes = null;
        }
      }
      coverBytes ??= await _extractExistingApicJpegBytes(existingFile);

      // 2. Copy audio stream without re-encoding via FFmpeg (-c:a copy)
      final ffmpegArgs = <String>[
        '-y',
        '-i',
        existingFile.path,
        '-vn',
        '-map_metadata',
        '-1',
        '-c:a',
        'copy',
        '-write_id3v1',
        '0',
        tempCopyMp3.path,
      ];

      final session = await FFmpegKit.executeWithArguments(ffmpegArgs);
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode) ||
          !await tempCopyMp3.exists() ||
          await tempCopyMp3.length() <= 1024) {
        // Fallback: copy raw file directly if FFmpeg stream copy wasn't needed
        await existingFile.copy(tempCopyMp3.path);
      }

      // 3. Inject updated ID3v2.4.0 binary header (APIC + TIT2 + TPE1 + TALB + TDRC + USLT)
      await _writeCompleteId3v24Tag(
        mp3File: tempCopyMp3,
        metadata: updatedMetadata,
        coverBytes: coverBytes,
        preferSyncedLyrics: preferSyncedLyrics,
      );

      // 4. Write back to the target folder (updating filename if Artist/Title changed)
      final folderSvc = FolderService();
      final parentDir = existingFile.parent;
      final desiredPath =
          '${parentDir.path}${Platform.pathSeparator}${updatedMetadata.sanitizedFileName}';
      final updatedBytes = await tempCopyMp3.readAsBytes();

      String finalSavedPath = existingFile.path;
      if (desiredPath != existingFile.path) {
        final wroteRenamed = await folderSvc.writeBytesToMusicFile(
          desiredPath,
          updatedBytes,
        );
        if (wroteRenamed) {
          finalSavedPath = desiredPath;
          if (await existingFile.exists()) {
            await folderSvc.deleteLocalAudioFile(existingFile.path);
          }
          await folderSvc.scanMediaFile(desiredPath);
          return finalSavedPath;
        }
      }

      // Overwrite existing file path safely on Android 11-15 Scoped Storage
      final wroteInPlace = await folderSvc.writeBytesToMusicFile(
        existingFile.path,
        updatedBytes,
      );
      if (!wroteInPlace) {
        throw const TaggingException(
          'Gagal menyimpan tag ke file MP3. Izinkan akses file musik jika diminta oleh sistem.',
        );
      }
      finalSavedPath = existingFile.path;
      await folderSvc.scanMediaFile(finalSavedPath);
      return finalSavedPath;
    } finally {
      for (final f in [coverFile, tempCopyMp3]) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  /// Extracts existing JPEG bytes from an ID3v2 `APIC` frame if present so offline
  /// re-tagging preserves the embedded album cover even without internet.
  Future<Uint8List?> _extractExistingApicJpegBytes(File mp3File) async {
    try {
      final bytes = await mp3File.readAsBytes();
      if (bytes.length < 24 ||
          bytes[0] != 0x49 ||
          bytes[1] != 0x44 ||
          bytes[2] != 0x33) {
        return null;
      }
      final tagSize = ((bytes[6] & 0x7F) << 21) |
          ((bytes[7] & 0x7F) << 14) |
          ((bytes[8] & 0x7F) << 7) |
          (bytes[9] & 0x7F);
      final endOffset = (10 + tagSize) <= bytes.length ? (10 + tagSize) : bytes.length;
      for (int i = 10; i + 16 < endOffset; i++) {
        // Look for JPEG SOI marker FF D8 FF inside the ID3 tag area
        if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8 && bytes[i + 2] == 0xFF) {
          // Find EOI marker FF D9 before endOffset
          for (int j = endOffset - 2; j > i; j--) {
            if (bytes[j] == 0xFF && bytes[j + 1] == 0xD9) {
              return Uint8List.sublistView(bytes, i, j + 2);
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Writes a complete, clean `ID3v2.4.0` tag header at the beginning of [mp3File]
  /// with the exact binary structure used by Musicolet-verified MP3 files:
  /// - `ID3v2.4.0` header (`49 44 33 04 00 00` + 28-bit syncsafe tag size)
  /// - `APIC` frame (`0x03` UTF-8 + `"image/jpg\x00"` + `0x03` front cover + `0x00` + JPEG bytes)
  /// - `TALB` frame (`0x03` UTF-8 + album)
  /// - `TDRC` frame (`0x00` ISO-8859-1 + releaseYear)
  /// - `TIT2` frame (`0x03` UTF-8 + title)
  /// - `TPE1` frame (`0x03` UTF-8 + artist)
  /// - `TPE2` frame (`0x03` UTF-8 + artist)
  /// - `USLT` frame (`0x03` UTF-8 + `"eng"` + `0x00` + UTF-8 synced `[mm:ss.xx]` or plain lyrics)
  /// - `256` bytes of `0x00` padding
  Future<void> _writeCompleteId3v24Tag({
    required File mp3File,
    required TrackMetadata metadata,
    required Uint8List? coverBytes,
    bool preferSyncedLyrics = true,
  }) async {
    final rawBytes = await mp3File.readAsBytes();
    if (rawBytes.length < 10) return;

    // Strip any existing ID3v2 header written by FFmpeg so we start at pure MP3 audio frames
    int audioStartOffset = 0;
    if (rawBytes[0] == 0x49 && rawBytes[1] == 0x44 && rawBytes[2] == 0x33) {
      final existingTagSize = ((rawBytes[6] & 0x7F) << 21) |
          ((rawBytes[7] & 0x7F) << 14) |
          ((rawBytes[8] & 0x7F) << 7) |
          (rawBytes[9] & 0x7F);
      final candidateOffset = 10 + existingTagSize;
      if (candidateOffset <= rawBytes.length) {
        audioStartOffset = candidateOffset;
      }
    }

    final framesBuilder = BytesBuilder(copy: false);

    // 1. APIC frame (Cover Art)
    if (coverBytes != null && coverBytes.isNotEmpty) {
      framesBuilder.add(_buildId3v24ApicFrame(coverBytes));
    }

    // 2. TALB (Album)
    if (metadata.album.trim().isNotEmpty) {
      framesBuilder.add(
        _buildId3v24TextFrame('TALB', metadata.album.trim(), encodingByte: 0x03),
      );
    }

    // 3. TDRC (Recording Year)
    if (metadata.releaseYear.trim().isNotEmpty) {
      framesBuilder.add(
        _buildId3v24TextFrame(
          'TDRC',
          metadata.releaseYear.trim(),
          encodingByte: 0x00,
        ),
      );
    }

    // 4. TIT2 (Title)
    if (metadata.title.trim().isNotEmpty) {
      framesBuilder.add(
        _buildId3v24TextFrame('TIT2', metadata.title.trim(), encodingByte: 0x03),
      );
    }

    // 5. TPE1 (Artist) & TPE2 (Album Artist)
    if (metadata.artist.trim().isNotEmpty) {
      framesBuilder.add(
        _buildId3v24TextFrame('TPE1', metadata.artist.trim(), encodingByte: 0x03),
      );
      framesBuilder.add(
        _buildId3v24TextFrame('TPE2', metadata.artist.trim(), encodingByte: 0x03),
      );
    }

    // 6. USLT (UTF-8 lyrics frame: either synced [mm:ss.xx] or plain lyrics)
    final embeddedLyrics = metadata.lyricsForEmbedding(
      preferSyncedLyrics: preferSyncedLyrics,
    );
    if (embeddedLyrics != null && embeddedLyrics.trim().isNotEmpty) {
      framesBuilder.add(_buildId3v24UsltFrame(embeddedLyrics));
    }

    // 7. 256 bytes of zero padding
    framesBuilder.add(Uint8List(256));

    final allFramesAndPadding = framesBuilder.takeBytes();
    final int totalTagSize = allFramesAndPadding.length;

    // 10-byte ID3v2.4.0 header
    final id3Header = Uint8List(10);
    id3Header[0] = 0x49; // 'I'
    id3Header[1] = 0x44; // 'D'
    id3Header[2] = 0x33; // '3'
    id3Header[3] = 0x04; // Version 2.4
    id3Header[4] = 0x00; // Revision 0
    id3Header[5] = 0x00; // Flags 0
    _writeSyncsafeInt32(id3Header, 6, totalTagSize);

    final finalFileBuilder = BytesBuilder(copy: false);
    finalFileBuilder.add(id3Header);
    finalFileBuilder.add(allFramesAndPadding);
    finalFileBuilder.add(Uint8List.sublistView(rawBytes, audioStartOffset));

    await mp3File.writeAsBytes(finalFileBuilder.takeBytes(), flush: true);
  }

  /// Builds an ID3v2.4 `APIC` frame matching `03 69 6d 61 67 65 2f 6a 70 67 00 03 00` + JPEG bytes.
  Uint8List _buildId3v24ApicFrame(Uint8List imageBytes) {
    // Prefix: 0x03 (UTF-8) + "image/jpg\x00" (10 bytes) + 0x03 (Front Cover) + 0x00 (empty description) = 13 bytes
    const prefix = <int>[
      0x03,
      0x69, // 'i'
      0x6D, // 'm'
      0x61, // 'a'
      0x67, // 'g'
      0x65, // 'e'
      0x2F, // '/'
      0x6A, // 'j'
      0x70, // 'p'
      0x67, // 'g'
      0x00, // null terminator for MIME type
      0x03, // Picture type: Cover (front)
      0x00, // Empty description null terminator
    ];

    final int payloadSize = prefix.length + imageBytes.length;
    final frame = Uint8List(10 + payloadSize);

    // Frame ID: "APIC"
    frame[0] = 0x41;
    frame[1] = 0x50;
    frame[2] = 0x49;
    frame[3] = 0x43;
    _writeSyncsafeInt32(frame, 4, payloadSize);
    frame[8] = 0x00;
    frame[9] = 0x00;

    frame.setRange(10, 10 + prefix.length, prefix);
    frame.setRange(10 + prefix.length, 10 + payloadSize, imageBytes);
    return frame;
  }

  /// Builds an ID3v2.4 text frame (`TALB`, `TDRC`, `TIT2`, `TPE1`, `TPE2`).
  Uint8List _buildId3v24TextFrame(
    String frameId,
    String text, {
    required int encodingByte,
  }) {
    final textBytes = encodingByte == 0x00
        ? ascii.encode(text)
        : utf8.encode(text);
    final int payloadSize = 1 + textBytes.length;
    final frame = Uint8List(10 + payloadSize);

    frame[0] = frameId.codeUnitAt(0);
    frame[1] = frameId.codeUnitAt(1);
    frame[2] = frameId.codeUnitAt(2);
    frame[3] = frameId.codeUnitAt(3);
    _writeSyncsafeInt32(frame, 4, payloadSize);
    frame[8] = 0x00;
    frame[9] = 0x00;

    frame[10] = encodingByte;
    frame.setRange(11, 11 + textBytes.length, textBytes);
    return frame;
  }

  /// Builds an ID3v2.4 `USLT` frame matching `03 65 6e 67 00` + UTF-8 plain lyrics.
  Uint8List _buildId3v24UsltFrame(String plainLyrics) {
    final lyricsBytes = utf8.encode(plainLyrics);
    // Prefix: 0x03 (UTF-8) + 'e','n','g' (3 bytes) + 0x00 (empty content descriptor) = 5 bytes
    final int payloadSize = 5 + lyricsBytes.length;
    final frame = Uint8List(10 + payloadSize);

    // Frame ID: "USLT"
    frame[0] = 0x55; // 'U'
    frame[1] = 0x53; // 'S'
    frame[2] = 0x4C; // 'L'
    frame[3] = 0x54; // 'T'
    _writeSyncsafeInt32(frame, 4, payloadSize);
    frame[8] = 0x00;
    frame[9] = 0x00;

    frame[10] = 0x03; // Encoding: UTF-8
    frame[11] = 0x65; // 'e'
    frame[12] = 0x6E; // 'n'
    frame[13] = 0x67; // 'g'
    frame[14] = 0x00; // Empty content descriptor (null-terminated UTF-8 string)
    frame.setRange(15, 15 + lyricsBytes.length, lyricsBytes);
    return frame;
  }

  void _writeSyncsafeInt32(Uint8List buffer, int offset, int value) {
    buffer[offset] = (value >> 21) & 0x7F;
    buffer[offset + 1] = (value >> 14) & 0x7F;
    buffer[offset + 2] = (value >> 7) & 0x7F;
    buffer[offset + 3] = value & 0x7F;
  }

  Future<String> _saveToTargetDirectory(
    File sourceMp3,
    String fileName, {
    required String targetFolderName,
  }) async {
    final bytes = await sourceMp3.readAsBytes();
    final cleanFolder = FolderService().sanitizeFolderName(
      targetFolderName.trim().isNotEmpty ? targetFolderName : 'Music Barat',
    );

    Future<void> removeStaleCompanionLrc(String mp3Path) async {
      try {
        final lrcPath = mp3Path.endsWith('.mp3')
            ? '${mp3Path.substring(0, mp3Path.length - 4)}.lrc'
            : '$mp3Path.lrc';
        final lrcFile = File(lrcPath);
        if (await lrcFile.exists()) {
          await lrcFile.delete();
        }
      } catch (_) {}
    }

    if (Platform.isAndroid) {
      final folderSvc = FolderService();
      final baseName = fileName.endsWith('.mp3')
          ? fileName.substring(0, fileName.length - 4)
          : fileName;
      final baseNameLower = baseName.toLowerCase();
      final targetLower = fileName.toLowerCase();

      final publicDirs = [
        '${FolderService.baseMusicRoot}/$cleanFolder',
        '${FolderService.fallbackDownloadRoot}/$cleanFolder',
      ];

      for (final dirPath in publicDirs) {
        final dir = Directory(dirPath);
        final exactPath = '$dirPath/$fileName';

        // Purge any previous exact or suffixed duplicate MP3 in this folder
        // from both disk and Android MediaStore so Musicolet never plays a stale copy.
        try {
          if (await dir.exists()) {
            await for (final entity in dir.list(followLinks: false)) {
              if (entity is File) {
                final nameLower = entity.path
                    .split(Platform.pathSeparator)
                    .last
                    .toLowerCase();
                if (nameLower == targetLower ||
                    (nameLower.endsWith('.mp3') &&
                        nameLower.startsWith('$baseNameLower ('))) {
                  await folderSvc.deleteMediaFile(entity.path);
                  await removeStaleCompanionLrc(entity.path);
                }
              }
            }
          }
        } catch (_) {}

        // Attempt A: Write directly to exact filename
        try {
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          await folderSvc.deleteMediaFile(exactPath);
          final targetFile = File(exactPath);
          await targetFile.writeAsBytes(bytes, flush: true);
          if (await targetFile.exists() && await targetFile.length() > 0) {
            await removeStaleCompanionLrc(targetFile.path);
            return targetFile.path;
          }
        } catch (e) {
          debugPrint('[AUTO_E2E] TAHAP_5: Penulisan langsung ke $exactPath gagal ($e), mencoba nama unik Scoped Storage...');
        }

        // Attempt B: If overwriting an existing file from an older app UID was blocked
        // by Android 11-15 Scoped Storage FUSE, create a unique filename in the same folder
        try {
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          final uniqueSuffix =
              (DateTime.now().millisecondsSinceEpoch % 100000).toString();
          final uniquePath = '$dirPath/$baseName ($uniqueSuffix).mp3';
          final uniqueFile = File(uniquePath);
          await uniqueFile.writeAsBytes(bytes, flush: true);
          if (await uniqueFile.exists() && await uniqueFile.length() > 0) {
            await removeStaleCompanionLrc(uniqueFile.path);
            return uniqueFile.path;
          }
        } catch (e) {
          debugPrint('[AUTO_E2E] TAHAP_5: Penulisan nama unik ke $dirPath gagal: $e');
        }
      }
    }

    // Fallback 1: Application external storage directory (/storage/emulated/0/Android/data/.../files/SpotMeta)
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final spotMetaExtDir = Directory(
          '${extDir.path}${Platform.pathSeparator}SpotMeta',
        );
        if (!await spotMetaExtDir.exists()) {
          await spotMetaExtDir.create(recursive: true);
        }
        final fallbackPath =
            '${spotMetaExtDir.path}${Platform.pathSeparator}$fileName';
        final targetFile = File(fallbackPath);
        await targetFile.writeAsBytes(bytes, flush: true);
        await removeStaleCompanionLrc(targetFile.path);
        return targetFile.path;
      }
    } catch (e) {
      debugPrint('[AUTO_E2E] TAHAP_5: Fallback getExternalStorageDirectory gagal: $e');
    }

    // Fallback 2: Application documents directory
    final docsDir = await getApplicationDocumentsDirectory();
    final spotMetaDocsDir = Directory(
      '${docsDir.path}${Platform.pathSeparator}SpotMeta',
    );
    if (!await spotMetaDocsDir.exists()) {
      await spotMetaDocsDir.create(recursive: true);
    }
    final docsPath =
        '${spotMetaDocsDir.path}${Platform.pathSeparator}$fileName';
    final targetFile = File(docsPath);
    await targetFile.writeAsBytes(bytes, flush: true);
    await removeStaleCompanionLrc(targetFile.path);
    return targetFile.path;
  }
}

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

  /// Validates [bitrateKbps] so values outside `{128, 192, 320}` fall back to `320`.
  static int normalizeBitrateKbps(int bitrateKbps) {
    if (bitrateKbps == 128 || bitrateKbps == 192 || bitrateKbps == 320) {
      return bitrateKbps;
    }
    return 320;
  }

  /// Downloads high-res cover art, converts [rawAudioFile] to MP3 at [bitrateKbps]
  /// (`320`, `192`, or `128` kbps; defaults to `320`) via FFmpeg,
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
    int bitrateKbps = 320,
    void Function(double progress, String detail)? onProgress,
  }) async {
    final resolvedBitrate = normalizeBitrateKbps(bitrateKbps);
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

      // 2. Convert audio stream to MP3 using FFmpeg at the configured bitrate
      onProgress?.call(
        0.45,
        'Mengonversi audio ke MP3 ${resolvedBitrate}kbps...',
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
        '${resolvedBitrate}k',
        '-write_id3v1',
        '0',
        tempOutputMp3.path,
      ];

      debugPrint(
        '[AUTO_E2E] TAHAP_5: Menjalankan FFmpeg konversi MP3 ${resolvedBitrate}kbps...',
      );
      final session = await FFmpegKit.executeWithArguments(ffmpegArgs);
      final returnCode = await session.getReturnCode();
      final outputLog = (await session.getOutput()) ?? '';
      debugPrint('[AUTO_E2E] TAHAP_5: FFmpeg ReturnCode = $returnCode');

      if (!ReturnCode.isSuccess(returnCode) ||
          !await tempOutputMp3.exists() ||
          await tempOutputMp3.length() <= 10000) {
        debugPrint('[AUTO_E2E] TAHAP_5: FFmpeg gagal. Log:\n$outputLog');
        throw TaggingException(
          'FFmpeg gagal mengonversi audio ke MP3 ${resolvedBitrate}kbps. Log: $outputLog',
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

  /// Tags a Lossless `.flac` file without re-encoding (`-c:a copy`), embedding
  /// Vorbis Comments (`TITLE`, `ARTIST`, `ALBUM`, `DATE`, `LYRICS`,
  /// `UNSYNCEDLYRICS`) and `1000x1000` Album Cover Art (`METADATA_BLOCK_PICTURE`),
  /// and saves it with the `.flac` extension into [targetFolderName].
  Future<String> tagFlacAudio({
    required File rawFlacFile,
    required TrackMetadata metadata,
    String targetFolderName = 'Music Barat',
    bool preferSyncedLyrics = true,
    void Function(double progress, String detail)? onProgress,
  }) async {
    debugPrint(
      '[AUTO_E2E] TAHAP_5_FLAC: Memulai tagging FLAC lossless: ${rawFlacFile.path} (${await rawFlacFile.length()} bytes)',
    );
    await requestStoragePermissions();

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final coverFile = File(
      '${tempDir.path}${Platform.pathSeparator}cover_flac_$timestamp.jpg',
    );
    final tempOutputFlac = File(
      '${tempDir.path}${Platform.pathSeparator}output_$timestamp.flac',
    );

    Uint8List? coverBytes;

    try {
      // 1. Download high-res 1000x1000 cover art
      if (metadata.coverUrl.trim().isNotEmpty) {
        onProgress?.call(0.15, 'Mengunduh cover art resolusi tinggi...');
        try {
          await _dio
              .download(metadata.coverUrl, coverFile.path)
              .timeout(const Duration(seconds: 15));
          if (await coverFile.exists() && await coverFile.length() > 0) {
            coverBytes = await coverFile.readAsBytes();
          }
        } catch (_) {
          coverBytes = null;
        }
      }
      coverBytes ??= await _extractExistingFlacPictureBytes(rawFlacFile);

      // 2. Remux lossless FLAC audio stream via FFmpeg (-c:a copy, 100% bit-perfect)
      onProgress?.call(
        0.45,
        'Menyalin stream Hi-Res FLAC tanpa kompresi ulang (-c:a copy)...',
      );
      final embeddedLyrics = metadata.lyricsForEmbedding(
        preferSyncedLyrics: preferSyncedLyrics,
      );
      final ffmpegArgs = <String>[
        '-y',
        '-i',
        rawFlacFile.path,
        if (await coverFile.exists() && await coverFile.length() > 0) ...[
          '-i',
          coverFile.path,
          '-map',
          '0:a:0',
          '-map',
          '1:v:0',
          '-c:v',
          'copy',
          '-disposition:v:0',
          'attached_pic',
        ] else ...[
          '-map',
          '0:a:0',
        ],
        '-c:a',
        'copy',
        '-metadata',
        'TITLE=${metadata.title.trim()}',
        '-metadata',
        'ARTIST=${metadata.artist.trim()}',
        '-metadata',
        'ALBUM=${metadata.album.trim()}',
        if (metadata.releaseYear.trim().isNotEmpty) ...[
          '-metadata',
          'DATE=${metadata.releaseYear.trim()}',
        ],
        if (embeddedLyrics != null && embeddedLyrics.trim().isNotEmpty) ...[
          '-metadata',
          'LYRICS=$embeddedLyrics',
          '-metadata',
          'UNSYNCEDLYRICS=$embeddedLyrics',
        ],
        tempOutputFlac.path,
      ];

      bool remuxedOk = false;
      try {
        final session = await FFmpegKit.executeWithArguments(ffmpegArgs);
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode) &&
            await tempOutputFlac.exists() &&
            await tempOutputFlac.length() > 10000) {
          remuxedOk = true;
        }
      } catch (_) {}

      if (!remuxedOk) {
        await rawFlacFile.copy(tempOutputFlac.path);
      }

      // 3. Guarantee deterministic Vorbis Comments (TITLE, ARTIST, ALBUM, DATE,
      // LYRICS, UNSYNCEDLYRICS) & METADATA_BLOCK_PICTURE (type 6) in binary fLaC header
      onProgress?.call(
        0.75,
        'Menyuntikkan Vorbis Comments & Cover Art HD ke dalam FLAC...',
      );
      await writeCompleteFlacMetadataBlocks(
        flacFile: tempOutputFlac,
        metadata: metadata,
        coverBytes: coverBytes,
        preferSyncedLyrics: preferSyncedLyrics,
      );

      // 4. Save final .flac file to target folder
      onProgress?.call(
        0.88,
        'Menyimpan file FLAC ke folder $targetFolderName...',
      );
      final savedFilePath = await _saveToTargetDirectory(
        tempOutputFlac,
        metadata.sanitizedFlacFileName,
        targetFolderName: targetFolderName,
      );

      await FolderService().scanMediaFile(savedFilePath);
      onProgress?.call(1.0, 'Selesai! Tersimpan di: $savedFilePath');
      return savedFilePath;
    } on TaggingException {
      rethrow;
    } catch (e, s) {
      debugPrint('[AUTO_E2E] TAHAP_5_FLAC: Exception saat tagging FLAC: $e\n$s');
      throw TaggingException('Gagal memproses tagging FLAC: $e');
    } finally {
      for (final file in [rawFlacFile, coverFile, tempOutputFlac]) {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
  }

  /// Alias for [retagExistingMp3] that supports both `.mp3` and `.flac` files.
  Future<String> retagExistingAudio({
    required String filePath,
    required TrackMetadata updatedMetadata,
    required bool preferSyncedLyrics,
  }) =>
      retagExistingMp3(
        filePath: filePath,
        updatedMetadata: updatedMetadata,
        preferSyncedLyrics: preferSyncedLyrics,
      );

  /// Re-tags an existing local `.mp3` or `.flac` file in-place without
  /// re-downloading or re-encoding the audio stream (`-c:a copy`), updates its
  /// metadata & embedded lyrics/cover art, and triggers MediaScanner.
  Future<String> retagExistingMp3({
    required String filePath,
    required TrackMetadata updatedMetadata,
    required bool preferSyncedLyrics,
  }) async {
    if (filePath.trim().toLowerCase().endsWith('.flac')) {
      return _retagExistingFlac(
        filePath: filePath,
        updatedMetadata: updatedMetadata,
        preferSyncedLyrics: preferSyncedLyrics,
      );
    }

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

  Future<String> _retagExistingFlac({
    required String filePath,
    required TrackMetadata updatedMetadata,
    required bool preferSyncedLyrics,
  }) async {
    final existingFile = File(filePath);
    if (!await existingFile.exists()) {
      throw const TaggingException(
        'File FLAC lokal tidak ditemukan di perangkat.',
      );
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final coverFile = File(
      '${tempDir.path}${Platform.pathSeparator}retag_cover_flac_$timestamp.jpg',
    );
    final tempCopyFlac = File(
      '${tempDir.path}${Platform.pathSeparator}retag_copy_$timestamp.flac',
    );

    Uint8List? coverBytes;

    try {
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
      coverBytes ??= await _extractExistingFlacPictureBytes(existingFile);

      await existingFile.copy(tempCopyFlac.path);

      await writeCompleteFlacMetadataBlocks(
        flacFile: tempCopyFlac,
        metadata: updatedMetadata,
        coverBytes: coverBytes,
        preferSyncedLyrics: preferSyncedLyrics,
      );

      final folderSvc = FolderService();
      final parentDir = existingFile.parent;
      final desiredPath =
          '${parentDir.path}${Platform.pathSeparator}${updatedMetadata.sanitizedFlacFileName}';
      final updatedBytes = await tempCopyFlac.readAsBytes();

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

      final wroteInPlace = await folderSvc.writeBytesToMusicFile(
        existingFile.path,
        updatedBytes,
      );
      if (!wroteInPlace) {
        throw const TaggingException(
          'Gagal menyimpan tag ke file FLAC. Izinkan akses file musik jika diminta oleh sistem.',
        );
      }
      finalSavedPath = existingFile.path;
      await folderSvc.scanMediaFile(finalSavedPath);
      return finalSavedPath;
    } finally {
      for (final f in [coverFile, tempCopyFlac]) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  /// Extracts existing cover art bytes from a FLAC `METADATA_BLOCK_PICTURE`
  /// (block type `6`) if present.
  Future<Uint8List?> _extractExistingFlacPictureBytes(File flacFile) async {
    try {
      final bytes = await flacFile.readAsBytes();
      int offset = _findFlacMagicOffset(bytes);
      if (offset < 0 || offset + 4 > bytes.length) return null;
      offset += 4; // skip 'fLaC'

      while (offset + 4 <= bytes.length) {
        final headerByte = bytes[offset];
        final isLast = (headerByte & 0x80) != 0;
        final blockType = headerByte & 0x7F;
        final blockLen =
            (bytes[offset + 1] << 16) |
            (bytes[offset + 2] << 8) |
            bytes[offset + 3];
        offset += 4;
        if (blockLen < 0 || offset + blockLen > bytes.length) break;

        if (blockType == 6 && blockLen > 32) {
          // METADATA_BLOCK_PICTURE (big-endian)
          int p = offset + 4; // skip picture type
          final mimeLen = _readBigEndianUint32(bytes, p);
          p += 4 + mimeLen;
          if (p + 4 <= offset + blockLen) {
            final descLen = _readBigEndianUint32(bytes, p);
            p += 4 + descLen + 16; // skip width, height, depth, colors (4 * 4)
            if (p + 4 <= offset + blockLen) {
              final dataLen = _readBigEndianUint32(bytes, p);
              p += 4;
              if (dataLen > 0 && p + dataLen <= offset + blockLen) {
                return Uint8List.sublistView(bytes, p, p + dataLen);
              }
            }
          }
        }

        offset += blockLen;
        if (isLast) break;
      }
    } catch (_) {}
    return null;
  }

  static int _findFlacMagicOffset(Uint8List bytes) {
    if (bytes.length < 4) return -1;
    int offset = 0;
    if (bytes.length >= 10 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      final id3Size =
          ((bytes[6] & 0x7F) << 21) |
          ((bytes[7] & 0x7F) << 14) |
          ((bytes[8] & 0x7F) << 7) |
          (bytes[9] & 0x7F);
      final afterId3 = 10 + id3Size;
      if (afterId3 + 4 <= bytes.length) {
        offset = afterId3;
      }
    }
    if (offset + 4 <= bytes.length &&
        bytes[offset] == 0x66 &&
        bytes[offset + 1] == 0x4C &&
        bytes[offset + 2] == 0x61 &&
        bytes[offset + 3] == 0x43) {
      return offset;
    }
    return -1;
  }

  /// Writes deterministic, standards-compliant FLAC metadata blocks:
  /// - Preserves `STREAMINFO` (block `0`) and any `APPLICATION`/`SEEKTABLE`/`CUESHEET`
  /// - Replaces `VORBIS_COMMENT` (block `4`) with UTF-8 `TITLE`, `ARTIST`,
  ///   `ALBUM`, `DATE`, `YEAR`, `LYRICS`, and `UNSYNCEDLYRICS`
  /// - Replaces `PICTURE` (block `6`) with [coverBytes] (`Front Cover`)
  /// - Copies all lossless FLAC audio frames bit-for-bit without re-encoding.
  Future<void> writeCompleteFlacMetadataBlocks({
    required File flacFile,
    required TrackMetadata metadata,
    required Uint8List? coverBytes,
    bool preferSyncedLyrics = true,
  }) async {
    final rawBytes = await flacFile.readAsBytes();
    final flacMagicOffset = _findFlacMagicOffset(rawBytes);
    if (flacMagicOffset < 0) return;

    int offset = flacMagicOffset + 4; // right after 'fLaC'
    final retainedBlocks = <_FlacMetadataBlock>[];

    while (offset + 4 <= rawBytes.length) {
      final headerByte = rawBytes[offset];
      final isLast = (headerByte & 0x80) != 0;
      final blockType = headerByte & 0x7F;
      final blockLen =
          (rawBytes[offset + 1] << 16) |
          (rawBytes[offset + 2] << 8) |
          rawBytes[offset + 3];
      offset += 4;
      if (blockLen < 0 || offset + blockLen > rawBytes.length) {
        return;
      }

      // Keep STREAMINFO (0), APPLICATION (2), SEEKTABLE (3), CUESHEET (5).
      // Replace VORBIS_COMMENT (4), PICTURE (6), and PADDING (1).
      if (blockType == 0 ||
          blockType == 2 ||
          blockType == 3 ||
          blockType == 5) {
        retainedBlocks.add(
          _FlacMetadataBlock(
            blockType: blockType,
            payload: Uint8List.sublistView(
              rawBytes,
              offset,
              offset + blockLen,
            ),
          ),
        );
      }

      offset += blockLen;
      if (isLast) break;
    }

    if (retainedBlocks.isEmpty || retainedBlocks.first.blockType != 0) {
      return;
    }

    final audioFramesStartOffset = offset;

    // Build Vorbis Comment block (blockType = 4)
    final vorbisPayload = _buildFlacVorbisCommentPayload(
      metadata: metadata,
      preferSyncedLyrics: preferSyncedLyrics,
    );
    retainedBlocks.add(
      _FlacMetadataBlock(blockType: 4, payload: vorbisPayload),
    );

    // Build Picture block (blockType = 6) if coverBytes is available and fits in 24-bit block length
    if (coverBytes != null &&
        coverBytes.isNotEmpty &&
        coverBytes.length < 15 * 1024 * 1024) {
      final picPayload = _buildFlacPicturePayload(coverBytes);
      if (picPayload.length < 0xFFFFFF) {
        retainedBlocks.add(
          _FlacMetadataBlock(blockType: 6, payload: picPayload),
        );
      }
    }

    final out = BytesBuilder(copy: false);
    // 'fLaC' magic header
    out.add(const <int>[0x66, 0x4C, 0x61, 0x43]);

    for (int i = 0; i < retainedBlocks.length; i++) {
      final blk = retainedBlocks[i];
      final isLast = i == retainedBlocks.length - 1;
      final len = blk.payload.length;
      final header = Uint8List(4);
      header[0] = (isLast ? 0x80 : 0x00) | (blk.blockType & 0x7F);
      header[1] = (len >> 16) & 0xFF;
      header[2] = (len >> 8) & 0xFF;
      header[3] = len & 0xFF;
      out.add(header);
      out.add(blk.payload);
    }

    // Append untouched lossless FLAC audio frames
    if (audioFramesStartOffset < rawBytes.length) {
      out.add(Uint8List.sublistView(rawBytes, audioFramesStartOffset));
    }

    await flacFile.writeAsBytes(out.takeBytes(), flush: true);
  }

  Uint8List _buildFlacVorbisCommentPayload({
    required TrackMetadata metadata,
    required bool preferSyncedLyrics,
  }) {
    final comments = <String>[];
    if (metadata.title.trim().isNotEmpty) {
      comments.add('TITLE=${metadata.title.trim()}');
    }
    if (metadata.artist.trim().isNotEmpty) {
      comments.add('ARTIST=${metadata.artist.trim()}');
      comments.add('ALBUMARTIST=${metadata.artist.trim()}');
    }
    if (metadata.album.trim().isNotEmpty) {
      comments.add('ALBUM=${metadata.album.trim()}');
    }
    if (metadata.releaseYear.trim().isNotEmpty) {
      comments.add('DATE=${metadata.releaseYear.trim()}');
      comments.add('YEAR=${metadata.releaseYear.trim()}');
    }

    final embeddedLyrics = metadata.lyricsForEmbedding(
      preferSyncedLyrics: preferSyncedLyrics,
    );
    if (embeddedLyrics != null && embeddedLyrics.trim().isNotEmpty) {
      comments.add('LYRICS=$embeddedLyrics');
      comments.add('UNSYNCEDLYRICS=$embeddedLyrics');
    }

    final vendorBytes = utf8.encode('MusEvee v4.9');
    final encodedComments = comments.map((c) => utf8.encode(c)).toList();

    final out = BytesBuilder(copy: false);
    out.add(_littleEndianUint32Bytes(vendorBytes.length));
    out.add(vendorBytes);
    out.add(_littleEndianUint32Bytes(encodedComments.length));
    for (final cBytes in encodedComments) {
      out.add(_littleEndianUint32Bytes(cBytes.length));
      out.add(cBytes);
    }
    return out.takeBytes();
  }

  Uint8List _buildFlacPicturePayload(Uint8List imageBytes) {
    final isPng = imageBytes.length >= 4 &&
        imageBytes[0] == 0x89 &&
        imageBytes[1] == 0x50 &&
        imageBytes[2] == 0x4E &&
        imageBytes[3] == 0x47;
    final mimeBytes = ascii.encode(isPng ? 'image/png' : 'image/jpeg');

    final out = BytesBuilder(copy: false);
    out.add(_bigEndianUint32Bytes(3)); // Picture type 3: Cover (front)
    out.add(_bigEndianUint32Bytes(mimeBytes.length));
    out.add(mimeBytes);
    out.add(_bigEndianUint32Bytes(0)); // Empty description
    out.add(_bigEndianUint32Bytes(1000)); // Width
    out.add(_bigEndianUint32Bytes(1000)); // Height
    out.add(_bigEndianUint32Bytes(24)); // Color depth
    out.add(_bigEndianUint32Bytes(0)); // Indexed colors (0 for JPEG/PNG)
    out.add(_bigEndianUint32Bytes(imageBytes.length));
    out.add(imageBytes);
    return out.takeBytes();
  }

  static Uint8List _littleEndianUint32Bytes(int value) {
    final b = Uint8List(4);
    b[0] = value & 0xFF;
    b[1] = (value >> 8) & 0xFF;
    b[2] = (value >> 16) & 0xFF;
    b[3] = (value >> 24) & 0xFF;
    return b;
  }

  static Uint8List _bigEndianUint32Bytes(int value) {
    final b = Uint8List(4);
    b[0] = (value >> 24) & 0xFF;
    b[1] = (value >> 16) & 0xFF;
    b[2] = (value >> 8) & 0xFF;
    b[3] = value & 0xFF;
    return b;
  }

  static int _readBigEndianUint32(Uint8List buf, int offset) {
    return ((buf[offset] & 0xFF) << 24) |
        ((buf[offset + 1] & 0xFF) << 16) |
        ((buf[offset + 2] & 0xFF) << 8) |
        (buf[offset + 3] & 0xFF);
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
    File sourceAudio,
    String fileName, {
    required String targetFolderName,
  }) async {
    final bytes = await sourceAudio.readAsBytes();
    final cleanFolder = FolderService().sanitizeFolderName(
      targetFolderName.trim().isNotEmpty ? targetFolderName : 'Music Barat',
    );
    final isFlac = fileName.toLowerCase().endsWith('.flac');
    final extWithDot = isFlac ? '.flac' : '.mp3';

    Future<void> removeStaleCompanionLrc(String audioPath) async {
      try {
        final stem = FolderService.stripAudioExtension(audioPath);
        final lrcFile = File('$stem.lrc');
        if (await lrcFile.exists()) {
          await lrcFile.delete();
        }
      } catch (_) {}
    }

    if (Platform.isAndroid) {
      final folderSvc = FolderService();
      final baseName = FolderService.stripAudioExtension(fileName);
      final baseNameLower = baseName.toLowerCase();
      final targetLower = fileName.toLowerCase();

      final primaryTargetDir = folderSvc.resolveFolderDirectoryPath(
        targetFolderName.trim().isNotEmpty ? targetFolderName : 'Music Barat',
      );
      final publicDirs = <String>[
        primaryTargetDir,
        '${FolderService.fallbackDownloadRoot}/$cleanFolder',
      ];

      for (final dirPath in publicDirs) {
        final dir = Directory(dirPath);
        final exactPath = '$dirPath/$fileName';

        // Purge any previous exact or suffixed duplicate audio file in this folder
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
                    (nameLower.endsWith(extWithDot) &&
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
          final uniquePath = '$dirPath/$baseName ($uniqueSuffix)$extWithDot';
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

class _FlacMetadataBlock {
  final int blockType;
  final Uint8List payload;

  const _FlacMetadataBlock({
    required this.blockType,
    required this.payload,
  });
}

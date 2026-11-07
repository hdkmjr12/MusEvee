package com.example.spotmeta_downloader

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.media.MediaScannerConnection
import android.media.audiofx.AudioEffect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.charset.Charset
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "com.spotmeta.downloader/system"
    private var methodChannel: MethodChannel? = null
    private var pendingSharedText: String? = null

    // 30s Preview MediaPlayer (Downloader feature)
    private var previewPlayer: MediaPlayer? = null
    private var currentPreviewUrl: String? = null

    // Primary Local Music MediaPlayer (Musicolet player engine)
    private var localPlayer: MediaPlayer? = null
    private var currentLocalPath: String? = null
    private var isLocalPrepared: Boolean = false

    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()

    private val positionTicker = object : Runnable {
        override fun run() {
            val mp = localPlayer
            if (mp != null && isLocalPrepared) {
                try {
                    if (mp.isPlaying) {
                        val pos = mp.currentPosition
                        val dur = mp.duration
                        methodChannel?.invokeMethod(
                            "onLocalPosition",
                            mapOf(
                                "positionMs" to pos,
                                "durationMs" to dur,
                                "isPlaying" to true,
                                "path" to currentLocalPath
                            )
                        )
                        mainHandler.postDelayed(this, 200L)
                        return
                    }
                } catch (_: Exception) {
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        extractSharedTextFromIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // =============================================================
                // EXISTING DOWNLOADER NATIVE HANDLERS (100% PRESERVED)
                // =============================================================
                "scanMediaFile" -> {
                    val path = call.argument<String>("path")
                    if (!path.isNullOrBlank()) {
                        MediaScannerConnection.scanFile(
                            applicationContext,
                            arrayOf(path),
                            arrayOf("audio/mpeg"),
                            null
                        )
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "deleteMediaFile" -> {
                    val path = call.argument<String>("path")
                    if (!path.isNullOrBlank()) {
                        if (currentLocalPath == path) {
                            stopLocalAudio(notifyFlutter = true)
                        }
                        var deleted = false
                        try {
                            val f = File(path)
                            if (f.exists() && f.delete()) {
                                deleted = true
                            }
                        } catch (_: Exception) {
                        }
                        try {
                            val rows = applicationContext.contentResolver.delete(
                                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                                "${MediaStore.MediaColumns.DATA} = ?",
                                arrayOf(path)
                            )
                            if (rows > 0) deleted = true
                        } catch (_: Exception) {
                        }
                        try {
                            MediaScannerConnection.scanFile(
                                applicationContext,
                                arrayOf(path),
                                null,
                                null
                            )
                        } catch (_: Exception) {
                        }
                        result.success(deleted)
                    } else {
                        result.success(false)
                    }
                }
                "getInitialSharedText" -> {
                    val text = pendingSharedText
                    pendingSharedText = null
                    result.success(text)
                }
                "playPreviewUrl" -> {
                    val url = call.argument<String>("url")?.trim()
                    if (url.isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        // Pause local player gently so 30s preview doesn't overlap
                        pauseLocalAudioIfPlaying()
                        playPreviewAudio(url, result)
                    }
                }
                "stopPreview" -> {
                    stopPreviewAudio(notifyFlutter = true)
                    result.success(true)
                }
                "isPreviewPlaying" -> {
                    val playing = try {
                        previewPlayer?.isPlaying == true
                    } catch (_: Exception) {
                        false
                    }
                    result.success(playing)
                }

                // =============================================================
                // MUSICOLET LOCAL AUDIO PLAYER ENGINE
                // =============================================================
                "localPlayFile" -> {
                    val path = call.argument<String>("path")?.trim()
                    val startPositionMs = call.argument<Int>("positionMs") ?: 0
                    if (path.isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        playLocalAudioFile(path, startPositionMs, result)
                    }
                }
                "localPause" -> {
                    pauseLocalAudio()
                    result.success(true)
                }
                "localResume" -> {
                    val resumed = resumeLocalAudio()
                    result.success(resumed)
                }
                "localSeekTo" -> {
                    val positionMs = call.argument<Int>("positionMs") ?: 0
                    val ok = seekLocalAudio(positionMs)
                    result.success(ok)
                }
                "localStop" -> {
                    stopLocalAudio(notifyFlutter = true)
                    result.success(true)
                }
                "getVolume" -> {
                    val audioManager =
                        applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                    if (audioManager != null) {
                        val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            .coerceAtLeast(1)
                        result.success(current.toDouble() / max.toDouble())
                    } else {
                        result.success(0.8)
                    }
                }
                "setVolume" -> {
                    val normalized = (call.argument<Double>("volume") ?: 0.8).coerceIn(0.0, 1.0)
                    val audioManager =
                        applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                    if (audioManager != null) {
                        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            .coerceAtLeast(1)
                        val target = Math.round(normalized * max).toInt().coerceIn(0, max)
                        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
                    }
                    try {
                        val gain = normalized.toFloat().coerceIn(0f, 1f)
                        localPlayer?.setVolume(gain, gain)
                    } catch (_: Exception) {
                    }
                    result.success(true)
                }
                "openEqualizer" -> {
                    val opened = launchSystemEqualizer()
                    result.success(opened)
                }

                // =============================================================
                // LOCAL MUSIC SCANNER + MEDIAMETADATARETRIEVER + ID3v2 USLT/APIC
                // =============================================================
                "scanLocalMusicLibrary" -> {
                    val requestedFolders = call.argument<List<String>>("folders")
                    ioExecutor.execute {
                        try {
                            val tracks = scanLocalLibraryInternal(requestedFolders)
                            mainHandler.post { result.success(tracks) }
                        } catch (e: Exception) {
                            mainHandler.post { result.success(emptyList<Map<String, Any?>>()) }
                        }
                    }
                }
                "readLocalTrackDetails" -> {
                    val path = call.argument<String>("path")?.trim()
                    if (path.isNullOrEmpty()) {
                        result.success(null)
                    } else {
                        ioExecutor.execute {
                            try {
                                val file = File(path)
                                val details = if (file.exists() && file.isFile) {
                                    extractTrackMetadataMap(file)
                                } else {
                                    null
                                }
                                mainHandler.post { result.success(details) }
                            } catch (_: Exception) {
                                mainHandler.post { result.success(null) }
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // =========================================================================
    // 30s PREVIEW AUDIO IMPLEMENTATION
    // =========================================================================
    private fun playPreviewAudio(url: String, result: MethodChannel.Result) {
        try {
            stopPreviewAudio(notifyFlutter = false)
            currentPreviewUrl = url

            val player = MediaPlayer()
            previewPlayer = player

            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .build()
            )
            player.setDataSource(url)
            player.setOnPreparedListener { mp ->
                try {
                    mp.start()
                    methodChannel?.invokeMethod(
                        "onPreviewStateChanged",
                        mapOf("isPlaying" to true, "url" to url)
                    )
                } catch (_: Exception) {
                    stopPreviewAudio(notifyFlutter = true)
                }
            }
            player.setOnCompletionListener {
                stopPreviewAudio(notifyFlutter = true)
            }
            player.setOnErrorListener { _, _, _ ->
                stopPreviewAudio(notifyFlutter = true)
                true
            }
            player.prepareAsync()
            result.success(true)
        } catch (_: Exception) {
            stopPreviewAudio(notifyFlutter = true)
            result.success(false)
        }
    }

    private fun stopPreviewAudio(notifyFlutter: Boolean) {
        val player = previewPlayer
        previewPlayer = null
        currentPreviewUrl = null
        if (player != null) {
            try {
                if (player.isPlaying) {
                    player.stop()
                }
            } catch (_: Exception) {
            }
            try {
                player.reset()
                player.release()
            } catch (_: Exception) {
            }
        }
        if (notifyFlutter) {
            methodChannel?.invokeMethod(
                "onPreviewStateChanged",
                mapOf("isPlaying" to false, "url" to null)
            )
        }
    }

    // =========================================================================
    // LOCAL MUSIC PLAYER ENGINE IMPLEMENTATION
    // =========================================================================
    private fun playLocalAudioFile(
        path: String,
        startPositionMs: Int,
        result: MethodChannel.Result
    ) {
        val file = File(path)
        if (!file.exists()) {
            result.success(false)
            return
        }

        stopPreviewAudio(notifyFlutter = true)
        stopLocalAudio(notifyFlutter = false)

        try {
            val player = MediaPlayer()
            localPlayer = player
            currentLocalPath = path
            isLocalPrepared = false

            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .build()
            )
            player.setDataSource(path)
            player.setOnPreparedListener { mp ->
                isLocalPrepared = true
                try {
                    if (startPositionMs > 0 && startPositionMs < mp.duration) {
                        mp.seekTo(startPositionMs)
                    }
                    mp.start()
                    notifyLocalPlayerState(isPlaying = true)
                    startPositionTicker()
                } catch (_: Exception) {
                    stopLocalAudio(notifyFlutter = true)
                }
            }
            player.setOnCompletionListener { mp ->
                stopPositionTicker()
                val completedPath = currentLocalPath
                val dur = try {
                    mp.duration
                } catch (_: Exception) {
                    0
                }
                methodChannel?.invokeMethod(
                    "onLocalTrackCompleted",
                    mapOf(
                        "path" to completedPath,
                        "durationMs" to dur
                    )
                )
            }
            player.setOnErrorListener { _, _, _ ->
                stopLocalAudio(notifyFlutter = true)
                true
            }
            player.prepareAsync()
            result.success(true)
        } catch (_: Exception) {
            stopLocalAudio(notifyFlutter = true)
            result.success(false)
        }
    }

    private fun pauseLocalAudioIfPlaying() {
        val mp = localPlayer ?: return
        try {
            if (isLocalPrepared && mp.isPlaying) {
                mp.pause()
                stopPositionTicker()
                notifyLocalPlayerState(isPlaying = false)
            }
        } catch (_: Exception) {
        }
    }

    private fun pauseLocalAudio() {
        val mp = localPlayer ?: return
        try {
            if (isLocalPrepared && mp.isPlaying) {
                mp.pause()
            }
        } catch (_: Exception) {
        }
        stopPositionTicker()
        notifyLocalPlayerState(isPlaying = false)
    }

    private fun resumeLocalAudio(): Boolean {
        val mp = localPlayer ?: return false
        if (!isLocalPrepared) return false
        return try {
            stopPreviewAudio(notifyFlutter = true)
            if (!mp.isPlaying) {
                mp.start()
            }
            notifyLocalPlayerState(isPlaying = true)
            startPositionTicker()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun seekLocalAudio(positionMs: Int): Boolean {
        val mp = localPlayer ?: return false
        if (!isLocalPrepared) return false
        return try {
            val dur = mp.duration
            val clamped = if (dur > 0) positionMs.coerceIn(0, dur) else positionMs.coerceAtLeast(0)
            mp.seekTo(clamped)
            methodChannel?.invokeMethod(
                "onLocalPosition",
                mapOf(
                    "positionMs" to clamped,
                    "durationMs" to dur,
                    "isPlaying" to mp.isPlaying,
                    "path" to currentLocalPath
                )
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun stopLocalAudio(notifyFlutter: Boolean) {
        stopPositionTicker()
        val mp = localPlayer
        localPlayer = null
        isLocalPrepared = false
        val prevPath = currentLocalPath
        currentLocalPath = null
        if (mp != null) {
            try {
                if (mp.isPlaying) {
                    mp.stop()
                }
            } catch (_: Exception) {
            }
            try {
                mp.reset()
                mp.release()
            } catch (_: Exception) {
            }
        }
        if (notifyFlutter) {
            methodChannel?.invokeMethod(
                "onLocalPlayerState",
                mapOf(
                    "isPlaying" to false,
                    "path" to prevPath,
                    "positionMs" to 0,
                    "durationMs" to 0,
                    "audioSessionId" to 0
                )
            )
        }
    }

    private fun notifyLocalPlayerState(isPlaying: Boolean) {
        val mp = localPlayer
        val pos = try {
            if (mp != null && isLocalPrepared) mp.currentPosition else 0
        } catch (_: Exception) {
            0
        }
        val dur = try {
            if (mp != null && isLocalPrepared) mp.duration else 0
        } catch (_: Exception) {
            0
        }
        val sessionId = try {
            mp?.audioSessionId ?: 0
        } catch (_: Exception) {
            0
        }
        methodChannel?.invokeMethod(
            "onLocalPlayerState",
            mapOf(
                "isPlaying" to isPlaying,
                "path" to currentLocalPath,
                "positionMs" to pos,
                "durationMs" to dur,
                "audioSessionId" to sessionId
            )
        )
    }

    private fun startPositionTicker() {
        mainHandler.removeCallbacks(positionTicker)
        mainHandler.post(positionTicker)
    }

    private fun stopPositionTicker() {
        mainHandler.removeCallbacks(positionTicker)
    }

    @Suppress("DEPRECATION")
    private fun launchSystemEqualizer(): Boolean {
        return try {
            val sessionId = try {
                localPlayer?.audioSessionId ?: 0
            } catch (_: Exception) {
                0
            }
            val eqIntent = Intent(AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL).apply {
                putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId)
                putExtra(AudioEffect.EXTRA_PACKAGE_NAME, packageName)
                putExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC)
            }
            if (eqIntent.resolveActivity(packageManager) != null) {
                startActivityForResult(eqIntent, 1099)
                true
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    // =========================================================================
    // LOCAL LIBRARY SCANNER & ID3v2 (USLT + APIC) METADATA EXTRACTOR
    // =========================================================================
    private fun scanLocalLibraryInternal(requestedFolders: List<String>?): List<Map<String, Any?>> {
        val audioExtensions = setOf("mp3", "m4a", "flac", "wav", "ogg", "aac", "opus")
        val discoveredFiles = LinkedHashMap<String, File>()

        val musicRoot = File("/storage/emulated/0/Music")
        val downloadRoot = File("/storage/emulated/0/Download")

        // 1. Scan prioritized folders first (Music Barat, Music Japan, Music Random, etc.)
        val baseFolders = requestedFolders?.takeIf { it.isNotEmpty() }
            ?: listOf("Music Barat", "Music Japan", "Music Random")
        for (folderName in baseFolders) {
            val dir = File(musicRoot, folderName)
            collectAudioFilesRecursively(dir, audioExtensions, discoveredFiles, maxDepth = 3)
            val dlDir = File(downloadRoot, folderName)
            collectAudioFilesRecursively(dlDir, audioExtensions, discoveredFiles, maxDepth = 2)
        }

        // 2. Scan remaining subdirectories in /storage/emulated/0/Music
        collectAudioFilesRecursively(musicRoot, audioExtensions, discoveredFiles, maxDepth = 4)

        // 3. Supplement via MediaStore query for any audio files under /Music or /SpotMeta
        try {
            val projection = arrayOf(MediaStore.MediaColumns.DATA)
            applicationContext.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"
            )?.use { cursor ->
                val dataCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                if (dataCol >= 0) {
                    while (cursor.moveToNext()) {
                        val rawPath = cursor.getString(dataCol) ?: continue
                        if (rawPath.contains("/Music/", ignoreCase = true) ||
                            rawPath.contains("/SpotMeta/", ignoreCase = true)
                        ) {
                            val f = File(rawPath)
                            if (f.exists() && f.isFile && f.length() > 1024L) {
                                discoveredFiles.putIfAbsent(f.absolutePath, f)
                            }
                        }
                    }
                }
            }
        } catch (_: Exception) {
        }

        val results = ArrayList<Map<String, Any?>>(discoveredFiles.size)
        for (file in discoveredFiles.values) {
            try {
                results.add(extractTrackMetadataMap(file))
            } catch (_: Exception) {
            }
        }
        return results
    }

    private fun collectAudioFilesRecursively(
        dir: File,
        extensions: Set<String>,
        out: LinkedHashMap<String, File>,
        maxDepth: Int
    ) {
        if (maxDepth < 0 || !dir.exists() || !dir.isDirectory) return
        val children = try {
            dir.listFiles()
        } catch (_: Exception) {
            null
        } ?: return

        for (child in children) {
            if (child.name.startsWith(".")) continue
            if (child.isFile) {
                val ext = child.extension.lowercase()
                if (extensions.contains(ext) && child.length() > 1024L) {
                    out.putIfAbsent(child.absolutePath, child)
                }
            } else if (child.isDirectory && maxDepth > 0) {
                collectAudioFilesRecursively(child, extensions, out, maxDepth - 1)
            }
        }
    }

    private data class ParsedId3Tags(
        val title: String?,
        val artist: String?,
        val album: String?,
        val year: String?,
        val usltLyrics: String?,
        val apicBytes: ByteArray?
    )

    private fun extractTrackMetadataMap(file: File): Map<String, Any?> {
        var mmrTitle: String? = null
        var mmrArtist: String? = null
        var mmrAlbum: String? = null
        var mmrYear: String? = null
        var durationMs = 0L
        var bitrateBps = 0L
        var sampleRateHz = 0
        var embeddedCover: ByteArray? = null

        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            mmrTitle = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)?.trim()
            mmrArtist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)?.trim()
                ?: retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)?.trim()
            mmrAlbum = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)?.trim()
            mmrYear = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR)?.trim()
                ?: retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DATE)?.trim()
            durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            bitrateBps = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)
                ?.toLongOrNull() ?: 0L
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                sampleRateHz = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_SAMPLERATE
                )?.toIntOrNull() ?: 44100
            } else {
                sampleRateHz = 44100
            }
            embeddedCover = retriever.embeddedPicture
        } catch (_: Exception) {
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }

        // Parse binary ID3v2 header for USLT lyrics and fallback text/APIC frames
        val id3 = parseId3v2Tags(file, needApic = (embeddedCover == null))
        val coverBytes = embeddedCover ?: id3.apicBytes

        // Fallback filename parser ("Artist - Title.mp3")
        val baseName = file.nameWithoutExtension.trim()
        var fallbackArtist = "Unknown Artist"
        var fallbackTitle = baseName
        val dashIdx = baseName.indexOf(" - ")
        if (dashIdx > 0 && dashIdx + 3 < baseName.length) {
            fallbackArtist = baseName.substring(0, dashIdx).trim()
            fallbackTitle = baseName.substring(dashIdx + 3).trim()
        }

        val resolvedTitle = listOf(id3.title, mmrTitle)
            .firstOrNull { !it.isNullOrBlank() } ?: fallbackTitle
        val resolvedArtist = listOf(id3.artist, mmrArtist)
            .firstOrNull { !it.isNullOrBlank() } ?: fallbackArtist
        val resolvedAlbum = listOf(id3.album, mmrAlbum)
            .firstOrNull { !it.isNullOrBlank() } ?: (file.parentFile?.name ?: "Unknown Album")
        val rawYear = listOf(id3.year, mmrYear).firstOrNull { !it.isNullOrBlank() } ?: ""
        val resolvedYear = Regex("""\b(19|20)\d{2}\b""").find(rawYear)?.value ?: rawYear.take(4)

        var coverFilePath: String? = null
        var dominantColor = 0xFF1E222B.toInt()

        if (coverBytes != null && coverBytes.isNotEmpty()) {
            val coversDir = File(applicationContext.cacheDir, "covers")
            if (!coversDir.exists()) {
                coversDir.mkdirs()
            }
            val safeHash = file.absolutePath.hashCode().toUInt().toString(16)
            val cachedCover = File(coversDir, "cov_${safeHash}_${file.lastModified()}.jpg")
            try {
                if (!cachedCover.exists() || cachedCover.length() == 0L) {
                    cachedCover.writeBytes(coverBytes)
                }
                coverFilePath = cachedCover.absolutePath
            } catch (_: Exception) {
            }
            dominantColor = computeDominantAmbientColor(coverBytes)
        }

        val folderName = file.parentFile?.name ?: "Music"
        val bitrateKbps = if (bitrateBps > 0) (bitrateBps / 1000L).toInt() else 320

        return mapOf(
            "filePath" to file.absolutePath,
            "fileName" to file.name,
            "folderName" to folderName,
            "title" to resolvedTitle,
            "artist" to resolvedArtist,
            "album" to resolvedAlbum,
            "year" to resolvedYear,
            "durationMs" to durationMs,
            "sizeBytes" to file.length(),
            "bitrateKbps" to bitrateKbps,
            "sampleRateHz" to sampleRateHz,
            "coverFilePath" to coverFilePath,
            "usltLyrics" to id3.usltLyrics,
            "dominantColor" to dominantColor,
            "lastModifiedMs" to file.lastModified()
        )
    }

    /**
     * Reads ONLY the ID3v2 header region of an MP3 file via RandomAccessFile
     * and extracts `USLT` (UTF-8 / UTF-16 / UTF-16BE / ISO-8859-1), text frames,
     * and optional `APIC` image bytes.
     */
    private fun parseId3v2Tags(file: File, needApic: Boolean): ParsedId3Tags {
        if (!file.exists() || file.length() < 14L) {
            return ParsedId3Tags(null, null, null, null, null, null)
        }

        var title: String? = null
        var artist: String? = null
        var album: String? = null
        var year: String? = null
        var usltLyrics: String? = null
        var apicBytes: ByteArray? = null

        try {
            RandomAccessFile(file, "r").use { raf ->
                val header = ByteArray(10)
                raf.readFully(header)
                if (header[0] != 0x49.toByte() ||
                    header[1] != 0x44.toByte() ||
                    header[2] != 0x33.toByte()
                ) {
                    return ParsedId3Tags(null, null, null, null, null, null)
                }

                val versionMajor = header[3].toInt() and 0xFF
                val headerFlags = header[5].toInt() and 0xFF
                val tagSize = readSyncsafeInt(header, 6)
                if (tagSize <= 0) {
                    return ParsedId3Tags(null, null, null, null, null, null)
                }

                val maxRead = minOf(tagSize.toLong(), file.length() - 10L, 6L * 1024L * 1024L).toInt()
                if (maxRead <= 0) {
                    return ParsedId3Tags(null, null, null, null, null, null)
                }

                var tagBytes = ByteArray(maxRead)
                raf.readFully(tagBytes)

                // Whole-tag unsynchronisation (ID3v2.2 / v2.3)
                if (versionMajor <= 3 && (headerFlags and 0x80) != 0) {
                    tagBytes = removeUnsynchronisation(tagBytes)
                }

                var offset = 0
                // Skip extended header if present
                if ((headerFlags and 0x40) != 0 && tagBytes.size >= 4) {
                    val extSize = if (versionMajor == 4) {
                        readSyncsafeInt(tagBytes, 0)
                    } else {
                        readBigEndianInt(tagBytes, 0) + 4
                    }
                    if (extSize in 4 until tagBytes.size) {
                        offset += extSize
                    }
                }

                if (versionMajor == 2) {
                    while (offset + 6 <= tagBytes.size) {
                        if (tagBytes[offset] == 0.toByte()) break
                        val frameId = String(tagBytes, offset, 3, StandardCharsets.ISO_8859_1)
                        val frameSize = ((tagBytes[offset + 3].toInt() and 0xFF) shl 16) or
                            ((tagBytes[offset + 4].toInt() and 0xFF) shl 8) or
                            (tagBytes[offset + 5].toInt() and 0xFF)
                        if (frameSize <= 0 || offset + 6 + frameSize > tagBytes.size) break
                        val payload = tagBytes.copyOfRange(offset + 6, offset + 6 + frameSize)
                        when (frameId) {
                            "TT2" -> title = decodeTextFrame(payload)
                            "TP1" -> artist = decodeTextFrame(payload)
                            "TAL" -> album = decodeTextFrame(payload)
                            "TYE" -> year = decodeTextFrame(payload)
                            "ULT" -> usltLyrics = decodeUsltFrame(payload)
                            "PIC" -> if (needApic && apicBytes == null) {
                                apicBytes = extractImageFromBytes(payload)
                            }
                        }
                        offset += 6 + frameSize
                    }
                } else {
                    // ID3v2.3 & ID3v2.4 (10-byte frame headers)
                    while (offset + 10 <= tagBytes.size) {
                        if (tagBytes[offset] == 0.toByte()) break
                        val frameId = String(tagBytes, offset, 4, StandardCharsets.ISO_8859_1)
                        if (!frameId.all { it in 'A'..'Z' || it in '0'..'9' }) break

                        val frameSize = if (versionMajor == 4) {
                            val syncSize = readSyncsafeInt(tagBytes, offset + 4)
                            val beSize = readBigEndianInt(tagBytes, offset + 4)
                            // Guard against non-compliant v2.4 encoders that wrote non-syncsafe sizes
                            if (syncSize != beSize &&
                                offset + 10 + syncSize + 4 <= tagBytes.size &&
                                !isLikelyFrameHeaderOrPadding(tagBytes, offset + 10 + syncSize) &&
                                offset + 10 + beSize <= tagBytes.size &&
                                isLikelyFrameHeaderOrPadding(tagBytes, offset + 10 + beSize)
                            ) {
                                beSize
                            } else {
                                syncSize
                            }
                        } else {
                            readBigEndianInt(tagBytes, offset + 4)
                        }

                        if (frameSize <= 0 || offset + 10 + frameSize > tagBytes.size) break

                        val formatFlags = tagBytes[offset + 9].toInt() and 0xFF
                        var payloadStart = offset + 10
                        val payloadEnd = offset + 10 + frameSize

                        // Data length indicator in ID3v2.4 adds 4 syncsafe bytes before payload
                        if (versionMajor == 4 && (formatFlags and 0x01) != 0 && payloadStart + 4 <= payloadEnd) {
                            payloadStart += 4
                        }

                        var payload = tagBytes.copyOfRange(payloadStart, payloadEnd)
                        if (versionMajor == 4 && (formatFlags and 0x02) != 0) {
                            payload = removeUnsynchronisation(payload)
                        }

                        when (frameId) {
                            "TIT2" -> title = decodeTextFrame(payload)
                            "TPE1" -> if (artist.isNullOrBlank()) artist = decodeTextFrame(payload)
                            "TPE2" -> if (artist.isNullOrBlank()) artist = decodeTextFrame(payload)
                            "TALB" -> album = decodeTextFrame(payload)
                            "TDRC", "TYER" -> if (year.isNullOrBlank()) year = decodeTextFrame(payload)
                            "USLT" -> {
                                val decoded = decodeUsltFrame(payload)
                                if (!decoded.isNullOrBlank()) {
                                    // Prefer synced LRC lyrics if multiple USLT frames exist
                                    if (usltLyrics.isNullOrBlank() || decoded.contains("[0")) {
                                        usltLyrics = decoded
                                    }
                                }
                            }
                            "APIC" -> if (needApic && apicBytes == null) {
                                apicBytes = extractImageFromBytes(payload)
                            }
                        }

                        offset += 10 + frameSize
                    }
                }
            }
        } catch (_: Exception) {
        }

        return ParsedId3Tags(title, artist, album, year, usltLyrics, apicBytes)
    }

    private fun isLikelyFrameHeaderOrPadding(bytes: ByteArray, index: Int): Boolean {
        if (index >= bytes.size) return true
        if (bytes[index] == 0.toByte()) return true
        if (index + 4 > bytes.size) return false
        for (i in 0 until 4) {
            val c = (bytes[index + i].toInt() and 0xFF).toChar()
            if (!(c in 'A'..'Z' || c in '0'..'9')) return false
        }
        return true
    }

    private fun readSyncsafeInt(buf: ByteArray, offset: Int): Int {
        return ((buf[offset].toInt() and 0x7F) shl 21) or
            ((buf[offset + 1].toInt() and 0x7F) shl 14) or
            ((buf[offset + 2].toInt() and 0x7F) shl 7) or
            (buf[offset + 3].toInt() and 0x7F)
    }

    private fun readBigEndianInt(buf: ByteArray, offset: Int): Int {
        return ((buf[offset].toInt() and 0xFF) shl 24) or
            ((buf[offset + 1].toInt() and 0xFF) shl 16) or
            ((buf[offset + 2].toInt() and 0xFF) shl 8) or
            (buf[offset + 3].toInt() and 0xFF)
    }

    private fun removeUnsynchronisation(src: ByteArray): ByteArray {
        val out = ByteArray(src.size)
        var outLen = 0
        var i = 0
        while (i < src.size) {
            out[outLen++] = src[i]
            if (src[i] == 0xFF.toByte() && i + 1 < src.size && src[i + 1] == 0x00.toByte()) {
                i += 2
            } else {
                i++
            }
        }
        return out.copyOf(outLen)
    }

    private fun charsetForEncoding(encodingByte: Int): Charset {
        return when (encodingByte) {
            0 -> StandardCharsets.ISO_8859_1
            1 -> StandardCharsets.UTF_16
            2 -> StandardCharsets.UTF_16BE
            3 -> StandardCharsets.UTF_8
            else -> StandardCharsets.UTF_8
        }
    }

    private fun decodeTextFrame(payload: ByteArray): String? {
        if (payload.size <= 1) return null
        val encoding = payload[0].toInt() and 0xFF
        val charset = charsetForEncoding(encoding)
        val raw = String(payload, 1, payload.size - 1, charset)
            .trim { it <= ' ' || it == '\u0000' || it == '\uFEFF' }
        return raw.takeIf { it.isNotEmpty() }
    }

    private fun decodeUsltFrame(payload: ByteArray): String? {
        if (payload.size < 5) return null
        val encoding = payload[0].toInt() and 0xFF
        val charset = charsetForEncoding(encoding)

        // Bytes 1..3 are 3-char ISO-639-2 language ("eng", "jpn", etc.)
        // Byte 4+ is null-terminated content descriptor, followed by lyrics text.
        var lyricsStart = 4
        if (encoding == 1 || encoding == 2) {
            // UTF-16 / UTF-16BE uses 2-byte null terminator (0x00 0x00)
            var pos = 4
            var found = false
            while (pos + 1 < payload.size) {
                if (payload[pos] == 0.toByte() && payload[pos + 1] == 0.toByte()) {
                    lyricsStart = pos + 2
                    found = true
                    break
                }
                pos += 2
            }
            if (!found) {
                lyricsStart = 4
            }
        } else {
            // ISO-8859-1 / UTF-8 uses 1-byte null terminator (0x00)
            var pos = 4
            var found = false
            while (pos < payload.size) {
                if (payload[pos] == 0.toByte()) {
                    lyricsStart = pos + 1
                    found = true
                    break
                }
                pos++
            }
            if (!found) {
                lyricsStart = 4
            }
        }

        if (lyricsStart >= payload.size) return null
        val text = String(payload, lyricsStart, payload.size - lyricsStart, charset)
            .replace("\u0000", "")
            .replace("\uFEFF", "")
            .trim()
        return text.takeIf { it.isNotEmpty() }
    }

    private fun extractImageFromBytes(payload: ByteArray): ByteArray? {
        for (i in 0 until payload.size - 4) {
            // JPEG SOI: FF D8 FF
            if (payload[i] == 0xFF.toByte() &&
                payload[i + 1] == 0xD8.toByte() &&
                payload[i + 2] == 0xFF.toByte()
            ) {
                return payload.copyOfRange(i, payload.size)
            }
            // PNG signature: 89 50 4E 47
            if (payload[i] == 0x89.toByte() &&
                payload[i + 1] == 0x50.toByte() &&
                payload[i + 2] == 0x4E.toByte() &&
                payload[i + 3] == 0x47.toByte()
            ) {
                return payload.copyOfRange(i, payload.size)
            }
        }
        return null
    }

    /**
     * Samples a tiny 24x24 downscaled Bitmap of the Cover Art to compute
     * a rich, dark Musicolet ambient background color matching the artwork's mood
     * (e.g. soft dark purple for YOASOBI - Idol, dark olive-grey for ASCA - Resister).
     */
    private fun computeDominantAmbientColor(imageBytes: ByteArray): Int {
        try {
            val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, boundsOpts)
            if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) {
                return 0xFF1E222B.toInt()
            }

            var sampleSize = 1
            val minSide = minOf(boundsOpts.outWidth, boundsOpts.outHeight)
            while (minSide / (sampleSize * 2) >= 24) {
                sampleSize *= 2
            }

            val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
            val bmp = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, decodeOpts)
                ?: return 0xFF1E222B.toInt()

            var weightedR = 0.0
            var weightedG = 0.0
            var weightedB = 0.0
            var totalWeight = 0.0

            val stepX = (bmp.width / 16).coerceAtLeast(1)
            val stepY = (bmp.height / 16).coerceAtLeast(1)
            val hsv = FloatArray(3)

            var y = 0
            while (y < bmp.height) {
                var x = 0
                while (x < bmp.width) {
                    val px = bmp.getPixel(x, y)
                    val a = Color.alpha(px)
                    if (a >= 180) {
                        val r = Color.red(px)
                        val g = Color.green(px)
                        val b = Color.blue(px)
                        Color.RGBToHSV(r, g, b, hsv)
                        val sat = hsv[1]
                        val v = hsv[2]
                        // Skip pure black (<0.08) and glaring pure white (>0.96 & low sat)
                        if (v > 0.08f && !(v > 0.95f && sat < 0.08f)) {
                            val weight = 0.35 + (sat * 1.65) + (1.0 - kotlin.math.abs(v - 0.55)) * 0.4
                            weightedR += r * weight
                            weightedG += g * weight
                            weightedB += b * weight
                            totalWeight += weight
                        }
                    }
                    x += stepX
                }
                y += stepY
            }
            bmp.recycle()

            if (totalWeight <= 0.0) {
                return 0xFF1E222B.toInt()
            }

            val avgR = (weightedR / totalWeight).toInt().coerceIn(0, 255)
            val avgG = (weightedG / totalWeight).toInt().coerceIn(0, 255)
            val avgB = (weightedB / totalWeight).toInt().coerceIn(0, 255)

            // Convert to HSV and clamp Value into Musicolet's dark ambient zone (0.22 .. 0.36)
            Color.RGBToHSV(avgR, avgG, avgB, hsv)
            hsv[1] = (hsv[1] * 0.85f).coerceIn(0.06f, 0.65f)
            hsv[2] = hsv[2].coerceIn(0.22f, 0.36f)
            return Color.HSVToColor(0xFF, hsv)
        } catch (_: Exception) {
            return 0xFF1E222B.toInt()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val shared = extractSharedTextFromIntent(intent)
        if (!shared.isNullOrBlank()) {
            pendingSharedText = null
            methodChannel?.invokeMethod("onSharedText", shared)
        }
    }

    override fun onDestroy() {
        stopPreviewAudio(notifyFlutter = false)
        stopLocalAudio(notifyFlutter = false)
        ioExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun extractSharedTextFromIntent(intent: Intent?): String? {
        if (intent == null) return null
        if (Intent.ACTION_SEND == intent.action && intent.type?.startsWith("text/") == true) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
            if (!text.isNullOrEmpty()) {
                pendingSharedText = text
                return text
            }
        }
        return null
    }
}

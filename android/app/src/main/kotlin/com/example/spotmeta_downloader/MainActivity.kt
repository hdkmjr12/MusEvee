package com.example.spotmeta_downloader

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.media.MediaScannerConnection
import android.media.audiofx.AudioEffect
import android.media.audiofx.LoudnessEnhancer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
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
    private var previewFocusRequest: AudioFocusRequest? = null

    // Primary Local Music MediaPlayer (Musicolet player engine)
    private var localPlayer: MediaPlayer? = null
    private var currentLocalPath: String? = null
    private var currentLocalSessionId: Int = 0
    private var isLocalPrepared: Boolean = false
    private var currentNormalizedVolume: Float = 1.0f
    private var currentPreAmpGainMb: Int = 0
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var localFocusRequest: AudioFocusRequest? = null
    private var resumeLocalOnFocusGain: Boolean = false
    private var resumeLocalAfterPreview: Boolean = false
    private var mediaNotifier: MusEveeMediaNotifier? = null

    // Android 11-15 Scoped Storage, All Files Access & Notification permission tracking
    private val reqAllFilesAccess = 2101
    private val reqDeleteMedia = 2102
    private val reqWriteMedia = 2103
    private val reqNotificationPermission = 2104
    private val reqNotificationSettings = 2105
    private val reqPickDirectoryTree = 2106
    private var pendingAllFilesResult: MethodChannel.Result? = null
    private var pendingNotificationResult: MethodChannel.Result? = null
    private var pendingPickDirectoryResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeletePath: String? = null
    private var pendingWriteResult: MethodChannel.Result? = null
    private var pendingWritePath: String? = null
    private var pendingWriteBytes: ByteArray? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()

    private val playbackAudioAttributes: AudioAttributes by lazy {
        AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .build()
    }

    private val localAudioFocusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        // Ignore self-inflicted transient loss while our own 30s preview is active
        if (previewPlayer != null) return@OnAudioFocusChangeListener

        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                resumeLocalOnFocusGain = false
                resumeLocalAfterPreview = false
                pauseLocalAudioInternal(abandonFocus = true)
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                val wasPlaying = try {
                    isLocalPrepared && localPlayer?.isPlaying == true
                } catch (_: Exception) {
                    false
                }
                if (wasPlaying) {
                    resumeLocalOnFocusGain = true
                    pauseLocalAudioInternal(abandonFocus = false)
                }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                try {
                    val duckGain = (currentNormalizedVolume * 0.25f).coerceIn(0f, 1f)
                    localPlayer?.setVolume(duckGain, duckGain)
                } catch (_: Exception) {
                }
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                try {
                    val gain = currentNormalizedVolume.coerceIn(0f, 1f)
                    localPlayer?.setVolume(gain, gain)
                } catch (_: Exception) {
                }
                if (resumeLocalOnFocusGain && previewPlayer == null) {
                    resumeLocalOnFocusGain = false
                    resumeLocalAudio()
                }
            }
        }
    }

    private val previewAudioFocusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                resumeLocalAfterPreview = false
                stopPreviewAudio(notifyFlutter = true, allowResumeLocal = false)
            }
        }
    }

    private val positionTicker = object : Runnable {
        override fun run() {
            val mp = localPlayer
            val activeSession = currentLocalSessionId
            val activePath = currentLocalPath
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
                                "path" to activePath,
                                "sessionId" to activeSession
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
        syncPersistentAppState()
        super.onCreate(savedInstanceState)
        ioExecutor.execute {
            migrateAndCleanupStorageFootprint()
        }
        mediaNotifier = MusEveeMediaNotifier(this) { action, positionMs ->
            mainHandler.post {
                handleMediaNotificationAction(action, positionMs)
            }
        }
        extractSharedTextFromIntent(intent)
    }

    override fun onStop() {
        syncPersistentAppState()
        super.onStop()
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
                    val path = call.argument<String>("path")?.trim()
                    if (!path.isNullOrBlank()) {
                        val deleted = deleteMediaFileNonInteractive(path)
                        result.success(deleted)
                    } else {
                        result.success(false)
                    }
                }
                "deleteLocalAudioFile" -> {
                    val path = call.argument<String>("path")?.trim()
                    val allowSystemPrompt = call.argument<Boolean>("allowSystemPrompt") ?: true
                    if (path.isNullOrBlank()) {
                        result.success(
                            mapOf(
                                "deleted" to false,
                                "needsAllFilesAccess" to false,
                                "cancelledByUser" to false
                            )
                        )
                    } else {
                        deleteLocalAudioFileLayered(path, allowSystemPrompt, result)
                    }
                }
                "writeBytesToMusicFile" -> {
                    val path = call.argument<String>("path")?.trim()
                    val bytes = call.argument<ByteArray>("bytes")
                    val allowSystemPrompt = call.argument<Boolean>("allowSystemPrompt") ?: true
                    if (path.isNullOrBlank() || bytes == null || bytes.isEmpty()) {
                        result.success(
                            mapOf(
                                "written" to false,
                                "needsAllFilesAccess" to false,
                                "cancelledByUser" to false
                            )
                        )
                    } else {
                        writeBytesToMusicFileLayered(path, bytes, allowSystemPrompt, result)
                    }
                }
                "hasAllFilesAccess" -> {
                    result.success(hasAllFilesAccessNow())
                }
                "requestAllFilesAccess" -> {
                    requestAllFilesAccessNative(result)
                }
                "hasNotificationPermission" -> {
                    result.success(hasNotificationPermissionNow())
                }
                "requestNotificationPermission" -> {
                    requestNotificationPermissionNative(result)
                }
                "openNotificationSettings" -> {
                    openAppNotificationSettingsNative(result)
                }
                "pickDirectoryTree" -> {
                    openSystemDirectoryPickerNative(result)
                }
                "getPermissionsStatus" -> {
                    result.success(
                        mapOf(
                            "hasAllFilesAccess" to hasAllFilesAccessNow(),
                            "hasNotificationPermission" to hasNotificationPermissionNow(),
                            "packageName" to packageName,
                            "sdkInt" to Build.VERSION.SDK_INT
                        )
                    )
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
                        // Pause local player gently so 30s preview doesn't overlap,
                        // and remember if it was playing so we resume after preview ends.
                        pauseLocalAudioForPreview()
                        playPreviewAudio(url, result)
                    }
                }
                "stopPreview" -> {
                    stopPreviewAudio(notifyFlutter = true, allowResumeLocal = true)
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
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    val title = call.argument<String>("title")?.trim()
                    val artist = call.argument<String>("artist")?.trim()
                    val album = call.argument<String>("album")?.trim()
                    val coverPath = call.argument<String>("coverPath")?.trim()
                    val durationMs = (call.argument<Number>("durationMs")?.toLong()) ?: 0L
                    val requestedVolume = (call.argument<Number>("volume")?.toFloat()) ?: 1.0f
                    val requestedPreAmpDb = call.argument<Number>("preAmpDb")?.toDouble()
                    currentNormalizedVolume = requestedVolume.coerceIn(0f, 1f)
                    if (requestedPreAmpDb != null) {
                        currentPreAmpGainMb = Math.round(
                            requestedPreAmpDb.coerceIn(0.0, 12.0) * 100.0
                        ).toInt()
                    }
                    if (path.isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        playLocalAudioFile(
                            path = path,
                            startPositionMs = startPositionMs,
                            requestedSessionId = sessionId,
                            title = title,
                            artist = artist,
                            album = album,
                            coverPath = coverPath,
                            durationMs = durationMs,
                            result = result
                        )
                    }
                }
                "updateMediaNotification" -> {
                    val title = call.argument<String>("title")?.trim().orEmpty()
                    val artist = call.argument<String>("artist")?.trim().orEmpty()
                    val album = call.argument<String>("album")?.trim().orEmpty()
                    val coverPath = call.argument<String>("coverPath")?.trim()
                    val durationMs = (call.argument<Number>("durationMs")?.toLong()) ?: 0L
                    mediaNotifier?.updateMetadata(
                        newTitle = title,
                        newArtist = artist,
                        newAlbum = album,
                        coverPath = coverPath,
                        newDurationMs = durationMs
                    )
                    val mp = localPlayer
                    val playing = try {
                        isLocalPrepared && mp?.isPlaying == true
                    } catch (_: Exception) {
                        false
                    }
                    val pos = try {
                        if (isLocalPrepared && mp != null) mp.currentPosition.toLong() else 0L
                    } catch (_: Exception) {
                        0L
                    }
                    mediaNotifier?.updatePlaybackState(playing, pos)
                    result.success(true)
                }
                "localPause" -> {
                    pauseLocalAudioByUser()
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
                    stopLocalAudio(notifyFlutter = true, abandonFocus = true)
                    result.success(true)
                }
                "getVolume" -> {
                    result.success(currentNormalizedVolume.coerceIn(0f, 1f).toDouble())
                }
                "setVolume" -> {
                    val normalized = (call.argument<Double>("volume") ?: 1.0).coerceIn(0.0, 1.0)
                    currentNormalizedVolume = normalized.toFloat()
                    try {
                        val gain = currentNormalizedVolume.coerceIn(0f, 1f)
                        localPlayer?.setVolume(gain, gain)
                    } catch (_: Exception) {
                    }
                    result.success(true)
                }
                "setPreAmpGainDb" -> {
                    val gainDb = (call.argument<Number>("gainDb")?.toDouble() ?: 0.0)
                        .coerceIn(0.0, 12.0)
                    currentPreAmpGainMb = Math.round(gainDb * 100.0).toInt()
                    localPlayer?.let { applyLoudnessEnhancerToPlayer(it) }
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
                "scanLocalMusicLibraryDelta" -> {
                    val requestedFolders = call.argument<List<String>>("folders")
                    @Suppress("UNCHECKED_CAST")
                    val cachedIndex =
                        call.argument<Map<String, Map<String, Any?>>>("cachedIndex")
                    ioExecutor.execute {
                        try {
                            val delta = scanLocalLibraryDeltaInternal(requestedFolders, cachedIndex)
                            mainHandler.post { result.success(delta) }
                        } catch (_: Exception) {
                            mainHandler.post {
                                result.success(
                                    mapOf(
                                        "presentPaths" to emptyList<String>(),
                                        "updatedTracks" to emptyList<Map<String, Any?>>()
                                    )
                                )
                            }
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
                                    extractTrackMetadataMap(file, includeFullLyrics = true)
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
                "readEmbeddedCoverBytes" -> {
                    val path = call.argument<String>("path")?.trim()
                    if (path.isNullOrEmpty()) {
                        result.success(null)
                    } else {
                        ioExecutor.execute {
                            try {
                                val file = File(path)
                                val bytes = if (file.exists() && file.isFile) {
                                    extractFullEmbeddedCoverBytes(file)
                                } else {
                                    null
                                }
                                mainHandler.post { result.success(bytes) }
                            } catch (_: Exception) {
                                mainHandler.post { result.success(null) }
                            }
                        }
                    }
                }
                "cleanupTempCacheFiles" -> {
                    ioExecutor.execute {
                        try {
                            cleanupTempFilesInternal()
                        } catch (_: Exception) {
                        }
                        mainHandler.post { result.success(true) }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // =========================================================================
    // AUDIO FOCUS HELPERS (LOCAL PLAYER + 30s PREVIEW)
    // =========================================================================
    @Suppress("DEPRECATION")
    private fun requestLocalAudioFocus(): Boolean {
        val audioManager =
            applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                ?: return true
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val req = localFocusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(playbackAudioAttributes)
                    .setWillPauseWhenDucked(false)
                    .setOnAudioFocusChangeListener(localAudioFocusListener, mainHandler)
                    .build()
                    .also { localFocusRequest = it }
                audioManager.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            } else {
                audioManager.requestAudioFocus(
                    localAudioFocusListener,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN
                ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            }
        } catch (_: Exception) {
            true
        }
    }

    @Suppress("DEPRECATION")
    private fun abandonLocalAudioFocus() {
        val audioManager =
            applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                localFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            } else {
                audioManager.abandonAudioFocus(localAudioFocusListener)
            }
        } catch (_: Exception) {
        }
    }

    @Suppress("DEPRECATION")
    private fun requestPreviewAudioFocus(): Boolean {
        val audioManager =
            applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                ?: return true
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val req = previewFocusRequest
                    ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                        .setAudioAttributes(playbackAudioAttributes)
                        .setOnAudioFocusChangeListener(previewAudioFocusListener, mainHandler)
                        .build()
                        .also { previewFocusRequest = it }
                audioManager.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            } else {
                audioManager.requestAudioFocus(
                    previewAudioFocusListener,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            }
        } catch (_: Exception) {
            true
        }
    }

    @Suppress("DEPRECATION")
    private fun abandonPreviewAudioFocus() {
        val audioManager =
            applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                previewFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            } else {
                audioManager.abandonAudioFocus(previewAudioFocusListener)
            }
        } catch (_: Exception) {
        }
    }

    // =========================================================================
    // 30s PREVIEW AUDIO IMPLEMENTATION
    // =========================================================================
    private fun playPreviewAudio(url: String, result: MethodChannel.Result) {
        try {
            stopPreviewAudio(notifyFlutter = false, allowResumeLocal = false)
            requestPreviewAudioFocus()
            currentPreviewUrl = url

            val player = MediaPlayer()
            previewPlayer = player

            player.setAudioAttributes(playbackAudioAttributes)
            player.setVolume(1.0f, 1.0f)
            player.setDataSource(url)
            player.setOnPreparedListener { mp ->
                if (mp !== previewPlayer) return@setOnPreparedListener
                try {
                    mp.setVolume(1.0f, 1.0f)
                    mp.start()
                    methodChannel?.invokeMethod(
                        "onPreviewStateChanged",
                        mapOf("isPlaying" to true, "url" to url)
                    )
                } catch (_: Exception) {
                    stopPreviewAudio(notifyFlutter = true, allowResumeLocal = true)
                }
            }
            player.setOnCompletionListener { mp ->
                if (mp !== previewPlayer) return@setOnCompletionListener
                stopPreviewAudio(notifyFlutter = true, allowResumeLocal = true)
            }
            player.setOnErrorListener { mp, _, _ ->
                if (mp === previewPlayer) {
                    stopPreviewAudio(notifyFlutter = true, allowResumeLocal = true)
                }
                true
            }
            player.prepareAsync()
            result.success(true)
        } catch (_: Exception) {
            stopPreviewAudio(notifyFlutter = true, allowResumeLocal = true)
            result.success(false)
        }
    }

    private fun stopPreviewAudio(
        notifyFlutter: Boolean,
        allowResumeLocal: Boolean = true
    ) {
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
        abandonPreviewAudioFocus()
        if (notifyFlutter) {
            methodChannel?.invokeMethod(
                "onPreviewStateChanged",
                mapOf("isPlaying" to false, "url" to null)
            )
        }
        if (allowResumeLocal && resumeLocalAfterPreview) {
            resumeLocalAfterPreview = false
            resumeLocalAudio()
        }
    }

    // =========================================================================
    // LOCAL MUSIC PLAYER ENGINE IMPLEMENTATION
    // =========================================================================
    private fun playLocalAudioFile(
        path: String,
        startPositionMs: Int,
        requestedSessionId: Int,
        title: String?,
        artist: String?,
        album: String?,
        coverPath: String?,
        durationMs: Long,
        result: MethodChannel.Result
    ) {
        val file = File(path)
        if (!file.exists()) {
            result.success(false)
            return
        }

        resumeLocalAfterPreview = false
        resumeLocalOnFocusGain = false
        stopPreviewAudio(notifyFlutter = true, allowResumeLocal = false)
        stopLocalAudio(notifyFlutter = false, abandonFocus = false)

        val resolvedTitle = if (!title.isNullOrBlank()) title else file.nameWithoutExtension
        val resolvedArtist = if (!artist.isNullOrBlank()) artist else "MusEvee"
        val resolvedAlbum = album.orEmpty()
        mediaNotifier?.updateMetadata(
            newTitle = resolvedTitle,
            newArtist = resolvedArtist,
            newAlbum = resolvedAlbum,
            coverPath = coverPath,
            newDurationMs = durationMs
        )

        val capturedSessionId = if (requestedSessionId > 0) {
            requestedSessionId
        } else {
            currentLocalSessionId + 1
        }
        currentLocalSessionId = capturedSessionId
        val capturedPath = path

        try {
            requestLocalAudioFocus()
            val player = MediaPlayer()
            localPlayer = player
            currentLocalPath = capturedPath
            isLocalPrepared = false

            player.setAudioAttributes(playbackAudioAttributes)
            val gain = currentNormalizedVolume.coerceIn(0f, 1f)
            player.setVolume(gain, gain)
            player.setDataSource(capturedPath)
            player.setOnPreparedListener { mp ->
                if (mp !== localPlayer || capturedSessionId != currentLocalSessionId) {
                    return@setOnPreparedListener
                }
                isLocalPrepared = true
                try {
                    val preparedGain = currentNormalizedVolume.coerceIn(0f, 1f)
                    mp.setVolume(preparedGain, preparedGain)
                    applyLoudnessEnhancerToPlayer(mp)
                    if (startPositionMs > 0 && startPositionMs < mp.duration) {
                        mp.seekTo(startPositionMs)
                    }
                    mp.start()
                    mediaNotifier?.updateDuration(mp.duration.toLong())
                    notifyLocalPlayerState(isPlaying = true)
                    startPositionTicker()
                } catch (_: Exception) {
                    stopLocalAudio(notifyFlutter = true, abandonFocus = true)
                }
            }
            player.setOnCompletionListener { mp ->
                if (mp !== localPlayer ||
                    capturedSessionId != currentLocalSessionId ||
                    !isLocalPrepared
                ) {
                    return@setOnCompletionListener
                }
                stopPositionTicker()
                val dur = try {
                    mp.duration
                } catch (_: Exception) {
                    0
                }
                methodChannel?.invokeMethod(
                    "onLocalTrackCompleted",
                    mapOf(
                        "path" to capturedPath,
                        "sessionId" to capturedSessionId,
                        "durationMs" to dur
                    )
                )
            }
            player.setOnErrorListener { mp, _, _ ->
                if (mp === localPlayer && capturedSessionId == currentLocalSessionId) {
                    stopLocalAudio(notifyFlutter = true, abandonFocus = true)
                }
                true
            }
            player.prepareAsync()
            result.success(true)
        } catch (_: Exception) {
            stopLocalAudio(notifyFlutter = true, abandonFocus = true)
            result.success(false)
        }
    }

    private fun pauseLocalAudioForPreview() {
        val mp = localPlayer ?: return
        try {
            if (isLocalPrepared && mp.isPlaying) {
                resumeLocalAfterPreview = true
                mp.pause()
                stopPositionTicker()
                notifyLocalPlayerState(isPlaying = false)
            }
        } catch (_: Exception) {
        }
    }

    private fun pauseLocalAudioByUser() {
        resumeLocalOnFocusGain = false
        resumeLocalAfterPreview = false
        pauseLocalAudioInternal(abandonFocus = true)
    }

    private fun pauseLocalAudioInternal(abandonFocus: Boolean) {
        val mp = localPlayer ?: return
        try {
            if (isLocalPrepared && mp.isPlaying) {
                mp.pause()
            }
        } catch (_: Exception) {
        }
        stopPositionTicker()
        if (abandonFocus) {
            abandonLocalAudioFocus()
        }
        notifyLocalPlayerState(isPlaying = false)
    }

    private fun resumeLocalAudio(): Boolean {
        val mp = localPlayer ?: return false
        if (!isLocalPrepared) return false
        return try {
            resumeLocalAfterPreview = false
            stopPreviewAudio(notifyFlutter = true, allowResumeLocal = false)
            requestLocalAudioFocus()
            val gain = currentNormalizedVolume.coerceIn(0f, 1f)
            mp.setVolume(gain, gain)
            applyLoudnessEnhancerToPlayer(mp)
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
            mediaNotifier?.updatePlaybackState(mp.isPlaying, clamped.toLong())
            methodChannel?.invokeMethod(
                "onLocalPosition",
                mapOf(
                    "positionMs" to clamped,
                    "durationMs" to dur,
                    "isPlaying" to mp.isPlaying,
                    "path" to currentLocalPath,
                    "sessionId" to currentLocalSessionId
                )
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun stopLocalAudio(notifyFlutter: Boolean, abandonFocus: Boolean = true) {
        stopPositionTicker()
        if (notifyFlutter) {
            resumeLocalOnFocusGain = false
            resumeLocalAfterPreview = false
        }
        val mp = localPlayer
        localPlayer = null
        isLocalPrepared = false
        val prevPath = currentLocalPath
        val prevSession = currentLocalSessionId
        currentLocalPath = null
        releaseLoudnessEnhancer()
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
        if (abandonFocus) {
            abandonLocalAudioFocus()
        }
        if (notifyFlutter) {
            mediaNotifier?.clear()
            methodChannel?.invokeMethod(
                "onLocalPlayerState",
                mapOf(
                    "isPlaying" to false,
                    "path" to prevPath,
                    "sessionId" to prevSession,
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
        if (dur > 0) {
            mediaNotifier?.updateDuration(dur.toLong())
        }
        mediaNotifier?.updatePlaybackState(isPlaying, pos.toLong())
        methodChannel?.invokeMethod(
            "onLocalPlayerState",
            mapOf(
                "isPlaying" to isPlaying,
                "path" to currentLocalPath,
                "sessionId" to currentLocalSessionId,
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

    private fun handleMediaNotificationAction(action: String, positionMs: Long) {
        when (action) {
            "pause" -> pauseLocalAudioByUser()
            "play" -> {
                if (!resumeLocalAudio()) {
                    methodChannel?.invokeMethod(
                        "onMediaNotificationAction",
                        mapOf("action" to "play", "positionMs" to 0)
                    )
                }
            }
            "seek" -> {
                seekLocalAudio(positionMs.toInt())
            }
            "next", "previous" -> {
                methodChannel?.invokeMethod(
                    "onMediaNotificationAction",
                    mapOf("action" to action, "positionMs" to 0)
                )
            }
            "stop" -> {
                stopLocalAudio(notifyFlutter = true, abandonFocus = true)
            }
        }
    }

    private fun releaseLoudnessEnhancer() {
        val enhancer = loudnessEnhancer
        loudnessEnhancer = null
        if (enhancer != null) {
            try {
                enhancer.enabled = false
            } catch (_: Exception) {
            }
            try {
                enhancer.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun applyLoudnessEnhancerToPlayer(mp: MediaPlayer) {
        if (currentPreAmpGainMb <= 0) {
            // Keep default 0.0 dB playback 100% bit-pure and unattenuated (no DSP limiter)
            releaseLoudnessEnhancer()
            return
        }
        try {
            val sessionId = mp.audioSessionId
            if (sessionId <= 0) return
            releaseLoudnessEnhancer()
            val enhancer = LoudnessEnhancer(sessionId)
            enhancer.setTargetGain(currentPreAmpGainMb)
            enhancer.enabled = true
            loudnessEnhancer = enhancer
        } catch (_: Exception) {
        }
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
    // LOCAL LIBRARY SCANNER & ID3v2 (USLT + APIC + .LRC FALLBACK) EXTRACTOR
    // =========================================================================
    private val excludedSystemAudioDirs = setOf(
        "whatsapp",
        "whatsapp audio",
        "whatsapp voice notes",
        "whatsapp animated gifs",
        "whatsapp images",
        "whatsapp video",
        "whatsapp documents",
        "telegram audio",
        "telegram video",
        "voice notes",
        "voicenotes",
        "recordings",
        "callrecord",
        "call_rec",
        "call recordings",
        "soundrecorder",
        "sound_recorder",
        "audio recorder",
        "ringtones_music",
        "ringtones",
        "alarms",
        "notifications",
        "ui",
        ".thumbnails",
        ".musevee_state",
        ".trash",
        ".trashed"
    )

    private val excludedPathFragments = listOf(
        "/whatsapp/",
        "/whatsapp audio/",
        "/whatsapp voice notes/",
        "/telegram/telegram audio/",
        "/voice notes/",
        "/recordings/",
        "/callrecord/",
        "/soundrecorder/",
        "/ringtones/",
        "/ringtones_music/",
        "/alarms/",
        "/notifications/",
        "/android/data/",
        "/android/media/",
        "/android/obb/"
    )

    private val minValidMusicBytes = 16384L // Hard floor against <16KB OS sound stubs
    private val minFallbackMusicBytes = 51200L // >= 50 KB when duration is not indexed yet
    private val minValidMusicDurationMs = 15000L // >= 15 seconds for indexed tracks

    private fun isExcludedAudioPath(path: String): Boolean {
        val normalized = path.replace('\\', '/')
        val lowerPath = normalized.lowercase()
        if (lowerPath.contains("/.")) return true
        for (frag in excludedPathFragments) {
            if (lowerPath.contains(frag)) return true
        }
        val segments = normalized.split('/')
        for (seg in segments) {
            if (seg.isEmpty()) continue
            val lower = seg.lowercase().trim()
            if (seg.startsWith(".") || excludedSystemAudioDirs.contains(lower)) {
                return true
            }
        }
        return false
    }

    private fun isLikelyMusicFolderPath(path: String): Boolean {
        val lower = path.replace('\\', '/').lowercase()
        return lower.contains("/music/") ||
            lower.contains("/download/") ||
            lower.contains("/audio/") ||
            lower.contains("/songs/") ||
            lower.contains("/spotmeta/") ||
            lower.contains("/musevee/")
    }

    private fun discoverLocalAudioFiles(requestedFolders: List<String>?): LinkedHashMap<String, File> {
        val audioExtensions = setOf("mp3", "m4a", "flac", "wav", "ogg", "aac", "opus")
        val discoveredFiles = LinkedHashMap<String, File>()

        val storageRoot = File("/storage/emulated/0")
        val musicRoot = File(storageRoot, "Music")
        val downloadRoot = File(storageRoot, "Download")
        val audioRoot = File(storageRoot, "Audio")
        val songsRoot = File(storageRoot, "Songs")

        // 1. Scan prioritized user folders first if they exist on disk
        val baseFolders = requestedFolders?.filter { it.isNotBlank() }.orEmpty()
        for (folderName in baseFolders) {
            if (excludedSystemAudioDirs.contains(folderName.lowercase().trim())) continue
            val dir = File(musicRoot, folderName)
            if (dir.exists() && dir.isDirectory) {
                collectAudioFilesRecursively(dir, audioExtensions, discoveredFiles, maxDepth = 3)
            }
            val dlDir = File(downloadRoot, folderName)
            if (dlDir.exists() && dlDir.isDirectory) {
                collectAudioFilesRecursively(dlDir, audioExtensions, discoveredFiles, maxDepth = 2)
            }
        }

        // 2. Scan standard music/download directories directly
        for (root in listOf(musicRoot, downloadRoot, audioRoot, songsRoot)) {
            if (root.exists() && root.isDirectory) {
                collectAudioFilesRecursively(root, audioExtensions, discoveredFiles, maxDepth = 4)
            }
        }

        // 3. Universal MediaStore query across internal/external storage with strict anti-junk filter
        try {
            val projection = arrayOf(
                MediaStore.MediaColumns.DATA,
                MediaStore.Audio.Media.DURATION,
                MediaStore.MediaColumns.SIZE,
                MediaStore.Audio.Media.IS_MUSIC
            )
            applicationContext.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"
            )?.use { cursor ->
                val dataCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                val durCol = cursor.getColumnIndex(MediaStore.Audio.Media.DURATION)
                val sizeCol = cursor.getColumnIndex(MediaStore.MediaColumns.SIZE)
                val isMusicCol = cursor.getColumnIndex(MediaStore.Audio.Media.IS_MUSIC)
                if (dataCol >= 0) {
                    while (cursor.moveToNext()) {
                        val rawPath = cursor.getString(dataCol)?.trim() ?: continue
                        if (rawPath.isEmpty() || isExcludedAudioPath(rawPath)) continue

                        val isMusicFlag = if (isMusicCol >= 0) cursor.getInt(isMusicCol) else 1
                        if (isMusicFlag == 0 && !isLikelyMusicFolderPath(rawPath)) {
                            continue
                        }

                        val f = File(rawPath)
                        val ext = f.extension.lowercase()
                        if (!audioExtensions.contains(ext)) continue
                        if (!f.exists() || !f.isFile) continue

                        val diskSize = f.length()
                        if (diskSize < minValidMusicBytes) continue

                        val indexedDuration = if (durCol >= 0) cursor.getLong(durCol) else 0L
                        val indexedSize = if (sizeCol >= 0) cursor.getLong(sizeCol) else diskSize
                        val effectiveSize = maxOf(diskSize, indexedSize)

                        val passesAntiJunkFilter =
                            (indexedDuration >= minValidMusicDurationMs) ||
                                (indexedDuration <= 0L && effectiveSize >= minFallbackMusicBytes)
                        if (passesAntiJunkFilter) {
                            discoveredFiles.putIfAbsent(f.absolutePath, f)
                        }
                    }
                }
            }
        } catch (_: Exception) {
        }

        return discoveredFiles
    }

    private fun scanLocalLibraryInternal(requestedFolders: List<String>?): List<Map<String, Any?>> {
        val discoveredFiles = discoverLocalAudioFiles(requestedFolders)
        val results = ArrayList<Map<String, Any?>>(discoveredFiles.size)
        for (file in discoveredFiles.values) {
            try {
                results.add(extractTrackMetadataMap(file))
            } catch (_: Exception) {
            }
        }
        return results
    }

    /**
     * Incremental delta scanner: checks `lastModifiedMs` + `sizeBytes` + persistent cover file
     * in `filesDir/covers` before running `MediaMetadataRetriever` or `parseId3v2Tags`.
     * Unchanged files skip heavy I/O and Bitmap decoding 100%.
     */
    private fun scanLocalLibraryDeltaInternal(
        requestedFolders: List<String>?,
        cachedIndex: Map<String, Map<String, Any?>>?
    ): Map<String, Any?> {
        val discoveredFiles = discoverLocalAudioFiles(requestedFolders)
        val presentPaths = ArrayList<String>(discoveredFiles.size)
        val updatedTracks = ArrayList<Map<String, Any?>>()
        val persistentCoversRoot = File(applicationContext.filesDir, "covers").absolutePath

        for ((path, file) in discoveredFiles) {
            presentPaths.add(path)
            val cached = cachedIndex?.get(path)
            var isUpToDate = false
            if (cached != null) {
                val cachedMod = (cached["lastModifiedMs"] as? Number)?.toLong() ?: -1L
                val cachedSize = (cached["sizeBytes"] as? Number)?.toLong() ?: -1L
                if (cachedMod == file.lastModified() && cachedSize == file.length()) {
                    val cachedHasLyrics = cached["hasLyrics"] == true
                    val companionLrcExists = !cachedHasLyrics &&
                        File(file.parentFile, "${file.nameWithoutExtension}.lrc").let {
                            it.exists() && it.isFile && it.length() > 0L
                        }
                    if (!companionLrcExists) {
                        val cachedCoverPath = (cached["coverFilePath"] as? String)?.trim()
                        if (cachedCoverPath.isNullOrEmpty()) {
                            isUpToDate = true
                        } else {
                            val covFile = File(cachedCoverPath)
                            if (covFile.exists() &&
                                covFile.length() > 0L &&
                                covFile.parentFile?.absolutePath == persistentCoversRoot
                            ) {
                                isUpToDate = true
                            }
                        }
                    }
                }
            }

            if (!isUpToDate) {
                try {
                    updatedTracks.add(extractTrackMetadataMap(file))
                } catch (_: Exception) {
                }
            }
        }

        return mapOf(
            "presentPaths" to presentPaths,
            "updatedTracks" to updatedTracks
        )
    }

    private fun collectAudioFilesRecursively(
        dir: File,
        extensions: Set<String>,
        out: LinkedHashMap<String, File>,
        maxDepth: Int
    ) {
        if (maxDepth < 0 || !dir.exists() || !dir.isDirectory) return
        if (isExcludedAudioPath(dir.absolutePath)) return
        val children = try {
            dir.listFiles()
        } catch (_: Exception) {
            null
        } ?: return

        for (child in children) {
            if (child.name.startsWith(".")) continue
            if (child.isFile) {
                val ext = child.extension.lowercase()
                if (extensions.contains(ext) &&
                    child.length() >= minFallbackMusicBytes &&
                    !isExcludedAudioPath(child.absolutePath)
                ) {
                    out.putIfAbsent(child.absolutePath, child)
                }
            } else if (child.isDirectory && maxDepth > 0) {
                if (excludedSystemAudioDirs.contains(child.name.lowercase().trim())) continue
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

    private fun extractTrackMetadataMap(
        file: File,
        includeFullLyrics: Boolean = false
    ): Map<String, Any?> {
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
            // Store compact 256x256 JPEG cover thumbnail (~8-15 KB) in `filesDir/covers`
            // so total User Data stays under 5 MB even with hundreds of local songs.
            val coversDir = File(applicationContext.filesDir, "covers")
            if (!coversDir.exists()) {
                coversDir.mkdirs()
            }
            val safeHash = file.absolutePath.hashCode().toUInt().toString(16)
            val prefix = "cov_${safeHash}_"
            val cachedCover = File(coversDir, "${prefix}${file.lastModified()}.jpg")
            try {
                if (!cachedCover.exists() || cachedCover.length() == 0L || cachedCover.length() > 36864L) {
                    val thumbBytes = compressCoverToThumbnailBytes(
                        coverBytes,
                        maxDim = 256,
                        quality = 78
                    )
                    cachedCover.writeBytes(thumbBytes)
                }
                // Prune any older cover file revisions for this same audio path
                coversDir.listFiles()?.forEach { existing ->
                    if (existing.name.startsWith(prefix) && existing.name != cachedCover.name) {
                        try {
                            existing.delete()
                        } catch (_: Exception) {
                        }
                    }
                }
                coverFilePath = cachedCover.absolutePath
            } catch (_: Exception) {
            }
            dominantColor = computeDominantAmbientColor(coverBytes)
        }

        // Fallback to companion .lrc file if legacy MP3 has no embedded USLT frame
        val resolvedLyrics = if (!id3.usltLyrics.isNullOrBlank()) {
            id3.usltLyrics
        } else {
            readCompanionLrcIfPresent(file)
        }
        val hasLyricsFlag = !resolvedLyrics.isNullOrBlank()
        val hasSyncedLyricsFlag = hasLyricsFlag &&
            Regex("""\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]""").containsMatchIn(resolvedLyrics!!)

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
            "usltLyrics" to if (includeFullLyrics) resolvedLyrics else null,
            "hasLyrics" to hasLyricsFlag,
            "hasSyncedLyrics" to hasSyncedLyricsFlag,
            "dominantColor" to dominantColor,
            "lastModifiedMs" to file.lastModified()
        )
    }

    /**
     * Downscales and compresses raw APIC cover bytes into a compact `256x256 px`
     * JPEG thumbnail (`quality = 78`, `~8-15 KB` per track) for list views & MiniPlayer.
     */
    private fun compressCoverToThumbnailBytes(
        rawBytes: ByteArray,
        maxDim: Int = 256,
        quality: Int = 78
    ): ByteArray {
        return try {
            val boundsOpts = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size, boundsOpts)
            val srcW = boundsOpts.outWidth
            val srcH = boundsOpts.outHeight
            if (srcW <= 0 || srcH <= 0) return rawBytes

            var sampleSize = 1
            while ((srcW / sampleSize) > maxDim * 2 || (srcH / sampleSize) > maxDim * 2) {
                sampleSize *= 2
            }

            val decodeOpts = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.RGB_565
            }
            val decoded = BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size, decodeOpts)
                ?: return rawBytes

            val finalBitmap = if (decoded.width > maxDim || decoded.height > maxDim) {
                val scale = minOf(
                    maxDim.toFloat() / decoded.width.toFloat(),
                    maxDim.toFloat() / decoded.height.toFloat()
                )
                val targetW = maxOf(1, Math.round(decoded.width * scale))
                val targetH = maxOf(1, Math.round(decoded.height * scale))
                val scaled = Bitmap.createScaledBitmap(decoded, targetW, targetH, true)
                if (scaled != decoded) {
                    decoded.recycle()
                }
                scaled
            } else {
                decoded
            }

            val out = ByteArrayOutputStream(16384)
            finalBitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
            finalBitmap.recycle()
            val compressed = out.toByteArray()
            if (compressed.isNotEmpty() && compressed.size < rawBytes.size) {
                compressed
            } else {
                rawBytes
            }
        } catch (_: Exception) {
            rawBytes
        }
    }

    /**
     * Reads full-resolution embedded APIC artwork bytes on-demand in memory
     * for `NowPlayingView` without writing a large file to disk.
     */
    private fun extractFullEmbeddedCoverBytes(file: File): ByteArray? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            val pic = retriever.embeddedPicture
            if (pic != null && pic.isNotEmpty()) {
                return pic
            }
        } catch (_: Exception) {
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
        return try {
            parseId3v2Tags(file, needApic = true).apicBytes
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Migrates oversized legacy cover files (`> 36 KB`) in `filesDir/covers` down to
     * `256x256 px` thumbnails (`~8-15 KB`) and purges leftover temporary files so
     * MusEvee's User Data stays under 5 MB like Musicolet.
     */
    private fun migrateAndCleanupStorageFootprint() {
        try {
            val coversDir = File(applicationContext.filesDir, "covers")
            if (coversDir.exists() && coversDir.isDirectory) {
                coversDir.listFiles()?.forEach { coverFile ->
                    if (coverFile.isFile && coverFile.length() > 36864L) {
                        try {
                            val raw = coverFile.readBytes()
                            val compressed = compressCoverToThumbnailBytes(
                                raw,
                                maxDim = 256,
                                quality = 78
                            )
                            if (compressed.isNotEmpty() && compressed.size < raw.size) {
                                coverFile.writeBytes(compressed)
                            }
                        } catch (_: Exception) {
                        }
                    }
                }
            }
        } catch (_: Exception) {
        }
        cleanupTempFilesInternal()
    }

    private fun cleanupTempFilesInternal() {
        val roots = listOfNotNull(
            applicationContext.cacheDir,
            applicationContext.externalCacheDir,
            applicationContext.filesDir
        )
        for (root in roots) {
            try {
                root.listFiles()?.forEach { child ->
                    val nameLower = child.name.lowercase()
                    if (child.isFile && (
                            nameLower.endsWith(".tmp") ||
                                nameLower.endsWith(".webm") ||
                                nameLower.endsWith(".m4a") ||
                                nameLower.startsWith("cover_") ||
                                nameLower.startsWith("output_") ||
                                nameLower.startsWith("retag_") ||
                                nameLower.startsWith("yt_")
                            )
                    ) {
                        try {
                            child.delete()
                        } catch (_: Exception) {
                        }
                    }
                }
            } catch (_: Exception) {
            }
        }
    }

    /**
     * Streams ID3v2 frames via `RandomAccessFile` and extracts `USLT`
     * (UTF-8 / UTF-16 / UTF-16BE / ISO-8859-1), text frames, and optional `APIC`
     * image bytes — skipping `APIC`/`PIC` and unneeded binary frames via `raf.seek()`
     * instead of allocating multi-megabyte byte arrays when `needApic == false`.
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

                // Fallback to whole-tag buffer ONLY when legacy whole-tag unsynchronisation (0x80) is set
                if (versionMajor <= 3 && (headerFlags and 0x80) != 0) {
                    val maxRead = minOf(tagSize.toLong(), file.length() - 10L, 6L * 1024L * 1024L).toInt()
                    if (maxRead <= 0) {
                        return ParsedId3Tags(null, null, null, null, null, null)
                    }
                    var tagBytes = ByteArray(maxRead)
                    raf.readFully(tagBytes)
                    tagBytes = removeUnsynchronisation(tagBytes)
                    return parseId3v2FromBuffer(tagBytes, versionMajor, headerFlags, needApic)
                }

                val tagEndPos = 10L + minOf(
                    tagSize.toLong(),
                    file.length() - 10L,
                    16L * 1024L * 1024L
                )

                // Skip extended header if present
                if ((headerFlags and 0x40) != 0 && raf.filePointer + 4L <= tagEndPos) {
                    val extBuf = ByteArray(4)
                    raf.readFully(extBuf)
                    val extSize = if (versionMajor == 4) {
                        readSyncsafeInt(extBuf, 0).toLong()
                    } else {
                        readBigEndianInt(extBuf, 0).toLong() + 4L
                    }
                    val nextAfterExt = 10L + extSize
                    if (extSize >= 4L && nextAfterExt < tagEndPos) {
                        raf.seek(nextAfterExt)
                    } else {
                        raf.seek(10L)
                    }
                }

                if (versionMajor == 2) {
                    val fh = ByteArray(6)
                    while (raf.filePointer + 6L <= tagEndPos) {
                        raf.readFully(fh)
                        if (fh[0] == 0.toByte()) break
                        val frameId = String(fh, 0, 3, StandardCharsets.ISO_8859_1)
                        val frameSize = ((fh[3].toInt() and 0xFF) shl 16) or
                            ((fh[4].toInt() and 0xFF) shl 8) or
                            (fh[5].toInt() and 0xFF)
                        val dataStart = raf.filePointer
                        val nextFramePos = dataStart + frameSize.toLong()
                        if (frameSize <= 0 || nextFramePos > tagEndPos) break

                        val wantFrame = when (frameId) {
                            "TT2", "TP1", "TAL", "TYE" -> frameSize <= 64 * 1024
                            "ULT" -> frameSize <= 1024 * 1024
                            "PIC" -> needApic && apicBytes == null && frameSize <= 6 * 1024 * 1024
                            else -> false
                        }

                        if (!wantFrame) {
                            raf.seek(nextFramePos)
                        } else {
                            val payload = ByteArray(frameSize)
                            raf.readFully(payload)
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
                        }
                    }
                } else {
                    // ID3v2.3 & ID3v2.4 streaming 10-byte frame header reader
                    val fh = ByteArray(10)
                    val peekBuf = ByteArray(4)
                    while (raf.filePointer + 10L <= tagEndPos) {
                        raf.readFully(fh)
                        if (fh[0] == 0.toByte()) break
                        val frameId = String(fh, 0, 4, StandardCharsets.ISO_8859_1)
                        if (!frameId.all { it in 'A'..'Z' || it in '0'..'9' }) break

                        val dataStart = raf.filePointer
                        val frameSize = if (versionMajor == 4) {
                            val syncSize = readSyncsafeInt(fh, 4)
                            val beSize = readBigEndianInt(fh, 4)
                            if (syncSize != beSize &&
                                beSize > 0 &&
                                dataStart + syncSize.toLong() + 4L <= tagEndPos &&
                                dataStart + beSize.toLong() <= tagEndPos
                            ) {
                                raf.seek(dataStart + syncSize.toLong())
                                raf.readFully(peekBuf)
                                val syncValidNext = isLikelyFrameHeaderOrPadding(peekBuf, 0)
                                var beValidNext = true
                                if (!syncValidNext && dataStart + beSize.toLong() + 4L <= tagEndPos) {
                                    raf.seek(dataStart + beSize.toLong())
                                    raf.readFully(peekBuf)
                                    beValidNext = isLikelyFrameHeaderOrPadding(peekBuf, 0)
                                }
                                raf.seek(dataStart)
                                if (!syncValidNext && beValidNext) beSize else syncSize
                            } else {
                                syncSize
                            }
                        } else {
                            readBigEndianInt(fh, 4)
                        }

                        val nextFramePos = dataStart + frameSize.toLong()
                        if (frameSize <= 0 || nextFramePos > tagEndPos) break

                        val wantFrame = when (frameId) {
                            "TIT2", "TPE1", "TPE2", "TALB", "TDRC", "TYER" -> frameSize <= 64 * 1024
                            "USLT" -> frameSize <= 1024 * 1024
                            "APIC" -> needApic && apicBytes == null && frameSize <= 6 * 1024 * 1024
                            else -> false
                        }

                        if (!wantFrame) {
                            raf.seek(nextFramePos)
                        } else {
                            val formatFlags = fh[9].toInt() and 0xFF
                            var readLen = frameSize
                            if (versionMajor == 4 && (formatFlags and 0x01) != 0 && readLen >= 4) {
                                raf.skipBytes(4)
                                readLen -= 4
                            }
                            if (readLen > 0) {
                                var payload = ByteArray(readLen)
                                raf.readFully(payload)
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
                                            if (usltLyrics.isNullOrBlank() || decoded.contains("[0")) {
                                                usltLyrics = decoded
                                            }
                                        }
                                    }
                                    "APIC" -> if (needApic && apicBytes == null) {
                                        apicBytes = extractImageFromBytes(payload)
                                    }
                                }
                            }
                            raf.seek(nextFramePos)
                        }
                    }
                }
            }
        } catch (_: Exception) {
        }

        return ParsedId3Tags(title, artist, album, year, usltLyrics, apicBytes)
    }

    private fun parseId3v2FromBuffer(
        tagBytes: ByteArray,
        versionMajor: Int,
        headerFlags: Int,
        needApic: Boolean
    ): ParsedId3Tags {
        var title: String? = null
        var artist: String? = null
        var album: String? = null
        var year: String? = null
        var usltLyrics: String? = null
        var apicBytes: ByteArray? = null

        var offset = 0
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
            while (offset + 10 <= tagBytes.size) {
                if (tagBytes[offset] == 0.toByte()) break
                val frameId = String(tagBytes, offset, 4, StandardCharsets.ISO_8859_1)
                if (!frameId.all { it in 'A'..'Z' || it in '0'..'9' }) break
                val frameSize = readBigEndianInt(tagBytes, offset + 4)
                if (frameSize <= 0 || offset + 10 + frameSize > tagBytes.size) break
                val payload = tagBytes.copyOfRange(offset + 10, offset + 10 + frameSize)
                when (frameId) {
                    "TIT2" -> title = decodeTextFrame(payload)
                    "TPE1" -> if (artist.isNullOrBlank()) artist = decodeTextFrame(payload)
                    "TPE2" -> if (artist.isNullOrBlank()) artist = decodeTextFrame(payload)
                    "TALB" -> album = decodeTextFrame(payload)
                    "TDRC", "TYER" -> if (year.isNullOrBlank()) year = decodeTextFrame(payload)
                    "USLT" -> {
                        val decoded = decodeUsltFrame(payload)
                        if (!decoded.isNullOrBlank()) {
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

    private fun readCompanionLrcIfPresent(audioFile: File): String? {
        return try {
            val lrcFile = File(audioFile.parentFile, "${audioFile.nameWithoutExtension}.lrc")
            if (lrcFile.exists() && lrcFile.isFile && lrcFile.length() in 1L..262144L) {
                val text = lrcFile.readText(StandardCharsets.UTF_8).trim()
                text.takeIf { it.isNotEmpty() }
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun deleteCompanionLrcIfPresent(audioPath: String) {
        try {
            val af = File(audioPath)
            val lrcFile = File(af.parentFile, "${af.nameWithoutExtension}.lrc")
            if (lrcFile.exists() && lrcFile.isFile) {
                lrcFile.delete()
            }
        } catch (_: Exception) {
        }
    }

    // =========================================================================
    // ANDROID 11-15 SCOPED STORAGE & MEDIASTORE FILE MANAGEMENT
    // =========================================================================
    private fun findMediaStoreAudioUri(path: String): Uri? {
        return try {
            val projection = arrayOf(MediaStore.Audio.Media._ID)
            val selection = "${MediaStore.MediaColumns.DATA} = ?"
            val selectionArgs = arrayOf(path)
            applicationContext.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idCol = cursor.getColumnIndex(MediaStore.Audio.Media._ID)
                    if (idCol >= 0) {
                        val id = cursor.getLong(idCol)
                        return ContentUris.withAppendedId(
                            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                            id
                        )
                    }
                }
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun purgeMediaStoreRow(path: String, itemUri: Uri? = null) {
        if (itemUri != null) {
            try {
                applicationContext.contentResolver.delete(itemUri, null, null)
            } catch (_: Exception) {
            }
        }
        try {
            applicationContext.contentResolver.delete(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                "${MediaStore.MediaColumns.DATA} = ?",
                arrayOf(path)
            )
        } catch (_: Exception) {
        }
    }

    private fun scanMediaPath(path: String, mimeType: String? = null) {
        try {
            val mimes = if (mimeType != null) arrayOf(mimeType) else null
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(path),
                mimes,
                null
            )
        } catch (_: Exception) {
        }
    }

    private fun deleteMediaFileNonInteractive(path: String): Boolean {
        if (currentLocalPath == path) {
            stopLocalAudio(notifyFlutter = false, abandonFocus = true)
        }
        val targetFile = File(path)
        if (!targetFile.exists()) {
            purgeMediaStoreRow(path)
            scanMediaPath(path)
            return true
        }
        try {
            targetFile.delete()
        } catch (_: Exception) {
        }
        val itemUri = findMediaStoreAudioUri(path)
        if (targetFile.exists()) {
            purgeMediaStoreRow(path, itemUri)
        } else {
            purgeMediaStoreRow(path, itemUri)
        }
        val physicallyDeleted = !targetFile.exists()
        if (physicallyDeleted) {
            deleteCompanionLrcIfPresent(path)
            scanMediaPath(path)
        }
        return physicallyDeleted
    }

    @Suppress("DEPRECATION")
    private fun deleteLocalAudioFileLayered(
        path: String,
        allowSystemPrompt: Boolean,
        result: MethodChannel.Result
    ) {
        // Layer 1: Release MediaPlayer file lock if this track is currently loaded
        if (currentLocalPath == path) {
            stopLocalAudio(notifyFlutter = false, abandonFocus = true)
        }

        val targetFile = File(path)
        if (!targetFile.exists()) {
            deleteCompanionLrcIfPresent(path)
            purgeMediaStoreRow(path)
            scanMediaPath(path)
            result.success(
                mapOf(
                    "deleted" to true,
                    "needsAllFilesAccess" to false,
                    "cancelledByUser" to false
                )
            )
            return
        }

        // Layer 2: Direct filesystem delete (succeeds for app-owned files or All Files Access)
        try {
            targetFile.delete()
        } catch (_: Exception) {
        }

        // Layer 3: MediaStore ContentResolver delete (both by _ID item Uri and DATA=?)
        val itemUri = findMediaStoreAudioUri(path)
        if (targetFile.exists()) {
            purgeMediaStoreRow(path, itemUri)
        } else {
            purgeMediaStoreRow(path, itemUri)
        }

        if (!targetFile.exists()) {
            deleteCompanionLrcIfPresent(path)
            scanMediaPath(path)
            result.success(
                mapOf(
                    "deleted" to true,
                    "needsAllFilesAccess" to false,
                    "cancelledByUser" to false
                )
            )
            return
        }

        // Layer 4: Android 11-15 Scoped Storage OS confirmation sheet or All Files Access signal
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (allowSystemPrompt && itemUri != null && pendingDeleteResult == null) {
                try {
                    val pi = MediaStore.createDeleteRequest(
                        applicationContext.contentResolver,
                        listOf(itemUri)
                    )
                    pendingDeleteResult = result
                    pendingDeletePath = path
                    startIntentSenderForResult(
                        pi.intentSender,
                        reqDeleteMedia,
                        null,
                        0,
                        0,
                        0,
                        null
                    )
                    return
                } catch (_: Exception) {
                    pendingDeleteResult = null
                    pendingDeletePath = null
                }
            }

            val needsAllFiles = !Environment.isExternalStorageManager()
            result.success(
                mapOf(
                    "deleted" to false,
                    "needsAllFilesAccess" to needsAllFiles,
                    "cancelledByUser" to false
                )
            )
            return
        }

        val gone = !targetFile.exists()
        if (gone) {
            scanMediaPath(path)
        }
        result.success(
            mapOf(
                "deleted" to gone,
                "needsAllFilesAccess" to false,
                "cancelledByUser" to false
            )
        )
    }

    @Suppress("DEPRECATION")
    private fun writeBytesToMusicFileLayered(
        path: String,
        bytes: ByteArray,
        allowSystemPrompt: Boolean,
        result: MethodChannel.Result
    ) {
        if (currentLocalPath == path) {
            stopLocalAudio(notifyFlutter = false, abandonFocus = true)
        }

        val targetFile = File(path)
        try {
            targetFile.parentFile?.let { parent ->
                if (!parent.exists()) parent.mkdirs()
            }
            FileOutputStream(targetFile, false).use { out ->
                out.write(bytes)
                out.flush()
            }
            if (targetFile.exists() && targetFile.length() > 0L) {
                scanMediaPath(path, "audio/mpeg")
                result.success(
                    mapOf(
                        "written" to true,
                        "needsAllFilesAccess" to false,
                        "cancelledByUser" to false
                    )
                )
                return
            }
        } catch (_: Exception) {
        }

        val itemUri = findMediaStoreAudioUri(path)
        if (itemUri != null) {
            try {
                applicationContext.contentResolver.openOutputStream(itemUri, "rwt")?.use { out ->
                    out.write(bytes)
                    out.flush()
                }
                if (targetFile.exists() && targetFile.length() > 0L) {
                    scanMediaPath(path, "audio/mpeg")
                    result.success(
                        mapOf(
                            "written" to true,
                            "needsAllFilesAccess" to false,
                            "cancelledByUser" to false
                        )
                    )
                    return
                }
            } catch (_: Exception) {
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (allowSystemPrompt && itemUri != null && pendingWriteResult == null) {
                try {
                    val pi = MediaStore.createWriteRequest(
                        applicationContext.contentResolver,
                        listOf(itemUri)
                    )
                    pendingWriteResult = result
                    pendingWritePath = path
                    pendingWriteBytes = bytes
                    startIntentSenderForResult(
                        pi.intentSender,
                        reqWriteMedia,
                        null,
                        0,
                        0,
                        0,
                        null
                    )
                    return
                } catch (_: Exception) {
                    pendingWriteResult = null
                    pendingWritePath = null
                    pendingWriteBytes = null
                }
            }

            val needsAllFiles = !Environment.isExternalStorageManager()
            result.success(
                mapOf(
                    "written" to false,
                    "needsAllFilesAccess" to needsAllFiles,
                    "cancelledByUser" to false
                )
            )
            return
        }

        result.success(
            mapOf(
                "written" to false,
                "needsAllFilesAccess" to false,
                "cancelledByUser" to false
            )
        )
    }

    private fun hasAllFilesAccessNow(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
            Environment.isExternalStorageManager()
    }

    private fun hasNotificationPermissionNow(): Boolean {
        val nm = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        val systemEnabled = nm?.areNotificationsEnabled() ?: true
        if (!systemEnabled) return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    @Suppress("DEPRECATION")
    private fun requestAllFilesAccessNative(result: MethodChannel.Result) {
        if (hasAllFilesAccessNow()) {
            result.success(true)
            return
        }
        if (pendingAllFilesResult != null) {
            result.success(false)
            return
        }
        try {
            pendingAllFilesResult = result
            val appIntent = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:$packageName")
            )
            if (appIntent.resolveActivity(packageManager) != null) {
                startActivityForResult(appIntent, reqAllFilesAccess)
            } else {
                val fallbackIntent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                startActivityForResult(fallbackIntent, reqAllFilesAccess)
            }
        } catch (_: Exception) {
            pendingAllFilesResult = null
            result.success(false)
        }
    }

    @Suppress("DEPRECATION")
    private fun requestNotificationPermissionNative(result: MethodChannel.Result) {
        if (hasNotificationPermissionNow()) {
            result.success(true)
            return
        }
        if (pendingNotificationResult != null) {
            result.success(false)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            try {
                pendingNotificationResult = result
                requestPermissions(
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    reqNotificationPermission
                )
                return
            } catch (_: Exception) {
                pendingNotificationResult = null
            }
        }
        openAppNotificationSettingsNative(result)
    }

    @Suppress("DEPRECATION")
    private fun openAppNotificationSettingsNative(result: MethodChannel.Result) {
        try {
            pendingNotificationResult = result
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                }
            } else {
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName")
                )
            }
            startActivityForResult(intent, reqNotificationSettings)
        } catch (_: Exception) {
            pendingNotificationResult = null
            result.success(hasNotificationPermissionNow())
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == reqNotificationPermission) {
            val cb = pendingNotificationResult
            pendingNotificationResult = null
            val granted = hasNotificationPermissionNow()
            if (granted) {
                cb?.success(true)
            } else {
                // If user permanently denied runtime prompt or disabled notifications in OS settings,
                // open the app notification settings page so they can toggle it on directly.
                val canShowRationale = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)
                if (!canShowRationale && cb != null) {
                    openAppNotificationSettingsNative(cb)
                } else {
                    cb?.success(false)
                }
            }
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        when (requestCode) {
            reqAllFilesAccess -> {
                val cb = pendingAllFilesResult
                pendingAllFilesResult = null
                cb?.success(hasAllFilesAccessNow())
                return
            }
            reqNotificationSettings -> {
                val cb = pendingNotificationResult
                pendingNotificationResult = null
                cb?.success(hasNotificationPermissionNow())
                return
            }
            reqDeleteMedia -> {
                val cb = pendingDeleteResult
                val path = pendingDeletePath
                pendingDeleteResult = null
                pendingDeletePath = null

                if (path != null) {
                    val f = File(path)
                    if (resultCode == Activity.RESULT_OK && f.exists()) {
                        try {
                            f.delete()
                        } catch (_: Exception) {
                        }
                        if (f.exists()) {
                            purgeMediaStoreRow(path, findMediaStoreAudioUri(path))
                        }
                    }
                    val gone = !f.exists()
                    if (gone) {
                        deleteCompanionLrcIfPresent(path)
                        scanMediaPath(path)
                    }
                    val cancelled = !gone && resultCode == Activity.RESULT_CANCELED
                    val needsAllFiles = !gone &&
                        !cancelled &&
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                        !Environment.isExternalStorageManager()
                    cb?.success(
                        mapOf(
                            "deleted" to gone,
                            "needsAllFilesAccess" to needsAllFiles,
                            "cancelledByUser" to cancelled
                        )
                    )
                } else {
                    cb?.success(
                        mapOf(
                            "deleted" to false,
                            "needsAllFilesAccess" to false,
                            "cancelledByUser" to true
                        )
                    )
                }
                return
            }
            reqWriteMedia -> {
                val cb = pendingWriteResult
                val path = pendingWritePath
                val bytes = pendingWriteBytes
                pendingWriteResult = null
                pendingWritePath = null
                pendingWriteBytes = null

                if (path != null && bytes != null && resultCode == Activity.RESULT_OK) {
                    var written = false
                    val itemUri = findMediaStoreAudioUri(path)
                    if (itemUri != null) {
                        try {
                            applicationContext.contentResolver.openOutputStream(itemUri, "rwt")
                                ?.use { out ->
                                    out.write(bytes)
                                    out.flush()
                                }
                            written = true
                        } catch (_: Exception) {
                        }
                    }
                    if (!written) {
                        try {
                            FileOutputStream(File(path), false).use { out ->
                                out.write(bytes)
                                out.flush()
                            }
                            written = true
                        } catch (_: Exception) {
                        }
                    }
                    if (written) {
                        scanMediaPath(path, "audio/mpeg")
                    }
                    val needsAllFiles = !written &&
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                        !Environment.isExternalStorageManager()
                    cb?.success(
                        mapOf(
                            "written" to written,
                            "needsAllFilesAccess" to needsAllFiles,
                            "cancelledByUser" to false
                        )
                    )
                } else {
                    val cancelled = resultCode == Activity.RESULT_CANCELED
                    val needsAllFiles = !cancelled &&
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                        !Environment.isExternalStorageManager()
                    cb?.success(
                        mapOf(
                            "written" to false,
                            "needsAllFilesAccess" to needsAllFiles,
                            "cancelledByUser" to cancelled
                        )
                    )
                }
                return
            }
            reqPickDirectoryTree -> {
                val cb = pendingPickDirectoryResult
                pendingPickDirectoryResult = null
                if (resultCode == Activity.RESULT_OK && data?.data != null) {
                    val treeUri = data.data!!
                    try {
                        val takeFlags = data.flags and
                            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        contentResolver.takePersistableUriPermission(treeUri, takeFlags)
                    } catch (_: Exception) {
                    }
                    val resolvedPath = resolveTreeUriToFileSystemPath(treeUri)
                    cb?.success(resolvedPath)
                } else {
                    cb?.success(null)
                }
                return
            }
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun openSystemDirectoryPickerNative(result: MethodChannel.Result) {
        try {
            pendingPickDirectoryResult?.success(null)
            pendingPickDirectoryResult = result
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                )
            }
            startActivityForResult(intent, reqPickDirectoryTree)
        } catch (_: Exception) {
            pendingPickDirectoryResult = null
            result.success(null)
        }
    }

    private fun resolveTreeUriToFileSystemPath(treeUri: Uri): String? {
        try {
            val rawPath = Uri.decode(treeUri.toString())
            val primaryMarker = "primary:"
            val idx = rawPath.lastIndexOf(primaryMarker)
            if (idx != -1) {
                val rel = rawPath.substring(idx + primaryMarker.length).trim('/')
                return if (rel.isEmpty()) {
                    "/storage/emulated/0/Music"
                } else {
                    "/storage/emulated/0/$rel"
                }
            }
            val treeSeg = treeUri.lastPathSegment ?: return null
            if (treeSeg.startsWith("primary:")) {
                val rel = treeSeg.removePrefix("primary:").trim('/')
                return if (rel.isEmpty()) {
                    "/storage/emulated/0/Music"
                } else {
                    "/storage/emulated/0/$rel"
                }
            }
            if (treeSeg.contains(":")) {
                val parts = treeSeg.split(":", limit = 2)
                val vol = parts[0]
                val rel = parts.getOrNull(1)?.trim('/') ?: ""
                if (vol.equals("home", ignoreCase = true)) {
                    return if (rel.isEmpty()) "/storage/emulated/0/Documents" else "/storage/emulated/0/Documents/$rel"
                }
                val candidate = if (rel.isEmpty()) "/storage/$vol" else "/storage/$vol/$rel"
                if (File(candidate).exists()) return candidate
            }
        } catch (_: Exception) {
        }
        return null
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
        pendingAllFilesResult = null
        pendingNotificationResult = null
        pendingPickDirectoryResult = null
        pendingDeleteResult = null
        pendingDeletePath = null
        pendingWriteResult = null
        pendingWritePath = null
        pendingWriteBytes = null
        stopPreviewAudio(notifyFlutter = false, allowResumeLocal = false)
        stopLocalAudio(notifyFlutter = false, abandonFocus = true)
        mediaNotifier?.release()
        mediaNotifier = null
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

    /**
     * Synchronizes persistent user state (`musicevee_playlists_v1.json`,
     * `musevee_favorites.json`, `musevee_library_cache_v1.json`,
     * `musevee_player_session.json`, `musevee_hidden_folders_v1.json`,
     * `last_selected_folder.txt`, and `FlutterSharedPreferences.xml`)
     * with `/storage/emulated/0/Music/.musevee_state/` so playlists, favorites,
     * hidden folders, and playback state seamlessly survive package ID migrations or reinstalls.
     */
    private fun syncPersistentAppState() {
        try {
            val backupDir = File("/storage/emulated/0/Music/.musevee_state")
            if (!backupDir.exists()) {
                backupDir.mkdirs()
            }
            if (!backupDir.exists() || !backupDir.canWrite()) return

            val dataRoot = File(applicationInfo.dataDir)
            val appFlutterDir = File(dataRoot, "app_flutter").apply { if (!exists()) mkdirs() }
            val sharedPrefsDir = File(dataRoot, "shared_preferences").apply { if (!exists()) mkdirs() }

            val trackedFiles = listOf(
                File(appFlutterDir, "musicevee_playlists_v1.json") to File(backupDir, "musicevee_playlists_v1.json"),
                File(appFlutterDir, "musevee_playlists_v1.json") to File(backupDir, "musevee_playlists_v1.json"),
                File(appFlutterDir, "musevee_favorites.json") to File(backupDir, "musevee_favorites.json"),
                File(appFlutterDir, "musicevee_favorites.json") to File(backupDir, "musicevee_favorites.json"),
                File(appFlutterDir, "musevee_library_cache_v1.json") to File(backupDir, "musevee_library_cache_v1.json"),
                File(appFlutterDir, "musicevee_library_cache_v1.json") to File(backupDir, "musicevee_library_cache_v1.json"),
                File(appFlutterDir, "musevee_player_session.json") to File(backupDir, "musevee_player_session.json"),
                File(appFlutterDir, "musicevee_player_session.json") to File(backupDir, "musicevee_player_session.json"),
                File(appFlutterDir, "musevee_hidden_folders_v1.json") to File(backupDir, "musevee_hidden_folders_v1.json"),
                File(appFlutterDir, "musevee_play_stats_v1.json") to File(backupDir, "musevee_play_stats_v1.json"),
                File(appFlutterDir, "musevee_custom_folders_v1.json") to File(backupDir, "musevee_custom_folders_v1.json"),
                File(appFlutterDir, "last_selected_folder.txt") to File(backupDir, "last_selected_folder.txt"),
                File(sharedPrefsDir, "FlutterSharedPreferences.xml") to File(backupDir, "FlutterSharedPreferences.xml")
            )

            for ((internalFile, externalFile) in trackedFiles) {
                val internalValid = internalFile.exists() && internalFile.length() > 1L
                val externalValid = externalFile.exists() && externalFile.length() > 1L
                if (internalValid && (!externalValid || internalFile.lastModified() >= externalFile.lastModified())) {
                    internalFile.copyTo(externalFile, overwrite = true)
                } else if (!internalValid && externalValid) {
                    externalFile.copyTo(internalFile, overwrite = true)
                }
            }
        } catch (_: Exception) {
        }
    }
}

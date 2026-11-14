package com.example.spotmeta_downloader

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.audiofx.LoudnessEnhancer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Application-scoped singleton audio playback engine shared between [MainActivity]
 * and [MusEveePlaybackService] so offline playback, `PARTIAL_WAKE_LOCK`,
 * `ACTION_AUDIO_BECOMING_NOISY` auto-pause, Sleep Timer, MediaSession controls,
 * and queue track progression continue seamlessly even if the UI Activity is
 * closed or swiped away from Recent Apps while playing.
 */
object MusEveeAudioEngine {
    data class QueueTrack(
        val path: String,
        val title: String,
        val artist: String,
        val album: String,
        val coverPath: String?,
        val durationMs: Long
    )

    private var appContext: Context? = null
    private var methodChannel: MethodChannel? = null
    private var mediaNotifier: MusEveeMediaNotifier? = null

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

    @Volatile
    var isPreviewActive: Boolean = false

    // Background queue mirror & play mode (`0=repeatAll, 1=repeatOne, 2=playSingleStop, 3=playQueueOnce`)
    private var queueTracks: List<QueueTrack> = emptyList()
    private var queueIndex: Int = -1
    private var playModeIndex: Int = 0

    // Offline Sleep Timer state (runs on mainHandler even if Flutter UI is detached)
    private var sleepDeadlineElapsedMs: Long = 0L
    private var sleepAfterCurrentTrack: Boolean = false
    private var noisyReceiverRegistered: Boolean = false

    private val mainHandler = Handler(Looper.getMainLooper())

    val playbackAudioAttributes: AudioAttributes by lazy {
        AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .build()
    }

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                mainHandler.post {
                    if (isActivelyPlaying()) {
                        pauseLocalAudioByUser()
                    }
                }
            }
        }
    }

    private val sleepTimerRunnable = Runnable {
        sleepDeadlineElapsedMs = 0L
        sleepAfterCurrentTrack = false
        if (isActivelyPlaying()) {
            pauseLocalAudioByUser()
        }
        methodChannel?.invokeMethod("onSleepTimerExpired", null)
    }

    private val localAudioFocusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        if (isPreviewActive) return@OnAudioFocusChangeListener

        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                resumeLocalOnFocusGain = false
                resumeLocalAfterPreview = false
                pauseLocalAudioInternal(abandonFocus = true)
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                val wasPlaying = isActivelyPlaying()
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
                if (resumeLocalOnFocusGain && !isPreviewActive) {
                    resumeLocalOnFocusGain = false
                    resumeLocalAudio()
                }
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

    fun init(context: Context) {
        val ctx = context.applicationContext
        if (appContext == null) {
            appContext = ctx
        }
        if (mediaNotifier == null) {
            mediaNotifier = MusEveeMediaNotifier(ctx) { action, positionMs ->
                mainHandler.post {
                    handleMediaNotificationAction(action, positionMs)
                }
            }
        }
    }

    fun attachMethodChannel(context: Context, channel: MethodChannel) {
        init(context)
        methodChannel = channel
        if (isActivelyPlaying()) {
            startPositionTicker()
        }
    }

    fun detachMethodChannel(channel: MethodChannel?) {
        if (channel == null || methodChannel === channel) {
            methodChannel = null
        }
    }

    fun isActivelyPlaying(): Boolean {
        return try {
            isLocalPrepared && localPlayer?.isPlaying == true
        } catch (_: Exception) {
            false
        }
    }

    fun hasActiveTrack(): Boolean = currentLocalPath != null && localPlayer != null

    fun getCurrentAudioSessionId(): Int {
        return try {
            localPlayer?.audioSessionId ?: 0
        } catch (_: Exception) {
            0
        }
    }

    fun getNormalizedVolume(): Double = currentNormalizedVolume.coerceIn(0f, 1f).toDouble()

    fun setNormalizedVolume(normalized: Float) {
        currentNormalizedVolume = normalized.coerceIn(0f, 1f)
        try {
            localPlayer?.setVolume(currentNormalizedVolume, currentNormalizedVolume)
        } catch (_: Exception) {
        }
    }

    fun setPreAmpGainDb(gainDb: Double) {
        currentPreAmpGainMb = Math.round(gainDb.coerceIn(0.0, 12.0) * 100.0).toInt()
        localPlayer?.let { applyLoudnessEnhancerToPlayer(it) }
    }

    fun syncQueue(items: List<QueueTrack>, currentIdx: Int, modeIndex: Int) {
        queueTracks = items
        queueIndex = if (items.isEmpty()) -1 else currentIdx.coerceIn(0, items.lastIndex)
        playModeIndex = modeIndex.coerceIn(0, 3)
    }

    fun setSleepTimer(context: Context, durationMs: Long, afterCurrentTrack: Boolean) {
        init(context)
        mainHandler.removeCallbacks(sleepTimerRunnable)
        sleepDeadlineElapsedMs = 0L
        sleepAfterCurrentTrack = afterCurrentTrack
        if (!afterCurrentTrack && durationMs > 0L) {
            sleepDeadlineElapsedMs = SystemClock.elapsedRealtime() + durationMs
            mainHandler.postDelayed(sleepTimerRunnable, durationMs)
        }
    }

    fun cancelSleepTimer() {
        mainHandler.removeCallbacks(sleepTimerRunnable)
        sleepDeadlineElapsedMs = 0L
        sleepAfterCurrentTrack = false
    }

    fun getSleepRemainingMs(): Long {
        if (sleepDeadlineElapsedMs <= 0L) return 0L
        val remaining = sleepDeadlineElapsedMs - SystemClock.elapsedRealtime()
        if (remaining <= 0L) {
            sleepDeadlineElapsedMs = 0L
            return 0L
        }
        return remaining
    }

    fun getPlaybackSnapshot(): Map<String, Any?> {
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
        return mapOf(
            "hasActiveTrack" to hasActiveTrack(),
            "isPlaying" to isActivelyPlaying(),
            "path" to currentLocalPath,
            "index" to queueIndex,
            "positionMs" to pos,
            "durationMs" to dur,
            "sessionId" to currentLocalSessionId,
            "volume" to getNormalizedVolume(),
            "preAmpDb" to (currentPreAmpGainMb / 100.0),
            "sleepRemainingMs" to getSleepRemainingMs(),
            "sleepAfterCurrentTrack" to sleepAfterCurrentTrack,
            "playModeIndex" to playModeIndex
        )
    }

    private fun registerNoisyReceiver() {
        val ctx = appContext ?: return
        if (noisyReceiverRegistered) return
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ctx.registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                ctx.registerReceiver(noisyReceiver, filter)
            }
            noisyReceiverRegistered = true
        } catch (_: Exception) {
        }
    }

    private fun unregisterNoisyReceiver() {
        val ctx = appContext ?: return
        if (!noisyReceiverRegistered) return
        try {
            ctx.unregisterReceiver(noisyReceiver)
        } catch (_: Exception) {
        }
        noisyReceiverRegistered = false
    }

    @Suppress("DEPRECATION")
    private fun requestLocalAudioFocus(): Boolean {
        val ctx = appContext ?: return true
        val audioManager = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
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
        val ctx = appContext ?: return
        val audioManager = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                localFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            } else {
                audioManager.abandonAudioFocus(localAudioFocusListener)
            }
        } catch (_: Exception) {
        }
    }

    fun updateMediaNotification(
        context: Context,
        title: String,
        artist: String,
        album: String,
        coverPath: String?,
        durationMs: Long
    ) {
        init(context)
        mediaNotifier?.updateMetadata(
            newTitle = title,
            newArtist = artist,
            newAlbum = album,
            coverPath = coverPath,
            newDurationMs = durationMs
        )
        val mp = localPlayer
        val playing = isActivelyPlaying()
        val pos = try {
            if (isLocalPrepared && mp != null) mp.currentPosition.toLong() else 0L
        } catch (_: Exception) {
            0L
        }
        mediaNotifier?.updatePlaybackState(playing, pos)
    }

    fun playLocalAudioFile(
        context: Context,
        path: String,
        startPositionMs: Int,
        requestedSessionId: Int,
        title: String?,
        artist: String?,
        album: String?,
        coverPath: String?,
        durationMs: Long
    ): Boolean {
        init(context)
        val ctx = appContext ?: return false
        val file = File(path)
        if (!file.exists()) {
            return false
        }

        val matchingIdx = queueTracks.indexOfFirst { it.path == path }
        if (matchingIdx >= 0) {
            queueIndex = matchingIdx
        }

        resumeLocalAfterPreview = false
        resumeLocalOnFocusGain = false
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

        return try {
            requestLocalAudioFocus()
            registerNoisyReceiver()
            val player = MediaPlayer()
            localPlayer = player
            currentLocalPath = capturedPath
            isLocalPrepared = false

            try {
                player.setWakeMode(ctx, PowerManager.PARTIAL_WAKE_LOCK)
            } catch (_: Exception) {
            }
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

                if (sleepAfterCurrentTrack) {
                    sleepAfterCurrentTrack = false
                    sleepDeadlineElapsedMs = 0L
                    try {
                        if (mp.isPlaying) mp.pause()
                        mp.seekTo(0)
                    } catch (_: Exception) {
                    }
                    abandonLocalAudioFocus()
                    notifyLocalPlayerState(isPlaying = false)
                    methodChannel?.invokeMethod("onSleepTimerExpired", null)
                    return@setOnCompletionListener
                }

                val dur = try {
                    mp.duration
                } catch (_: Exception) {
                    0
                }
                val ch = methodChannel
                if (ch != null) {
                    ch.invokeMethod(
                        "onLocalTrackCompleted",
                        mapOf(
                            "path" to capturedPath,
                            "sessionId" to capturedSessionId,
                            "durationMs" to dur
                        )
                    )
                } else {
                    handleAutonomousTrackCompletion()
                }
            }
            player.setOnErrorListener { mp, _, _ ->
                if (mp === localPlayer && capturedSessionId == currentLocalSessionId) {
                    stopLocalAudio(notifyFlutter = true, abandonFocus = true)
                }
                true
            }
            player.prepareAsync()
            true
        } catch (_: Exception) {
            stopLocalAudio(notifyFlutter = true, abandonFocus = true)
            false
        }
    }

    fun pauseLocalAudioForPreview() {
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

    fun resumeLocalAfterPreviewIfNeeded() {
        if (resumeLocalAfterPreview) {
            resumeLocalAfterPreview = false
            resumeLocalAudio()
        }
    }

    fun clearResumeAfterPreviewFlag() {
        resumeLocalAfterPreview = false
    }

    fun pauseLocalAudioByUser() {
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

    fun resumeLocalAudio(): Boolean {
        val mp = localPlayer ?: return false
        if (!isLocalPrepared) return false
        return try {
            resumeLocalAfterPreview = false
            requestLocalAudioFocus()
            registerNoisyReceiver()
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

    fun seekLocalAudio(positionMs: Int): Boolean {
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

    fun stopLocalAudioIfPath(path: String) {
        if (currentLocalPath == path) {
            stopLocalAudio(notifyFlutter = false, abandonFocus = true)
        }
    }

    fun stopLocalAudio(notifyFlutter: Boolean, abandonFocus: Boolean = true) {
        stopPositionTicker()
        if (notifyFlutter) {
            resumeLocalOnFocusGain = false
            resumeLocalAfterPreview = false
            cancelSleepTimer()
        }
        unregisterNoisyReceiver()
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

    private fun handleAutonomousTrackCompletion() {
        val ctx = appContext ?: return
        if (queueTracks.isEmpty()) {
            stopLocalAudio(notifyFlutter = true, abandonFocus = true)
            return
        }
        when (playModeIndex) {
            // 2 = MusicoletPlayMode.playSingleStop (`1→`)
            2 -> {
                seekLocalAudio(0)
                pauseLocalAudioInternal(abandonFocus = true)
            }
            // 1 = MusicoletPlayMode.repeatOne
            1 -> {
                val track = queueTracks.getOrNull(queueIndex) ?: queueTracks.first()
                playLocalAudioFile(
                    context = ctx,
                    path = track.path,
                    startPositionMs = 0,
                    requestedSessionId = currentLocalSessionId + 1,
                    title = track.title,
                    artist = track.artist,
                    album = track.album,
                    coverPath = track.coverPath,
                    durationMs = track.durationMs
                )
            }
            // 3 = MusicoletPlayMode.playQueueOnce (`→|`)
            3 -> {
                if (queueIndex + 1 < queueTracks.size) {
                    queueIndex++
                    val track = queueTracks[queueIndex]
                    playLocalAudioFile(
                        context = ctx,
                        path = track.path,
                        startPositionMs = 0,
                        requestedSessionId = currentLocalSessionId + 1,
                        title = track.title,
                        artist = track.artist,
                        album = track.album,
                        coverPath = track.coverPath,
                        durationMs = track.durationMs
                    )
                } else {
                    seekLocalAudio(0)
                    pauseLocalAudioInternal(abandonFocus = true)
                }
            }
            // 0 = MusicoletPlayMode.repeatAll
            else -> {
                queueIndex = (queueIndex + 1) % queueTracks.size
                val track = queueTracks[queueIndex]
                playLocalAudioFile(
                    context = ctx,
                    path = track.path,
                    startPositionMs = 0,
                    requestedSessionId = currentLocalSessionId + 1,
                    title = track.title,
                    artist = track.artist,
                    album = track.album,
                    coverPath = track.coverPath,
                    durationMs = track.durationMs
                )
            }
        }
    }

    private fun handleMediaNotificationAction(action: String, positionMs: Long) {
        val ch = methodChannel
        when (action) {
            "pause" -> pauseLocalAudioByUser()
            "play" -> {
                if (!resumeLocalAudio()) {
                    if (ch != null) {
                        ch.invokeMethod(
                            "onMediaNotificationAction",
                            mapOf("action" to "play", "positionMs" to 0)
                        )
                    } else {
                        val ctx = appContext
                        val track = queueTracks.getOrNull(queueIndex) ?: queueTracks.firstOrNull()
                        if (ctx != null && track != null) {
                            playLocalAudioFile(
                                context = ctx,
                                path = track.path,
                                startPositionMs = 0,
                                requestedSessionId = currentLocalSessionId + 1,
                                title = track.title,
                                artist = track.artist,
                                album = track.album,
                                coverPath = track.coverPath,
                                durationMs = track.durationMs
                            )
                        }
                    }
                }
            }
            "seek" -> seekLocalAudio(positionMs.toInt())
            "next" -> {
                if (ch != null) {
                    ch.invokeMethod(
                        "onMediaNotificationAction",
                        mapOf("action" to "next", "positionMs" to 0)
                    )
                } else if (queueTracks.isNotEmpty()) {
                    val ctx = appContext ?: return
                    queueIndex = (queueIndex + 1) % queueTracks.size
                    val track = queueTracks[queueIndex]
                    playLocalAudioFile(
                        context = ctx,
                        path = track.path,
                        startPositionMs = 0,
                        requestedSessionId = currentLocalSessionId + 1,
                        title = track.title,
                        artist = track.artist,
                        album = track.album,
                        coverPath = track.coverPath,
                        durationMs = track.durationMs
                    )
                }
            }
            "previous" -> {
                if (ch != null) {
                    ch.invokeMethod(
                        "onMediaNotificationAction",
                        mapOf("action" to "previous", "positionMs" to 0)
                    )
                } else if (queueTracks.isNotEmpty()) {
                    val currentPos = try {
                        if (isLocalPrepared && localPlayer != null) localPlayer!!.currentPosition else 0
                    } catch (_: Exception) {
                        0
                    }
                    if (currentPos > 3500) {
                        seekLocalAudio(0)
                    } else {
                        val ctx = appContext ?: return
                        queueIndex = if (queueIndex > 0) queueIndex - 1 else queueTracks.lastIndex
                        val track = queueTracks[queueIndex]
                        playLocalAudioFile(
                            context = ctx,
                            path = track.path,
                            startPositionMs = 0,
                            requestedSessionId = currentLocalSessionId + 1,
                            title = track.title,
                            artist = track.artist,
                            album = track.album,
                            coverPath = track.coverPath,
                            durationMs = track.durationMs
                        )
                    }
                }
            }
            "stop" -> {
                stopLocalAudio(notifyFlutter = true, abandonFocus = true)
            }
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
}

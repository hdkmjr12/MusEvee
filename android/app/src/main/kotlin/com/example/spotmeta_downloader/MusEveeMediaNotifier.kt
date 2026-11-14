package com.example.spotmeta_downloader

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import java.io.File
import java.util.Locale

/**
 * MusEvee native media notification: framework [MediaSession] +
 * [Notification.MediaStyle] (Play/Pause, Next, Prev, Close & system Seekbar)
 * visible in the notification shade, lockscreen, Bluetooth & headset buttons.
 *
 * All transport commands are forwarded through [onAction] (`play`, `pause`,
 * `next`, `previous`, `seek`, `stop`) so the Flutter `LocalMusicProvider`
 * queue stays the single source of truth.
 */
class MusEveeMediaNotifier(
    private val activity: Activity,
    private val onAction: (action: String, positionMs: Long) -> Unit
) {
    companion object {
        const val CHANNEL_ID = "musevee_playback"
        const val NOTIFICATION_ID = 4207
        const val ACTION_PLAY = "com.example.spotmeta_downloader.media.PLAY"
        const val ACTION_PAUSE = "com.example.spotmeta_downloader.media.PAUSE"
        const val ACTION_NEXT = "com.example.spotmeta_downloader.media.NEXT"
        const val ACTION_PREVIOUS = "com.example.spotmeta_downloader.media.PREVIOUS"
        const val ACTION_STOP = "com.example.spotmeta_downloader.media.STOP"
    }

    private val appContext: Context = activity.applicationContext
    private val notificationManager =
        appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private val mainHandler = Handler(Looper.getMainLooper())
    private val session: MediaSession = MediaSession(appContext, "MusEveeSession")

    private var title: String = ""
    private var artist: String = ""
    private var album: String = ""
    private var durationMs: Long = 0L
    private var artwork: Bitmap? = null
    private var artworkPath: String? = null
    private var isPlaying: Boolean = false
    private var positionMs: Long = 0L
    private var hasTrack: Boolean = false
    private var receiverRegistered = false

    private val actionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_PLAY -> onAction("play", 0L)
                ACTION_PAUSE -> onAction("pause", 0L)
                ACTION_NEXT -> onAction("next", 0L)
                ACTION_PREVIOUS -> onAction("previous", 0L)
                ACTION_STOP -> onAction("stop", 0L)
            }
        }
    }

    init {
        createChannel()
        session.setCallback(object : MediaSession.Callback() {
            override fun onPlay() = onAction("play", 0L)
            override fun onPause() = onAction("pause", 0L)
            override fun onSkipToNext() = onAction("next", 0L)
            override fun onSkipToPrevious() = onAction("previous", 0L)
            override fun onSeekTo(pos: Long) = onAction("seek", pos)
            override fun onStop() = onAction("stop", 0L)
        })
        session.setSessionActivity(contentIntent())

        val filter = IntentFilter().apply {
            addAction(ACTION_PLAY)
            addAction(ACTION_PAUSE)
            addAction(ACTION_NEXT)
            addAction(ACTION_PREVIOUS)
            addAction(ACTION_STOP)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                appContext.registerReceiver(actionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                appContext.registerReceiver(actionReceiver, filter)
            }
            receiverRegistered = true
        } catch (_: Exception) {
        }
    }

    private fun isIndonesianLocale(): Boolean {
        val lang = Locale.getDefault().language.lowercase(Locale.ROOT)
        return lang == "id" || lang == "in"
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val isId = isIndonesianLocale()
        val channelName = if (isId) "Pemutar MusEvee" else "MusEvee Player"
        val channelDesc = if (isId) {
            "Kontrol pemutaran musik MusEvee"
        } else {
            "MusEvee music playback controls"
        }
        val existing = notificationManager.getNotificationChannel(CHANNEL_ID)
        if (existing != null && existing.name?.toString() == channelName) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            channelName,
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = channelDesc
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun pendingFlags(): Int =
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    private fun contentIntent(): PendingIntent {
        val intent = Intent(appContext, activity.javaClass).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(appContext, 0, intent, pendingFlags())
    }

    private fun broadcastIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(action).setPackage(appContext.packageName)
        return PendingIntent.getBroadcast(appContext, requestCode, intent, pendingFlags())
    }

    /** Updates track metadata (title/artist/album/cover/duration). */
    fun updateMetadata(
        newTitle: String,
        newArtist: String,
        newAlbum: String,
        coverPath: String?,
        newDurationMs: Long
    ) {
        title = newTitle
        artist = newArtist
        album = newAlbum
        if (newDurationMs > 0) durationMs = newDurationMs
        hasTrack = true

        if (coverPath != artworkPath) {
            artworkPath = coverPath
            artwork = decodeArtwork(coverPath)
        }

        val builder = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, title)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadata.METADATA_KEY_ALBUM, album)
            .putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs)
        artwork?.let {
            builder.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, it)
            builder.putBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON, it)
        }
        session.setMetadata(builder.build())
    }

    fun updateDuration(newDurationMs: Long) {
        if (newDurationMs <= 0 || newDurationMs == durationMs || !hasTrack) return
        updateMetadata(title, artist, album, artworkPath, newDurationMs)
    }

    /** Updates playback state + re-posts the media notification. */
    fun updatePlaybackState(playing: Boolean, newPositionMs: Long) {
        if (!hasTrack) return
        isPlaying = playing
        positionMs = newPositionMs.coerceAtLeast(0L)

        val actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_SKIP_TO_NEXT or
            PlaybackState.ACTION_SKIP_TO_PREVIOUS or
            PlaybackState.ACTION_SEEK_TO or
            PlaybackState.ACTION_STOP
        val state = PlaybackState.Builder()
            .setActions(actions)
            .setState(
                if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                positionMs,
                if (playing) 1.0f else 0f,
                SystemClock.elapsedRealtime()
            )
            .build()
        val wasActive = session.isActive
        if (!wasActive) {
            session.isActive = true
        }
        session.setPlaybackState(state)
        if (!wasActive) {
            // ZTE DynamicIslandManager registers its MediaController.Callback asynchronously
            // inside onActiveSessionsChanged; re-emit PlaybackState once registered.
            mainHandler.postDelayed({
                if (hasTrack && session.isActive) {
                    val refreshState = PlaybackState.Builder()
                        .setActions(actions)
                        .setState(
                            if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                            positionMs,
                            if (isPlaying) 1.0f else 0f,
                            SystemClock.elapsedRealtime()
                        )
                        .build()
                    session.setPlaybackState(refreshState)
                }
            }, 180L)
        }

        postNotification()
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(appContext, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(appContext)
        }

        val isId = isIndonesianLocale()
        val pauseLabel = if (isId) "Jeda" else "Pause"
        val playLabel = if (isId) "Putar" else "Play"
        val prevLabel = if (isId) "Sebelumnya" else "Previous"
        val nextLabel = if (isId) "Berikutnya" else "Next"
        val closeLabel = if (isId) "Tutup" else "Close"

        val playPauseAction = if (isPlaying) {
            Notification.Action.Builder(
                android.R.drawable.ic_media_pause,
                pauseLabel,
                broadcastIntent(ACTION_PAUSE, 11)
            ).build()
        } else {
            Notification.Action.Builder(
                android.R.drawable.ic_media_play,
                playLabel,
                broadcastIntent(ACTION_PLAY, 12)
            ).build()
        }

        builder
            .setSmallIcon(R.drawable.ic_stat_musevee)
            .setContentTitle(title.ifBlank { "MusEvee" })
            .setContentText(artist)
            .setSubText(album.ifBlank { null })
            .setContentIntent(contentIntent())
            .setDeleteIntent(broadcastIntent(ACTION_STOP, 15))
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setOngoing(isPlaying)
            .setColor(0xFF0E1014.toInt())
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_media_previous,
                    prevLabel,
                    broadcastIntent(ACTION_PREVIOUS, 13)
                ).build()
            )
            .addAction(playPauseAction)
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_media_next,
                    nextLabel,
                    broadcastIntent(ACTION_NEXT, 14)
                ).build()
            )
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    closeLabel,
                    broadcastIntent(ACTION_STOP, 15)
                ).build()
            )
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )
        artwork?.let { builder.setLargeIcon(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    private fun postNotification() {
        val notification = try {
            buildNotification()
        } catch (_: Exception) {
            return
        }
        MusEveePlaybackService.latestNotification = notification
        if (isPlaying) {
            if (!MusEveePlaybackService.isForeground) {
                // Promote to foreground service so playback & Live Island survive background / screen-off
                try {
                    val intent = Intent(appContext, MusEveePlaybackService::class.java)
                        .setAction(MusEveePlaybackService.ACTION_FOREGROUND)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        appContext.startForegroundService(intent)
                    } else {
                        appContext.startService(intent)
                    }
                    return
                } catch (_: Exception) {
                    // Background FGS start restricted -> fall back to notify() below
                }
            }
        } else if (MusEveePlaybackService.isForeground) {
            try {
                appContext.startService(
                    Intent(appContext, MusEveePlaybackService::class.java)
                        .setAction(MusEveePlaybackService.ACTION_DETACH)
                )
            } catch (_: Exception) {
            }
        }
        try {
            notificationManager.notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS denied on Android 13+
        } catch (_: Exception) {
        }
    }

    /** Removes the notification & deactivates the session (Close / app destroy). */
    fun clear() {
        hasTrack = false
        isPlaying = false
        try {
            session.setPlaybackState(
                PlaybackState.Builder()
                    .setState(PlaybackState.STATE_STOPPED, 0L, 0f)
                    .build()
            )
            session.isActive = false
        } catch (_: Exception) {
        }
        if (MusEveePlaybackService.isForeground || MusEveePlaybackService.isRunning) {
            try {
                appContext.startService(
                    Intent(appContext, MusEveePlaybackService::class.java)
                        .setAction(MusEveePlaybackService.ACTION_STOP)
                )
            } catch (_: Exception) {
            }
        }
        MusEveePlaybackService.latestNotification = null
        try {
            notificationManager.cancel(NOTIFICATION_ID)
        } catch (_: Exception) {
        }
    }

    fun release() {
        clear()
        if (receiverRegistered) {
            try {
                appContext.unregisterReceiver(actionReceiver)
            } catch (_: Exception) {
            }
            receiverRegistered = false
        }
        try {
            session.release()
        } catch (_: Exception) {
        }
    }

    private fun decodeArtwork(path: String?): Bitmap? {
        if (path.isNullOrBlank()) return null
        return try {
            val file = File(path)
            if (!file.exists()) return null
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            val maxSide = maxOf(bounds.outWidth, bounds.outHeight)
            while (maxSide / (sample * 2) >= 512) sample *= 2
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
        } catch (_: Exception) {
            null
        }
    }
}

/**
 * Lightweight `mediaPlayback` foreground service that only hosts the MusEvee
 * media notification so Android keeps the process alive while music plays in
 * the background / with the screen off.
 */
class MusEveePlaybackService : Service() {
    companion object {
        const val ACTION_FOREGROUND = "com.example.spotmeta_downloader.service.FOREGROUND"
        const val ACTION_DETACH = "com.example.spotmeta_downloader.service.DETACH"
        const val ACTION_STOP = "com.example.spotmeta_downloader.service.STOP"

        @Volatile
        var latestNotification: Notification? = null

        @Volatile
        var isForeground: Boolean = false

        @Volatile
        var isRunning: Boolean = false
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        isRunning = true
        when (intent?.action) {
            ACTION_FOREGROUND -> {
                val notification = latestNotification
                if (notification == null) {
                    if (!isForeground) stopSelf()
                    return START_NOT_STICKY
                }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        startForeground(
                            MusEveeMediaNotifier.NOTIFICATION_ID,
                            notification,
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                        )
                    } else {
                        startForeground(MusEveeMediaNotifier.NOTIFICATION_ID, notification)
                    }
                    isForeground = true
                } catch (_: Exception) {
                    isForeground = false
                    stopSelf()
                }
            }
            ACTION_DETACH -> {
                detachForeground(removeNotification = false)
            }
            ACTION_STOP -> {
                detachForeground(removeNotification = true)
                stopSelf()
            }
            else -> {
                if (!isForeground) stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun detachForeground(removeNotification: Boolean) {
        if (!isForeground) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(
                    if (removeNotification) STOP_FOREGROUND_REMOVE else STOP_FOREGROUND_DETACH
                )
            } else {
                @Suppress("DEPRECATION")
                stopForeground(removeNotification)
            }
        } catch (_: Exception) {
        }
        isForeground = false
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        detachForeground(removeNotification = true)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        isForeground = false
        isRunning = false
        super.onDestroy()
    }
}


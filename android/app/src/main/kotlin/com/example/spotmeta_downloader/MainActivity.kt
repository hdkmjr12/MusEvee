package com.example.spotmeta_downloader

import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.MediaScannerConnection
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.spotmeta.downloader/system"
    private var methodChannel: MethodChannel? = null
    private var pendingSharedText: String? = null
    private var mediaPlayer: MediaPlayer? = null
    private var currentPreviewUrl: String? = null

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
                        playPreviewAudio(url, result)
                    }
                }
                "stopPreview" -> {
                    stopPreviewAudio(notifyFlutter = true)
                    result.success(true)
                }
                "isPreviewPlaying" -> {
                    val playing = try {
                        mediaPlayer?.isPlaying == true
                    } catch (_: Exception) {
                        false
                    }
                    result.success(playing)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun playPreviewAudio(url: String, result: MethodChannel.Result) {
        try {
            stopPreviewAudio(notifyFlutter = false)
            currentPreviewUrl = url

            val player = MediaPlayer()
            mediaPlayer = player

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
        } catch (e: Exception) {
            stopPreviewAudio(notifyFlutter = true)
            result.success(false)
        }
    }

    private fun stopPreviewAudio(notifyFlutter: Boolean) {
        val player = mediaPlayer
        mediaPlayer = null
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

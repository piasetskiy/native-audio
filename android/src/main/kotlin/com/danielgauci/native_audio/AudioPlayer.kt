package com.danielgauci.native_audio

import android.media.MediaPlayer
import android.os.Handler
import java.util.concurrent.TimeUnit

class AudioPlayer(
        private val onLoad: ((duration: Long) -> Unit)? = null,
        private val onProgressChange: ((currentTime: Long) -> Unit)? = null,
        private val onComplete: (() -> Unit)? = null,
        private val onError: ((error: Exception) -> Unit)? = null
) {

    private var mediaPlayer: MediaPlayer? = null
    private var progressCallbackHandler: Handler? = null
    private var progressCallback: Runnable? = null
    private var currentProgress = 0L
    private var isLoaded = false

    fun play(url: String) {
        if (mediaPlayer == null) initMediaPlayer()

        if (mediaPlayer?.isPlaying == true) stop()

        loadAudio(url)
        startListeningForProgress()
    }

    fun resume() {
        try {
            mediaPlayer?.apply { if (isLoaded && !isPlaying) start() }
        } catch (e: Exception) {
            onError?.invoke(e)
        }

        startListeningForProgress()
    }

    fun pause() {
        try {
            mediaPlayer?.apply { if (isPlaying) pause() }
        } catch (e: Exception) {
            onError?.invoke(e)
        }

        stopListeningForProgress()
    }

    fun stop() {
        try {
            mediaPlayer?.let {
                if (!it.isPlaying) return
                it.stop()
                it.reset()
            }
        } catch (e: Exception) {
            onError?.invoke(e)
        }
    }

    /**
     * @param time the offset time in milliseconds from the start to seek to
     */
    fun seekTo(time: Long) {
        try {
            mediaPlayer?.apply { if (isLoaded) seekTo(time.toInt()) }
        } catch (e: Exception) {
            onError?.invoke(e)
        }
    }

    fun release() {
        stop()
        stopListeningForProgress()

        mediaPlayer?.release()
        mediaPlayer = null
    }

    private fun loadAudio(url: String) {
        try {
            mediaPlayer?.apply {
                reset()
                setDataSource(url)
                prepareAsync()
            }
        } catch (e: Exception) {
            onError?.invoke(e)
        }
    }

    private fun initMediaPlayer() {
        mediaPlayer = MediaPlayer().apply {
            setOnPreparedListener {
                // Start audio once loaded
                start()

                // Update flags
                isLoaded = true

                // Notify callback
                onLoad?.invoke(duration.toLong())
            }

            setOnCompletionListener {
                // Update flags
                isLoaded = false

                // Notify callback
                onComplete?.invoke()

                // Release
                this@AudioPlayer.release()
            }

            setOnErrorListener { _, what, extra ->
                onError?.invoke(Exception("Failed to load audio with error code: $what, extra code: $extra"))
                // Return false to trigger on complete
                false
            }
        }
    }

    private fun startListeningForProgress() {
        // Try to clear any existing listeners
        stopListeningForProgress()

        // Setup progress callback
        initProgressCallback()
        progressCallbackHandler?.postDelayed(progressCallback, TimeUnit.SECONDS.toMillis(1))
    }

    private fun stopListeningForProgress() {
        progressCallbackHandler?.removeCallbacks(progressCallback)
        progressCallbackHandler = null
        progressCallback = null
    }

    private fun initProgressCallback() {
        progressCallbackHandler = Handler()
        progressCallback = Runnable {
            mediaPlayer?.let {
                val progress = it.currentPosition.toLong()
                if (progress != currentProgress) {
                    onProgressChange?.invoke(progress)
                    currentProgress = progress
                }

                progressCallbackHandler?.postDelayed(progressCallback, TimeUnit.SECONDS.toMillis(1))
            }
        }
    }
}
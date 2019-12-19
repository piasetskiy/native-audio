package com.danielgauci.native_audio

import android.annotation.SuppressLint
import android.annotation.TargetApi
import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.media.AudioManager
import android.media.AudioManager.*
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.MediaMetadataCompat.METADATA_KEY_DURATION
import android.support.v4.media.MediaMetadataCompat.METADATA_KEY_TITLE
import android.support.v4.media.MediaMetadataCompat.METADATA_KEY_ARTIST
import android.support.v4.media.MediaMetadataCompat.METADATA_KEY_ALBUM_ART
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.annotation.ColorInt
import androidx.core.app.NotificationCompat
import androidx.media.AudioFocusRequestCompat
import androidx.media.AudioManagerCompat
import androidx.media.session.MediaButtonReceiver
import androidx.palette.graphics.Palette
import com.bumptech.glide.Glide
import com.bumptech.glide.request.target.SimpleTarget
import com.bumptech.glide.request.transition.Transition
import java.lang.Exception
import java.util.concurrent.TimeUnit

class AudioService : Service() {

    companion object {
        private const val MEDIA_SESSION_TAG = "com.danielgauci.native_audio"

        private const val NOTIFICATION_ID = 10

        private const val NOTIFICATION_CHANNEL_ID = "media_playback_channel"
        private const val NOTIFICATION_CHANNEL_NAME = "Media Playback"
        private const val NOTIFICATION_CHANNEL_DESCRIPTION = "Media Playback Controls"
    }

    // TODO: Confirm that this does not leak the activity
    var onLoad: ((Long) -> Unit)? = null
    var onProgressChange: ((Long) -> Unit)? = null
    var onResume: (() -> Unit)? = null
    var onPause: (() -> Unit)? = null
    var onStop: (() -> Unit)? = null
    var onComplete: (() -> Unit)? = null
    var onError: ((Exception) -> Unit)? = null

    private var playbackState = PlaybackStateCompat.STATE_STOPPED
    private var oldPlaybackState: Int = Int.MIN_VALUE

    private val isPlaying get() = playbackState == PlaybackStateCompat.STATE_PLAYING
    /**
     * Gets the current playback position.
     *
     * @return the current audio position in milliseconds
     */
    private var audioProgress = 0L
    /**
     * Gets the duration of the audio file.
     *
     * @return the duration in milliseconds, if no duration is available
     *         (for example, if streaming live content), -1 is returned.
     */
    private var audioDuration = 0L
    private var resumeOnAudioFocus = false
    private var isNotificationShown = false
    private var notificationBuilder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
    private var metadata = MediaMetadataCompat.Builder()

    private val binder by lazy { AudioServiceBinder() }
    private val session by lazy {
        MediaSessionCompat(this, MEDIA_SESSION_TAG).apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    super.onPlay()
                    resume()
                }

                override fun onPause() {
                    super.onPause()
                    pause()
                }

                override fun onStop() {
                    super.onStop()
                    stop()
                }

                override fun onSeekTo(pos: Long) {
                    super.onSeekTo(pos)
                    seekTo(pos)
                }

                override fun onSkipToNext() {
                    super.onSkipToNext()
                    seekForward()
                }

                override fun onSkipToPrevious() {
                    super.onSkipToPrevious()
                    seekBackward()
                }

                override fun onFastForward() {
                    super.onFastForward()
                    seekForward()
                }

                override fun onRewind() {
                    super.onRewind()
                    seekBackward()
                }
            })
        }
    }

    private val notificationManager by lazy {
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }

    private val audioPlayer by lazy {
        AudioPlayer(
                onLoad = {
                    audioDuration = it
                    onLoad?.invoke(it)

                    metadata.putLong(METADATA_KEY_DURATION, audioDuration)
                    session.setMetadata(metadata.build())
                },
                onProgressChange = {
                    audioProgress = it
                    onProgressChange?.invoke(it)
                    updatePlaybackState()
                },
                onComplete = { onComplete?.invoke() }
        )
    }

    private val playbackStateBuilder by lazy {
        PlaybackStateCompat.Builder().setActions(
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackStateCompat.ACTION_FAST_FORWARD or
                        PlaybackStateCompat.ACTION_REWIND or
                        PlaybackStateCompat.ACTION_STOP or
                        PlaybackStateCompat.ACTION_SEEK_TO
        )
    }

    private val audioFocusRequest by lazy {
        AudioFocusRequestCompat.Builder(AudioManagerCompat.AUDIOFOCUS_GAIN)
                .setOnAudioFocusChangeListener { audioFocus ->
                    when (audioFocus) {
                        AUDIOFOCUS_GAIN -> {
                            if (resumeOnAudioFocus && !isPlaying) {
                                resume()
                                resumeOnAudioFocus = false
                            } else if (isPlaying) {
                                // TODO: Set volume to full
                            }
                        }
                        AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                            // TODO: Set volume to duck
                        }
                        AUDIOFOCUS_LOSS_TRANSIENT -> {
                            if (isPlaying) {
                                resumeOnAudioFocus = true
                                pause()
                            }
                        }
                        AUDIOFOCUS_LOSS -> {
                            resumeOnAudioFocus = false
                            stop()
                        }
                    }
                }
                .build()
    }

    private val audioManager by lazy { getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    private val headsetManager by lazy { HeadsetManager() }
    private val bluetoothManager by lazy { BluetoothManager() }

    override fun onBind(intent: Intent?): IBinder? {
        return binder
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MediaButtonReceiver.handleIntent(session, intent)

        headsetManager.registerHeadsetPlugReceiver(
                this,
                onConnected = {},
                onDisconnected = { pause() })

        bluetoothManager.registerBluetoothReceiver(
                this,
                onConnected = {},
                onDisconnected = { pause() })

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        audioPlayer.release()
    }

    fun play(
            url: String,
            title: String? = null,
            artist: String? = null,
            album: String? = null,
            imageUrl: String? = null
    ) {
        requestFocus()

        audioPlayer.play(url)

        session.isActive = true
        playbackState = PlaybackStateCompat.STATE_PLAYING
        updatePlaybackState()

        showNotification(title = title, artist = artist, album = album, imageUrl = imageUrl)
    }

    fun resume() {
        requestFocus()

        audioPlayer.resume()

        playbackState = PlaybackStateCompat.STATE_PLAYING
        updatePlaybackState()

        onResume?.invoke()
    }

    fun pause() {
        audioPlayer.pause()

        playbackState = PlaybackStateCompat.STATE_PAUSED
        updatePlaybackState()

        onPause?.invoke()

        if (!resumeOnAudioFocus) abandonFocus()
    }

    fun stop() {
        audioPlayer.stop()

        playbackState = PlaybackStateCompat.STATE_STOPPED

        cancelNotification()
        session.isActive = false

        onStop?.invoke()

        abandonFocus()

        stopSelf()
    }

    fun seekTo(time: Long) {
        audioPlayer.seekTo(time)
    }

    private fun seekForward(to: Long = 30) {
        val forwardTime = TimeUnit.SECONDS.toMillis(to)
        if (audioDuration - audioProgress > forwardTime) {
            seekTo(audioProgress + forwardTime.toInt())
        }
    }

    private fun seekBackward(to: Long = 30) {
        val rewindTime = TimeUnit.SECONDS.toMillis(to)
        if (audioProgress - rewindTime > 0) {
            seekTo(audioProgress - rewindTime.toInt())
        }
    }

    private fun requestFocus() {
        AudioManagerCompat.requestAudioFocus(audioManager, audioFocusRequest)
    }

    private fun abandonFocus() {
        AudioManagerCompat.abandonAudioFocusRequest(audioManager, audioFocusRequest)
    }

    @TargetApi(26)
    private fun createNotificationChannel() {
        notificationManager.createNotificationChannel(NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                NOTIFICATION_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = NOTIFICATION_CHANNEL_DESCRIPTION
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(false)
        })
    }

    private fun updateNotificationBuilder(
            title: String?,
            artist: String?,
            album: String?,
            image: Bitmap? = null,
            @ColorInt notificationColor: Int? = null
    ) {

        title?.let { metadata.putString(METADATA_KEY_TITLE, it) }
        artist?.let { metadata.putString(METADATA_KEY_ARTIST, it) }
        image?.let { metadata.putBitmap(METADATA_KEY_ALBUM_ART, it) }

        session.setMetadata(metadata.build())

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) createNotificationChannel()
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT)
        val stopIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_STOP)

        val mediaStyle = androidx.media.app.NotificationCompat.MediaStyle()
                .setMediaSession(session.sessionToken)
                .setShowActionsInCompactView(0, 1, 2)
                .setCancelButtonIntent(stopIntent)
                .setShowCancelButton(true)

        notificationBuilder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setSmallIcon(R.drawable.play)
                .setContentIntent(contentIntent)
                .setDeleteIntent(stopIntent)
                .setContentTitle(title)
                .setOnlyAlertOnce(true)
                .setStyle(mediaStyle)
                .setOngoing(true)

        artist?.let { notificationBuilder.setSubText(it) }
        album?.let { notificationBuilder.setContentText(it) }

        notificationBuilder.apply {
            if (image != null) setLargeIcon(image)
            if (notificationColor != null) color = notificationColor

            // Add play/pause action
            setNotificationButtons(this)
        }
    }

    @SuppressLint("RestrictedApi")
    private fun setNotificationButtons(builder: NotificationCompat.Builder, isPlaying: Boolean = true) {
        builder.apply {
            mActions.clear()

            // Add play/pause action
            val playPauseAction = NotificationCompat.Action.Builder(
                    if (isPlaying) R.drawable.pause else R.drawable.play,
                    if (isPlaying) "Pause" else "Play",
                    MediaButtonReceiver.buildMediaButtonPendingIntent(this@AudioService, PlaybackStateCompat.ACTION_PLAY_PAUSE)
            ).build()
            addAction(playPauseAction)

            // Add rewind action
            val rewindAction = NotificationCompat.Action.Builder(
                    R.drawable.rewind_30,
                    "Rewind",
                    MediaButtonReceiver.buildMediaButtonPendingIntent(this@AudioService, PlaybackStateCompat.ACTION_REWIND)
            ).build()
            addAction(rewindAction)

            // Add fast forward action
            val forwardAction = NotificationCompat.Action.Builder(
                    R.drawable.fast_forward_30,
                    "Fast Forward",
                    MediaButtonReceiver.buildMediaButtonPendingIntent(this@AudioService, PlaybackStateCompat.ACTION_FAST_FORWARD)
            ).build()
            addAction(forwardAction)
        }
    }

    private fun showNotification(title: String?, artist: String?, album: String?, imageUrl: String? = null) {
        if (imageUrl.isNullOrBlank()) {
            // No image is set, show notification
            updateNotificationBuilder(title, artist, album)
            startForeground(NOTIFICATION_ID, notificationBuilder.build())
            isNotificationShown = true

            return
        }

            // Get image show notification
        Glide.with(this)
                    .asBitmap()
                    .load(imageUrl)
                    .into(object : SimpleTarget<Bitmap>() {
                        override fun onResourceReady(resource: Bitmap, transition: Transition<in Bitmap>?) {
                            Palette.from(resource).generate { palette ->
                                palette?.let {
                                    // Palette generated, show notification with bitmap and palette
                                    val color = it.getVibrantColor(Color.WHITE)
                                    updateNotificationBuilder(
                                            title = title,
                                            artist = artist,
                                            album = album,
                                            notificationColor = color,
                                            image = resource
                                    )

                                    startForeground(NOTIFICATION_ID, notificationBuilder.build())
                                    isNotificationShown = true
                                } ?: run {
                                    // Failed to generate palette, show notification with bitmap
                                    updateNotificationBuilder(
                                            title = title,
                                            artist = artist,
                                            album = album,
                                            image = resource
                                    )

                                    startForeground(NOTIFICATION_ID, notificationBuilder.build())
                                    isNotificationShown = true
                                }
                            }
                        }

                        override fun onLoadFailed(errorDrawable: Drawable?) {
                            super.onLoadFailed(errorDrawable)

                            // Failed to load image, show notification
                            updateNotificationBuilder(title, artist, album)
                            startForeground(NOTIFICATION_ID, notificationBuilder.build())
                            isNotificationShown = true
                        }
                    })

    }

    private fun cancelNotification() {
        stopForeground(true)
        notificationManager.cancel(NOTIFICATION_ID)
        isNotificationShown = false
    }

    private fun updatePlaybackState() {
        val playbackState = playbackStateBuilder
                .setState(playbackState, audioProgress, 0f)
                .build()

        // Update session
        session.setPlaybackState(playbackState)

        // Try to update notification
        if (isNotificationShown) {
            val stateChanged = this.playbackState != oldPlaybackState

            // Update buttons based on current state
            setNotificationButtons(notificationBuilder, isPlaying)

            // Allow notification to be dismissed if not playing
            notificationBuilder.setOngoing(isPlaying)

            if (isPlaying && stateChanged) {
                // Update notification and ensure that notification is in foreground as it could have been stopped before
                startForeground(NOTIFICATION_ID, notificationBuilder.build())
            } else if (isPlaying) {
                // Notification was already in foreground, update with the latest information
                notificationManager.notify(NOTIFICATION_ID, notificationBuilder.build())
            } else {
                // Allow notification to be dismissed if not playing by changing the service to a non-foreground service
                stopForeground(false)
                notificationManager.notify(NOTIFICATION_ID, notificationBuilder.build())
            }
        }

        // Update playback state
        oldPlaybackState = this.playbackState
    }

    inner class AudioServiceBinder : Binder() {

        fun getService() = this@AudioService
    }
}
package com.danielgauci.native_audio

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.PluginRegistry.Registrar
import io.flutter.view.FlutterNativeView

class AudioPlugin(private val context: Context, private val channel: MethodChannel) : MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.danielgauci.native_audio"

        private const val INVOKE_PLAY_METHOD_CALL = "play"
        private const val PLAY_METHOD_CALL_URL_ARG = "url"
        private const val PLAY_METHOD_CALL_TITLE_ARG = "title"
        private const val PLAY_METHOD_CALL_ALBUM_ARG = "album"
        private const val PLAY_METHOD_CALL_ARTIST_ARG = "artist"
        private const val PLAY_METHOD_CALL_IMAGE_ARG = "imageUrl"

        private const val INVOKE_STOP_METHOD_CALL = "stop"
        private const val INVOKE_PAUSE_METHOD_CALL = "pause"
        private const val INVOKE_RESUME_METHOD_CALL = "resume"
        private const val INVOKE_RELEASE_METHOD_CALL = "release"

        private const val INVOKE_SEEK_TO_METHOD_CALL = "seekTo"
        private const val SEEK_TO_METHOD_CALL_TIME_ARG = "timeInMillis"

        private const val METHOD_CALL_ON_LOAD = "onLoad"
        private const val METHOD_CALL_ON_STOP = "onStop"
        private const val METHOD_CALL_ON_PAUSE = "onPause"
        private const val METHOD_CALL_ON_RESUME = "onResume"
        private const val METHOD_CALL_ON_COMPLETE = "onComplete"
        private const val METHOD_CALL_ON_PROGRESS_CHANGE = "onProgressChange"
        private const val METHOD_CALL_ON_ERROR = "onError"

        private var pluginRegistrantCallback: PluginRegistry.PluginRegistrantCallback? = null

        @JvmStatic
        fun setPluginRegistrantCallback(callback: PluginRegistry.PluginRegistrantCallback) {
            pluginRegistrantCallback = callback
        }

        @JvmStatic
        fun registerWith(registrar: Registrar) {
            val channel = MethodChannel(registrar.messenger(), CHANNEL)
            channel.setMethodCallHandler(AudioPlugin(registrar.context(), channel))
        }
    }

    private var flutterView: FlutterNativeView? = null
    private var audioService: AudioService? = null
    private var serviceConnection: ServiceConnection? = null

    override fun onMethodCall(call: MethodCall, result: Result) {
        withService { service ->
            if (flutterView == null) {
                // Register all plugins for the application with our new FlutterNativeView's
                // plugin registry.
                // Other plugins will not work when running in the background if this isn't done
                flutterView = FlutterNativeView(service, false).apply {
                    pluginRegistrantCallback?.registerWith(pluginRegistry)
                            ?: throw IllegalStateException("No pluginRegistrantCallback has been set. Make sure you call NativeAudioPlugin.setPluginRegistrantCallback(this) in your application's onCreate.")
                }
            }

            when (call.method) {
                INVOKE_PLAY_METHOD_CALL -> {
                    withArgument(call, PLAY_METHOD_CALL_URL_ARG) { url: String ->
                        // Get optional arguments
                        val title = call.argument<String>(PLAY_METHOD_CALL_TITLE_ARG)
                        val artist = call.argument<String>(PLAY_METHOD_CALL_ARTIST_ARG)
                        val album = call.argument<String>(PLAY_METHOD_CALL_ALBUM_ARG)
                        val imageUrl = call.argument<String>(PLAY_METHOD_CALL_IMAGE_ARG)

                        // Call service
                        service.play(url, title, artist, album, imageUrl)
                    }
                }
                INVOKE_RESUME_METHOD_CALL -> service.resume()
                INVOKE_PAUSE_METHOD_CALL -> service.pause()
                INVOKE_STOP_METHOD_CALL -> service.stop()
                INVOKE_RELEASE_METHOD_CALL -> releaseAudioService()
                INVOKE_SEEK_TO_METHOD_CALL -> {
                    withArgument(call, SEEK_TO_METHOD_CALL_TIME_ARG) { time: Int ->
                        service.seekTo(time.toLong())
                    }
                }
            }
        }
    }

    private fun <T> withArgument(methodCall: MethodCall, argumentKey: String, withArgument: (T) -> Unit) {
        val argument = methodCall.argument<T>(argumentKey)
                ?: throw IllegalArgumentException(
                        "Argument $argumentKey is required when calling the ${methodCall.method} method."
                )

        withArgument(argument)
    }

    private fun withService(withService: (AudioService) -> Unit) {
        if (audioService == null) {
            // Audio service not available yet, bind and setup
            serviceConnection = object : ServiceConnection {
                override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                    val service = (binder as AudioService.AudioServiceBinder).getService()
                    bindAudioServiceWithChannel(service)
                    withService(service)

                    audioService = service
                }

                override fun onServiceDisconnected(name: ComponentName?) {
                    audioService = null
                }
            }

            val serviceIntent = Intent(context, AudioService::class.java)
            if (!context.isServiceRunning(AudioService::class.java)) context.startService(serviceIntent)
            serviceConnection?.let { context.bindService(serviceIntent, it, Context.BIND_AUTO_CREATE) }

            // Return and wait for service to be connected
            return
        }

        // Call lambda with service
        audioService?.let { withService(it) }
    }

    private fun bindAudioServiceWithChannel(service: AudioService) {
        service.apply {
            // Notify flutter with audio updates

            onLoad = { invokeMethod(METHOD_CALL_ON_LOAD, it) }

            onProgressChange = { invokeMethod(METHOD_CALL_ON_PROGRESS_CHANGE, it) }

            onResume = { invokeMethod(METHOD_CALL_ON_RESUME) }

            onPause = { invokeMethod(METHOD_CALL_ON_PAUSE) }

            onStop = { invokeMethod(METHOD_CALL_ON_STOP) }

            onComplete = { invokeMethod(METHOD_CALL_ON_COMPLETE) }

            onError = { handleError(it) }
        }
    }

    private fun invokeMethod(method: String, args: Any? = null) = try {
        channel.invokeMethod(method, args)
    } catch (e: Exception) {
        handleError(e)
    }

    private fun handleError(error: Exception) = try {
        channel.invokeMethod(METHOD_CALL_ON_ERROR, error.toString())
    } catch (e: Exception) {
        Log.e(this::class.java.simpleName, e.message, e)
    }

    private fun releaseAudioService() {
        serviceConnection?.let { context.unbindService(it) }
        context.stopService(Intent(context, AudioService::class.java))
    }
}
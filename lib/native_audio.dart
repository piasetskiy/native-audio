import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

abstract class NativeAudio {
  void play(
    String url, {
    @required String title,
    String artist,
    String album,
    String imageUrl,
  });
  void resume();
  void pause();
  void stop();
  void seekTo(Duration time);
  void release();
}

class NativeAudioImpl implements NativeAudio {
  static const _invokePlayMethodCall = "play";
  static const _playMethodCallUrlArg = "url";
  static const _playMethodCallTitleArg = "title";
  static const _playMethodCallArtistArg = "artist";
  static const _playMethodCallAlbumArg = "album";
  static const _playMethodCallImageArg = "imageUrl";

  static const _invokeResumeMethodCall = "resume";
  static const _invokePauseMethodCall = "pause";
  static const _invokeStopMethodCall = "stop";

  static const _invokeSeekToMethodCall = "seekTo";
  static const _seekToMethodCallTimeArg = "timeInMillis";

  static const _nativeMethodRelease = "release";
  static const _methodCallOnLoaded = "onLoaded";
  static const _methodCallOnResumed = "onResumed";
  static const _methodCallOnPaused = "onPaused";
  static const _methodCallOnStopped = "onStopped";
  static const _methodCallOnProgressChanged = "onProgressChanged";
  static const _methodCallOnCompleted = "onCompleted";

  factory NativeAudioImpl() {
    return _instance ??= NativeAudioImpl.private(
      MethodChannel('com.danielgauci.native_audio'),
    );
  }

  @visibleForTesting
  NativeAudioImpl.private(this._channel);

  static NativeAudio _instance;

  final MethodChannel _channel;

  VoidCallback onResumed;
  VoidCallback onPaused;
  VoidCallback onStopped;
  VoidCallback onCompleted;
  void Function(Duration) onLoaded;
  void Function(Duration) onProgressChanged;
  void Function(Exception, StackTrace) onError;

  @override
  void play(
    String url, {
    @required String title,
    String artist,
    String album,
    String imageUrl,
  }) {
    _registerMethodCallHandler();
    _invokeMethod(
      _invokePlayMethodCall,
      arguments: <String, dynamic>{
        _playMethodCallUrlArg: url,
        _playMethodCallAlbumArg: album,
        _playMethodCallTitleArg: title,
        _playMethodCallArtistArg: artist,
        _playMethodCallImageArg: imageUrl,
      },
    );
  }

  @override
  void resume() {
    _invokeMethod(_invokeResumeMethodCall);
  }

  @override
  void pause() {
    _invokeMethod(_invokePauseMethodCall);
  }

  @override
  void stop() {
    _invokeMethod(_invokeStopMethodCall);
  }

  @override
  void seekTo(Duration time) {
    _invokeMethod(
      _invokeSeekToMethodCall,
      arguments: <String, dynamic>{
        _seekToMethodCallTimeArg: time.inMilliseconds
      },
    );
  }

  @override
  void release() {
    _invokeMethod(_nativeMethodRelease);
  }

  void _registerMethodCallHandler() {
    // Listen to method calls from native
    _channel.setMethodCallHandler((methodCall) {
      switch (methodCall.method) {
        case _methodCallOnLoaded:
          int durationInMillis = methodCall.arguments;
          if (onLoaded != null)
            onLoaded(Duration(milliseconds: durationInMillis));
          break;

        case _methodCallOnResumed:
          if (onResumed != null) onResumed();
          break;

        case _methodCallOnPaused:
          if (onPaused != null) onPaused();
          break;

        case _methodCallOnStopped:
          if (onStopped != null) onStopped();
          break;

        case _methodCallOnCompleted:
          if (onCompleted != null) onCompleted();
          break;

        case _methodCallOnProgressChanged:

          /// Current progress in milliseconds
          final int progress = methodCall.arguments;
          if (onProgressChanged != null && progress != null)
            onProgressChanged(Duration(milliseconds: progress));
          break;
      }

      return;
    });
  }

  Future<void> _invokeMethod<T>(
    String method, {
    Map<String, dynamic> arguments,
  }) async {
    try {
      await _channel.invokeMethod(method, arguments);
    } catch (e, stack) {
      onError(e, stack);
    }
  }
}

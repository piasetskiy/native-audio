import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:quiver/strings.dart';

abstract class NativeAudio {
  VoidCallback didResume;
  VoidCallback didPause;
  VoidCallback didStop;
  VoidCallback didComplete;
  void Function(Duration) didLoad;
  void Function(Exception) onError;
  void Function(Duration) didChangeProgress;

  factory NativeAudio.build() => _NativeAudioImpl();

  void play(
    String url, {
    String title,
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

class _NativeAudioImpl implements NativeAudio {
  static const _invokePlayMethodCall = "play";
  static const _playMethodCallUrlArg = "url";
  static const _playMethodCallTitleArg = "title";
  static const _playMethodCallArtistArg = "artist";
  static const _playMethodCallAlbumArg = "album";
  static const _playMethodCallImageArg = "imageUrl";

  static const _invokeReleaseMethodCall = "release";
  static const _invokeResumeMethodCall = "resume";
  static const _invokePauseMethodCall = "pause";

  static const _invokeStopMethodCall = "stop";
  static const _invokeSeekToMethodCall = "seekTo";

  static const _seekToMethodCallTimeArg = "timeInMillis";
  static const _methodCallOnError = "onError";
  static const _methodCallOnStop = "onStop";
  static const _methodCallOnLoad = "onLoad";
  static const _methodCallOnPause = "onPause";
  static const _methodCallOnResume = "onResume";
  static const _methodCallOnComplete = "onComplete";
  static const _methodCallOnProgressChange = "onProgressChange";

  factory _NativeAudioImpl() {
    return _instance ??= _NativeAudioImpl.private(
      MethodChannel('com.danielgauci.native_audio'),
    );
  }

  @visibleForTesting
  _NativeAudioImpl.private(this._channel);

  static NativeAudio _instance;

  final MethodChannel _channel;

  VoidCallback didResume;
  VoidCallback didPause;
  VoidCallback didStop;
  VoidCallback didComplete;
  void Function(Duration) didLoad;
  void Function(Exception) onError;
  void Function(Duration) didChangeProgress;

  @override
  void play(
    String url, {
    String title,
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
    if (Platform.isAndroid) _invokeMethod(_invokeReleaseMethodCall);
  }

  void _registerMethodCallHandler() {
    // Listen to method calls from native
    _channel.setMethodCallHandler((methodCall) {
      switch (methodCall.method) {
        case _methodCallOnLoad:
          final int duration = methodCall.arguments ?? 0;
          if (didLoad != null) didLoad(Duration(milliseconds: duration));
          break;

        case _methodCallOnResume:
          if (didResume != null) didResume();
          break;

        case _methodCallOnPause:
          if (didPause != null) didPause();
          break;

        case _methodCallOnStop:
          if (didStop != null) didStop();
          break;

        case _methodCallOnComplete:
          if (didComplete != null) didComplete();
          break;

        case _methodCallOnProgressChange:

          /// Current progress in milliseconds
          final int progress = methodCall.arguments;
          if (didChangeProgress != null && progress != null)
            didChangeProgress(Duration(milliseconds: progress));
          break;

        case _methodCallOnError:
          final String error = methodCall.arguments;
          if (onError != null && !isBlank(error)) onError(Exception(error));
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
    } catch (e) {
      if (onError != null) onError(e);
    }
  }
}

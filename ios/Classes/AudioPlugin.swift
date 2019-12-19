import Flutter
import UIKit
import AVFoundation
import MediaPlayer

public class AudioPlugin: NSObject, FlutterPlugin {
    
    enum SupportedInvokeMethodCall: String {
        case onLoad = "onLoaded"
        case onPause = "onPause"
        case onResume = "onResume"
        case onStop = "onStop"
        case onComplete = "onComplete"
        case onProgressChange = "onProgressChange"
    }
    
    private enum SupportedMethodCall: String {
        case play = "play"
        case resume = "resume"
        case pause = "pause"
        case stop = "stop"
        case seekTo = "seekTo"
        
        init?(method: String?) {
            switch method {
            case SupportedMethodCall.play.rawValue:
                self = .play
            case SupportedMethodCall.resume.rawValue:
                self = .resume
            case SupportedMethodCall.pause.rawValue:
                self = .pause
            case SupportedMethodCall.stop.rawValue:
                self = .stop
            case SupportedMethodCall.seekTo.rawValue:
                self = .seekTo
            default:
                return nil
            }
        }
    }
    
    private static let channelName = "com.danielgauci.native_audio"
    
    private var methodChannel: FlutterMethodChannel!
    private var player: AudioPlayer!
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel: FlutterMethodChannel = .init(name: channelName, binaryMessenger: registrar.messenger())
        let instance: AudioPlugin = .init(withChannel: channel)
        
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public init(withChannel channel: FlutterMethodChannel) {
        super.init()
        methodChannel = channel
        if #available(iOS 10.0, *) {
            player = instance()
            player.delegate = self
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let player = player, let method = SupportedMethodCall(method: call.method) else {
            result(FlutterMethodNotImplemented)
            return
        }
        
        switch (method) {
        case .play:
            guard let arguments = call.arguments as? NSDictionary,
                let url =  arguments["url"] as? String else {
                    return result(FlutterError.init(
                        code: "IllegalArgumentException",
                        message: "Argument url is required when calling the play method",
                        details: nil
                    ))
            }
            player.play(
                url: url,
                title: arguments["title"] as? String,
                artist: arguments["artist"] as? String,
                album: arguments["album"] as? String,
                imageUrl: arguments["imageUrl"] as? String
            )
            
        case .resume:
            player.resume()
            
        case .pause:
            player.pause()
            
        case .stop:
            player.stop()
            
        case .seekTo:
            guard let arguments = call.arguments as? NSDictionary,
                let time = arguments["timeInMillis"] as? Int else {
                    return result(FlutterError.init(
                        code: "IllegalArgumentException",
                        message: "Argument timeInMillis is required when calling the seekTo method",
                        details: nil
                    ))
            }
            player.seekTo(time: time)
        }
    }
    
    @available(iOS 10.0, *)
    private func instance() -> AudioPlayer {
        return AudioPlayerImpl()
    }
}

// MARK: AudioPlayerDelegate

extension AudioPlugin: AudioPlayerDelegate {
    
    func audioPlayerDidChangeProgress(_ progress: Int) {
        methodChannel.invokeMethod(method: .onProgressChange, arguments: progress)
    }
    
    func audioPlayerDidLoad(duration: Int) {
        methodChannel.invokeMethod(method: .onLoad, arguments: duration)
    }
    
    func audioPlayerDidStop() {
        methodChannel.invokeMethod(method: .onStop)
    }
    
    func audioPlayerDidPause() {
        methodChannel.invokeMethod(method: .onPause)
    }
    
    func audioPlayerDidResume() {
        methodChannel.invokeMethod(method: .onResume)
    }
    
    func audioPlayerDidComplete() {
        methodChannel.invokeMethod(method: .onComplete)
    }
}

fileprivate extension FlutterMethodChannel {
    func invokeMethod(method: AudioPlugin.SupportedInvokeMethodCall, arguments: Any? = nil) {
        invokeMethod(method.rawValue, arguments: arguments)
    }
}

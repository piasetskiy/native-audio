import Flutter
import UIKit
import AVFoundation
import MediaPlayer

public class AudioPlugin: NSObject, FlutterPlugin {
    
    enum SupportedInvokeCall: String {
        case onLoad = "onLoaded"
        case onPause = "onPause"
        case onResume = "onResume"
        case onStop = "onStop"
        case onComplete = "onComplete"
        case onProgressChange = "onProgressChange"
    }
    
    private enum SupportedCall: String {
        case play = "play"
        case resume = "resume"
        case pause = "pause"
        case stop = "stop"
        case seekTo = "seekTo"
        
        init?(method: String?) {
            switch method {
            case SupportedCall.play.rawValue:
                self = .play
            case SupportedCall.resume.rawValue:
                self = .resume
            case SupportedCall.pause.rawValue:
                self = .pause
            case SupportedCall.stop.rawValue:
                self = .stop
            case SupportedCall.seekTo.rawValue:
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
        guard let player = player, let method = SupportedCall(method: call.method) else {
            result(FlutterMethodNotImplemented)
            return
        }
        
        switch (method) {
        case .play:
            guard let arguments = call.arguments as? NSDictionary,
                let url =  arguments["url"] as? String,
                let title = arguments["title"] as? String else {
                    return
            }
            player.play(
                url: url,
                title: title,
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
                    return
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
    func invokeMethod(method: AudioPlugin.SupportedInvokeCall, arguments: Any? = nil) {
        invokeMethod(method.rawValue, arguments: arguments)
    }
}

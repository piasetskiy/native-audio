import Flutter
import UIKit
import AVFoundation
import MediaPlayer
import os

public class AudioPlugin: NSObject, FlutterPlugin {
    
    enum SupportedInvokeCall: String {
        case onLoadedCall = "onLoaded"
        case onPausedCall = "onPaused"
        case onResumedCall = "onResumed"
        case onStoppedCall = "onStopped"
        case onCompletedCall = "onCompleted"
        case onProgressChangedCall = "onProgressChanged"
    }
    
    private enum SupportedCall: String {
        case playCall = "play"
        case resumeCall = "resume"
        case pauseCall = "pause"
        case stopCall = "stop"
        case seekToCall = "seekTo"
        
        init?(method: String) {
            switch method {
            case SupportedCall.playCall.rawValue:
                self = .playCall
            case SupportedCall.resumeCall.rawValue:
                self = .resumeCall
                
            case SupportedCall.pauseCall.rawValue:
                self = .pauseCall
                
            case SupportedCall.stopCall.rawValue:
                self = .stopCall
                
            case SupportedCall.seekToCall.rawValue:
                self = .seekToCall
                
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
        let instance = AudioPlugin(withChannel: channel)
        
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public init(withChannel channel: FlutterMethodChannel) {
        super.init()
        methodChannel = channel
        if #available(iOS 10.0, *) {
            player = instance()
            player.delegate = self
        } else {
            // Fallback on earlier versions
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let player = player, let method = SupportedCall(method: call.method) else {
            result(FlutterMethodNotImplemented)
            return
        }
        
        switch (method) {
        case .playCall:
            guard let arguments = call.arguments as? NSDictionary,
                let url =  arguments["url"] as? String,
                let title = arguments["title"] as? String else {
                    return
            }
            
            let artist =  arguments["artist"] as? String
            let album =  arguments["album"] as? String
            let imageUrl =  arguments["imageUrl"] as? String
            
            player.play(url: url, title: title, artist: artist, album: album, imageUrl: imageUrl)
            
        case .resumeCall:
            player.resume()
            
        case .pauseCall:
            player.pause()
            
        case .stopCall:
            player.stop()
            
        case .seekToCall:
            let arguments = call.arguments as! NSDictionary
            let timeInMillis =  arguments["timeInMillis"] as! Int
            player.seekTo(time: timeInMillis)
        }
    }
    
    @available(iOS 10.0, *)
    private func instance() -> AudioPlayer {
        return AudioPlayerImpl()
    }
}

extension AudioPlugin: AudioPlayerDelegate {
    
    func audioPlayerDidChangeProgress(_ progress: Int) {
        methodChannel.invokeMethod(method: .onProgressChangedCall, arguments: progress)
    }
    
    func audioPlayerDidLoad(duration: Int) {
        methodChannel.invokeMethod(method: .onLoadedCall, arguments: duration)
    }
    
    func audioPlayerDidStoped() {
     methodChannel.invokeMethod(method: .onStoppedCall)
    }
    
    func audioPlayerDidPaused() {
       methodChannel.invokeMethod(method: .onPausedCall)
    }
    
    func audioPlayerDidResumed() {
       methodChannel.invokeMethod(method: .onResumedCall)
    }
    
    func audioPlayerDidComplete() {
        methodChannel.invokeMethod(method: .onCompletedCall)
    }
}

extension FlutterMethodChannel {
    func invokeMethod(method: AudioPlugin.SupportedInvokeCall, arguments: Any? = nil) {
        invokeMethod(method.rawValue, arguments: arguments)
    }
}

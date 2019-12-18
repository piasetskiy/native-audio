import Flutter
import UIKit
import AVFoundation
import MediaPlayer
import os

public class SwiftNativeAudioPlugin: NSObject, FlutterPlugin {
    private static let channelName = "com.danielgauci.native_audio"
    
    private enum SupportedCall: String {
        case playCall = "play"
        case resumeCall = "resume"
        case pauseCall = "pause"
        case stopCall = "stop"
        case seekToCall = "seekTo"
    }
    
    private enum SupportedInvokeCall: String {
        case onLoadedCall = "onLoaded"
        case durationCall = "duration"
        case onResumedCall = "onResumed"
        case onStoppedCall = "onStopped"
        case onCompletedCall = "onCompleted"
        case onProgressChangedCall = "onProgressChanged" // `currentTime` arg
    }
    
    private var methodChannel: FlutterMethodChannel!
    private var player: AudioPlayer!
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel: FlutterMethodChannel = .init(name: channelName, binaryMessenger: registrar.messenger())
        let instance = SwiftNativeAudioPlugin(withChannel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public init(withChannel channel: FlutterMethodChannel) {
        super.init()
        methodChannel = channel
        player = instance()
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result("iOS " + UIDevice.current.systemVersion)
        switch(call.method) {
        case "play":
            guard let arguments = call.arguments as? NSDictionary,
                let url =  arguments["url"] as? String,
                let title = arguments["title"] as? String else {
                    return
            }
            
            let artist =  arguments["artist"] as? String
            let album =  arguments["album"] as? String
            let imageUrl =  arguments["imageUrl"] as? String
            
            player.play(url: url, title: title, artist: artist, album: album, imageUrl: imageUrl)
            
        case "resume":
            player.resume()
            
        case "pause":
            player.pause()
            
        case "stop":
            player.stop()
            
        case "seekTo":
            let arguments = call.arguments as! NSDictionary
            let timeInMillis =  arguments["timeInMillis"] as! Int
            player.seekTo(time: timeInMillis)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func instance() -> AudioPlayer {
        return AudioPlayerImpl()
    }
}


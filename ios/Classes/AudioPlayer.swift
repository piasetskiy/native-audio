//
//  AudioPlayer.swift
//  native_audio
//
//  Created by David Piasetskiy on 18.12.2019.
//

import Flutter
import UIKit
import AVFoundation
import MediaPlayer

protocol AudioPlayerDelegate: class {

    // Progress in secconds
    func audioPlayerDidChangeProgress(_ progress: Int)
    func audioPlayerDidLoad(duration: Int)
    func audioPlayerDidStoped()
    func audioPlayerDidPaused()
    func audioPlayerDidResumed()
    func audioPlayerDidComplete()
}

protocol AudioPlayer {
    var delegate: AudioPlayerDelegate? { get set }
    
    func play(url: String, title: String, artist: String?, album: String?, imageUrl: String?)
    func seekTo(time: Int)
    func resume()
    func pause()
    func stop()
}

@available(iOS 10.0, *)
class AudioPlayerImpl: NSObject, AudioPlayer {
    
    weak var delegate: AudioPlayerDelegate?
    
    private var methodChannel: FlutterMethodChannel!
    
    private var player: AVPlayer!
    private var playerItem: AVPlayerItem!
    private var playerItemContext = 0
    private var currentProgressInMillis = -1
    private var totalDurationInMillis = -1
    private var skipForwardTimeInMillis = 15_000
    private var skipBackwardTimeInMillis = 15_000
    
    private var playingInfoCenter: MPNowPlayingInfoCenter {
        return MPNowPlayingInfoCenter.default()
    }
    
    private var notificationCenter: NotificationCenter {
        return NotificationCenter.default
    }
    
    private var audioSession: AVAudioSession {
        return AVAudioSession.sharedInstance()
    }
    
    override init() {
        super.init()
        setupRemoteTransportControls()
    }
    
    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        // Only handle observations for the playerItemContext
        guard context == &playerItemContext else {
            super.observeValue(
                forKeyPath: keyPath,
                of: object,
                change: change,
                context: context
            )
            return
        }
        
        guard keyPath == #keyPath(AVPlayerItem.status) else {
            return
        }
        
        let status: AVPlayerItem.Status
        if let statusNumber = change?[.newKey] as? NSNumber,
            let newStatus = AVPlayerItem.Status(rawValue: statusNumber.intValue) {
            status = newStatus
        } else {
            status = .unknown
        }
        
        switch status {
        case .readyToPlay:
            // Update listener
            guard playerItem.duration.isNumeric else { return }
            
            let durationInSeconds = CMTimeGetSeconds(playerItem.duration)
            totalDurationInMillis = Int(1000 * durationInSeconds)
            delegate?.audioPlayerDidLoad(duration: totalDurationInMillis)
            
            // Update control center
            playingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = CMTimeGetSeconds(playerItem.duration)
            
        case .failed:
            debugPrint("Failed AVPlayerItem state.")
        case .unknown:
            debugPrint("Unknown AVPlayerItem state.")
        }
    }
    
    func play(url: String, title: String, artist: String?, album: String?, imageUrl: String?) {
        // Setup player item
        guard let audioUrl = URL(string: url) else { return }
        playerItem = .init(url: audioUrl)
        
        // Update control center
        updateNowPlayingInfoCenter(title: title, artist: artist, album: album, imageUrl: imageUrl)
        
        // Observe player item status
        playerItem.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.old, .new], context: &playerItemContext)
        
        // Setup player
        player = .init(playerItem: playerItem)
        
        // Skips initial buffering
        player.automaticallyWaitsToMinimizeStalling = false
        
        player.play()
        
        // Observe finished playing
        notificationCenter.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying(notification:)),
            name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // Set audio session as active to play in background
        
        try? audioSession.setCategory(AVAudioSession.Category.playback)
        try? audioSession.setActive(true)
        
        // Observe progress
        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let mainQueue = DispatchQueue.main
        player.addPeriodicTimeObserver(forInterval: interval, queue: mainQueue) { [weak self] time in
            let currentSeconds = CMTimeGetSeconds(time)
            let currentMillis = 1000 * currentSeconds
            
            self?.progressChanged(timeInMillis: Int(currentMillis))
        }
    }
    
    func resume() {
        player.play()
        if player.currentItem != nil {
            playingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = CMTimeGetSeconds(player.currentTime())
            playingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 1
        }
        delegate?.audioPlayerDidResumed()
    }
    
    func pause() {
        player.pause()
        if player.currentItem != nil {
            let currentTime = CMTimeGetSeconds(player.currentTime())
            playingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            playingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 0
        }
        delegate?.audioPlayerDidPaused()
    }
    
    func stop() {
        player.pause()
        player.seek(to: .init(value: 0, timescale: 1))
        
        playingInfoCenter.nowPlayingInfo = nil
        
        // Set audio session as active to play in background
        do {
            try audioSession.setActive(false)
        } catch {
            debugPrint("Failed to set AVAudioSession to inactive")
        }
        
        notificationCenter.removeObserver(
            self,
            name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )        
        
        delegate?.audioPlayerDidStoped()
    }
    
    func seekTo(time: Int) {
           let seekTo = CMTimeMakeWithSeconds(Float64(time / 1000), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
           player.seek(to: seekTo)
           guard player.currentItem != nil else {
               return
           }
           
           playingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Float64(time / 1000)
       }
    
    func setupRemoteTransportControls() {
        // Get the shared MPRemoteCommandCenter
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Add handler for Play Command
        commandCenter.playCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            
            self.resume()
            return .success
        }
        
        // Add handler for Pause Command
        commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            
            self.pause()
            return .success
        }
        
        // Add skip forward/backward track
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            
            return self.skipForward() ? .success : .commandFailed
        }
        
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            
            return self.skipBackward() ? .success : .commandFailed
        }
        
        
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let time = CMTime(seconds: event.positionTime, preferredTimescale: 1000000).seconds
            self?.seekTo(time: Int(1000 * time))
            
            return .success
        }
    }
}

@available(iOS 10.0, *)
private extension AudioPlayerImpl {
    func skipForward() -> Bool {
        if (totalDurationInMillis > currentProgressInMillis + skipForwardTimeInMillis) {
            // Episode is loaded and there is enough time to skip forward
            seekTo(time: currentProgressInMillis + skipForwardTimeInMillis)
            return true
        } else {
            debugPrint("Unable to skip forward, episode is not loaded or there is not enough time to skip forward")
            return false
        }
    }
    
    func skipBackward() -> Bool {
        if (currentProgressInMillis - skipBackwardTimeInMillis > 0) {
            // Episode is loaded and there is enough time to skip backward
            seekTo(time: currentProgressInMillis - skipBackwardTimeInMillis)
            return true
        } else {
            debugPrint("Unable to skip backward, episode is not loaded or there is not enough time to skip backward")
            return false
        }
    }
    
    func updateNowPlayingInfoCenter(title: String, artist: String?, album: String?, imageUrl: String?) {
        playingInfoCenter.nowPlayingInfo = [MPMediaItemPropertyTitle: title, MPMediaItemPropertySkipCount: "15"]
        
        if let album = album {
            playingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyAlbumTitle] = album
        }
        
        if let artist = artist {
            playingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyArtist] = artist
        }
        
        guard let imageUrl = imageUrl,
            let url = URL(string: imageUrl),
            let data = try? Data(contentsOf: url),
            let artwork = UIImage(data: data) else {
                return
        }
        
        let itemArtwork: MPMediaItemArtwork = .init(boundsSize: artwork.size, requestHandler: { _ in artwork })
        playingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] = itemArtwork
    }
    
    func progressChanged(timeInMillis: Int) {
        currentProgressInMillis = timeInMillis
        delegate?.audioPlayerDidChangeProgress(timeInMillis)
    }
    
    @objc func playerDidFinishPlaying(notification: Notification) {
        delegate?.audioPlayerDidComplete()
    }
}

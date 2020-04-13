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
    /// - Parameter progress: progress in secconds
    func audioPlayerDidChangeProgress(_ progress: Int)
    /// - Parameter duration: duration in secconds
    func audioPlayerDidLoad(duration: Int)
    func audioPlayerDidStop()
    func audioPlayerDidPause()
    func audioPlayerDidResume()
    func audioPlayerDidComplete()
}

protocol AudioPlayer {
    var delegate: AudioPlayerDelegate? { get set }
    
    func play(url: String, title: String?, artist: String?, album: String?, imageUrl: String?)
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
    /// current  progress  in milliseconds
    private var currentProgress = -1
    /// total  duration  in milliseconds
    private var totalDuration = -1
    /// seek forward time in milliseconds
    private let seekForwardTime = 15_000
    /// seek backward time in milliseconds
    private let seekBackwardTime = 15_000
    
    private var playerTimeObserver: Any?
    private var playCommandTarget: Any?
    private var pauseCommandTarget: Any?
    private var skipForwardCommandTarget: Any?
    private var skipBackwardCommandTarget: Any?
    private var seekToCommandTarget: Any?
    
    private var playingInfoCenter: MPNowPlayingInfoCenter {
        return MPNowPlayingInfoCenter.default()
    }
    
    private var notificationCenter: NotificationCenter {
        return NotificationCenter.default
    }
    
    private var audioSession: AVAudioSession {
        return AVAudioSession.sharedInstance()
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
            guard playerItem.duration.isNumeric else {
                return
            }

            let duration = playerItem.duration.seconds
            totalDuration = Int(1000 * duration)

            // Update control center
            playingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = duration

            delegate?.audioPlayerDidLoad(duration: totalDuration)

        case .failed:
            debugPrint("Failed AVPlayerItem state.")
        case .unknown:
            debugPrint("Unknown AVPlayerItem state.")
        @unknown default:
            debugPrint("Unhandled AVPlayerItem state")
        }
    }

    func play(url: String, title: String?, artist: String?, album: String?, imageUrl: String?) {
        // Setup player item
        guard let audioUrl = URL(string: url) else { return }

        // Set audio session as active to play in background
        do {
            try audioSession.setCategory(.playback, options: [.allowBluetooth, .duckOthers])
            try audioSession.setActive(true)
        } catch let e {
            debugPrint(e.localizedDescription)
            debugPrint("Failed to set AVAudioSession to active")
        }

        playerItem = .init(url: audioUrl)

        // Observe finished playing
        notificationCenter.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying(notification:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        // Setup player
        player = .init(playerItem: playerItem)

        // Observe player item status
        playerItem.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.old, .new], context: &playerItemContext)

        // Skips initial buffering
        player.automaticallyWaitsToMinimizeStalling = false

        // Setup control center
        setupRemoteTransportControls()

        // Update control center
        updateNowPlayingInfoCenter(title: title, artist: artist, album: album, imageUrl: imageUrl)

        // Observe progress
        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        playerTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let currentSeconds = time.seconds
            let currentMillis = 1000 * currentSeconds

            self?.progressChanged(time: Int(currentMillis))
        }

        player.play()
    }

    func resume() {
        guard let player = player else { return }

        player.play()
        if player.currentItem != nil {
            let currentTime = CMTimeGetSeconds(player.currentTime())
            playingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            playingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 1
        }
        delegate?.audioPlayerDidResume()
    }

    func pause() {
        guard let player = player else { return }

        player.pause()
        if player.currentItem != nil {
            let currentTime = CMTimeGetSeconds(player.currentTime())
            playingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            playingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = 0
        }
        delegate?.audioPlayerDidPause()
    }

    func stop() {
        guard let player = player, let playerItem = playerItem else { return }

        player.pause()
        player.seek(to: .init(value: 0, timescale: 1))
        player.replaceCurrentItem(with: nil)
        playingInfoCenter.nowPlayingInfo = nil

        // Set audio session as inactive
        do {
            try audioSession.setActive(false)
        } catch let e {
            debugPrint(e.localizedDescription)
            debugPrint("Failed to set AVAudioSession to inactive")
        }

        if let observer = playerTimeObserver {
            player.removeTimeObserver(observer)
            playerTimeObserver = nil
        }

        removeRemoteTransportControls()
        notificationCenter.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        self.playerItem.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), context: &playerItemContext)
        self.playerItem = nil
        self.player = nil
        delegate?.audioPlayerDidStop()
    }

    func seekTo(time: Int) {
        // Playback is not automatically paused when seeking, handle this manually
        let isPlaying = player.rate > 0.0
        
        if (isPlaying) {
            pause()
        }
        
        let seekTo = CMTimeMakeWithSeconds(Float64(time / 1000), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: seekTo, completionHandler: { [weak self] success in
            // Resume playback if player was previously playing
            if (isPlaying) {
                self?.resume()
            }
            
            guard self?.player.currentItem != nil else {
                return
            }
            
            self?.playingInfoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Float64(time / 1000)
        })
    }
    
}

@available(iOS 10.0, *)
private extension AudioPlayerImpl {
    
    func removeRemoteTransportControls() {
        // Get the shared MPRemoteCommandCenter
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.removeTarget(playCommandTarget)
        commandCenter.pauseCommand.removeTarget(pauseCommandTarget)
        commandCenter.skipForwardCommand.removeTarget(skipForwardCommandTarget)
        commandCenter.skipBackwardCommand.removeTarget(skipBackwardCommandTarget)
        commandCenter.changePlaybackPositionCommand.removeTarget(seekToCommandTarget)
    }
    
    func setupRemoteTransportControls() {
        // Get the shared MPRemoteCommandCenter
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Add handler for Play Command
        playCommandTarget = commandCenter.playCommand.addTarget { [weak self] event in
            guard let self = self else { return .noSuchContent }
            
            self.resume()
            return .success
        }
        
        // Add handler for Pause Command
        pauseCommandTarget = commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let self = self else { return .noSuchContent }
            
            self.pause()
            return .success
        }
        
        // Add skip forward/backward track
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        skipForwardCommandTarget = commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let self = self else { return .noSuchContent }
            
            return self.seekForward() ? .success : .commandFailed
        }
        
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        skipBackwardCommandTarget = commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self = self else { return .noSuchContent }
            
            return self.seekBackward() ? .success : .commandFailed
        }
        
        seekToCommandTarget = commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self else { return .noSuchContent }
            
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let time = CMTime(seconds: event.positionTime, preferredTimescale: 1000000).seconds
            self.seekTo(time: Int(1000 * time))
            
            return .success
        }
    }
    
    func seekForward() -> Bool {
        let time = currentProgress + seekForwardTime
        if (totalDuration > time) {
            // Episode is loaded and there is enough time to seek forward
            seekTo(time: time)
            return true
        } else {
            debugPrint("Unable to seek forward, episode is not loaded or there is not enough time to seek forward")
            return false
        }
    }
    
    func seekBackward() -> Bool {
        let time = currentProgress - seekBackwardTime
        if (time > 0) {
            // Episode is loaded and there is enough time to seek backward
            seekTo(time: time)
            return true
        } else {
            debugPrint("Unable to seek backward, episode is not loaded or there is not enough time to seek backward")
            return false
        }
    }
    
    func updateNowPlayingInfoCenter(title: String?, artist: String?, album: String?, imageUrl: String?) {
        playingInfoCenter.nowPlayingInfo = [
            MPMediaItemPropertySkipCount: "15",
            MPNowPlayingInfoPropertyMediaType: NSNumber(value: MPNowPlayingInfoMediaType.audio.rawValue)
        ]
        
        if let title = title {
            playingInfoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] = title
        }
        
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
    
    /// - Parameter time: progress in milliseconds
    func progressChanged(time: Int) {
        currentProgress = time
        delegate?.audioPlayerDidChangeProgress(time)
    }
    
    @objc func playerDidFinishPlaying(notification: Notification) {
        delegate?.audioPlayerDidComplete()
    }
}

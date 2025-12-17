//
//  AudioManager.swift
//  offio
//
//  Created by Theo on 12/16/25.
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import MediaPlayer

@Observable
class AudioManager: NSObject, AVAudioPlayerDelegate {
    
    static let shared = AudioManager()

    var audioFiles: [URL] = []
    var currentTrackIndex: Int?
    var isPlaying: Bool = false
    var duration: TimeInterval = 0.0
    var currentTime: TimeInterval = 0.0
    
    // --- SHUFFLE QUEUE ---
    var shuffledIndices: [Int] = []
    
    // --- CUSTOM NAMES ---
    var customNames: [String: String] = [:]
    
    enum PlayStrategy: String { // Use RawValue for saving
        case off, all, shuffle
    }
    
    // --- Playback Settings ---
    var playStrategy: PlayStrategy = .off {
        didSet {
            // Save state whenever it changes
            UserDefaults.standard.set(playStrategy.rawValue, forKey: "PlayStrategy")
        }
    }
    var isRepeatOne: Bool = false {
        didSet {
            // Save state whenever it changes
            UserDefaults.standard.set(isRepeatOne, forKey: "IsRepeatOne")
        }
    }
    // ---------------------------------
    
    var trackImage: UIImage? = nil
    var trackName: String = "No Audio Selected"
    
    var player: AVAudioPlayer?
    var timer: Timer?
    
    
    // Make init private so no one can accidentally create a second instance
    private override init() {
        super.init()
        
        // 1. Setup Audio Session FIRST
        setupAudioSession()
        
        // 2. Load Data
        loadCustomNames()
        restorePlaybackSettings()
        loadFilesFromDocumentDirectory()
        
        // 3. Setup Commands
        setupRemoteCommandCenter()
        
        // 4. Restore State
        restoreLastPlayedTrack()
        
        if playStrategy == .shuffle {
            generateShuffleList()
        }
    }
    
    // MARK: - State Persistence
    
    func loadCustomNames() {
        if let saved = UserDefaults.standard.dictionary(forKey: "CustomTrackNames") as? [String: String] {
            customNames = saved
        }
    }
    
    func restorePlaybackSettings() {
        if let savedStrategy = UserDefaults.standard.string(forKey: "PlayStrategy"),
           let strategy = PlayStrategy(rawValue: savedStrategy) {
            self.playStrategy = strategy
        }
        self.isRepeatOne = UserDefaults.standard.bool(forKey: "IsRepeatOne")
    }
    
    
    func getDisplayName(for url: URL) -> String {
        let filename = url.lastPathComponent
        return customNames[filename] ?? filename
    }
    
    func renameCurrentTrack(to userTypedName: String) {
        guard let index = currentTrackIndex, audioFiles.indices.contains(index) else { return }
        guard !userTypedName.isEmpty else { return }
        
        let currentUrl = audioFiles[index]
        let fileExtension = currentUrl.pathExtension
        let oldFilename = currentUrl.lastPathComponent
        
        var cleanName = userTypedName
        if cleanName.hasSuffix("." + fileExtension) {
            cleanName = String(cleanName.dropLast(fileExtension.count + 1))
        }
        
        let newPhysicalName = cleanName + "." + fileExtension
        let directory = currentUrl.deletingLastPathComponent()
        let newUrl = directory.appendingPathComponent(newPhysicalName)
        
        do {
            let fileManager = FileManager.default
            
            if currentUrl != newUrl {
                try fileManager.moveItem(at: currentUrl, to: newUrl)
                let oldArt = currentUrl.appendingPathExtension("jpg")
                let newArt = newUrl.appendingPathExtension("jpg")
                if fileManager.fileExists(atPath: oldArt.path) {
                    try? fileManager.moveItem(at: oldArt, to: newArt)
                }
            }
            
            customNames.removeValue(forKey: oldFilename)
            customNames[newPhysicalName] = userTypedName
            UserDefaults.standard.set(customNames, forKey: "CustomTrackNames")
            
            loadFilesFromDocumentDirectory()
            
            if let newIndex = audioFiles.firstIndex(of: newUrl) {
                currentTrackIndex = newIndex
                trackName = getDisplayName(for: newUrl)
                UserDefaults.standard.set(newUrl.lastPathComponent, forKey: "LastPlayedTrack")
                updateNowPlayingInfo()
                if playStrategy == .shuffle { generateShuffleList() }
            }
        } catch { print("Error renaming: \(error)") }
    }
    
    func playTrack(at index: Int) {
        player?.stop()
        guard audioFiles.indices.contains(index) else { return }
        
        currentTrackIndex = index
        let url = audioFiles[index]
        trackName = getDisplayName(for: url)
        UserDefaults.standard.set(url.lastPathComponent, forKey: "LastPlayedTrack")
        loadCustomImage(for: url)
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
            
            duration = player?.duration ?? 0.0
            isPlaying = true
            startTimer()
            updateNowPlayingInfo()
        } catch {
            print("Playback failed: \(error)")
        }
    }
    
    func setupAudioSession() {
        do {
           
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session: \(error)")
        }
    }
   
    func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // 1. CLEAR EVERYTHING FIRST
        // This ensures if the app effectively restarts, we don't have stale targets.
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        
        // 2. PAUSE
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            
            // Explicitly run on Main Thread
            DispatchQueue.main.async {
                self.player?.pause()
                self.isPlaying = false
                self.timer?.invalidate()
                self.updateNowPlayingInfo() // Force UI update
            }
            return .success
        }
        
        // 3. PLAY
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            
            DispatchQueue.main.async {
                // Only play if player exists. Do NOT create a new player here.
                if let player = self.player {
                    // Ensure session is active before playing
                    try? AVAudioSession.sharedInstance().setActive(true)
                    player.play()
                    self.isPlaying = true
                    self.startTimer()
                    self.updateNowPlayingInfo()
                }
            }
            return .success
        }
        
        // 4. TOGGLE (Headphones/Earbuds)
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            
            DispatchQueue.main.async {
                self.togglePlayPause() // Reuse your existing logic
            }
            return .success
        }
        
        // 5. NEXT
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async { self.nextTrack() }
            return .success
        }
        
        // 6. PREVIOUS
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async { self.previousTrack(force: false) }
            return .success
        }
        
        // 7. SCRUBBER
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            
            DispatchQueue.main.async {
                self.player?.currentTime = event.positionTime
                self.currentTime = event.positionTime
                self.updateNowPlayingInfo()
            }
            return .success
        }
        
        // 8. IMPORTANT: Set the app strictly to receive remote events
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }
    
    
    
    func playFromRemote() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            player?.play()
            isPlaying = true
            startTimer()
            updateNowPlayingInfo()
        } catch {
            print("Remote play failed:", error)
        }
    }

    func pauseFromRemote() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        updateNowPlayingInfo()
    }
    func syncPlaybackState() {
        isPlaying = player?.isPlaying ?? false
        updateNowPlayingInfo()
    }
    
    
    
    func cyclePlayStrategy() {
        switch playStrategy {
        case .off: playStrategy = .shuffle; generateShuffleList()
        case .shuffle: playStrategy = .all
        case .all: playStrategy = .off
        }
    }
    
    func generateShuffleList() {
        shuffledIndices = audioFiles.indices.shuffled()
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard let current = currentTrackIndex else { return }
        if isRepeatOne { playTrack(at: current); return }
        
        if let next = getNextTrackIndex() {
            if playStrategy == .off && next == 0 && !isShuffleMode() {
                if current == audioFiles.count - 1 {
                    isPlaying = false; seek(to: 0); updateNowPlayingInfo(); return
                }
            }
            playTrack(at: next)
        }
    }
    
    private func isShuffleMode() -> Bool {
        return playStrategy == .shuffle && !shuffledIndices.isEmpty
    }
    
    func getNextTrackIndex() -> Int? {
        guard let current = currentTrackIndex, !audioFiles.isEmpty else { return nil }
        
        if isShuffleMode() {
            if let indexInShuffle = shuffledIndices.firstIndex(of: current) {
                let nextShufflePos = indexInShuffle + 1
                return nextShufflePos < shuffledIndices.count ? shuffledIndices[nextShufflePos] : shuffledIndices[0]
            } else { return shuffledIndices.first }
        } else {
            let nextIndex = current + 1
            if nextIndex < audioFiles.count { return nextIndex }
            else { return playStrategy == .all ? 0 : nil }
        }
    }
    
    func getPreviousTrackIndex() -> Int? {
        guard let current = currentTrackIndex, !audioFiles.isEmpty else { return nil }
        
        if isShuffleMode() {
            if let indexInShuffle = shuffledIndices.firstIndex(of: current) {
                let prevShufflePos = indexInShuffle - 1
                return prevShufflePos >= 0 ? shuffledIndices[prevShufflePos] : shuffledIndices.last
            } else { return shuffledIndices.first }
        } else {
            let prevIndex = current - 1
            if prevIndex >= 0 { return prevIndex }
            else { return playStrategy == .all ? audioFiles.count - 1 : nil }
        }
    }
    
    func nextTrack() {
        if let next = getNextTrackIndex() {
            if playStrategy == .off && next == 0 && !isShuffleMode() {
                isPlaying = false; updateNowPlayingInfo()
                
            } else { playTrack(at: next) }
        }
    }
    
    func previousTrack(force: Bool = false) {
        if !force && currentTime > 3.0 { seek(to: 0); return }
        if let prev = getPreviousTrackIndex() { playTrack(at: prev) }
    }
    
    func togglePlayPause() {
        guard let player = player else { return }
        
        if self.isPlaying {
            print("pause")
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            print("play")
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                player.play()
                isPlaying = true
                startTimer()
            } catch {
                print("Failed to activate audio session: \(error)")
            }
        }
        updateNowPlayingInfo()
    }
    
    func startScrubbing() { if isPlaying { player?.pause(); timer?.invalidate() } }
    func endScrubbing() { if isPlaying { player?.play(); startTimer() } }
    
    func startTimer() { timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in self.currentTime = self.player?.currentTime ?? 0.0 } }
    func seek(to time: TimeInterval) { player?.currentTime = time; currentTime = time; updateNowPlayingInfo() }
    
    func updateNowPlayingInfo() {
        guard let player = player else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var nowPlayingInfo = [String: Any]()
        
        // Title
        nowPlayingInfo[MPMediaItemPropertyTitle] = trackName
        
        // Artwork
        if let image = trackImage {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in return image }
        }
        
        // Duration
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = player.duration
        
        // Current Time
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
        
        // Rate (1.0 = Playing, 0.0 = Paused)
        // This tells the iPhone to show the Pause bars vs the Play triangle
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    func importFile(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let fileManager = FileManager.default
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destination = docs.appendingPathComponent(url.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
                let oldImage = destination.appendingPathExtension("jpg")
                if fileManager.fileExists(atPath: oldImage.path) { try? fileManager.removeItem(at: oldImage) }
            }
            try fileManager.copyItem(at: url, to: destination)
            DispatchQueue.main.async {
                self.loadFilesFromDocumentDirectory()
                if self.playStrategy == .shuffle { self.generateShuffleList() }
                
            }
        } catch { print("Error importing file: \(error)") }
    }
    
    func loadFilesFromDocumentDirectory() {
        // 1. Capture the URL of the song currently playing (before we change the array order)
        var currentlyPlayingURL: URL? = nil
        if let index = currentTrackIndex, audioFiles.indices.contains(index) {
            currentlyPlayingURL = audioFiles[index]
        }

        // 2. Perform the load and sort
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let items = try fileManager.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)
            self.audioFiles = items
                .filter { ["mp3", "m4a", "wav"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            
        } catch {
            print("Error loading files: \(error)")
        }

        // 3. Find where the playing song moved to in the new list
        if let url = currentlyPlayingURL, let newIndex = audioFiles.firstIndex(of: url) {
            // Update the pointer so the UI stays on the correct song
            currentTrackIndex = newIndex
        } else {
            // If the playing file was somehow deleted during this process
            if currentlyPlayingURL != nil {
                currentTrackIndex = nil
            }
        }
    }
    
    func restoreLastPlayedTrack() {
        guard let lastPlayedName = UserDefaults.standard.string(forKey: "LastPlayedTrack") else { return }
        if let index = audioFiles.firstIndex(where: { $0.lastPathComponent == lastPlayedName }) {
            currentTrackIndex = index; let url = audioFiles[index];
            trackName = getDisplayName(for: url)
            loadCustomImage(for: url)
            do { player = try AVAudioPlayer(contentsOf: url); player?.delegate = self; player?.prepareToPlay(); duration = player?.duration ?? 0.0; updateNowPlayingInfo() } catch { print("Failed to restore track") }
        }
    }
    
    func saveImage(_ image: UIImage, for url: URL) {
        self.trackImage = image; updateNowPlayingInfo()
        let imageUrl = url.appendingPathExtension("jpg")
        if let data = image.jpegData(compressionQuality: 0.8) { try? data.write(to: imageUrl) }
    }
    
    func loadCustomImage(for url: URL) { if let image = getImage(for: url) { self.trackImage = image } else { self.trackImage = nil } }
    func getImage(at index: Int) -> UIImage? { guard audioFiles.indices.contains(index) else { return nil }; return getImage(for: audioFiles[index]) }
    private func getImage(for url: URL) -> UIImage? {
        let imageUrl = url.appendingPathExtension("jpg")
        if FileManager.default.fileExists(atPath: imageUrl.path), let data = try? Data(contentsOf: imageUrl), let image = UIImage(data: data) { return image }
        return nil
    }
}
extension TimeInterval {
    func formattedString() -> String {
        let hours = Int(self) / 3600; let minutes = Int(self) / 60 % 60; let seconds = Int(self) % 60
        return hours > 0 ? String(format: "%02i:%02i:%02i", hours, minutes, seconds) : String(format: "%02i:%02i", minutes, seconds)
    }
}

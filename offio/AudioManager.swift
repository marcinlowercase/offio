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
            UserDefaults.standard.set(playStrategy.rawValue, forKey: "PlayStrategy")
            updateCommandAvailability()
        }
    }
    var isRepeatOne: Bool = false {
        didSet {
            UserDefaults.standard.set(isRepeatOne, forKey: "IsRepeatOne")
        }
    }
    
    var trackImage: UIImage? = nil
    var trackName: String = "No Audio Selected"
    
    var player: AVAudioPlayer?
    var timer: Timer?
    
    private override init() {
        super.init()
        setupAudioSession()
        loadCustomNames()
        restorePlaybackSettings()
        loadFilesFromDocumentDirectory()
        setupRemoteCommandCenter()
        restoreLastPlayedTrack()
        
        if playStrategy == .shuffle {
            generateShuffleList()
        }
    }
    
    // MARK: - File Management
    
    func deleteTrack(at index: Int) {
        guard audioFiles.indices.contains(index) else { return }
        let url = audioFiles[index]
        var nextTrackUrlToFocus: URL? = nil
        
        // 1. IF DELETING CURRENT TRACK: Determine what to focus next
        if currentTrackIndex == index {
            
            // Try to find the next track based on current strategy (Shuffle/Repeat)
            if let nextIndex = getNextTrackIndex() {
                nextTrackUrlToFocus = audioFiles[nextIndex]
            }
            // If next is nil (e.g. End of list + Repeat Off), try Previous
            else if let prevIndex = getPreviousTrackIndex() {
                nextTrackUrlToFocus = audioFiles[prevIndex]
            }
            
            // Stop current playback
            player?.stop()
            player = nil
            isPlaying = false
            timer?.invalidate()
            
            // Clear metadata temporarily
            trackName = "No Audio Selected"
            trackImage = nil
            currentTime = 0
            duration = 0
            currentTrackIndex = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        
        // 2. Delete File from Disk
        do {
            try FileManager.default.removeItem(at: url)
            let artUrl = url.appendingPathExtension("jpg")
            if FileManager.default.fileExists(atPath: artUrl.path) {
                try? FileManager.default.removeItem(at: artUrl)
            }
            
            let filename = url.lastPathComponent
            if customNames[filename] != nil {
                customNames.removeValue(forKey: filename)
                UserDefaults.standard.set(customNames, forKey: "CustomTrackNames")
            }
            
            // 3. HANDLE SHUFFLE QUEUE UPDATE
            if !shuffledIndices.isEmpty {
                if let indexInShuffle = shuffledIndices.firstIndex(of: index) {
                    shuffledIndices.remove(at: indexInShuffle)
                }
                for i in 0..<shuffledIndices.count {
                    if shuffledIndices[i] > index {
                        shuffledIndices[i] -= 1
                    }
                }
            }
            
            // 4. Handle Index Shift (for normal logic)
            if let current = currentTrackIndex, index < current {
                currentTrackIndex = current - 1
            }
            
            // 5. Reload List
            loadFilesFromDocumentDirectory()
            
            if playStrategy == .shuffle && shuffledIndices.isEmpty && !audioFiles.isEmpty {
                generateShuffleList()
            }
            
            // 6. RE-FOCUS LOGIC
            // If we have a target URL (from Step 1), find its new index and prepare it
            if let targetUrl = nextTrackUrlToFocus, let newIndex = audioFiles.firstIndex(of: targetUrl) {
                preparePlayer(at: newIndex)
            } else if currentTrackIndex == nil && !audioFiles.isEmpty {
                // Fallback: If logic failed but we still have files, focus the first one
                preparePlayer(at: 0)
            } else {
                 updateCommandAvailability()
            }
            
        } catch {
            print("Error deleting file: \(error)")
        }
    }
    
    func renameTrack(at index: Int, to userTypedName: String) {
        guard audioFiles.indices.contains(index) else { return }
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
            
            // Reload to reflect changes
            loadFilesFromDocumentDirectory()
            
            // If we renamed the currently playing track, update the UI
            if let newIndex = audioFiles.firstIndex(of: newUrl) {
                if currentTrackIndex == index {
                    currentTrackIndex = newIndex
                    trackName = getDisplayName(for: newUrl)
                    UserDefaults.standard.set(newUrl.lastPathComponent, forKey: "LastPlayedTrack")
                    updateNowPlayingInfo()
                }
                if playStrategy == .shuffle { generateShuffleList() }
            }
        } catch { print("Error renaming: \(error)") }
    }
    
    // MARK: - State Persistence & Helpers
    
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
    
    // MARK: - Playback Logic
    
    // NEW FUNCTION: Loads track, sets metadata, but DOES NOT play.
    // Used for "Focus" on import or after delete.
    func preparePlayer(at index: Int) {
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
            
            // Don't play, just setup
            duration = player?.duration ?? 0.0
            currentTime = 0.0
            isPlaying = false
            timer?.invalidate() // Ensure timer isn't running
            
            updateNowPlayingInfo()
        } catch {
            print("Prepare failed: \(error)")
        }
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
        } catch { print("Failed to set audio session: \(error)") }
    }
   
    func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.player?.pause()
                self.isPlaying = false
                self.timer?.invalidate()
                self.updateNowPlayingInfo()
            }
            return .success
        }
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                if let player = self.player {
                    try? AVAudioSession.sharedInstance().setActive(true)
                    player.play()
                    self.isPlaying = true
                    self.startTimer()
                    self.updateNowPlayingInfo()
                }
            }
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async { self.togglePlayPause() }
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async { self.nextTrack() }
            return .success
        }
        
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async { self.previousTrack(force: false) }
            return .success
        }
        
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
        
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }
    
    func updateCommandAvailability() {
        let center = MPRemoteCommandCenter.shared()
        guard let index = currentTrackIndex, !audioFiles.isEmpty else {
            center.nextTrackCommand.isEnabled = false; center.previousTrackCommand.isEnabled = false; return
        }
        if playStrategy == .off {
            center.previousTrackCommand.isEnabled = (index > 0)
            center.nextTrackCommand.isEnabled = (index < audioFiles.count - 1)
        } else {
            center.previousTrackCommand.isEnabled = true; center.nextTrackCommand.isEnabled = true
        }
    }
    
    func cyclePlayStrategy() {
        switch playStrategy {
        case .off: playStrategy = .shuffle; generateShuffleList()
        case .shuffle: playStrategy = .all
        case .all: playStrategy = .off
        }
    }
    
    func generateShuffleList() { shuffledIndices = audioFiles.indices.shuffled() }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard let current = currentTrackIndex else { return }
        if isRepeatOne { playTrack(at: current); return }
        if let next = getNextTrackIndex() {
            if playStrategy == .off && next == 0 && !isShuffleMode() {
                if current == audioFiles.count - 1 { isPlaying = false; seek(to: 0); updateNowPlayingInfo(); return }
            }
            playTrack(at: next)
        }
    }
    
    private func isShuffleMode() -> Bool { return playStrategy == .shuffle && !shuffledIndices.isEmpty }
    
    func getNextTrackIndex() -> Int? {
        guard let current = currentTrackIndex, !audioFiles.isEmpty else { return nil }
        if isShuffleMode() {
            if let indexInShuffle = shuffledIndices.firstIndex(of: current) {
                let nextShufflePos = indexInShuffle + 1
                return nextShufflePos < shuffledIndices.count ? shuffledIndices[nextShufflePos] : shuffledIndices[0]
            } else { return shuffledIndices.first }
        } else {
            let nextIndex = current + 1
            if nextIndex < audioFiles.count { return nextIndex } else { return playStrategy == .all ? 0 : nil }
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
            if prevIndex >= 0 { return prevIndex } else { return playStrategy == .all ? audioFiles.count - 1 : nil }
        }
    }
    
    func nextTrack() {
        if let next = getNextTrackIndex() {
            if playStrategy == .off && next == 0 && !isShuffleMode() { isPlaying = false; updateNowPlayingInfo() } else { playTrack(at: next) }
        }
    }
    
    func previousTrack(force: Bool = false) {
        if !force && currentTime > 3.0 { seek(to: 0); return }
        if let prev = getPreviousTrackIndex() { playTrack(at: prev) }
    }
    
    func togglePlayPause() {
        guard let player = player else { return }
        if self.isPlaying { player.pause(); isPlaying = false; timer?.invalidate() }
        else { try? AVAudioSession.sharedInstance().setActive(true); player.play(); isPlaying = true; startTimer() }
        updateNowPlayingInfo()
    }
    
    func startScrubbing() { if isPlaying { player?.pause(); timer?.invalidate() } }
    func endScrubbing() { if isPlaying { player?.play(); startTimer() } }
    func startTimer() { timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in self.currentTime = self.player?.currentTime ?? 0.0 } }
    func seek(to time: TimeInterval) { player?.currentTime = time; currentTime = time; updateNowPlayingInfo() }
    
    func updateNowPlayingInfo() {
        guard let player = player else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; updateCommandAvailability(); return }
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = trackName
        if let image = trackImage { nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in return image } }
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = player.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        updateCommandAvailability()
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
            DispatchQueue.main.async { self.loadFilesFromDocumentDirectory(); if self.playStrategy == .shuffle { self.generateShuffleList() } }
        } catch { print("Error importing file: \(error)") }
    }
    
    func loadFilesFromDocumentDirectory() {
        var currentlyPlayingURL: URL? = nil
        if let index = currentTrackIndex, audioFiles.indices.contains(index) { currentlyPlayingURL = audioFiles[index] }
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let items = try fileManager.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)
            self.audioFiles = items.filter { ["mp3", "m4a", "wav"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch { print("Error loading files: \(error)") }
        
        if let url = currentlyPlayingURL, let newIndex = audioFiles.firstIndex(of: url) {
            currentTrackIndex = newIndex
        } else {
            if currentlyPlayingURL != nil {
                currentTrackIndex = nil
            } else if currentTrackIndex == nil && !audioFiles.isEmpty {
                // 👇 NEW LOGIC: If no track was playing (nil), but we now have files (first import),
                // Focus the first track (index 0) so user can just hit play.
                preparePlayer(at: 0)
            }
        }
        updateCommandAvailability()
    }
    
    func restoreLastPlayedTrack() {
        guard let lastPlayedName = UserDefaults.standard.string(forKey: "LastPlayedTrack") else { return }
        if let index = audioFiles.firstIndex(where: { $0.lastPathComponent == lastPlayedName }) {
            currentTrackIndex = index; let url = audioFiles[index]; trackName = getDisplayName(for: url); loadCustomImage(for: url)
            do { player = try AVAudioPlayer(contentsOf: url); player?.delegate = self; player?.prepareToPlay(); duration = player?.duration ?? 0.0; updateNowPlayingInfo() } catch { print("Failed to restore track") }
        }
    }
    
    func saveImage(_ image: UIImage, for url: URL) {
        self.trackImage = image; updateNowPlayingInfo()
        let imageUrl = url.appendingPathExtension("jpg"); if let data = image.jpegData(compressionQuality: 0.8) { try? data.write(to: imageUrl) }
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

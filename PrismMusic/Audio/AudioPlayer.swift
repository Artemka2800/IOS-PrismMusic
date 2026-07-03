//
//  AudioPlayer.swift
//  PrismMusic
//
//  AVPlayer wrapper that owns the entire playback domain:
//   - current track + queue + index
//   - play/pause/seek + repeat/shuffle modes
//   - progress + duration broadcasting via @Observable
//   - audio session activation
//   - MPNowPlayingInfoCenter integration
//   - MPRemoteCommandCenter handlers (lock screen + headphones + Siri)
//   - Live Activity / Dynamic Island lifecycle
//
//  This is the single source of truth — the UI never instantiates an
//  AVPlayer of its own.
//

import AVFoundation
import Combine
import Foundation
import MediaPlayer
import Observation
import SwiftUI
import UIKit

@Observable
@MainActor
final class AudioPlayer {
    // MARK: - Observable state

    enum TrackChangeDirection { case forward, backward, none }

    private(set) var currentTrack: Track?
    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int = 0
    private(set) var isPlaying: Bool = false
    private(set) var progress: Double = 0
    private(set) var duration: Double = 0
    private(set) var isBuffering: Bool = false
    /// Direction of the last track change — used by the UI to animate cover slides.
    private(set) var trackChangeDirection: TrackChangeDirection = .none
    private var transitionTask: Task<Void, Never>?

    private var hasTriggeredAutoNext: Bool = false
    private var trackLoadRetryCount = 0

    var errorMessage: String? = nil
    var showError: Bool = false
    var isLoadingStream = false

    var volume: Float {
        get { storedVolume }
        set {
            let val = max(0, min(1, newValue))
            storedVolume = val
            if !isMuted {
                player.volume = val
            }
            NotificationCenter.default.post(name: .prismPlayerStateChanged, object: nil)
        }
    }
    private(set) var isMuted: Bool = false {
        didSet { player.volume = isMuted ? 0 : storedVolume }
    }
    private var storedVolume: Float = 1.0

    enum RepeatMode: String, CaseIterable { case off, all, one }
    var repeatMode: RepeatMode = .off
    var isShuffled: Bool = false

    /// Lyrics parsed for the current track (nil while still loading / absent).
    private(set) var lyrics: ParsedLyrics?

    // MARK: - Internals

    private let api: APIClient
    private let library: LibraryStore
    private var player = AVPlayer()
    private let session = AudioSessionManager()
    private let nowPlaying = NowPlayingManager()
    private let lyricsCache = LyricsCache()

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var endNotificationObserver: NSObjectProtocol?
    private var lastSavedTrackId: String?

    init(api: APIClient, library: LibraryStore) {
        self.api = api
        self.library = library
    }

    // No `deinit` cleanup is needed: AudioPlayer is owned by AppState for
    // the lifetime of the process, and ARC tears down both the AVPlayer
    // and its time observer atomically when the app exits. Touching
    // `@MainActor` state from `deinit` would also violate Swift 6's
    // strict-concurrency rules.

    // MARK: - Public API

    /// One-shot setup called once when the app boots.
    func bootstrap() {
        session.activate()
        setupRemoteCommands()
        attachTimeObserver()
        attachEndNotification()
        // Volume mirror for Now Playing.
        storedVolume = player.volume
    }

    /// Replace the queue and start playing the first track.
    func play(queue tracks: [Track], startAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        let clampedIndex = max(0, min(index, tracks.count - 1))
        self.queue = tracks
        self.currentIndex = clampedIndex
        self.trackChangeDirection = .none
        load(track: tracks[clampedIndex], autoplay: true)
    }

    /// Fetches track recommendations (flow) and sets up the player queue.
    func startStream(seed: Track, client: APIClient, userId: String?) async {
        isLoadingStream = true
        do {
            let recommendations = try await client.recommendTracks(
                id: seed.id,
                source: seed.source?.rawValue ?? "soundcloud",
                title: seed.title,
                artist: seed.artist,
                userId: userId
            )
            
            // Deduplicate: seed track is always first, then recommended ones
            var seen = Set<String>([seed.id])
            var streamTracks = [seed]
            for t in recommendations {
                if !seen.contains(t.id) {
                    seen.insert(t.id)
                    streamTracks.append(t)
                }
            }
            
            if streamTracks.isEmpty {
                throw APIError.invalidResponse
            }
            
            await MainActor.run {
                if self.currentTrack != nil && self.isPlaying {
                    // Smooth transition: don't interrupt active playback
                    let active = self.currentTrack!
                    let filtered = streamTracks.filter { $0.id != active.id }
                    self.queue = [active] + filtered
                    self.currentIndex = 0
                } else {
                    self.queue = streamTracks
                    self.currentIndex = 0
                    load(track: streamTracks[0], autoplay: true)
                }
                self.isLoadingStream = false
                
                // Show confirmation alert
                self.errorMessage = "Поток запущен: \(seed.title) — \(seed.artist)"
                self.showError = true
            }
        } catch {
            await MainActor.run {
                self.isLoadingStream = false
                self.errorMessage = "Не удалось запустить поток: \(error.localizedDescription)"
                self.showError = true
            }
        }
    }

    func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
            if let track = currentTrack {
                saveToHistoryIfNeeded(track: track)
            }
        }
        updateNowPlaying()
        NotificationCenter.default.post(name: .prismPlayerStateChanged, object: nil)
    }

    func next(isAutomatic: Bool = false) {
        guard !queue.isEmpty else { return }
        let nextIndex: Int
        if isShuffled {
            nextIndex = Int.random(in: 0..<queue.count)
        } else if currentIndex + 1 >= queue.count {
            guard repeatMode == .all else {
                // End of queue, no repeat — stop playback gracefully.
                player.pause()
                isPlaying = false
                return
            }
            nextIndex = 0
        } else {
            nextIndex = currentIndex + 1
        }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.85)) {
            trackChangeDirection = .forward
            currentIndex = nextIndex
            load(track: queue[nextIndex], autoplay: true, isAutomatic: isAutomatic)
        }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        // If more than 3s in, restart current track instead of jumping back.
        if progress > 3 {
            seek(to: 0)
            return
        }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.85)) {
            trackChangeDirection = .backward
            let prevIndex = currentIndex == 0 ? queue.count - 1 : currentIndex - 1
            currentIndex = prevIndex
            load(track: queue[prevIndex], autoplay: true)
        }
    }

    func moveTrack(from source: IndexSet, to destination: Int) {
        let offset = currentIndex + 1
        guard offset < queue.count else { return }
        
        var newQueue = queue
        
        // Map source offsets and destination to actual indices in queue
        let adjustedSource = IndexSet(source.map { $0 + offset })
        let adjustedDestination = destination + offset
        
        newQueue.move(fromOffsets: adjustedSource, toOffset: adjustedDestination)
        self.queue = newQueue
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.progress = seconds
                self.updateNowPlaying()
                NotificationCenter.default.post(name: .prismPlayerSeekChanged, object: nil, userInfo: ["currentTime": seconds])
            }
        }
    }

    func toggleMute() {
        if isMuted {
            isMuted = false
        } else {
            storedVolume = player.volume
            isMuted = true
        }
    }

    func toggleRepeat() {
        let all = RepeatMode.allCases
        let next = all[(all.firstIndex(of: repeatMode)! + 1) % all.count]
        repeatMode = next
    }

    func toggleShuffle() { isShuffled.toggle() }

    func toggleLike() {
        guard let track = currentTrack else { return }
        library.toggleLike(track)
        updateNowPlaying()
    }

    func replaceTrackInQueue(oldTrackId: String, with newTrack: Track) {
        if let idx = queue.firstIndex(where: { $0.id == oldTrackId }) {
            queue[idx] = newTrack
        }
        
        if currentTrack?.id == oldTrackId {
            let savedProgress = progress
            let wasPlaying = isPlaying
            load(track: newTrack, autoplay: wasPlaying)
            seek(to: savedProgress)
        }
        updateNowPlaying()
    }

    func syncPlay(track: Track, autoplay: Bool) {
        self.queue = [track]
        self.currentIndex = 0
        self.trackChangeDirection = .none
        load(track: track, autoplay: autoplay)
    }

    func syncStop() {
        player.pause()
        isPlaying = false
        currentTrack = nil
        queue = []
        currentIndex = 0
        updateNowPlaying()
        NotificationCenter.default.post(name: .prismPlayerStateChanged, object: nil)
    }

    func setPlaying(_ playing: Bool) {
        if playing != isPlaying {
            togglePlay()
        }
    }

    // MARK: - Load track

    private func load(track: Track, autoplay: Bool, isAutomatic: Bool = false, isRetry: Bool = false) {
        if !isRetry {
            trackLoadRetryCount = 0
        }
        currentTrack = track
        progress = 0
        duration = track.durationSeconds ?? 0
        isBuffering = true
        lyrics = nil
        hasTriggeredAutoNext = false

        // Check if track is downloaded locally
        let trackURL: URL?
        let safeId = track.id.replacingOccurrences(of: ":", with: "_")
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let docDir = paths.first {
            let localPath = docDir.appendingPathComponent("PrismDownloads/\(safeId).mp3")
            if FileManager.default.fileExists(atPath: localPath.path) {
                trackURL = localPath
                print("[AudioPlayer] Playing offline track from local URL: \(localPath)")
            } else {
                trackURL = api.streamURL(for: track)
            }
        } else {
            trackURL = api.streamURL(for: track)
        }
        
        guard let url = trackURL else {
            print("[AudioPlayer] ⚠️ streamURL returned nil for track: \(track.id)")
            self.errorMessage = "Не удалось получить URL для трека \(track.title)."
            self.showError = true
            self.isBuffering = false
            return
        }
        print("[AudioPlayer] ▶ Loading: \(track.title) — \(track.artist)")
        print("[AudioPlayer]   URL: \(url)")

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        
        let oldPlayer = self.player
        let newPlayer = AVPlayer()
        self.player = newPlayer
        
        // Remove old observers
        if let timeObserver {
            oldPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        statusObserver?.invalidate()
        bufferObserver?.invalidate()
        if let endNotificationObserver {
            NotificationCenter.default.removeObserver(endNotificationObserver)
            self.endNotificationObserver = nil
        }
        
        observePlayerItem(item)
        attachTimeObserver()
        newPlayer.replaceCurrentItem(with: item)
        attachEndNotification()
        
        let targetVolume = isMuted ? 0 : storedVolume
        
        if isAutomatic {
            newPlayer.volume = 0
            if autoplay {
                newPlayer.play()
                self.isPlaying = true
            }
            performCrossfade(oldPlayer: oldPlayer, newPlayer: newPlayer)
        } else {
            // Cancel transition first
            transitionTask?.cancel()
            
            // Instantly stop and unload old player to avoid sound overlap
            oldPlayer.pause()
            oldPlayer.replaceCurrentItem(with: nil)
            
            newPlayer.volume = targetVolume
            if autoplay {
                newPlayer.play()
                self.isPlaying = true
            }
        }

        Task { await fetchLyrics(for: track) }

        if autoplay {
            saveToHistoryIfNeeded(track: track)
        }

        updateNowPlaying()
        NotificationCenter.default.post(name: .prismPlayerStateChanged, object: nil)
    }

    private func performCrossfade(oldPlayer: AVPlayer, newPlayer: AVPlayer) {
        transitionTask?.cancel()
        let targetVolume = isMuted ? 0 : storedVolume
        
        transitionTask = Task { [weak self] in
            guard self != nil else { return }
            
            let crossfadeDuration = 2.0 // 2 seconds crossfade
            let steps = 20
            let interval = crossfadeDuration / Double(steps)
            
            let startVolume = oldPlayer.volume
            
            for step in 1...steps {
                if Task.isCancelled { break }
                
                let progress = Float(step) / Float(steps)
                
                // Fade out old player
                oldPlayer.volume = startVolume * (1.0 - progress)
                
                // Fade in new player
                newPlayer.volume = targetVolume * progress
                
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            
            // Clean up old player
            oldPlayer.pause()
            oldPlayer.replaceCurrentItem(with: nil)
            
            // Ensure new player has final target volume
            if !Task.isCancelled {
                newPlayer.volume = targetVolume
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        statusObserver?.invalidate()
        bufferObserver?.invalidate()

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    let d = item.duration.seconds
                    if d.isFinite, d > 0 { self.duration = d }
                    self.isBuffering = false
                case .failed:
                    let msg = item.error?.localizedDescription ?? "Неизвестная ошибка"
                    print("[AudioPlayer] ❌ Failed to load: \(msg)")
                    self.errorMessage = "Ошибка воспроизведения: \(msg)"
                    self.showError = true
                    self.isBuffering = false
                    
                    // Rotate backend host and retry playback if retry count not exceeded
                    if self.trackLoadRetryCount < APIConfig.hosts.count {
                        self.trackLoadRetryCount += 1
                        print("[AudioPlayer] Rotating host and retrying playback (attempt \(self.trackLoadRetryCount) of \(APIConfig.hosts.count))...")
                        self.api.rotateHost()
                        if let track = self.currentTrack {
                            self.load(track: track, autoplay: self.isPlaying, isRetry: true)
                        } else {
                            self.next()
                        }
                    } else {
                        // Reset count and skip to next track
                        self.trackLoadRetryCount = 0
                        self.errorMessage = "Не удалось воспроизвести трек ни на одном из доступных серверов."
                        self.showError = true
                        self.next()
                    }
                default:
                    break
                }
            }
        }

        bufferObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.isBuffering = !item.isPlaybackLikelyToKeepUp
            }
        }
    }

    // MARK: - Time observation

    private var hasNextTrack: Bool {
        guard !queue.isEmpty else { return false }
        if isShuffled { return true }
        if currentIndex + 1 < queue.count { return true }
        if repeatMode == .all { return true }
        return false
    }

    private func attachTimeObserver() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        // Tick every 250ms — enough granularity for the lyrics RAF
        // interpolator without overloading the main thread.
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                self.progress = seconds
                
                // Trigger early transition for audio crossfade if there's a next track
                let remaining = self.duration - seconds
                if remaining > 0 && remaining <= 3.0 && !self.hasTriggeredAutoNext && self.repeatMode != .one && self.hasNextTrack && self.duration > 10 {
                    self.hasTriggeredAutoNext = true
                    self.next(isAutomatic: true)
                }
                
                // Refresh Now Playing occasionally
                if Int(seconds * 4) % 4 == 0 {
                    self.updateNowPlaying()
                }
            }
        }
    }

    private func attachEndNotification() {
        if let endNotificationObserver {
            NotificationCenter.default.removeObserver(endNotificationObserver)
            self.endNotificationObserver = nil
        }
        guard let currentItem = player.currentItem else { return }
        endNotificationObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                switch self.repeatMode {
                case .one:
                    self.seek(to: 0)
                    self.player.play()
                default:
                    self.next(isAutomatic: true)
                }
            }
        }
    }

    // MARK: - Remote commands (lock screen + headphones)

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else {
            nowPlaying.clear()
            return
        }
        nowPlaying.update(
            track: track,
            isPlaying: isPlaying,
            progress: progress,
            duration: duration
        )
    }

    // MARK: - Lyrics

    private func fetchLyrics(for track: Track) async {
        if let cached = lyricsCache.value(for: track) {
            self.lyrics = cached
            return
        }
        do {
            let response = try await api.lyrics(
                artist: track.artist,
                title: track.title,
                id: track.id,
                duration: track.durationSeconds
            )
            guard let raw = response?.lyrics, !raw.isEmpty else {
                lyricsCache.set(nil, for: track)
                return
            }
            let parsed = LyricsParser.parse(raw, duration: track.durationSeconds)
            lyricsCache.set(parsed, for: track)
            // Only commit if the user hasn't already changed tracks while we waited.
            if currentTrack?.id == track.id {
                self.lyrics = parsed
            }
        } catch {
            // Soft-fail — leave lyrics nil; UI shows "no lyrics" placeholder.
        }
    }

    // MARK: - Play History Recording

    private func saveToHistoryIfNeeded(track: Track) {
        guard api.settings.isLoggedIn else { return }
        let userId = api.settings.userId
        guard lastSavedTrackId != track.id else { return }
        
        lastSavedTrackId = track.id
        Task {
            do {
                try await api.addTrackToHistory(userId: userId, track: track)
                print("[AudioPlayer] Successfully saved track \(track.title) to history")
            } catch {
                print("[AudioPlayer] Failed to save track to history: \(error)")
            }
        }
    }

}

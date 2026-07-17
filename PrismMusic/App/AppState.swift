//
//  AppState.swift
//  PrismMusic
//
//  Root state container. Holds everything that has to outlive a single view:
//   - audio (AVPlayer + Now Playing + Live Activity orchestration)
//   - API client (single instance, reads backend URL from UserDefaults)
//   - library (liked tracks)
//   - recommendations cache (loaded once at app start)
//   - settings (backend URL, Yandex token, immersive mode)
//
//  Wired into the SwiftUI environment by `PrismMusicApp` so any view can
//  pull it via `@Environment(AppState.self)`.s
//

import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class AppState {
    static private(set) var shared: AppState?

    let settings: SettingsStore
    let api: APIClient
    let audio: AudioPlayer
    let library: LibraryStore
    let recommendations: RecommendationsStore
    let search: SearchStore
    let profile: ProfileStore
    let recent: RecentStore
    let networkMonitor: NetworkMonitor
    let downloadStore: DownloadStore
    let sync: CrossDeviceSyncManager

    init() {
        let settings = SettingsStore()
        let api = APIClient(settings: settings)
        let library = LibraryStore(api: api, settings: settings)
        let audio = AudioPlayer(api: api, library: library)
        
        self.settings = settings
        self.api = api
        self.library = library
        self.recommendations = RecommendationsStore()
        self.search = SearchStore()
        self.profile = ProfileStore()
        self.recent = RecentStore()
        self.audio = audio
        self.networkMonitor = NetworkMonitor.shared
        self.downloadStore = DownloadStore(api: api)
        self.sync = CrossDeviceSyncManager(audio: audio, settings: settings, api: api)
        
        AppState.shared = self
    }

    func findAndReplace(track: Track, targetSource: TrackSource) async {
        do {
            let results = try await api.findTrack(
                title: track.title,
                artist: track.artist,
                targetSource: targetSource.rawValue
            )
            
            guard let matchedTrack = results.first else {
                audio.errorMessage = "Трек не найден на \(targetSource.label)"
                audio.showError = true
                return
            }
            
            let newId = "\(targetSource.rawValue):\(matchedTrack.id)"
            let replacedTrack = Track(
                id: newId,
                title: matchedTrack.title,
                artist: matchedTrack.artist,
                album: matchedTrack.album,
                durationSeconds: matchedTrack.durationSeconds,
                cover: matchedTrack.cover,
                streamURL: matchedTrack.streamURL,
                source: targetSource
            )
            
            if library.isLiked(track) {
                library.replaceTrack(track, with: replacedTrack)
            }
            
            audio.replaceTrackInQueue(oldTrackId: track.id, with: replacedTrack)
            
            // If downloaded, delete old and download new
            if downloadStore.isDownloaded(track.id) {
                downloadStore.deleteTrack(track)
                await downloadStore.downloadTrack(replacedTrack)
            }
            
            audio.errorMessage = "Трек успешно заменен на \(targetSource.label)!"
            audio.showError = true
        } catch {
            print("[AppState] Find and replace failed: \(error)")
            audio.errorMessage = "Ошибка замены: \(error.localizedDescription)"
            audio.showError = true
        }
    }

    // MARK: - Dynamic Color Accent

    var accentColor: SwiftUI.Color {
        switch settings.accentTheme {
        case "monochrome":
            return .white
        case "emerald":
            return .emerald
        case "amethyst":
            return SwiftUI.Color(red: 0.64, green: 0.44, blue: 0.96)
        case "azure":
            return SwiftUI.Color(red: 0.22, green: 0.63, blue: 0.95)
        case "sunset":
            return SwiftUI.Color(red: 0.95, green: 0.35, blue: 0.22)
        case "dynamic":
            if let source = audio.currentTrack?.source {
                switch source {
                case .soundcloud:
                    return .orange
                case .yandex:
                    return .yellow
                case .spotify:
                    return .emerald
                case .other:
                    return .emerald
                }
            }
            return .emerald
        default:
            return .emerald
        }
    }
}

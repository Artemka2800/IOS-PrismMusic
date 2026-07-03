//
//  RecentStore.swift
//  PrismMusic
//
//  State manager for the user's listening history.
//

import Foundation
import Observation

@Observable
@MainActor
final class RecentStore {
    private(set) var tracks: [Track] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func fetchHistory(client: APIClient, userId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            self.tracks = try await client.recentTracks(userId: userId)
        } catch {
            print("[RecentStore] Fetch history error: \(error)")
            self.errorMessage = "Не удалось загрузить историю: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

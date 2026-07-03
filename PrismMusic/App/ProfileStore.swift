//
//  ProfileStore.swift
//  PrismMusic
//
//  State manager for user profiles. Handles fetching profile statistics,
//  updating bio/avatar/banner, and pinning tracks.
//

import Foundation
import Observation

@Observable
@MainActor
final class ProfileStore {
    private(set) var stats: ProfileStats?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func fetchProfile(client: APIClient, userId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            self.stats = try await client.userStats(userId: userId)
        } catch {
            print("[ProfileStore] Fetch error: \(error)")
            self.errorMessage = "Не удалось загрузить данные профиля: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func updateProfile(
        client: APIClient,
        userId: String,
        avatarUrl: String? = nil,
        bannerUrl: String? = nil,
        bio: String? = nil,
        pinnedTrack: Track? = nil,
        shouldRemovePinnedTrack: Bool = false
    ) async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            _ = try await client.updateProfile(
                userId: userId,
                avatarUrl: avatarUrl,
                bannerUrl: bannerUrl,
                bio: bio,
                pinnedTrack: pinnedTrack,
                shouldRemovePinnedTrack: shouldRemovePinnedTrack
            )
            // Reload stats to keep the UI in sync
            self.stats = try await client.userStats(userId: userId)
            isLoading = false
            return true
        } catch {
            print("[ProfileStore] Update error: \(error)")
            self.errorMessage = "Ошибка сохранения: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }
}

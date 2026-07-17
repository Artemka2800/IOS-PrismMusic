//
//  CarPlaySceneDelegate.swift
//  PrismMusic
//
//  Handles the CarPlay integration lifecycle. Sets up a tabbed template
//  interface to browse SoundCloud Recommendations, Custom/Server Playlists,
//  Liked Tracks, and Recent playback history.
//

import CarPlay
import UIKit
import MediaPlayer

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPTabBarTemplateDelegate {
    private var interfaceController: CPInterfaceController?
    private var recommendationsTemplate: CPListTemplate?
    private var libraryTemplate: CPListTemplate?
    private var recentTemplate: CPListTemplate?
    private var tabBarTemplate: CPTabBarTemplate?

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        
        setupTemplates()
        fetchDataAndRefresh()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        self.tabBarTemplate = nil
        self.recommendationsTemplate = nil
        self.libraryTemplate = nil
        self.recentTemplate = nil
    }

    // MARK: - Setup UI

    private func setupTemplates() {
        // 1. Recommendations tab
        let recLoadingItem = CPListItem(text: "Загрузка рекомендаций...", detailText: nil)
        recLoadingItem.isEnabled = false
        recommendationsTemplate = CPListTemplate(title: "Рекомендации", sections: [CPListSection(items: [recLoadingItem])])
        recommendationsTemplate?.tabImage = UIImage(systemName: "sparkles")

        // 2. Library tab
        let libLoadingItem = CPListItem(text: "Загрузка медиатеки...", detailText: nil)
        libLoadingItem.isEnabled = false
        libraryTemplate = CPListTemplate(title: "Медиатека", sections: [CPListSection(items: [libLoadingItem])])
        libraryTemplate?.tabImage = UIImage(systemName: "music.note.house")

        // 3. Recent tracks tab
        let recentsLoadingItem = CPListItem(text: "Загрузка истории...", detailText: nil)
        recentsLoadingItem.isEnabled = false
        recentTemplate = CPListTemplate(title: "Недавние", sections: [CPListSection(items: [recentsLoadingItem])])
        recentTemplate?.tabImage = UIImage(systemName: "clock")

        guard let recs = recommendationsTemplate,
              let lib = libraryTemplate,
              let recents = recentTemplate else { return }

        // Assemble Tab Bar
        tabBarTemplate = CPTabBarTemplate(templates: [recs, lib, recents])
        tabBarTemplate?.delegate = self
        
        interfaceController?.setRootTemplate(tabBarTemplate!, animated: true, completion: nil)
    }

    // MARK: - Data Refresh & Observation

    private func fetchDataAndRefresh() {
        Task {
            guard let appState = AppState.shared else {
                showNoAppStatePlaceholder()
                return
            }

            // Load initial view data
            if appState.settings.isLoggedIn {
                let userId = appState.settings.userId
                async let recs: () = appState.recommendations.loadIfNeeded(client: appState.api)
                async let mixes: () = appState.recommendations.loadDailyMixesIfNeeded(client: appState.api, userId: userId)
                async let library: () = appState.library.syncWithServer()
                async let recent: () = appState.recent.fetchHistory(client: appState.api, userId: userId)
                _ = await (recs, mixes, library, recent)
            } else {
                await appState.recommendations.loadIfNeeded(client: appState.api)
            }

            updateRecommendationsSection()
            updateLibrarySection()
            updateRecentSection()
        }
    }

    private func showNoAppStatePlaceholder() {
        let errorItem = CPListItem(text: "Запустите приложение на iPhone", detailText: "Требуется инициализация")
        errorItem.isEnabled = false
        
        let section = CPListSection(items: [errorItem])
        recommendationsTemplate?.updateSections([section])
        libraryTemplate?.updateSections([section])
        recentTemplate?.updateSections([section])
    }

    // MARK: - CPTabBarTemplateDelegate

    func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        Task {
            guard let appState = AppState.shared else { return }
            
            if selectedTemplate == recommendationsTemplate {
                if appState.settings.isLoggedIn {
                    async let recs: () = appState.recommendations.refresh(client: appState.api)
                    async let mixes: () = appState.recommendations.refreshDailyMixes(client: appState.api, userId: appState.settings.userId)
                    _ = await (recs, mixes)
                } else {
                    await appState.recommendations.refresh(client: appState.api)
                }
                updateRecommendationsSection()
            } else if selectedTemplate == libraryTemplate {
                await appState.library.syncWithServer()
                updateLibrarySection()
            } else if selectedTemplate == recentTemplate {
                if appState.settings.isLoggedIn {
                    await appState.recent.fetchHistory(client: appState.api, userId: appState.settings.userId)
                }
                updateRecentSection()
            }
        }
    }

    // MARK: - Template Update Helpers

    private func updateRecommendationsSection() {
        guard let appState = AppState.shared, let recsTemplate = recommendationsTemplate else { return }

        var sections: [CPListSection] = []

        // 1. Daily Mixes
        let dailyMixes = appState.recommendations.dailyMixes
        if !dailyMixes.isEmpty {
            let items = dailyMixes.map { album in
                let item = CPListItem(text: album.title, detailText: album.artist)
                item.accessoryType = .disclosureIndicator
                
                if let coverURL = album.artworkURL {
                    Task {
                        if let image = await self.loadImage(from: coverURL) {
                            item.setImage(image)
                        }
                    }
                }
                
                item.handler = { [weak self] _, completion in
                    self?.pushAlbumTracks(album)
                    completion()
                }
                return item
            }
            sections.append(CPListSection(items: items, header: "Миксы дня", sectionIndexTitle: nil))
        }

        // 2. Playlists / Recommendations
        let recommendations = appState.recommendations.albums
        if !recommendations.isEmpty {
            let items = recommendations.map { album in
                let item = CPListItem(text: album.title, detailText: "\(album.artist) • \(album.source?.label ?? "")")
                item.accessoryType = .disclosureIndicator
                
                if let coverURL = album.artworkURL {
                    Task {
                        if let image = await self.loadImage(from: coverURL) {
                            item.setImage(image)
                        }
                    }
                }
                
                item.handler = { [weak self] _, completion in
                    self?.pushAlbumTracks(album)
                    completion()
                }
                return item
            }
            sections.append(CPListSection(items: items, header: "Рекомендованные плейлисты", sectionIndexTitle: nil))
        }

        if sections.isEmpty {
            let emptyItem = CPListItem(text: "Рекомендации не найдены", detailText: nil)
            emptyItem.isEnabled = false
            sections.append(CPListSection(items: [emptyItem]))
        }

        recsTemplate.updateSections(sections)
    }

    private func updateLibrarySection() {
        guard let appState = AppState.shared, let libTemplate = libraryTemplate else { return }

        var sections: [CPListSection] = []

        // 1. Liked Tracks quick access
        let likedCount = appState.library.likedTracks.count
        let likedItem = CPListItem(text: "Любимые треки", detailText: "\(likedCount) треков")
        likedItem.accessoryType = .disclosureIndicator
        likedItem.setImage(UIImage(systemName: "heart.fill"))
        likedItem.handler = { [weak self] _, completion in
            self?.pushLikedTracks()
            completion()
        }
        sections.append(CPListSection(items: [likedItem], header: "Медиатека", sectionIndexTitle: nil))

        // 2. User Playlists
        let playlists = appState.library.playlists
        if !playlists.isEmpty {
            let items = playlists.map { playlist in
                let item = CPListItem(text: playlist.title, detailText: playlist.artist)
                item.accessoryType = .disclosureIndicator
                
                if let coverURL = playlist.artworkURL {
                    Task {
                        if let image = await self.loadImage(from: coverURL) {
                            item.setImage(image)
                        }
                    }
                }
                
                item.handler = { [weak self] _, completion in
                    self?.pushAlbumTracks(playlist)
                    completion()
                }
                return item
            }
            sections.append(CPListSection(items: items, header: "Мои плейлисты", sectionIndexTitle: nil))
        }

        libTemplate.updateSections(sections)
    }

    private func updateRecentSection() {
        guard let appState = AppState.shared, let recsTemplate = recentTemplate else { return }

        if !appState.settings.isLoggedIn {
            let loginItem = CPListItem(text: "Требуется авторизация", detailText: "Войдите на iPhone")
            loginItem.isEnabled = false
            recsTemplate.updateSections([CPListSection(items: [loginItem])])
            return
        }

        let recentTracks = appState.recent.tracks
        if recentTracks.isEmpty {
            let emptyItem = CPListItem(text: "История пуста", detailText: "Послушайте музыку на iPhone")
            emptyItem.isEnabled = false
            recsTemplate.updateSections([CPListSection(items: [emptyItem])])
            return
        }

        let items = recentTracks.map { track in
            let item = CPListItem(text: track.title, detailText: "\(track.artist) • \(track.durationLabel)")
            
            if let coverURL = track.artworkURL {
                Task {
                    if let image = await self.loadImage(from: coverURL) {
                        item.setImage(image)
                    }
                }
            }

            item.handler = { _, completion in
                let index = recentTracks.firstIndex(of: track) ?? 0
                appState.audio.play(queue: recentTracks, startAt: index)
                completion()
            }
            return item
        }

        recsTemplate.updateSections([CPListSection(items: items, header: "История прослушиваний", sectionIndexTitle: nil)])
    }

    // MARK: - Navigation / Selection Actions

    private func pushAlbumTracks(_ album: Album) {
        guard let appState = AppState.shared else { return }

        let loadingItem = CPListItem(text: "Загрузка треков...", detailText: nil)
        loadingItem.isEnabled = false
        
        let detailTemplate = CPListTemplate(title: album.title, sections: [CPListSection(items: [loadingItem])])
        interfaceController?.pushTemplate(detailTemplate, animated: true, completion: nil)

        Task {
            do {
                let fetchedTracks = try await appState.api.playlistTracks(
                    id: album.id,
                    source: album.source?.rawValue ?? "soundcloud"
                )
                
                if fetchedTracks.isEmpty {
                    let emptyItem = CPListItem(text: "Плейлист пуст", detailText: nil)
                    emptyItem.isEnabled = false
                    detailTemplate.updateSections([CPListSection(items: [emptyItem])])
                    return
                }

                let items = fetchedTracks.map { track in
                    let item = CPListItem(text: track.title, detailText: "\(track.artist) • \(track.durationLabel)")
                    
                    if let coverURL = track.artworkURL {
                        Task {
                            if let image = await self.loadImage(from: coverURL) {
                                item.setImage(image)
                            }
                        }
                    }

                    item.handler = { _, completion in
                        let index = fetchedTracks.firstIndex(of: track) ?? 0
                        appState.audio.play(queue: fetchedTracks, startAt: index)
                        completion()
                    }
                    return item
                }
                
                detailTemplate.updateSections([CPListSection(items: items)])
            } catch {
                let errorItem = CPListItem(text: "Ошибка загрузки", detailText: error.localizedDescription)
                errorItem.isEnabled = false
                detailTemplate.updateSections([CPListSection(items: [errorItem])])
            }
        }
    }

    private func pushLikedTracks() {
        guard let appState = AppState.shared else { return }

        let likedTracks = appState.library.likedTracks
        if likedTracks.isEmpty {
            let emptyItem = CPListItem(text: "Нет любимых треков", detailText: nil)
            emptyItem.isEnabled = false
            let detailTemplate = CPListTemplate(title: "Любимые", sections: [CPListSection(items: [emptyItem])])
            interfaceController?.pushTemplate(detailTemplate, animated: true, completion: nil)
            return
        }

        let items = likedTracks.map { track in
            let item = CPListItem(text: track.title, detailText: "\(track.artist) • \(track.durationLabel)")
            
            if let coverURL = track.artworkURL {
                Task {
                    if let image = await self.loadImage(from: coverURL) {
                        item.setImage(image)
                    }
                }
            }

            item.handler = { _, completion in
                let index = likedTracks.firstIndex(of: track) ?? 0
                appState.audio.play(queue: likedTracks, startAt: index)
                completion()
            }
            return item
        }

        let detailTemplate = CPListTemplate(title: "Любимые", sections: [CPListSection(items: items)])
        interfaceController?.pushTemplate(detailTemplate, animated: true, completion: nil)
    }

    // MARK: - Artwork Asynchronous Loading

    private func loadImage(from url: URL?) async -> UIImage? {
        guard let url = url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}

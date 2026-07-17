//
//  LibraryView.swift
//  PrismMusic
//
//  Liked tracks and user custom playlists with grid presentation.
//
import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var app

    enum LibraryTab: String, CaseIterable, Identifiable {
        case favorites = "Избранное"
        case playlists = "Плейлисты"
        case artists = "Исполнители"
        case history = "История"
        var id: String { self.rawValue }
    }

    @State private var activeTab: LibraryTab = .favorites
    @State private var isShowingCreateDialog = false
    @State private var newPlaylistName = ""
    @State private var newPlaylistDescription = ""
    @State private var artistDestination: ArtistDestination?
    @State private var followedArtists: [FollowedArtistDTO] = []
    @State private var isLoadingArtists = false

    private var tracksToDisplay: [Track] {
        if !app.networkMonitor.isConnected {
            return app.library.likedTracks.filter { app.downloadStore.isDownloaded($0.id) }
        } else {
            return app.library.likedTracks
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ImmersiveBackground()
                    .ignoresSafeArea()

                if activeTab == .playlists {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            headerSection
                            pickerSection
                            playlistsSection
                        }
                        .padding(.bottom, 140)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable {
                        await app.library.syncWithServer()
                    }
                } else {
                    List {
                        Section {
                            if activeTab == .favorites {
                                favoritesListRows
                            } else if activeTab == .artists {
                                artistsListRows
                            } else {
                                historyListRows
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 16) {
                                headerSection
                                pickerSection
                            }
                            .padding(.bottom, 12)
                            .listRowInsets(EdgeInsets())
                            .textCase(nil)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .scrollIndicators(.hidden)
                    .refreshable {
                        if activeTab == .history {
                            if app.settings.isLoggedIn {
                                await app.recent.fetchHistory(client: app.api, userId: app.settings.userId)
                            }
                        } else if activeTab == .artists {
                            await fetchFollowedArtists()
                        } else {
                            await app.library.syncWithServer()
                        }
                    }
                }
            }
            .onChange(of: activeTab) { _, newValue in
                if newValue == .history && app.settings.isLoggedIn {
                    Task {
                        await app.recent.fetchHistory(client: app.api, userId: app.settings.userId)
                    }
                } else if newValue == .artists {
                    Task {
                        await fetchFollowedArtists()
                    }
                }
            }
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $artistDestination) { dest in
                ArtistView(destination: dest)
            }
            .alert("Новый плейлист", isPresented: $isShowingCreateDialog) {
                TextField("Название", text: $newPlaylistName)
                TextField("Описание (необязательно)", text: $newPlaylistDescription)
                Button("Создать") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let desc = newPlaylistDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        Task {
                            _ = await app.library.createPlaylist(name: name, description: desc)
                        }
                    }
                    newPlaylistName = ""
                    newPlaylistDescription = ""
                }
                Button("Отмена", role: .cancel) {
                    newPlaylistName = ""
                    newPlaylistDescription = ""
                }
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Медиатека")
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(.white)
                
                if activeTab == .favorites {
                    if !app.networkMonitor.isConnected {
                        Text("Скачано \(tracksToDisplay.count) треков (офлайн)")
                            .font(Theme.Typography.secondary)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    } else {
                        Text("\(app.library.likedTracks.count) понравившихся")
                            .font(Theme.Typography.secondary)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                } else if activeTab == .artists {
                    Text("\(followedArtists.count) отслеживаемых")
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Text(app.settings.isLoggedIn ? "\(app.library.playlists.count) плейлистов" : "Личные плейлизации")
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            
            Spacer()
            
            if activeTab == .playlists && app.settings.isLoggedIn {
                Button {
                    isShowingCreateDialog = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Layout.screenInset)
        .padding(.top, 56)
    }

    private var pickerSection: some View {
        HStack(spacing: 0) {
            ForEach(LibraryTab.allCases) { tab in
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(activeTab == tab ? .black : .white.opacity(0.7))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        activeTab == tab ? Color.white : Color.clear,
                        in: Capsule()
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            activeTab = tab
                        }
                    }
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.horizontal, Theme.Layout.screenInset)
    }

    @ViewBuilder
    private var favoritesListRows: some View {
        if tracksToDisplay.isEmpty {
            emptyState
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            ForEach(tracksToDisplay) { track in
                TrackRowView(
                    track: track,
                    isPlaying: app.audio.currentTrack?.id == track.id && app.audio.isPlaying,
                    onTap: {
                        if let idx = tracksToDisplay.firstIndex(of: track) {
                            app.audio.play(queue: tracksToDisplay, startAt: idx)
                        }
                    },
                    onLikeToggle: { app.library.toggleLike(track) },
                    liked: true,
                    onArtistTap: {
                        let rawId = track.id.components(separatedBy: ":").last ?? track.id
                        artistDestination = ArtistDestination(
                            id: rawId,
                            name: track.artist,
                            source: track.source ?? .soundcloud
                        )
                    }
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        app.library.toggleLike(track)
                        HapticFeedback.notification(.success)
                    } label: {
                        Label("Удалить", systemImage: "trash.fill")
                    }
                    .tint(.red)
                }
            }
        }
    }

    private var playlistsSection: some View {
        Group {
            if !app.settings.isLoggedIn {
                guestPlaylistsView
            } else if app.library.playlists.isEmpty {
                emptyPlaylistsState
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(app.library.playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(album: playlist)
                        } label: {
                            PlaylistGridCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    await app.library.deletePlaylist(playlist)
                                }
                            } label: {
                                Label("Удалить плейлист", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Layout.screenInset)
            }
        }
    }

    @ViewBuilder
    private var historyListRows: some View {
        if !app.settings.isLoggedIn {
            guestHistoryView
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else if app.recent.isLoading {
            HStack {
                Spacer()
                ProgressView()
                    .tint(.white)
                Spacer()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .padding(.top, 40)
        } else if app.recent.tracks.isEmpty {
            emptyHistoryState
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            ForEach(app.recent.tracks) { track in
                let isLiked = app.library.isLiked(track)
                TrackRowView(
                    track: track,
                    isPlaying: app.audio.currentTrack?.id == track.id && app.audio.isPlaying,
                    onTap: {
                        app.audio.play(queue: app.recent.tracks, startAt: app.recent.tracks.firstIndex(where: { $0.id == track.id }) ?? 0)
                    },
                    onLikeToggle: { app.library.toggleLike(track) },
                    liked: isLiked,
                    onArtistTap: {
                        let rawId = track.id.components(separatedBy: ":").last ?? track.id
                        artistDestination = ArtistDestination(
                            id: rawId,
                            name: track.artist,
                            source: track.source ?? .soundcloud
                        )
                    }
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        app.library.toggleLike(track)
                        HapticFeedback.notification(.success)
                    } label: {
                        Label(isLiked ? "Дизлайк" : "Лайк", systemImage: isLiked ? "heart.slash.fill" : "heart.fill")
                    }
                    .tint(isLiked ? .gray : .red)
                }
            }
        }
    }

    private var guestHistoryView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Вход не выполнен")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text("Войдите в аккаунт, чтобы сохранять историю прослушиваний и синхронизировать её.")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.top, 60)
    }

    private var emptyHistoryState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("История пуста")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text("Здесь появятся треки, которые вы воспроизводите в приложении.")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.top, 60)
    }


    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: !app.networkMonitor.isConnected ? "wifi.slash" : "heart.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(!app.networkMonitor.isConnected ? "Нет скачанных треков" : "Пока пусто")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text(!app.networkMonitor.isConnected ? "Скачайте треки в настройках, чтобы слушать их офлайн" : "Лайкни треки, и они появятся здесь")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.top, 60)
    }

    private var guestPlaylistsView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Вход не выполнен")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text("Войдите в аккаунт, чтобы создавать персональные плейлисты и синхронизировать их между вашими устройствами")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.top, 60)
    }

    private var emptyPlaylistsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Нет плейлистов")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text("У вас пока нет созданных плейлистов. Нажмите «+» вверху, чтобы создать свой первый плейлист")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.top, 60)
    }

    private var guestArtistsView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Вход не выполнен")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text("Войдите в аккаунт, чтобы отслеживать исполнителей.")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.top, 60)
    }

    private var emptyArtistsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Список пуст")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text("Здесь появятся исполнители, которых вы отслеживаете.")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.top, 60)
    }

    @ViewBuilder
    private var artistsListRows: some View {
        if !app.settings.isLoggedIn {
            guestArtistsView
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else if isLoadingArtists && followedArtists.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                    .tint(.white)
                Spacer()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .padding(.top, 40)
        } else if followedArtists.isEmpty {
            emptyArtistsState
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            ForEach(followedArtists) { artist in
                Button {
                    artistDestination = ArtistDestination(
                        id: artist.id,
                        name: artist.name,
                        source: artist.source
                    )
                } label: {
                    HStack(spacing: 14) {
                        AsyncImage(url: URL(string: artist.avatarUrl ?? "")) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Circle().fill(Color.white.opacity(0.08))
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(.white.opacity(0.4))
                                    }
                            }
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(artist.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            HStack(spacing: 4) {
                                if artist.source.hasCustomIcon {
                                    Image(artist.source.rawValue)
                                        .resizable()
                                        .renderingMode(.template)
                                        .scaledToFit()
                                        .frame(width: 10, height: 10)
                                }
                                Text(artist.source.label)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    private func fetchFollowedArtists() async {
        guard app.settings.isLoggedIn else { return }
        isLoadingArtists = true
        do {
            let fetched = try await app.api.followedArtists(userId: app.settings.userId)
            self.followedArtists = fetched
        } catch {
            print("[LibraryView] Failed to fetch followed artists: \(error)")
        }
        isLoadingArtists = false
    }
}

struct PlaylistGridCard: View {
    let playlist: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Artwork cover
            ZStack {
                AsyncImage(url: playlist.artworkURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.note.list")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
                .frame(width: (UIScreen.main.bounds.width - 48 - 16) / 2, height: (UIScreen.main.bounds.width - 48 - 16) / 2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(playlist.artist) // Displays description
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .prismGlass(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

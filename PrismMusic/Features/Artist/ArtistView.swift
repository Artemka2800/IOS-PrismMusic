//
//  ArtistView.swift
//  PrismMusic
//
//  Full-screen artist profile, matching the web `artist-view.tsx`.
//  Shows hero banner with avatar, follower count, city,
//  popular tracks list, and albums/playlists grid.
//
//  Navigation: push via `NavigationLink(value: ArtistDestination(...))`
//  from TrackRowView, NowPlayingView, SearchView.
//

import SwiftUI

/// Lightweight navigation value for artist pages.
struct ArtistDestination: Hashable {
    let id: String
    let name: String
    let source: TrackSource
}

struct ArtistView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let destination: ArtistDestination

    @State private var artistData: ArtistResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAllTracks = false
    @State private var isFollowingLocally: Bool? = nil

    var body: some View {
        ZStack {
            ArtistBackdrop(avatarURL: avatarURL)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero
                    heroBanner
                        .padding(.top, 70) // space for back button

                    if isLoading {
                        loadingState
                    } else if let errorMessage {
                        errorState(errorMessage)
                    } else if let data = artistData {
                        // Popular tracks
                        if !data.tracks.isEmpty {
                            tracksSection(data.tracks)
                                .padding(.top, 24)
                        }

                        // Albums / playlists
                        if !data.albums.isEmpty {
                            albumsSection(data.albums)
                                .padding(.top, 28)
                        }
                    }
                }
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white)
                    .contentShape(Circle())
            }
            .buttonStyle(GlassCircleButtonStyle())
            .padding(.leading, Theme.Layout.screenInset)
            .padding(.top, 52)
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Album.self) { album in
            PlaylistDetailView(album: album)
        }
        .task {
            await loadArtist()
        }
    }

    // MARK: - Computed

    private var avatarURL: URL? {
        if let urlStr = artistData?.avatarUrl, !urlStr.isEmpty {
            return URL(string: urlStr)
        }
        return nil
    }

    private var followersText: String? {
        guard let count = artistData?.followers, count > 0 else { return nil }
        if count >= 1_000_000 {
            return String(format: "%.1fM подписчиков", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK подписчиков", Double(count) / 1_000)
        }
        return "\(count) подписчиков"
    }

    private var isFollowing: Bool {
        if let local = isFollowingLocally {
            return local
        }
        let userId = app.settings.userId
        guard !userId.isEmpty else { return false }
        if let followerIds = artistData?.settings?.followerIds {
            return followerIds.contains(userId)
        }
        return false
    }

    // MARK: - Hero banner

    private var heroBanner: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                // Ambient glow
                if let url = avatarURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 28, opaque: false)
                                .opacity(0.5)
                                .scaleEffect(0.95)
                                .offset(y: 8)
                        }
                    }
                    .frame(width: 140, height: 140)
                }

                // Main avatar
                AsyncImage(url: avatarURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        fallbackAvatar
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.04))
                            .overlay {
                                ProgressView()
                                    .tint(Theme.Palette.textTertiary)
                            }
                    }
                }
                .frame(width: 140, height: 140)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
            }

            // Name
            Text(destination.name)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .tracking(-0.3)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Metadata row
            HStack(spacing: 12) {
                // Source badge
                HStack(spacing: 4) {
                    if destination.source.hasCustomIcon {
                        Image(destination.source.rawValue)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                    }
                    Text(destination.source.label)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.Palette.textSecondary)

                if let city = artistData?.city, !city.isEmpty {
                    Text("·")
                        .foregroundStyle(Theme.Palette.textTertiary)
                    HStack(spacing: 3) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10))
                        Text(city)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.Palette.textSecondary)
                }

                if let followers = followersText {
                    Text("·")
                        .foregroundStyle(Theme.Palette.textTertiary)
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                        Text(followers)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.Palette.textSecondary)
                }
            }

            // Buttons row
            if let data = artistData {
                HStack(spacing: 12) {
                    if !data.tracks.isEmpty {
                        Button {
                            app.audio.play(queue: data.tracks, startAt: 0)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Слушать")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(PlayButtonStyle())
                    }
                    
                    if app.settings.isLoggedIn {
                        Button {
                            Task {
                                await toggleFollow()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isFollowing ? "checkmark" : "plus")
                                    .font(.system(size: 13, weight: .bold))
                                Text(isFollowing ? "Отслеживается" : "Отслеживать")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(isFollowing ? Color.white.opacity(0.15) : app.accentColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var fallbackAvatar: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "person.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Tracks section

    private func tracksSection(_ tracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Популярные треки")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if tracks.count > 5 {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showAllTracks.toggle()
                        }
                    } label: {
                        Text(showAllTracks ? "Свернуть" : "Все")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Layout.screenInset)

            let displayTracks = showAllTracks ? tracks : Array(tracks.prefix(5))

            LazyVStack(spacing: 0) {
                ForEach(displayTracks) { track in
                    TrackRowView(
                        track: track,
                        isPlaying: app.audio.currentTrack?.id == track.id && app.audio.isPlaying,
                        onTap: {
                            if let idx = tracks.firstIndex(of: track) {
                                app.audio.play(queue: tracks, startAt: idx)
                            }
                        },
                        onLikeToggle: { app.library.toggleLike(track) },
                        liked: app.library.isLiked(track)
                    )
                }
            }
            .padding(.horizontal, Theme.Layout.screenInset)
        }
    }

    // MARK: - Albums section

    private func albumsSection(_ dtos: [ArtistAlbumDTO]) -> some View {
        let albums = dtos.map { $0.toAlbum }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Альбомы и плейлисты")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Layout.screenInset)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ],
                spacing: 18
            ) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        VStack(alignment: .leading, spacing: 8) {
                            AsyncImage(url: album.artworkURL) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else if phase.error != nil {
                                    albumFallbackCover
                                } else {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.04))
                                        .overlay {
                                            ProgressView()
                                                .tint(Theme.Palette.textTertiary)
                                        }
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(album.artist)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Palette.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Layout.screenInset)
        }
    }

    private var albumFallbackCover: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Загружаем данные артиста...")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.top, 40)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
            Button("Повторить") {
                Task { await loadArtist() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
        }
        .padding(28)
        .padding(.top, 24)
    }

    // MARK: - Loading

    private func loadArtist() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await app.api.artist(
                id: destination.id,
                source: destination.source.rawValue,
                userId: app.settings.userId
            )
            self.artistData = response
            self.isFollowingLocally = nil
        } catch {
            self.errorMessage = "Не удалось загрузить информацию об артисте"
            print("[ArtistView] Error: \(error)")
        }
        isLoading = false
    }

    private func toggleFollow() async {
        let userId = app.settings.userId
        guard !userId.isEmpty else { return }
        guard let data = artistData else { return }
        
        let currentStatus = isFollowing
        isFollowingLocally = !currentStatus
        
        do {
            let res = try await app.api.toggleFollowArtist(
                userId: userId,
                artistId: data.id,
                source: destination.source.rawValue,
                name: data.name,
                avatarUrl: data.avatarUrl
            )
            isFollowingLocally = res.isFollowing
            
            // Background reload to update UI state
            let response = try await app.api.artist(
                id: destination.id,
                source: destination.source.rawValue,
                userId: userId
            )
            self.artistData = response
            self.isFollowingLocally = nil
        } catch {
            isFollowingLocally = currentStatus
            print("[ArtistView] Toggle follow failed: \(error)")
        }
    }
}

// MARK: - Backdrop

private struct ArtistBackdrop: View {
    let avatarURL: URL?

    var body: some View {
        ZStack {
            Theme.Palette.background

            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 60, opaque: true)
                            .opacity(0.35)
                            .scaleEffect(1.2)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
            }

            LinearGradient(
                colors: [.black.opacity(0.35), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

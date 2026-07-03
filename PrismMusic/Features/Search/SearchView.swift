//
//  SearchView.swift
//  PrismMusic
//
//  Debounced search across all sources (Yandex + SoundCloud). Empty state
//  shows suggestions; results render as a flat list of tracks plus a
//  compact horizontal carousel of playlist cards when present.
//

import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var app
    @Binding var pendingArtistDestination: ArtistDestination?
    @State private var query: String = ""
    @State private var artistDestination: ArtistDestination?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                ImmersiveBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    searchField

                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.top, 4)

                    if !app.networkMonitor.isConnected {
                        offlinePlaceholder
                    } else {
                        content
                    }
                }
            }
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Album.self) { album in
                PlaylistDetailView(album: album)
            }
            .navigationDestination(for: ArtistDestination.self) { dest in
                ArtistView(destination: dest)
            }
            .navigationDestination(item: $artistDestination) { dest in
                ArtistView(destination: dest)
            }
            .onChange(of: pendingArtistDestination) { _, dest in
                if let dest {
                    artistDestination = dest
                    pendingArtistDestination = nil
                }
            }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)

            TextField("Поиск треков, альбомов, артистов", text: $query)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .submitLabel(.search)
                .foregroundStyle(.white)
                .tint(.white)
                .onChange(of: query) { _, newValue in
                    app.search.update(query: newValue, client: app.api)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    app.search.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .prismGlassCapsule()
        .overlay(
            Capsule()
                .stroke(fieldFocused ? Color.white.opacity(0.24) : Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .animation(.easeOut(duration: 0.15), value: fieldFocused)
        .padding(.horizontal, Theme.Layout.screenInset)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        switch app.search.state {
        case .idle:
            idleState
        case .searching:
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Ищем «\(app.search.query)»...")
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .results(let tracks, let albums):
            if tracks.isEmpty && albums.isEmpty {
                emptyState
            } else {
                resultsList(tracks: tracks, albums: albums)
            }

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var idleState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Найди свои треки")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text("Поиск работает по Я.Музыке, SoundCloud и Spotify")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Ничего не найдено по запросу «\(app.search.query)»")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultsList(tracks: [Track], albums: [Album]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !albums.isEmpty {
                    Text("Плейлисты")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.horizontal, Theme.Layout.screenInset)
                        .padding(.top, 8)

                    // Compact horizontal scroll — small cards (100pt wide)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(albums) { album in
                                searchPlaylistCard(album)
                            }
                        }
                        .padding(.horizontal, Theme.Layout.screenInset)
                    }
                    .frame(height: 140)
                }

                if !tracks.isEmpty {
                    Text("Треки")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.horizontal, Theme.Layout.screenInset)
                        .padding(.top, albums.isEmpty ? 8 : 4)

                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { track in
                            TrackRowView(
                                track: track,
                                isPlaying: app.audio.currentTrack?.id == track.id && app.audio.isPlaying,
                                onTap: {
                                    if let idx = tracks.firstIndex(of: track) {
                                        app.audio.play(queue: tracks, startAt: idx)
                                    }
                                },
                                onLikeToggle: { app.library.toggleLike(track) },
                                liked: app.library.isLiked(track),
                                onArtistTap: {
                                    // Navigate to artist — use track's raw ID (strip source prefix)
                                    let rawId = track.id.components(separatedBy: ":").last ?? track.id
                                    artistDestination = ArtistDestination(
                                        id: rawId,
                                        name: track.artist,
                                        source: track.source ?? .soundcloud
                                    )
                                }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
    }

    private func searchPlaylistCard(_ album: Album) -> some View {
        NavigationLink(value: album) {
            VStack(alignment: .leading, spacing: 6) {
                // Small square cover (100pt)
                AsyncImage(url: album.artworkURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.white.opacity(0.04)
                            Image(systemName: "music.note")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .clipped()

                Text(album.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .leading)
                    .multilineTextAlignment(.leading)

                Text(album.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var offlinePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Поиск недоступен")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text("Подключись к интернету, чтобы искать музыку на Яндекс.Музыке, SoundCloud и Spotify")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

//
//  PlaylistDetailView.swift
//  PrismMusic
//
//  Detailed view for playlists and albums.
//  Fetches tracklist dynamically from the backend client on load.
//

import SwiftUI

struct PlaylistDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let album: Album

    @State private var tracks: [Track] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    @State private var playlistTitle: String = ""
    @State private var playlistDescription: String = ""
    @State private var playlistCoverURL: URL? = nil
    @State private var isShowingEditSheet = false
    @State private var artistDestination: ArtistDestination?

    init(album: Album) {
        self.album = album
        _playlistTitle = State(initialValue: album.title)
        _playlistDescription = State(initialValue: album.artist)
        _playlistCoverURL = State(initialValue: album.artworkURL)
    }

    var body: some View {
        ZStack {
            // Immersive background matching NowPlayingView style
            Backdrop(coverURL: playlistCoverURL)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header / cover detail
                    header
                        .padding(.top, 70) // space for back button

                    // Controls (Play All)
                    if !tracks.isEmpty {
                        controlsSection
                            .padding(.top, 24)
                    }

                    // Tracks list
                    Group {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.large)
                                .padding(.top, 40)
                        } else if let errorMessage {
                            errorView(errorMessage)
                        } else if tracks.isEmpty {
                            emptyState
                        } else {
                            tracksList
                        }
                    }
                    .padding(.top, 24)
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
        .overlay(alignment: .topTrailing) {
            if album.source == .other {
                Button {
                    isShowingEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.white)
                        .contentShape(Circle())
                }
                .buttonStyle(GlassCircleButtonStyle())
                .padding(.trailing, Theme.Layout.screenInset)
                .padding(.top, 52)
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $artistDestination) { dest in
            ArtistView(destination: dest)
        }
        .task {
            await loadTracks()
        }
        .sheet(isPresented: $isShowingEditSheet) {
            PlaylistEditView(playlist: album) { updatedAlbum in
                playlistTitle = updatedAlbum.title
                playlistDescription = updatedAlbum.artist
                playlistCoverURL = updatedAlbum.artworkURL
            } onDelete: {
                dismiss()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 20) {
            // Album cover image with ambient glow
            ZStack {
                AsyncImage(url: playlistCoverURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 28, opaque: false)
                            .opacity(0.55)
                            .scaleEffect(0.95)
                            .offset(y: 10)
                    }
                }
                .frame(width: 180, height: 180)
                
                AsyncImage(url: playlistCoverURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else if phase.error != nil {
                        fallbackCover
                    } else {
                        Rectangle()
                            .fill(Color.white.opacity(0.04))
                            .overlay {
                                ProgressView()
                                    .tint(Theme.Palette.textTertiary)
                            }
                    }
                }
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
            }

            VStack(spacing: 6) {
                Text(playlistTitle)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .tracking(-0.3)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                HStack(spacing: 8) {
                    Text(playlistDescription)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
    }

    private var fallbackCover: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(width: 180, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var controlsSection: some View {
        Button {
            app.audio.play(queue: tracks, startAt: 0)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("Слушать")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 36)
            .padding(.vertical, 13)
        }
        .buttonStyle(PlayButtonStyle())
    }

    private var tracksList: some View {
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
                    onRemoveTrack: album.source == .other ? {
                        Task {
                            await app.library.removeTrack(track, from: album)
                            withAnimation {
                                self.tracks.removeAll { $0.id == track.id }
                            }
                        }
                    } : nil,
                    onArtistTap: {
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
        .padding(.horizontal, Theme.Layout.screenInset)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Нет треков")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.top, 40)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("Повторить") {
                Task { await loadTracks() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
        }
        .padding(28)
    }

    private func loadTracks() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await app.api.playlistTracks(
                id: album.id,
                source: album.source?.rawValue ?? "soundcloud"
            )
            self.tracks = fetched
        } catch {
            self.errorMessage = "Не удалось загрузить треки"
            print("[PlaylistDetail] Error loading tracks: \(error)")
        }
        isLoading = false
    }
}

private struct Backdrop: View {
    let coverURL: URL?

    var body: some View {
        ZStack {
            Theme.Palette.background

            if let coverURL {
                AsyncImage(url: coverURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 60, opaque: true)
                            .opacity(0.4)
                            .scaleEffect(1.2)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
            }

            LinearGradient(
                colors: [.black.opacity(0.45), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct PlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.85 : 1.0))
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .shadow(color: .white.opacity(configuration.isPressed ? 0.08 : 0.15), radius: 12, y: 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

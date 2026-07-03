//
//  TrackRowView.swift
//  PrismMusic
//
//  Reusable horizontal row that displays a track with cover, title, artist,
//  source badge and an optional trailing action (typically the like button).
//  Used in Home, Search, and Library lists so the visual language stays
//  consistent.
//

import SwiftUI

struct TrackRowView: View {
    @Environment(AppState.self) private var app
    let track: Track
    let isPlaying: Bool
    var onTap: () -> Void
    var onLikeToggle: (() -> Void)?
    var liked: Bool = false
    var onRemoveTrack: (() -> Void)? = nil
    var onArtistTap: (() -> Void)? = nil

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AsyncImage(url: track.artworkURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .shimmering()
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .overlay(alignment: .center) {
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                            .padding(6)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isPlaying ? Color.white : Theme.Palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let onArtistTap {
                            Button {
                                onArtistTap()
                            } label: {
                                Text(track.artist)
                                    .lineLimit(1)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(track.artist)
                                .lineLimit(1)
                        }

                        if let source = track.source {
                            Text("·")
                            if source.hasCustomIcon {
                                Image(source.rawValue)
                                    .resizable()
                                    .renderingMode(.template)
                                    .scaledToFit()
                                    .frame(width: 11, height: 11)
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            } else {
                                Image(systemName: "music.note")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                }

                Spacer()

                if let onLikeToggle {
                    Button(action: onLikeToggle) {
                        Image(systemName: liked ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(liked ? Color.white : Theme.Palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .contentTransition(.symbolEffect(.replace))
                }

                Text(track.durationLabel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(TrackRowButtonStyle())
        .contextMenu {
            if app.networkMonitor.isConnected {
                if track.source == .yandex {
                    Button {
                        Task {
                            await app.findAndReplace(track: track, targetSource: .spotify)
                        }
                    } label: {
                        Label("Найти на Spotify", systemImage: "magnifyingglass")
                    }
                } else if track.source == .spotify {
                    Button {
                        Task {
                            await app.findAndReplace(track: track, targetSource: .yandex)
                        }
                    } label: {
                        Label("Найти в Яндекс.Музыке", systemImage: "magnifyingglass")
                    }
                } else if track.source == .soundcloud {
                    Button {
                        Task {
                            await app.findAndReplace(track: track, targetSource: .spotify)
                        }
                    } label: {
                        Label("Найти на Spotify", systemImage: "magnifyingglass")
                    }
                    Button {
                        Task {
                            await app.findAndReplace(track: track, targetSource: .yandex)
                        }
                    } label: {
                        Label("Найти в Яндекс.Музыке", systemImage: "magnifyingglass")
                    }
                }
            }
            
            if let onLikeToggle {
                Button {
                    onLikeToggle()
                } label: {
                    Label(
                        liked ? "Удалить из любимых" : "В любимые",
                        systemImage: liked ? "heart.fill" : "heart"
                    )
                }
            }
            
            if app.settings.isLoggedIn && !app.library.playlists.isEmpty {
                Menu("Добавить в плейлист") {
                    ForEach(app.library.playlists) { playlist in
                        Button(playlist.title) {
                            Task {
                                await app.library.addTrack(track, to: playlist)
                            }
                        }
                    }
                }
            }

            if let onRemoveTrack {
                Button(role: .destructive) {
                    onRemoveTrack()
                } label: {
                    Label("Удалить из плейлиста", systemImage: "trash")
                }
            }

            if let onArtistTap {
                Divider()
                Button {
                    onArtistTap()
                } label: {
                    Label("Перейти к артисту", systemImage: "person.crop.circle")
                }
            }
        }
    }
}

struct TrackRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.07 : 0.0))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

//
//  ProfileView.swift
//  PrismMusic
//
//  Full-screen user profile that mirrors the Next.js web `profile-view.tsx` design.
//  Includes:
//   - Parallax/Blur banner matching preset gradients or custom URLs
//   - Stat summary cards (Tracks, Likes, Playlists)
//   - Achievements / Badges catalog (illuminated if unlocked, locked with progress bar if countable)
//   - Top Artists list with counts
//   - Pinned "Favorite Track" card with rotating vinyl record player (animates when track is playing!)
//   - Recently Played history list (tap to play, tap artist to navigate)
//   - Profile Editor sheet with base64/custom avatar, banner preset selectors, bio, and track pin search.
//

import SwiftUI
import PhotosUI

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let userId: String
    let isOwnProfile: Bool

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showEditSheet = false
    
    // Rotating vinyl animation state
    @State private var rotationDegrees = 0.0
    private let timer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    init(userId: String) {
        self.userId = userId
        // If it matches logged-in user, it's own profile
        self.isOwnProfile = true // Handled dynamically in view from app.settings
    }

    var body: some View {
        ZStack {
            Theme.Palette.background
                .ignoresSafeArea()

            if let stats = app.profile.stats {
                ScrollView {
                    VStack(spacing: 0) {
                        // Banner with parallax-ish stretch
                        profileBanner(stats)
                        
                        VStack(spacing: Theme.Layout.sectionSpacing) {
                            // Bio if present
                            if let bio = stats.bio, !bio.isEmpty {
                                bioCard(bio)
                            }
                            
                            // Stats grid
                            statsSection(stats)

                            // Pinned Favorite Track
                            pinnedTrackSection(stats)
                            
                            // Recently played list
                            if let history = stats.recentHistory, !history.isEmpty {
                                recentHistorySection(history)
                            }

                            // Badges list
                            badgesSection(stats)
                            
                            // Top Artists
                            if let topArtists = stats.topArtists, !topArtists.isEmpty {
                                topArtistsSection(topArtists)
                            }
                            
                            // Comments section (profile wall)
                            commentsSection(stats)
                            
                            // Account actions if own profile (Logout, Sync, checkout)
                            if stats.id == app.settings.userId {
                                accountActionsSection
                            }
                        }
                        .padding(.horizontal, Theme.Layout.screenInset)
                        .padding(.top, 20)
                        .padding(.bottom, 140)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .scrollIndicators(.hidden)
                .refreshable {
                    await app.profile.fetchProfile(client: app.api, userId: userId)
                }
            } else if app.profile.isLoading {
                ProgressView("Загрузка профиля...")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if let error = app.profile.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Button("Повторить") {
                        Task {
                            await app.profile.fetchProfile(client: app.api, userId: userId)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                }
                .padding()
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showEditSheet) {
            EditProfileSheet(stats: app.profile.stats)
        }
        .task {
            await app.profile.fetchProfile(client: app.api, userId: userId)
        }
    }

    // MARK: - Media URL Resolver

    private func resolveMediaURL(_ pathOrUrl: String?) -> URL? {
        guard let str = pathOrUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty else { return nil }
        if str.starts(with: "http://") || str.starts(with: "https://") {
            return URL(string: str)
        }
        let stored = UserDefaults.standard.string(forKey: "prism.backendURL") ?? ""
        let backend = stored.isEmpty ? "https://prism-music-virid.vercel.app" : stored
        var cleanBackend = backend.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanBackend.hasSuffix("/") {
            cleanBackend.removeLast()
        }
        let cleanPath = str.starts(with: "/") ? str : "/\(str)"
        return URL(string: "\(cleanBackend)\(cleanPath)")
    }

    // MARK: - Banner Header
    
    private func profileBanner(_ stats: ProfileStats) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Background preset or custom banner image
            bannerBackground(stats.bannerUrl)
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipped()
            
            // Mask gradient
            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.35), Theme.Palette.background],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // User Meta Info overlay firmly anchored at the bottom of the banner
            HStack(alignment: .bottom, spacing: 14) {
                // Avatar image
                ZStack {
                    if let url = resolveMediaURL(stats.avatarUrl) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .frame(width: 74, height: 74)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 2))
                .shadow(radius: 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(stats.username)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        if let role = stats.role, role != "user" {
                            Text(role.uppercased())
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(role == "admin" ? Color.red : Color.yellow)
                                .cornerRadius(6)
                        }
                    }
                    
                    Text("С нами с \(formattedDate(stats.memberSince))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                
                Spacer()
                
                // Actions: Edit / Share
                HStack(spacing: 8) {
                    if stats.id == app.settings.userId {
                        Button {
                            showEditSheet = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 38, height: 38)
                                .background(.white.opacity(0.15), in: Circle())
                        }
                    }
                    
                    Button {
                        let url = "https://pm.standrise.net/user-profile/\(stats.id)"
                        UIPasteboard.general.string = url
                        app.audio.errorMessage = "Ссылка скопирована!"
                        app.audio.showError = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                }
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Layout.screenInset)
            .padding(.bottom, 16)
        }
        .frame(height: 240)
    }
    
    @ViewBuilder
    private func bannerBackground(_ bannerUrl: String?) -> some View {
        if let url = resolveMediaURL(bannerUrl) {
            ZStack {
                // Ambient blur backdrop
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 20)
                            .opacity(0.6)
                            .scaleEffect(1.15)
                    }
                }
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(red: 0.12, green: 0.12, blue: 0.15)
                    }
                }
            }
        } else {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.18, blue: 0.25), Color(red: 0.08, green: 0.08, blue: 0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // MARK: - Subcomponents
    
    private func bioCard(_ bio: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("О СЕБЕ")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
            
            Text(bio)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineSpacing(4)
        }
        .padding(Theme.Layout.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .prismGlass(cornerRadius: Theme.Layout.cornerLarge)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerLarge)
                .stroke(Theme.Palette.border, lineWidth: 0.5)
        )
    }

    private func statsSection(_ stats: ProfileStats) -> some View {
        HStack(spacing: 12) {
            statItem(value: "\(stats.tracksListened)", label: "Слушал")
            statItem(value: "\(stats.likedTracks)", label: "Любимые")
            statItem(value: "\(stats.playlistCount)", label: "Плейлисты")
        }
    }
    
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .prismGlass(cornerRadius: Theme.Layout.cornerMedium)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerMedium)
                .stroke(Theme.Palette.border, lineWidth: 0.5)
        )
    }
    
    // MARK: - Pinned Track Card
    
    private func pinnedTrackSection(_ stats: ProfileStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ЛЮБИМЫЙ ТРЕК")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
            
            if let track = stats.pinnedTrack {
                let isCurrent = app.audio.currentTrack?.id == track.id
                let isPlaying = isCurrent && app.audio.isPlaying
                
                HStack(spacing: 16) {
                    // Pinned track cover with spinning Vinyl record!
                    ZStack {
                        // Vinyl Record
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            // Grooves
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                .padding(6)
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                .padding(14)
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                .padding(24)
                            
                            // Mini label
                            if let coverURL = track.artworkURL {
                                AsyncImage(url: coverURL) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Circle().fill(Color.white.opacity(0.04))
                                    }
                                }
                                .frame(width: 22, height: 22)
                                .clipShape(Circle())
                            }
                            
                            // Center hole
                            Circle()
                                .fill(Color.black)
                                .frame(width: 4, height: 4)
                        }
                        .frame(width: 58, height: 58)
                        .offset(x: isCurrent ? 28 : 0)
                        .rotationEffect(.degrees(rotationDegrees))
                        .animation(isCurrent ? .none : .spring(), value: isCurrent)
                        
                        // Album Sleeve cover art
                        Button {
                            app.audio.play(queue: [track], startAt: 0)
                        } label: {
                            ZStack {
                                AsyncImage(url: track.artworkURL) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.white.opacity(0.05))
                                            .overlay(Image(systemName: "music.note"))
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                
                                // Overlay play/pause
                                Color.black.opacity(0.25)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 60, height: 60)
                        }
                        .buttonStyle(.plain)
                        .shadow(radius: 6)
                    }
                    .frame(width: 88, height: 60, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        // Tap artist name to navigate to ArtistView
                        NavigationLink(value: ArtistDestination(id: track.id.components(separatedBy: ":").last ?? track.id, name: track.artist, source: track.source ?? .soundcloud)) {
                            Text(track.artist)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .lineLimit(1)
                                .underline(color: .clear)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    if isCurrent && app.audio.isPlaying {
                        // Soundwave indicator
                        HStack(spacing: 2) {
                            ForEach(0..<4) { idx in
                                Capsule()
                                    .fill(Color.emerald)
                                    .frame(width: 2.5)
                                    .shimmering() // visually pulsing
                            }
                        }
                        .frame(height: 12)
                    }
                }
                .padding(Theme.Layout.cardInset)
                .prismGlass(cornerRadius: Theme.Layout.cornerLarge)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.cornerLarge)
                        .stroke(Theme.Palette.border, lineWidth: 0.5)
                )
                .onReceive(timer) { _ in
                    if isPlaying {
                        rotationDegrees += 2.5
                        if rotationDegrees >= 360 {
                            rotationDegrees = 0
                        }
                    }
                }
            } else {
                // Empty fallback
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.Palette.textTertiary)
                        Text(stats.id == app.settings.userId ? "Вы не выбрали любимый трек" : "Любимый трек не выбран")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 24)
                .prismGlass(cornerRadius: Theme.Layout.cornerLarge)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.cornerLarge)
                        .stroke(Theme.Palette.border, lineWidth: 0.5)
                )
            }
        }
    }
    
    // MARK: - Recent History
    
    private func recentHistorySection(_ history: [RecentHistoryItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("НЕДАВНО СЛУШАЛ")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
            
            VStack(spacing: 0) {
                let displayHistory = Array(history.prefix(5))
                ForEach(displayHistory, id: \.playedAt) { item in
                    let track = item.track
                    let isPlaying = app.audio.currentTrack?.id == track.id && app.audio.isPlaying
                    
                    HStack(spacing: 12) {
                        // Mini cover
                        Button {
                            app.audio.play(queue: displayHistory.map { $0.track }, startAt: displayHistory.firstIndex(where: { $0.track.id == track.id }) ?? 0)
                        } label: {
                            ZStack {
                                AsyncImage(url: track.artworkURL) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.white.opacity(0.04))
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                
                                Color.black.opacity(0.15)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 38, height: 38)
                        }
                        .buttonStyle(.plain)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isPlaying ? Color.emerald : .white)
                                .lineLimit(1)
                            
                            NavigationLink(value: ArtistDestination(id: track.id.components(separatedBy: ":").last ?? track.id, name: track.artist, source: track.source ?? .soundcloud)) {
                                Text(track.artist)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Palette.textSecondary)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Spacer()
                        
                        // Played time label (extract HH:MM from ISO string)
                        Text(formatTimeString(item.playedAt))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .padding(.vertical, 8)
                    
                    if item.playedAt != displayHistory.last?.playedAt {
                        Divider()
                            .background(Color.white.opacity(0.06))
                    }
                }
            }
            .padding(Theme.Layout.cardInset)
            .prismGlass(cornerRadius: Theme.Layout.cornerLarge)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cornerLarge)
                    .stroke(Theme.Palette.border, lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Achievements / Badges Section
    
    private func badgesSection(_ stats: ProfileStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ДОСТИЖЕНИЯ И ЗНАЧКИ")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                Text("\(stats.unlockedBadges.count)/\(badgeCatalog.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            
            VStack(spacing: 8) {
                ForEach(badgeCatalog) { badge in
                    let unlocked = stats.unlockedBadges.contains(badge.id)
                    let progress = stats.badgeProgress?[badge.id]
                    
                    HStack(spacing: 12) {
                        // Badge Icon Box
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(unlocked ? LinearGradient(colors: badge.bgColors, startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.01)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(unlocked ? badge.color.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 0.5)
                                )
                            
                            if unlocked {
                                Image(systemName: badge.iconName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(badge.color)
                            } else {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                        .frame(width: 38, height: 38)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(badge.label)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(unlocked ? .white : Theme.Palette.textSecondary)
                                
                                if badge.id == "prism_plus" {
                                    Text("PLUS")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.yellow)
                                        .cornerRadius(3)
                                }
                            }
                            
                            Text(badge.description)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Palette.textTertiary)
                                .lineLimit(1)
                            
                            // locked count progress bar
                            if !unlocked && badge.id != "prism_plus", let progress {
                                HStack(spacing: 6) {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.white.opacity(0.06))
                                            Capsule()
                                                .fill(Color.emerald.opacity(0.55))
                                                .frame(width: geo.size.width * CGFloat(progress.current) / CGFloat(progress.target))
                                        }
                                    }
                                    .frame(height: 3)
                                    
                                    Text("\(progress.current)/\(progress.target)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(Theme.Palette.textTertiary)
                                }
                                .padding(.top, 2)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(8)
                    .background(unlocked ? Color.white.opacity(0.02) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(Theme.Layout.cardInset)
            .prismGlass(cornerRadius: Theme.Layout.cornerLarge)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cornerLarge)
                    .stroke(Theme.Palette.border, lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Top Artists Section
    
    private func topArtistsSection(_ artists: [TopArtistItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ПОПУЛЯРНЫЕ ИСПОЛНИТЕЛИ")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
            
            VStack(spacing: 8) {
                ForEach(0..<artists.count, id: \.self) { idx in
                    let artist = artists[idx]
                    HStack(spacing: 12) {
                        // Index badge
                        Text("\(idx + 1)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.emerald)
                            .frame(width: 24, height: 24)
                            .background(Color.emerald.opacity(0.12), in: Circle())
                        
                        VStack(alignment: .leading, spacing: 2) {
                            // Tap to open artist view
                            NavigationLink(value: ArtistDestination(id: artist.name, name: artist.name, source: .soundcloud)) {
                                Text(artist.name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .underline(color: .clear)
                            }
                            .buttonStyle(.plain)
                            
                            Text("Прослушан \(artist.count) раз(а)")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(Theme.Layout.cardInset)
            .prismGlass(cornerRadius: Theme.Layout.cornerLarge)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cornerLarge)
                    .stroke(Theme.Palette.border, lineWidth: 0.5)
            )
        }
    }
    
    private func commentsSection(_ stats: ProfileStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("СТЕНА И КОММЕНТАРИИ")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
            
            CommentsView(
                kind: .profile,
                targetId: stats.id,
                profileOwnerId: stats.id,
                variant: .card
            )
            .padding(Theme.Layout.cardInset)
            .prismGlass(cornerRadius: Theme.Layout.cornerLarge)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cornerLarge)
                    .stroke(Theme.Palette.border, lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Account Management actions
    
    private var accountActionsSection: some View {
        VStack(spacing: 12) {
            // Sync status
            Button {
                Task {
                    await app.library.syncWithServer()
                    app.audio.errorMessage = "Синхронизация завершена!"
                    app.audio.showError = true
                }
            } label: {
                HStack {
                    Label("Синхронизировать медиатеку", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            
            // Sign Out
            Button(role: .destructive) {
                withAnimation {
                    app.settings.logout()
                }
            } label: {
                HStack {
                    Spacer()
                    Label("Выйти из аккаунта", systemImage: "arrow.left.circle")
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(12)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.2), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Helpers
    
    private func formattedDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateStr) {
            let outFormatter = DateFormatter()
            outFormatter.locale = Locale(identifier: "ru_RU")
            outFormatter.dateFormat = "MMMM yyyy"
            return outFormatter.string(from: date)
        }
        return "недавно"
    }

    private func formatTimeString(_ dateStr: String) -> String {
        // Parse "2026-07-03T12:00:00Z" -> "12:00"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateStr) {
            let outFormatter = DateFormatter()
            outFormatter.dateFormat = "HH:mm"
            return outFormatter.string(from: date)
        }
        return "—:—"
    }
}

// MARK: - Profile Editor sheet

struct EditProfileSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let stats: ProfileStats?
    
    @State private var bioDraft: String = ""
    @State private var avatarUrlDraft: String = ""
    @State private var bannerUrlDraft: String = ""
    
    @State private var isPinSearchPresented = false
    @State private var selectedPinnedTrack: Track?
    @State private var shouldRemovePinnedTrack = false
    @State private var isSaving = false
    
    // PhotosPicker Items
    @State private var avatarItem: PhotosPickerItem? = nil
    @State private var bannerItem: PhotosPickerItem? = nil
    
    // Drag and Drop hover states
    @State private var isAvatarHovered = false
    @State private var isBannerHovered = false

    init(stats: ProfileStats?) {
        self.stats = stats
        _bioDraft = State(initialValue: stats?.bio ?? "")
        _avatarUrlDraft = State(initialValue: stats?.avatarUrl ?? "")
        _bannerUrlDraft = State(initialValue: stats?.bannerUrl ?? "")
        _selectedPinnedTrack = State(initialValue: stats?.pinnedTrack)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background
                    .ignoresSafeArea()
                
                Form {
                    Section("О БО МНЕ") {
                        TextField("Пару слов о себе...", text: $bioDraft)
                            .foregroundStyle(.white)
                            .onChange(of: bioDraft) { _, newValue in
                                if newValue.count > 120 {
                                    bioDraft = String(newValue.prefix(120))
                                }
                            }
                        
                        Text("\(bioDraft.count)/120 символов")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    
                    Section("АВАТАРКА") {
                        avatarUploadView
                        
                        TextField("Ссылка на изображение", text: $avatarUrlDraft)
                            .textInputAutocapitalization(.none)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                            .font(.system(size: 13))
                    }
                    
                    Section("ОБЛОЖКА ПРОФИЛЯ") {
                        bannerUploadView
                        
                        TextField("Ссылка на фоновое изображение", text: $bannerUrlDraft)
                            .textInputAutocapitalization(.none)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                            .font(.system(size: 13))
                    }
                    
                    Section("ЗАКРЕПЛЕННЫЙ ТРЕК") {
                        if shouldRemovePinnedTrack {
                            Text("Любимый трек будет убран")
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                        } else if let track = selectedPinnedTrack {
                            HStack(spacing: 12) {
                                AsyncImage(url: track.artworkURL) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.white.opacity(0.04))
                                    }
                                }
                                .frame(width: 46, height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(track.artist)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.Palette.textSecondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                            .padding(.vertical, 4)
                        } else {
                            Text("Не выбрано")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        
                        HStack(spacing: 12) {
                            Button("Выбрать трек...") {
                                isPinSearchPresented = true
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .foregroundStyle(.white)
                            
                            if selectedPinnedTrack != nil && !shouldRemovePinnedTrack {
                                Button("Убрать", role: .destructive) {
                                    shouldRemovePinnedTrack = true
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            } else if shouldRemovePinnedTrack {
                                Button("Вернуть") {
                                    shouldRemovePinnedTrack = false
                                }
                                .buttonStyle(.bordered)
                                .tint(.gray)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle("Настройка профиля")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "..." : "Готово") {
                        saveProfile()
                    }
                    .disabled(isSaving)
                    .foregroundStyle(.white)
                    .fontWeight(.bold)
                }
            }
            .sheet(isPresented: $isPinSearchPresented) {
                PinnedTrackSearchSheet { track in
                    selectedPinnedTrack = track
                    shouldRemovePinnedTrack = false
                }
            }
            .onChange(of: avatarItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        let base64 = data.base64EncodedString()
                        avatarUrlDraft = "data:image/jpeg;base64,\(base64)"
                    }
                }
            }
            .onChange(of: bannerItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        let base64 = data.base64EncodedString()
                        bannerUrlDraft = "data:image/jpeg;base64,\(base64)"
                    }
                }
            }
        }
    }
    
    // Custom drop-zone and picker for Avatar
    private var avatarUploadView: some View {
        VStack(spacing: 12) {
            ZStack {
                previewImage(urlStr: avatarUrlDraft)
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                
                if isAvatarHovered {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .overlay(
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                        )
                }
            }
            .frame(width: 96, height: 96)
            .shadow(radius: 4)
            .onDrop(of: [.image, .fileURL], isTargeted: $isAvatarHovered) { providers in
                handleDroppedImage(providers: providers, isAvatar: true)
            }
            
            PhotosPicker(selection: $avatarItem, matching: .images) {
                Label("Выбрать фото...", systemImage: "photo.on.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    
    // Custom drop-zone and picker for Banner
    private var bannerUploadView: some View {
        VStack(spacing: 12) {
            ZStack {
                previewImage(urlStr: bannerUrlDraft)
                    .frame(width: 240, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
                
                if isBannerHovered {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.5))
                        .overlay(
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                        )
                }
            }
            .frame(width: 240, height: 120)
            .shadow(radius: 4)
            .onDrop(of: [.image, .fileURL], isTargeted: $isBannerHovered) { providers in
                handleDroppedImage(providers: providers, isAvatar: false)
            }
            
            PhotosPicker(selection: $bannerItem, matching: .images) {
                Label("Выбрать обложку...", systemImage: "photo.on.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func previewImage(urlStr: String) -> some View {
        if urlStr.hasPrefix("data:image"),
           let data = base64ToData(urlStr),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.04)
                }
            }
        } else {
            Color.white.opacity(0.04)
        }
    }
    
    private func base64ToData(_ base64Str: String) -> Data? {
        let parts = base64Str.components(separatedBy: ";base64,")
        guard parts.count == 2 else { return nil }
        return Data(base64Encoded: parts[1])
    }
    
    private func handleDroppedImage(providers: [NSItemProvider], isAvatar: Bool) -> Bool {
        guard let provider = providers.first else { return false }
        
        if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { image, error in
                if let uiImage = image as? UIImage,
                   let data = uiImage.jpegData(compressionQuality: 0.8) {
                    let base64 = data.base64EncodedString()
                    let dataUri = "data:image/jpeg;base64,\(base64)"
                    Task { @MainActor in
                        if isAvatar {
                            avatarUrlDraft = dataUri
                        } else {
                            bannerUrlDraft = dataUri
                        }
                    }
                }
            }
            return true
        }
        return false
    }

    private func saveProfile() {
        isSaving = true
        
        Task {
            let success = await app.profile.updateProfile(
                client: app.api,
                userId: app.settings.userId,
                avatarUrl: avatarUrlDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                bannerUrl: bannerUrlDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                bio: bioDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                pinnedTrack: shouldRemovePinnedTrack ? nil : selectedPinnedTrack,
                shouldRemovePinnedTrack: shouldRemovePinnedTrack
            )
            isSaving = false
            if success {
                dismiss()
            }
        }
    }
}

// MARK: - Track search for pin

struct PinnedTrackSearchSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    
    let onSelect: (Track) -> Void
    
    @State private var query = ""
    @State private var tracks: [Track] = []
    @State private var isSearching = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background
                    .ignoresSafeArea()
                
                VStack(spacing: 12) {
                    // Custom search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.Palette.textTertiary)
                        TextField("Имя артиста или название трека", text: $query)
                            .foregroundStyle(.white)
                            .tint(.white)
                            .onSubmit {
                                performSearch()
                            }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, Theme.Layout.screenInset)
                    .padding(.top, 12)
                    
                    if isSearching {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                        Spacer()
                    } else if tracks.isEmpty {
                        Spacer()
                        Text(query.isEmpty ? "Введите запрос для поиска" : "Ничего не найдено")
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Spacer()
                    } else {
                        List(tracks) { track in
                            Button {
                                onSelect(track)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    AsyncImage(url: track.artworkURL) { phase in
                                        if let image = phase.image {
                                            image.resizable().scaledToFill()
                                        } else {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.white.opacity(0.04))
                                        }
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(track.artist)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.Palette.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Color.emerald)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                        .scrollContentBackground(.hidden)
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Выбор трека")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
    
    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        Task {
            do {
                let response = try await app.api.search(query: trimmed)
                self.tracks = response.tracks
            } catch {
                print("[PinSearch] error: \(error)")
            }
            isSearching = false
        }
    }
}

// MARK: - Badge Details Definition

struct BadgeDetails: Identifiable {
    let id: String
    let label: String
    let description: String
    let iconName: String
    let color: Color
    let bgColors: [Color]
}

let badgeCatalog: [BadgeDetails] = [
    BadgeDetails(id: "melomaniac", label: "Меломан", description: "Прослушано более 100 треков", iconName: "music.note", color: .yellow, bgColors: [Color.yellow.opacity(0.12), Color.yellow.opacity(0.04)]),
    BadgeDetails(id: "marathoner", label: "Марафонец", description: "Прослушано 10+ треков за один день", iconName: "bolt.fill", color: .orange, bgColors: [Color.orange.opacity(0.12), Color.orange.opacity(0.04)]),
    BadgeDetails(id: "loyal_fan", label: "Преданный фанат", description: "Слушает одного артиста регулярно", iconName: "heart.fill", color: .pink, bgColors: [Color.pink.opacity(0.12), Color.pink.opacity(0.04)]),
    BadgeDetails(id: "collector", label: "Коллекционер", description: "Добавлено 50+ треков в медиатеку", iconName: "star.fill", color: .yellow, bgColors: [Color.yellow.opacity(0.12), Color.yellow.opacity(0.04)]),
    BadgeDetails(id: "curator", label: "Куратор", description: "Создано 5+ публичных плейлистов", iconName: "music.note.list", color: .cyan, bgColors: [Color.cyan.opacity(0.12), Color.cyan.opacity(0.04)]),
    BadgeDetails(id: "architect", label: "Архитектор", description: "Управляет очередью воспроизведения", iconName: "square.stack.3d.down.right.fill", color: .blue, bgColors: [Color.blue.opacity(0.12), Color.blue.opacity(0.04)]),
    BadgeDetails(id: "designer", label: "Дизайнер", description: "Использует кастомные темы оформления", iconName: "sparkles", color: .emerald, bgColors: [Color.emerald.opacity(0.12), Color.emerald.opacity(0.04)]),
    BadgeDetails(id: "pioneer", label: "Первопроходец", description: "Один из первых 100 пользователей PrismMusic", iconName: "flag.fill", color: .purple, bgColors: [Color.purple.opacity(0.12), Color.purple.opacity(0.04)]),
    BadgeDetails(id: "veteran", label: "Ветеран", description: "В PrismMusic уже более 6 месяцев", iconName: "medal.fill", color: .indigo, bgColors: [Color.indigo.opacity(0.12), Color.indigo.opacity(0.04)]),
    BadgeDetails(id: "night_owl", label: "Сова", description: "Часто слушает музыку ночью (00:00 - 05:00)", iconName: "moon.stars.fill", color: .purple, bgColors: [Color.purple.opacity(0.12), Color.purple.opacity(0.04)]),
    BadgeDetails(id: "commentator", label: "Рецензент", description: "Оставил более 10 комментариев к трекам", iconName: "bubble.left.and.bubble.right.fill", color: .teal, bgColors: [Color.teal.opacity(0.12), Color.teal.opacity(0.04)]),
    BadgeDetails(id: "prism_plus", label: "Prism Plus", description: "Активная подписка Prism Plus", iconName: "crown.fill", color: .yellow, bgColors: [Color.yellow.opacity(0.15), Color.purple.opacity(0.1)])
]

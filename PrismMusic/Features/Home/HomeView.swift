//
//  HomeView.swift
//  PrismMusic
//
//  Recommendations feed matching the web main-content.tsx design:
//   - Hero banner with blurred cover crossfade + gradient
//   - 2-column grid of playlist cards with tap → fetch tracks → play
//   - Pull-to-refresh
//   - Loading states for playlist fetches
//

import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var activeTab: HomeTab = .home
    @Namespace private var tabNamespace

    enum HomeTab {
        case home, hot, mix
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ImmersiveBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Hero banner
                        heroBanner

                        // Content
                        if !app.networkMonitor.isConnected {
                            offlinePlaceholder
                        } else {
                            switch app.recommendations.state {
                            case .idle, .loading:
                                loadingState
                            case .failed(let message):
                                errorState(message)
                            case .loaded:
                                VStack(alignment: .leading, spacing: 0) {
                                    tabSelector
                                    if activeTab == .mix {
                                        dailyMixesSection
                                    } else {
                                        albumGrid
                                        if activeTab == .home {
                                            recentlyPlayedSection
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 140) // mini-player + tab bar room
                }
                .ignoresSafeArea(edges: .top)
                .scrollIndicators(.hidden)
                .refreshable {
                    if activeTab == .mix {
                        if app.settings.isLoggedIn {
                            await app.recommendations.refreshDailyMixes(client: app.api, userId: app.settings.userId)
                        }
                    } else {
                        await app.recommendations.refresh(client: app.api)
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
        }
    }

    // MARK: - Hero banner

    private var heroBanner: some View {
        ZStack(alignment: .bottomLeading) {
            // Blurred cover background
            GeometryReader { _ in
                heroCoverBackground
            }

            // Gradient overlay
            LinearGradient(
                colors: [
                    .clear,
                    app.settings.immersiveMode ? .black.opacity(0.2) : Theme.Palette.background.opacity(0.7),
                    app.settings.immersiveMode ? .black.opacity(0.5) : Theme.Palette.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Text content — no background, no substrate
            VStack(alignment: .leading, spacing: 4) {
                Text("PrismMusic")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(.white)

                Text("Слушай подборки и любимые треки")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.horizontal, Theme.Layout.screenInset + 4)
            .padding(.bottom, 20)
        }
        .frame(height: 240)
        .clipped()
    }

    @ViewBuilder
    private var heroCoverBackground: some View {
        let coverURL = app.audio.currentTrack?.artworkURL
            ?? app.recommendations.albums.first?.cover

        if let url = coverURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 40, opaque: true)
                        .saturation(1.4)
                        .brightness(-0.15)
                        .scaleEffect(1.15)
                } else {
                    defaultHeroGradient
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
        } else {
            defaultHeroGradient
        }
    }

    private var defaultHeroGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.15, green: 0.08, blue: 0.25),
                Theme.Palette.background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Загружаем подборки...")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
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
                Task { await app.recommendations.refresh(client: app.api) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Album grid

    private var displayedAlbums: [Album] {
        let albums = app.recommendations.albums
        guard !albums.isEmpty else { return [] }
        if activeTab == .home {
            return Array(albums.prefix(12))
        } else {
            if albums.count > 12 {
                return Array(albums.suffix(from: 12))
            } else {
                let halfIndex = albums.count / 2
                return Array(albums.suffix(from: halfIndex))
            }
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 24) {
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                    activeTab = .home
                }
            } label: {
                VStack(spacing: 6) {
                    Text("Главная")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(activeTab == .home ? .white : .white.opacity(0.45))
                    
                    if activeTab == .home {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: 20, height: 3)
                            .matchedGeometryEffect(id: "activeTabUnderline", in: tabNamespace)
                    } else {
                        Color.clear
                            .frame(width: 20, height: 3)
                    }
                }
            }
            .buttonStyle(.plain)
            
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                    activeTab = .hot
                }
            } label: {
                VStack(spacing: 6) {
                    Text("Новое и горячее")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(activeTab == .hot ? .white : .white.opacity(0.45))
                    
                    if activeTab == .hot {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: 20, height: 3)
                            .matchedGeometryEffect(id: "activeTabUnderline", in: tabNamespace)
                    } else {
                        Color.clear
                            .frame(width: 20, height: 3)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                    activeTab = .mix
                }
            } label: {
                VStack(spacing: 6) {
                    Text("Микс")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(activeTab == .mix ? .white : .white.opacity(0.45))
                    
                    if activeTab == .mix {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: 20, height: 3)
                            .matchedGeometryEffect(id: "activeTabUnderline", in: tabNamespace)
                    } else {
                        Color.clear
                            .frame(width: 20, height: 3)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Layout.screenInset)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var albumGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(activeTab == .home ? "Выбор редакции" : "Сейчас в тренде")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Layout.screenInset)

            if displayedAlbums.isEmpty {
                Text("Нет подборок")
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 18
                ) {
                    ForEach(displayedAlbums) { album in
                        AlbumCardView(album: album)
                    }
                }
                .padding(.horizontal, Theme.Layout.screenInset)
            }
        }
        .padding(.top, 8)
    }

    private var recentlyPlayedSection: some View {
        Group {
            let albums = app.recommendations.albums
            let limit = activeTab == .home ? 12 : 6
            if albums.count > limit {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Недавно слушал")
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
                        ForEach(Array(albums.suffix(from: limit).prefix(6))) { album in
                            AlbumCardView(album: album)
                        }
                    }
                    .padding(.horizontal, Theme.Layout.screenInset)
                }
                .padding(.top, 24)
            }
        }
    }

    private var offlinePlaceholder: some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Отсутствует подключение")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text("Подключись к интернету, либо перейди во вкладку Медиатека, чтобы слушать загруженные треки")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var dailyMixesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ваш персональный микс")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Layout.screenInset)
            
            Text("Подборки треков, составленные на основе ваших любимых жанров и предпочтений. Обновляются ежедневно.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.horizontal, Theme.Layout.screenInset)
                .padding(.bottom, 8)
            
            if !app.settings.isLoggedIn {
                authRequiredPlaceholder
            } else {
                switch app.recommendations.dailyMixesState {
                case .idle, .loading:
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, minHeight: 120)
                case .failed(let msg):
                    errorState(msg)
                case .loaded:
                    if app.recommendations.dailyMixes.isEmpty {
                        Text("Нет миксов")
                            .font(Theme.Typography.secondary)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 14),
                                GridItem(.flexible(), spacing: 14)
                            ],
                            spacing: 18
                        ) {
                            ForEach(app.recommendations.dailyMixes) { album in
                                AlbumCardView(album: album)
                            }
                        }
                        .padding(.horizontal, Theme.Layout.screenInset)
                    }
                }
            }
        }
        .padding(.top, 8)
        .task(id: activeTab) {
            if activeTab == .mix, app.settings.isLoggedIn {
                await app.recommendations.loadDailyMixesIfNeeded(client: app.api, userId: app.settings.userId)
            }
        }
    }

    private var authRequiredPlaceholder: some View {
        VStack(spacing: 18) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.red.opacity(0.8))
            Text("Войдите в аккаунт")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text("Авторизуйтесь в PrismMusic, чтобы мы могли составить ваши индивидуальные Дневные Миксы.")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }

}

// MARK: - Album card (matches web album-card.tsx)

struct AlbumCardView: View {
    let album: Album
    @State private var isPressed = false

    var body: some View {
        NavigationLink(value: album) {
            VStack(alignment: .leading, spacing: 8) {
                // Square cover with play overlay
                ZStack {
                    coverImage
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()

                    if isPressed {
                        Color.black.opacity(0.4)
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 8)
                            }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )

                // Title + subtitle — no background, clean text
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    Text(album.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .buttonStyle(CardPressStyle(isPressed: $isPressed))
    }

    @ViewBuilder
    private var coverImage: some View {
        AsyncImage(url: album.artworkURL) { phase in
            if let image = phase.image {
                image.resizable()
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
    }

    private var fallbackCover: some View {
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
}

/// Button style that tracks press state for the play overlay.
private struct CardPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.snap, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

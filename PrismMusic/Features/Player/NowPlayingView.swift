//
//  NowPlayingView.swift
//  PrismMusic
//
//  Full-screen player. Same composition as the web `FullScreenPlayer`:
//   - top bar (close + "Сейчас играет" label)
//   - animated cover in the centre
//   - track info (source / title / artist) with smooth crossfade on track change
//   - progress slider + time labels
//   - playback controls (shuffle / prev / play-pause / next / repeat)
//   - secondary actions (like, lyrics, queue, volume, share, more)
//   - lyrics panel that slides out from behind the cover when lyrics enabled
//
//  Track change animations:
//   - Cover slides left/right based on direction (forward → left, backward → right)
//   - Track info crossfades with a subtle upward slide
//   - Backdrop smoothly transitions to the new cover's colour palette
//

import SwiftUI

struct NowPlayingView: View {
    @Environment(AppState.self) private var app
    @Binding var isPresented: Bool
    @Binding var pendingArtistDestination: ArtistDestination?

    enum Panel: Equatable { case none, lyrics, queue, comments }
    @State private var panel: Panel = .none
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>? = nil
    @State private var sleepMinutes: Int? = nil
    @State private var sleepTask: Task<Void, Never>? = nil

    private func setSleepTimer(_ minutes: Int?) {
        resetIdleTimer()
        sleepMinutes = minutes
        startSleepTimer()
    }

    private func startSleepTimer() {
        sleepTask?.cancel()
        guard let minutes = sleepMinutes, app.audio.isPlaying else { return }
        sleepTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            if app.audio.isPlaying {
                app.audio.togglePlay()
            }
            sleepMinutes = nil
        }
    }

    private func shareTrack() {
        guard let track = app.audio.currentTrack else { return }
        let shareText = "Послушай \(track.title) — \(track.artist) в PrismMusic"
        
        let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            if let popoverController = activityVC.popoverPresentationController {
                popoverController.sourceView = rootVC.view
                popoverController.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                popoverController.permittedArrowDirections = []
            }
            rootVC.present(activityVC, animated: true)
        }
    }

    private func resetIdleTimer() {
        guard panel == .lyrics else {
            withAnimation(Theme.Motion.apple) {
                showControls = true
            }
            hideControlsTask?.cancel()
            return
        }
        withAnimation(Theme.Motion.apple) {
            showControls = true
        }
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.appleLong) {
                showControls = false
            }
        }
    }

    private func cancelIdleTimer() {
        hideControlsTask?.cancel()
        withAnimation(Theme.Motion.apple) {
            showControls = true
        }
    }

    private func handleBackgroundTap() {
        guard panel == .lyrics else { return }
        if showControls {
            withAnimation(Theme.Motion.apple) {
                showControls = false
            }
            hideControlsTask?.cancel()
        } else {
            resetIdleTimer()
        }
    }

    /// Custom transition for cover based on track change direction.
    private var coverTransition: AnyTransition {
        let isForward = app.audio.trackChangeDirection == .forward
        if app.audio.trackChangeDirection == .none {
            return .scale(scale: 0.92).combined(with: .opacity)
        }

        let moveEdge: Edge = isForward ? .trailing : .leading
        let removeEdge: Edge = isForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: moveEdge).combined(with: .opacity).combined(with: .scale(scale: 0.88)),
            removal: .move(edge: removeEdge).combined(with: .opacity).combined(with: .scale(scale: 0.88))
        )
    }

    var body: some View {
        ZStack {
            // Classic blurred backdrop
            Backdrop()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Transparent tap catcher for lyrics background tap — sits below controls
            if panel == .lyrics {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleBackgroundTap()
                    }
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                if showControls {
                    topBar
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if panel == .lyrics {
                    HStack(spacing: 8) {
                        AsyncImage(url: app.audio.currentTrack?.artworkURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color.white.opacity(0.1)
                            }
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.audio.currentTrack?.title ?? "—")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(app.audio.currentTrack?.artist ?? "")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: 160, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .prismGlassCapsule()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        resetIdleTimer()
                    }
                }

                Spacer(minLength: 12)

                ZStack {
                    if panel == .lyrics {
                        SyncedLyricsView(
                            lyrics: app.audio.lyrics,
                            progress: app.audio.progress,
                            duration: app.audio.duration,
                            isPlaying: app.audio.isPlaying,
                            onSeek: { app.audio.seek(to: $0) },
                            onInteraction: {
                                resetIdleTimer()
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleBackgroundTap()
                        }
                        .transition(.opacity)
                    } else if panel == .queue {
                        QueueView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                    } else if panel == .comments {
                        if let track = app.audio.currentTrack {
                            ScrollView {
                                CommentsView(
                                    kind: .track,
                                    targetId: track.id,
                                    profileOwnerId: nil,
                                    variant: .overlay
                                )
                                .padding(.horizontal, Theme.Layout.screenInset)
                                .padding(.top, 16)
                            }
                            .transition(.opacity)
                        } else {
                            Text("Выберите трек")
                                .font(Theme.Typography.secondary)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .transition(.opacity)
                        }
                    } else {
                        // Show centered square cover
                        GeometryReader { proxy in
                            let coverSize = min(proxy.size.width, proxy.size.height) * 0.85
                            AnimatedCoverView(
                                track: app.audio.currentTrack,
                                isPlaying: app.audio.isPlaying,
                                size: coverSize
                            )
                            .id(app.audio.currentTrack?.id)
                            .transition(coverTransition)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onEnded { value in
                                        let horizontalDistance = value.translation.width
                                        let verticalDistance = value.translation.height
                                        
                                        if verticalDistance > 80 && abs(horizontalDistance) < abs(verticalDistance) {
                                            isPresented = false
                                        } else if abs(horizontalDistance) > 60 && abs(verticalDistance) < abs(horizontalDistance) {
                                            if horizontalDistance < 0 {
                                                app.audio.next()
                                            } else {
                                                app.audio.previous()
                                            }
                                        }
                                    }
                            )
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxHeight: .infinity)
                .animation(Theme.Motion.appleLong, value: panel)
                .animation(.spring(response: 0.55, dampingFraction: 0.78), value: app.audio.currentTrack?.id)

                if showControls {
                    VStack(spacing: 0) {
                        trackInfo
                            .padding(.horizontal, Theme.Layout.screenInset)
                            .padding(.top, 16)

                        progress
                            .padding(.horizontal, Theme.Layout.screenInset)
                            .padding(.top, 18)

                        playbackControls
                            .padding(.top, 14)

                        actionRow
                            .padding(.top, 18)
                            .padding(.horizontal, Theme.Layout.screenInset)
                            .padding(.bottom, 28)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            if panel == .lyrics {
                resetIdleTimer()
            }
        }
        .onDisappear {
            cancelIdleTimer()
        }
        .onChange(of: panel) { _, newPanel in
            if newPanel == .lyrics {
                resetIdleTimer()
            } else {
                cancelIdleTimer()
            }
        }
        .onChange(of: app.audio.isPlaying) { _, _ in
            startSleepTimer()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                resetIdleTimer()
                isPresented = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(GlassCircleButtonStyle())

            Spacer()

            VStack(spacing: 2) {
                Text("Сейчас играет")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text(app.audio.currentTrack?.album ?? app.audio.currentTrack?.title ?? "—")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .id(app.audio.currentTrack?.id)
                    .transition(.opacity)
            }
            .animation(Theme.Motion.apple, value: app.audio.currentTrack?.id)

            Spacer()

            Menu {
                if app.networkMonitor.isConnected, let track = app.audio.currentTrack {
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
                
                if let track = app.audio.currentTrack {
                    let liked = app.library.isLiked(track)
                    Button {
                        app.audio.toggleLike()
                    } label: {
                        Label(
                            liked ? "Удалить из любимых" : "В любимые",
                            systemImage: liked ? "heart.fill" : "heart"
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(GlassCircleButtonStyle())
        }
        .padding(.horizontal, Theme.Layout.screenInset)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 40 && abs(value.translation.width) < abs(value.translation.height) {
                        isPresented = false
                    }
                }
        )
    }

    // MARK: - Track info

    private var trackInfo: some View {
        VStack(spacing: 4) {
            if let source = app.audio.currentTrack?.source {
                Text(source.label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.bottom, 4)
            }
            Text(app.audio.currentTrack?.title ?? "Ничего не выбрано")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)

            Button {
                guard let track = app.audio.currentTrack else { return }
                let rawId = track.id.components(separatedBy: ":").last ?? track.id
                pendingArtistDestination = ArtistDestination(
                    id: rawId,
                    name: track.artist,
                    source: track.source ?? .soundcloud
                )
                isPresented = false
            } label: {
                Text(app.audio.currentTrack?.artist ?? "Выбери трек из библиотеки")
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .underline(color: .clear) // Reserve space, subtle tap
            }
            .buttonStyle(.plain)
        }
        .id(app.audio.currentTrack?.id)
        .transition(coverTransition)
        .animation(.spring(response: 0.52, dampingFraction: 0.85), value: app.audio.currentTrack?.id)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Progress

    private var progress: some View {
        VStack(spacing: 6) {
            ProgressSlider(
                value: app.audio.progress,
                duration: app.audio.duration,
                onSeek: {
                    resetIdleTimer()
                    app.audio.seek(to: $0)
                }
            )
            HStack {
                Text(formatTime(app.audio.progress))
                Spacer()
                Text(formatTime(app.audio.duration))
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.Palette.textTertiary)
            .monospacedDigit()
        }
    }

    // MARK: - Playback controls

    private var playbackControls: some View {
        HStack(spacing: 28) {
            iconButton(
                "shuffle",
                tinted: app.audio.isShuffled,
                action: {
                    app.audio.toggleShuffle()
                    HapticFeedback.impact(.light)
                }
            )

            iconButton("backward.fill", size: 28, action: {
                app.audio.previous()
                HapticFeedback.impact(.medium)
            })

            Button(action: {
                resetIdleTimer()
                app.audio.togglePlay()
                HapticFeedback.impact(.medium)
            }) {
                Image(systemName: app.audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: 76, height: 76)
                    .foregroundStyle(.black)
                    .background(
                        Circle()
                            .fill(.white)
                            .shadow(color: .white.opacity(0.25), radius: 22)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .scaleEffect(app.audio.isPlaying ? 1 : 0.94)
            .animation(Theme.Motion.snap, value: app.audio.isPlaying)

            iconButton("forward.fill", size: 28, action: {
                app.audio.next()
                HapticFeedback.impact(.medium)
            })

            iconButton(
                repeatIcon,
                tinted: app.audio.repeatMode != .off,
                action: {
                    app.audio.toggleRepeat()
                    HapticFeedback.impact(.light)
                }
            )
        }
    }

    private var repeatIcon: String {
        switch app.audio.repeatMode {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    private func iconButton(_ symbol: String, size: CGFloat = 22, tinted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: {
            resetIdleTimer()
            action()
        }) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
                .foregroundStyle(tinted ? Color.white : Theme.Palette.textSecondary)
        }
        .buttonStyle(.plain)
        .contentTransition(.symbolEffect(.replace))
    }

    // MARK: - Secondary actions

    private var actionRow: some View {
        HStack {
            Spacer()

            // Like
            let liked = app.audio.currentTrack.map(app.library.isLiked) ?? false
            Button(action: {
                resetIdleTimer()
                app.audio.toggleLike()
                HapticFeedback.impact(.light)
            }) {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .foregroundStyle(liked ? Color.white : Theme.Palette.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            // Lyrics (music.mic like website)
            Button(action: {
                resetIdleTimer()
                togglePanel(.lyrics)
            }) {
                Image(systemName: "music.mic")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .foregroundStyle(panel == .lyrics ? Color.white : Theme.Palette.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            // Queue
            Button(action: {
                resetIdleTimer()
                togglePanel(.queue)
            }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .foregroundStyle(panel == .queue ? Color.white : Theme.Palette.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            // Comments
            Button(action: {
                resetIdleTimer()
                togglePanel(.comments)
            }) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .foregroundStyle(panel == .comments ? Color.white : Theme.Palette.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            // Sleep Timer Menu
            Menu {
                Button("Выключить") {
                    setSleepTimer(nil)
                }
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) мин") {
                        setSleepTimer(minutes)
                    }
                }
            } label: {
                Image(systemName: sleepMinutes != nil ? "moon.zzz.fill" : "moon.zzz")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .foregroundStyle(sleepMinutes != nil ? Color.white : Theme.Palette.textSecondary)
                    .overlay(alignment: .topTrailing) {
                        if let sleepMinutes {
                            Text("\(sleepMinutes)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.white))
                                .offset(x: 4, y: -4)
                        }
                    }
            }
            .menuStyle(.button)

            Spacer()

            // Share
            Button(action: {
                resetIdleTimer()
                shareTrack()
            }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private func togglePanel(_ target: Panel) {
        withAnimation(Theme.Motion.appleLong) {
            panel = (panel == target) ? .none : target
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Cover-tinted backdrop

private struct Backdrop: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            Theme.Palette.background

            if let url = app.audio.currentTrack?.artworkURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 80, opaque: true)
                            .saturation(1.4)
                            .opacity(0.7)
                            .scaleEffect(1.4)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                .id(app.audio.currentTrack?.id)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.8), value: app.audio.currentTrack?.id)
            }

            LinearGradient(
                colors: [.black.opacity(0.45), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Glass circle button style

struct GlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .prismGlassCircle()
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(Theme.Motion.snap, value: configuration.isPressed)
    }
}

// MARK: - Custom progress slider with rounded thumb

private struct ProgressSlider: View {
    let value: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { proxy in
            let frac: Double = {
                let v = dragValue ?? value
                guard duration > 0 else { return 0 }
                return max(0, min(1, v / duration))
            }()
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, proxy.size.width * frac), height: 4)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard duration > 0 else { return }
                        let frac = max(0, min(1, gesture.location.x / proxy.size.width))
                        dragValue = frac * duration
                    }
                    .onEnded { _ in
                        if let dragValue { onSeek(dragValue) }
                        dragValue = nil
                    }
            )
        }
        .frame(height: 18)
    }
}

// MARK: - Queue View

private struct QueueView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Далее")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            let upNextTracks = Array(app.audio.queue.suffix(from: min(app.audio.queue.count, app.audio.currentIndex + 1)))

            if upNextTracks.isEmpty {
                VStack {
                    Spacer()
                    Text("Очередь пуста")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(upNextTracks.enumerated()), id: \.element.id) { index, track in
                        let actualQueueIndex = app.audio.currentIndex + 1 + index
                        TrackRowView(
                            track: track,
                            isPlaying: false,
                            onTap: {
                                app.audio.play(queue: app.audio.queue, startAt: actualQueueIndex)
                            }
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden)
                    }
                    .onMove { indices, newOffset in
                        app.audio.moveTrack(from: indices, to: newOffset)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .environment(\.editMode, .constant(.active))
            }
        }
    }
}



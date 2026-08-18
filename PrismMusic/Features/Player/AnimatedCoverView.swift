//
//  AnimatedCoverView.swift
//  PrismMusic
//
//  Clean and high-performance album cover representation for the Prism player:
//   - Centered square cover with rounded corners and high-quality rendering.
//   - Subtle shadow and dominant-color glow effects behind the cover.
//   - Gyroscope parallax, organic drift, and breathing animations when enabled.
//   - Smooth spring scale animation (1.0 when playing, 0.82 when paused) for visual feedback.
//

import SwiftUI
import CoreMotion

struct AnimatedCoverView: View {
    @Environment(AppState.self) private var app

    let track: Track?
    let isPlaying: Bool
    /// Side length in points. Square aspect enforced.
    let size: CGFloat

    @State private var dominantColor: Color = .white
    @StateObject private var motion = MotionManager.shared

    private var animatedCoverEnabled: Bool {
        app.settings.animatedCover
    }

    var body: some View {
        ZStack {
            // Radiant glow tinted with the cover's dominant colour
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(dominantColor.opacity(0.4))
                .blur(radius: size * 0.20)
                .offset(y: size * 0.04)
                .scaleEffect(0.92)

            // Actual artwork
            artwork
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.06, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(
                    color: .black.opacity(isPlaying ? 0.45 : 0.15),
                    radius: isPlaying ? 30 : 15,
                    y: isPlaying ? 16 : 8
                )
                .scaleEffect(isPlaying ? 1.0 : 0.82)
                .rotation3DEffect(
                    animatedCoverEnabled ? .degrees(motion.pitch * 6) : .zero,
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.3
                )
                .rotation3DEffect(
                    animatedCoverEnabled ? .degrees(motion.roll * 6) : .zero,
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.3
                )
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isPlaying)
        }
        .frame(width: size, height: size)
        .task(id: track?.artworkURL) {
            await refreshDominantColor()
        }
        .onAppear {
            if animatedCoverEnabled {
                motion.start()
            }
        }
        .onDisappear {
            motion.stop()
        }
        .onChange(of: animatedCoverEnabled) { _, enabled in
            if enabled {
                motion.start()
            } else {
                motion.stop()
            }
        }
    }

    // MARK: - Artwork loader

    @ViewBuilder
    private var artwork: some View {
        if let url = track?.artworkURL {
            AsyncImage(url: url) { phase in
                ZStack {
                    if let image = phase.image {
                        image
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .transition(.opacity)
                    } else {
                        fallback
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: phase.image != nil)
            }
            .id(url)
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: size * 0.3, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Dominant Color

    private func refreshDominantColor() async {
        guard let url = track?.artworkURL else { dominantColor = .white; return }
        if let color = await ColorExtractor.dominantColor(from: url) {
            withAnimation(.easeInOut(duration: 0.6)) { dominantColor = color }
        }
    }
}

// MARK: - Gyroscope Motion Manager

@MainActor
final class MotionManager: ObservableObject {
    static let shared = MotionManager()

    @Published private(set) var roll: Double = 0
    @Published private(set) var pitch: Double = 0

    private let manager = CMMotionManager()
    private var refCount = 0

    private init() {}

    func start() {
        refCount += 1
        guard refCount == 1, manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let roll = motion.attitude.roll
            let pitch = motion.attitude.pitch
            Task { @MainActor [weak self] in
                guard let self else { return }
                let alpha = 0.12
                self.roll = self.roll * (1 - alpha) + roll * alpha
                self.pitch = self.pitch * (1 - alpha) + pitch * alpha
            }
        }
    }

    func stop() {
        refCount = max(0, refCount - 1)
        if refCount == 0 && manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
            roll = 0
            pitch = 0
        }
    }
}

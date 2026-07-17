//
//  SyncedLyricsView.swift
//  PrismMusic
//
//  Synchronised lyrics with word-level highlighting — same algorithm as
//  the web `synced-lyrics.tsx`. Active line scrolls into the centre with
//  a smooth Apple-style ease curve. Tapping a line seeks the player.
//
//  We avoid Combine/UIKit gymnastics by leveraging `TimelineView(.animation)`
//  for the per-frame interpolation: it's the SwiftUI equivalent of the
//  web `requestAnimationFrame` loop.
//

import SwiftUI

struct SyncedLyricsView: View {
    let lyrics: ParsedLyrics?
    /// Audio progress from `AudioPlayer`. Ticks ~4×/sec so we interpolate
    /// between updates for sub-second accuracy.
    let progress: Double
    let duration: Double
    let isPlaying: Bool
    let onSeek: (Double) -> Void
    var onInteraction: (() -> Void)? = nil

    @StateObject private var ticker = LyricsTicker()

    var body: some View {
        Group {
            if let lyrics, !lyrics.lines.isEmpty {
                content(lines: lyrics.lines, isSynced: lyrics.isSynced)
            } else if lyrics == nil {
                placeholder(symbol: "waveform", text: "Загружаем текст...")
            } else {
                placeholder(symbol: "music.mic", text: "Нет текста для этого трека")
            }
        }
        .onAppear {
            ticker.update(progress: progress)
        }
        .onChange(of: progress) { _, newProgress in
            ticker.update(progress: newProgress)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(lines: [LyricsLine], isSynced: Bool) -> some View {
        ScrollViewReader { scroller in
            // TimelineView drives per-frame redraws while playing; pulls
            // the wall-clock and lets us interpolate progress between
            // ~250ms ticks for smooth word advancement.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { timeline in
                let interpolated = ticker.interpolated(at: timeline.date, isPlaying: isPlaying)
                let activeIndex = activeLineIndex(in: lines, at: interpolated, isSynced: isSynced)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            LineView(
                                line: line,
                                isActive: index == activeIndex,
                                isPast: index < activeIndex,
                                progress: interpolated
                            )
                            .id(line.id)
                            .onTapGesture {
                                onInteraction?()
                                if isSynced { onSeek(line.time) }
                            }
                            // Trigger an opacity transition when the active
                            // line changes so the inactive ones gently dim.
                            // Departure (Theme.Motion.standard) is faster than arrival (Theme.Motion.appleLong)
                            .animation((index == activeIndex) ? Theme.Motion.appleLong : Theme.Motion.standard, value: activeIndex)
                        }
                    }
                    .padding(.vertical, 80)   // top/bottom breathing room so the centre line can scroll
                    .padding(.horizontal, 20)
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        onInteraction?()
                    }
                )
                .onChange(of: activeIndex) { _, newIndex in
                    guard newIndex >= 0, newIndex < lines.count else { return }
                    withAnimation(Theme.Motion.appleLong) {
                        scroller.scrollTo(lines[newIndex].id, anchor: .center)
                    }
                }
            }
        }
        // Top + bottom fade so lines don't pop in/out at the edges.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            onInteraction?()
        }
    }

    // MARK: - Active line detection

    /// Pick the latest line whose timestamp ≤ progress (with a 0.1s grace
    /// for early highlighting). Same logic as the web parser.
    private func activeLineIndex(in lines: [LyricsLine], at time: Double, isSynced: Bool) -> Int {
        guard isSynced else { return -1 }
        var best = -1
        var bestTime = -Double.infinity
        for (i, line) in lines.enumerated() {
            guard line.time >= 0 else { continue }
            if line.time - 0.1 <= time && line.time >= bestTime {
                bestTime = line.time
                best = i
            }
        }
        return best
    }
}

// MARK: - Lyrics progress ticker for frame-rate interpolation

@MainActor
private final class LyricsTicker: ObservableObject {
    private var lastProgress: Double = 0
    private var lastUpdate: Date = Date()
    private var rate: Double = 1.0

    func update(progress: Double) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastUpdate)
        let delta = progress - lastProgress
        if elapsed > 0.05 && delta > 0 && delta < 2 {
            let observed = delta / elapsed
            if observed >= 0.5 && observed <= 2.0 {
                rate = rate * 0.7 + observed * 0.3
            }
        }
        lastProgress = progress
        lastUpdate = now
    }

    func interpolated(at date: Date, isPlaying: Bool) -> Double {
        guard isPlaying else { return lastProgress }
        let elapsed = date.timeIntervalSince(lastUpdate)
        if elapsed > 0.35 { return lastProgress }
        return lastProgress + elapsed * rate
    }
}

// MARK: - Single line view (with karaoke word highlight)

private struct LineView: View {
    let line: LyricsLine
    let isActive: Bool
    let isPast: Bool
    let progress: Double

    var body: some View {
        Group {
            if line.isPause {
                AnimatedEllipsisView(isActive: isActive, isPast: isPast)
            } else if let words = line.words, !words.isEmpty {
                karaokeText(words: words)
            } else {
                Text(line.text)
                    .foregroundStyle(lineOnlyTextColor)
                    .shadow(color: isActive ? .white.opacity(0.3) : .clear, radius: 10, x: 0, y: 0)
            }
        }
        .font(.system(size: 24, weight: .bold, design: .rounded))
        .blur(radius: blurRadius)
        .opacity(lineOpacity)
        .shadow(color: isActive ? .white.opacity(0.15) : .clear, radius: 8, x: 0, y: 0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Word-by-word text with an active/inactive split based on `progress`.
    private func karaokeText(words: [LyricsWord]) -> some View {
        var attributed = AttributedString()
        for (i, word) in words.enumerated() {
            let next = i + 1 < words.count ? words[i + 1].time : (line.endTime ?? word.time + 1.0)
            let color = wordColor(start: word.time, end: next)
            let text = word.text + (i == words.count - 1 ? "" : " ")
            var chunk = AttributedString(text)
            chunk.foregroundColor = color
            attributed.append(chunk)
        }
        return Text(attributed)
    }

    private func wordColor(start: Double, end: Double) -> Color {
        if isPast {
            return Color.white.opacity(0.35)
        }
        if isActive {
            if progress < start {
                return Color.white.opacity(0.20)
            } else if progress < end {
                let elapsed = progress - start
                let ratio = min(1.0, max(0.0, elapsed / 0.38))
                let opacity = 0.20 + (1.0 - 0.20) * ratio
                return Color.white.opacity(opacity)
            } else {
                let elapsed = progress - end
                let ratio = min(1.0, max(0.0, elapsed / 0.75))
                let opacity = 1.0 - (1.0 - 0.55) * ratio
                return Color.white.opacity(opacity)
            }
        }
        return Color.white.opacity(0.20)
    }

    // MARK: - Visual style

    private var lineOnlyTextColor: Color {
        if isActive { return .white }
        if isPast { return Color.white.opacity(0.35) }
        return Color.white.opacity(0.20)
    }

    private var lineOpacity: Double {
        if isActive { return 1.0 }
        if isPast { return 0.65 }
        return 1.0
    }

    /// Cinematic depth-of-field — far-away inactive lines blur slightly.
    private var blurRadius: Double {
        isActive ? 0 : 2.0
    }
}

// MARK: - Animated Ellipsis View for Instrumental Breaks

private struct AnimatedEllipsisView: View {
    let isActive: Bool
    let isPast: Bool
    
    @State private var dot1 = false
    @State private var dot2 = false
    @State private var dot3 = false
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .scaleEffect(isActive && dot1 ? 1.25 : 0.8)
                .offset(y: isActive && dot1 ? -6 : 0)
                .opacity(isPast ? 0.35 : (isActive ? (dot1 ? 1.0 : 0.25) : 0.20))
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .scaleEffect(isActive && dot2 ? 1.25 : 0.8)
                .offset(y: isActive && dot2 ? -6 : 0)
                .opacity(isPast ? 0.35 : (isActive ? (dot2 ? 1.0 : 0.25) : 0.20))
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .scaleEffect(isActive && dot3 ? 1.25 : 0.8)
                .offset(y: isActive && dot3 ? -6 : 0)
                .opacity(isPast ? 0.35 : (isActive ? (dot3 ? 1.0 : 0.25) : 0.20))
        }
        .frame(height: 36)
        .onAppear {
            if isActive {
                startAnimation()
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }
    
    private func startAnimation() {
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            dot1 = true
        }
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(0.18)) {
            dot2 = true
        }
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(0.36)) {
            dot3 = true
        }
    }
    
    private func stopAnimation() {
        withAnimation(.easeInOut(duration: 0.3)) {
            dot1 = false
            dot2 = false
            dot3 = false
        }
    }
}

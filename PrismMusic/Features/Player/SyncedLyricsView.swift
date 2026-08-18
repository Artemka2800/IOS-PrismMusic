//
//  SyncedLyricsView.swift
//  PrismMusic
//
//  Synchronised lyrics with word-level highlighting — High Performance Edition.
//  Uses Equatable LineViews and binary search active line indexing to ensure 60/120 FPS
//  without frame drops on iOS.
//

import SwiftUI

struct SyncedLyricsView: View {
    let lyrics: ParsedLyrics?
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
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying || !isSynced)) { timeline in
                let interpolated = ticker.interpolated(at: timeline.date, isPlaying: isPlaying)
                let activeIndex = activeLineIndex(in: lines, at: interpolated, isSynced: isSynced)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: isSynced ? 16 : 14) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            LineView(
                                line: line,
                                isSynced: isSynced,
                                isActive: index == activeIndex,
                                isPast: isSynced && index < activeIndex,
                                progress: interpolated
                            )
                            .equatable()
                            .id(line.id)
                            .onTapGesture {
                                onInteraction?()
                                if isSynced { onSeek(line.time) }
                            }
                            .animation((index == activeIndex) ? Theme.Motion.appleLong : Theme.Motion.standard, value: activeIndex)
                        }
                    }
                    .padding(.vertical, isSynced ? 80 : 24)
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
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: isSynced ? 0.12 : 0.04),
                    .init(color: .black, location: isSynced ? 0.88 : 0.94),
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

    // MARK: - Fast binary-search active line detection

    private func activeLineIndex(in lines: [LyricsLine], at time: Double, isSynced: Bool) -> Int {
        guard isSynced, !lines.isEmpty else { return -1 }
        let effectiveTime = time + 0.1
        var low = 0
        var high = lines.count - 1
        var result = -1

        while low <= high {
            let mid = (low + high) / 2
            let t = lines[mid].time
            if t <= effectiveTime {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}

// MARK: - Lyrics progress ticker

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

// MARK: - Equatable single line view

private struct LineView: View, Equatable {
    let line: LyricsLine
    var isSynced: Bool = true
    let isActive: Bool
    let isPast: Bool
    let progress: Double

    static func == (lhs: LineView, rhs: LineView) -> Bool {
        lhs.line.id == rhs.line.id &&
        lhs.isSynced == rhs.isSynced &&
        lhs.isActive == rhs.isActive &&
        lhs.isPast == rhs.isPast &&
        (!lhs.isActive || abs(lhs.progress - rhs.progress) < 0.02)
    }

    var body: some View {
        Group {
            if line.isPause {
                AnimatedEllipsisView(isActive: isActive, isPast: isPast)
            } else if isSynced, let words = line.words, !words.isEmpty {
                karaokeText(words: words)
            } else {
                Text(line.text)
                    .foregroundStyle(lineOnlyTextColor)
                    .shadow(color: isActive ? .white.opacity(0.3) : .clear, radius: 10, x: 0, y: 0)
            }
        }
        .font(.system(size: 24, weight: .bold, design: .rounded))
        .opacity(lineOpacity)
        .shadow(color: isActive ? .white.opacity(0.15) : .clear, radius: 8, x: 0, y: 0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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

    private var lineOnlyTextColor: Color {
        if !isSynced { return Color.white.opacity(0.9) }
        if isActive { return .white }
        if isPast { return Color.white.opacity(0.35) }
        return Color.white.opacity(0.20)
    }

    private var lineOpacity: Double {
        if !isSynced { return 1.0 }
        if isActive { return 1.0 }
        if isPast { return 0.65 }
        return 0.35
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

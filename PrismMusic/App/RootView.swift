//
//  RootView.swift
//  PrismMusic
//
//  Top-level layout: tab navigation + persistent mini-player overlay +
//  fullscreen Now Playing presented modally. Same composition pattern as
//  the Next.js web app (`app/page.tsx`).
//

import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var nowPlayingPresented = false
    @State private var showCrashReport = false
    @State private var pendingArtistDestination: ArtistDestination?

    var body: some View {
        ZStack {
            Theme.Palette.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if !app.networkMonitor.isConnected {
                    HStack {
                        Spacer()
                        Image(systemName: "wifi.slash")
                        Text("Отсутствует подключение к интернету")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.85))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                TabRoot(pendingArtistDestination: $pendingArtistDestination)
            }
            .animation(.spring(), value: app.networkMonitor.isConnected)

            // Mini player docks above the tab bar. Tapping it opens the
            // full Now Playing modal.
            VStack {
                Spacer()
                if app.audio.currentTrack != nil {
                    MiniPlayerView(onExpand: { nowPlayingPresented = true })
                        .padding(.horizontal, 12)
                        .padding(.bottom, 56)   // sits above standard tab bar height
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Theme.Motion.apple, value: app.audio.currentTrack?.id)
        }
        .fullScreenCover(isPresented: $nowPlayingPresented) {
            NowPlayingView(
                isPresented: $nowPlayingPresented,
                pendingArtistDestination: $pendingArtistDestination
            )
                .environment(app)
        }
        .alert(
            "Ошибка воспроизведения",
            isPresented: Bindable(app.audio).showError
        ) {
            Button("ОК", role: .cancel) { }
        } message: {
            Text(app.audio.errorMessage ?? "Неизвестная ошибка")
        }
        .onAppear {
            if CrashReporter.shared.lastCrashReport != nil {
                showCrashReport = true
            }
        }
        .alert("Crash Report", isPresented: $showCrashReport) {
            Button("Скопировать и закрыть") {
                if let report = CrashReporter.shared.lastCrashReport {
                    UIPasteboard.general.string = report
                }
                CrashReporter.shared.lastCrashReport = nil
                showCrashReport = false
            }
        } message: {
            Text(CrashReporter.shared.lastCrashReport ?? "")
        }
    }
}


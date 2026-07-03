//
//  PrismMusicApp.swift
//  PrismMusic
//
//  Entry point. Spins up the global `AppState` (audio + library + settings)
//  and registers it as an `@Environment` value so any view in the tree can
//  reach the player without prop-drilling.
//

import SwiftUI

@main
struct PrismMusicApp: App {
    /// Single shared AppState lives for the entire application lifecycle.
    /// `@State` keeps the SwiftUI runtime aware of it; `@Observable` inside
    /// the type drives view updates.
    @State private var appState = AppState()

    init() {
        CrashReporter.shared.start()
        DebugLogger.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.dark)   // PrismMusic is dark-first, like the web app.
                .tint(appState.accentColor)    // global accent
                .task {
                    // Kick off one-time initialisation here: audio session,
                    // remote command handlers, Live Activity recovery.
                    appState.audio.bootstrap()
                    appState.sync.bootstrap()
                    await appState.recommendations.loadIfNeeded(client: appState.api)
                    await appState.library.syncWithServer()
                }
        }
    }
}

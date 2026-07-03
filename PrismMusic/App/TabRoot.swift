//
//  TabRoot.swift
//  PrismMusic
//
//  Bottom tab navigation: Home / Search / Library / Settings.
//  Uses SwiftUI's `TabView` with `.sidebarAdaptable` style so it'll do the
//  right thing on iPad too.
//

import SwiftUI

struct TabRoot: View {
    @Environment(AppState.self) private var app
    @State private var selection: Tab = .home
    @Binding var pendingArtistDestination: ArtistDestination?

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Главная", systemImage: "house.fill") }
                .tag(Tab.home)
            SearchView(pendingArtistDestination: $pendingArtistDestination)
                .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
                .tag(Tab.search)
            LibraryView()
                .tabItem { Label("Медиатека", systemImage: "rectangle.stack.fill") }
                .tag(Tab.library)
            AccountView()
                .tabItem { Label("Аккаунт", systemImage: "person.crop.circle.fill") }
                .tag(Tab.account)
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gear") }
                .tag(Tab.settings)
        }
        // iOS 26: tab bar automatically gets Liquid Glass material.
        // `.tabBarMinimizeBehavior` lets it shrink on scroll for immersion.
        .safeTabBarMinimizeBehavior()
        .tint(app.accentColor)
        .onChange(of: pendingArtistDestination) { _, dest in
            if dest != nil {
                selection = .search
            }
        }
    }

    enum Tab: Hashable { case home, search, library, account, settings }
}

private extension View {
    @ViewBuilder
    func safeTabBarMinimizeBehavior() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}


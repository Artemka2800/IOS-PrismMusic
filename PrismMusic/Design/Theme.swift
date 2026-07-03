//
//  Theme.swift
//  PrismMusic
//
//  Design tokens that mirror the web app: charcoal-black canvas, white
//  primary text, dimmed secondary text, accent gradients, animation timings.
//
//  Two reusable curves are exported as `Animation` constants so the whole
//  app uses the same easing — same logic as on the web (`cubic-bezier(0.32,
//  0.72, 0, 1)` for Apple's signature ease, plus Material standard).
//

import SwiftUI
import UIKit

enum Theme {
    // MARK: - Colours

    enum Palette {
        /// Near-black canvas, slightly warmer than pure #000.
        static let background = Color(red: 0.03, green: 0.03, blue: 0.04)
        /// Card / panel background with subtle elevation.
        static let surface = Color.white.opacity(0.05)
        static let surfaceElevated = Color.white.opacity(0.08)
        /// Primary text.
        static let textPrimary = Color.white
        /// Secondary / supporting text.
        static let textSecondary = Color.white.opacity(0.65)
        /// Tertiary / labels.
        static let textTertiary = Color.white.opacity(0.45)
        /// Hairline borders.
        static let border = Color.white.opacity(0.10)
    }

    // MARK: - Typography

    enum Typography {
        /// 28pt rounded — big section titles like "Сейчас слушают".
        static let largeTitle = Font.system(size: 28, weight: .bold, design: .rounded)
        /// 22pt rounded — modest section titles.
        static let title = Font.system(size: 22, weight: .semibold, design: .rounded)
        /// 17pt — body / track titles.
        static let body = Font.system(size: 17, weight: .medium)
        /// 15pt — supporting copy, artist names.
        static let secondary = Font.system(size: 15, weight: .regular)
        /// 12pt uppercase — section labels.
        static let caption = Font.system(size: 12, weight: .semibold).uppercaseSmallCaps()
    }

    // MARK: - Animations

    enum Motion {
        /// Apple's signature smooth-scroll / page-transition easing.
        /// Web equivalent: `cubic-bezier(0.32, 0.72, 0, 1)`.
        static let apple = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.5)
        /// Slightly slower variant for big transitions (full-screen player open).
        static let appleLong = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.7)
        /// Material standard easing — fallback for state changes.
        /// Web equivalent: `cubic-bezier(0.4, 0, 0.2, 1)`.
        static let standard = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.3)
        /// Springy bounce for tactile feedback (button presses, toggles).
        static let snap = Animation.interpolatingSpring(stiffness: 220, damping: 22)
    }

    // MARK: - Layout

    enum Layout {
        /// Default screen padding.
        static let screenInset: CGFloat = 16
        /// Vertical rhythm between sections.
        static let sectionSpacing: CGFloat = 24
        /// Inner padding of cards.
        static let cardInset: CGFloat = 12
        /// Outer corner radius for major surfaces (cover, panel, modal).
        static let cornerLarge: CGFloat = 20
        /// Standard control corner radius (buttons, chips).
        static let cornerMedium: CGFloat = 12
    }
}

extension Color {
    static let emerald = Color(red: 0.05, green: 0.78, blue: 0.43)
}

enum HapticFeedback {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}


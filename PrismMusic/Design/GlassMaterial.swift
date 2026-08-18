//
//  GlassMaterial.swift
//  PrismMusic
//
//  Clean and high-performance frosted dark glass material for PrismMusic iOS.
//

import SwiftUI

extension View {
    /// Applies subtle frosted dark glass with clean borders.
    @ViewBuilder
    func prismGlass(cornerRadius: CGFloat? = nil, tint: Color? = nil) -> some View {
        if let radius = cornerRadius {
            self.background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint?.opacity(0.2) ?? Color(white: 0.12).opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        } else {
            self.background(
                Rectangle()
                    .fill(tint?.opacity(0.2) ?? Color(white: 0.12).opacity(0.85))
                    .overlay(
                        Rectangle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
    }

    /// Applies Liquid Glass with a circular shape — for round buttons, avatars, etc.
    @ViewBuilder
    func prismGlassCircle(tint: Color? = nil) -> some View {
        self.background(
            Circle()
                .fill(tint?.opacity(0.2) ?? Color(white: 0.14).opacity(0.85))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }

    /// Applies Liquid Glass with a capsule shape — for pills, chips, search fields.
    @ViewBuilder
    func prismGlassCapsule(tint: Color? = nil) -> some View {
        self.background(
            Capsule()
                .fill(tint?.opacity(0.2) ?? Color(white: 0.14).opacity(0.85))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }
}

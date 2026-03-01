// Theme.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// GitHub-dark inspired color scheme and design tokens.
// Author: Matheus Machado Rech

import SwiftUI

// MARK: - Color tokens

extension Color {
    // Backgrounds
    static let bgPrimary   = Color(hex: "#0d1117")
    static let bgSecondary = Color(hex: "#161b22")
    static let bgTertiary  = Color(hex: "#21262d")
    static let bgCard      = Color(hex: "#1c2128")

    // Borders
    static let border      = Color(hex: "#30363d")
    static let borderMuted = Color(hex: "#21262d")

    // Text
    static let textPrimary  = Color(hex: "#c9d1d9")
    static let textSecondary = Color(hex: "#8b949e")
    static let textMuted    = Color(hex: "#6e7681")

    // Accent
    static let accent      = Color(hex: "#58a6ff")
    static let accentMuted = Color(hex: "#1f6feb")

    // Status
    static let success = Color(hex: "#3fb950")
    static let warning = Color(hex: "#d29922")
    static let danger  = Color(hex: "#f85149")
    static let orange  = Color(hex: "#ff6e40")
    static let cyan    = Color(hex: "#00d4d4")

    // NPH levels
    static let nphLow      = Color(hex: "#3fb950")
    static let nphModerate = Color(hex: "#d29922")
    static let nphHigh     = Color(hex: "#f85149")

    // Metric status
    static let metricNormal   = Color(hex: "#3fb950").opacity(0.15)
    static let metricAbnormal = Color(hex: "#f85149").opacity(0.15)
    static let metricModerate = Color(hex: "#d29922").opacity(0.15)

    /// Initialize Color from a CSS hex string like "#0d1117" or "0d1117".
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: Double
        switch hex.count {
        case 6:
            (r, g, b, a) = (Double((int >> 16) & 0xFF) / 255,
                            Double((int >> 8)  & 0xFF) / 255,
                            Double(int         & 0xFF) / 255,
                            1.0)
        case 8:
            (r, g, b, a) = (Double((int >> 24) & 0xFF) / 255,
                            Double((int >> 16) & 0xFF) / 255,
                            Double((int >> 8)  & 0xFF) / 255,
                            Double(int         & 0xFF) / 255)
        default:
            (r, g, b, a) = (0.5, 0.5, 0.5, 1.0)
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Typography

enum AppFont {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Spacing

enum Spacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 16
    static let lg:  CGFloat = 24
    static let xl:  CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner radii

enum Radius {
    static let sm:  CGFloat = 6
    static let md:  CGFloat = 10
    static let lg:  CGFloat = 14
    static let xl:  CGFloat = 20
}

// MARK: - Common view modifiers

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.bgCard)
            .cornerRadius(Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Color.border, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

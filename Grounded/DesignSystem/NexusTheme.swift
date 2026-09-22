//
//  NexusTheme.swift
//  Grounded
//
//  Design tokens lifted from the "Nexus" Figma file (dark, circuit-board
//  aesthetic; currency is styled as "Voltage"). Values here are pulled directly
//  from the design's hex codes / type scale so every screen stays consistent.
//
//  Font substitution: the design specifies "JetBrains Mono" (numbers, labels)
//  and "Geist" (body/headings). Neither ships on iOS and this project adds no
//  third-party packages, so `.mono` maps to the system monospaced design (SF
//  Mono) and `.sans` maps to the default system font (SF Pro) — visually close
//  substitutes, not the literal typefaces.
//

import SwiftUI

enum NexusColor {
    static let background = Color(hex: 0x0A0A0A)
    static let surface = Color(hex: 0x121212)
    static let surfaceElevated = Color(hex: 0x1A1A1A)
    static let border = Color(hex: 0x2A2A2A)
    static let accent = Color(hex: 0xEAE04A)      // primary yellow
    static let gold = Color(hex: 0xFFD700)        // secondary "voltage" yellow
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x8A8A8F)
}

enum NexusMetrics {
    static let cardRadius: CGFloat = 12
    static let chipRadius: CGFloat = 8
    static let screenPadding: CGFloat = 24
}

enum NexusFont {
    /// Numbers, tags, meta labels — stands in for JetBrains Mono.
    static func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// Body copy and headings — stands in for Geist.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

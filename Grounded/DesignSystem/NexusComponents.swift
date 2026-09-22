//
//  NexusComponents.swift
//  Grounded
//
//  Reusable pieces shared by the Nexus / Missions / Grid / Settings screens.
//

import SwiftUI

/// Outlined rectangle, accent text — the design's primary action (START
/// TASK, RE-GROUND). Sketched as a plain bordered box, not a filled capsule.
struct NexusPrimaryButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(NexusFont.sans(16, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .foregroundStyle(NexusColor.accent)
        .overlay(
            RoundedRectangle(cornerRadius: NexusMetrics.chipRadius)
                .stroke(NexusColor.accent, lineWidth: 1.5)
        )
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Outlined rectangle, muted border — a lower-emphasis secondary action
/// (DISCHARGE, ABORT MISSION). Same bordered-box shape as the primary
/// button, just a quieter border so it doesn't compete with it.
struct NexusSecondaryButton: View {
    let title: String
    var tint: Color = NexusColor.textSecondary
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(NexusFont.sans(14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .foregroundStyle(tint)
        .overlay(
            RoundedRectangle(cornerRadius: NexusMetrics.chipRadius)
                .stroke(tint.opacity(0.5), lineWidth: 1)
        )
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Standard dark card: #121212 surface, #2A2A2A border, 12pt radius.
struct NexusCard<Content: View>: View {
    var highlighted = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NexusColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: NexusMetrics.cardRadius)
                    .stroke(highlighted ? NexusColor.accent : NexusColor.border, lineWidth: highlighted ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius))
            .shadow(color: highlighted ? NexusColor.accent.opacity(0.2) : .clear, radius: 6)
    }
}

/// A small stat tile, e.g. "BLOCKED APPS / 42 active".
struct NexusStatTile: View {
    let label: String
    let value: String
    var valueColor: Color = NexusColor.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(NexusFont.sans(11))
                .foregroundStyle(NexusColor.textSecondary)
            Text(value)
                .font(NexusFont.mono(18))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(NexusColor.surface)
        .overlay(
            RoundedRectangle(cornerRadius: NexusMetrics.cardRadius)
                .stroke(NexusColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius))
    }
}

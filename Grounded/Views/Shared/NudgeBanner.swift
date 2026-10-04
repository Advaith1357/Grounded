//
//  NudgeBanner.swift
//  Grounded
//
//  The "Alex nudged you" toast shown over any tab when a friend zaps you.
//

import SwiftUI

struct NudgeBanner: View {
    let nudge: Nudge
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(NexusColor.background)
                .frame(width: 36, height: 36)
                .background(NexusColor.accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("\(nudge.fromName) nudged you")
                    .font(NexusFont.sans(14, weight: .bold))
                    .foregroundStyle(NexusColor.textPrimary)
                Text("Time to get back on track.")
                    .font(NexusFont.sans(12))
                    .foregroundStyle(NexusColor.textSecondary)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(NexusColor.textSecondary)
            }
        }
        .padding(14)
        .background(NexusColor.surface)
        .overlay(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius).stroke(NexusColor.accent))
        .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius))
        .shadow(color: NexusColor.accent.opacity(0.25), radius: 8)
        .accessibilityElement(children: .combine)
    }
}

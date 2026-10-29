//
//  BlockListsSection.swift
//  Grounded
//
//  The "BLOCK LISTS" block at the top of the Queue tab: every list with an
//  on/off switch, plus a button to add another. Tapping a list's name opens
//  its editor. Switching a list on is what makes its apps blockable; they're
//  only intercepted when you open one.
//

import SwiftUI

struct BlockListsSection: View {
    @EnvironmentObject private var shieldManager: ScreenTimeShieldManager
    @State private var editing: EditTarget?

    private struct EditTarget: Identifiable {
        let id: UUID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BLOCK LISTS")
                    .font(NexusFont.mono(11))
                    .foregroundStyle(NexusColor.textSecondary)
                Spacer()
                Button {
                    editing = EditTarget(id: shieldManager.addBlockList(named: "New list"))
                } label: {
                    Label("New list", systemImage: "plus")
                        .font(NexusFont.mono(11, weight: .bold))
                        .foregroundStyle(NexusColor.accent)
                }
            }

            Text("Switch a list on to block its apps. They're only blocked when you open one.")
                .font(NexusFont.sans(12))
                .foregroundStyle(NexusColor.textSecondary)

            if !ScreenTimeSupport.isEnabled {
                pausedNotice
            } else if !shieldManager.accessApproved {
                accessNotice
            }

            if shieldManager.blockLists.isEmpty {
                Text("No lists yet. Tap New list to make one.")
                    .font(NexusFont.sans(13))
                    .foregroundStyle(NexusColor.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(shieldManager.blockLists) { list in
                    row(list)
                }
            }
        }
        .sheet(item: $editing) { target in
            BlockListEditorSheet(listID: target.id)
        }
    }

    private var pausedNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(NexusColor.gold)
            Text("Blocking is paused in this build — it needs Screen Time, which needs a paid developer account. Your lists are saved and start blocking once Screen Time is turned on.")
                .font(NexusFont.sans(12))
                .foregroundStyle(NexusColor.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.chipRadius))
    }

    /// Screen Time is built in but not approved (e.g. "Don't Allow" was tapped).
    private var accessNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(NexusColor.gold)
                Text("Screen Time access is off, so Grounded can't block anything yet.")
                    .font(NexusFont.sans(12))
                    .foregroundStyle(NexusColor.textSecondary)
            }
            Button {
                Task { await shieldManager.requestAccess() }
            } label: {
                Text("TURN ON SCREEN TIME ACCESS")
                    .font(NexusFont.mono(12, weight: .bold))
                    .foregroundStyle(NexusColor.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(NexusColor.accent)
                    .clipShape(Capsule())
            }
            Text("If nothing appears, delete Grounded and install it again to be asked afresh.")
                .font(NexusFont.sans(11))
                .foregroundStyle(NexusColor.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.chipRadius))
    }

    private func row(_ value: BlockList) -> some View {
        HStack(spacing: 12) {
            Button {
                editing = EditTarget(id: value.id)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(value.name)
                            .font(NexusFont.sans(15, weight: .semibold))
                            .foregroundStyle(NexusColor.textPrimary)
                            .lineLimit(1)
                        Text(value.statusText(blockingAvailable: blockingActive))
                            .font(NexusFont.mono(10))
                            .foregroundStyle(isBlockingNow(value) ? NexusColor.accent : NexusColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NexusColor.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // By id, not array position: see BlockListEditorSheet.
            Toggle(value.name, isOn: Binding(
                get: { shieldManager.blockList(id: value.id)?.isEnabled ?? false },
                set: { on in shieldManager.updateBlockList(id: value.id) { $0.isEnabled = on } }
            ))
            .labelsHidden()
            .tint(NexusColor.accent)
        }
        .padding(14)
        .background(NexusColor.surface)
        .overlay(
            RoundedRectangle(cornerRadius: NexusMetrics.cardRadius)
                .stroke(isBlockingNow(value) ? NexusColor.accent.opacity(0.6) : NexusColor.border)
        )
        .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius))
    }

    /// Blocking is genuinely possible: this build has Screen Time and access is approved.
    private var blockingActive: Bool {
        ScreenTimeSupport.isEnabled && shieldManager.accessApproved
    }

    private func isBlockingNow(_ list: BlockList) -> Bool {
        blockingActive && list.isBlocking
    }
}

#if DEBUG
#Preview {
    ZStack {
        NexusColor.background.ignoresSafeArea()
        BlockListsSection()
            .padding()
    }
    .environmentObject(ScreenTimeShieldManager())
}
#endif

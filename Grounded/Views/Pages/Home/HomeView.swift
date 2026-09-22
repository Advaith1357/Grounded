//
//  HomeView.swift
//  Grounded
//
//  Home tab ("The Nexus"). Header is bound strictly to `shieldState` — no more
//  overlapping "SHIELD OFFLINE" badge + separate status sentence from the old
//  design. Settings ("The Kernel") is a sheet off the toolbar gear icon.
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: GroundedViewModel
    /// Switches the root TabView to the Queue tab. Starting a task happens
    /// there (the "+" sheet), not on Home.
    let switchToQueue: () -> Void

    @State private var showSettings = false
    @State private var showDischargeDialog = false

    var body: some View {
        NavigationStack {
            ZStack {
                NexusColor.background.ignoresSafeArea()
                CircuitBackdrop()

                VStack(spacing: 32) {
                    if !viewModel.geminiKeyConfigured {
                        keyMissingBanner
                    }

                    Spacer(minLength: 0)

                    header

                    ZStack {
                        CircuitNode(isCharging: viewModel.shieldState == .grounded)
                        VStack(spacing: 4) {
                            if viewModel.shieldState == .unlocked {
                                Text(Self.timeString(viewModel.unlockRemaining))
                                    .font(NexusFont.mono(44, weight: .heavy))
                                    .foregroundStyle(NexusColor.gold)
                                    .monospacedDigit()
                                Text("REMAINING")
                                    .font(NexusFont.mono(12))
                                    .foregroundStyle(NexusColor.textSecondary)
                            } else {
                                Text("\(viewModel.economy.voltageBalance)")
                                    .font(NexusFont.mono(60, weight: .heavy))
                                    .foregroundStyle(NexusColor.accent)
                                    .monospacedDigit()
                                Text("AVAILABLE")
                                    .font(NexusFont.mono(12))
                                    .foregroundStyle(NexusColor.textSecondary)
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    controls
                }
                .padding(.horizontal, NexusMetrics.screenPadding)
                .padding(.vertical, 24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .tint(NexusColor.accent)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            KernelSettingsSheet()
        }
    }

    private var header: some View {
        Text(viewModel.shieldState == .grounded ? "[ GROUNDED ]" : "[ UNLOCKED ]")
            .font(NexusFont.mono(20, weight: .bold))
            .foregroundStyle(viewModel.shieldState == .grounded ? NexusColor.accent : NexusColor.gold)
    }

    @ViewBuilder
    private var controls: some View {
        switch viewModel.shieldState {
        case .grounded:
            VStack(spacing: 12) {
                NexusPrimaryButton(title: "START TASK", action: switchToQueue)
                NexusSecondaryButton(title: "DISCHARGE") {
                    showDischargeDialog = true
                }
                .confirmationDialog(
                    "Spend Voltage for a break",
                    isPresented: $showDischargeDialog,
                    titleVisibility: .visible
                ) {
                    ForEach([10, 20, 30], id: \.self) { amount in
                        Button("Spend \(amount)V — \(amount) min", action: { viewModel.discharge(amount: amount) })
                            .disabled(viewModel.economy.voltageBalance < amount)
                    }
                    Button("Cancel", role: .cancel) { }
                }
            }
        case .unlocked:
            NexusPrimaryButton(title: "RE-GROUND") {
                viewModel.reGround()
            }
        }
    }

    private var keyMissingBanner: some View {
        Label {
            Text("No Gemini API key yet. Add one in **Settings** (gear icon above).")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .font(.footnote)
        .foregroundStyle(NexusColor.textSecondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.cardRadius))
    }

    private static func timeString(_ interval: TimeInterval) -> String {
        let whole = max(0, Int(interval.rounded(.up)))
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }
}

#if DEBUG
#Preview("Grounded") {
    RootTabView(viewModel: .previewIdle())
}

#Preview("Unlocked") {
    RootTabView(viewModel: .previewUnlocked())
}
#endif

//
//  RootTabView.swift
//  Grounded
//
//  The app's layout shell: a plain 4-tab bar. No full-screen cover, no phase
//  routing — Settings is a sheet off Home, and the mission-flow screens from
//  the previous design are gone entirely.
//

import SwiftUI

struct RootTabView: View {
    @ObservedObject var viewModel: GroundedViewModel
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                destination(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.icon) }
                    .tag(tab)
            }
        }
        .tint(NexusColor.accent)
        .preferredColorScheme(.dark)
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(viewModel: viewModel, switchToQueue: { selectedTab = .queue })
        case .queue:
            QueueView(viewModel: viewModel)
        case .insights:
            InsightsView(viewModel: viewModel)
        case .grid:
            GridView()
        }
    }
}

#if DEBUG
#Preview {
    RootTabView(viewModel: .previewQueue())
}
#endif

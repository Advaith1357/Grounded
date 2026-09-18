//
//  ContentView.swift
//  Grounded
//
//  Root view. Shows the "apps blocked" banner and switches the body on
//  `viewModel.phase`. Plain system styling only.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: GroundedViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isBlocking {
                    blockedBanner
                }
                phaseBody
            }
            .navigationTitle("Grounded")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        HistoryView(entries: viewModel.history)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("History")
                }
            }
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
    }

    private var blockedBanner: some View {
        Text("🔒 APPS BLOCKED (simulated)")
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.yellow.opacity(0.30))
    }

    @ViewBuilder
    private var phaseBody: some View {
        switch viewModel.phase {
        case .idle:
            TaskInputView(viewModel: viewModel)
        case .classifying:
            ProgressView("Working out what proof this needs…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .active:
            ActiveTaskView(viewModel: viewModel)
        case .verifying:
            ProgressView("Sending your proof to Gemini…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .result(let result):
            ProofResultView(result: result) {
                viewModel.acknowledgeResult()
            }
        }
    }
}

#if DEBUG
#Preview("Idle") {
    ContentView(viewModel: .previewIdle())
}

#Preview("Active + blocked") {
    ContentView(viewModel: .previewActive())
}
#endif

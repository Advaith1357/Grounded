//
//  ActiveTaskView.swift
//  Grounded
//
//  Shown while a task is in progress. Suggested proof + why, three ways to
//  submit proof, and the Abandon override.
//

import SwiftUI

struct ActiveTaskView: View {
    @ObservedObject var viewModel: GroundedViewModel

    @State private var showCamera = false
    @State private var showDocumentPicker = false
    @State private var showTimer = false
    @State private var showAbandonConfirm = false

    /// Minutes for a timed session — the AI's suggestion if it suggested a
    /// timer, otherwise a sensible default.
    private var timerMinutes: Int {
        if case .timer(let minutes) = viewModel.activeTask?.suggestedProof {
            return minutes
        }
        return 25
    }

    var body: some View {
        Group {
            if let task = viewModel.activeTask {
                content(for: task)
            } else {
                // Phase changed out from under us; nothing to show.
                Color.clear
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { imageData in
                viewModel.submitPhoto(imageData)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(
                onPick: { pdfData in viewModel.submitPDF(pdfData) },
                onError: { message in viewModel.errorMessage = message }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showTimer) {
            TimerView(minutes: timerMinutes) { elapsed in
                viewModel.completeTimer(elapsed: elapsed, plannedMinutes: timerMinutes)
            }
        }
    }

    @ViewBuilder
    private func content(for task: FocusTask) -> some View {
        Form {
            Section("Task in progress") {
                Text(task.title)
                    .font(.headline)
            }

            Section("Suggested proof") {
                Label(task.suggestedProof.displayName, systemImage: task.suggestedProof.sfSymbol)
                Text(task.suggestedProof.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Submit proof") {
                Button {
                    showCamera = true
                } label: {
                    Label("Take / choose a photo", systemImage: "camera")
                }

                Button {
                    showDocumentPicker = true
                } label: {
                    Label("Choose a PDF", systemImage: "doc.text")
                }

                Button {
                    showTimer = true
                } label: {
                    Label("Start a \(timerMinutes)-minute session", systemImage: "timer")
                }
            }

            Section {
                Button(role: .destructive) {
                    showAbandonConfirm = true
                } label: {
                    Label("Abandon task", systemImage: "xmark.circle")
                }
            } footer: {
                Text("Abandoning unblocks your apps, resets your streak and costs 50 charge.")
            }
        }
        .confirmationDialog(
            "Abandon this task?",
            isPresented: $showAbandonConfirm,
            titleVisibility: .visible
        ) {
            Button("Abandon", role: .destructive) { viewModel.abandonTask() }
            Button("Keep going", role: .cancel) { }
        } message: {
            Text("Your streak resets and you lose 50 charge.")
        }
    }
}

#if DEBUG
#Preview {
    ActiveTaskView(viewModel: .previewActive())
}
#endif

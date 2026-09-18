//
//  TaskInputView.swift
//  Grounded
//
//  The idle screen: state a task, list apps to block, see your progress, Start.
//

import SwiftUI

struct TaskInputView: View {
    @ObservedObject var viewModel: GroundedViewModel

    @State private var title = ""
    @State private var blockedAppsText = ""

    private var canStart: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            if !viewModel.geminiKeyConfigured {
                Section {
                    Label {
                        Text("No Gemini API key yet. Open **Grounded/Support/Secrets.swift** and paste your key from aistudio.google.com, then rebuild. You can still look around, but classifying and verifying won't work.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.footnote)
                }
            }

            Section("What are you going to do?") {
                TextField("e.g. Finish matrices homework", text: $title, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section {
                TextField("e.g. Instagram, TikTok, Safari", text: $blockedAppsText, axis: .vertical)
                    .lineLimit(1...3)
            } header: {
                Text("Apps to block while you work")
            } footer: {
                Text("Separate names with commas or new lines. Blocking is simulated in this build.")
            }

            Section {
                Button("Start") {
                    viewModel.setBlockedApps(from: blockedAppsText)
                    viewModel.startTask(title: title)
                    title = ""
                }
                .disabled(!canStart)
            }

            Section("Progress") {
                LabeledContent("Current streak", value: "\(viewModel.progress.currentStreak)")
                LabeledContent("Longest streak", value: "\(viewModel.progress.longestStreak)")
                LabeledContent("Charge", value: "\(viewModel.progress.totalCharge)")
            }
        }
    }
}

#if DEBUG
#Preview {
    TaskInputView(viewModel: .previewIdle())
}
#endif

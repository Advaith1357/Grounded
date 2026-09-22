//
//  AddTaskSheet.swift
//  Grounded
//
//  The "+" bottom sheet on Queue. Two fields: "Define process" (the task
//  title) and "Proposed proof" (free text describing what the user intends to
//  submit — passed to Gemini as grading context later, not used to pick a
//  proof type up front, since both Photo and PDF are always available).
//

import SwiftUI

struct AddTaskSheet: View {
    @ObservedObject var viewModel: GroundedViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var processText = ""
    @State private var proofText = ""

    private var canCreate: Bool {
        !processText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Define process") {
                    TextField("What are you going to do?", text: $processText, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section {
                    TextField("What will you submit as proof?", text: $proofText, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Proposed proof")
                } footer: {
                    Text("A quick description — Gemini reads it as context when you actually submit a photo or PDF later.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(NexusColor.background)
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewModel.addTask(title: processText, proposedProof: proofText)
                        dismiss()
                    }
                    .disabled(!canCreate)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#if DEBUG
#Preview {
    AddTaskSheet(viewModel: .previewIdle())
}
#endif

//
//  BlockListEditorSheet.swift
//  Grounded
//
//  Edit one block list: rename it, switch it on or off, choose its apps with
//  Apple's picker, or delete it. The picker needs Screen Time authorization
//  (a paid developer account), so on a device without it the list can still
//  be created and named but not filled.
//
//  Every control is bound by the list's id through the shield manager, never
//  by array position: when the list is deleted, SwiftUI keeps evaluating the
//  old controls for a moment, and an index into the shrunken array would crash.
//

import SwiftUI
import FamilyControls

struct BlockListEditorSheet: View {
    let listID: UUID

    @EnvironmentObject private var shieldManager: ScreenTimeShieldManager
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var showDeleteConfirm = false

    private static let maxNameLength = 30

    var body: some View {
        NavigationStack {
            Group {
                if let list = shieldManager.blockList(id: listID) {
                    form(for: list)
                } else {
                    Text("This list no longer exists.")
                        .foregroundStyle(NexusColor.textSecondary)
                }
            }
            .background(NexusColor.background)
            .navigationTitle("Block List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear(perform: tidyName)
    }

    /// A binding to one field of this list that's safe if the list is gone.
    private func binding<Value>(_ keyPath: WritableKeyPath<BlockList, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { shieldManager.blockList(id: listID)?[keyPath: keyPath] ?? fallback },
            set: { newValue in shieldManager.updateBlockList(id: listID) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func form(for list: BlockList) -> some View {
        Form {
            Section("Name") {
                TextField("List name", text: binding(\.name, fallback: ""))
                    .font(NexusFont.mono(15))
                    .onChange(of: list.name) { _, name in
                        if name.count > Self.maxNameLength {
                            shieldManager.updateBlockList(id: listID) { $0.name = String(name.prefix(Self.maxNameLength)) }
                        }
                    }
            }

            Section {
                Toggle("Block these apps", isOn: binding(\.isEnabled, fallback: false))
                Button(list.itemCount == 0 ? "Choose apps" : "Edit apps (\(list.itemCount))") {
                    showPicker = true
                }
                .disabled(!(ScreenTimeSupport.isEnabled && shieldManager.accessApproved))
            } footer: {
                if ScreenTimeSupport.isEnabled && shieldManager.accessApproved {
                    Text("Apps in a switched-on list are blocked only when you open them, and only while you're grounded — not during a Discharge break.")
                } else if ScreenTimeSupport.isEnabled {
                    Text("Turn on Screen Time access first (the button is at the top of the Queue), then you can pick apps.")
                } else {
                    Text("Picking apps is paused in this build: it needs Screen Time, which needs a paid developer account. You can still name and organize your lists.")
                }
            }

            Section {
                Button("Delete list", role: .destructive) { showDeleteConfirm = true }
            }
        }
        .scrollContentBackground(.hidden)
        .familyActivityPicker(isPresented: $showPicker, selection: binding(\.selection, fallback: FamilyActivitySelection()))
        .confirmationDialog("Delete \"\(list.name)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete list", role: .destructive) {
                shieldManager.removeBlockList(id: listID)
                dismiss()
            }
            Button("Keep it", role: .cancel) { }
        }
    }

    /// A blank name would leave an unlabeled row in the Queue.
    private func tidyName() {
        guard let name = shieldManager.blockList(id: listID)?.name else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed != name {
            shieldManager.updateBlockList(id: listID) { $0.name = trimmed.isEmpty ? "Untitled list" : trimmed }
        }
    }
}

#if DEBUG
#Preview {
    let manager = ScreenTimeShieldManager()
    return BlockListEditorSheet(listID: manager.blockLists.first?.id ?? UUID())
        .environmentObject(manager)
}
#endif

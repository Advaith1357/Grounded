//
//  KernelSettingsSheet.swift
//  Grounded
//
//  "The Kernel" — Settings, now a `.sheet` off Home's toolbar gear icon, not a
//  tab or a full-screen route. No Parental Diagnostic Pin UI (deleted per the
//  refactor brief).
//
//  The API key field never displays the real value (SecureField masks it
//  regardless, but this also skips loading it into state at all) — a footer
//  reports whether a key is already saved instead. "Circuit Breaker" is
//  stored for later; nothing enforces it yet since that needs a background
//  scheduler, out of scope here.
//

import SwiftUI

struct KernelSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput = ""
    @State private var showSavedConfirmation = false

    @AppStorage(SettingsKey.mockAIMode) private var mockAIMode = false
    @AppStorage(SettingsKey.nightlyLockoutTime) private var lockoutTimeInterval = SettingsKey.defaultLockoutInterval

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Paste your Gemini API key", text: $apiKeyInput)
                        .font(NexusFont.mono(14))
                    Button("Save to Keychain") {
                        KeychainStore.saveGeminiAPIKey(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
                        apiKeyInput = ""
                        showSavedConfirmation = true
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("The API Vault")
                } footer: {
                    Text(KeychainStore.loadGeminiAPIKey() != nil
                         ? "A key is saved in the Keychain and will be used for all Gemini calls."
                         : "No key saved yet — falls back to the placeholder in Secrets.swift.")
                }

                Section {
                    Toggle("Mock AI Mode", isOn: $mockAIMode)
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Bypasses the Gemini network call and auto-approves every submission — for UI testing without spending real API calls.")
                }

                Section {
                    DatePicker("Circuit Breaker", selection: lockoutTimeBinding, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Nightly Lockout")
                } footer: {
                    Text("The time the shield should force-ground overnight. Stored here for later — enforcing it needs a background scheduler, not wired up in this build.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(NexusColor.background)
            .navigationTitle("The Kernel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Key Saved", isPresented: $showSavedConfirmation) {
                Button("OK", role: .cancel) { }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var lockoutTimeBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSinceReferenceDate: lockoutTimeInterval) },
            set: { lockoutTimeInterval = $0.timeIntervalSinceReferenceDate }
        )
    }

}

#if DEBUG
#Preview {
    KernelSettingsSheet()
}
#endif

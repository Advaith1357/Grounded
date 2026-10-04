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
//  reports whether a key is already saved instead. Changing "Circuit Breaker"
//  reschedules the nightly DeviceActivity window that enforces it.
//

import SwiftUI
import FamilyControls

struct KernelSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var shieldManager: ScreenTimeShieldManager

    @State private var showPicker = false
    @AppStorage(SettingsKey.friendsServerURL) private var friendsServerURL = SettingsKey.defaultFriendsServerURL

    @State private var apiKeyInput = ""
    @State private var showSavedConfirmation = false

    @AppStorage(SettingsKey.mockAIMode) private var mockAIMode = false
    @AppStorage(SettingsKey.nightlyLockoutTime) private var lockoutTimeInterval = SettingsKey.defaultLockoutInterval
    @AppStorage(SettingsKey.nightlyWakeTime) private var wakeTimeInterval = SettingsKey.defaultWakeInterval

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Choose Apps to Block") { showPicker = true }
                } header: {
                    Text("Shielded Apps")
                } footer: {
                    Text(selectionSummary)
                }

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
                    TextField("http://127.0.0.1:8787", text: $friendsServerURL)
                        .font(NexusFont.mono(14))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("The Grid Server")
                } footer: {
                    Text("Where friends, statuses and nudges are stored. Run Server/server.py on your Mac, or point this at a deployed copy.")
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
                    DatePicker("Wake Time", selection: wakeTimeBinding, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Nightly Lockout")
                } footer: {
                    Text(lockoutFooter)
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
            .familyActivityPicker(isPresented: $showPicker, selection: $shieldManager.selection)
        }
        .preferredColorScheme(.dark)
    }

    private var selectionSummary: String {
        let selection = shieldManager.selection
        let count = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
        return count == 0
            ? "Nothing selected — grounding won't block anything yet."
            : "\(count) item\(count == 1 ? "" : "s") shielded while grounded."
    }

    private var lockout: NightlyLockout {
        NightlyLockout(lockoutTimeInterval: lockoutTimeInterval, wakeTimeInterval: wakeTimeInterval)
    }

    private var lockoutFooter: String {
        let base = "From the Circuit Breaker time until your wake time, the shield is forced on and Discharge is unavailable."
        if lockout.windowMinutes == 0 {
            return base + " Both times match, so there is no lockout."
        }
        if !lockout.canBeScheduledInBackground {
            return base + " This window is under 15 minutes, which iOS can't enforce while Grounded is closed."
        }
        return base
    }

    private var lockoutTimeBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSinceReferenceDate: lockoutTimeInterval) },
            set: {
                lockoutTimeInterval = $0.timeIntervalSinceReferenceDate
                shieldManager.scheduleNightlyLockout(lockout)
            }
        )
    }

    private var wakeTimeBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSinceReferenceDate: wakeTimeInterval) },
            set: {
                wakeTimeInterval = $0.timeIntervalSinceReferenceDate
                shieldManager.scheduleNightlyLockout(lockout)
            }
        )
    }
}

#if DEBUG
#Preview {
    KernelSettingsSheet()
        .environmentObject(ScreenTimeShieldManager())
}
#endif

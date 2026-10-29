//
//  OnboardingView.swift
//  Grounded
//
//  First-run questionnaire, shown full-screen until it's finished. Nothing is
//  assigned for the user: each step asks, and the answers become real settings:
//    account   -> a friends-server account (name + friend code)
//    habits    -> how much they use their phone, and their age (for the stats)
//    numbers   -> what that adds up to (illustrative; assumptions shown)
//    goal      -> the daily limit in minutes, which becomes the Queue's daily load
//    blockList -> their first block list, named, with its apps
//    friends   -> invites sent from their contacts, with their friend code
//    finish    -> notification permission, then in
//

import SwiftUI
import FamilyControls
import UserNotifications

struct OnboardingView: View {
    let onFinish: () -> Void

    @EnvironmentObject private var friends: FriendsViewModel
    @EnvironmentObject private var shieldManager: ScreenTimeShieldManager

    @AppStorage(SettingsKey.phoneHoursPerDay) private var hoursPerDay = 5.0
    @AppStorage(SettingsKey.userAge) private var age = 20
    @AppStorage(SettingsKey.dailyLimitMinutes) private var limitMinutes = DailyLimit.defaultMinutes

    @State private var step: OnboardingStep = .account
    @State private var name = ""

    @State private var listName = ""
    @State private var createdListID: UUID?
    @State private var draftSelection = FamilyActivitySelection()
    @State private var showAppPicker = false

    @State private var invitees: [Invitee] = []
    @State private var showContactPicker = false
    @State private var showMessageComposer = false

    private static let maxNameLength = 24
    private static let listSuggestions = ["Social", "Games", "Video", "News"]

    private var stats: PhoneHabitStats { PhoneHabitStats(hoursPerDay: hoursPerDay, age: age) }

    private var draftItemCount: Int {
        draftSelection.applicationTokens.count + draftSelection.categoryTokens.count + draftSelection.webDomainTokens.count
    }

    // MARK: - Layout

    var body: some View {
        ZStack {
            NexusColor.background.ignoresSafeArea()
            CircuitBackdrop()

            VStack(spacing: 0) {
                header
                ScrollView {
                    content
                        .padding(.horizontal, NexusMetrics.screenPadding)
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                footer
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STEP \(step.number) OF \(OnboardingStep.count)")
                .font(NexusFont.mono(11))
                .foregroundStyle(NexusColor.textSecondary)
            ProgressView(value: step.progress)
                .tint(NexusColor.accent)
        }
        .padding(.horizontal, NexusMetrics.screenPadding)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .account: accountStep
        case .habits: habitsStep
        case .numbers: numbersStep
        case .goal: goalStep
        case .blockList: blockListStep
        case .friends: friendsStep
        case .finish: finishStep
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            NexusPrimaryButton(title: primaryTitle, isEnabled: primaryEnabled, action: primaryAction)
            if step.previous != nil {
                Button("BACK") { goBack() }
                    .font(NexusFont.mono(12, weight: .semibold))
                    .foregroundStyle(NexusColor.textSecondary)
                    .frame(height: 36)
            }
        }
        .padding(.horizontal, NexusMetrics.screenPadding)
        .padding(.bottom, 12)
    }

    // MARK: - Primary button

    private var primaryTitle: String {
        switch step {
        case .account: return friends.isJoined ? "CONTINUE" : (friends.isBusy ? "CREATING…" : "CREATE ACCOUNT")
        case .habits: return "CONTINUE"
        case .numbers: return "I WANT TO CHANGE THAT"
        case .goal: return "SET MY LIMIT"
        case .blockList: return "CONTINUE"
        case .friends: return invitees.isEmpty ? "SKIP FOR NOW" : "CONTINUE"
        case .finish: return "START GROUNDED"
        }
    }

    private var primaryEnabled: Bool {
        switch step {
        case .account: return friends.isJoined || (!trimmed(name).isEmpty && !friends.isBusy)
        case .blockList: return !trimmed(listName).isEmpty
        default: return true
        }
    }

    private func primaryAction() {
        switch step {
        case .account:
            if friends.isJoined {
                advance()
            } else {
                Task {
                    await friends.join(name: name)
                    if friends.isJoined { advance() }
                }
            }
        case .blockList:
            commitBlockList()
            advance()
        case .finish:
            Task {
                // Asked here, with context, rather than at launch.
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                onFinish()
            }
        default:
            advance()
        }
    }

    private func advance() {
        guard let next = step.next else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    private func goBack() {
        guard let previous = step.previous else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = previous }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Step 1: account

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Make your account")
            subtitle("Friends see this name on The Grid, and you get a friend code to share. It's how you'll keep each other off your phones.")

            if let profile = friends.profile {
                NexusCard {
                    VStack(alignment: .leading, spacing: 6) {
                        label("SIGNED IN AS")
                        Text(profile.name)
                            .font(NexusFont.sans(20, weight: .bold))
                            .foregroundStyle(NexusColor.textPrimary)
                        label("FRIEND CODE  \(profile.code)")
                    }
                }
            } else {
                TextField("Display name", text: $name)
                    .font(NexusFont.mono(16))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onChange(of: name) { _, value in
                        if value.count > Self.maxNameLength { name = String(value.prefix(Self.maxNameLength)) }
                    }
                    .padding(14)
                    .background(NexusColor.surface)
                    .overlay(RoundedRectangle(cornerRadius: NexusMetrics.chipRadius).stroke(NexusColor.border))
                    .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.chipRadius))

                if let message = friends.errorMessage {
                    Text(message)
                        .font(NexusFont.sans(12))
                        .foregroundStyle(Color(hex: 0xEF4444))
                    Button("Continue without an account for now") { advance() }
                        .font(NexusFont.sans(13, weight: .semibold))
                        .foregroundStyle(NexusColor.accent)
                    Text("You can create it later from The Grid tab.")
                        .font(NexusFont.sans(11))
                        .foregroundStyle(NexusColor.textSecondary)
                }
            }
        }
    }

    // MARK: - Step 2: habits

    private var habitsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("How much do you use your phone?")
            subtitle("Your best guess for an average day. Be honest — nobody's watching.")

            VStack(spacing: 6) {
                Text(PhoneHabitStats.hoursText(hoursPerDay))
                    .font(.system(size: 56, weight: .heavy, design: .monospaced))
                    .foregroundStyle(NexusColor.accent)
                label("PER DAY")
            }
            .frame(maxWidth: .infinity)

            Slider(value: $hoursPerDay, in: 0.5...16, step: 0.5)
                .tint(NexusColor.accent)

            Divider().overlay(NexusColor.border)

            Stepper(value: $age, in: 10...100) {
                Text("Your age: \(age)")
                    .font(NexusFont.mono(15, weight: .semibold))
                    .foregroundStyle(NexusColor.textPrimary)
            }
            Text("Used only for the numbers on the next screen. It stays on this phone.")
                .font(NexusFont.sans(11))
                .foregroundStyle(NexusColor.textSecondary)
        }
    }

    // MARK: - Step 3: the numbers

    private var numbersStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("At this rate…")
            subtitle("Here's what \(PhoneHabitStats.hoursText(hoursPerDay)) a day adds up to.")

            statCard(
                value: String(format: "%.0f%%", stats.percentOfWakingLife),
                caption: "of your waking hours are spent on your phone"
            )
            statCard(
                value: String(format: "%.0f days", stats.daysPerYear),
                caption: "every year, counted in full 24-hour days"
            )
            statCard(
                value: PhoneHabitStats.durationText(years: stats.yearsOfRemainingLife),
                caption: "of your remaining life, if nothing changes"
            )

            Text("Rough maths: assumes \(Int(PhoneHabitStats.wakingHoursPerDay)) waking hours a day and living to \(PhoneHabitStats.assumedLifeExpectancy).")
                .font(NexusFont.sans(11))
                .foregroundStyle(NexusColor.textSecondary)
        }
    }

    // MARK: - Step 4: the goal

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("What do you want to limit it to?")
            subtitle("This becomes your daily load: the most screen time you allow yourself in a day. You earn it back one task at a time.")

            VStack(spacing: 6) {
                Text(DailyLimit.label(minutes: limitMinutes))
                    .font(.system(size: 48, weight: .heavy, design: .monospaced))
                    .foregroundStyle(NexusColor.accent)
                label("PER DAY MAXIMUM")
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                ForEach(DailyLimit.presets, id: \.self) { minutes in
                    Button {
                        limitMinutes = minutes
                    } label: {
                        Text(DailyLimit.label(minutes: minutes))
                            .font(NexusFont.mono(12, weight: .bold))
                            .foregroundStyle(limitMinutes == minutes ? NexusColor.background : NexusColor.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(limitMinutes == minutes ? NexusColor.accent : NexusColor.surface)
                            .overlay(RoundedRectangle(cornerRadius: NexusMetrics.chipRadius).stroke(NexusColor.accent.opacity(0.5)))
                            .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.chipRadius))
                    }
                }
            }

            Stepper(value: $limitMinutes, in: DailyLimit.range, step: DailyLimit.step) {
                Text("Fine-tune")
                    .font(NexusFont.mono(13))
                    .foregroundStyle(NexusColor.textSecondary)
            }

            NexusCard(highlighted: true) {
                let saved = stats.yearsSaved(goalMinutes: limitMinutes)
                if saved > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        label("THAT GIVES YOU BACK")
                        Text(PhoneHabitStats.durationText(years: saved))
                            .font(NexusFont.mono(24, weight: .heavy))
                            .foregroundStyle(NexusColor.accent)
                        Text("of your life — down to \(String(format: "%.0f%%", PhoneHabitStats.percentOfWakingLife(hoursPerDay: Double(limitMinutes) / 60))) of your waking hours.")
                            .font(NexusFont.sans(12))
                            .foregroundStyle(NexusColor.textSecondary)
                    }
                } else {
                    Text("That's already at or below how much you use now. A solid line to hold.")
                        .font(NexusFont.sans(13))
                        .foregroundStyle(NexusColor.textPrimary)
                }
            }
        }
    }

    // MARK: - Step 5: first block list

    private var blockListStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Block your first list")
            subtitle("Name it, then pick the apps that pull you in. They're only blocked when you open one, and you can make more lists later.")

            TextField("List name", text: $listName)
                .font(NexusFont.mono(16))
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(14)
                .background(NexusColor.surface)
                .overlay(RoundedRectangle(cornerRadius: NexusMetrics.chipRadius).stroke(NexusColor.border))
                .clipShape(RoundedRectangle(cornerRadius: NexusMetrics.chipRadius))

            HStack(spacing: 8) {
                ForEach(Self.listSuggestions, id: \.self) { suggestion in
                    Button(suggestion) { listName = suggestion }
                        .font(NexusFont.mono(12, weight: .semibold))
                        .foregroundStyle(NexusColor.accent)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .overlay(Capsule().stroke(NexusColor.accent.opacity(0.5)))
                }
            }

            appsSection
        }
        .familyActivityPicker(isPresented: $showAppPicker, selection: $draftSelection)
    }

    @ViewBuilder
    private var appsSection: some View {
        if !ScreenTimeSupport.isEnabled {
            note("Picking apps is paused in this build — it needs Screen Time. Your list is saved by name for later.")
        } else {
            NexusSecondaryButton(
                title: draftItemCount == 0 ? "CHOOSE APPS" : "EDIT APPS (\(draftItemCount))",
                action: chooseApps
            )
            if draftItemCount > 0 {
                note("\(draftItemCount) selected. You can change this any time in the Queue.")
            } else if !shieldManager.accessApproved {
                note("Blocking uses Apple's Screen Time, so Grounded will ask for access when you tap this.")
            }
        }
    }

    private func chooseApps() {
        Task {
            if !shieldManager.accessApproved { await shieldManager.requestAccess() }
            if shieldManager.accessApproved { showAppPicker = true }
        }
    }

    /// Creates the list on the way out of this step (or updates it if they
    /// came back and changed their mind).
    private func commitBlockList() {
        let listTitle = trimmed(listName)
        guard !listTitle.isEmpty else { return }
        let id = createdListID ?? shieldManager.addBlockList(named: listTitle)
        createdListID = id
        shieldManager.updateBlockList(id: id) {
            $0.name = listTitle
            $0.selection = draftSelection
        }
    }

    // MARK: - Step 6: friends

    private var friendsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Bring friends along")
            subtitle("It's easier to put the phone down together. Pick people from your contacts and send them your code.")

            if let profile = friends.profile {
                NexusCard {
                    VStack(alignment: .leading, spacing: 6) {
                        label("YOUR FRIEND CODE")
                        Text(profile.code)
                            .font(.system(size: 30, weight: .heavy, design: .monospaced))
                            .tracking(4)
                            .foregroundStyle(NexusColor.accent)
                    }
                }

                NexusSecondaryButton(title: invitees.isEmpty ? "CHOOSE FROM CONTACTS" : "CHANGE SELECTION") {
                    showContactPicker = true
                }

                if !invitees.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(invitees) { invitee in
                            Text("• \(invitee.name)")
                                .font(NexusFont.sans(14))
                                .foregroundStyle(NexusColor.textPrimary)
                        }
                    }

                    if MessageComposer.canSendText {
                        NexusPrimaryButton(title: "SEND INVITES BY MESSAGE") {
                            showMessageComposer = true
                        }
                    } else {
                        ShareLink(item: inviteText(code: profile.code)) {
                            Label("Share your invite", systemImage: "square.and.arrow.up")
                                .font(NexusFont.sans(14, weight: .semibold))
                        }
                    }
                }

                note("Grounded never sees or stores your contacts. Picking just fills in a text message, and nothing is sent until you press Send.")
            } else {
                note("You skipped creating an account, so there's no friend code to share yet. Create one from The Grid tab and invite people there.")
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPicker { invitees = $0; showContactPicker = false }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showMessageComposer) {
            MessageComposer(
                recipients: invitees.map(\.phone),
                body: inviteText(code: friends.profile?.code ?? "")
            ) { showMessageComposer = false }
            .ignoresSafeArea()
        }
    }

    private func inviteText(code: String) -> String {
        "Join me on Grounded — it helps us both spend less time on our phones. My friend code is \(code)."
    }

    // MARK: - Step 7: finish

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("You're all set")
            subtitle("Here's what you set up.")

            NexusCard {
                VStack(alignment: .leading, spacing: 14) {
                    summaryRow("ACCOUNT", friends.profile?.name ?? "Not yet")
                    summaryRow("DAILY LIMIT", DailyLimit.label(minutes: limitMinutes))
                    summaryRow("FIRST LIST", createdListName)
                    summaryRow("INVITES", invitees.isEmpty ? "None yet" : "\(invitees.count) chosen")
                }
            }

            note("Next, Grounded will ask to send notifications — that's how it reminds you when a break is about to end.")
        }
    }

    private var createdListName: String {
        guard let id = createdListID else { return "None" }
        return shieldManager.blockList(id: id)?.name ?? "None"
    }

    private func summaryRow(_ heading: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(heading)
            Text(value)
                .font(NexusFont.sans(16, weight: .semibold))
                .foregroundStyle(NexusColor.textPrimary)
        }
    }

    // MARK: - Small pieces

    private func title(_ text: String) -> some View {
        Text(text)
            .font(NexusFont.sans(28, weight: .bold))
            .foregroundStyle(NexusColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func subtitle(_ text: String) -> some View {
        Text(text)
            .font(NexusFont.sans(14))
            .foregroundStyle(NexusColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(NexusFont.mono(11))
            .foregroundStyle(NexusColor.textSecondary)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(NexusFont.sans(12))
            .foregroundStyle(NexusColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statCard(value: String, caption: String) -> some View {
        NexusCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 34, weight: .heavy, design: .monospaced))
                    .foregroundStyle(NexusColor.accent)
                Text(caption)
                    .font(NexusFont.sans(13))
                    .foregroundStyle(NexusColor.textSecondary)
            }
        }
    }
}

#if DEBUG
#Preview {
    OnboardingView(onFinish: {})
        .environmentObject(FriendsViewModel.preview(joined: false))
        .environmentObject(ScreenTimeShieldManager())
}
#endif

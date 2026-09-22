# Grounded

A focused, single-threaded MVP. You define a task and describe what proof
you'll submit, work on it, then submit a photo or PDF; Gemini judges whether it
genuinely shows the task is done. Every verified task pays a flat **10V**
(1V = 1 minute of screen time). Spend Voltage via **Discharge** to unlock your
phone for a timed break; **Re-Ground** ends it early. While your queue is
empty, a trickle charge passively banks +1V every 5 minutes, capped at 20V.

**Real screen-time blocking is stubbed in this build** — see
[What's stubbed](#5-whats-stubbed).

---

## 1. Prerequisites

- macOS with **Xcode 16 or newer** (built and tested on Xcode 26).
- **XcodeGen** (`brew install xcodegen`) — only needed if you want to regenerate
  the project file. `Grounded.xcodeproj` is already generated and git-ignored.
- An iPhone running **iOS 17.0 or newer** if you want to run on device.

The project targets **iOS 17.0**, SwiftUI, Swift 5 language mode, and uses **no
third-party packages**.

---

## 2. Paste your Gemini API key

Two ways to set a key, checked in this order:

1. **The Kernel** (Settings, gear icon on Home) → **The API Vault** → paste
   your key → **Save to Keychain**. This is the real, intended path — the key
   never touches source control and is read at runtime from the iOS Keychain
   (`Grounded/Services/KeychainStore.swift`).
2. **`Grounded/Support/Secrets.swift`** (git-ignored) — a fallback for local
   dev so the app works out of the box before you've opened Settings once.

### Get a key

1. Go to <https://aistudio.google.com>.
2. Sign in with a Google account.
3. Click **Get API key** (left sidebar) → **Create API key**.
4. Copy the key (a long string starting with `AIza…`).

### The Secrets.swift fallback

```swift
enum Secrets {
    static let geminiAPIKey = "AIza...your real key..."
}
```

Recreate it from the template if needed:

```bash
cp Grounded/Support/Secrets.example.swift Grounded/Support/Secrets.swift
```

While no Keychain key is saved and this is still `PASTE_YOUR_KEY_HERE`, the app
**runs fine** but shows a notice on Home, and every Gemini call fails with a
clear "no API key" message instead of crashing. **Mock AI Mode** (Kernel →
Diagnostics) bypasses the network call entirely and auto-approves every
submission — useful for UI testing without a key at all.

> **Model name:** `GeminiService.swift` has `private let model = "gemini-3.6-flash"`.
> Google rotates model names — `gemini-2.0-flash` and `gemini-2.5-flash` both
> 404'd during development. If API calls start returning **HTTP 404**, the
> error message now echoes the server's response, which has named the current
> replacement both times so far; confirm at <https://aistudio.google.com>.

---

## 3. Run on the iOS Simulator

Open the project:

```bash
open Grounded.xcodeproj
```

In Xcode: pick an iPhone simulator in the scheme/destination dropdown (top bar),
then press **▶︎ Run** (Cmd-R).

### From the command line

```bash
xcodebuild -scheme Grounded -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Or build without booting anything:

```bash
xcodebuild -scheme Grounded -destination 'generic/platform=iOS Simulator' build
```

**Camera on the Simulator:** there is no camera, so **Take Photo** automatically
falls back to the photo library. Drag a few images into the simulator first
(Photos app) so you have something to pick.

---

## 4. Run on your physical iPhone (free Apple ID)

You do **not** need a paid Apple Developer account.

1. Plug in your iPhone. Trust the computer if prompted.
2. In Xcode, open **Grounded** target → **Signing & Capabilities** tab.
3. **Team:** click the dropdown → **Add an Account…** → sign in with your Apple ID.
   Then select the personal team that appears (shown as *"Your Name (Personal Team)"*).
4. Leave **Automatically manage signing** checked.
5. **If signing fails** with *"failed to register bundle identifier"* or
   *"com.grounded.app is not available"*: the bundle ID is taken. Change it to
   something unique — e.g. `com.yourname.grounded` — in the same tab
   (**Bundle Identifier** field), or in `project.yml` under
   `PRODUCT_BUNDLE_IDENTIFIER` and re-run `xcodegen generate`.
6. Select your iPhone as the run destination (top bar) and press **Run**.
7. **First launch will be blocked** by iOS with *"Untrusted Developer"*. On the
   iPhone: **Settings → General → VPN & Device Management → [your Apple ID] →
   Trust**. Then launch the app again.

### Free Apple ID limits (important)

- Apps signed with a free account **stop launching after 7 days**. Re-run from
  Xcode to refresh for another 7 days.
- You can have at most **3 apps** sideloaded with a free account at once.
- Some entitlements (including **Family Controls**, which real screen-time
  enforcement needs) are **not available** on a free account at all.

---

## 5. What's stubbed

### Screen-time enforcement — `Grounded/Services/ShieldManager.swift`

Real enforcement needs Apple's **Family Controls** entitlement
(`FamilyControls` / `ManagedSettings` / `DeviceActivity`), which needs a paid
Apple Developer account — the $100/year fee this build explicitly defers. So
this build **does not import any of those three frameworks** and **does not
add the Family Controls capability**.

Instead:

| Piece | This build | With the entitlement |
| --- | --- | --- |
| `protocol ShieldManager` | unchanged | unchanged |
| Concrete shield | `MockShieldManager` — flips `state` (`.grounded` / `.unlocked`), prints to console | new `ScreenTimeShieldManager: ShieldManager` using `ManagedSettingsStore` |
| Wiring | `GroundedApp` passes `MockShieldManager()` into `GroundedViewModel` | `GroundedApp` passes `ScreenTimeShieldManager()` instead |

**Exactly what changes when the entitlement arrives:** add the Family Controls
capability, add a new file conforming to `ShieldManager`, and change one line
in `GroundedApp.swift`. Nothing in the models, the view model, `GeminiService`,
or any view needs to change — they all talk only to `ShieldManager` /
`GroundedViewModel.shieldState`.

### Nightly "Circuit Breaker" lockout

The Kernel's `DatePicker` stores a time-of-day (`UserDefaults`, key
`settings.nightlyLockoutTime`), but nothing enforces it yet — that needs a
background scheduler (`BGTaskScheduler` or local notifications), which is out
of scope for this pass.

---

## 6. Manual test script

Do this on the **Simulator**. For Path A you need either a real Gemini key
(see [§2](#2-paste-your-gemini-api-key)) or **Mock AI Mode** switched on in the
Kernel — the latter needs no key and spends no API calls.

### Path A — define, queue, and verify a task

1. Launch the app → **Home**, `[ GROUNDED ]`, 0V.
2. Tap the tab bar → **Queue** → empty state → tap the **+** FAB.
3. Fill **Define process** ("Finish matrices homework") and **Proposed proof**
   ("A photo of the worked page") → **Add**.
4. Queue now shows one **Active** card (yellow border) with **Take Photo** /
   **Upload PDF** buttons.
5. Tap **Take Photo** → photo library opens (no camera on Sim) → pick any photo.
6. "Verifying…" briefly, then a banner: ✅ **Verified — +10V** with feedback
   (or, in Mock AI Mode, the canned "automatically approved" message).
7. Voltage balance is now 10 on **Home**, **Insights**, and **The Grid**'s
   Completed count is 1.

### Path B — single-threaded queue

1. Add two tasks via the **+** FAB without resolving the first.
2. Queue shows task #1 as the yellow **Active** card with submit buttons, and
   task #2 below it, greyed out, labeled **Standby** — no buttons, not tappable.
3. Swipe left on the Standby row → **Remove** deletes it outright (no
   confirmation; it was never attempted).
4. Resolve or abandon the Active task (see Path C) — if another task follows,
   it becomes the new Active card automatically.

### Path C — abandon (manual override, no penalty)

1. With a task Active, tap the small **✕** in its card's top-right corner →
   confirm **Abandon (streak resets)**.
2. Task disappears from the queue. **The Grid** would list it under history as
   abandoned; the current streak resets to 0. Unlike the previous build, this
   costs **no Voltage** — nothing in this economy spec calls for a penalty.

### Path D — Discharge / Re-Ground

1. Get some Voltage banked (Path A, or wait for trickle charge — see Path E).
2. On **Home**, tap **Discharge** → a dialog offers **Spend 10V — 10 min**,
   **20V — 20 min**, **30V — 30 min** (options costing more than your balance
   are disabled).
3. Pick one → header flips to `[ UNLOCKED ]`, the dial shows a countdown, and
   the console logs `[MockShieldManager] state -> .unlocked`.
4. Tap **RE-GROUND** to end the break early — header flips back, countdown
   clears — or just wait for the countdown to hit zero, which re-grounds
   automatically.

### Path E — trickle charge

1. Make sure the queue is empty.
2. **Insights** → the Trickle Buffer card reads **CHARGING**. Leave the app
   foregrounded (or background and return later) — every 5 minutes idle adds
   +1V, up to a hardware cap of 20V, after which it reads **CHARGING** but the
   bar stops moving until you spend some down.
3. Add a task → the buffer card switches to **PAUSED** — the generator only
   runs while the queue is empty.

### Path F — Mock AI Mode & the Kernel

1. Home → gear icon → **The Kernel**.
2. Toggle **Mock AI Mode** on. Every future photo/PDF submission now
   auto-approves with no network call — confirm by watching Xcode's console
   for the absence of any `CFNetwork` request log lines during a submission.
3. **The API Vault**: paste a key → **Save to Keychain** → the footer updates
   to confirm a key is saved. This takes priority over `Secrets.swift`.
4. **Circuit Breaker**: set a time — it persists across relaunches (not yet
   enforced; see [§5](#5-whats-stubbed)).

---

## 7. Regenerating the Xcode project

`project.yml` is the source of truth. After changing it (or adding/moving source
files):

```bash
xcodegen generate
```

`Grounded.xcodeproj` is listed in `.gitignore` because it's fully derived from
`project.yml`.

---

## 8. Project layout — the MVP pivot

This is a from-scratch information-architecture rewrite of the earlier
"Nexus" 6-frame redesign, which the product brief described as suffering from
"scope creep and contradictory UI states." Only three surfaces were specified
in detail — Home, Queue, and Settings (as a sheet, not a tab) — with Insights
and The Grid named as tabs but not otherwise detailed; see
[the notes on those two](#insights-and-the-grid-content-not-specified) below.

```
Grounded/
  App/              GroundedApp.swift — entry point, shows RootTabView
  Navigation/        AppTab (4 tabs: Home/Queue/Insights/Grid), RootTabView (tab bar + error alert)
  DesignSystem/      NexusTheme (colors/fonts), CircuitBackdrop (decorative wires),
                     CircuitNode (Home's radiating-trace ring), NexusComponents (buttons/cards)
  Models/            FocusTask (title + proposedProof + status), ProofType (photo/pdf only),
                     ProofSubmission, VerificationResult (flat 10V reward)
  Services/          GeminiService (actor, verify-only — no classify), PDFTextExtractor,
                     ShieldManager (+ MockShieldManager), KeychainStore, TaskStore
  ViewModels/        GroundedViewModel (@MainActor ObservableObject — queue, economy, shield, trickle timer)
  Views/
    Pages/
      Home/           HomeView (state-bound header, CircuitNode dial, Start Task / Discharge / Re-Ground)
      Queue/           QueueView (Active card + Standby rows), AddTaskSheet
      Insights/        InsightsView (Voltage balance, trickle buffer gauge, streak, completion rate)
      Grid/            GridView (completed count, streak, weekly chart, recent activity)
      Kernel/          KernelSettingsSheet (API Vault, Mock AI Mode, Circuit Breaker) — a `.sheet`, not a tab
    Shared/           CameraPicker, DocumentPicker (UIKit picker wrappers)
  Support/            Secrets.swift (ignored), Secrets.example.swift, Info.plist
project.yml           XcodeGen spec
```

### What changed from the previous ("Nexus") build

- **No more AI classification step.** The old `classify(taskTitle:)` call and
  `ProofType.timer` case are gone. Both Photo and PDF are always available for
  the Active task; the user's own "Proposed proof" text is passed to Gemini as
  grading context instead.
- **No more phase state machine or full-screen mission flow.** Active/Standby
  live inline in Queue; a verification result shows as a dismissible banner,
  not a separate screen.
- **Flat reward, no stars.** Every pass is worth exactly 10V regardless of
  confidence (confidence still decides pass/fail via the same 70% threshold).
  The old confidence-tiered star system is gone.
- **Shield and queue are decoupled.** Completing, abandoning, or queuing tasks
  never touches the shield. The shield only changes via Discharge / Re-Ground
  / the auto-timeout — a deliberate simplification from the old
  "blocked-while-a-task-is-active" model.
- **API key can live in the Keychain now**, entered via Settings, not just
  compiled into `Secrets.swift`.

### Insights and The Grid: content not specified

The refactor brief named these two tabs but never described their content
(only Home, Queue, and the Kernel sheet got full specs). Reasonable calls made
to fill the gap, easy to redirect:

- **The Grid** — activity history, adapted from the previous build's Power Grid
  screen: completed-task count, streak, a 7-day Voltage chart, recent activity.
- **Insights** — introspection on the Voltage economy itself: current balance,
  the trickle-charge buffer's progress toward its 20V cap, longest streak, and
  completion rate. Distinct from Grid's history focus.

### A known Simulator-testing limitation (not an app bug)

Tapping *inside* `.sheet`-presented `Form` content (the Kernel's toggle, the
Add Task sheet's text fields) doesn't register through this session's
simulator-automation tooling, while everything else — tab bar, buttons on
full-screen views, the FAB, `.confirmationDialog` — works reliably. Swiping
down dismisses a stuck sheet. This was verified as a tooling quirk, not a code
issue: every affected control (`Toggle`, `TextField`, `SecureField`) is
completely standard SwiftUI with no custom gesture handling, and the same
sheets render their content correctly on screen — only synthetic taps into
their body fail to land. Worth trying on a real device or via Xcode's own
Simulator window if this needs deeper interactive testing than screenshots and
tab/button verification can offer.

### Data & persistence

Plain JSON in the app's Documents directory (`tasks.json`, `submissions.json`,
`economy.json`), plus proof files under `Documents/proofs/<uuid>.jpg|pdf`. No
SwiftData, no Core Data. To wipe state, delete the app from the simulator/device.

### Economy rules (in `VerificationResult.swift` / `GroundedViewModel.swift`)

- Pass threshold: **confidence ≥ 70**.
- Reward: **flat +10V** per verified task. 1V = 1 minute.
- Trickle charge: **+1V every 5 minutes** while the queue is empty, hardware
  **cap of 20V**. Computed from wall-clock elapsed time (not a background
  timer), so it catches up correctly across relaunches.
- Discharge: spend 10/20/30V for a break of that many minutes; auto
  re-grounds when the countdown ends, or tap Re-Ground to end it early.
- Abandon: streak → 0, **no Voltage penalty** (the old build's −50 charge
  penalty is gone — nothing in this refactor's spec calls for one).

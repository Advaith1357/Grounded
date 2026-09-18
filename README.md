# Grounded

A proof-based focus app. You state a task, an AI decides what kind of proof would
show it's done, you submit that proof (photo, PDF, or a timed session), and Gemini
judges whether the proof actually demonstrates completion. A verified proof
"restores current" and (eventually) unblocks your distracting apps.

**App blocking is stubbed in this build** — see [What's stubbed](#whats-stubbed).

---

## 1. Prerequisites

- macOS with **Xcode 16 or newer** (built and tested on Xcode 26).
- **XcodeGen** (`brew install xcodegen`) — only needed if you want to regenerate
  the project file. `Grounded.xcodeproj` is already generated and committed-ignored.
- An iPhone running **iOS 17.0 or newer** if you want to run on device.

The project targets **iOS 17.0**, SwiftUI, Swift 5 language mode, and uses **no
third-party packages**.

---

## 2. Paste your Gemini API key

Nothing in this repo contains a key, and `Grounded/Support/Secrets.swift` is
git-ignored.

### Get a key

1. Go to <https://aistudio.google.com>.
2. Sign in with a Google account.
3. Click **Get API key** (left sidebar) → **Create API key**.
4. Copy the key (a long string starting with `AIza…`).

### Put it in the app

The repo ships `Grounded/Support/Secrets.swift` already containing a **placeholder**.
Open it and replace the placeholder:

```swift
enum Secrets {
    static let geminiAPIKey = "AIza...your real key..."
}
```

If you ever need to recreate it from scratch:

```bash
cp Grounded/Support/Secrets.example.swift Grounded/Support/Secrets.swift
```

Then rebuild. While the key is still `PASTE_YOUR_KEY_HERE`, the app **runs fine** but
shows an orange notice on the home screen, and every Gemini call fails with a clear
"no API key" message instead of crashing.

> **Model name:** `GeminiService.swift` has `private let model = "gemini-2.0-flash"`.
> Google rotates model names. If API calls start returning **HTTP 404**, that
> constant is the first thing to change — confirm the current name at
> <https://aistudio.google.com>.

---

## 3. Run on the iOS Simulator

Open the project:

```bash
open Grounded.xcodeproj
```

In Xcode: pick an iPhone simulator in the scheme/destination dropdown (top bar),
then press **▶︎ Run** (Cmd-R).

### From the command line

The spec's example used `iPhone 15`; this Mac doesn't have that runtime installed.
Use a simulator you actually have (list them with
`xcrun simctl list devices available`):

```bash
xcodebuild -scheme Grounded -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Or build without booting anything:

```bash
xcodebuild -scheme Grounded -destination 'generic/platform=iOS Simulator' build
```

**Camera on the Simulator:** there is no camera, so the "Take / choose a photo"
button automatically falls back to the photo library. Drag a few images into the
simulator first (Photos app) so you have something to pick.

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
- Some entitlements (including **Family Controls**, which real app-blocking needs)
  are **not available** on a free account at all.

---

## 5. What's stubbed

### App blocking — `Grounded/Services/AppBlocker.swift`

Real blocking needs Apple's **Family Controls** entitlement
(`FamilyControls` / `ManagedSettings` / `DeviceActivity`). That entitlement is
unavailable on a free Personal Team, so this build **does not import any of those
frameworks** and **does not add the Family Controls capability**.

Instead:

| Piece | This build | With the entitlement |
| --- | --- | --- |
| `protocol AppBlocker` | unchanged | unchanged |
| Concrete blocker | `MockAppBlocker` — flips `isBlocking`, prints to console | new `ScreenTimeBlocker: AppBlocker` using `ManagedSettingsStore` + `FamilyActivitySelection` |
| Chosen apps | user types names as free text | system `FamilyActivityPicker` returns opaque `ApplicationToken`s |
| Wiring | `GroundedApp` passes `MockAppBlocker()` into `GroundedViewModel` | `GroundedApp` passes `ScreenTimeBlocker()` instead |
| UI | shows `🔒 APPS BLOCKED (simulated)` banner | same banner, minus "(simulated)" |

**Exactly what changes when the entitlement arrives:**

1. Add the **Family Controls** capability to the target (and request it from Apple
   for distribution).
2. Add a new file `Grounded/Services/ScreenTimeBlocker.swift` conforming to the
   existing `AppBlocker` protocol.
3. Change **one line** in `GroundedApp.swift`:
   `GroundedViewModel(blocker: ScreenTimeBlocker())`.
4. Replace the free-text app-names `TextField` in `TaskInputView.swift` with a
   `familyActivityPicker(...)` sheet.
5. Drop "(simulated)" from the banner string in `ContentView.swift`.

Nothing in the models, the view model's flow, `GeminiService`, `TaskStore`, or the
result/history screens needs to change.

### Timer verification

Timer proofs are judged **locally** (no API call): pass if elapsed ≥ the suggested
duration; confidence scales linearly with the fraction completed. This is intended
behaviour, not a stub.

---

## 6. Manual test script

Do this on the **Simulator** with a **real Gemini key** pasted in. Before you
start, open the Photos app in the simulator and drag in: one photo of some
handwritten/worked pages, and one clearly-unrelated photo (a landscape, say). Have
a text-based PDF somewhere reachable by the Files app (AirDrop or drag one onto the
simulator).

### Path A — photo proof (happy path)

1. Launch the app. Home screen shows the task field and a Progress section
   (streak 0, charge 0).
2. Type **"Finish matrices homework"**. In the block-list field type
   **"Instagram, Safari"**. Tap **Start**.
3. Spinner: *"Working out what proof this needs…"*. Then the active-task screen
   appears and the yellow **🔒 APPS BLOCKED (simulated)** banner is pinned to the top.
   (Check the Xcode console for a `[MockAppBlocker] block()` line.)
4. Suggested proof should be **Photo** with a one-line explanation.
5. Tap **Take / choose a photo** → the photo library opens (no camera on Sim) →
   pick the photo of worked pages.
6. Spinner: *"Sending your proof to Gemini…"*. Then the result screen:
   ✅ **Proof verified**, a confidence %, 1–3 stars, and specific feedback.
7. Tap **Continue** → back to the home screen. Banner is gone. Progress now shows
   streak 1 and charge 50 (or 75 if confidence ≥ 90).
8. Tap the **clock icon** (top-right) → History shows the task as **Verified**
   with its stars and feedback.

### Path B — photo proof (rejection + retry)

1. From home, start **"Tidy my desk"**, tap **Start**.
2. On the active screen tap **Take / choose a photo** → pick the **unrelated
   landscape** photo.
3. Result screen: ❌ **Not verified**, low confidence, feedback naming what's wrong.
   Note the copy: *"Your task is still active."*
4. Tap **Continue** → you're back on the **active-task** screen (not home), banner
   still up.
5. Tap **Take / choose a photo** again → pick the **worked-pages** photo → this
   time it verifies. Progress increments.

### Path C — PDF proof

1. Start **"Write history essay"**. If the classifier suggests something other than
   PDF, that's fine — all three submit buttons are always available.
2. Tap **Choose a PDF** → Files picker → select a **text-based** PDF.
3. Result screen shows a verdict from Gemini based on the extracted text.
   - If you feed it a **scanned/image-only** PDF instead, you get an immediate
     ❌ with feedback telling you to submit it as a photo — **no API call is made**.

### Path D — timer proof

1. Start a task the classifier will treat as effort-based, e.g.
   **"Meditate"** or **"Read 10 pages"**. Suggested proof: **Timed Session** with
   a duration.
2. Tap **Start a N-minute session** → the timer sheet opens and auto-starts;
   the screen stays awake.
3. Tap **Pause**, wait, tap **Resume** — the countdown accounts for the paused gap.
4. Tap **Complete** *before* the timer runs out → result screen shows a
   **shortfall** confidence (e.g. 40%) and, because it's below 70, ❌ **Not
   verified**; task stays active.
5. Start the session again and let it run to 00:00 → it auto-completes,
   ✅ **verified** at 100%, charge + streak increment.

### Path E — abandon (the override)

1. Start any task so the banner is up and streak > 0 from earlier paths.
2. On the active screen tap **Abandon task** → confirm.
3. Banner disappears, you're on home. Progress: **streak reset to 0**, **charge
   reduced by 50** (never below 0). History lists the task as **Abandoned**.

### Path F — no key / bad key

1. Set `Secrets.swift` back to `PASTE_YOUR_KEY_HERE`, rebuild.
2. Home screen shows the orange "No Gemini API key yet" notice.
3. Start a task → the classify step falls through to a default 25-minute timer
   suggestion; submitting a photo or PDF surfaces a clear
   *"No Gemini API key set…"* alert rather than crashing.

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

## 8. Project layout

```
Grounded/
  App/            GroundedApp.swift — entry point, wires the view model
  Models/         FocusTask, ProofType, ProofSubmission, VerificationResult
  Services/       GeminiService (actor), PDFTextExtractor, AppBlocker (+ mock), TaskStore
  ViewModels/     GroundedViewModel (@MainActor ObservableObject, phase state machine)
  Views/          ContentView + one file per screen + Camera/Document pickers
  Support/        Secrets.swift (ignored), Secrets.example.swift, Info.plist
project.yml       XcodeGen spec
```

### Data & persistence

Plain JSON in the app's Documents directory (`tasks.json`, `submissions.json`,
`progress.json`), plus proof files under `Documents/proofs/<uuid>.jpg|pdf`. No
SwiftData, no Core Data. To wipe state, delete the app from the simulator/device.

### Reward rules (in `VerificationResult.swift`)

- Pass threshold: **confidence ≥ 70**.
- Charge: **+50** per verified task, **+25** bonus at confidence ≥ 90.
- Stars: **1** for a pass, **2** at confidence ≥ 80, **3** at confidence ≥ 90.
- Abandon: streak → 0, charge −50 (clamped at 0).

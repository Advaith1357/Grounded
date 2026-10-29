# Grounded

A focused, single-threaded MVP. You define a task and describe what proof
you'll submit, work on it, then submit a photo or PDF; Gemini judges whether it
genuinely shows the task is done. Every verified task pays a flat **10V**
(1V = 1 minute of screen time). Spend Voltage via **Discharge** to unlock your
phone for a timed break; **Re-Ground** ends it early. While your queue is
empty, a trickle charge passively banks +1V every 5 minutes, capped at 20V.

Blocking uses Apple's Screen Time APIs and needs a paid developer account and a
real device — see [§5](#5-screen-time-enforcement-real-needs-a-paid-account).

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

You do **not** need a paid Apple Developer account. The **default** project is
built for exactly this: it requests no Family Controls, no App Groups, and
embeds no Screen Time extensions, so a free Apple ID can sign it. **App
blocking is paused** in this build (the Queue's block-list screens say so);
everything else works: the focus loop and Voltage, the Queue, the Circuit
Breaker lockout, the friends system, and the **one-minute break warning**.

1. Plug in your iPhone. Trust the computer if prompted.
2. `cp Config/Local.xcconfig.example Config/Local.xcconfig`, then set
   `GROUNDED_BUNDLE_ID` to something unique (e.g. `com.yourname.grounded`) —
   a generic ID is usually already registered by someone else. Delete the
   `DEVELOPMENT_TEAM` line unless you have a paid team; you'll pick your free
   team in Xcode.
3. Run `xcodegen generate`, open the project, and in the **Grounded** target →
   **Signing & Capabilities** choose **Team:** click the dropdown → **Add an
   Account…** → your Apple ID, then the *"Your Name (Personal Team)"* entry.
   Leave **Automatically manage signing** on. You should see **no**
   capabilities listed.
4. If signing fails with *"failed to register bundle identifier"*, pick a
   different `GROUNDED_BUNDLE_ID` and regenerate.
5. Select your iPhone as the run destination and press **Run**. Allow
   notifications when asked.
6. **First launch will be blocked** by iOS with *"Untrusted Developer"*. On the
   iPhone: **Settings → General → VPN & Device Management → [your Apple ID] →
   Trust**. Then launch the app again.
7. **Friends server:** `127.0.0.1` means the phone itself, so Settings → The
   Grid Server needs a hosted server or your Mac's address (section 6).

If Xcode still lists **Family Controls** or **App Groups**, the project was
last generated in Screen Time mode: run plain `xcodegen generate` again.

### Testing the one-minute warning

Start a break from Home (the smallest is 10V = 10 minutes) and leave the app.
About 9 minutes in you'll get **"[ 1 MINUTE LEFT ] Your break is almost
over…"**, even with Grounded closed. Re-Grounding early cancels it. It's a local
notification, so no account or server is involved.

### Free Apple ID limits (important)

- Apps signed with a free account **stop launching after 7 days**. Re-run from
  Xcode to refresh for another 7 days.
- You can have at most **3 apps** sideloaded with a free account at once.
- **Family Controls** (real screen-time enforcement) is **not available** on a
  free account at all — that's why blocking is paused here; see section 5.

---

## 5. Screen-time enforcement (real, needs a paid account)

**Paused by default.** The default project leaves all of this out so it builds
on a free Apple ID. To turn it on once you have a paid account:

```bash
xcodegen generate --spec project.screentime.yml   # Screen Time build
xcodegen generate                                  # back to the default
```

`project.screentime.yml` is the default project plus the `SCREEN_TIME` compile
flag (`Shared/ScreenTimeSupport.swift` — without it every Screen Time call is
skipped), the Family Controls and App Group capabilities, and the three
extensions below.

Grounded uses Apple's Screen Time APIs (`FamilyControls`, `ManagedSettings`,
`ManagedSettingsUI`, `DeviceActivity`), which require the **Family Controls
entitlement** and a paid Apple Developer account. Simulator builds compile and
launch (the Screen Time permission prompt even appears), but approving it needs
a Screen Time passcode, and picking apps and the shield itself only work on a
**real device** with the entitlement.

| Piece | File |
| --- | --- |
| `protocol ShieldManager` + `MockShieldManager` (previews/tests only) | `Grounded/Services/ShieldManager.swift` |
| Real shield; persists the block lists to the App Group | `Grounded/Services/ScreenTimeShieldManager.swift` |
| Authorization, notification permission, Circuit Breaker scheduling on launch | `Grounded/App/GroundedApp.swift` |
| Block lists (create, switch on/off, pick apps) | `Grounded/Views/Pages/Queue/BlockListsSection.swift`, `BlockListEditorSheet.swift`, model in `Shared/BlockLists.swift` |
| Shared by app + monitor: `ShieldState`, saved selection, `ShieldApplier`, activity names, schedule math | `Shared/` |
| Interceptor screen (what a blocked app shows) | `ShieldConfiguration/` |
| Interceptor button: posts a "open Grounded" notification and closes the app | `ShieldAction/` |
| Re-grounds when a break ends or the Circuit Breaker opens, even if Grounded isn't running | `DeviceActivityMonitor/` |
| Entitlements (Family Controls + an App Group named `group.` + your bundle ID) | `Config/*.entitlements`, declared in `project.yml` |

### Block lists

The **Queue** tab starts with a "BLOCK LISTS" section. Each list is a named
set of apps, categories and websites with its own on/off switch. Your first list
is created during [onboarding](#onboarding); rename, delete, or add more with
**New list**. Tap a list to pick its apps with Apple's picker.

Only lists that are switched **on** and contain something are shielded, and a
shielded app is only intercepted when you open it: iOS shows the interceptor
screen over that app. Nothing else on the phone is touched, and during a
Discharge break nothing is blocked. (Apple's picker hands the app opaque
tokens, so Grounded can't pre-fill lists with named apps.)

Nothing pops up when you open a blocked app until the developer account is in:
no normal app can tell that you opened another one, so the interceptor screen
is the only mechanism and it needs the Screen Time entitlement.

### Circuit Breaker

From the **Circuit Breaker** time until the **Wake Time** (both set in the
Kernel sheet; defaults 10:00 PM and 6:00 AM), the shield is forced on and
**Discharge is disabled**. If a break is running when the window opens it is cut
short and the unused minutes are refunded. Enforced in-app by the view model's
1-second tick and, when the app isn't running, by a repeating `DeviceActivity`
schedule. `DeviceActivity` needs a window of at least 15 minutes, so a shorter
one is still enforced in-app (and the Kernel sheet says so) but not in the
background.

### Break warning (works without a developer account)

Starting a Discharge break schedules a local notification for one minute before
it ends — **"[ 1 MINUTE LEFT ] Your break is almost over. Wrap up and get off
your apps."** — and Re-Grounding early cancels it. It's the only notification
tied to time passing; there's deliberately nothing that fires just because you
closed the app. (Whatever pops up when you open a *blocked* app is the Screen
Time shield screen itself, which needs the entitlement.)

### Breaks that expire while the app is closed

`discharge` also registers a one-off `DeviceActivity` window ending when the
break does, so the monitor extension re-applies the shield on time. (`DeviceActivity`
schedules must span 15+ minutes, so a 10V break's window starts early rather
than ending late. Schedules are minute-resolution.) The app reconciles its own
state on next launch.

### When your developer account arrives

1. `cp Config/Local.xcconfig.example Config/Local.xcconfig`, put your team ID
   in it, then `xcodegen generate`.
2. Build to a real device. Xcode's automatic signing registers the App IDs
   (app + 3 extensions) and your App Group (`group.` + your bundle ID).
3. In the Queue tab, open a block list, choose its apps, and make sure it's
   switched on; then Discharge / Re-Ground and watch those apps get blocked
   and unblocked.
4. Things worth checking on-device, since the Simulator can't: the break-end
   and Circuit Breaker schedules actually fire the monitor, and the shield's
   "Remind Me in Grounded" button.

---

## 6. The Grid: friends server

The Grid tab is a real social layer: join with a display name, get a 6-character
friend code, add friends by their code, see who is `[ GROUNDED ]` or
`[ ON A BREAK ]`, and Zap a friend to nudge them. It needs **no Apple Developer
account** — it talks to a small server in `Server/` over plain HTTP(S).

**The server only exists while something is running it.** Nothing starts it for
you, so with no server up the app reports "Can't reach the friends server". Two
ways to run one:

1. **On your Mac, for development.**

   ```bash
   python3 Server/server.py                 # 127.0.0.1:8787, database in Server/grounded.db
   python3 Server/server.py --host 0.0.0.0  # also reachable from a phone on your Wi-Fi
   python3 -m unittest Server/test_server.py   # server tests (both transports)
   ```

   Python 3.9+ standard library only — nothing to install. This works for the
   Simulator as is. A **physical phone** can't use `127.0.0.1` (that is the phone
   itself): use your Mac's address (`http://192.168.x.x:8787`, same Wi-Fi, and
   allow Grounded under Settings → Privacy & Security → Local Network) — or,
   better, host it, below.
2. **Hosted for free, always on** — see the next section.

In the app, the address lives in **Settings → The Grid Server**; **Test
connection** tells you what's wrong in plain words. The default is
`http://127.0.0.1:8787`, or your hosted server if you set `FRIENDS_SERVER_HOST`
in `Config/Local.xcconfig` (so it survives reinstalls).

### Hosting the friends server for free

Friend lists are tiny (about 300 bytes per account; nudges are deleted after 7
days; registration stops at 1,000 accounts), so any free host with a persistent
disk works. **PythonAnywhere's free plan** fits: one always-on web app at
`yourname.pythonanywhere.com`, 512 MiB of disk, and web apps aren't subject to
its daily CPU allowance. The catch: **a free web app expires after one month**
unless you renew it (see step 7). Their terms change, so check
[pythonanywhere.com](https://www.pythonanywhere.com) before relying on it.

1. Sign up for a free account (your username becomes the address,
   `https://USERNAME.pythonanywhere.com`).
2. **Consoles → Bash**, then `git clone https://github.com/Advaith1357/Grounded.git`.
   (If the repo is private, skip this and upload `Server/server.py` to
   `/home/USERNAME/Grounded/Server/` from the **Files** tab instead.)
3. **Web → Add a new web app → Manual configuration**, newest Python 3 offered
   (3.10 or later).
4. On the Web tab open the **WSGI configuration file**, replace everything with
   this (swap in your username), and save:

   ```python
   import os, sys

   HOME = "/home/USERNAME"
   sys.path.insert(0, HOME + "/Grounded/Server")

   os.environ["GROUNDED_DB"] = HOME + "/grounded.db"
   # Their disk is a network filesystem, where SQLite's default WAL mode can fail.
   os.environ["GROUNDED_JOURNAL_MODE"] = "delete"

   from server import application  # noqa: E402
   ```
5. Press the green **Reload** button, then open
   `https://USERNAME.pythonanywhere.com/health` — it should show `{"ok": true}`.
6. Point the app at it: put `FRIENDS_SERVER_HOST = USERNAME.pythonanywhere.com`
   in `Config/Local.xcconfig`, run `xcodegen generate`, rebuild — or paste
   `https://USERNAME.pythonanywhere.com` into Settings → The Grid Server. Hit
   **Test connection**.
7. **Once a month**, open the Web tab and press the **Run until 1 month from
   today** button (they email a reminder). Miss it and the server goes offline
   until you do. Back up `grounded.db` from the Files tab now and then.

To update after changing the server code: `git pull` in a Bash console, then
Reload. Hosts with no monthly renewal exist (e.g. Cloudflare Workers + D1), but
they'd need the server rewritten in JavaScript.

How it works:

- **Identity** — joining creates an account and a bearer token (kept in the
  Keychain; the server stores only its hash). There are no passwords.
- **Friends** — entering someone's code makes you friends *both ways at once*;
  the code itself is the invitation, so only share it with people you want
  seeing your status. Long-press a friend to remove them.
- **Status** — the app reports `.grounded` / `.unlocked` (with the break's end
  time) whenever the shield changes. A friend whose break has run out reads as
  grounded even if their app is closed.
- **Nudges** — one per friend per minute. They arrive the next time the
  recipient has Grounded open (the app polls every 8 seconds while the Grid
  tab is showing and every 30 seconds elsewhere); delivering to a closed app
  would need push notifications, which need a paid developer account.
- **Going public** — `server.py` itself speaks plain HTTP; a host such as
  PythonAnywhere supplies HTTPS in front of it. It validates input, rate-limits
  nudges and caps total accounts, but isn't hardened for the open internet
  beyond that: anyone who finds the address can create an account.

---

## Onboarding

A fresh install opens a seven-step full-screen setup instead of assigning
defaults:

1. **Account** — a display name; registers with the friends server and gives you
   a friend code. If the server can't be reached you can continue without one
   and join later from The Grid.
2. **Habits** — your daily phone hours and age.
3. **The numbers** — what that rate adds up to: % of waking hours, days per
   year, and years of your remaining life. (Rough maths: 16 waking hours a day,
   life expectancy 80 — see `PhoneHabitStats`.)
4. **Limit** — your daily maximum in minutes. This is the Queue's
   "DAILY LOAD: x / y MIN" cap and can be changed later in Settings.
5. **First block list** — name it and (with Screen Time) pick its apps. This is
   where the Screen Time permission is first requested.
6. **Friends** — choose people from your contacts and send them your friend
   code by text. It uses Apple's contact picker, so Grounded never gets access
   to your address book, and nothing is sent until you press Send.
7. **Finish** — a summary, then the notification permission prompt.

Settings → **Replay onboarding** runs it again. Nothing is deleted by replaying.
The contact picker and message composer can't be exercised in the Simulator
(no Messages); try them on a device.

---

## 7. Manual test script

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
   the selected apps are un-shielded.
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
4. **Circuit Breaker**: set a time — it persists across relaunches. While the
   window is open (until your Wake Time) Home's Discharge button is disabled and says
   so; see [§5](#5-screen-time-enforcement-real-needs-a-paid-account).

---

## 8. Regenerating the Xcode project

`project.yml` (the default, free-account build) and `project.screentime.yml`
(adds Screen Time) are the source of truth. After changing either, or adding or
moving source files, regenerate whichever one you build with:

```bash
xcodegen generate                                  # default
xcodegen generate --spec project.screentime.yml    # Screen Time build
```

`Grounded.xcodeproj` is listed in `.gitignore` because it's fully derived from
those specs. Both modes write the same file, so regenerate when you switch.

---

## 9. Project layout — the MVP pivot

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
                     Friends/ (FriendsService, FriendsModels — friends-server client),
                     ShieldManager (+ MockShieldManager), ScreenTimeShieldManager,
                     NightlyLockout, GroundingNotifier + BreakWarningPlan (the one-minute
                     break warning), KeychainStore, TaskStore
  ViewModels/        GroundedViewModel (@MainActor ObservableObject — queue, economy, shield, trickle timer),
                     FriendsViewModel (identity, friends, nudges, polling)
  Views/
    Pages/
      Home/           HomeView (state-bound header, CircuitNode dial, Start Task / Discharge / Re-Ground)
      Queue/           QueueView (block lists + Active card + Standby rows), BlockListsSection,
                       BlockListEditorSheet, AddTaskSheet
      Insights/        InsightsView (activity heatmap, balance, weekly Voltage chart, recent feed, streak, completion rate)
      Grid/            GridView (join, friend code, add friend, live statuses, nudge)
      Kernel/          KernelSettingsSheet (API Vault, Grid server, Mock AI Mode, Circuit Breaker) — a `.sheet`, not a tab
    Shared/           CameraPicker, DocumentPicker (UIKit picker wrappers)
  Support/            Secrets.swift (ignored), Secrets.example.swift, Info.plist
Shared/               Code compiled into the app (and the monitor extension in the Screen Time build)
ShieldConfiguration/  Extension: the interceptor screen        (Screen Time build only)
ShieldAction/         Extension: the interceptor button        (Screen Time build only)
DeviceActivityMonitor/ Extension: background re-grounding      (Screen Time build only)
Config/               Entitlements, Base.xcconfig, Local.xcconfig.example
Server/               Friends server (server.py, runs standalone or as a WSGI app) and its tests
Tests/                Logic tests (schedule + Circuit Breaker math, break warning, block lists, friends client)
project.yml           XcodeGen spec (default: free-account build, blocking paused)
project.screentime.yml  Adds the Screen Time capabilities, flag and extensions (paid account)
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

### Insights and The Grid

- **Insights** — analytics: a GitHub-style activity heatmap built from real
  completion dates, the Voltage balance, the weekly Voltage chart, recent
  Voltage feeds, longest streak, and completion rate.
- **The Grid** — the friends list described in [§6](#6-the-grid-friends-server).

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

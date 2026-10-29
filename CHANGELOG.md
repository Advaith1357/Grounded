# Changelog

All notable changes to Grounded, newest first. Versions 0.1.0–0.3.0 correspond to
the original commits; 0.4.0 onward were built after them and are published as the
commit series that follows `a671da7` (one commit per entry, then a docs commit).

Grounded is a proof-based focus app: you earn **Voltage** (1V = 1 minute of screen
time) by completing tasks verified by Gemini, and spend it on timed breaks.

## [0.7.0] — Onboarding and a user-set daily limit

### Added
- **Seven-step onboarding** shown on first launch: account → phone habits → "at
  this rate…" stats → daily limit → first block list → friends → finish.
  (`Grounded/Views/Onboarding/`, `OnboardingFlow.swift`)
- **Phone-habit stats** (`PhoneHabitStats`): share of waking hours, days per year,
  and years of remaining life spent on the phone, plus the years a lower limit
  gives back. Assumes 16 waking hours a day and living to 80; the screen says so.
- **Daily limit** (15–720 min in 15-min steps) chosen in onboarding and editable in
  Settings. It is the ceiling in the Queue header, `DAILY LOAD: x / y MIN`.
- **Friends from contacts**: Apple's contact picker (no Contacts permission) plus a
  pre-filled text carrying your friend code. Nothing is sent until you press Send.
- Settings → **Replay onboarding**.
- `TESTING.md`: 20 test cases, with Simulator results and phone-only cases.

### Changed
- The Screen Time prompt now appears at the block-list step, and the notification
  prompt at the end of onboarding, instead of at launch.
- The pre-made Social/Games/Video lists are gone; your first list is created and
  named in onboarding.
- If the friends server can't be reached, onboarding offers "Continue without an
  account for now"; you can join later from The Grid.
- On launch the app restores shielding only if Screen Time was already approved.

### Tests
- `PhoneHabitStatsTests`, `OnboardingFlowTests`.

## [0.6.0] — Break warning, visible trickle charge, readable AI feedback

### Added
- **One-minute warning**: a `[ 1 MINUTE LEFT ]` local notification one minute
  before a break ends (`BreakWarningPlan`, `LocalGroundingNotifier`), with a
  foreground presenter so it also shows while the app is open.
- **Trickle schedule** (`TrickleSchedule`): +1V every 5 minutes while the queue is
  empty, capped at 20V, with catch-up after the app was closed.
- An always-visible **trickle banner** on the Queue: "Trickle Charge Active: 3V /
  20V — next +1V in 2:09", or "paused" while a task is active.
- **Expandable, selectable Gemini feedback** so a long verdict or error is no
  longer cut off after two lines.

### Changed
- `GroundedViewModel` takes a `GroundingNotifier`, so tests and previews use a no-op.

### Removed
- The test notification that fired whenever the app was closed. A notification is
  only meant to warn you about a blocked app (see 0.5.0) or a break ending.

### Fixed
- Passive charge looked broken: it was pausing correctly while the queue had a
  task, and the Home dial hides +1V during a break. The banner makes both visible.

### Tests
- `BreakWarningTests`, `TrickleScheduleTests`.

## [0.5.0] — Screen Time on a real iPhone, and block lists

### Added
- **Two build modes.** The default `project.yml` is a free-account build with
  blocking paused so it installs on any iPhone; `project.screentime.yml` adds the
  Family Controls entitlement, App Group and the three extensions
  (`xcodegen generate --spec project.screentime.yml`). `ScreenTimeSupport.isEnabled`
  gates every Screen Time call at compile time.
- **Block lists** in the Queue tab: any number of named lists, each with its own
  on/off switch and Apple's app picker (`BlockLists`, `BlockListsSection`,
  `BlockListEditorSheet`).
- **Screen Time access** request flow with a "Turn on Screen Time access" button
  and an access state the UI reacts to.
- **Shield screen**: `[ DISCHARGE REQUIRED ]`, with a button that posts a
  "Tap to open Grounded" notification. The shield action can't open the app
  itself (an iOS limit), so the button is labelled "Remind Me in Grounded".
- **Break-end re-grounding** by the DeviceActivity monitor, using a one-off
  schedule padded to the 15-minute minimum window.
- Signing, device-install and data-inspection workflow documented in the README
  (`xcodebuild … -allowProvisioningUpdates`, `devicectl install/launch`).
- App Group derived from your bundle ID (`group.<bundle id>`); `GROUNDED_BUNDLE_ID`
  and `DEVELOPMENT_TEAM` live in the gitignored `Config/Local.xcconfig`.

### Changed
- Blocking is per-app and only when you open a blocked app; nothing is blocked
  during a Discharge break.

### Fixed
- Deleting a block list while its editor was open crashed with an out-of-range
  index; every control now binds by list id.
- The Circuit Breaker end time formatted with the device time zone instead of the
  configured calendar's, so it differed by machine.

### Tests
- `BlockListTests`.

## [0.4.0] — Friends server you can actually host

### Added
- **Free hosting**: the server now exposes a WSGI `application`, and reads
  `GROUNDED_DB`, `GROUNDED_JOURNAL_MODE` and `GROUNDED_MAX_USERS`. README documents
  hosting on PythonAnywhere's free plan, including the monthly renewal.
- **Registration cap** (default 1,000 accounts) so a public address can't grow
  the database without bound.
- `FRIENDS_SERVER_HOST` (in `Config/Local.xcconfig`) is baked into the build, so a
  phone talks to your hosted server from first launch.
- **Plain-language connection errors** (`FriendsError.unreachable`) and a
  **Test connection** button in Settings, and a clear message when a saved account
  is no longer valid on the server.

### Fixed
- Friend IDs were percent-encoded twice, breaking friend lookups.
- `[::1]` wasn't recognised as loopback, so the "start the server" hint was wrong.
- A phone can't use `127.0.0.1`; the app now explains that.

### Tests
- Server suite extended from 17 to 23 test methods (43 runs); `FriendsTests` extended.

## [0.3.0] — 2026-10-04 — Screen Time, Circuit Breaker, real friends (`2e1d204`)

### Added
- `ScreenTimeShieldManager` with an interceptor screen, a shield-action extension
  and a DeviceActivity monitor extension that re-ground when a break ends or the
  nightly Circuit Breaker opens, even with the app closed.
- **Circuit Breaker** with a configurable wake time; Discharge is disabled overnight.
- **The Grid** is a real social layer: join with a display name, add friends by
  code, see live `[ GROUNDED ]` / `[ ON A BREAK ]` status, send nudges. Backed by a
  dependency-free Python + SQLite server in `Server/`.
- Logic tests for schedule maths and the friends client; a server test suite.

### Changed
- Home restyled to a dashed-trace PCB node with capsule buttons.

## [0.2.0] — 2026-09-22 — Single-threaded Voltage economy (`8ed8fd6`)

### Added
- Flat **10V per verified task**, spendable on timed breaks; passive trickle charge.
- **Single-threaded queue**: only the first task is active, the rest stand by.
- Four-tab shell: Home / Queue / Insights / The Grid, with Settings as a sheet.
- "Nexus" dark circuit-board design system.
- Insights: heatmap, weekly chart and activity feed.

### Changed
- Replaced the photo/PDF/timer-classified proof flow with the focused loop above.
- Home redrawn from a hand sketch: a 16-trace PCB fan-out with an animated
  charge/discharge pulse.

## [0.1.0] — 2026-09-18 — Scaffold (`67eec42`)

### Added
- SwiftUI / iOS 17 app where Gemini judges whether submitted photo or PDF proof
  shows a task is done. Blocking stubbed behind an `AppBlocker` protocol while the
  Family Controls entitlement wasn't available.
- Keychain-stored API key with a gitignored `Secrets.swift` fallback.

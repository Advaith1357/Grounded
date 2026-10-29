# Grounded — 20 test cases

**Sim** = what was run in the iOS Simulator (2026-10-22). **Phone** = for you to run
on the iPhone; tick the box. Cases marked *phone only* can't be exercised in the
Simulator (no camera, no Screen Time tokens, no Messages/Contacts, no real
background execution).

Before you start on the phone: the friends server has to be hosted (see
"Setting up the account" in the chat reply / README §6), or the account cases
(2, 16, 17, 18) will hit the "can't reach the server" path.

| # | Case | Steps → expected | Sim | Phone |
|---|------|------------------|-----|-------|
| 1 | Fresh install opens onboarding | Delete + reinstall → onboarding step 1 of 7 appears; **no** permission prompt at launch | PASS | ☐ |
| 2 | Account creation | Step 1: type a name (≤ 24 chars), Create Account → step 2; a 6-character friend code appears on step 6 | PASS (local server) | ☐ |
| 3 | Server unreachable | With the server stopped: Settings → Test connection shows a plain-language error. Onboarding step 1 shows the error and "Continue without an account for now" | PARTIAL — Test-connection error PASS; onboarding fallback button not re-exercised this run | ☐ |
| 4 | Stats maths | 5 h/day, age 20 → 31% of waking hours, 76 days/year, 12.5 years. Goal 1 h → "gives you back 10.0 years", 6% | PASS | ☐ |
| 5 | Daily limit | Pick 1 h in onboarding → Queue header "DAILY LOAD: 0 / 60 MIN". Settings stepper +1 → 75 MIN (15-min steps, 15–720) | PASS | ☐ |
| 6 | First block list | Step 5: Continue disabled with empty name; tapping the "Social" chip fills it; list appears in Queue after onboarding | PASS | ☐ |
| 7 | Add a task | Queue → + → fill both fields → Add. Card shows ACTIVE; trickle banner changes to "paused" | PASS — but see finding A | ☐ |
| 8 | Submit proof, earn Voltage | Take Photo / Upload PDF on a real task → Gemini verdict → +10V, streak +1, daily load rises. Also: a failing proof shows an expandable, selectable message | *phone only* (sim camera can't capture) | ☐ |
| 9 | Abandon a task | ✕ on the active card → confirm → task gone, balance unchanged, streak 0, trickle resumes | PASS | ☐ |
| 10 | Trickle charge | Empty queue: +1V per 5 min, cap 20V; banner countdown; paused while a task is active | PASS (12 min backdated → +2V; 60 min at 19V → 20V cap) | ☐ |
| 11 | Discharge | Home → Discharge → Spend 10V → state UNLOCKED, countdown from 10:00, balance −10 | PASS — see finding B | ☐ |
| 12 | Break expiry | Let a break run out (app open) → returns to `[ GROUNDED ]`, balance kept | PASS (20 s break) — closed-app expiry is phone only | ☐ |
| 13 | One-minute warning | Start a break, background the app → notification "[ 1 MINUTE LEFT ]" 60 s before the end | Logic unit-tested (`BreakWarningTests`); delivery *phone only* | ☐ |
| 14 | Circuit Breaker | Inside the 10 PM–wake window Discharge is disabled and Home says "CIRCUIT BREAKER ACTIVE UNTIL …". Move wake time earlier → Discharge enabled | PASS (2:16 AM sim clock: disabled; wake 1:00 AM: enabled) | ☐ |
| 15 | Block list CRUD | Queue → New list → rename → Delete → confirm: no crash, list gone, others intact | PASS — see finding C | ☐ |
| 16 | Add a friend by code | Two accounts add each other's code → each appears in the other's Grid, both ways | PASS | ☐ (needs 2 phones/accounts) |
| 17 | Status + nudge | Friend starts a break → shows `[ ON A BREAK ]` within ~8 s. Their Zap arrives as a banner; a second Zap within 1 min is refused | PASS (status; nudge delivered + acked; 429 on repeat). Banner itself not captured | ☐ |
| 18 | Stale account recovery | Server database wiped → Grid says "account is no longer valid" and offers Join again | PASS | ☐ |
| 19 | Screen Time shield | Onboarding step 5 → Choose Apps → approve → pick apps; open a blocked app → "[ DISCHARGE REQUIRED ]" shield; "Remind Me in Grounded" → notification → tap opens Grounded; during a break the app opens normally | *phone only* | ☐ |
| 20 | Contacts invite | Onboarding step 6 → Choose from Contacts → pick people → Messages opens pre-filled with your code; nothing sends until you press Send | *phone only* | ☐ |

## Findings from the Simulator run

- **A — proof text possibly truncated (unconfirmed).** Typed "Photo of my notes" into
  *Proposed proof*; the stored task had `"Photo"`. The code passes the field
  straight through, so this may be the simulator dropping keystrokes. On the
  phone, type a long proof description and check the card.
- **B — countdown overflows the dial.** The large `09:57` break countdown is
  wider than the ring (cosmetic).
- **C — delete-confirmation title is stale.** After renaming a list the dialog
  still says `Delete "New list"?` (cosmetic).

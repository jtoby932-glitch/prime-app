# PRIME

A native iOS gym trainer: weekly timetable, routines, a 96-exercise library, live workout tracking, per-exercise strength ranks, analytics and a muscle map. SwiftUI + SwiftData, iOS 17+, iPhone, fully offline, no account.

## Build it

**On GitHub (no Mac needed).** Push this folder to a GitHub repo. The workflow in `.github/workflows/build.yml` runs on GitHub's Macs and produces two things on every push:

- **Unit tests** on an iOS simulator (`test-log` artifact).
- **`PRIME.ipa`**, unsigned (`PRIME-ipa` artifact). Install it with Sideloadly or AltStore, which sign it with your Apple ID.

**On a Mac.** Open `PRIME.xcodeproj` in Xcode 16 or newer, pick your team under Signing & Capabilities, choose your iPhone and press Run. `⌘U` runs the tests.

The project file is generated. After adding or removing Swift files run `python3 tools/gen_xcodeproj.py`.

## What's where

| Spec section | Where it lives |
|---|---|
| Design language | `Design/Theme.swift`, `Design/Components.swift` (lime-on-black tokens, cards, buttons, tier shields) |
| Home dashboard | `Features/Home/HomeView.swift` |
| Timetable, routines, history | `Features/Workouts/` (week planner, day editor, routine editor with reorder/duplicate/move, session history and editing) |
| Exercise catalogue | `Features/Exercises/`, data in `Resources/exercises.json` (generated from `tools/catalogue.py`) |
| Workout tracking | `Features/ActiveWorkout/` (sets, previous performance, rest timer, notes, skip, replace, live PRs, summary) |
| Ranking engine | `Domain/RankingEngine.swift`, `Services/RankingService.swift`, `Features/Rankings/` |
| Analytics | `Domain/Analytics.swift`, `Features/Analytics/AnalyticsView.swift` |
| Muscle map | `Features/Anatomy/` (original 2D figure from `tools/anatomy.py`) |
| Profile, units, bodyweight, notifications | `Features/Profile/` |
| Onboarding and first workout | `Features/Onboarding/` |
| Data model | `Models/` (all 11 requested models, versioned schema with a migration plan) |
| Tests | `PRIMETests/` |

`Domain/` is plain Swift with no SwiftData or SwiftUI, so every calculation is unit-tested on its own.

## How ranking works

- **Estimated 1RM** uses Epley: `weight × (1 + reps ÷ 30)`. A single rep counts as the 1RM itself rather than adding 3%.
- **Loaded lifts** rank on estimated 1RM ÷ bodyweight, using the bodyweight logged nearest to that workout. With no bodyweight the app says so instead of guessing.
- **Bodyweight exercises** rank on reps in one set. Weighted sets are converted to bodyweight-equivalent reps with the same Epley formula.
- Sets over 12 reps aren't ranked because the estimate gets unreliable.
- Each exercise has its own four thresholds, and each equipment variation is a separate exercise, so machines are never compared with free weights. The overall profile shows free weights and machines separately.
- Current rank uses your best set from the last 90 days. Peak rank is shown alongside it.
- Every rank screen shows the full working: the set, the formula with your numbers, the ratio and the thresholds.

**The tiers are provisional.** They're PRIME's own starting points, labelled as such in the app, not a validated population dataset, and they aren't adjusted for sex, age or bodyweight class. Users can scale all of them in Profile → Rankings, or set their own per exercise. Bands and rotational cable work are unranked because the load isn't comparable.

## Extending the exercise library

Edit `tools/catalogue.py`, bump `VERSION`, then run `python3 tools/catalogue.py PRIME/Resources/exercises.json`. The script validates muscles, equipment, alternatives and thresholds. On the next launch, existing installs get the new and updated exercises while favourites, custom tiers and custom exercises are kept.

## Deliberate limits

- **3D anatomy:** there's no suitably licensed 3D model to bundle, so the muscle map is an original 2D front/back figure with a 3D turn animation. It's fully interactive.
- **HealthKit:** left out. It needs an entitlement that free sideloading accounts often can't sign, and a failed entitlement would stop the app installing.
- **CloudKit:** not enabled. The store is versioned so sync can be added later (it would need the unique constraints relaxed).
- **Notifications** are local only and each kind is opt-in.

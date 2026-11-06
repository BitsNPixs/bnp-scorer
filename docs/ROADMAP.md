# Roadmap, decisions and open issues

## Product context
- **Owner:** Bits N Pixs (BNP). **Product:** BNP Scorer.
- **Brief:** replicate the core of [CricHeroes](https://cricheroes.com/) for
  Android and iOS with Flutter. The owner considered multi-sport and narrowed
  it to **cricket only**.
- **Users:** local / gully / club scorers, often on cheap Android phones at
  grounds with poor network. Scoring must work offline and be quick to learn.
- **UI bar:** "user friendly and eye-catching". Big touch targets, the next
  action always visible, strong colours, readable in sunlight.
- **Name:** "Crease" was dropped because another cricket app uses it. Check
  any future name on both stores.

## Agreed stack (target) and what v0.1 actually uses
| Area | Target | v0.1 | Why the difference |
| --- | --- | --- | --- |
| App | Flutter, Riverpod | Flutter 3.32+, Riverpod 3 | — |
| Routing | go_router | `Navigator` | 4 screens. Add go_router with deep links |
| Models | freezed + json_serializable | hand-written | Builds without build_runner |
| Offline store | Drift (SQLite) | shared_preferences behind `MatchRepository` | Enough for v0.1. Swap via the interface |
| Backend | Firebase: Auth (phone OTP, Google, Apple), Firestore, Cloud Functions, Storage, FCM, Crashlytics, App Check | none | Needs the owner's Firebase project |
| Charts | fl_chart (wagon wheel, Manhattan, worm) | none | Later phase |
| Stats at scale | Postgres later, only if Firestore aggregates hurt | — | Keep the event log portable |

## Phases
**Phase 0: make v0.1 real (next)**
1. Generate the platform folders and set the display name (README "Setup").
2. Run README "Verify" and fix every analyzer issue and failing test. Expect a
   few small API slips: the code has never been compiled.
3. Run on a real Android phone. Score a full short match: wides, a no-ball and
   free hit, a run out, a mid-over bowler change, retired hurt, the innings
   break, the chase, the result and undo throughout.
4. Fix the open issues below that bite during that test.
5. `git init`, then commit with all checks green. Update AGENTS.md "Current
   status".
6. App icon and splash in BNP branding (navy `#0E1430` and lime `#D4FF3F`).

**Phase 1: accounts, teams, players**
- Firebase project, `flutterfire configure` (creates `lib/firebase_options.dart`,
  which is gitignored), and phone OTP sign-in.
- Saved teams and players are done on the device (`TeamRepository`). Still to
  do: sync them to the account, a screen to edit a squad, and a player profile
  with photo (Storage).

**Phase 2: cloud sync for scoring**
- `FirestoreMatchRepository implements MatchRepository`, or better, keep local
  storage as the source of truth for the scorer and add a background sync that
  pushes events.
- Firestore layout:
  - `matches/{matchId}`: setup, owner, scorers, status;
  - `matches/{matchId}/events/{eventId}`: one document per event. The event id
    makes writes idempotent on re-sync.
- Security rules: only the match's scorers can write events. Events are
  append-only; undo is a separate "undo" marker or a delete by the scorer.
  Decide which and document it in ARCHITECTURE.
- Conflict rule: one active scorer device per match (lock), with a handover.

**Phase 3: live viewers and push**
- A Cloud Function runs the same engine rules (share the Dart engine via a
  Dart-on-server function, or port the projection) and maintains
  `matches/{id}/live/state`, a small document that spectators listen to. This
  costs 1 read per update per viewer instead of streaming every event.
- FCM pushes for wickets, milestones and results. Share a match link.

**Phase 4: tournaments and stats**
- Tournaments, fixtures, points table, NRR, player career stats and
  leaderboards. Precompute them in Functions. Never let clients write
  aggregates.
- Charts: Manhattan, worm, wagon wheel (needs shot direction added to
  `BallBowled` as an optional field).

**Phase 5: growth**
- Share the scorecard as an image to WhatsApp (the main growth loop for local
  cricket), vernacular UI, discovery of nearby teams and grounds.
- Later: social feed, live-stream overlays, premium.

## Open issues (not yet fixed)
From the independent review and known limitations, in priority order:
1. **Run out off a bye or leg bye.** The wicket sheet only offers legal / wide /
   no-ball deliveries, so runs completed go to the batter. Fix: add Bye and LB
   to the sheet's delivery options and map them to `extra` + `extraRuns`. The
   engine already allows it.
2. **Leg byes off a no-ball** are recorded as byes. Fix: let the no-ball sheet
   pick byes or leg byes. The engine needs an extra field (keep the JSON
   backward compatible).
3. **No "no result" / "abandoned".** Closing the second innings early always
   decides on runs. Fix: a result kind plus an "Abandon match" action.
4. **Two-bowler deadlock.** With strict Law 17.8, a side with only 2 bowlers
   that changes bowler mid-over has nobody eligible for the next over. "End
   innings" is the only way out. Consider allowing it with a warning in local
   mode.
5. **Run-out strike.** After a run out, strike follows the runs completed. If
   the batters crossed, the scorer must tap "swap strike". Consider asking
   "who's on strike?" in the wicket sheet.
6. **Large text / long names.** The "Players · N" label is fixed. Other rows
   have not been checked at 200% text size.
7. **Fonts are fetched at runtime.** Bundle Inter and Space Grotesk (`.ttf` in
   `assets/google_fonts/`, listed in pubspec) and set
   `GoogleFonts.config.allowRuntimeFetching = false`, so the first launch
   works offline.
8. **Last man stands margin** reads "won by 11 wickets" for 11 players (it
   counts the extra wicket). Decide the wording with the owner.
9. **Untested:** the new-match "Start" blocker, including the new bowler-limit
   check. Add a widget test or extract the validation into a pure function and
   unit test it.
10. **Minor:** `LiveMatchNotifier.build` uses `ref.read` for the repository
    (`ref.watch` is more idiomatic); `useMaterial3: true` is redundant.

## Out of scope for v0.1
- Super over, DLS, Test / multi-day formats, follow-on.
- Player profiles, career stats, tournaments, sharing, cloud sync (phases 1–5).

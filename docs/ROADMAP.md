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
| Routing | go_router | `Navigator` | 12 screens, no deep links yet. Add go_router with them |
| Models | freezed + json_serializable | hand-written | Builds without build_runner |
| Offline store | Drift (SQLite) | shared_preferences behind repositories | Enough for v0.1. Swap via the interfaces |
| Backend | Firebase: Auth (phone OTP, Google, Apple), Firestore, Cloud Functions, Storage, FCM, Crashlytics, App Check | none | Needs the owner's Firebase project |
| Charts | fl_chart (wagon wheel, Manhattan, worm) | hand-drawn on a canvas | Keeps out a dependency; three simple charts did not need one |
| Sharing, files | — | share_plus, file_picker behind `DeviceFiles` | Needs platform code |
| Stats at scale | Postgres later, only if Firestore aggregates hurt | — | Keep the event log portable |

## Phases
**Phase 0: make v0.1 real (next)**
Done: Android folder, compile, analyzer and tests green, install on a phone, git.

Still to do:
1. On a real Android phone, score a full short match: wides, a no-ball and free
   hit, a run out, a mid-over bowler change, retired hurt, the innings break, the
   chase, the result and undo throughout. On 2026-11-10 the owner scored a match
   to its result; which of these cases it covered is not known.
2. Try sharing and backup and restore on a real phone (open issue 1).
3. Fix the open issues below that bite during those tests.
4. ~~App icon and splash~~ Done on 2026-11-10: the BNP letters over a red seam
   on night (option C), as an adaptive icon with a themed-icon layer, and a
   night splash on every Android version. Seen on the phone's install screen;
   the home-screen icon and the splash itself are still to be checked there.
5. ~~A release build~~ Done on 2026-11-10: it builds, installs over the debug
   build keeping data, and runs, with no internet permission. It is still
   signed with the debug key; the Play Store needs a real upload key. Then iOS
   on a Mac.

**Phase 1: accounts, teams, players**
- Firebase project, `flutterfire configure` (creates `lib/firebase_options.dart`,
  which is gitignored), and phone OTP sign-in.
- Saved teams, squad editing and player roles are done on the device
  (`TeamRepository`). Still to do: sync them to the account, and a player profile
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
- Tournaments, fixtures, points tables, NRR, career stats and leaderboards work
  on the device from local matches, with groups, semi-finals and home-and-away
  formats. Still to do: more than two groups, arranging groups by hand, quarter-
  finals, and precomputing shared stats in Functions. Never let clients write
  aggregates.
- Manhattan, worm and wagon wheel charts are done.

**Phase 5: growth**
- Done: sharing a scorecard as an image, the main growth loop for local cricket.
- Vernacular UI, discovery of nearby teams and grounds.
- Later: social feed, live-stream overlays, premium.

**Ideas raised but not started**
- A Squads tab on the scorecard, listing both playing XIs.
- Automatic highlights from wickets, boundaries and milestones.

## Open issues (not yet fixed)
In priority order:

1. **Sharing and backup are untested on a phone.** Tests replace the share sheet and
   file picker, so a real WhatsApp share and a real restore have never been run.
2. **Unexplained install stalls.** `adb install` hung twice with the phone locked,
   then once worked while locked. A leftover "Installing" screen from the phone's
   installer was seen. The cause is unknown.
3. **Tournament edge cases:**
   - changing a league result after knockouts are scheduled shows no notice until
     that game is finished again;
   - a corrected final leaves its old Super Over in the fixture list, though it no
     longer affects the champion;
   - fixture cards keep the name a team had when the tournament was created;
   - groups are split by list order and cannot be arranged by hand.
4. **Run out off a bye or leg bye.** The wicket sheet only offers legal / wide /
   no-ball deliveries, so runs completed go to the batter. Fix: add Bye and LB
   to the sheet's delivery options and map them to `extra` + `extraRuns`. The
   engine already allows it.
5. **Leg byes off a no-ball** are recorded as byes. Fix: let the no-ball sheet
   pick byes or leg byes. The engine needs an extra field (keep the JSON
   backward compatible).
6. **Closing an innings early** still decides on runs. Use "Abandon match" for a
   game that should have no result. Rain rules such as DLS are not implemented.
7. **Two-bowler deadlock.** With strict Law 17.8, a side with only 2 bowlers
   that changes bowler mid-over has nobody eligible for the next over. "End
   innings" is the only way out. Consider allowing it with a warning in local
   mode.
8. **Run-out strike.** After a run out, strike follows the runs completed. If
   the batters crossed, the scorer must tap "swap strike". Consider asking
   "who's on strike?" in the wicket sheet.
9. **Large text / long names.** The "Players · N" label is fixed. Other rows
   have not been checked at 200% text size.
10. **Last man stands margin** reads "won by 11 wickets" for 11 players (it
   counts the extra wicket). Decide the wording with the owner.
11. **Untested:** the new-match "Start" blocker, including the new bowler-limit
   check. Add a widget test or extract the validation into a pure function and
   unit test it.
12. **Minor:** `LiveMatchNotifier.build` uses `ref.read` for the repository
    (`ref.watch` is more idiomatic); `useMaterial3: true` is redundant.

## Out of scope for v0.1
- DLS, Test / multi-day formats, follow-on.
- Player photos and cloud sync (phases 1 and 2).

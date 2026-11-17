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
| Backend | Firebase on the free Spark plan: Auth (Google), Firestore; later FCM | none | Being added ("Cloud: shared matches") |
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
2. Try sharing a scorecard on a real phone (open issue 1). Backup and restore
   were confirmed on 2026-11-17.
3. Fix the open issues below that bite during those tests.
4. ~~App icon and splash~~ Done on 2026-11-10: the BNP letters over a red seam
   on night (option C), as an adaptive icon with a themed-icon layer, and a
   night splash on every Android version. Seen on the phone's install screen;
   the home-screen icon and the splash itself are still to be checked there.
5. ~~A release build~~ Done on 2026-11-10: it builds, installs over the debug
   build keeping data, and runs, with no internet permission. It is still
   signed with the debug key; the Play Store needs a real upload key. Then iOS
   on a Mac.

**Beta readiness (before testers outside the owner's circle)**
Done on 2026-11-17: release signing setup, byes and leg byes on run outs and
no-balls, Report a problem, version and privacy note in Settings, a bowler picker
that never leaves the scorer stuck, run-out ends, the repo pushed to GitHub, the
upload key, and the privacy policy at https://bitsnpixs.github.io/bnp-scorer/privacy.html.
The real names in `demo_data.dart` are fine to show (owner).

Still to do, all free unless noted:
1. Testers on an early debug-signed build back up, uninstall and install the
   beta once. The owner's phone made this move on 2026-11-17, and the restore
   brought everything back.
2. Score full matches on the phone covering the cases in Phase 0 step 1, plus a
   run out with the batters crossed and a side short of bowlers.
3. Share 0.9.0-beta.1 over WhatsApp or Drive (the owner's choice, free;
   README "Beta builds"). Later, the Play Store needs a one-time $25 developer
   account; a new personal account must run a closed test with about 12 testers
   for 14 days before going public.
4. For the store: `flutter build appbundle --release --obfuscate
   --split-debug-info=build/symbols` (keep the symbols), screenshots, a 1024x500
   feature graphic, content rating, target audience not children, and Data
   safety "no data collected". Bump the version first (AGENTS "Version").

**Cloud: shared matches (decided with the owner on 2026-11-17)**
Goal: everyone who installs the app sees the same, up-to-date matches.

Decisions:
- **Public:** every match a signed-in scorer saves to the cloud is visible to all
  app users. Player names become public, and the app says so before a scorer
  publishes.
- **Only its scorer changes a match.** Everyone else watches it update live. A
  handover to another scorer can come later.
- **Google sign-in** for scorers only. Watching needs no account. Scoring
  signed out still works, on the phone only, as today.
- **Firebase, free Spark plan:** Firestore and Firebase Auth. About 50,000 reads,
  20,000 writes and 1 GiB stored per day for free; it never bills, and past a
  limit syncing pauses until the next day while scoring carries on offline.
  Analytics stays off.

Design:
- `matches/{matchId}` holds one match whole, as `MatchRecord` already does: the
  setup, the event list, `ownerUid`, the scorer's display name, `createdAt`,
  `updatedAt`, and a few summary fields for lists (teams, score, status). One ball
  is one document write; a watcher pays one read per update. A long match stays
  far below the 1 MiB document limit (about 150 bytes per event).
- Local storage stays the scorer's source of truth. A cloud repository wraps the
  local one: save locally first, then write to Firestore, whose offline queue
  sends it when the phone is back online.
- Security rules: anyone may read; only a signed-in user may create a match with
  their own `ownerUid`; only that owner may change or delete it, and never its
  owner field. Rules cannot run the engine, so viewers replay defensively and
  show "can't display this match" on a broken log. A bad owner can only spoil
  their own match.
- Old local matches stay private unless the scorer chooses to publish them.
- New screens: a public "Live and recent" list and a read-only match view (no
  pad, no scoring menu) that streams updates.
- Teams and tournaments move to the cloud after matches, with the same rules.
- The app gains the internet permission. The privacy policy and Play Data
  safety must be updated **before** that build ships: account name and email,
  and public match content including player names.

Order of work:
1. Owner: create the Firebase project, Firestore (Mumbai, `asia-south1`), Google
   sign-in, and the Android app with the debug and upload key fingerprints, then
   put `google-services.json` in `app/android/app/` (gitignored). Done 2026-11-17.
2. Sign-in and the cloud match repository, with security rules in the repo and
   tests against a fake cloud. Done and tried on the owner's phone on
   2026-11-17, with `firestore.rules` published in the console.
3. The public list and the read-only live view. Done on 2026-11-17 and seen
   updating live on a second phone.
4. Privacy policy, in-app notice before publishing, beta.2 to testers. Done in
   code on 2026-11-17 (brought forward, owner's call, so testers get live
   watching sooner; cups ship as beta.3). Still owed before the Play upload:
   - the Play Data safety form (answers in README "Cloud");
   - an in-app "Delete my account" that removes the scorer's published matches
     and the Firebase user, plus a web page for the same request: Play requires
     both for apps with sign-in;
   - a private contact for privacy requests (a role address such as
     privacy@, not a personal email) in the policy instead of public GitHub
     issues.
5. Teams and tournaments in the cloud; handing a match to another scorer.

**Cups, prizes and upcoming matches (decided with the owner on 2026-11-17)**
Goal: run a local cash-prize cup or league in the app, and list what is coming
up, for organisers and for everyone following.

Decisions:
- **Formats: both.** A new straight-knockout cup: any number of teams in a
  bracket, losers out each round (round of 32 or 16, quarter-finals, semis,
  final), with byes for numbers that are not a power of two. And quarter-finals
  as a third knockout option after a league or groups (top 8; top 4 of each of
  two groups).
- **Prizes and entry fees.** Prize amounts (winner, runner-up, player of the
  series, and so on) shown on the tournament page and the champion's share card.
  An entry fee per team and who has paid it, for the organiser's own tracking.
  The app never handles money. Amounts default to rupees.
- **Upcoming: cup fixtures and friendlies.** Fixtures get a start time and show
  as upcoming. Friendlies get "Schedule for later" on New match. A scheduled
  match is a fixture, not a match: the toss is set when it starts, through New
  match prefilled, as tournament fixtures already work.
- **Public.** A signed-in organiser's cups and scheduled matches appear under
  Everyone; only the organiser changes them. Who has paid the entry fee stays on
  the organiser's phone and is never published.

Order of work (each step tested and committed):
1. Engine: straight knockout with byes and round names, quarter-finals after
   groups, prizes and entry fees on `Tournament` (optional JSON fields), tests.
2. App: format choice and draw order on New tournament, a bracket tab, prizes
   and entry fees (organiser-only paid status), prizes on the champion card.
3. Upcoming: fixture start times shown and editable, an Upcoming strip on My
   matches, "Schedule for later" for friendlies, and a WhatsApp invite.
4. Cloud: publish cups (without paid status) and scheduled friendlies; Everyone
   gains Upcoming and Cups.
5. Then update the privacy policy for cups and schedules (organiser name,
   prizes; never amounts paid) and ship beta.3.

**Phase 3: push**
- FCM pushes for wickets, milestones and results. Share a match link that opens
  the live view.

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

1. **Scorecard sharing is untested on a phone.** Tests replace the share sheet,
   so sharing a scorecard image to WhatsApp has never been run. Backup and
   restore were confirmed on the owner's phone on 2026-11-17.
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
4. **Closing an innings early** still decides on runs. Use "Abandon match" for a
   game that should have no result. Rain rules such as DLS are not implemented.
5. **Large text / long names.** The "Players · N" label is fixed. Other rows
   have not been checked at 200% text size.
6. **Last man stands margin** reads "won by 11 wickets" for 11 players (it
   counts the extra wicket). Decide the wording with the owner.
7. **Untested:** the new-match "Start" blocker, including the new bowler-limit
   check. Add a widget test or extract the validation into a pure function and
   unit test it.
8. **Minor:** `LiveMatchNotifier.build` uses `ref.read` for the repository
    (`ref.watch` is more idiomatic); `useMaterial3: true` is redundant.

## Out of scope for v0.1
- DLS, Test / multi-day formats, follow-on.
- Player photos. Cloud sync is planned in "Cloud: shared matches".

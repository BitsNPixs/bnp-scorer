# Roadmap, decisions and open issues

## Product context
- **Owner:** BitsNPixs Technologies Private Limited (BNP). **Product:** BNP Scorer.
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
| Routing | go_router | `Navigator` | 15 screens, no deep links yet. Add go_router with them |
| Models | freezed + json_serializable | hand-written | Builds without build_runner |
| Offline store | Drift (SQLite) | shared_preferences behind repositories | Enough for v0.1. Swap via the interfaces |
| Backend | Firebase on the free Spark plan: Auth (Google), Firestore; later FCM | Auth (Google) and Firestore: matches, tournaments, schedules | FCM not needed yet |
| Charts | fl_chart (wagon wheel, Manhattan, worm) | hand-drawn on a canvas | Keeps out a dependency; three simple charts did not need one |
| Sharing, files | — | share_plus, file_picker behind `DeviceFiles` | Needs platform code |
| QR codes | — | qr_flutter (team invites) | Drawing a QR by hand is not worth it |
| Photos | — | Cloudflare R2 behind a Worker (`cloud/photos-worker`), image_picker | Owner's choice; free downloads, and the app holds no keys |
| Stats at scale | Postgres later, only if Firestore aggregates hurt | — | Keep the event log portable |

## Next, in order (as of 2026-11-21, end of day)
0. **Finish and release beta.7 (registered players):** everything is built
   and on the owner's phone (`docs/PLAYER_PROFILES.md`). Owner first: paste
   the current `firestore.rules` (photo and logo checks), and remove the real
   number from Firebase's test numbers before testers. Then a two-phone try:
   sign in with a number on phone B, add that player by number on phone A,
   share a team invite and join it from phone B, set a team logo, score a
   match and see it on the player's profile on both phones. Then push, cut
   the GitHub Release and update the site.
1. **Before photos go wide:** a way to report a photo, and a BNP domain in
   front of the photos Worker (its workers.dev name comes from another
   project on the same Cloudflare account).
2. **Two-phone try of beta.6 on the real Firestore:** on the owner's phone,
   signed in, create a knockout cup with a date, add prizes, a fee and a
   payment, and "Schedule for later" a friendly. On a second phone, check
   Everyone > Upcoming and Cups, open the cup (bracket and prize shown, no
   payments, no edit), and watch a fixture played. If something is missing,
   read the documents with the Firestore REST API (public read) and compare.
3. **Check on a phone what is only tested in renders:** AGENTS.md "Current
   status" lists it (cups, bracket, prizes tab, upcoming sheet, WhatsApp invite,
   scorecard sharing, charts, Super Overs, the new launcher icon and splash,
   and squad import: paste a real WhatsApp team list, import a sheet filled
   from the shared template, and check Sheets or Excel opens the shared file).
4. **Before the Play Store:** in-app "Delete my account" (removes the scorer's
   published matches, tournaments, schedules, shared teams, photos, phone
   link and number lookup, then the Firebase user) and a
   web page for the same request; a private privacy contact (a role address
   such as privacy@, the owner's call); the Data safety form (answers in README
   "Cloud"); the $25 account and a closed test with about 12 testers for 14
   days.
5. **Cloud step 5:** teams in the cloud are done as shared teams with invites
   (docs/PLAYER_PROFILES.md, release 4); handing a match to another scorer is
   still to do.

## Website and API (planned 2026-11-27)
The owner wants match details on the website as they look in the app, and
maybe an admin page later, as a lasting design rather than a patch.

**The problem:** a published match is its setup and its balls; the score
exists only after `cricket_engine` replays them, and the rules must not be
written a second time in another language.

**The design (stored read copies):**
1. The scorer's app keeps writing `matches/{id}` as now. It stays the source
   of truth, and offline scoring is untouched.
2. A Dart service on Cloud Run (`cloud/api`, asia-south1) is called by a
   Firestore trigger on every match write. It imports `cricket_engine`,
   replays the match and stores a small card for lists and the full
   scorecard view. Only the server writes these. Triggers can arrive twice
   or out of order, so it re-reads the match and never replaces a copy made
   from more balls.
3. The same service serves them as a versioned, cached API
   (`/v1/matches`, `/v1/matches/{id}`, later tournaments and players).
4. The website reads the API; the admin page later uses it with sign-in.
5. Later the app's Everyone list and player careers read the stored copies
   and stop downloading every ball.

Why not Dart in Firebase Functions: experimental, and its Firestore
triggers cannot be deployed (checked 2026-11-27). Why not a copy of the
engine in JavaScript on the site: no API for the admin page or anyone else.
Fallback if the trigger cannot reach Dart directly: the TypeScript
Functions take the trigger and call the service over HTTP.

**Stages:** 0. the trial below; 1. the match view JSON as pure Dart with
tests (the wording helpers the app keeps in `ui/format.dart` move where
both can use them); 2. the service, trigger, rules for the new collections
and a rebuild of existing matches; 3. the API; 4. the website's match page
and list, and "share a match link" in the app; 5. the app reads the stored
copies; 6. the admin page. The privacy policy and the site's feature list
change with stage 4.

**Stage 2 (2026-11-27): deployed.** `cloud/api` is the real service
(README "API server", docs/ARCHITECTURE.md "Stored copies"): it stores
`matchCards/{id}` and `matchViews/{id}` for every save, keeps the newest
save when events arrive out of order or twice, removes the copies of a
deleted match and keeps the last good ones of a match it cannot read. 23
tests with an in-memory store. Live as the private Cloud Run service
`bnp-api-projector` with the trigger `bnp-api-projector-matches`. The
rebuild stored all 5 published matches, twice (a first write and a
replacement), and Firestore refuses a stale copy with FAILED_PRECONDITION
and an existing one with ALREADY_EXISTS, both of which the store treats as
"do it again". The trial is removed (service, trigger and `trialViews`).
**Still to do:** the owner pastes `firestore.rules` (until then the copies
are not publicly readable, which nothing needs yet), and a try from the
phone: a few balls, an undo and a deleted match, then read the copies.
Decided for stage 3: the public API will be a second service from the same
image with a read-only account, so the internet never reaches the one
that writes.

**Stage 1 (2026-11-27): done.** `packages/match_view` holds the wording
moved out of the app's `ui/format.dart` (which re-exports it, so screens
are unchanged) and `matchCard` / `matchView`, version 1 (docs/ARCHITECTURE.md
"Match views"). Not in the view yet: the result tab's top batter and best
bowler (private to the app's widget), and chart series beyond what
`overByOver` gives. Next is stage 2; `cloud/api`'s Dockerfile must copy
`packages/match_view` too.

**Stage 0, the trial (2026-11-27): passed.** `cloud/api` is a throwaway
service that stores only a score line in `trialViews/{id}`. Deployed as the
private Cloud Run service `bnp-api-trial` (asia-south1, at most 2
instances, running as the service account `bnp-api`, which holds only
Firestore access), with the Eventarc trigger `bnp-api-trial-matches` on
`matches/{matchId}`. The owner scored 13 balls of a published match on
their phone: all 14 saves reached the service in order, each was replayed
(8 to 37 ms; 89 ms on a cold start) and stored, and the stored score
matched the phone (25/2 after 1.2 overs). From the phone saving a ball to
the stored copy took 1.0 to 2.4 seconds, the slowest being the cold start.
The trigger's CloudEvent names the document in its `ce-document` header,
so the protobuf body is never parsed. Cost is not measured yet (too little
use to show on a bill). Build the image with `cloud/api/cloudbuild.yaml`
from a copy holding only `packages/cricket_engine` and `cloud/api`.
It was removed the same day, when stage 2's service replaced it.

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
4. ~~App icon and splash~~ Done on 2026-11-10 (the BNP letters over a red
   seam), replaced on 2026-11-18 by the owner's ball logo: a cricket ball in
   the BitsNPixs green with "bp" across it, as an adaptive icon with a
   themed-icon layer, a night splash, the Matches header and the website's
   icons. The whole app moved to the brand green the same day (beta.4). The
   header was seen on the owner's phone; the home-screen icon and the splash
   are still to be checked there. The bottom bar's Matches tab keeps its bat
   and ball icon (owner, 2026-11-18).
5. ~~A release build~~ Done on 2026-11-10: it builds, installs over the debug
   build keeping data, and runs, with no internet permission. It is still
   signed with the debug key; the Play Store needs a real upload key. iOS
   was started on a Mac on 2026-11-26 (see "iOS" below).

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
3. Share betas from the website's Download for Android button (the latest
   GitHub Release, since beta.3; beta.6 is the latest) or over WhatsApp (README "Beta builds"). Later, the Play Store needs a one-time $25 developer
   account; a new personal account must run a closed test with about 12 testers
   for 14 days before going public.
4. For the store: `flutter build appbundle --release --obfuscate
   --split-debug-info=build/symbols` (keep the symbols), screenshots, a 1024x500
   feature graphic, content rating, target audience not children, and Data
   safety as in README "Cloud" (the cloud build collects data). Bump the version first (AGENTS "Version").

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
- **Prizes and entry fees.** Prizes (winner, runner-up, player of the series,
  and so on) shown on the tournament page and the champion's share card. An
  entry fee per team and how much each team has paid, for the organiser's own
  tracking. The app never handles money. Amounts default to rupees.
- **After comparing with CricHeroes and real cash-prize listings (owner agreed,
  2026-11-17):** a prize is a title plus free text ("Rs 3000 & trophy"), not
  just a number; the organiser records the amount paid, so deposits show
  ("Rs 10,000 of Rs 37,000"); a rules and notes box on the cup (ball, fees not
  refundable, invitation only); and a ground per fixture. Left out for now:
  player availability polls, sponsors, registration forms, spreadsheet
  upload.
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
   Done 2026-11-17: one bracket model now drives every knockout game, old and
   new; a cup's draw pairs teams in list order with byes to the first teams.
2. App: format choice and draw order on New tournament, a bracket tab, prizes
   and entry fees (organiser-only paid status), prizes on the champion card.
   Done 2026-11-17: format choice, Quarters, the cup draw with Shuffle, the
   Bracket tab (2a); the Prizes tab with entry fees and payments, rules, and the
   prize on the champion banner (2b). A ground per fixture moved to step 3,
   with the fixture's time, on one fixture sheet.
3. Upcoming: fixture start times shown and editable, an Upcoming strip on My
   matches, "Schedule for later" for friendlies, and a WhatsApp invite. Done
   2026-11-17, with a ground per fixture on the same sheet.
4. Cloud: publish cups (without paid status) and scheduled friendlies; Everyone
   gains Upcoming and Cups. Done in code 2026-11-17, tested with a fake cloud.
   The owner must paste the new `firestore.rules` (tournaments and schedules)
   into the console before it works for real; until then those writes are
   refused and nothing else breaks.
5. Then update the privacy policy for cups and schedules (organiser name,
   prizes; never amounts paid) and ship beta.3. Done 2026-11-17: policy and
   notice live, rules pasted, beta.3 on the owner's phone and published as
   GitHub Release `v0.9.0-beta.3`, served by the website's download button.
   Not yet tried on two phones against the real Firestore (see "Next").

**iOS (started 2026-11-26 on the owner's Mac)**
Done: `app/ios` generated (bundle ID `com.bitsnpixs.bnpscorer`, minimum iOS
15, Swift Package Manager), a debug build seen running in the iPhone 17e
Simulator to the Matches home, phone-only.

Still to do, in order:
1. App icon and launch screen from `paintLogo`: extend
   `tool/generate_app_icon_test.dart` to write
   `ios/Runner/Assets.xcassets` (1024 px, no transparency) and check it in
   `test/app_icon_test.dart`.
2. Score a match in the Simulator; check the share sheet (iPad needs a
   share origin, or the app may crash there; or limit the app to iPhone),
   the file picker and the photo picker.
3. ~~Run on an iPhone~~ Installed on an iPhone 16 Pro Max (iOS 27.2.1) on
   2026-11-26, a release signed by the owner's free Personal Team (lasts 7
   days; README "Setup"). Not yet tried there.
4. ~~Firebase~~ Done in code on 2026-11-26: the iOS app is registered, its
   `GoogleService-Info.plist` is gitignored, and a build step copies it and
   adds the sign-in URL schemes (README "Cloud"). Installed on the iPhone;
   Google sign-in, number sign-in (reCAPTCHA page, no APNs on the free
   account) and publishing not yet tried there. APNs needs the paid Apple
   developer account ($99 a year).
5. Swift sides of the two channels in `MainActivity.kt`: the contact picker
   (`CNContactPickerViewController`, no permission) and the
   `bnpscorer://join` link (URL scheme in `Info.plist`).
6. TestFlight and the App Store: the paid account, privacy labels, and
   account deletion (as for Play).

**Notifications (decided with the owner on 2026-11-26)**
Goal: tell people what matters without opening the app, on Android and iOS.

Decisions:
- **All four kinds:** match reminders, following a live match (start,
  wickets, fifties and hundreds, five-fors, innings break, result), team
  activity (a join request to the captain, "you're in" to the player, "you
  were added" to a player added by number), and cup updates (your team's
  next fixture set or moved, a team through, the champion).
- **Pushes are sent by Firebase Functions** on Firestore changes (Blaze is
  already on for SMS), so a scorer's phone sends nothing extra and nobody can
  fake a notification. The Functions live in `cloud/functions`; the owner
  logs the Firebase CLI in once.
- **Android first, iOS push later:** iOS push needs the paid Apple Developer
  Program ($99 a year) for its APNs key. Until then iOS has reminders only.
- **Permission asked at the right moment:** when the user turns reminders
  on, follows a match, or shares a team invite, with the reason shown first;
  never at launch. Settings > Notifications has a switch per kind.

Order of work (each step tested and committed):
1. Match reminders, made on the phone. Done 2026-11-26: the offer above
   Upcoming, Remind me on each sheet, a bell on reminded cards, Settings with
   how long before (15 min to 1 day), a tap opening the match. Up to 40
   pending reminders (iOS keeps 64). Not yet seen firing on a phone.
2. Push setup: done in code 2026-11-26. `firebase_messaging` (Android
   only until iOS has an APNs key), `pushDevices/{installId}` with token,
   owner, platform and kinds (rules in `firestore.rules`), a switch per
   kind and "Send me a test notification" in Settings > Notifications,
   pushes shown while the app is open, the registration removed before
   sign-out and a new one made if the last account's was left behind.
   `cloud/functions` with `pushTest`, deployed 2026-11-26 after the owner
   logged in, upgraded to Blaze and published the rules. The test push
   reached the owner's Android phone the same day.
3. Follow a live match: done in code 2026-11-26 (owner agreed the plan).
   The engine's `momentOf` finds the moment one event made; the scorer's app
   words it and publishes it as `highlight` (seq, kind, title, body) with the
   ball; the Function `matchHighlight` sends each new seq once to phones
   following the match, never the scorer's. Bell on the watched match,
   follows kept two days, a tap opens the match. Boundaries are not sent
   (too many). Still to do: paste the rules, deploy, try with two phones.
   Known limit: undoing a wicket and scoring it again sends it twice.
4. Team activity, from `teams/{id}/joins` and team changes.
5. Cup updates, from tournament changes.

**Phase 3: push**
- See "Notifications" above. Share a match link that opens the live view.

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
8. **Cloud cups, known limits:** a fixture's match scored while signed out is
   never published, so a watched cup shows that fixture as not started;
   Everyone lists only the newest 20 cups; a friendly neither started nor
   cancelled stays in Firestore (it drops off the lists by time); a watched cup
   reads one document per played match.
9. **Minor:** `LiveMatchNotifier.build` uses `ref.read` for the repository
    (`ref.watch` is more idiomatic); `useMaterial3: true` is redundant.
10. **Two Flutter versions (2026-11-26):** the owner's Mac has Flutter 3.50,
    newer than the Windows machine's. `flutter analyze` there shows infos
    asking to import `package:material_ui` instead of
    `package:flutter/material.dart`, one per file. AGP is now 9.1.1 (the
    reminders plugin needed it, and so does 3.50). Settle on one Flutter
    version, then migrate the imports as their own change. Icons rendered on
    the Mac differ by a few edge pixels from the committed ones, so regenerate
    icons on one machine only.

## Out of scope for v0.1
- DLS, Test / multi-day formats, follow-on.
- Player photos. Cloud sync is planned in "Cloud: shared matches".

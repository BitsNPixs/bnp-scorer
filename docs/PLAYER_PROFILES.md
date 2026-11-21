# Registered players: progress tracker

A person registers once, has a public profile with career stats from every
published match, and a captain adds them to a squad by their mobile number
(the CricHeroes model). Agreed with the owner on 2026-11-21. This file tracks
the work; tick a step in the same commit that finishes it, with the date.
Design detail is in `docs/ARCHITECTURE.md` "Cloud" once each piece lands.

## Decisions (fixed)
- **Identity:** Google sign-in stays the account. A player adds their mobile
  number in Settings and confirms it once with an SMS code (Firebase phone
  auth, linked to the same user). Only a verified number claims a profile.
  Needs the Blaze plan (about $0.07 per SMS in India after 10 free a day).
- **The global player id is `Player.id`.** No new field on `Player`; the
  engine and every stored format stay as they are. A player added by number
  before registering is "invited" (a placeholder) under that id; registering
  with the same number attaches the account to it.
- **Numbers never go public.** `phones/{sha256(number)}` is readable one
  document at a time by signed-in users and never listable. The public
  profile shows a Verified tick, not a masked number. The owner sees their
  own masked number in Settings. (Flip later with a `phoneTail` field if the
  owner wants a public mask.)
- **Stats are derived on the phone** from all published matches that carry
  the player id (`playerIds` on `matches/{id}`), replayed through the engine.
  Nothing aggregated is ever written by a client.
- **Format buckets** (ALL, T10 <= 10 overs, T20 11-20, 20+) and per-match
  lines come from the engine; dates come from `MatchRecord.createdAt`.
- **Contacts** use the system picker (one tapped contact, no `READ_CONTACTS`).
- **Team invite** is a 6-character join code in a link and WhatsApp text
  first; one-tap App Links and a QR come later with the same link.

## Release 1: identity, add by number, profile with career stats (beta.7)
- [x] 1. This tracker, with pointers from ROADMAP and AGENTS. (2026-11-21, adbc32a)
- [x] 2. Engine: `formatOf`, `BattingStats.ducks`, `playerMatchLines` + tests. (2026-11-21, 18c41ba)
- [x] 3. `phone_numbers.dart` (normalise, mask, hash) + tests; `crypto` dependency. (2026-11-21, aa2747b)
- [x] 4. `Accounts` phone methods, `Scorer.phone`, `userChanges()`, `FakeAccounts`. (2026-11-21, 1d02228)
- [x] 5. `PlayerDirectory` (Firestore + fake) + tests; rules for `players` and `phones`. (2026-11-21, 57a9d3c)
- [x] 6. `playerIds` on publish, `CloudMatches.byPlayer`, one-time backfill + tests; rules for `matches`. (2026-11-21, 1c82e19)
- [x] 7. `PlayerProfileScreen` (INFO, BATTING, BOWLING, CAREER), `KeyValueTable`, `StatsTable`; replaces `PlayerStatsScreen` everywhere (watched cups show their own numbers). (2026-11-21, 98ca03e; tab pill inset app-wide after owner feedback)
- [x] 8. Settings: link a number, Verified line, Change number, My profile + tests. (2026-11-21, 7c30c3a)
- [x] 9. Add by number on the team page and New match (found / invited / already in squad / offline / signed out) + tests. (2026-11-21, f19ee42)
- [x] 10. Docs, privacy policy, Data safety answers, site feature list and FAQ, screenshots, version bump, beta build. (2026-11-21, beta.7 build 8 in dist/, not released)

Owner tasks in the Firebase console before step 8 is tried on a phone:
- [ ] Upgrade to Blaze with a budget alert.
- [ ] Authentication > Sign-in method: enable Phone; SMS region policy: allow India only.
- [ ] Enable the Play Integrity API on the Google Cloud project (else a reCAPTCHA page opens in the browser).
- [ ] Add a test phone number and code for development.
- [ ] Paste the new `firestore.rules`; in the Rules Playground check `hashing.sha256(...).toHexString().lower()` matches the app's lowercase hex.

## Release 2: profile fields
- [x] Playing role, batting style, bowling arm and type, home town on `players/{id}`. (2026-11-21)
- [x] INFO tab rows; owner-only Edit profile sheet + tests. (2026-11-21)
- [x] Privacy text: styles and home town are public. (2026-11-21)

## Release 3: pick from phone contacts
- [ ] `MainActivity.kt` picker channel; `DeviceContacts` + fake; button in the add-by-number sheet + tests.
- [ ] README Data safety and privacy Permissions paragraph; site FAQ.

## Release 4: teams in the cloud, join code, invite, join requests
- [ ] `CloudTeams`, `SyncingTeamRepository`, `teams` rules.
- [ ] Join a team by code; captain accepts requests; Share invite; `site/join.html`.
- [ ] Profile Teams panel lists published teams; privacy text; ROADMAP cloud step 5.

## Release 5: one-tap link, QR, share a profile
- [ ] Android App Links (`.well-known/assetlinks.json` on the site), route handling in `HomeScreen`.
- [ ] QR for the invite; scorecard rows open profiles; share a profile as text.

## Later, tied to account deletion (ROADMAP "Before the Play Store")
- [ ] Deleting the account also forgets the number, releases the profile and unlinks phone auth.

## Open items and risks
- Enumeration of `phones/` by a signed-in attacker at Firestore read prices: sign-in is required now; App Check or a rate-limited Function later.
- A recycled number inherits the old profile (the number is the identity).
- "This year" and ordering use `MatchRecord.createdAt`, the phone's clock.
- Matches published by scorers who never update to beta.7 have no `playerIds` and stay off profiles, including when opened from a watched cup.
- iOS: phone auth needs APNs; the contacts picker needs Swift. Both wait for the iOS folder.

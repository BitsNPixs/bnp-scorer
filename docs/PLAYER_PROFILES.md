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
- [ ] Upgrade to Blaze with a budget alert. Owner asked (2026-11-21) to test with dummy codes first: use test phone numbers (next item), which send no SMS and cost nothing. Whether the console allows phone sign-in on Spark at all is unconfirmed; if it refuses, Blaze with a budget alert and only test numbers still costs nothing.
- [x] Authentication > Sign-in method: enable Phone; Settings > SMS region policy: allow India (and United States for the +1 test numbers; the policy blocks test numbers too). (2026-11-21; a test number then linked on the owner's phone.)
- [ ] Before testers: remove any real number from the test list (a test number accepts its fixed code from anyone).
- [ ] Enable the Play Integrity API on the Google Cloud project (else a reCAPTCHA page opens in the browser). Optional: it only spares players that page; sideloaded betas may see it anyway.
- [ ] Add test phone numbers under Phone > Phone numbers for testing: fictional ones such as +1 650-555-3434 and +1 650-555-3435, each with a six-digit code like 123456 (Firebase codes are six digits, so 1234 will not do). Up to 10.
- [x] Paste the new `firestore.rules`. (Owner, 2026-11-21.)
- [ ] Check the hash matches: easiest end to end, by confirming a test number in Settings and seeing "Verified" under My profile (a mismatch shows "The cloud refused this"). The phone document for +16505553434 is `phones/661c9cd16b8d7726a54b1b683842f5cdde36cf65722ae7e74b00c06e64695e46`.

## Release 2: profile fields
- [x] Playing role, batting style, bowling arm and type, home town on `players/{id}`. (2026-11-21)
- [x] INFO tab rows; owner-only Edit profile sheet + tests. (2026-11-21)
- [x] Privacy text: styles and home town are public. (2026-11-21)

## Release 3: pick from phone contacts
- [x] `MainActivity.kt` picker channel; `DeviceContacts` + fake; button in the add-by-number sheet + tests. (2026-11-21)
- [x] README Data safety and privacy Permissions paragraph; site feature list. (2026-11-21)

## Release 4: teams in the cloud, join code, invite, join requests
- [x] `CloudTeams`, `SyncingTeamRepository`, `teams` rules. (2026-11-21)
- [x] Join a team by code; captain accepts requests; Share invite; `site/join.html`. (2026-11-21; a team is public only once its invite is shared)
- [x] Profile Teams panel lists published teams; privacy text; ROADMAP cloud step 5. (2026-11-21)

## Release 5: one-tap link, QR, share a profile
- [x] Opening the app from an invite: the join page's "Open in BNP Scorer" button (`bnpscorer://join`), handled in `HomeScreen`. (2026-11-21; verified App Links need `/.well-known/assetlinks.json` at the root of bitsnpixs.github.io, which this project's Pages site does not serve, so they wait for a domain the project controls)
- [x] QR for the invite; scorecard rows open profiles; share a profile as text. (2026-11-21)

## After the releases (owner's asks)
- [x] Sign in with a mobile number beside Google; name asked once; link Google later. (2026-11-21, owner chose "offer both")
- [x] Profile photos on Cloudflare R2 through `cloud/photos-worker` (owner's choice). (2026-11-21; the Worker is deployed once the owner logs Wrangler in)
- [x] Team logos on the same Worker. (2026-11-21)
- [ ] Deploy: owner enables R2 and logs in (`npx wrangler login`); bucket `bnp-photos`; set the Worker address in the app; paste the rules.
- [ ] Before wide release: a way to report a photo.

## Later, tied to account deletion (ROADMAP "Before the Play Store")
- [ ] Deleting the account also forgets the number, releases the profile and unlinks phone auth.

## Open items and risks
- Enumeration of `phones/` by a signed-in attacker at Firestore read prices: sign-in is required now; App Check or a rate-limited Function later.
- A recycled number inherits the old profile (the number is the identity).
- "This year" and ordering use `MatchRecord.createdAt`, the phone's clock.
- Matches published by scorers who never update to beta.7 have no `playerIds` and stay off profiles, including when opened from a watched cup.
- iOS: phone auth needs APNs; the contacts picker needs Swift. Both wait for the iOS folder.

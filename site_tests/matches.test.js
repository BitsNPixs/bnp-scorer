// Tests for the website's match pages (site/matches.js): the helpers that
// decide what a page says, and the rules that keep it safe. Run from the
// repo root with: node --test site_tests
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const site = path.join(__dirname, '..', 'site');
const h = require(path.join(site, 'matches.js'));
const source = fs.readFileSync(path.join(site, 'matches.js'), 'utf8');

const now = Date.parse('2026-11-27T12:00:00Z');

/** Lions (batted first, 40/2) v Tigers (chasing, 12/1). */
function chase(extra) {
  return Object.assign({
    id: 'm1',
    state: 'live',
    venue: 'Marina Ground',
    oversPerInnings: 10,
    superOver: false,
    teams: [{ id: 'b', name: 'Tigers', logoUrl: null }, { id: 'a', name: 'Lions', logoUrl: null }],
    result: null,
    innings: [
      { battingTeamId: 'a', team: 'Lions', runs: 40, wickets: 2, overs: '10', score: '40/2', complete: true,
        overByOver: [{ balls: [{ label: '1', kind: 'runs' }] }] },
      { battingTeamId: 'b', team: 'Tigers', runs: 12, wickets: 1, overs: '1.3', score: '12/1', complete: false,
        overByOver: [{ balls: [{ label: '4', kind: 'four' }] }, { balls: [{ label: 'W', kind: 'wicket' }, { label: '0', kind: 'dot' }] }] },
    ],
  }, extra);
}

test('only a real match id is taken from the address', () => {
  assert.equal(h.matchIdFrom('?id=hoduxmluoisrh0u9'), 'hoduxmluoisrh0u9');
  assert.equal(h.matchIdFrom('?x=1&id=a_b-9'), 'a_b-9');
  for (const bad of ['', '?id=', '?id=a/b', '?id=../x', '?id=<script>', '?id=' + 'x'.repeat(65), '?other=1']) {
    assert.equal(h.matchIdFrom(bad), null, bad);
  }
});

test('how long ago reads the way people say it', () => {
  const at = (ms) => new Date(now - ms).toISOString();
  assert.equal(h.ago(at(5 * 1000), now), 'just now');
  assert.equal(h.ago(at(5 * 60 * 1000), now), '5 min ago');
  assert.equal(h.ago(at(3 * 3600 * 1000), now), '3 h ago');
  assert.equal(h.ago(at(26 * 3600 * 1000), now), '1 day ago');
  assert.equal(h.ago(at(9 * 24 * 3600 * 1000), now), '9 days ago');
  assert.equal(h.ago(at(59 * 1000), now), 'just now');
  assert.equal(h.ago(at(119 * 1000), now), '1 min ago', 'never rounded up');
  assert.equal(h.ago(at(5.5 * 24 * 3600 * 1000), now), '5 days ago');
  assert.equal(h.ago(new Date(now + 60000).toISOString(), now), 'just now', 'a clock a little ahead');
  assert.equal(h.ago('not a time', now), '');
  assert.equal(h.ago(undefined, now), '');
});

test('the pill says Live, Result or Stopped', () => {
  assert.equal(h.stateLabel('live'), 'Live');
  assert.equal(h.stateLabel('finished'), 'Result');
  assert.equal(h.stateLabel('stopped'), 'Stopped');
  assert.equal(h.stateLabel(undefined), 'Live');
});

test('a logo is shown only from the app\'s own photo service', () => {
  const ours = 'https://bnp-photos.quikfly-api.workers.dev/img/teams/u1/t1.img?v=2';
  assert.equal(h.trustedLogo(ours), ours);
  for (const bad of [null, undefined, 7, '', 'http://bnp-photos.quikfly-api.workers.dev/x',
    'https://evil.example/bnp-photos.quikfly-api.workers.dev/x', 'javascript:alert(1)',
    'https://bnp-photos.quikfly-api.workers.dev.evil.example/x']) {
    assert.equal(h.trustedLogo(bad), null, String(bad));
  }
});

test('initials and plurals', () => {
  assert.equal(h.initials('Lewis Team'), 'LT');
  assert.equal(h.initials('Melpuram Cricket Club'), 'MC');
  assert.equal(h.initials('home'), 'HO');
  assert.equal(h.initials('  '), '?');
  assert.equal(h.initials(null), '?');
  assert.equal(h.plural(1, 'over'), '1 over');
  assert.equal(h.plural(10, 'over'), '10 overs');
});

test('the line under the pill names the ground and the overs', () => {
  assert.equal(h.whereLine(chase()), 'Marina Ground · 10 overs');
  assert.equal(h.whereLine(chase({ venue: null, oversPerInnings: 1 })), '1 over');
  assert.equal(h.whereLine(chase({ venue: null, superOver: true, oversPerInnings: 1 })), '1 over · Super Over');
});

test('sides come in batting order, with the side batting now marked', () => {
  const sides = h.sides(chase());
  assert.deepEqual(sides.map((s) => s.team.name), ['Lions', 'Tigers']);
  assert.deepEqual(sides.map((s) => s.innings.score), ['40/2', '12/1']);
  assert.deepEqual(sides.map((s) => s.batting), [false, true]);
  assert.deepEqual(sides.map((s) => s.winner), [false, false]);
});

test('a finished match marks the winner, not a side batting', () => {
  const sides = h.sides(chase({ state: 'finished', result: { winnerTeamId: 'a' } }));
  assert.deepEqual(sides.map((s) => s.winner), [true, false]);
  assert.deepEqual(sides.map((s) => s.batting), [false, false]);
});

test('a side that has not batted has no score, even with its innings opened', () => {
  const match = chase();
  match.innings[1] = { battingTeamId: 'b', team: 'Tigers', runs: 0, wickets: 0, overs: '0', score: '0/0', complete: false, overByOver: [] };
  assert.equal(h.sides(match)[1].innings, null);
  match.innings.pop();
  assert.equal(h.sides(match)[1].innings, null);
  assert.equal(h.sides(chase({ innings: [], state: 'live' })).length, 2, 'no innings at all still lists both teams');
});

test('this over is the last over bowled', () => {
  assert.deepEqual(h.thisOver(chase().innings[1]).map((b) => b.label), ['W', '0']);
  assert.deepEqual(h.thisOver({ overByOver: [] }), []);
  assert.deepEqual(h.thisOver(undefined), []);
});

test('a scorecard row is found by player id', () => {
  const rows = [{ id: 'a1', name: 'Asha' }, { id: 'a2', name: 'Bilal' }];
  assert.equal(h.rowOf(rows, 'a2').name, 'Bilal');
  assert.equal(h.rowOf(rows, 'zz'), null);
  assert.equal(h.rowOf(undefined, 'a1'), null);
});

test('extras and rates read as the app\'s scorecard does', () => {
  assert.equal(h.extrasText({ wides: 2, noBalls: 0, byes: 0, legByes: 1 }), 'wd 2, lb 1');
  assert.equal(h.extrasText({ wides: 1, noBalls: 1, byes: 1, legByes: 1 }), 'wd 1, nb 1, b 1, lb 1');
  assert.equal(h.extrasText({ wides: 0, noBalls: 0, byes: 0, legByes: 0 }), 'None');
  assert.equal(h.rate(7.5), '7.50');
  assert.equal(h.rate(133.33), '133.33');
  assert.equal(h.rate(0), '0.00');
  assert.equal(h.rate(null), '—');
});

test('the list is grouped by what each match is doing, order kept', () => {
  const groups = h.groupMatches([
    { id: '1', state: 'stopped' }, { id: '2', state: 'live' }, { id: '3', state: 'finished' },
    { id: '4', state: 'live' }, { id: '5' },
  ]);
  assert.deepEqual(groups.live.map((m) => m.id), ['2', '4', '5']);
  assert.deepEqual(groups.finished.map((m) => m.id), ['3']);
  assert.deepEqual(groups.stopped.map((m) => m.id), ['1']);
  assert.deepEqual(h.groupMatches(undefined), { live: [], finished: [], stopped: [] });
});

test('a live match is asked about often, a stopped one rarely, a finished one never again', () => {
  assert.equal(h.refreshMs('live'), 10000);
  assert.equal(h.refreshMs('stopped'), 60000);
  assert.equal(h.refreshMs('finished'), null);
  assert.equal(h.refreshMs(undefined), null);
});

test('tabs are one per innings, then Overs; none before an innings', () => {
  assert.deepEqual(h.tabsOf(chase()).map((t) => t.label), ['Lions', 'Tigers', 'Overs']);
  assert.deepEqual(h.tabsOf(chase()).map((t) => t.key), ['innings-0', 'innings-1', 'overs']);
  assert.deepEqual(h.tabsOf({ innings: [] }), []);
});

// ---- the live connection ---------------------------------------------------

test('a stored match says live, stopped or finished by the same six hours as the app', () => {
  const saved = (ms) => new Date(now - ms).toISOString();
  assert.equal(h.stateOf({ stage: 'live', sourceUpdateTime: saved(60 * 1000) }, now), 'live');
  assert.equal(h.stateOf({ stage: 'inningsBreak', sourceUpdateTime: saved(6 * 3600 * 1000 - 1000) }, now), 'live');
  assert.equal(h.stateOf({ stage: 'live', sourceUpdateTime: saved(6 * 3600 * 1000) }, now), 'stopped');
  assert.equal(h.stateOf({ stage: 'starting', sourceUpdateTime: saved(9 * 24 * 3600 * 1000) }, now), 'stopped');
  assert.equal(h.stateOf({ stage: 'finished', sourceUpdateTime: saved(9 * 24 * 3600 * 1000) }, now), 'finished');
  assert.equal(h.stateOf({ stage: 'finished', sourceUpdateTime: saved(1000) }, now), 'finished');
  assert.equal(h.stateOf({ stage: 'live' }, now), 'live', 'no save time: live, not hidden');
});

test('the six hours here are the six hours in the shared Dart rule', () => {
  const dart = fs.readFileSync(path.join(__dirname, '..', 'packages', 'match_view', 'lib', 'src', 'now.dart'), 'utf8');
  assert.match(dart, /const stoppedAfter = Duration\(hours: 6\);/);
  assert.match(source, /STOPPED_AFTER_MS = 6 \* 60 \* 60 \* 1000;/);
});

test('a stored match is shown as the API would send it', () => {
  const copy = { id: 'm1', stage: 'live', status: 'Lions 4/0', ownerUid: 'secret', ownerName: 'Aswin',
    sourceUpdateTime: new Date(now - 5000).toISOString(), innings: [] };
  const view = h.viewFromCopy(copy, now);
  assert.equal(view.state, 'live');
  assert.equal(view.status, 'Lions 4/0');
  assert.equal(view.ownerName, 'Aswin');
  assert.equal('ownerUid' in view, false);
  assert.equal(copy.ownerUid, 'secret', 'the copy itself is left alone');
});

test('an older save never replaces a newer one on the page', () => {
  const at = (s) => ({ sourceUpdateTime: '2026-11-27T10:00:' + s + 'Z' });
  assert.equal(h.mayReplace(at('05'), null), true, 'nothing shown yet');
  assert.equal(h.mayReplace(at('09'), at('05')), true);
  assert.equal(h.mayReplace(at('05.250000'), at('05.250000')), true, 'the same save again');
  assert.equal(h.mayReplace(at('05'), at('09')), false, 'a kept answer arriving late');
  assert.equal(h.mayReplace({}, at('09')), true, 'with no time to compare, show it');
});

test('the Firestore library is this site\'s own copy and names no other server to load from', () => {
  const dir = path.join(site, 'vendor', 'firebase');
  for (const file of ['firebase-app.js', 'firebase-firestore.js']) {
    const code = fs.readFileSync(path.join(dir, file), 'utf8');
    assert.equal(/\bfrom\s*["']https?:/.test(code), false, file + ' imports from another server');
    assert.equal(/\bimport\s*\(\s*["']https?:/.test(code), false, file + ' loads from another server');
  }
  assert.match(fs.readFileSync(path.join(dir, 'firebase-firestore.js'), 'utf8'), /from"\.\/firebase-app\.js"/);
  const loads = source.match(/import\('[^']+'\)/g);
  assert.deepEqual(loads, ["import('./vendor/firebase/firebase-app.js')", "import('./vendor/firebase/firebase-firestore.js')"]);
  assert.ok(fs.existsSync(path.join(dir, 'README.txt')));
});

// ---- safety, checked on the source itself ---------------------------------

test('text from the API is never written as HTML', () => {
  for (const risky of ['innerHTML', 'outerHTML', 'insertAdjacentHTML', 'document.write', 'eval(']) {
    assert.equal(source.includes(risky), false, risky);
  }
});

test('the pages talk only to the BNP API over https, and load nothing from elsewhere', () => {
  const urls = source.match(/https?:\/\/[^'"\s)]+/g) || [];
  assert.deepEqual([...new Set(urls)].sort(), [
    'https://bnp-api-482745302753.asia-south1.run.app',
    'https://bnp-photos.quikfly-api.workers.dev/',
  ]);
  for (const page of ['match.html', 'matches.html']) {
    const html = fs.readFileSync(path.join(site, page), 'utf8');
    const loaded = [...html.matchAll(/<(?:script|link|img)[^>]*?(?:src|href)="([^"]+)"/g)].map((m) => m[1]);
    assert.ok(loaded.length >= 4, page);
    for (const url of loaded) assert.equal(/^(https?:)?\/\//.test(url), false, `${page} loads ${url}`);
    for (const file of loaded) assert.ok(fs.existsSync(path.join(site, file)), `${page}: ${file} exists`);
    assert.match(html, /<script src="matches\.js"><\/script>/);
  }
});

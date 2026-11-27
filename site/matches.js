/* BNP Scorer on the web: the matches list (matches.html) and one match
   (match.html?id=…), read from the public API. Every score is worked out by
   the server with the app's own scoring engine; this file only lays it out.

   Text from the API is always set with textContent, never as HTML, so a team
   or player name can never run as markup. The helpers at the top touch no
   page and are tested with Node (site_tests/). */
(function (root) {
  'use strict';

  var API = 'https://bnp-api-482745302753.asia-south1.run.app';
  var PHOTOS = 'https://bnp-photos.quikfly-api.workers.dev/';

  /* How often a page asks again, by what its match is doing. A stopped match
     may start again; a finished one will not change. */
  var REFRESH_MS = { live: 10000, stopped: 60000 };

  // ---- helpers (no page needed) -----------------------------------------

  /** The match id in a page address ("?id=abc"), or null if it is not one. */
  function matchIdFrom(search) {
    var id = new URLSearchParams(search || '').get('id') || '';
    return /^[A-Za-z0-9_-]{1,64}$/.test(id) ? id : null;
  }

  /** "just now", "5 min ago", "3 h ago", "2 days ago". */
  function ago(iso, now) {
    var then = Date.parse(iso);
    if (isNaN(then)) return '';
    var seconds = Math.max(0, Math.round((now - then) / 1000));
    if (seconds < 45) return 'just now';
    var minutes = Math.round(seconds / 60);
    if (minutes < 60) return minutes + ' min ago';
    var hours = Math.round(minutes / 60);
    if (hours < 24) return hours + ' h ago';
    var days = Math.round(hours / 24);
    return days + (days === 1 ? ' day ago' : ' days ago');
  }

  /** The word on a match's pill. An unknown state reads as live, as the app does. */
  function stateLabel(state) {
    return state === 'finished' ? 'Result' : state === 'stopped' ? 'Stopped' : 'Live';
  }

  /** A team logo only from the app's own photo service; anything else is dropped. */
  function trustedLogo(url) {
    return typeof url === 'string' && url.indexOf(PHOTOS) === 0 ? url : null;
  }

  /** "LT" for "Lewis Team", "HO" for "Home". */
  function initials(name) {
    var parts = String(name || '').trim().split(/\s+/).filter(Boolean);
    if (!parts.length) return '?';
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  /** "10 overs", "1 over". */
  function plural(count, word) {
    return count + ' ' + word + (count === 1 ? '' : 's');
  }

  /** "Marina Ground · 10 overs", or just the overs. */
  function whereLine(match) {
    var parts = [];
    if (match.venue) parts.push(match.venue);
    parts.push(plural(match.oversPerInnings, 'over') + (match.superOver ? ' · Super Over' : ''));
    return parts.join(' · ');
  }

  /** Each team with its innings (or null before it bats), batting order first. */
  function sides(match) {
    var innings = match.innings || [];
    function inningsOf(teamId) {
      for (var i = 0; i < innings.length; i++) {
        var inn = innings[i];
        var began = inn.overs !== '0' || inn.runs > 0 || inn.wickets > 0 || inn.complete;
        if (inn.battingTeamId === teamId && began) return inn;
      }
      return null;
    }
    var teams = (match.teams || []).slice();
    var first = innings.length ? innings[0].battingTeamId : null;
    teams.sort(function (a, b) { return (b.id === first) - (a.id === first); });
    var winner = match.result ? match.result.winnerTeamId : null;
    var batting = match.state === 'finished' || !innings.length ? null : innings[innings.length - 1].battingTeamId;
    return teams.map(function (team) {
      return { team: team, innings: inningsOf(team.id), winner: team.id === winner, batting: team.id === batting };
    });
  }

  /** The balls of the over being bowled, for "this over". Empty before a ball. */
  function thisOver(innings) {
    var overs = (innings && innings.overByOver) || [];
    return overs.length ? overs[overs.length - 1].balls : [];
  }

  /** A row of the scorecard by player id, or null. */
  function rowOf(rows, id) {
    for (var i = 0; i < (rows || []).length; i++) if (rows[i].id === id) return rows[i];
    return null;
  }

  /** Extras as the scorecard words them: "wd 2, lb 1", or "None". */
  function extrasText(extras) {
    var parts = [];
    if (extras.wides) parts.push('wd ' + extras.wides);
    if (extras.noBalls) parts.push('nb ' + extras.noBalls);
    if (extras.byes) parts.push('b ' + extras.byes);
    if (extras.legByes) parts.push('lb ' + extras.legByes);
    return parts.length ? parts.join(', ') : 'None';
  }

  /** A number to at most two places, as the app prints rates: "7.50", "133.33". */
  function rate(value) {
    return typeof value === 'number' ? value.toFixed(2) : '—';
  }

  /** The list in three groups, each in the order the API gave (newest first). */
  function groupMatches(matches) {
    var groups = { live: [], finished: [], stopped: [] };
    (matches || []).forEach(function (m) {
      (groups[m.state] || groups.live).push(m);
    });
    return groups;
  }

  /** How long to wait before asking again, or null to stop asking. */
  function refreshMs(state) {
    return REFRESH_MS[state] || null;
  }

  /** The tabs of a match page: one per innings, then Overs. */
  function tabsOf(match) {
    var tabs = (match.innings || []).map(function (inn, i) {
      return { key: 'innings-' + i, label: inn.team, innings: i };
    });
    if (tabs.length) tabs.push({ key: 'overs', label: 'Overs' });
    return tabs;
  }

  var helpers = {
    matchIdFrom: matchIdFrom, ago: ago, stateLabel: stateLabel, trustedLogo: trustedLogo,
    initials: initials, plural: plural, whereLine: whereLine, sides: sides, thisOver: thisOver,
    rowOf: rowOf, extrasText: extrasText, rate: rate, groupMatches: groupMatches,
    refreshMs: refreshMs, tabsOf: tabsOf,
  };
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = helpers;
    return;
  }

  // ---- page building ----------------------------------------------------

  var doc = root.document;

  /** An element with a class and plain text; children are appended after. */
  function el(tag, className, text) {
    var node = doc.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    for (var i = 3; i < arguments.length; i++) if (arguments[i]) node.appendChild(arguments[i]);
    return node;
  }

  function pill(state) {
    return el('span', 'pill ' + (state === 'finished' || state === 'stopped' ? state : 'live'), stateLabel(state));
  }

  function badge(team) {
    var logo = trustedLogo(team.logoUrl);
    if (!logo) return el('span', 'badge', initials(team.name));
    var img = el('img', 'badge');
    img.src = logo;
    img.alt = '';
    img.width = 36;
    img.height = 36;
    return img;
  }

  function ballChip(ball) {
    var kinds = { dot: 1, runs: 1, four: 1, six: 1, extra: 1, wicket: 1 };
    return el('span', 'ball ' + (kinds[ball.kind] ? ball.kind : 'runs'), ball.kind === 'dot' ? '•' : ball.label);
  }

  function sideRows(match) {
    return sides(match).map(function (side) {
      var row = el('div', 'side' + (side.winner || side.batting ? ' strong' : ''));
      row.appendChild(badge(side.team));
      row.appendChild(el('span', 'name', side.team.name));
      if (side.innings) {
        row.appendChild(el('span', 'score', side.innings.score));
        row.appendChild(el('span', 'overs', '(' + side.innings.overs + ')'));
      } else {
        row.appendChild(el('span', 'overs', 'Yet to bat'));
      }
      return row;
    });
  }

  function fetchJson(path) {
    return root.fetch(API + path, { headers: { accept: 'application/json' } }).then(function (response) {
      if (response.status === 404) return null;
      if (!response.ok) throw new Error('HTTP ' + response.status);
      return response.json();
    });
  }

  /** Runs [load] now and again after each answer, only while the tab shows. */
  function keepFresh(load) {
    var timer = null;
    function again(ms) {
      root.clearTimeout(timer);
      if (ms) timer = root.setTimeout(run, ms);
    }
    function run() {
      if (doc.hidden) return;
      load().then(again, function () { again(30000); });
    }
    doc.addEventListener('visibilitychange', function () { if (!doc.hidden) run(); });
    run();
  }

  function notice(page, title, text) {
    page.replaceChildren(el('section', 'notice', null, el('h1', null, title), el('p', null, text),
      el('p', null, null, link('matches.html', 'See all matches'))));
  }

  function link(href, text, className) {
    var a = el('a', className, text);
    a.href = href;
    return a;
  }

  // ---- the list -----------------------------------------------------------

  function matchCard(match, now) {
    var card = link('match.html?id=' + encodeURIComponent(match.id), null, 'card');
    card.appendChild(el('div', 'meta', null, pill(match.state), el('span', 'where', whereLine(match))));
    sideRows(match).forEach(function (row) { card.appendChild(row); });
    card.appendChild(el('p', 'status', match.status));
    var when = match.state === 'live' ? '' : ' · ' + ago(match.sourceUpdateTime, now);
    card.appendChild(el('p', 'by', 'Scored by ' + match.ownerName + when));
    return card;
  }

  function initList() {
    var page = doc.getElementById('page');
    keepFresh(function () {
      return fetchJson('/v1/matches?limit=50').then(function (body) {
        var groups = groupMatches(body ? body.matches : []);
        var now = Date.now();
        var out = [];
        [['live', 'Live now'], ['finished', 'Results'], ['stopped', 'Stopped']].forEach(function (group) {
          var matches = groups[group[0]];
          if (!matches.length) return;
          var section = el('section', 'group', null, el('h2', null, group[1]));
          if (group[0] === 'stopped') {
            section.appendChild(el('p', 'hint', 'Not finished, and no ball for six hours or more.'));
          }
          var grid = el('div', 'cards');
          matches.forEach(function (m) { grid.appendChild(matchCard(m, now)); });
          section.appendChild(grid);
          out.push(section);
        });
        if (!out.length) {
          out.push(el('section', 'notice', null, el('h1', null, 'No matches yet'),
            el('p', null, 'When a signed-in scorer starts a match in BNP Scorer, it shows here ball by ball.')));
        }
        page.replaceChildren.apply(page, out);
        return groups.live.length ? 30000 : 120000;
      }, function (error) {
        if (!page.querySelector('.card')) {
          page.replaceChildren(el('section', 'notice', null, el('h1', null, 'Could not load matches'),
            el('p', null, 'Check your connection. This page tries again by itself.')));
        }
        throw error;
      });
    });
  }

  // ---- one match ----------------------------------------------------------

  function heroOf(match) {
    var hero = el('section', 'hero-card');
    hero.appendChild(el('div', 'meta', null, pill(match.state), el('span', 'where', whereLine(match))));
    sideRows(match).forEach(function (row) { hero.appendChild(row); });
    var status = el('p', 'status', match.status);
    status.setAttribute('aria-live', 'polite');
    hero.appendChild(status);

    var innings = match.innings[match.innings.length - 1];
    var crease = innings && innings.atCrease;
    if (crease && match.state !== 'finished') {
      var box = el('div', 'crease');
      [crease.strikerId, crease.nonStrikerId].forEach(function (id, i) {
        var batter = rowOf(innings.batters, id);
        if (!batter) return;
        box.appendChild(el('p', 'at', null,
          el('span', 'who', batter.name + (i === 0 ? ' *' : '')),
          el('span', 'num', batter.runs + ' (' + batter.balls + ')')));
      });
      var bowler = rowOf(innings.bowlers, crease.bowlerId);
      if (bowler) {
        box.appendChild(el('p', 'at bowler', null,
          el('span', 'who', bowler.name),
          el('span', 'num', bowler.overs + '-' + bowler.maidens + '-' + bowler.runs + '-' + bowler.wickets)));
      }
      var balls = thisOver(innings);
      if (balls.length) {
        var over = el('div', 'over');
        over.setAttribute('aria-label', 'This over');
        balls.forEach(function (ball) { over.appendChild(ballChip(ball)); });
        box.appendChild(over);
      }
      if (box.childNodes.length) hero.appendChild(box);
    }
    if (match.playerOfTheMatch) {
      hero.appendChild(el('p', 'potm', null, el('span', 'label', 'Player of the match'),
        el('strong', null, match.playerOfTheMatch.name)));
    }
    return hero;
  }

  function table(caption, head, rows) {
    var t = el('table', 'sheet');
    t.appendChild(el('caption', null, caption));
    var tr = el('tr');
    head.forEach(function (h, i) {
      var th = el('th', i === 0 ? 'first' : null, h);
      th.scope = 'col';
      tr.appendChild(th);
    });
    t.appendChild(el('thead', null, null, tr));
    var body = el('tbody');
    rows.forEach(function (cells) {
      var row = el('tr');
      cells.forEach(function (cell, i) {
        row.appendChild(i === 0 ? cell : el('td', null, cell));
      });
      body.appendChild(row);
    });
    t.appendChild(body);
    return t;
  }

  function scorecard(innings) {
    var panel = el('div', 'panel');
    var atCrease = innings.atCrease || {};
    panel.appendChild(table('Batting · ' + innings.team, ['Batter', 'R', 'B', '4s', '6s', 'SR'],
      innings.batters.map(function (b) {
        var live = b.id === atCrease.strikerId || b.id === atCrease.nonStrikerId;
        var first = el('th', 'first', null, el('span', 'who' + (live ? ' in' : ''), b.name), el('span', 'how', b.howOut));
        first.scope = 'row';
        return [first, b.runs, b.balls, b.fours, b.sixes, rate(b.strikeRate)];
      })));
    panel.appendChild(el('p', 'line', null, el('span', null, 'Extras'),
      el('span', 'muted', extrasText(innings.extras)), el('strong', null, innings.extras.total)));
    panel.appendChild(el('p', 'line total', null, el('span', null, 'Total'),
      el('span', 'muted', innings.overs + ' of ' + innings.maxOvers + ' ov · RR ' + rate(innings.runRate)),
      el('strong', null, innings.score)));
    if (innings.yetToBat.length) {
      panel.appendChild(el('p', 'yet', null, el('span', 'label', 'Yet to bat'),
        el('span', null, innings.yetToBat.map(function (p) { return p.name; }).join(', '))));
    }
    if (innings.bowlers.length) {
      panel.appendChild(table('Bowling', ['Bowler', 'O', 'M', 'R', 'W', 'Econ'],
        innings.bowlers.map(function (f) {
          var first = el('th', 'first', null, el('span', 'who', f.name));
          first.scope = 'row';
          return [first, f.overs, f.maidens, f.runs, f.wickets, rate(f.economy)];
        })));
    }
    if (innings.fallOfWickets.length) {
      var fall = el('div', 'fall', null, el('h3', null, 'Fall of wickets'));
      var list = el('ol');
      innings.fallOfWickets.forEach(function (w) {
        list.appendChild(el('li', null, null, el('strong', null, w.score), el('span', null, w.name),
          el('span', 'muted', w.over + ' ov')));
      });
      fall.appendChild(list);
      panel.appendChild(fall);
    }
    return panel;
  }

  function oversPanel(match) {
    var panel = el('div', 'panel');
    // The innings being played first, and in it the newest over first.
    match.innings.slice().reverse().forEach(function (innings) {
      panel.appendChild(el('h3', null, innings.team + ' · ' + innings.label));
      if (!innings.overByOver.length) {
        panel.appendChild(el('p', 'muted', 'No ball bowled yet.'));
        return;
      }
      var list = el('ol', 'overs-list');
      innings.overByOver.slice().reverse().forEach(function (over) {
        var balls = el('div', 'over');
        over.balls.forEach(function (ball) { balls.appendChild(ballChip(ball)); });
        list.appendChild(el('li', null, null,
          el('div', 'over-head', null, el('strong', null, 'Over ' + over.number),
            el('span', 'muted', plural(over.runs, 'run') + (over.wickets ? ', ' + plural(over.wickets, 'wicket') : '')),
            el('span', 'after', over.score)),
          el('p', 'muted', over.headline), balls));
      });
      panel.appendChild(list);
    });
    return panel;
  }

  function initMatch() {
    var page = doc.getElementById('page');
    var id = matchIdFrom(root.location.search);
    if (!id) return notice(page, 'No match chosen', 'This link does not name a match.');
    var chosen = null;

    function draw(match) {
      var tabs = tabsOf(match);
      // Open on the innings being played (or the last one); keep the reader's
      // own choice across refreshes.
      if (!tabs.some(function (t) { return t.key === chosen; })) {
        chosen = tabs.length ? 'innings-' + (match.innings.length - 1) : null;
      }
      var out = [heroOf(match)];
      if (tabs.length) {
        var bar = el('div', 'tabs');
        bar.setAttribute('role', 'tablist');
        tabs.forEach(function (tab) {
          var button = el('button', tab.key === chosen ? 'on' : null, tab.label);
          button.type = 'button';
          button.setAttribute('role', 'tab');
          button.setAttribute('aria-selected', tab.key === chosen ? 'true' : 'false');
          button.addEventListener('click', function () { chosen = tab.key; draw(match); });
          bar.appendChild(button);
        });
        out.push(bar);
        var open = tabs.filter(function (t) { return t.key === chosen; })[0];
        out.push(open.key === 'overs' ? oversPanel(match) : scorecard(match.innings[open.innings]));
      }
      out.push(el('p', 'by', 'Scored by ' + match.ownerName + ' with BNP Scorer · last ball ' +
        ago(match.sourceUpdateTime, Date.now())));
      page.replaceChildren.apply(page, out);
      var names = match.teams.map(function (t) { return t.name; }).join(' v ');
      doc.title = names + ' · ' + match.status + ' · BNP Scorer';
    }

    keepFresh(function () {
      return fetchJson('/v1/matches/' + encodeURIComponent(id)).then(function (match) {
        if (!match) {
          notice(page, 'Match not found', 'This match is no longer published, or the link is wrong.');
          return null;
        }
        draw(match);
        return refreshMs(match.state);
      }, function (error) {
        if (!page.querySelector('.hero-card')) {
          notice(page, 'Could not load the match', 'Check your connection. This page tries again by itself.');
        }
        throw error;
      });
    });
  }

  root.BnpMatches = { initList: initList, initMatch: initMatch };
})(typeof window !== 'undefined' ? window : globalThis);

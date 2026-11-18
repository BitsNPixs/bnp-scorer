import 'dart:convert';
import 'dart:io';

import 'package:bnp_scorer/data/device_files.dart';
import 'package:bnp_scorer/data/squad_import.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ids in order: id1, id2, ...
String Function() _ids() {
  var n = 0;
  return () => 'id${++n}';
}

List<String> _names(Iterable<ImportedPlayer> players) => [for (final p in players) p.name];

void main() {
  group('one line of a list', () {
    test('numbering, bullets, WhatsApp bold and emoji go', () {
      for (final line in ['1. Asha', '1) Asha', '01 - Asha', '1.Asha', '#1 Asha', '- Asha', '• Asha', '*Asha*', 'Asha 🏏🔥']) {
        expect(parsePlayerLine(line)?.name, 'Asha', reason: line);
      }
    });

    test('marks in brackets, after a dash or as symbols become jobs and roles', () {
      final captain = parsePlayerLine('1. Asha (c)')!;
      expect(captain.captain, isTrue);
      expect(captain.name, 'Asha');

      final both = parsePlayerLine('Bilal (c & wk)')!;
      expect([both.captain, both.keeper, both.viceCaptain], [true, true, false]);

      expect(parsePlayerLine('Chitra (VC)')!.viceCaptain, isTrue);
      expect(parsePlayerLine('Chitra (Vice-Captain)')!.viceCaptain, isTrue);
      expect(parsePlayerLine('Devi - wk')!.keeper, isTrue);
      expect(parsePlayerLine('Devi [Wicket keeper]')!.keeper, isTrue);
      expect(parsePlayerLine('Esha ©')!.captain, isTrue);
      expect(parsePlayerLine('Farid 🧤')!.keeper, isTrue);
      expect(parsePlayerLine('Gopal (bowler)')!.role, PlayerRole.bowler);
      expect(parsePlayerLine('Hari (AR)')!.role, PlayerRole.allRounder);
      expect(parsePlayerLine('Indu (c, batter)')!.marks, ['C', 'Batter']);
    });

    test('a bare mark at the end counts, but a lone letter stays as an initial', () {
      expect(parsePlayerLine('Bilal wk')!.keeper, isTrue);
      expect(parsePlayerLine('Bilal wk')!.name, 'Bilal');
      final initial = parsePlayerLine('Ravi C')!;
      expect(initial.name, 'Ravi C');
      expect(initial.captain, isFalse);
    });

    test('brackets that are not marks stay in the name', () {
      expect(parsePlayerLine('Ravi (Ravi Kumar)')!.name, 'Ravi (Ravi Kumar)');
    });

    test('a number in a name stays, but a line of only numbers is not a player', () {
      expect(parsePlayerLine('Ravi 2')!.name, 'Ravi 2');
      expect(parsePlayerLine('3. Ravi 2')!.name, 'Ravi 2');
      expect(parsePlayerLine('Alpha P12')!.name, 'Alpha P12');
      expect(parsePlayerLine('12'), isNull);
      expect(parsePlayerLine('1.'), isNull);
    });

    test('initials, apostrophes and hyphens survive', () {
      expect(parsePlayerLine('M. Monish Savio')!.name, 'M. Monish Savio');
      expect(parsePlayerLine("D'Souza")!.name, "D'Souza");
      expect(parsePlayerLine('Jean-Paul')!.name, 'Jean-Paul');
    });

    test('blank lines, headings and sentences are not players', () {
      expect(parsePlayerLine(''), isNull);
      expect(parsePlayerLine('   '), isNull);
      expect(parsePlayerLine('Team A:'), isNull);
      expect(parsePlayerLine('🏏🔥'), isNull);
      expect(parsePlayerLine('Match tomorrow at the main ground please come early'), isNull);
    });
  });

  group('a pasted list', () {
    test('a WhatsApp message gives every player once, in order', () {
      const message = '*Warriors XI* 🏏\n'
          'Playing:\n'
          '1. Asha (c)\n'
          '2. Bilal (wk)\n'
          '\n'
          '3. Chitra\n'
          '4. asha\n'
          '5. Devi (vc)';
      final players = parsePlayerList(message);
      expect(_names(players), ['Warriors XI', 'Asha', 'Bilal', 'Chitra', 'Devi']);
      expect([for (final p in players) p.likelyHeading], [true, false, false, false, false],
          reason: 'in a numbered list the unnumbered line is probably a heading');
      expect(players[1].captain, isTrue);
      expect(players[2].keeper, isTrue);
      expect(players[4].viceCaptain, isTrue);
    });

    test('a list without numbers has no headings', () {
      final players = parsePlayerList('Warriors\nAsha\nBilal');
      expect(_names(players), ['Warriors', 'Asha', 'Bilal']);
      expect(players.any((p) => p.likelyHeading), isFalse);
    });

    test('bulleted lists count as numbered', () {
      final players = parsePlayerList('Our team\n• Asha\n• Bilal\n- Chitra');
      expect([for (final p in players) if (!p.likelyHeading) p.name], ['Asha', 'Bilal', 'Chitra']);
      expect(players.first.likelyHeading, isTrue);
    });

    test('a forgotten number is only flagged, never lost', () {
      final players = parsePlayerList('1. Asha\n2. Bilal\nChitra');
      expect(_names(players), ['Asha', 'Bilal', 'Chitra']);
      expect(players.last.likelyHeading, isTrue);
    });

    test('names on one line are split at commas, but not inside brackets', () {
      expect(_names(parsePlayerList('Asha (c, wk), Bilal, Chitra')), ['Asha', 'Bilal', 'Chitra']);
      expect(parsePlayerList('Asha (c, wk), Bilal').first.keeper, isTrue);
    });

    test('Windows line ends work', () {
      expect(_names(parsePlayerList('Asha\r\nBilal\r\n')), ['Asha', 'Bilal']);
    });

    test('an empty paste gives nobody', () {
      expect(parsePlayerList(''), isEmpty);
      expect(parsePlayerList('\n\n  \n'), isEmpty);
    });
  });

  group('CSV rows', () {
    test('quoted fields keep commas, doubled quotes and line breaks', () {
      final rows = parseCsv('Team,Player\n"Kings, Town","Asha ""Ace"""\nKings,"Bil\nal"\n');
      expect(rows, [
        ['Team', 'Player'],
        ['Kings, Town', 'Asha "Ace"'],
        ['Kings', 'Bil\nal'],
      ]);
    });

    test('semicolons, tabs, a byte order mark and blank rows', () {
      expect(parseCsv('﻿Team;Player\r\n\r\nKings;Asha\r\n'), [
        ['Team', 'Player'],
        ['Kings', 'Asha'],
      ]);
      expect(parseCsv('Kings\tQueens\nAsha\tBilal'), [
        ['Kings', 'Queens'],
        ['Asha', 'Bilal'],
      ]);
    });
  });

  group('teams from a CSV file', () {
    test('one column per team, names on top', () {
      final teams = parseTeamsCsv('Kings,Queens\nAsha (c),Bilal\nChitra,Devi (wk)\nEsha,\n');
      expect([for (final t in teams) t.name], ['Kings', 'Queens']);
      expect(_names(teams[0].players), ['Asha', 'Chitra', 'Esha']);
      expect(_names(teams[1].players), ['Bilal', 'Devi']);
      expect(teams[0].players.first.captain, isTrue);
      expect(teams[1].players.last.keeper, isTrue);
    });

    test('a numbering column and empty columns are dropped', () {
      final teams = parseTeamsCsv('No.,Kings,,Queens\n1,Asha,,Bilal\n2,Chitra,,Devi\n');
      expect([for (final t in teams) t.name], ['Kings', 'Queens']);
    });

    test('Team and Player columns, with roles and merged team cells', () {
      final teams = parseTeamsCsv(
        'Team Name,Player Name,Role\n'
        'Kings,Asha,Captain\n'
        ',Bilal,WK\n'
        ',Chitra,Bowler\n'
        'Queens,Devi,\n'
        'queens,Esha,All-rounder\n'
        'Kings,asha,\n',
      );
      expect([for (final t in teams) t.name], ['Kings', 'Queens']);
      final kings = teams[0].players;
      expect(_names(kings), ['Asha', 'Bilal', 'Chitra']);
      expect(kings[0].captain, isTrue);
      expect(kings[1].keeper, isTrue);
      expect(kings[2].role, PlayerRole.bowler);
      expect(_names(teams[1].players), ['Devi', 'Esha']);
      expect(teams[1].players[1].role, PlayerRole.allRounder);
    });

    test('an Excel workbook gets told to save as CSV', () {
      expect(
        () => parseTeamsCsv('PK\u0003\u0004[Content_Types].xml'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('CSV UTF-8'))),
      );
    });

    test('empty files, half headers and teams without players are refused', () {
      expect(() => parseTeamsCsv(''), throwsA(isA<FormatException>().having((e) => e.message, 'm', 'That file is empty.')));
      expect(
        () => parseTeamsCsv('Player\nAsha\nBilal'),
        throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('not both'))),
      );
      expect(
        () => parseTeamsCsv('Kings,Queens\n'),
        throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('No teams with players'))),
      );
    });
  });

  test('the template on the website imports as two full teams', () {
    final teams = parseTeamsCsv(File('../site/teams-template.csv').readAsStringSync());
    expect([for (final t in teams) t.name], ['Kings XI', 'Royal Strikers']);
    expect([for (final t in teams) t.players.length], [6, 6]);
    final kings = teams[0].players;
    expect(kings[0].captain, isTrue);
    expect(kings[1].keeper, isTrue);
    expect([kings[2].role, kings[3].role, kings[4].role], [PlayerRole.bowler, PlayerRole.allRounder, PlayerRole.batter]);
    expect(teams[1].players[2].viceCaptain, isTrue);
    expect(teamsTemplateAddress, endsWith('/teams-template.csv'));
  });

  group('joining a squad', () {
    const asha = Player(id: 'a', name: 'Asha');
    const bilal = Player(id: 'b', name: 'Bilal', role: PlayerRole.batter);

    test('new names join at the end and old ones keep their ids', () {
      final update = addToSquad(
        players: const [asha, bilal],
        captainId: 'a',
        viceCaptainId: null,
        keeperId: null,
        incoming: const [ImportedPlayer('bilal'), ImportedPlayer('Chitra')],
        newId: _ids(),
      );
      expect([for (final p in update.players) '${p.id}:${p.name}'], ['a:Asha', 'b:Bilal', 'id1:Chitra']);
      expect(update.added, 1);
      expect(update.alreadyIn, 1);
      expect(update.captainId, 'a');
    });

    test('marks in the list win, and the first of each counts', () {
      final update = addToSquad(
        players: const [asha, bilal],
        captainId: 'a',
        viceCaptainId: null,
        keeperId: 'a',
        incoming: const [
          ImportedPlayer('Bilal', captain: true, role: PlayerRole.allRounder),
          ImportedPlayer('Chitra', captain: true, keeper: true),
        ],
        newId: _ids(),
      );
      expect(update.captainId, 'b');
      expect(update.keeperId, 'id1');
      expect(update.players[1].role, PlayerRole.allRounder);
      expect(update.players[1].name, 'Bilal', reason: 'the saved spelling stays');
    });

    test('captain and vice-captain stay two people', () {
      final markedVice = addToSquad(
        players: const [asha, bilal],
        captainId: 'a',
        viceCaptainId: null,
        keeperId: null,
        incoming: const [ImportedPlayer('Asha', viceCaptain: true)],
        newId: _ids(),
      );
      expect(markedVice.viceCaptainId, 'a');
      expect(markedVice.captainId, isNull);

      final markedBoth = addToSquad(
        players: const [],
        captainId: null,
        viceCaptainId: null,
        keeperId: null,
        incoming: const [ImportedPlayer('Asha', captain: true, viceCaptain: true)],
        newId: _ids(),
      );
      expect(markedBoth.captainId, 'id1');
      expect(markedBoth.viceCaptainId, isNull);
    });
  });

  group('an import plan', () {
    final saved = Team(
      id: 'k',
      name: 'Kings',
      players: const [Player(id: 'a', name: 'Asha'), Player(id: 'b', name: 'Bilal')],
      captainId: 'a',
    );

    test('a saved name adds to that squad, the rest are new', () {
      final plan = planImport(
        [saved],
        const [
          ImportedTeam('kings', [ImportedPlayer('Asha'), ImportedPlayer('Chitra')]),
          ImportedTeam('Queens', [ImportedPlayer('Devi'), ImportedPlayer('Esha', keeper: true)]),
        ],
        newId: _ids(),
      );
      final kings = plan[0];
      expect(kings.isNew, isFalse);
      expect(kings.team!.id, 'k');
      expect(kings.team!.name, 'Kings', reason: 'the saved spelling stays');
      expect(kings.team!.players.map((p) => p.name), ['Asha', 'Bilal', 'Chitra']);
      expect(kings.team!.captainId, 'a');
      expect(kings.update.added, 1);

      final queens = plan[1];
      expect(queens.isNew, isTrue);
      expect(queens.team!.players.map((p) => p.name), ['Devi', 'Esha']);
      expect(queens.team!.keeperId, queens.team!.players[1].id);
    });

    test('a new team of one player is not saved', () {
      final plan = planImport(const [], const [ImportedTeam('Solo', [ImportedPlayer('Asha')])], newId: _ids());
      expect(plan.single.team, isNull);
      expect(plan.single.update.players, hasLength(1));
    });
  });

  group('reading a picked file', () {
    test('UTF-8 is read as UTF-8', () {
      expect(decodeTextFile(utf8.encode('Kings,Zoë')), 'Kings,Zoë');
    });

    test('a plain Excel CSV on Windows still reads', () {
      expect(decodeTextFile(latin1.encode('Kings,Zoë')), 'Kings,Zoë');
    });

    test('a workbook comes through for the reader to refuse', () {
      final text = decodeTextFile([0x50, 0x4B, 0x03, 0x04, 0xFF, 0x00]);
      expect(() => parseTeamsCsv(text), throwsFormatException);
    });
  });
}

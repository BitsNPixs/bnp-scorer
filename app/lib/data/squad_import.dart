import 'package:cricket_engine/cricket_engine.dart';

/// Reading squads that someone already has written down: a list pasted from
/// WhatsApp, or a sheet saved as CSV from Excel or Google Sheets. Nothing here
/// touches storage; the screens decide what to keep.

/// A player read from a list or a file, before they join a squad.
class ImportedPlayer {
  const ImportedPlayer(
    this.name, {
    this.role,
    this.captain = false,
    this.viceCaptain = false,
    this.keeper = false,
    this.likelyHeading = false,
  });

  final String name;
  final PlayerRole? role;
  final bool captain;
  final bool viceCaptain;
  final bool keeper;

  /// An unnumbered line in a numbered list: probably a heading, not a player.
  final bool likelyHeading;

  ImportedPlayer asHeading() => ImportedPlayer(
        name,
        role: role,
        captain: captain,
        viceCaptain: viceCaptain,
        keeper: keeper,
        likelyHeading: true,
      );

  /// The marks to show next to the name: C, VC, WK and the role.
  List<String> get marks => [
        if (captain) 'C',
        if (viceCaptain) 'VC',
        if (keeper) 'WK',
        ?role?.label,
      ];
}

class ImportedTeam {
  const ImportedTeam(this.name, this.players);

  final String name;
  final List<ImportedPlayer> players;
}

/// A ready CSV to fill in, on the website (`site/teams-template.csv`).
const teamsTemplateAddress = 'bitsnpixs.github.io/bnp-scorer/teams-template.csv';

/// The file name the template is shared under from the app.
const teamsTemplateFileName = 'bnp-teams-template.csv';

/// The same template, shared from the Teams tab. It must stay identical to
/// `site/teams-template.csv`; a test compares them.
const teamsTemplateCsv = 'Team,Player,Role\r\n'
    'Kings XI,Arun Kumar,Captain\r\n'
    'Kings XI,Balu,Wicket-keeper\r\n'
    'Kings XI,Charles,Bowler\r\n'
    'Kings XI,Dinesh,All-rounder\r\n'
    'Kings XI,Ezhil,Batter\r\n'
    'Kings XI,Farook,\r\n'
    'Royal Strikers,Ganesh,Captain\r\n'
    'Royal Strikers,Hameed,WK\r\n'
    'Royal Strikers,Imran,Vice-captain\r\n'
    'Royal Strikers,Jegan,Bowler\r\n'
    'Royal Strikers,Karthik,\r\n'
    'Royal Strikers,Lenin,\r\n';

/// What a CSV import needs to look like, for error messages and the help text.
const csvFormatHelp =
    'Put each team in its own column with the team name on top, or use two columns '
    'headed Team and Player (a Role column is optional).';

const _notCsv = 'That file is not a CSV. In Excel use File > Save As > CSV UTF-8, '
    'in Google Sheets File > Download > CSV, then pick the new file.';

// ---- marks ---------------------------------------------------------------

enum _Mark { captain, viceCaptain, keeper, batter, bowler, allRounder }

const _vocabulary = <String, _Mark>{
  'c': _Mark.captain,
  'cap': _Mark.captain,
  'capt': _Mark.captain,
  'captain': _Mark.captain,
  'vc': _Mark.viceCaptain,
  'v c': _Mark.viceCaptain,
  'vice captain': _Mark.viceCaptain,
  'vicecaptain': _Mark.viceCaptain,
  'vice capt': _Mark.viceCaptain,
  'wk': _Mark.keeper,
  'w k': _Mark.keeper,
  'wkt': _Mark.keeper,
  'keeper': _Mark.keeper,
  'wicketkeeper': _Mark.keeper,
  'wicket keeper': _Mark.keeper,
  'wkt keeper': _Mark.keeper,
  'bat': _Mark.batter,
  'batter': _Mark.batter,
  'batsman': _Mark.batter,
  'batting': _Mark.batter,
  'bowl': _Mark.bowler,
  'bowler': _Mark.bowler,
  'bowling': _Mark.bowler,
  'ar': _Mark.allRounder,
  'all rounder': _Mark.allRounder,
  'allrounder': _Mark.allRounder,
};

/// The marks in [text] ("c & wk", "Vice-captain", "Batter"), or null if any
/// part of it is not a mark, so ordinary words are never swallowed.
Set<_Mark>? _marksIn(String text) {
  final normal = text.toLowerCase().replaceAll('.', '').replaceAll(RegExp(r'[-_]'), ' ').trim();
  if (normal.isEmpty) return null;
  final marks = <_Mark>{};
  for (final raw in normal.split(RegExp(r'[,/&+;|]|\band\b'))) {
    final piece = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (piece.isEmpty) continue;
    final whole = _vocabulary[piece];
    if (whole != null) {
      marks.add(whole);
      continue;
    }
    for (final word in piece.split(' ')) {
      final mark = _vocabulary[word];
      if (mark == null) return null;
      marks.add(mark);
    }
  }
  return marks.isEmpty ? null : marks;
}

PlayerRole? _roleOf(Set<_Mark> marks) => marks.contains(_Mark.allRounder)
    ? PlayerRole.allRounder
    : marks.contains(_Mark.bowler)
        ? PlayerRole.bowler
        : marks.contains(_Mark.batter)
            ? PlayerRole.batter
            : null;

ImportedPlayer _player(String name, Set<_Mark> marks) => ImportedPlayer(
      name,
      role: _roleOf(marks),
      captain: marks.contains(_Mark.captain),
      viceCaptain: marks.contains(_Mark.viceCaptain),
      keeper: marks.contains(_Mark.keeper),
    );

// ---- one line ------------------------------------------------------------

final _bracketed = RegExp(r'\(([^)]*)\)|\[([^\]]*)\]');
final _trailingDash = RegExp(r'\s+[-–—:]\s+([^-–—:]+)$');
final _leadingBullet = RegExp(r'^(?:[\s\-–—•·>#*]+)?(?:\d{1,3}\s*[.):\]\-–]*\s+|\d{1,3}[.):\]\-–]+\s*)?');
final _notNameChars = RegExp(r"[^\p{L}\p{M}\p{N}\s.'()-]", unicode: true);
final _letter = RegExp(r'\p{L}', unicode: true);

/// One player from one line of a list, or null if the line holds no name:
/// "1. Asha (c)", "• Bilal - wk", "*Chitra* 🧤". Numbering, bullets, WhatsApp
/// bold and emoji go, but a number inside a name ("Ravi 2") stays; known marks in brackets or after a dash become captain,
/// vice-captain, keeper or a role; anything else stays part of the name.
ImportedPlayer? parsePlayerLine(String line) {
  var text = line.replaceAll(RegExp(r'[*_~]'), ' ').trim();
  if (text.isEmpty || text.endsWith(':')) return null;
  final marks = <_Mark>{};
  if (text.contains('©')) marks.add(_Mark.captain);
  if (text.contains('🧤')) marks.add(_Mark.keeper);
  text = text.replaceAllMapped(_bracketed, (m) {
    final found = _marksIn(m.group(1) ?? m.group(2) ?? '');
    if (found == null) return m.group(0)!;
    marks.addAll(found);
    return ' ';
  });
  final dash = _trailingDash.firstMatch(text);
  if (dash != null) {
    final found = _marksIn(dash.group(1)!);
    if (found != null) {
      marks.addAll(found);
      text = text.substring(0, dash.start);
    }
  }
  text = text.replaceFirst(_leadingBullet, '');
  // Bare marks at the end ("Bilal wk"), but never a lone letter, which is
  // more likely an initial than "c" for captain.
  while (true) {
    final words = text.trim().split(RegExp(r'\s+'));
    if (words.length < 2) break;
    final last = words.last.toLowerCase().replaceAll('.', '');
    final mark = last.length > 1 ? _vocabulary[last] : null;
    if (mark == null) break;
    marks.add(mark);
    text = words.sublist(0, words.length - 1).join(' ');
  }
  final name = text
      .replaceAll(_notNameChars, ' ')
      .replaceAll(RegExp(r'\(\s*\)|\[\s*\]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r"^[\s.'-]+|[\s.'-]+$"), '');
  if (!_letter.hasMatch(name) || name.length > 40 || name.split(' ').length > 5) return null;
  return _player(name, marks);
}

/// A line that starts with a number ("1.", "2)", "3 ") or a bullet.
final _numbered = RegExp(r'^\s*(?:\d{1,3}\s*[.):\]\-–]|\d{1,3}\s|[-–—•·]\s*\S)');

/// Every player in a pasted list, one per line (or comma separated when it is
/// all on one line), without repeats. The first spelling of a name wins. When
/// most lines are numbered or bulleted, the others are probably headings
/// ("*Warriors*", "Playing XI") and come back with [ImportedPlayer.likelyHeading]
/// set, so the scorer sees them already taken off and can bring one back.
List<ImportedPlayer> parsePlayerList(String text) {
  var lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  if (lines.length == 1) lines = lines.single.split(RegExp(r',(?![^()\[\]]*[)\]])'));
  final numbered = lines.where(_numbered.hasMatch).length;
  final mostlyNumbered = numbered >= 2 && numbered * 2 > lines.length;
  return _unique([
    for (final line in lines)
      if (parsePlayerLine(line) case final p?) mostlyNumbered && !_numbered.hasMatch(line) ? p.asHeading() : p,
  ]);
}

List<ImportedPlayer> _unique(Iterable<ImportedPlayer> players) {
  final seen = <String>{};
  return [for (final p in players) if (seen.add(p.name.toLowerCase())) p];
}

// ---- CSV -----------------------------------------------------------------

/// The rows of a CSV file as Excel and Google Sheets write it: quoted fields,
/// doubled quotes, and a comma, semicolon or tab between fields, whichever the
/// first line uses most. Blank rows are dropped and cells trimmed.
List<List<String>> parseCsv(String text) {
  final body = text.startsWith('﻿') ? text.substring(1) : text;
  final firstLine = body.split('\n').first;
  final delimiter = [',', ';', '\t'].reduce(
    (best, d) => d.allMatches(firstLine).length > best.allMatches(firstLine).length ? d : best,
  );
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  void endCell() {
    row.add(cell.toString().trim());
    cell.clear();
  }

  void endRow() {
    endCell();
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < body.length; i++) {
    final ch = body[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < body.length && body[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"' && cell.toString().trim().isEmpty) {
      cell.clear();
      quoted = true;
    } else if (ch == delimiter) {
      endCell();
    } else if (ch == '\n') {
      endRow();
    } else if (ch != '\r') {
      cell.write(ch);
    }
  }
  endRow();
  return rows;
}

const _teamHeaders = {'team', 'team name', 'teamname', 'side', 'club'};
const _playerHeaders = {'player', 'player name', 'playername', 'players', 'name'};
const _roleHeaders = {'role', 'type', 'position'};

/// The teams in a CSV file, in either of two shapes:
///
/// * one column per team, the team's name on top and its players below;
/// * columns headed Team and Player, one row per player, with an optional
///   Role column ("Captain", "WK", "Bowler"). A blank team cell continues the
///   team above, as merged cells in Excel save.
///
/// Throws a [FormatException] with a message for the scorer when the file is
/// not a CSV, or holds no team with players.
List<ImportedTeam> parseTeamsCsv(String text) {
  if (text.startsWith('PK\u0003\u0004') || text.contains('\u0000')) throw const FormatException(_notCsv);
  final rows = parseCsv(text);
  if (rows.isEmpty) throw const FormatException('That file is empty.');
  final header = [for (final c in rows.first) c.toLowerCase()];
  final teamColumn = header.indexWhere(_teamHeaders.contains);
  final playerColumn = header.indexWhere(_playerHeaders.contains);
  final teams = teamColumn >= 0 && playerColumn >= 0
      ? _byRow(rows.skip(1), teamColumn, playerColumn, header.indexWhere(_roleHeaders.contains))
      : playerColumn >= 0 || teamColumn >= 0
          ? throw const FormatException('Found a Team or Player column but not both. $csvFormatHelp')
          : _byColumn(rows);
  final kept = [for (final t in teams) if (t.players.isNotEmpty) t];
  if (kept.isEmpty) throw const FormatException('No teams with players in that file. $csvFormatHelp');
  return kept;
}

String _cell(List<String> row, int i) => i >= 0 && i < row.length ? row[i] : '';

List<ImportedTeam> _byRow(Iterable<List<String>> rows, int teamColumn, int playerColumn, int roleColumn) {
  final order = <String>[];
  final names = <String, String>{};
  final players = <String, List<ImportedPlayer>>{};
  String? current;
  for (final row in rows) {
    final team = _cell(row, teamColumn);
    if (team.isNotEmpty) current = team;
    if (current == null) continue;
    final key = current.toLowerCase();
    final parsed = parsePlayerLine(_cell(row, playerColumn));
    if (parsed == null) continue;
    final extra = _marksIn(_cell(row, roleColumn)) ?? const <_Mark>{};
    final player = extra.isEmpty
        ? parsed
        : ImportedPlayer(
            parsed.name,
            role: _roleOf(extra) ?? parsed.role,
            captain: parsed.captain || extra.contains(_Mark.captain),
            viceCaptain: parsed.viceCaptain || extra.contains(_Mark.viceCaptain),
            keeper: parsed.keeper || extra.contains(_Mark.keeper),
          );
    if (!names.containsKey(key)) {
      order.add(key);
      names[key] = current;
    }
    (players[key] ??= []).add(player);
  }
  return [for (final key in order) ImportedTeam(names[key]!, _unique(players[key]!))];
}

List<ImportedTeam> _byColumn(List<List<String>> rows) {
  final header = rows.first;
  final byName = <String, ImportedTeam>{};
  for (var col = 0; col < header.length; col++) {
    final name = header[col].trim();
    if (name.isEmpty) continue;
    final players = [for (final row in rows.skip(1)) ?parsePlayerLine(_cell(row, col))];
    final key = name.toLowerCase();
    final earlier = byName[key];
    byName[key] = ImportedTeam(earlier?.name ?? name, _unique([...?earlier?.players, ...players]));
  }
  return byName.values.toList();
}

// ---- joining a squad -----------------------------------------------------

/// A squad after imported players join it.
class SquadUpdate {
  const SquadUpdate({
    required this.players,
    required this.captainId,
    required this.viceCaptainId,
    required this.keeperId,
    required this.added,
    required this.alreadyIn,
  });

  final List<Player> players;
  final String? captainId;
  final String? viceCaptainId;
  final String? keeperId;

  /// New names that joined.
  final int added;

  /// Names that were already in the squad (same spelling, any case).
  final int alreadyIn;
}

/// [incoming] joins a squad of [players]: new names are added at the end,
/// names already there are kept with their ids. Marks in the list win, since
/// someone wrote them on purpose: a role replaces the old one, and the first
/// player marked captain, vice-captain or keeper takes that job. Captain and
/// vice-captain stay two different people.
SquadUpdate addToSquad({
  required List<Player> players,
  required String? captainId,
  required String? viceCaptainId,
  required String? keeperId,
  required List<ImportedPlayer> incoming,
  required String Function() newId,
}) {
  final squad = [...players];
  var captain = captainId, vice = viceCaptainId, keeper = keeperId;
  var added = 0, alreadyIn = 0;
  var markedCaptain = false, markedVice = false, markedKeeper = false;
  for (final p in incoming) {
    final i = squad.indexWhere((s) => s.name.toLowerCase() == p.name.toLowerCase());
    final String id;
    if (i >= 0) {
      alreadyIn++;
      id = squad[i].id;
      if (p.role != null) squad[i] = Player(id: id, name: squad[i].name, role: p.role);
    } else {
      added++;
      id = newId();
      squad.add(Player(id: id, name: p.name, role: p.role));
    }
    if (p.captain && !markedCaptain) {
      captain = id;
      markedCaptain = true;
    }
    if (p.viceCaptain && !markedVice) {
      vice = id;
      markedVice = true;
    }
    if (p.keeper && !markedKeeper) {
      keeper = id;
      markedKeeper = true;
    }
  }
  if (captain != null && captain == vice) {
    // Whichever the list set wins; otherwise the captain keeps the job.
    if (markedVice && !markedCaptain) {
      captain = null;
    } else {
      vice = null;
    }
  }
  return SquadUpdate(
    players: squad,
    captainId: captain,
    viceCaptainId: vice,
    keeperId: keeper,
    added: added,
    alreadyIn: alreadyIn,
  );
}

/// One team of an import: what would be saved, or why it cannot be.
class PlannedTeam {
  const PlannedTeam({required this.source, required this.team, required this.isNew, required this.update});

  final ImportedTeam source;

  /// Null when the team would have fewer than two players.
  final Team? team;

  /// False when the file adds to a saved team of the same name.
  final bool isNew;
  final SquadUpdate update;
}

/// How [teams] from a file would land among the [saved] squads. A team whose
/// name matches a saved one (any case) adds to it; the rest are new.
List<PlannedTeam> planImport(List<Team> saved, List<ImportedTeam> teams, {required String Function() newId}) => [
      for (final source in teams)
        () {
          final existing = saved.where((t) => t.name.toLowerCase() == source.name.toLowerCase()).firstOrNull;
          final update = addToSquad(
            players: existing?.players ?? const [],
            captainId: existing?.captainId,
            viceCaptainId: existing?.viceCaptainId,
            keeperId: existing?.keeperId,
            incoming: source.players,
            newId: newId,
          );
          return PlannedTeam(
            source: source,
            isNew: existing == null,
            update: update,
            team: update.players.length < 2
                ? null
                : Team(
                    id: existing?.id ?? newId(),
                    name: existing?.name ?? source.name,
                    players: update.players,
                    captainId: update.captainId,
                    viceCaptainId: update.viceCaptainId,
                    keeperId: update.keeperId,
                  ),
          );
        }(),
    ];

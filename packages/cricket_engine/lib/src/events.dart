/// Scoring events. The ordered event log is the single source of truth for a
/// match; every scorecard and statistic is derived from it.
library;

import 'models.dart';

sealed class MatchEvent {
  const MatchEvent({required this.id, required this.at});

  /// Globally unique id, used for de-duplication when syncing.
  final String id;
  final DateTime at;

  String get type;

  Json payloadToJson();

  Json toJson() => {
        'type': type,
        'id': id,
        'at': at.toUtc().toIso8601String(),
        ...payloadToJson(),
      };

  static MatchEvent fromJson(Json json) {
    final id = json['id']! as String;
    final at = DateTime.parse(json['at']! as String);
    return switch (json['type']) {
      OpenersSelected.typeName => OpenersSelected(
          id: id,
          at: at,
          strikerId: json['strikerId']! as String,
          nonStrikerId: json['nonStrikerId']! as String,
        ),
      BowlerChanged.typeName =>
        BowlerChanged(id: id, at: at, bowlerId: json['bowlerId']! as String),
      BallBowled.typeName => BallBowled(
          id: id,
          at: at,
          runsOffBat: json['runsOffBat']! as int,
          extra: ExtraType.values.byName(json['extra']! as String),
          extraRuns: json['extraRuns']! as int,
          boundary: json['boundary']! as bool,
          wicket: json['wicket'] == null
              ? null
              : Wicket.fromJson(json['wicket']! as Json),
        ),
      NewBatter.typeName =>
        NewBatter(id: id, at: at, batterId: json['batterId']! as String),
      BatterRetired.typeName => BatterRetired(
          id: id,
          at: at,
          batterId: json['batterId']! as String,
          hurt: json['hurt']! as bool,
        ),
      StrikeSwapped.typeName => StrikeSwapped(id: id, at: at),
      InningsClosed.typeName =>
        InningsClosed(id: id, at: at, reason: json['reason']! as String),
      MatchAbandoned.typeName =>
        MatchAbandoned(id: id, at: at, reason: json['reason']! as String),
      final other => throw FormatException('Unknown event type: $other'),
    };
  }
}

/// Starts an innings with two batters. Starts the second innings too.
final class OpenersSelected extends MatchEvent {
  const OpenersSelected({
    required super.id,
    required super.at,
    required this.strikerId,
    required this.nonStrikerId,
  });

  static const typeName = 'openersSelected';
  final String strikerId;
  final String nonStrikerId;

  @override
  String get type => typeName;

  @override
  Json payloadToJson() => {'strikerId': strikerId, 'nonStrikerId': nonStrikerId};
}

/// Sets the bowler for a new over, or replaces the bowler mid-over.
final class BowlerChanged extends MatchEvent {
  const BowlerChanged({
    required super.id,
    required super.at,
    required this.bowlerId,
  });

  static const typeName = 'bowlerChanged';
  final String bowlerId;

  @override
  String get type => typeName;

  @override
  Json payloadToJson() => {'bowlerId': bowlerId};
}

class Wicket {
  const Wicket({required this.type, required this.batterOutId, this.fielderId});

  final DismissalType type;
  final String batterOutId;

  /// Catcher, run-out fielder or wicket-keeper, when known.
  final String? fielderId;

  Json toJson() =>
      {'type': type.name, 'batterOutId': batterOutId, 'fielderId': fielderId};

  factory Wicket.fromJson(Json json) => Wicket(
        type: DismissalType.values.byName(json['type']! as String),
        batterOutId: json['batterOutId']! as String,
        fielderId: json['fielderId'] as String?,
      );
}

/// One delivery.
///
/// * [runsOffBat]: runs credited to the striker (also on a no-ball).
/// * [extra]: the kind of extra, if any.
/// * [extraRuns]: runs that are extras on top of any wide/no-ball penalty:
///   runs run (or a boundary) off a wide, byes off a no-ball, or the byes /
///   leg byes themselves.
/// * [boundary]: [runsOffBat] was a 4 or 6 that reached the rope.
final class BallBowled extends MatchEvent {
  const BallBowled({
    required super.id,
    required super.at,
    this.runsOffBat = 0,
    this.extra = ExtraType.none,
    this.extraRuns = 0,
    this.boundary = false,
    this.wicket,
  });

  static const typeName = 'ballBowled';
  final int runsOffBat;
  final ExtraType extra;
  final int extraRuns;
  final bool boundary;
  final Wicket? wicket;

  @override
  String get type => typeName;

  @override
  Json payloadToJson() => {
        'runsOffBat': runsOffBat,
        'extra': extra.name,
        'extraRuns': extraRuns,
        'boundary': boundary,
        'wicket': wicket?.toJson(),
      };
}

/// Fills an empty crease slot after a wicket or retirement. A batter who
/// retired hurt may return this way.
final class NewBatter extends MatchEvent {
  const NewBatter({required super.id, required super.at, required this.batterId});

  static const typeName = 'newBatter';
  final String batterId;

  @override
  String get type => typeName;

  @override
  Json payloadToJson() => {'batterId': batterId};
}

/// A batter leaves between deliveries. [hurt] means retired hurt (not out,
/// may return); otherwise retired out (counts as a wicket).
final class BatterRetired extends MatchEvent {
  const BatterRetired({
    required super.id,
    required super.at,
    required this.batterId,
    required this.hurt,
  });

  static const typeName = 'batterRetired';
  final String batterId;
  final bool hurt;

  @override
  String get type => typeName;

  @override
  Json payloadToJson() => {'batterId': batterId, 'hurt': hurt};
}

/// Manual correction of who is on strike.
final class StrikeSwapped extends MatchEvent {
  const StrikeSwapped({required super.id, required super.at});

  static const typeName = 'strikeSwapped';

  @override
  String get type => typeName;

  @override
  Json payloadToJson() => const {};
}

/// Ends the current innings early (declaration, rain, bad light...).
final class InningsClosed extends MatchEvent {
  const InningsClosed({required super.id, required super.at, required this.reason});

  static const typeName = 'inningsClosed';
  final String reason;

  @override
  String get type => typeName;

  @override
  Json payloadToJson() => {'reason': reason};
}

/// Ends the match with no result (rain, bad light, no ground), at any point.
final class MatchAbandoned extends MatchEvent {
  const MatchAbandoned({required super.id, required super.at, required this.reason});

  static const typeName = 'matchAbandoned';
  final String reason;

  @override
  String get type => typeName;

  @override
  Json payloadToJson() => {'reason': reason};
}

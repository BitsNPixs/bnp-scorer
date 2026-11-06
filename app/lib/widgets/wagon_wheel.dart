import 'dart:math';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/format.dart';
import 'surface_panel.dart';

const _fieldSize = 260.0;
const _strokeWidth = 2.0;

/// How far a shot's line reaches, as a share of the boundary.
const _reachBySingles = 0.42;
const _reachPerRun = 0.14;

/// Spread within a zone, so several shots to one zone stay separate lines.
const _spreadDegrees = 34.0;

/// Where the scoring shots went, one line per shot, off side to the right. The
/// table of runs per zone beside it gives the same numbers without colour.
class WagonWheel extends StatefulWidget {
  const WagonWheel({super.key, required this.state});

  final MatchState state;

  @override
  State<WagonWheel> createState() => _WagonWheelState();
}

class _WagonWheelState extends State<WagonWheel> {
  int _inningsIndex = 0;
  String? _batterId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final setup = widget.state.setup;
    final innings = widget.state.innings;
    final current = innings[min(_inningsIndex, innings.length - 1)];
    final batterIds = {for (final s in current.shots) s.batterId};
    final batterId = batterIds.contains(_batterId) ? _batterId : null;
    final shots = [
      for (final s in current.shots)
        if (batterId == null || s.batterId == batterId) s,
    ];
    final others = scheme.onSurfaceVariant;

    Widget chip(String label, {required bool selected, required VoidCallback onTap}) => ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        );
    int count(bool Function(BallSummary) test) => shots.where(test).length;
    bool isFour(BallSummary s) => s.runsOffBat == 4;
    bool isSix(BallSummary s) => s.runsOffBat >= 6;

    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Wagon wheel'),
          const SizedBox(height: 8),
          if (innings.length > 1) ...[
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < innings.length; i++)
                  chip(
                    setup.teamById(innings[i].battingTeamId).name,
                    selected: i == _inningsIndex,
                    onTap: () => setState(() {
                      _inningsIndex = i;
                      _batterId = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              chip('All batters', selected: batterId == null, onTap: () => setState(() => _batterId = null)),
              for (final id in batterIds)
                chip(
                  playerName(setup, id),
                  selected: id == batterId,
                  onTap: () => setState(() => _batterId = id),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Semantics(
              label: 'Wagon wheel of ${plural(shots.length, 'scoring shot')}.',
              child: SizedBox.square(
                dimension: _fieldSize,
                child: CustomPaint(
                  painter: _WagonPainter(
                    shots: shots,
                    field: scheme.surfaceContainer,
                    line: scheme.outlineVariant,
                    runColor: others,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _Key(color: others, label: '1 to 3: ${count((s) => !isFour(s) && !isSix(s))}'),
              _Key(color: AppColors.four, label: '4s: ${count(isFour)}'),
              _Key(color: AppColors.six, label: '6s: ${count(isSix)}'),
            ],
          ),
          const SizedBox(height: 12),
          const SectionLabel('Runs by zone'),
          const SizedBox(height: 6),
          for (final zone in ShotZone.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text(zone.label, style: theme.textTheme.bodySmall)),
                  Text(
                    '${shots.where((s) => s.shotZone == zone).fold<int>(0, (t, s) => t + s.runsOffBat)}',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      );
}

class _WagonPainter extends CustomPainter {
  _WagonPainter({
    required this.shots,
    required this.field,
    required this.line,
    required this.runColor,
  });

  final List<BallSummary> shots;
  final Color field;
  final Color line;
  final Color runColor;

  /// Up is towards the bowler, and the angle runs clockwise.
  Offset _pointAt(Offset center, double radius, double degrees) {
    final radians = (degrees - 90) * pi / 180;
    return center + Offset(cos(radians), sin(radians)) * radius;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;
    final grid = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas
      ..drawCircle(center, radius, Paint()..color = field)
      ..drawCircle(center, radius, grid)
      ..drawCircle(center, radius * 0.5, grid);
    for (var i = 0; i < ShotZone.values.length; i++) {
      canvas.drawLine(center, _pointAt(center, radius, i * 45.0), grid);
    }
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 8, height: 30),
      Paint()..color = line,
    );

    // Boundaries last, so they stay readable on top of the singles.
    final ordered = [...shots]..sort((a, b) => a.runsOffBat.compareTo(b.runsOffBat));
    for (var i = 0; i < ordered.length; i++) {
      final shot = ordered[i];
      final boundary = shot.runsOffBat >= 4;
      // A fixed pattern, not a random one, so the picture never changes.
      final spread = ((i * 7) % 11 / 10 - 0.5) * _spreadDegrees;
      final reach = boundary ? 1.0 : _reachBySingles + _reachPerRun * shot.runsOffBat;
      final color = switch (shot.runsOffBat) {
        4 || 5 => AppColors.four,
        >= 6 => AppColors.six,
        _ => runColor,
      };
      canvas.drawLine(
        center,
        _pointAt(center, radius * reach, shot.shotZone!.angleDegrees + spread),
        Paint()
          ..color = color
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WagonPainter old) =>
      old.shots != shots || old.field != field;
}

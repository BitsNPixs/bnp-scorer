import 'dart:math';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/format.dart';
import 'surface_panel.dart';

const _chartHeight = 180.0;
const _axisLeft = 26.0;
const _axisBottom = 20.0;
const _axisTop = 12.0;
const _barGap = 2.0;
const _barRadius = 4.0;
const _lineWidth = 2.0;
const _markerRadius = 4.0;
const _ticks = 4;

/// Runs per over and the race between the innings. Tap or drag a chart to read
/// one over. The scorecard tabs are the table view of the same numbers.
class MatchCharts extends StatefulWidget {
  const MatchCharts({super.key, required this.state});

  final MatchState state;

  @override
  State<MatchCharts> createState() => _MatchChartsState();
}

class _MatchChartsState extends State<MatchCharts> {
  int? _selectedOver;

  List<InningsState> get _innings => widget.state.innings;

  int get _overCount => _innings.map((i) => i.overs.length).fold(0, max);

  String _teamName(InningsState innings) =>
      widget.state.setup.teamById(innings.battingTeamId).name;

  void _selectAt(double x, double width) {
    final count = _overCount;
    if (count == 0) return;
    final plot = width - _axisLeft;
    final over = ((x - _axisLeft) / plot * count).floor().clamp(0, count - 1);
    if (over != _selectedOver) setState(() => _selectedOver = over);
  }

  /// "Over 7: Team A 12, Team B 8 (1 wkt)".
  String get _readout {
    final over = _selectedOver;
    if (over == null) return 'Tap a chart to read an over';
    final parts = [
      for (final innings in _innings)
        if (over < innings.overs.length)
          () {
            final o = innings.overs[over];
            final wickets = o.wickets == 0 ? '' : ' (${plural(o.wickets, 'wkt')})';
            return '${_teamName(innings)} ${o.runs}$wickets';
          }(),
    ];
    return 'Over ${over + 1}: ${parts.join(', ')}';
  }

  Widget _chart(CustomPainter painter, String description) => LayoutBuilder(
        builder: (context, constraints) => Semantics(
          label: description,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _selectAt(d.localPosition.dx, constraints.maxWidth),
            onHorizontalDragUpdate: (d) => _selectAt(d.localPosition.dx, constraints.maxWidth),
            child: SizedBox(
              height: _chartHeight,
              width: double.infinity,
              child: CustomPaint(painter: painter),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.chartSeries(theme.brightness);
    final style = _ChartStyle(
      colors: colors,
      grid: scheme.outlineVariant,
      label: theme.textTheme.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
      value: theme.textTheme.labelSmall!.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
      surface: scheme.surfaceContainerLowest,
      highlight: scheme.surfaceContainer,
    );
    final legend = _Legend(
      entries: [
        for (var i = 0; i < _innings.length; i++) (colors[i], _teamName(_innings[i])),
      ],
    );
    final readout = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        _readout,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
    final series = [for (final i in _innings) i.overs];
    final totals = _innings.map((i) => '${_teamName(i)} ${scoreLine(i)}').join(', ');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SurfacePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Runs per over'),
              const SizedBox(height: 8),
              legend,
              const SizedBox(height: 12),
              _chart(
                _ManhattanPainter(series: series, style: style, selected: _selectedOver),
                'Runs per over. $totals.',
              ),
              readout,
            ],
          ),
        ),
        const SizedBox(height: 12),
        SurfacePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Run race'),
              const SizedBox(height: 8),
              legend,
              const SizedBox(height: 12),
              _chart(
                _WormPainter(series: series, style: style, selected: _selectedOver),
                'Total runs over by over. $totals.',
              ),
              readout,
            ],
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.entries});

  final List<(Color, String)> entries;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final (color, name) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 6),
              Text(name, style: style),
            ],
          ),
      ],
    );
  }
}

class _ChartStyle {
  const _ChartStyle({
    required this.colors,
    required this.grid,
    required this.label,
    required this.value,
    required this.surface,
    required this.highlight,
  });

  final List<Color> colors;
  final Color grid;
  final TextStyle label;
  final TextStyle value;
  final Color surface;
  final Color highlight;
}

/// The next round number at or above [value], so ticks read 0, 5, 10, 15, 20.
int _niceMax(int value) {
  for (final step in const [1, 2, 5, 10, 20, 50, 100]) {
    if (value <= step * _ticks) return max(step * _ticks, 1);
  }
  return (value / 100).ceil() * 100;
}

/// Shared axes: horizontal gridlines, y labels and over numbers.
abstract class _OverChartPainter extends CustomPainter {
  _OverChartPainter({required this.series, required this.style, required this.selected});

  final List<List<OverSummary>> series;
  final _ChartStyle style;
  final int? selected;

  int get overCount => series.map((s) => s.length).fold(0, max);

  int get highestValue;

  late final int yMax = _niceMax(highestValue);

  Rect plotOf(Size size) =>
      Rect.fromLTRB(_axisLeft, _axisTop, size.width, size.height - _axisBottom);

  double yFor(Rect plot, num value) => plot.bottom - plot.height * value / yMax;

  void text(Canvas canvas, String value, Offset at, TextStyle textStyle, {TextAlign align = TextAlign.left}) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - painter.width,
      TextAlign.center => at.dx - painter.width / 2,
      _ => at.dx,
    };
    painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
  }

  void paintAxes(Canvas canvas, Rect plot) {
    final line = Paint()
      ..color = style.grid
      ..strokeWidth = 1;
    for (var i = 0; i <= _ticks; i++) {
      final value = yMax * i ~/ _ticks;
      final y = yFor(plot, value);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), line);
      text(canvas, '$value', Offset(plot.left - 6, y), style.label, align: TextAlign.right);
    }
    final count = overCount;
    if (count == 0) return;
    final slot = plot.width / count;
    final every = count <= 10 ? 1 : (count <= 20 ? 2 : 5);
    for (var i = 0; i < count; i++) {
      final number = i + 1;
      if (number % every != 0 && i != 0) continue;
      text(
        canvas,
        '$number',
        Offset(plot.left + slot * (i + 0.5), plot.bottom + _axisBottom / 2 + 2),
        style.label,
        align: TextAlign.center,
      );
    }
  }

  void paintSelection(Canvas canvas, Rect plot) {
    final over = selected;
    final count = overCount;
    if (over == null || count == 0 || over >= count) return;
    final slot = plot.width / count;
    canvas.drawRect(
      Rect.fromLTWH(plot.left + slot * over, plot.top, slot, plot.height),
      Paint()..color = style.highlight,
    );
  }

  /// A wicket marker, with a surface ring so it reads against any mark.
  void paintWicket(Canvas canvas, Offset at, Color color) {
    canvas
      ..drawCircle(at, _markerRadius + 2, Paint()..color = style.surface)
      ..drawCircle(at, _markerRadius, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _OverChartPainter old) =>
      old.selected != selected || old.series != series || old.style.surface != style.surface;
}

class _ManhattanPainter extends _OverChartPainter {
  _ManhattanPainter({required super.series, required super.style, required super.selected});

  @override
  int get highestValue => series.expand((s) => s).map((o) => o.runs).fold(0, max);

  @override
  void paint(Canvas canvas, Size size) {
    final plot = plotOf(size);
    paintSelection(canvas, plot);
    paintAxes(canvas, plot);
    final count = overCount;
    if (count == 0) return;
    final slot = plot.width / count;
    final bars = series.length;
    final barWidth = max((slot - _barGap * (bars + 1)) / bars, 2.0);

    for (var s = 0; s < bars; s++) {
      final paint = Paint()..color = style.colors[s];
      for (var i = 0; i < series[s].length; i++) {
        final over = series[s][i];
        final left = plot.left + slot * i + _barGap + (barWidth + _barGap) * s;
        final top = yFor(plot, over.runs);
        canvas.drawRRect(
          RRect.fromLTRBAndCorners(
            left,
            top,
            left + barWidth,
            plot.bottom,
            topLeft: const Radius.circular(_barRadius),
            topRight: const Radius.circular(_barRadius),
          ),
          paint,
        );
        for (var w = 0; w < over.wickets; w++) {
          final center = Offset(left + barWidth / 2, top - _markerRadius - 2 - w * (_markerRadius * 2 + 1));
          paintWicket(canvas, center, style.colors[s]);
        }
      }
    }
  }
}

class _WormPainter extends _OverChartPainter {
  _WormPainter({required super.series, required super.style, required super.selected});

  @override
  int get highestValue =>
      series.map((s) => s.fold<int>(0, (total, o) => total + o.runs)).fold(0, max);

  @override
  void paint(Canvas canvas, Size size) {
    final plot = plotOf(size);
    paintSelection(canvas, plot);
    paintAxes(canvas, plot);
    final count = overCount;
    if (count == 0) return;
    final slot = plot.width / count;

    for (var s = 0; s < series.length; s++) {
      final overs = series[s];
      if (overs.isEmpty) continue;
      final color = style.colors[s];
      final path = Path()..moveTo(plot.left, plot.bottom);
      final wickets = <Offset>[];
      var total = 0;
      Offset last = Offset(plot.left, plot.bottom);
      for (var i = 0; i < overs.length; i++) {
        total += overs[i].runs;
        last = Offset(plot.left + slot * (i + 1), yFor(plot, total));
        path.lineTo(last.dx, last.dy);
        if (overs[i].wickets > 0) wickets.add(last);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = _lineWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      for (final at in wickets) {
        paintWicket(canvas, at, color);
      }
      text(
        canvas,
        '$total',
        Offset(last.dx - 4, last.dy + (s == 0 ? 12 : -12)),
        style.value,
        align: TextAlign.right,
      );
    }
  }
}

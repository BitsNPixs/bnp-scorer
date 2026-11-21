import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'surface_panel.dart';

/// One ranked line in a stats list. The leader is drawn in the hero style.
class LeaderRow extends StatelessWidget {
  const LeaderRow({
    super.key,
    required this.rank,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.valueLabel,
    this.onTap,
  });

  final int rank;
  final Widget leading;
  final String title;
  final String subtitle;
  final String value;
  final String valueLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final leader = rank == 1;
    final strong = leader ? Colors.white : scheme.onSurface;
    final muted = leader ? Colors.white70 : scheme.onSurfaceVariant;
    final radius = BorderRadius.circular(20);

    return Ink(
      decoration: BoxDecoration(
        gradient: leader ? AppColors.heroGradient : null,
        color: leader ? null : scheme.surfaceContainerLowest,
        borderRadius: radius,
        border: Border.all(color: leader ? AppColors.neon.withValues(alpha: 0.35) : scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: scoreStyle(16, color: leader ? AppColors.neon : muted),
                ),
              ),
              const SizedBox(width: 6),
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(color: strong, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value, style: scoreStyle(24, color: leader ? AppColors.neon : strong)),
                  Text(valueLabel, style: text.labelSmall?.copyWith(color: muted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled panel of numbers, three to a row.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.title, required this.stats});

  final String title;
  final List<(String label, String value)> stats;

  static const _perRow = 3;

  @override
  Widget build(BuildContext context) => SurfacePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(title),
            for (var i = 0; i < stats.length; i += _perRow)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  children: [
                    for (var j = i; j < i + _perRow; j++)
                      Expanded(child: j < stats.length ? _StatCell(stats[j]) : const SizedBox()),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _StatCell extends StatelessWidget {
  const _StatCell(this.stat);

  final (String label, String value) stat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, value) = stat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: scoreStyle(22, color: scheme.onSurface),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// A titled panel of labels and values, one pair to a line.
class KeyValueTable extends StatelessWidget {
  const KeyValueTable({super.key, required this.title, required this.rows});

  final String title;
  final List<(String label, String value)> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(title),
          for (final (i, (label, value)) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Numbers by row and column, such as a career split by format. Columns
/// share the width; when they do not fit, the table scrolls sideways. Each
/// value has the key `stat:<row>:<column>` for tests.
class StatsTable extends StatelessWidget {
  const StatsTable({super.key, required this.columns, required this.rows});

  final List<String> columns;
  final List<(String label, List<String> values)> rows;

  static const _labelWidth = 104.0;
  static const _minValueWidth = 76.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SurfacePanel(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final room = (constraints.maxWidth - 32 - _labelWidth) / columns.length;
          final valueWidth = room < _minValueWidth ? _minValueWidth : room;
          Widget cell(String value, TextStyle? style, {Key? key, TextAlign align = TextAlign.end}) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(value, key: key, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: align, style: style),
              );
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Table(
              defaultColumnWidth: FixedColumnWidth(valueWidth),
              columnWidths: const {0: FixedColumnWidth(_labelWidth)},
              border: TableBorder(horizontalInside: BorderSide(color: scheme.outlineVariant)),
              children: [
                TableRow(
                  children: [
                    cell('', null),
                    for (final column in columns)
                      cell(
                        column,
                        text.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
                for (final (label, values) in rows)
                  TableRow(
                    children: [
                      cell(label, TextStyle(color: scheme.onSurfaceVariant), align: TextAlign.start),
                      for (final (i, value) in values.indexed)
                        cell(
                          value,
                          scoreStyle(17, color: scheme.onSurface),
                          key: ValueKey('stat:$label:${columns[i]}'),
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Shown when there is nothing to list yet.
class StatsEmpty extends StatelessWidget {
  const StatsEmpty({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.leaderboard_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

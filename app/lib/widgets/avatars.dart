import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/format.dart';

const _avatarPalette = [
  Color(0xFF3446FF),
  Color(0xFF00A3A3),
  Color(0xFFE85D04),
  Color(0xFF8E44AD),
  Color(0xFF2E9E44),
  Color(0xFFD63384),
  Color(0xFF1D7FD6),
  Color(0xFFB7791F),
];

/// Stable colour per name, so a player looks the same everywhere.
Color colorForName(String name) {
  var hash = 0;
  for (final unit in name.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _avatarPalette[hash % _avatarPalette.length];
}

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({super.key, required this.name, this.radius = 18});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: colorForName(name),
        child: Text(
          initials(name),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: radius * 0.75,
          ),
        ),
      );
}

/// Lime badge with team initials, used on dark (ink) backgrounds.
class TeamBadge extends StatelessWidget {
  const TeamBadge({super.key, required this.name, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.lime,
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Text(
          initials(name),
          style: scoreStyle(size * 0.38, color: AppColors.ink),
        ),
      );
}

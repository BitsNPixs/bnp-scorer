import 'package:flutter/material.dart';

import '../data/photo_store.dart';
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
  const PlayerAvatar({super.key, required this.name, this.radius = 18, this.photoUrl});

  final String name;
  final double radius;

  /// The player's photo; the initials show until it loads, and if it cannot.
  final String? photoUrl;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundColor: colorForName(name),
        foregroundImage: trustedPhoto(photoUrl) == null ? null : NetworkImage(photoUrl!),
        onForegroundImageError: trustedPhoto(photoUrl) == null ? null : (_, _) {},
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

/// Neon badge with team initials, used on the dark hero cards.
class TeamBadge extends StatelessWidget {
  const TeamBadge({super.key, required this.name, this.size = 40, this.logoUrl});

  final String name;
  final double size;

  /// The team's logo; the initials show until it loads, and if it cannot.
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.32);
    final letters = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: AppColors.neonGradient, borderRadius: radius),
      child: Text(
        initials(name),
        style: scoreStyle(size * 0.42, color: AppColors.night, weight: FontWeight.w800),
      ),
    );
    final logo = trustedPhoto(logoUrl);
    if (logo == null) return letters;
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        logo,
        width: size,
        height: size,
        fit: BoxFit.cover,
        frameBuilder: (_, child, frame, _) => frame == null ? letters : child,
        errorBuilder: (_, _, _) => letters,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../state/reminders.dart';
import '../state/upcoming.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import 'scoring_sheets.dart';
import 'surface_panel.dart';

/// Shows [result] when it carries a message; otherwise [done], if given.
void _report(BuildContext context, String? result, {String? done}) {
  if (result != null) {
    reportResult(context, result);
  } else if (done != null) {
    showMessage(context, done);
  }
}

/// Offered once above the Upcoming strip, the first time this phone has a
/// match coming up: the moment a reminder makes sense, so the permission
/// question that follows is no surprise.
class ReminderOffer extends ConsumerWidget {
  const ReminderOffer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(reminderSettingsProvider);
    if (settings.ownOn != null || !ref.watch(deviceNotificationsProvider).available) {
      return const SizedBox.shrink();
    }
    final text = Theme.of(context).textTheme;
    final notifier = ref.read(reminderSettingsProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SurfacePanel(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_rounded, color: AppColors.neon),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Get a reminder before each match',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${settings.lead.label} before. Change it in Settings.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: () => notifier.setOwn(false),
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: () async {
                      final result = await notifier.setOwn(true);
                      if (context.mounted) _report(context, result, done: 'Reminders on');
                    },
                    icon: const Icon(Icons.notifications_active_rounded, size: 18),
                    label: const Text('Turn on'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// True when [match] will be reminded of: one of this phone's own while
/// reminders are on, or someone else's this phone follows.
bool isReminded(ReminderSettings settings, UpcomingMatch match, {required bool watching}) =>
    watching ? settings.watched.any((w) => w.id == match.id) : settings.ownOn ?? false;

/// The "Remind me" switch on an upcoming match's sheet. For this phone's own
/// matches it is the one switch for all of them; for someone else's it
/// follows just that match.
class ReminderSwitch extends ConsumerWidget {
  const ReminderSwitch({super.key, required this.match, required this.watching});

  final UpcomingMatch match;
  final bool watching;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(deviceNotificationsProvider).available || match.startsAt == null) {
      return const SizedBox.shrink();
    }
    final settings = ref.watch(reminderSettingsProvider);
    final notifier = ref.read(reminderSettingsProvider.notifier);
    final on = isReminded(settings, match, watching: watching);
    return SwitchListTile(
      secondary: Icon(on ? Icons.notifications_active_rounded : Icons.notifications_none_rounded),
      title: const Text('Remind me'),
      subtitle: Text(watching
          ? '${settings.lead.label} before it starts'
          : '${settings.lead.label} before each of your matches'),
      value: on,
      onChanged: (value) async {
        final result = watching ? await notifier.toggleWatched(match) : await notifier.setOwn(value);
        if (context.mounted) _report(context, result);
      },
    );
  }
}

/// Settings: reminders on or off, and how long before.
class ReminderSettingsPanel extends ConsumerStatefulWidget {
  const ReminderSettingsPanel({super.key});

  @override
  ConsumerState<ReminderSettingsPanel> createState() => _ReminderSettingsPanelState();
}

class _ReminderSettingsPanelState extends ConsumerState<ReminderSettingsPanel> {
  /// Whether the phone still lets the app notify; read when the panel opens,
  /// since it can be turned off in the phone's settings at any time.
  late final Future<bool> _allowed = ref.read(deviceNotificationsProvider).allowed();

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(reminderSettingsProvider);
    final notifier = ref.read(reminderSettingsProvider.notifier);
    final on = settings.ownOn ?? false;
    final scheme = Theme.of(context).colorScheme;
    final followed = settings.watched.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfacePanel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_rounded),
                title: const Text('Match reminders'),
                subtitle: Text(followed == 0
                    ? 'Before your fixtures and friendlies'
                    : 'Before your fixtures and friendlies, and $followed '
                        '${followed == 1 ? 'match' : 'matches'} you follow'),
                value: on,
                onChanged: (value) async {
                  final result = await notifier.setOwn(value);
                  if (context.mounted) _report(context, result);
                },
              ),
              if (on || followed > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('How long before', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      OptionChips<ReminderLead>(
                        options: ReminderLead.values,
                        labelOf: (l) => l.label,
                        selected: settings.lead,
                        color: AppColors.neon,
                        onSelected: notifier.setLead,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        FutureBuilder<bool>(
          future: _allowed,
          builder: (context, snapshot) {
            if (!(on || followed > 0) || snapshot.data != false) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: NoticeBanner(
                icon: Icons.notifications_off_rounded,
                text: notificationsOffMessage,
                background: scheme.errorContainer,
                foreground: scheme.onErrorContainer,
              ),
            );
          },
        ),
      ],
    );
  }
}

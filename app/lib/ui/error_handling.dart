import 'dart:ui';

import 'package:flutter/material.dart';

import '../data/error_log.dart';
import '../theme/app_theme.dart';

/// Records every uncaught error in [log] and swaps Flutter's red or grey
/// error box for a calm message. Errors still print to the console.
void installErrorHandlers(ErrorLog log) {
  final present = FlutterError.onError;
  FlutterError.onError = (details) {
    present?.call(details);
    log.record(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    log.record(error, stack);
    return true;
  };
  ErrorWidget.builder = (_) => const FriendlyErrorPanel();
}

/// Shown in place of a widget that failed to build. It may appear anywhere,
/// even outside the app's theme, so it sets its own direction and colours,
/// and scales down to fit a small slot.
class FriendlyErrorPanel extends StatelessWidget {
  const FriendlyErrorPanel({super.key});

  static const message = 'Something went wrong here';
  static const hint = 'Go back and try again. Settings › Report a problem tells us what happened.';

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: AppColors.night,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 280,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.wicket, size: 36),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: AppFonts.display(
                          const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hint,
                        textAlign: TextAlign.center,
                        style: AppFonts.body(const TextStyle(color: Colors.white70, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

class BnpScorerApp extends StatelessWidget {
  const BnpScorerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BNP Scorer',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const HomeScreen(),
      );
}

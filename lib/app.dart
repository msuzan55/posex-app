import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'screens/splash_screen.dart';
import 'theme/posex_theme.dart';

class PosexApp extends StatelessWidget {
  const PosexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        title: 'PosEx',
        debugShowCheckedModeBanner: false,
        theme: PosexTheme.light(),
        home: const SplashScreen(),
      ),
    );
  }
}

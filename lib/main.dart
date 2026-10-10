import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'screens/language_selection_screen.dart';
import 'services/settings_service.dart';

import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock to portrait: detection coordinates and guidance assume an upright image.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SettingsService.instance.initialize();
  runApp(const FindItApp());
}

class FindItApp extends StatelessWidget {
  const FindItApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isFirstLaunch = SettingsService.instance.isFirstLaunch;

    return MaterialApp(
      title: 'FindIt',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: isFirstLaunch
          ? const LanguageSelectionScreen(isFirstLaunch: true)
          : const HomeScreen(),
    );
  }
}

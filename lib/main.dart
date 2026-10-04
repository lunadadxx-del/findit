import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/finder_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock to portrait: detection boxes and guidance assume an upright image.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const FindItApp());
}

class FindItApp extends StatelessWidget {
  const FindItApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FindIt',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.dark,
        ),
      ),
      home: const FinderScreen(),
    );
  }
}

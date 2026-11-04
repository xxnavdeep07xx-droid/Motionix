import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'widgets/brand.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Brand.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const MotionixApp());
}

class MotionixApp extends StatelessWidget {
  const MotionixApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'Motionix',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: Brand.bg,
        colorScheme: base.colorScheme.copyWith(
          primary: Brand.violet,
          secondary: Brand.orange,
          surface: Brand.surface,
        ),
        sliderTheme: base.sliderTheme.copyWith(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

import 'package:asteroid/audio_handler.dart';
import 'package:asteroid/providers/theme_provider.dart';
import 'package:asteroid/providers/search_provider.dart';
import 'package:asteroid/screens/home_screen.dart';
import 'package:asteroid/screens/player_screen.dart';
import 'package:asteroid/screens/search_screen.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';

late AudioHandler _audioHandler;

Future<void> main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}');
  });
  WidgetsFlutterBinding.ensureInitialized();
  _audioHandler = await initAudioService();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => SearchProvider()),
        Provider<AudioHandler>.value(value: _audioHandler),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        ThemeData amoledTheme = ThemeData(
          brightness: Brightness.dark,
          primarySwatch: themeProvider.primarySwatch,
          scaffoldBackgroundColor: Colors.black,
          canvasColor: Colors.black,
          cardColor: Colors.grey[900],
          appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
        );
        // Map CustomThemeMode to ThemeMode for MaterialApp
        ThemeMode mode;
        switch (themeProvider.themeMode) {
          case CustomThemeMode.light:
            mode = ThemeMode.light;
            break;
          case CustomThemeMode.dark:
            mode = ThemeMode.dark;
            break;
          case CustomThemeMode.amoled:
            mode = ThemeMode.dark;
            break;
          case CustomThemeMode.system:
            mode = ThemeMode.system;
            break;
        }
        return AudioServiceWidget(
          child: MaterialApp(
            title: 'Asteroid Music',
            themeMode: mode, // Always ThemeMode
            theme: ThemeData(
              brightness: Brightness.light,
              primarySwatch: themeProvider.primarySwatch,
            ),
            darkTheme: themeProvider.themeMode == CustomThemeMode.amoled
                ? amoledTheme
                : ThemeData(
                    brightness: Brightness.dark,
                    primarySwatch: themeProvider.primarySwatch,
                  ),
            initialRoute: '/',
            routes: {
              '/': (context) => const HomeScreen(),
              '/player': (context) => const PlayerScreen(),
              '/search': (context) => const SearchScreen(),
            },
          ),
        );
      },
    );
  }
}

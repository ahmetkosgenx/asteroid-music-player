import 'package:flutter/material.dart';

enum CustomThemeMode { system, light, dark, amoled }

class ThemeProvider with ChangeNotifier {
  CustomThemeMode _themeMode = CustomThemeMode.system;
  MaterialColor _primarySwatch = Colors.blue;

  CustomThemeMode get themeMode => _themeMode;
  MaterialColor get primarySwatch => _primarySwatch;

  void setThemeMode(CustomThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void setPrimarySwatch(MaterialColor color) {
    _primarySwatch = color;
    notifyListeners();
  }
}
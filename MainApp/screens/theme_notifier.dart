import 'package:flutter/material.dart';

// This class will manage the theme state
class ThemeNotifier extends ChangeNotifier {
  ThemeData _themeData;

  // Constructor: Start with the light theme by default
  ThemeNotifier(this._themeData);

  // Getter to access the current theme
  ThemeData get getTheme => _themeData;

  // Method to toggle the theme and notify listeners
  void toggleTheme() {
    // If the current theme is light, switch to dark, and vice versa.
    if (_themeData == ThemeData.light()) {
      _themeData = ThemeData.dark();
    } else {
      _themeData = ThemeData.light();
    }
    // This is the crucial part: It tells all listening widgets to rebuild.
    notifyListeners();
  }
}

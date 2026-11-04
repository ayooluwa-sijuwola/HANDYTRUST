import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModePrefsKey = 'theme_mode';

/// Persists as a plain SharedPreferences string ('light' | 'dark') rather
/// than Firestore — theme preference is a local UI concern, not user data,
/// and this way it works even before sign-in (login/splash screens).
class ThemeNotifier extends StateNotifier<ThemeMode> {
  // Light is the default for a fresh session with no saved preference —
  // every Stitch reference screen is light-themed; a dark default meant
  // every screen rendered wrong for a first-time/never-toggled user
  // (found by actually running the app and screenshotting it, not by
  // reading this file in isolation — the login screen rendered dark navy
  // against light-themed references made it unmissable).
  ThemeNotifier() : super(ThemeMode.light) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeModePrefsKey);
    // Previously only ever re-applied a saved 'dark' value — a saved
    // 'light' choice fell through and left `state` at whatever the
    // constructor default was, so a user who explicitly chose light mode
    // would see it silently revert on next launch. Both saved values are
    // now actually restored.
    if (saved == 'dark') {
      state = ThemeMode.dark;
    } else if (saved == 'light') {
      state = ThemeMode.light;
    }
  }

  Future<void> toggle() async {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModePrefsKey, next == ThemeMode.dark ? 'dark' : 'light');
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>(
  (ref) => ThemeNotifier(),
);

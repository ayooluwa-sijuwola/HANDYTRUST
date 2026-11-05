import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _onboardingSeenKey = 'onboarding_seen_v1';

/// Stage 8: whether this device has shown the onboarding screen. Local UI
/// state only (same approach as the theme preference) — no server data.
/// `null` while loading; the router treats that as "seen" so a slow
/// SharedPreferences read never traps a returning user on onboarding.
class OnboardingNotifier extends StateNotifier<bool?> {
  OnboardingNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_onboardingSeenKey) ?? false;
  }

  Future<void> markSeen() async {
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingSeenKey, true);
  }
}

final onboardingSeenProvider = StateNotifierProvider<OnboardingNotifier, bool?>((ref) => OnboardingNotifier());

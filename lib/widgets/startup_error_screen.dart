import 'package:flutter/material.dart';

/// Shown in place of an indefinite loading spinner when app startup cannot
/// proceed — either Firebase itself failed to initialize, or the initial
/// auth-state resolution never completed within a bounded time (see
/// design/V2_IOS_SAFARI_RELIABILITY_REPORT.md — this is the fix for the
/// "infinite spinner on Safari" failure mode: a browser/network condition
/// that stalls Firebase Auth's persisted-session restoration previously had
/// no failure state at all, just an unbounded CircularProgressIndicator).
///
/// Deliberately never renders the raw [error] object — only a generic,
/// actionable message plus a Retry action. The real error is still logged
/// via debugPrint by the caller before this widget is shown.
class StartupErrorScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const StartupErrorScreen({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_tethering_error_rounded,
                    color: Colors.white70, size: 48),
                const SizedBox(height: 20),
                const Text(
                  'Something went wrong while starting HandyTrust.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Check your internet connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0B1220),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Retry',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

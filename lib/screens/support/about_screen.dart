import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_scaffold.dart';

/// Minimal about/legal screen — replaces the previously no-op
/// "About HandyTrust" menu item in Profile (redesign/v2/06 finding).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 4),
                  const AuthBrandHeader(),
                ],
              ),
              const SizedBox(height: 24),
              Center(child: AuthLogoBadge(size: 72)),
              const SizedBox(height: 16),
              Text(
                'HandyTrust',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: context.colors.textPrimary,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Version 1.0.0',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.textSecondary, fontFamily: 'Inter'),
              ),
              const SizedBox(height: 28),
              AuthCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Nigeria's trusted service marketplace — securely connecting "
                      'customers with verified artisans through escrow-protected payments.',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _LegalLinkRow(label: 'Terms of Service', url: 'https://handytrust.example.com/terms'),
                    const Divider(height: 24),
                    const _LegalLinkRow(label: 'Privacy Policy', url: 'https://handytrust.example.com/privacy'),
                  ],
                ),
              ),
              const AuthFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalLinkRow extends StatelessWidget {
  final String label;
  final String url;

  const _LegalLinkRow({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
          Icon(Icons.open_in_new_rounded, size: 16, color: context.colors.textTertiary),
        ],
      ),
    );
  }
}

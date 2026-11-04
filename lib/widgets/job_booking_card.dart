import 'package:flutter/material.dart';
import '../theme/app_design_system.dart';
import '../theme/app_theme.dart';

/// Visual tone for [JobBookingCard]'s status badge. The card itself has no
/// opinion about which phase maps to which tone — the caller decides,
/// typically from WorkflowGateService.describeStep(...).phase — this just
/// keeps the three badge colors consistent wherever the card is used.
enum JobBookingTone { positive, neutral, attention }

/// The "My Bookings" job card from the Stitch redesign: status badge, date,
/// counterparty (or a "searching for a match" placeholder for unmatched
/// jobs), price, and up to two actions.
///
/// Purely presentational — same convention as WorkflowStatusCard. It does
/// not read job.status/agreementStatus itself; the screen that places it
/// computes phase/tone/labels (via WorkflowGateService for anything
/// workflow-related) and passes the result in.
class JobBookingCard extends StatelessWidget {
  final String title;
  final String dateLabel;

  final String phase;
  final JobBookingTone tone;

  /// Icon shown inside the status badge — Stitch's own cards always pair
  /// one (clock for "In Progress", hourglass for "Awaiting Artisan", etc.),
  /// there's no separate "Waiting on X" text row the way the pre-Stitch
  /// version of this card had.
  final IconData? phaseIcon;

  /// True for a job with no artisan yet — renders the "Searching…" +
  /// proposals-count placeholder instead of a counterparty row.
  final bool isSearching;
  final int? proposalsCount;

  final String? counterpartyName;
  final String? counterpartyAvatarUrl;
  final bool counterpartyVerified;

  final String priceLabel;
  final String priceValue;

  final String? primaryLabel;
  final VoidCallback? onPrimary;
  // Stitch's own primary action on a matched job ("View Details") is dark
  // navy, not the app's Trust Green — a deliberate deviation from the rest
  // of the palette on this one button, matched exactly rather than
  // normalized to the theme's usual primary color.
  final bool primaryDark;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  final VoidCallback? onTap;

  const JobBookingCard({
    super.key,
    required this.title,
    required this.dateLabel,
    required this.phase,
    required this.tone,
    this.phaseIcon,
    required this.priceLabel,
    required this.priceValue,
    this.isSearching = false,
    this.proposalsCount,
    this.counterpartyName,
    this.counterpartyAvatarUrl,
    this.counterpartyVerified = false,
    this.primaryLabel,
    this.onPrimary,
    this.primaryDark = false,
    this.secondaryLabel,
    this.onSecondary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: appCardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(label: phase, tone: tone, icon: phaseIcon),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 13, color: context.colors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    dateLabel,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: context.colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(color: context.colors.borderLight, height: 1),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _counterpartyRow(context)),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      priceValue,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    Text(
                      priceLabel,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: context.colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (primaryLabel != null || secondaryLabel != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  if (secondaryLabel != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onSecondary,
                        child: Text(secondaryLabel!),
                      ),
                    ),
                  if (secondaryLabel != null && primaryLabel != null)
                    const SizedBox(width: 10),
                  if (primaryLabel != null)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onPrimary,
                        // context.colors.ink, not the fixed AppColors.
                        // darkBackground literal this used to hardcode —
                        // same "dark navy commitment button nearly
                        // invisible in dark mode" issue CommitButton had,
                        // fixed the same way: the theme extension already
                        // carries a dark-mode-appropriate ink tone.
                        style: primaryDark
                            ? ElevatedButton.styleFrom(
                                backgroundColor: context.colors.ink,
                                foregroundColor: context.colors.onInk,
                                side: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? BorderSide(
                                        color: Colors.white
                                            .withValues(alpha: 0.10))
                                    : BorderSide.none,
                              )
                            : null,
                        child: Text(primaryLabel!),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _counterpartyRow(BuildContext context) {
    if (isSearching) {
      return Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: context.colors.surfaceVariant,
            child: Icon(Icons.person_search_outlined,
                size: 16, color: context.colors.textTertiary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Searching…',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                ),
                if (proposalsCount != null)
                  Text(
                    'Proposals: $proposalsCount',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: context.colors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: context.colors.primarySurface,
          backgroundImage: counterpartyAvatarUrl != null
              ? NetworkImage(counterpartyAvatarUrl!)
              : null,
          child: counterpartyAvatarUrl == null
              ? Text(
                  (counterpartyName?.isNotEmpty ?? false)
                      ? counterpartyName![0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    color: context.colors.primary,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  counterpartyName ?? '',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (counterpartyVerified) ...[
                const SizedBox(width: 4),
                Icon(Icons.verified_rounded,
                    size: 14, color: context.colors.primary),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final JobBookingTone tone;
  final IconData? icon;

  const _StatusBadge({required this.label, required this.tone, this.icon});

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (tone) {
      JobBookingTone.positive => (context.colors.primary, context.colors.primarySurface),
      JobBookingTone.attention => (context.colors.warning, context.colors.warningSurface),
      JobBookingTone.neutral => (context.colors.textSecondary, context.colors.surfaceVariant),
    };
    return AppBadge(label: label, color: fg, backgroundColor: bg, icon: icon);
  }
}

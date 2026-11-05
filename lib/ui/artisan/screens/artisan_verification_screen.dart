import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/artisan_eligibility.dart';
import '../../../models/verification_model.dart';
import '../../../providers/verification_provider.dart';
import '../../components/ht_components.dart';
import '../../components/ht_kit.dart';
import '../../screens/verification_screen.dart';
import '../../theme/ht_theme.dart';
import '../artisan_shell.dart';
import '../components/pro_components.dart';

/// Artisan verification hub (`/verification` in Artisan Mode): live status
/// and steps; uploading reuses the Stage 8 ID + selfie flow.
class ArtisanVerificationScreen extends ConsumerWidget {
  const ArtisanVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final ctx = ref.watch(artisanContextProvider).asData?.value;
    if (ctx == null) return const ArtisanPage(title: 'Identity verification', children: [SizedBox(height: 80), HtLoadingView()]);
    final vAsync = ref.watch(verificationStatusProvider(ctx.uid));
    final verified = ctx.artisan != null && ArtisanEligibility.isReallyVerified(ctx.artisan!);

    void upload() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const VerificationScreen()));

    return vAsync.when(
      loading: () => const ArtisanPage(title: 'Identity verification', children: [SizedBox(height: 80), HtLoadingView(label: 'Checking your status…')]),
      error: (e, _) => ArtisanPage(title: 'Identity verification', children: [ArtisanState.error(e, onRetry: () => ref.invalidate(verificationStatusProvider(ctx.uid)))]),
      data: (v) {
        final hasId = v != null && v.governmentIdUrl.isNotEmpty;
        final hasSelfie = v != null && v.selfieUrl.isNotEmpty;
        final status = verified ? VerificationStatus.approved : v?.status;
        final done = [hasId || verified, hasSelfie || verified, verified].where((x) => x).length;
        final (title, text, tone) = switch (status) {
          VerificationStatus.approved => ('Verified', 'You appear with the Verified badge and can quote on matched jobs.', HtTone.success),
          VerificationStatus.pending when hasId && hasSelfie => ('Under review', 'HandyTrust is reviewing your documents. You can keep setting up your profile meanwhile.', HtTone.warning),
          VerificationStatus.rejected => ('Needs attention', v?.rejectionReason?.isNotEmpty == true ? 'Not approved: ${v!.rejectionReason}. Upload new photos to try again.' : 'Your documents weren’t approved. Upload new photos to try again.', HtTone.danger),
          _ => ('Not verified yet', 'Upload a government ID and a selfie. Verification is required before you can quote.', HtTone.neutral),
        };
        Widget row(IconData i, String t, String s, bool ok, {bool pending = false}) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: HtCard(
                radius: HtRadius.inner,
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  htIconTile(context, i, tone: ok ? HtTone.success : (pending ? HtTone.warning : HtTone.neutral), size: 40),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14)), Text(s, style: HtType.small(p.textSecondary))])),
                  HtStatusPill(label: ok ? 'Done' : (pending ? 'Pending' : 'To do'), tone: ok ? HtTone.success : (pending ? HtTone.warning : HtTone.neutral)),
                ]),
              ),
            );
        final canUpload = !verified && !(status == VerificationStatus.pending && hasId && hasSelfie);
        return ArtisanPage(
          title: 'Identity verification',
          bottomBar: canUpload ? ProActionBar(label: status == VerificationStatus.rejected ? 'Upload new documents' : 'Upload documents', onPressed: upload) : null,
          children: [
            HtCard(
              child: Row(children: [
                ProCountdownRing(fraction: done / 3, big: '$done/3', small: 'steps', size: 84, tone: tone),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: HtType.cardTitle(p.textPrimary)), Text(text, style: HtType.small(p.textSecondary))])),
              ]),
            ),
            const SizedBox(height: 12),
            row(Icons.badge_outlined, 'Government ID', hasId || verified ? 'Photo uploaded' : 'Photo of a valid ID', hasId || verified),
            row(Icons.face_outlined, 'Selfie', hasSelfie || verified ? 'Photo uploaded' : 'A clear photo of your face', hasSelfie || verified),
            row(Icons.fact_check_outlined, 'HandyTrust review', 'An administrator checks your documents', verified, pending: !verified && hasId && hasSelfie && status == VerificationStatus.pending),
            const SizedBox(height: 4),
            const HtInfoBanner(icon: Icons.lock_outline_rounded, tone: HtTone.neutral, text: 'Your ID photos are seen only by HandyTrust reviewers and are never shown to customers.'),
          ],
        );
      },
    );
  }
}

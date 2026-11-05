import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/verification_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart' show storageServiceProvider;
import '../../providers/verification_provider.dart';
import '../components/ht_components.dart';
import '../theme/ht_theme.dart';

/// Identity verification (references 7 dark, 23 light), driving the real
/// artisan verification flow: government-ID photo + selfie uploaded via
/// StorageService (metadata stripped), then a manual HandyTrust review
/// (verificationServiceProvider). Reference claims with no backend
/// support — NIN/BVN/NIMC matching, "3D biometric" scans, escrow tiers,
/// 256-bit / end-to-end encryption, approval rates, "< 1 minute"
/// turnaround — are not shown.
class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});
  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  final _picker = ImagePicker();
  Uint8List? _id;
  Uint8List? _selfie;
  bool _busy = false;
  bool _deferring = false;

  Future<bool> _permission(Permission permission, String what) async {
    final status = await permission.request();
    if (status.isGranted || status.isLimited) return true;
    if (!mounted) return false;
    htSnack(
      context,
      status.isPermanentlyDenied ? '$what access is turned off for HandyTrust. Enable it in Settings to continue.' : '$what permission is required to continue.',
      error: true,
    );
    if (status.isPermanentlyDenied) await openAppSettings();
    return false;
  }

  Future<void> _captureId() async {
    final p = context.ht;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: p.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(HtRadius.card))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HtMenuRow(icon: Icons.photo_camera_outlined, title: 'Take a photo of your ID', onTap: () => Navigator.of(ctx).pop(ImageSource.camera)),
            HtMenuRow(icon: Icons.photo_library_outlined, title: 'Choose from gallery', onTap: () => Navigator.of(ctx).pop(ImageSource.gallery)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final ok = await _permission(source == ImageSource.camera ? Permission.camera : Permission.photos, source == ImageSource.camera ? 'Camera' : 'Photo library');
    if (!ok) return;
    final x = await _picker.pickImage(source: source, maxWidth: 2560);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (mounted) setState(() => _id = bytes);
  }

  Future<void> _captureSelfie() async {
    if (!await _permission(Permission.camera, 'Camera')) return;
    final x = await _picker.pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front, maxWidth: 2048);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (mounted) setState(() => _selfie = bytes);
  }

  Future<void> _submit(String uid) async {
    if (_id == null || _selfie == null) {
      htSnack(context, 'Please add a photo of your government ID and a selfie.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final storage = ref.read(storageServiceProvider);
      final urls = await Future.wait([
        storage.uploadVerificationPhoto(userId: uid, type: 'selfie', bytes: _selfie!),
        storage.uploadVerificationPhoto(userId: uid, type: 'id_front', bytes: _id!),
      ]);
      await ref.read(verificationServiceProvider).submit(uid: uid, selfieUrl: urls[0], governmentIdUrl: urls[1]);
      if (!mounted) return;
      htSnack(context, "Documents submitted. We'll notify you when the review is complete.");
      setState(() {
        _id = null;
        _selfie = null;
      });
    } catch (e) {
      if (mounted) htSnack(context, 'Submission failed. Check your connection and try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _later(String uid) async {
    setState(() => _deferring = true);
    try {
      await ref.read(verificationServiceProvider).deferVerification(uid);
      if (!mounted) return;
      htSnack(context, 'You can verify your identity later from your profile.');
      context.pop();
    } catch (_) {
      if (mounted) htSnack(context, 'Could not save your choice. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _deferring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final user = ref.watch(currentUserProvider).asData?.value;
    final recordAsync = user == null ? const AsyncValue<VerificationModel?>.loading() : ref.watch(verificationStatusProvider(user.uid));
    final record = recordAsync.asData?.value;
    final status = record?.status;
    final submitted = status == VerificationStatus.pending || status == VerificationStatus.approved;
    final idDone = submitted || _id != null;
    final selfieDone = submitted || _selfie != null;
    final reviewDone = status == VerificationStatus.approved;
    final completed = [idDone, selfieDone, reviewDone].where((d) => d).length;

    return Scaffold(
      backgroundColor: p.background,
      body: HtBackground(
        child: SafeArea(
          child: user == null
              ? const HtLoadingView()
              : ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    HtScreenHeader(
                      title: 'Verify Your Identity',
                      center: false,
                      trailing: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: p.headerAvatarFill, shape: BoxShape.circle),
                        child: Icon(Icons.person_outline_rounded, color: p.onHeaderAvatar),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          color: p.surface,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: p.border),
                          boxShadow: p.isDark ? [BoxShadow(color: p.primaryGlow, blurRadius: 30)] : p.cardShadow,
                        ),
                        child: Icon(Icons.verified_user_outlined, size: 54, color: p.isDark ? p.accent : p.accentStrong),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Center(
                      child: Text.rich(
                        TextSpan(children: [
                          const TextSpan(text: 'Safety Starts With '),
                          TextSpan(text: 'Trust', style: TextStyle(color: p.isDark ? p.accent : p.accentStrong)),
                        ]),
                        style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 24),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 10, 32, 0),
                      child: Text(
                        'Artisans verify their identity with a government ID and a selfie, reviewed by HandyTrust, so customers know who they are hiring.',
                        style: HtType.body(p.textSecondary).copyWith(fontSize: 14, height: 1.55),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 26, HtSpace.gutter, 0),
                      child: HtCard(
                        radius: 30,
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.fact_check_outlined, color: p.isDark ? p.accent : p.textPrimary),
                                const SizedBox(width: 10),
                                Expanded(child: Text('Verification Checklist', style: HtType.sectionTitle(p.textPrimary))),
                                HtStatusPill(label: '$completed of 3 Completed', tone: HtTone.accent),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _CheckRow(
                              icon: Icons.badge_outlined,
                              title: 'Government ID',
                              subtitle: submitted ? 'Submitted for review' : (_id != null ? 'Photo added — tap to retake' : 'Photo of your national ID card, licence or passport'),
                              done: idDone,
                              onTap: submitted || _busy ? null : _captureId,
                            ),
                            _CheckRow(
                              icon: Icons.face_retouching_natural_outlined,
                              title: 'Take a selfie',
                              subtitle: submitted ? 'Submitted for review' : (_selfie != null ? 'Selfie added — tap to retake' : 'A clear photo of your face'),
                              done: selfieDone,
                              onTap: submitted || _busy ? null : _captureSelfie,
                            ),
                            _CheckRow(
                              icon: Icons.manage_search_rounded,
                              title: 'Verification review',
                              subtitle: switch (status) {
                                VerificationStatus.pending => 'HandyTrust is reviewing your documents',
                                VerificationStatus.approved => 'Your identity is verified',
                                VerificationStatus.rejected => 'Not approved${(record?.rejectionReason ?? '').isEmpty ? '' : ': ${record!.rejectionReason}'} — please resubmit',
                                _ => 'Reviewed by HandyTrust after you submit',
                              },
                              done: reviewDone,
                              inProgress: status == VerificationStatus.pending,
                              highlighted: status == VerificationStatus.pending,
                              error: status == VerificationStatus.rejected,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 18, HtSpace.gutter, 0),
                      child: HtInfoBanner(
                        icon: Icons.lock_outline_rounded,
                        title: 'Privacy First',
                        text: 'Your ID photos are seen only by HandyTrust reviewers and are never shown to customers.',
                        tone: HtTone.neutral,
                      ),
                    ),
                    if (!submitted) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 26, HtSpace.gutter, 0),
                        child: HtPrimaryButton(
                          label: 'Continue',
                          icon: Icons.arrow_forward_rounded,
                          loading: _busy,
                          onPressed: _busy ? null : () => _submit(user.uid),
                        ),
                      ),
                      if (status == null || status == VerificationStatus.pendingLater) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton(
                            onPressed: _deferring || _busy ? null : () => _later(user.uid),
                            child: Text('Verify later', style: HtType.bodyStrong(p.textSecondary)),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: () => context.push('/support'),
                        child: Text('Need help with verification?',
                            style: HtType.bodyStrong(p.isDark ? p.accent : p.accentStrong).copyWith(decoration: p.isDark ? TextDecoration.underline : null, decorationColor: p.accent)),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
    this.onTap,
    this.inProgress = false,
    this.highlighted = false,
    this.error = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback? onTap;
  final bool inProgress;
  final bool highlighted;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final trailing = done
        ? Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: p.isDark ? p.success : p.accentSoft, shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, color: p.isDark ? p.onPrimary : p.accentStrong, size: 20),
          )
        : inProgress
            ? SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2.5, color: p.isDark ? p.accent : p.accentStrong))
            : error
                ? Icon(Icons.error_outline_rounded, color: p.danger)
                : Icon(Icons.chevron_right_rounded, color: p.textMuted);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: highlighted && p.isDark
          ? BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border(left: BorderSide(color: p.accent, width: 3)))
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(HtRadius.inner),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              if (p.isDark) ...[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: p.surfaceRaised, shape: BoxShape.circle),
                  child: Icon(icon, color: p.textSecondary, size: 21),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: HtType.cardTitle(p.textPrimary).copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: HtType.small(error ? p.danger : (highlighted ? (p.isDark ? p.accent : p.textSecondary) : p.textSecondary))),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

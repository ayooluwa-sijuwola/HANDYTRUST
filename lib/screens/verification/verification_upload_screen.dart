import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/services/storage_service.dart';
import '../../models/verification_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/verification_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_snackbar.dart';

class VerificationUploadScreen extends ConsumerStatefulWidget {
  const VerificationUploadScreen({super.key});

  @override
  ConsumerState<VerificationUploadScreen> createState() =>
      _VerificationUploadScreenState();
}

class _VerificationUploadScreenState
    extends ConsumerState<VerificationUploadScreen> {
  final _picker = ImagePicker();
  final _storage = StorageService();

  Uint8List? _selfieBytes;
  Uint8List? _idBytes;
  bool _uploading = false;
  bool _processingSelfie = false;
  bool _processingId = false;
  bool _deferring = false;

  VerificationModel? _existing;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkExistingStatus();
  }

  Future<void> _checkExistingStatus() async {
    final user = ref.read(currentUserProvider).asData?.value;
    if (user == null) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    try {
      debugPrint('[VerificationUpload] checking existing status for ${user.uid}');
      final doc = await FirebaseFirestore.instance
          .collection('verifications')
          .doc(user.uid)
          .get();
      if (mounted) {
        setState(() {
          _existing = doc.exists
              ? VerificationModel.fromJson(doc.data()!)
              : null;
          _checking = false;
        });
      }
    } catch (e) {
      // Non-fatal: treat "couldn't check" the same as "no existing
      // submission" — the artisan can still submit, worst case is a
      // redundant resubmission, never data loss. Logged so it's visible in
      // debug output instead of vanishing silently.
      debugPrint('[VerificationUpload] checkExistingStatus failed: $e');
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<Uint8List> _compress(Uint8List bytes) async {
    if (bytes.lengthInBytes <= 800 * 1024) return bytes;
    return FlutterImageCompress.compressWithList(
      bytes,
      quality: 75,
      format: CompressFormat.jpeg,
    );
  }

  // Root cause of "the selfie/ID step silently does nothing" (traced from
  // source, see the verification-flow debug summary): image_picker's
  // pickImage() returns null both when the user genuinely cancels AND, on
  // some OS/plugin version combinations, when the OS denies the
  // camera/photo-library permission outright — the two are indistinguishable
  // from the return value alone, and this screen previously treated both as
  // "silently do nothing." Requesting the permission explicitly first (via
  // permission_handler, already a project dependency) lets a real denial
  // surface as a real, actionable message instead of a blank tap.
  //
  // Separately and more severely on iOS specifically: ios/Runner/Info.plist
  // had NO NSCameraUsageDescription or NSPhotoLibraryUsageDescription keys
  // at all. Without those, iOS refuses the permission request outright
  // before any prompt is even shown — every artisan on iOS would hit this
  // on the very first "Take Selfie" tap, which is the single highest-
  // confidence explanation for "an artisan cannot submit verification."
  // Fixed in Info.plist alongside this change.
  Future<bool> _ensurePermission(Permission permission, String what) async {
    final status = await permission.request();
    if (status.isGranted || status.isLimited) return true;
    if (!mounted) return false;
    if (status.isPermanentlyDenied) {
      showErrorSnackbar(
        context,
        '$what access is turned off for HandyTrust. Enable it in Settings to continue.',
        onRetry: openAppSettings,
        actionLabel: 'Open Settings',
      );
    } else {
      showErrorSnackbar(context, '$what permission is required to continue.');
    }
    return false;
  }

  // Both pickers previously had zero error handling and called setState()
  // without checking `mounted` — if the widget was disposed while the
  // camera/gallery intent was in flight (the camera is a separate Activity
  // on Android; backgrounding or low-memory reclaim during that window is
  // common), this threw "setState() called after dispose()" uncaught,
  // which is the most likely cause of the screen "closing unexpectedly."
  Future<void> _takeSelfie() async {
    if (_processingSelfie) return;
    setState(() => _processingSelfie = true);
    try {
      if (!await _ensurePermission(Permission.camera, 'Camera')) return;
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 80,
      );
      if (picked == null) return;
      debugPrint('[VerificationUpload] selfie selected: ${picked.path}');
      final compressed = await _compress(await picked.readAsBytes());
      if (mounted) setState(() => _selfieBytes = compressed);
    } catch (e) {
      debugPrint('[VerificationUpload] selfie capture failed: $e');
      if (mounted) showErrorSnackbar(context, 'Could not capture selfie: $e');
    } finally {
      if (mounted) setState(() => _processingSelfie = false);
    }
  }

  Future<void> _pickId({bool fromCamera = false}) async {
    if (_processingId) return;
    setState(() => _processingId = true);
    try {
      final permission = fromCamera ? Permission.camera : Permission.photos;
      final label = fromCamera ? 'Camera' : 'Photo library';
      if (!await _ensurePermission(permission, label)) return;
      final picked = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;
      debugPrint('[VerificationUpload] ID document selected: ${picked.path}');
      final compressed = await _compress(await picked.readAsBytes());
      if (mounted) setState(() => _idBytes = compressed);
    } catch (e) {
      debugPrint('[VerificationUpload] ID capture failed: $e');
      if (mounted) showErrorSnackbar(context, 'Could not load ID document: $e');
    } finally {
      if (mounted) setState(() => _processingId = false);
    }
  }

  // Split into two explicit stages (upload, then Firestore submit) so a
  // failure clearly tells the artisan — and the debug log — which one
  // actually failed, instead of a single generic "Upload failed" message
  // covering both. Success (snackbar + pop) only ever fires after the
  // Firestore write in stage 2 completes without throwing — the upload
  // alone is never treated as success.
  Future<void> _submit() async {
    if (_selfieBytes == null || _idBytes == null) {
      showErrorSnackbar(
          context, 'Please capture both a selfie and your government ID.');
      return;
    }

    final user = ref.read(currentUserProvider).asData?.value;
    if (user == null) {
      showErrorSnackbar(
          context, 'Your session could not be verified. Please sign in again.');
      return;
    }

    final uid = user.uid;
    setState(() => _uploading = true);

    String selfieUrl;
    String idUrl;
    try {
      debugPrint('[VerificationUpload] upload started for $uid');
      final results = await Future.wait([
        _storage.uploadVerificationPhoto(
            userId: uid, type: 'selfie', bytes: _selfieBytes!),
        _storage.uploadVerificationPhoto(
            userId: uid, type: 'id_front', bytes: _idBytes!),
      ]);
      selfieUrl = results[0];
      idUrl = results[1];
      debugPrint('[VerificationUpload] upload completed for $uid');
    } catch (e) {
      debugPrint('[VerificationUpload] upload failed for $uid: $e');
      if (mounted) {
        showErrorSnackbar(context,
            'Failed to upload your documents. Check your connection and try again.');
        setState(() => _uploading = false);
      }
      return;
    }

    try {
      debugPrint('[VerificationUpload] firestore write started for $uid');
      await ref.read(verificationServiceProvider).submit(
            uid: uid,
            selfieUrl: selfieUrl,
            governmentIdUrl: idUrl,
          );
      debugPrint('[VerificationUpload] firestore write completed for $uid');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Documents submitted. We\'ll review within 24–48 hours.'),
            backgroundColor: context.colors.accent,
          ),
        );
        context.pop();
      }
    } catch (e) {
      debugPrint('[VerificationUpload] firestore submit failed for $uid: $e');
      if (mounted) {
        showErrorSnackbar(context,
            'Your documents uploaded, but submission failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // "Verify Later" — the explicit non-blocking escape hatch. Skips the
  // upload requirement entirely (no Storage call, no /verifications doc)
  // and just flags the artisan's account as deferred so onboarding can
  // continue. Reachable both as a deliberate choice and as the fallback
  // when uploads keep failing — it's a permanent secondary action on this
  // screen rather than something that only appears after a failure, so a
  // flaky connection never strands the artisan with no way forward.
  Future<void> _verifyLater() async {
    if (_deferring) return;
    final user = ref.read(currentUserProvider).asData?.value;
    if (user == null) {
      showErrorSnackbar(
          context, 'Your session could not be verified. Please sign in again.');
      return;
    }

    setState(() => _deferring = true);
    try {
      debugPrint('[VerificationUpload] deferring verification for ${user.uid}');
      await ref.read(verificationServiceProvider).deferVerification(user.uid);
      debugPrint('[VerificationUpload] verification deferred for ${user.uid}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'You can verify your identity later from your dashboard.'),
            backgroundColor: context.colors.accent,
          ),
        );
        context.pop();
      }
    } catch (e) {
      debugPrint('[VerificationUpload] deferVerification failed for ${user.uid}: $e');
      if (mounted) {
        showErrorSnackbar(
            context, 'Could not save your choice. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _deferring = false);
    }
  }

  void _showIdSourcePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(context);
                _pickId(fromCamera: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickId();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        title: const Text(
          'Verify Your Identity',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: _checking
            ? const Center(child: CircularProgressIndicator())
            : _existing?.status == VerificationStatus.pending
                ? _PendingReviewView()
                : _existing?.status == VerificationStatus.approved
                    ? const _ApprovedView()
                    : _UploadForm(
                    selfieBytes: _selfieBytes,
                    idBytes: _idBytes,
                    uploading: _uploading,
                    processingSelfie: _processingSelfie,
                    processingId: _processingId,
                    deferring: _deferring,
                    onTakeSelfie: _takeSelfie,
                    onPickId: _showIdSourcePicker,
                    onSubmit: _submit,
                    onVerifyLater: _verifyLater,
                    isRejected: _existing?.status == VerificationStatus.rejected,
                    isDeferred: _existing?.status == VerificationStatus.pendingLater,
                    rejectionReason: _existing?.rejectionReason,
                  ),
      ),
    );
  }
}

class _PendingReviewView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.colors.accentSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.hourglass_top_rounded,
                  size: 40, color: context.colors.accent),
            ),
            const SizedBox(height: 20),
            Text(
              'Documents Submitted',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Your verification documents are under review. This usually takes 24–48 hours. You\'ll be notified once approved.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Back to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}

// Previously absent: an already-approved artisan who navigated back to this
// screen fell through to _UploadForm and could tap Submit — Firestore
// rules only let the owner update verifications/{uid} while its status is
// 'rejected' or 'pending_later', so an approved artisan's resubmission was
// rejected with the generic "submission failed" message. Not the main
// "cannot submit" failure point, but a real dead-end worth a clear
// dedicated state instead of a confusing rules error.
class _ApprovedView extends StatelessWidget {
  const _ApprovedView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.colors.accentSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.verified_rounded,
                  size: 40, color: context.colors.accent),
            ),
            const SizedBox(height: 20),
            Text(
              'Identity Verified',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Your identity has already been verified. You appear with the Verified badge to customers.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Back to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadForm extends StatelessWidget {
  final Uint8List? selfieBytes;
  final Uint8List? idBytes;
  final bool uploading;
  final bool processingSelfie;
  final bool processingId;
  final bool deferring;
  final VoidCallback onTakeSelfie;
  final VoidCallback onPickId;
  final VoidCallback onSubmit;
  final VoidCallback onVerifyLater;
  final bool isRejected;
  final bool isDeferred;
  final String? rejectionReason;

  const _UploadForm({
    required this.selfieBytes,
    required this.idBytes,
    required this.uploading,
    required this.processingSelfie,
    required this.processingId,
    required this.deferring,
    required this.onTakeSelfie,
    required this.onPickId,
    required this.onSubmit,
    required this.onVerifyLater,
    required this.isRejected,
    required this.isDeferred,
    this.rejectionReason,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (isRejected) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.colors.errorSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.cancel_outlined, color: context.colors.error, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    rejectionReason != null && rejectionReason!.isNotEmpty
                        ? 'Your previous submission was rejected: $rejectionReason'
                        : 'Your previous submission was rejected. Please resubmit with clearer photos.',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.error,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (isDeferred && !isRejected) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.colors.accentSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_outlined, color: context.colors.accent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You chose to verify later. Complete it anytime — submitting below replaces that choice.',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.accent,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.colors.primarySurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, color: context.colors.primary, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Identity verification earns the Verified badge and builds customer trust.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.primary,
                    fontFamily: 'Inter',
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        _VerificationCard(
          title: 'Step 1: Take a Selfie',
          subtitle:
              'Use your front camera. Ensure your face is clearly visible and well-lit.',
          icon: Icons.face_outlined,
          bytes: selfieBytes,
          processing: processingSelfie,
          onCapture: onTakeSelfie,
          captureLabel: 'Take Selfie',
        ),
        const SizedBox(height: 16),

        _VerificationCard(
          title: 'Step 2: Upload Government ID',
          subtitle:
              'National ID, Driver\'s licence, Voter\'s card, or International passport.',
          icon: Icons.badge_outlined,
          bytes: idBytes,
          processing: processingId,
          onCapture: onPickId,
          captureLabel: 'Upload ID',
        ),
        const SizedBox(height: 32),

        ElevatedButton(
          onPressed: (selfieBytes == null ||
                  idBytes == null ||
                  uploading ||
                  processingSelfie ||
                  processingId ||
                  deferring)
              ? null
              : onSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.colors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: context.colors.border,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: uploading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text(
                  'Submit for Verification',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: (uploading || deferring) ? null : onVerifyLater,
          child: deferring
              ? SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: context.colors.textSecondary),
                )
              : Text(
                  'Verify Later',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Text(
          'You can keep using the app and complete verification anytime from your dashboard.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: context.colors.textTertiary,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }
}

class _VerificationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Uint8List? bytes;
  final bool processing;
  final VoidCallback onCapture;
  final String captureLabel;

  const _VerificationCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.bytes,
    required this.processing,
    required this.onCapture,
    required this.captureLabel,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: bytes != null ? context.colors.accent : context.colors.border,
          width: bytes != null ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                bytes != null ? Icons.check_circle_rounded : icon,
                color: bytes != null ? context.colors.accent : context.colors.textSecondary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          if (bytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                bytes!,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: processing ? null : onCapture,
              icon: processing
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: context.colors.textSecondary),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: Text(processing ? 'Processing…' : 'Retake'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.textSecondary,
                side: BorderSide(color: context.colors.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: processing ? null : onCapture,
                icon: processing
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: context.colors.primary),
                      )
                    : const Icon(Icons.add_a_photo_outlined, size: 18),
                label: Text(processing ? 'Processing…' : captureLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primarySurface,
                  foregroundColor: context.colors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

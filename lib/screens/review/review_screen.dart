import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/job_model.dart';
import '../../models/review_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../providers/review_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/review_tile.dart';
import '../../widgets/star_rating.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  final String jobId;

  const ReviewScreen({super.key, required this.jobId});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  int _rating = 0;
  final _commentController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jobAsync = ref.watch(jobStreamProvider(widget.jobId));
    final existingReviewAsync = ref.watch(jobReviewProvider(widget.jobId));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Leave a Review')),
      body: jobAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (job) {
          if (job == null) return const Center(child: Text('Job not found'));
          if (job.status != JobStatus.completed) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 48, color: context.colors.textSecondary),
                    const SizedBox(height: 16),
                    Text(
                      'Reviews are only available after a job is completed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.colors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    TextButton(onPressed: () => context.go('/home'), child: const Text('Go home')),
                  ],
                ),
              ),
            );
          }
          return existingReviewAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (existing) {
              if (existing != null) return _alreadyReviewed(existing);
              return _reviewForm(job);
            },
          );
        },
      ),
    );
  }

  Widget _alreadyReviewed(ReviewModel review) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 48, color: context.colors.accent),
            const SizedBox(height: 12),
            const Text(
              'You already reviewed this job',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ReviewTile(review: review),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.go('/home'),
              child: const Text('Go home'),
            ),
          ],
        ),
      );

  Widget _reviewForm(JobModel job) {
    return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.star_outline_rounded,
                    size: 48, color: context.colors.ratingGold),
                const SizedBox(height: 12),
                const Text(
                  'How was the service?',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Your review helps other customers and motivates artisans.',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                InteractiveStarRating(
                  value: _rating,
                  onChanged: (v) => setState(() => _rating = v),
                  size: 44,
                ),
                const SizedBox(height: 8),
                Text(
                  _ratingLabel(_rating),
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _commentController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Share your experience (optional)…',
                    alignLabelWithHint: true,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: context.colors.error, fontFamily: 'Inter')),
                ],
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _submitting ? null : () => _submit(job.artisanId),
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit Review'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Skip for now'),
                ),
              ],
            ),
          );
  }

  String _ratingLabel(int r) => switch (r) {
        1 => 'Poor',
        2 => 'Fair',
        3 => 'Good',
        4 => 'Very Good',
        5 => 'Excellent!',
        _ => 'Tap a star to rate',
      };

  Future<void> _submit(String artisanId) async {
    if (_rating == 0) {
      setState(() => _error = 'Please select a rating.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final uid = ref.read(authStateChangesProvider).value?.uid ?? '';
      final db = FirebaseFirestore.instance;
      // Deterministic doc ID (= jobId) gives us "one review per job" for
      // free: a second attempt would hit the `allow update: if false;`
      // Firestore rule instead of `allow create`, and is rejected.
      final ref2 = db.collection('reviews').doc(widget.jobId);
      final review = ReviewModel(
        id: ref2.id,
        jobId: widget.jobId,
        customerId: uid,
        artisanId: artisanId,
        rating: _rating,
        comment: _commentController.text.trim(),
        createdAt: DateTime.now(),
      );
      await ref2.set(review.toJson());

      // Artisan rating/totalRatings/trustScore aggregation is now handled
      // server-side by the onReviewCreated Cloud Function (functions/index.js),
      // triggered by the write above. This used to be attempted here as a
      // direct client transaction, but the writer (this customer) can never
      // be the artisan document's own owner, so firestore.rules rejected it
      // on every attempt — the review saved, but the artisan's rating never
      // moved, for any review, ever (see design/V2_IOS_SAFARI_RELIABILITY_REPORT.md
      // §9). Aggregation must not live on an untrusted client; removed here,
      // not weakened into "try anyway."

      // Stage 6 (HT-015): this notification is generated server-side from the
      // underlying document change (functions/index.js); clients can no longer
      // create notifications.

      if (mounted) context.go('/home');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/artisan_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../providers/job_provider.dart';
import '../../providers/platform_config_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../widgets/web_content_wrapper.dart';

/// Route-level wrapper — takes only [artisanId] (a path parameter, safe on
/// direct navigation/refresh) and fetches the real artisan via the same
/// provider [ArtisanProfileScreen] uses, rather than an `extra:`-passed
/// object that would be null on a Flutter Web refresh (the exact P0-2
/// class of bug this deliberately avoids).
class SecureBookingRoute extends ConsumerWidget {
  final String artisanId;
  const SecureBookingRoute({super.key, required this.artisanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artisanAsync = ref.watch(artisanProfileProvider(artisanId));
    return Scaffold(
      body: artisanAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load artisan: $e')),
        data: (artisan) => artisan == null
            ? const Center(child: Text('Artisan not found'))
            : SecureBookingScreen(artisan: artisan),
      ),
    );
  }
}

/// "Secure Booking" — a direct-hire entry point for a specific, already-
/// chosen artisan (reached from [ArtisanProfileScreen] when no existing
/// [jobId] context exists). Per design/STITCH_BUILD_ORDER.md Group 7 and
/// the resolved product decision: this is an ADDITIVE alternate front door
/// onto the *existing* job lifecycle, not a parallel state machine. It
/// creates a completely normal [JobModel] via the same
/// [jobRequestNotifierProvider] every job goes through, then walks it
/// through the same real transitions ([EscrowNotifier.acceptArtisan] →
/// [EscrowNotifier.openChat] → optionally [EscrowNotifier.confirmAgreement])
/// that a customer would otherwise reach by browsing → matching → chatting
/// → negotiating — just pre-filled and submitted in one linear form instead
/// of spread across several screens and a back-and-forth conversation.
///
/// Critically, this does NOT lock escrow or move any money. Step 3 shows a
/// cost preview only — real payment stays exactly where it already was:
/// gated on `WorkflowGateService`/`JobService.canInitPayment`, reachable
/// only once BOTH the customer and the artisan have confirmed the
/// agreement. This screen only ever gets the customer's side confirmed
/// (`confirmAgreementAsCustomer`, via [EscrowNotifier.confirmAgreement]);
/// the artisan still has to accept for themselves, through the same
/// existing job-detail flow, before payment is ever possible.
class SecureBookingScreen extends ConsumerStatefulWidget {
  final ArtisanModel artisan;
  const SecureBookingScreen({super.key, required this.artisan});

  @override
  ConsumerState<SecureBookingScreen> createState() => _SecureBookingScreenState();
}

class _SecureBookingScreenState extends ConsumerState<SecureBookingScreen> {
  int _step = 0;
  final _titleFormKey = GlobalKey<FormState>();

  final _descriptionCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  String _urgency = 'asap';
  DateTime? _scheduledDate;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (picked != null) setState(() => _scheduledDate = picked);
  }

  double? get _proposedAmount => double.tryParse(_budgetCtrl.text.trim());

  Future<void> _submit() async {
    final customerId = ref.read(authStateChangesProvider).value?.uid;
    if (customerId == null) return;
    final config = ref.read(platformConfigProvider);
    if (_proposedAmount != null && !config.meetsMinimum(_proposedAmount)) {
      setState(() => _error =
          'The proposed budget must be at least ${config.minJobValueLabel} (the minimum job value for secure payment).');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // 1. Create a completely normal job — same path/fields as posting one
      // from scratch (service_request_screen.dart), just pre-filled here.
      final jobNotifier = ref.read(jobRequestNotifierProvider.notifier);
      await jobNotifier.submitRequest(
        customerId: customerId,
        category: widget.artisan.category ?? widget.artisan.skills,
        description: _descriptionCtrl.text.trim(),
        images: const [],
        budgetMin: _proposedAmount,
        budgetMax: _proposedAmount,
        urgency: _urgency,
        scheduledDate: _scheduledDate,
      );
      final jobId = ref.read(jobRequestNotifierProvider).createdJobId;
      final createError = ref.read(jobRequestNotifierProvider).error;
      if (jobId == null) {
        throw Exception(createError ?? 'Could not create the job.');
      }

      // 2. Select this specific artisan — the exact same real transition
      // (requested -> matched) the existing "Hire This Artisan" flow uses.
      final escrow = ref.read(escrowNotifierProvider.notifier);
      await escrow.acceptArtisan(jobId, widget.artisan.uid);
      if (ref.read(escrowNotifierProvider).hasError) {
        throw Exception('Could not select this artisan for the job.');
      }

      // Stage 5 (policy D7): a direct booking is a REQUEST. The flow stops
      // here — the artisan must accept it (within the server-configured
      // window, default 24 h) before chat, agreement or payment are
      // possible; a decline or no answer reopens the job. Previously this
      // screen opened chat and confirmed the customer's side of the
      // agreement immediately, with no consent from the artisan. The
      // proposed budget is kept on the job (budgetMin/budgetMax) as the
      // opening position for the agreement.

      if (!mounted) return;
      context.go('/job/$jobId');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not send the booking request: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Secure Booking'),
      ),
      body: WebContentWrapper(
        maxWidth: 560,
        child: Column(
          children: [
            _StepHeader(step: _step),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: switch (_step) {
                  0 => _detailsStep(),
                  1 => _scheduleStep(),
                  _ => _reviewStep(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailsStep() => Form(
        key: _titleFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _artisanChip(),
            const SizedBox(height: 24),
            Text('Task Details',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Inter', color: context.colors.textPrimary)),
            const SizedBox(height: 12),
            _fieldCard(
              child: TextFormField(
                controller: _descriptionCtrl,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Describe the issue in detail...',
                  border: InputBorder.none,
                ),
                validator: (v) => (v == null || v.trim().length < 10) ? 'Please describe the work needed' : null,
              ),
            ),
            const SizedBox(height: 12),
            _fieldCard(
              child: TextFormField(
                controller: _budgetCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Your proposed budget (optional)',
                  hintText: 'e.g. 15000',
                  helperText: 'Minimum job value: ${ref.watch(platformConfigProvider).minJobValueLabel}',
                  prefixText: '₦ ',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 28),
            CommitButton(
              label: 'Continue',
              icon: Icons.arrow_forward_rounded,
              onPressed: () {
                if (_titleFormKey.currentState!.validate()) {
                  setState(() => _step = 1);
                }
              },
            ),
          ],
        ),
      );

  Widget _scheduleStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Schedule Preferences',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Inter', color: context.colors.textPrimary)),
          const SizedBox(height: 12),
          _fieldCard(
            child: Column(
              children: [
                RadioListTile<String>(
                  value: 'asap',
                  groupValue: _urgency,
                  onChanged: (v) => setState(() {
                    _urgency = v!;
                    _scheduledDate = null;
                  }),
                  title: const Text('As soon as possible'),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  value: 'scheduled',
                  groupValue: _urgency,
                  onChanged: (v) async {
                    setState(() => _urgency = v!);
                    await _pickDate();
                  },
                  title: Text(_scheduledDate == null
                      ? 'Pick a specific date'
                      : DateFormat('EEEE, d MMMM yyyy').format(_scheduledDate!)),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _step = 0),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CommitButton(
                  label: 'Continue',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () {
                    if (_urgency == 'scheduled' && _scheduledDate == null) {
                      setState(() => _error = 'Pick a date, or choose "As soon as possible".');
                      return;
                    }
                    setState(() {
                      _error = null;
                      _step = 2;
                    });
                  },
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: context.colors.error, fontFamily: 'Inter')),
          ],
        ],
      );

  Widget _reviewStep() {
    final amount = _proposedAmount;
    final fee = (amount ?? 0) * 0.05;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Deliberately NOT an "Escrow Protection Active" claim — no money
        // moves at this step. This is a request, not a payment.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.accentSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.accent.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: context.colors.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This sends a booking request to ${widget.artisan.displayName}. '
                  'Nothing is charged yet — you\'ll pay into escrow once they accept.',
                  style: TextStyle(fontSize: 13, height: 1.4, color: context.colors.accent, fontFamily: 'Inter'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Summary',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Inter', color: context.colors.textPrimary)),
        const SizedBox(height: 12),
        _fieldCard(
          child: Column(
            children: [
              _summaryRow('Artisan', widget.artisan.displayName),
              _summaryRow('Task', _descriptionCtrl.text.trim()),
              _summaryRow(
                'Schedule',
                _urgency == 'asap'
                    ? 'As soon as possible'
                    : (_scheduledDate != null ? DateFormat('EEE, d MMM yyyy').format(_scheduledDate!) : '—'),
              ),
            ],
          ),
        ),
        if (amount != null && amount > 0) ...[
          const SizedBox(height: 16),
          Text('Estimated Cost (once accepted)',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Inter', color: context.colors.textPrimary)),
          const SizedBox(height: 12),
          _fieldCard(
            child: Column(
              children: [
                _summaryRow('Your proposed amount', '₦${amount.toStringAsFixed(0)}'),
                _summaryRow('Platform fee (5%)', '₦${fee.toStringAsFixed(0)}'),
                const Divider(height: 20),
                _summaryRow('Total, once accepted', '₦${(amount + fee).toStringAsFixed(0)}', bold: true),
              ],
            ),
          ),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : () => setState(() => _step = 1),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: CommitButton(
                label: 'Send Booking Request',
                icon: Icons.send_rounded,
                loading: _submitting,
                onPressed: _submit,
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: context.colors.error, fontFamily: 'Inter')),
        ],
      ],
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: context.colors.textSecondary, fontFamily: 'Inter')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: context.colors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
        ),
      );

  Widget _artisanChip() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: context.colors.primarySurface,
              backgroundImage:
                  widget.artisan.profileImageUrl != null ? NetworkImage(widget.artisan.profileImageUrl!) : null,
              child: widget.artisan.profileImageUrl == null
                  ? Text(widget.artisan.displayName.isNotEmpty ? widget.artisan.displayName[0].toUpperCase() : '?')
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.artisan.displayName,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontFamily: 'Inter', color: context.colors.textPrimary)),
                  Text(widget.artisan.category ?? widget.artisan.skills,
                      style: TextStyle(fontSize: 12, color: context.colors.textSecondary, fontFamily: 'Inter')),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _fieldCard({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: context.colors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}

class _StepHeader extends StatelessWidget {
  final int step;
  const _StepHeader({required this.step});

  static const _labels = ['Details', 'Schedule', 'Review'];

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: List.generate(_labels.length, (i) {
            final active = i <= step;
            return Expanded(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: active ? context.colors.ink : context.colors.surfaceVariant,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? context.colors.onInk : context.colors.textTertiary,
                      ),
                    ),
                  ),
                  if (i < _labels.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i < step ? context.colors.ink : context.colors.surfaceVariant,
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      );
}

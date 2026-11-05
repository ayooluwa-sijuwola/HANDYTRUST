import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/job_model.dart';
import '../../../models/quote_model.dart';
import '../../../providers/platform_config_provider.dart';
import '../../../providers/quote_provider.dart';
import '../../components/ht_components.dart';
import '../../components/ht_format.dart';
import '../../components/ht_kit.dart';
import '../../theme/ht_theme.dart';
import '../artisan_shell.dart';
import '../components/pro_components.dart';
import 'find_work_screen.dart';
import 'work_ui.dart';

/// Quote composer (OV-14): submit or edit a quote, or withdraw it. Same
/// validation and QuoteService calls as the previous quote sheet.
class QuoteComposerScreen extends ConsumerStatefulWidget {
  const QuoteComposerScreen({super.key, required this.job, required this.artisanId, this.existing});
  final JobModel job;
  final String artisanId;
  final QuoteModel? existing;

  @override
  ConsumerState<QuoteComposerScreen> createState() => _QuoteComposerScreenState();
}

class _QuoteComposerScreenState extends ConsumerState<QuoteComposerScreen> {
  final _labour = TextEditingController();
  final _materials = TextEditingController();
  final _notes = TextEditingController();
  int _days = 1;
  bool _submitting = false;
  bool _withdrawing = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final q = widget.existing;
    if (q != null) {
      _labour.text = q.laborCost.toStringAsFixed(0);
      if (q.materialsCost > 0) _materials.text = q.materialsCost.toStringAsFixed(0);
      _days = q.durationDays < 1 ? 1 : q.durationDays;
      _notes.text = q.notes ?? '';
    }
  }

  @override
  void dispose() {
    _labour.dispose();
    _materials.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _labourValue => double.tryParse(_labour.text.trim()) ?? 0;
  double get _materialsValue => double.tryParse(_materials.text.trim()) ?? 0;

  Future<void> _submit() async {
    final labour = double.tryParse(_labour.text.trim());
    if (labour == null || labour <= 0) {
      htSnack(context, 'Enter a valid labour cost.', error: true);
      return;
    }
    final materials = _materialsValue;
    // Policy D1 (also enforced by firestore.rules on the quote write).
    final cfg = ref.read(platformConfigProvider);
    if (!cfg.meetsMinimum(labour + materials)) {
      htSnack(context, 'Quotes must total at least ${cfg.minJobValueLabel} (the minimum job value for secure payment).', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(quoteServiceProvider).submitQuote(
            jobId: widget.job.id,
            artisanId: widget.artisanId,
            laborCost: labour,
            materialsCost: materials,
            durationDays: _days,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => _QuoteSent(total: labour + materials, days: _days, edited: _editing)));
    } catch (e) {
      if (mounted) htSnack(context, _friendly(e), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _friendly(Object e) {
    final m = e.toString();
    if (m.contains('permission-denied') || m.contains('PERMISSION_DENIED')) {
      return "You're not eligible to quote on this job right now — your profile may need admin approval or identity verification first.";
    }
    if (m.contains('network')) return 'No internet connection. Please check your network and try again.';
    return 'Could not submit quote. Please try again.';
  }

  Future<void> _withdraw() async {
    final ok = await htConfirm(context, title: 'Withdraw this quote?', message: 'The customer will no longer see it. You can quote again while the job is open.', confirmLabel: 'Withdraw quote');
    if (!ok || !mounted) return;
    setState(() => _withdrawing = true);
    try {
      await ref.read(quoteServiceProvider).withdrawQuote(jobId: widget.job.id, artisanId: widget.artisanId);
      if (!mounted) return;
      htSnack(context, 'Quote withdrawn.');
      Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) htSnack(context, 'Could not withdraw the quote. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final cfg = ref.watch(platformConfigProvider);
    final j = widget.job;
    final total = _labourValue + _materialsValue;
    Widget money(String label, TextEditingController c, {String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14)), if (hint != null) Text(hint, style: HtType.small(p.textMuted))])),
            SizedBox(
              width: 160,
              child: TextField(
                controller: c,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                style: HtType.bodyStrong(p.textPrimary),
                decoration: htInputDecoration(context, hint: '0').copyWith(prefixText: '₦ ', contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
              ),
            ),
          ]),
        );
    return ArtisanPage(
      title: _editing ? 'Edit quote' : 'New quote',
      sub: '${workTitle(j)} · ${j.areaLabel ?? j.category}',
      bottomBar: ProActionBar(
        label: total > 0 ? '${_editing ? 'Update' : 'Send'} quote · ${HtFormat.naira(total)}' : (_editing ? 'Update quote' : 'Send quote'),
        loading: _submitting,
        onPressed: _submitting || _withdrawing ? null : _submit,
      ),
      children: [
        HtCard(
          radius: HtRadius.inner,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('THE JOB', style: HtType.caps(p.textMuted)),
            const SizedBox(height: 6),
            Text(j.description, style: HtType.body(p.textPrimary).copyWith(fontSize: 13.5)),
            if (j.imageUrls.isNotEmpty) ...[const SizedBox(height: 10), HtPhotoGrid(urls: j.imageUrls.take(3).toList(), tileHeight: 70)],
            const SizedBox(height: 6),
            Text('Budget ${budgetLabel(j)}${j.urgency == 'asap' ? ' · Urgent' : ''}', style: HtType.smallStrong(p.textSecondary)),
          ]),
        ),
        const ProSection('Your price'),
        money('Labour / service', _labour),
        money('Materials', _materials, hint: 'Optional'),
        Row(children: [
          Expanded(child: Text('Estimated duration', style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14))),
          Container(
            decoration: BoxDecoration(color: p.input, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.isDark ? Colors.transparent : p.border)),
            child: Row(children: [
              IconButton(tooltip: 'Fewer days', onPressed: _days > 1 ? () => setState(() => _days--) : null, icon: Icon(Icons.remove_rounded, color: p.textSecondary)),
              Text('$_days ${_days == 1 ? 'day' : 'days'}', style: HtType.bodyStrong(p.textPrimary)),
              IconButton(tooltip: 'More days', onPressed: _days < 365 ? () => setState(() => _days++) : null, icon: Icon(Icons.add_rounded, color: proAccent(p))),
            ]),
          ),
        ]),
        HtTextField(label: 'Notes for the customer (optional)', controller: _notes, hint: 'e.g. parts included, when you can start', lines: 2, maxLength: 500),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.isDark ? p.backgroundDeep : p.accentSoft, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border.all(color: p.border)),
          child: Column(children: [
            htKv(context, 'Quote total', HtFormat.naira(total), strong: true),
            Text(
              'You receive the full agreed price when the work is approved. The customer pays HandyTrust’s ${cfg.platformFeePercent.toStringAsFixed(cfg.platformFeePercent % 1 == 0 ? 0 : 1)}% platform fee on top. Minimum job value: ${cfg.minJobValueLabel}.',
              style: HtType.small(p.textSecondary),
            ),
          ]),
        ),
        if (_editing) ...[
          const SizedBox(height: 18),
          HtDangerButton(label: 'Withdraw quote', icon: Icons.undo_rounded, loading: _withdrawing, onPressed: _submitting ? null : _withdraw),
        ],
      ],
    );
  }
}

/// Success state after sending or updating a quote (OV-14).
class _QuoteSent extends StatelessWidget {
  const _QuoteSent({required this.total, required this.days, required this.edited});
  final double total;
  final int days;
  final bool edited;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return ArtisanPage(title: edited ? 'Quote updated' : 'Quote sent', children: [
      const SizedBox(height: 70),
      Center(child: Container(width: 96, height: 96, decoration: BoxDecoration(color: p.successSoft, shape: BoxShape.circle), child: Icon(Icons.send_rounded, size: 42, color: p.success))),
      const SizedBox(height: 22),
      Text(edited ? 'Your quote is updated' : 'Your quote is with the customer', textAlign: TextAlign.center, style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 23)),
      const SizedBox(height: 8),
      Text('${HtFormat.naira(total)} · $days ${days == 1 ? 'day' : 'days'}. You’ll get a notification if it’s accepted, and you can edit or withdraw it until then.',
          textAlign: TextAlign.center, style: HtType.body(p.textSecondary)),
      const SizedBox(height: 26),
      HtPrimaryButton(label: 'Back to Find Work', onPressed: () => Navigator.of(context).maybePop()),
    ]);
  }
}

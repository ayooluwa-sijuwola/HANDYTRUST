import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/artisan_profile_service.dart';
import '../../../providers/auth_provider.dart';
import '../../components/ht_components.dart';
import '../../components/ht_kit.dart';
import '../../theme/ht_theme.dart';
import '../artisan_shell.dart';
import '../components/pro_components.dart';

/// AR-07 Payout account (`/bank-details`): bank, 10-digit NUBAN, account
/// name, stored in `artisan_private/{uid}` through ArtisanProfileService.
class PayoutAccountScreen extends ConsumerStatefulWidget {
  const PayoutAccountScreen({super.key});
  @override
  ConsumerState<PayoutAccountScreen> createState() => _PayoutAccountScreenState();
}

class _PayoutAccountScreenState extends ConsumerState<PayoutAccountScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _number = TextEditingController();
  String? _bank;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = ref.read(currentUserProvider).asData?.value?.uid;
    if (uid != null) {
      try {
        final d = await ref.read(artisanProfileServiceProvider).loadBankDetails(uid);
        if (!mounted) return;
        _bank = d.bankName;
        _name.text = d.accountName;
        _number.text = d.accountNumber;
      } catch (_) {
        // Load failed: the form starts empty, as before.
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final uid = ref.read(currentUserProvider).asData?.value?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(artisanProfileServiceProvider).saveBankDetails(uid, bankName: _bank!, accountName: _name.text, accountNumber: _number.text);
      if (!mounted) return;
      htSnack(context, 'Bank details saved.');
      if (context.canPop()) context.pop();
    } catch (_) {
      if (mounted) htSnack(context, 'Could not save your bank details. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    if (!_loaded) return const ArtisanPage(title: 'Payout account', children: [SizedBox(height: 80), HtLoadingView(label: 'Loading…')]);
    return ArtisanPage(
      title: 'Payout account',
      bottomBar: ProActionBar(label: 'Save bank details', loading: _saving, onPressed: _saving ? null : _save),
      children: [
        Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const HtInfoBanner(icon: Icons.lock_outline_rounded, tone: HtTone.neutral, text: 'Only you and HandyTrust administrators can see these details.'),
            const HtFieldLabel('Bank'),
            DropdownButtonFormField<String>(
              initialValue: _bank,
              isExpanded: true,
              decoration: htInputDecoration(context, hint: 'Select your bank'),
              dropdownColor: p.surface,
              style: HtType.body(p.textPrimary),
              items: [for (final b in ArtisanProfileService.nigerianBanks) DropdownMenuItem(value: b, child: Text(b))],
              onChanged: (v) => setState(() => _bank = v),
              validator: (v) => v == null ? 'Please select your bank' : null,
            ),
            const HtFieldLabel('Account number'),
            TextFormField(
              controller: _number,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
              style: HtType.body(p.textPrimary),
              decoration: htInputDecoration(context, hint: '10-digit NUBAN number'),
              validator: ArtisanProfileService.validateAccountNumber,
            ),
            HtTextField(
              label: 'Account name',
              controller: _name,
              hint: 'Name exactly as it appears on your account',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the account name' : null,
            ),
            const SizedBox(height: 14),
            const HtInfoBanner(icon: Icons.info_outline_rounded, tone: HtTone.neutral, text: 'Released payments are sent to this account.'),
          ]),
        ),
      ],
    );
  }
}

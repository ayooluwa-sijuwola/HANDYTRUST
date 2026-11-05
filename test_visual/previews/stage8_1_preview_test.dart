// Stage 8.1 rendered PREVIEWS for design approval
// (design/STAGE8_1_PREVIEW_REVIEW.md). Renders every proposed artisan,
// admin, authentication and remaining customer screen in light and dark
// with the bundled fonts, and writes PNGs to test_visual/previews/goldens/.
//   flutter test test_visual/previews --update-goldens   (render)
// All content is SAMPLE DATA; nothing here touches lib/ or any backend.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'admin_previews.dart';
import 'artisan_previews.dart';
import 'extra_previews.dart';
import 'shared_previews.dart';

Future<void> _loadFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final f in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(f['asset'] as String).then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }
}

class _Preview {
  const _Preview(this.name, this.width, this.height, this.builder, {this.phone = true});
  final String name;
  final double width;
  final double height;
  final Widget Function() builder;
  final bool phone;
}

final _previews = <_Preview>[
  // Artisan — REVISED "HandyTrust Pro" (purpose-built; replaces v1 artisan previews)
  _Preview('ar01_home', 390, 1520, proHome),
  _Preview('ar01n_home_new_artisan', 390, 1020, proHomeNew),
  _Preview('ar02_find_work', 390, 1000, proFindWork),
  _Preview('ar02q_my_quotes', 390, 920, proMyQuotes),
  _Preview('ar02b_quote_composer', 390, 1180, proQuoteComposer),
  _Preview('ar02s_quote_sent', 390, 780, proQuoteSent),
  _Preview('ar03r_booking_request', 390, 1020, proBookingRequest),
  _Preview('ar03_my_jobs', 390, 1180, proMyJobs),
  _Preview('ar03t_my_jobs_tablet', 1024, 740, proJobsBoardTablet, phone: false),
  _Preview('ar04_work_order', 390, 1120, proWorkspace),
  _Preview('ar04a_agreement', 390, 1150, proAgreement),
  _Preview('ar04s_schedule', 390, 1020, proSchedule),
  _Preview('ar05_submit_work', 390, 1040, proSubmitWork),
  _Preview('ar05r_in_review', 390, 1040, proInReview),
  _Preview('ar06_rework', 390, 860, proRework),
  _Preview('ar07_dispute', 390, 1120, proDispute),
  _Preview('ar08_earnings', 390, 1280, proEarnings),
  _Preview('ar08p_payout_account', 390, 780, proPayoutAccount),
  _Preview('ar09_profile', 390, 1400, proProfile),
  _Preview('ar09v_verification', 390, 900, proVerification),
  _Preview('ar09b_business_profile', 390, 900, proBusiness),
  _Preview('ar10_portfolio', 390, 900, proPortfolio),
  _Preview('ar11_notifications', 390, 900, proNotifications),
  _Preview('ar12_messages', 390, 780, proMessages),
  _Preview('ar12c_chat', 390, 844, proChat),
  _Preview('ar13_loading', 390, 844, proLoading),
  _Preview('ar13e_error', 390, 780, proError),
  // Admin (AD-*)
  _Preview('ad01_dashboard_desktop', 1440, 1420, adDashboard, phone: false),
  _Preview('ad01_dashboard_mobile', 390, 1290, adDashboard),
  _Preview('ad02_users', 1440, 900, adUsers, phone: false),
  _Preview('ad04_verifications', 1440, 820, adVerifications, phone: false),
  _Preview('ad05_jobs', 1440, 900, adJobs, phone: false),
  _Preview('ad06_disputes_settlement', 1440, 820, adDisputes, phone: false),
  _Preview('ad13_finance', 1440, 860, adFinance, phone: false),
  _Preview('ad13b_payout_freeze', 1440, 860, () => adFinance(freezeDialog: true), phone: false),
  _Preview('ad10_audit_logs', 1440, 840, adAuditLogs, phone: false),
  _Preview('ad12_settings', 1440, 840, adSettings, phone: false),
  // Authentication (AU-*)
  _Preview('au00_splash', 390, 844, authSplash),
  _Preview('au00b_startup_error', 390, 760, authStartupError),
  _Preview('au01_login', 390, 844, authLogin),
  _Preview('au01b_login_error', 390, 900, () => authLogin(error: 'Email or password is incorrect.')),
  _Preview('au01c_login_loading', 390, 844, () => authLogin(loading: true)),
  _Preview('au02_register', 390, 1000, authRegister),
  _Preview('au02b_register_errors', 390, 1100, authRegisterErrors),
  _Preview('au03_forgot_password', 390, 760, authForgotPassword),
  _Preview('au03b_reset_link_sent', 390, 780, authResetSent),
  _Preview('au04_verify_email', 390, 760, authVerifyEmail),
  _Preview('au05_role_select', 390, 760, authRoleSelect),
  _Preview('au06_artisan_registration', 390, 900, authArtisanRegistration),
  _Preview('au07_suspended', 390, 760, authSuspended),
  // Remaining customer screens (CU-*)
  _Preview('cu01_settings', 390, 1080, cuSettings),
  _Preview('cu02_support', 390, 900, cuSupport),
  _Preview('cu03_dispute', 390, 960, cuDispute),
  _Preview('cu04_review', 390, 900, cuReview),
  _Preview('cu05_secure_booking', 390, 1020, cuSecureBooking),
  _Preview('cu06_matched_artisans', 390, 860, cuMatchedArtisans),
  _Preview('cu07_favorites', 390, 600, cuFavorites),
  _Preview('cu08_payment_result', 390, 844, cuPaymentResult),
  _Preview('cu09_about', 390, 640, cuAbout),
  // Complete-audit batch 2: system, nested screens, dialogs and sheets
  _Preview('sy01_not_found', 390, 760, syNotFound),
  _Preview('sy02_cannot_open_directly', 390, 760, syCannotOpen),
  _Preview('cu10_payment_checkout', 390, 844, cuPaymentCheckout),
  _Preview('cu08b_payment_not_completed', 390, 820, cuPaymentNotCompleted),
  _Preview('cu08c_payment_verifying', 390, 760, cuPaymentVerifying),
  _Preview('cu11_transaction_detail', 390, 844, cuTransactionDetail),
  _Preview('cu12_job_detail_customer_quotes', 390, 1100, cuJobDetailQuotes),
  _Preview('sh01_portfolio_viewer', 390, 844, shPortfolioViewer),
  _Preview('ar10e_portfolio_project', 390, 844, arPortfolioProject),
  _Preview('ar01b_trust_score_sheet', 390, 1000, arTrustScoreSheet),
  _Preview('dl01_edit_name', 390, 844, dlEditName),
  _Preview('dl02_change_email', 390, 844, dlChangeEmail),
  _Preview('dl03_change_password', 390, 844, dlChangePassword),
  _Preview('dl04_request_deletion', 390, 844, dlRequestDeletion),
  _Preview('dl05_switch_mode', 390, 844, dlSwitchMode),
  _Preview('dl06_cancel_job', 390, 844, dlCancelJob),
  _Preview('dl07_request_changes', 390, 844, dlRequestChanges),
  _Preview('dl08_date_picker', 390, 844, dlDatePicker),
  _Preview('ad03_artisans_pending', 1440, 860, adArtisansPending, phone: false),
  _Preview('ad07_reviews', 1440, 840, adReviews, phone: false),
  _Preview('ad08_support', 1440, 860, adSupport, phone: false),
  _Preview('ad09_deletions', 1440, 840, adDeletions, phone: false),
  _Preview('ad11_analytics', 1440, 900, adAnalytics, phone: false),
  _Preview('ad14_search', 1440, 860, adSearch, phone: false),
  _Preview('ad15_notifications', 1440, 860, adNotifications, phone: false),
  _Preview('ad16_delete_user_dialog', 1440, 900, adReasonDialog, phone: false),
];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  for (final v in _previews) {
    for (final dark in [false, true]) {
      final name = '${v.name}_${dark ? 'dark' : 'light'}';
      testWidgets(name, (tester) async {
        final dpr = v.phone ? 1.5 : 1.0;
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = Size(v.width * dpr, v.height * dpr);
        final pad = v.phone ? FakeViewPadding(top: 47 * dpr, bottom: 34 * dpr) : FakeViewPadding.zero;
        tester.view.padding = pad;
        tester.view.viewPadding = pad;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light, useMaterial3: true),
          home: v.builder(),
        ));
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
      });
    }
  }
}

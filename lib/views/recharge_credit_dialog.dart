import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_config.dart';
import '../services/credit_service.dart';
import '../services/language_service.dart';
import '../utils/app_theme.dart';

class RechargeCreditDialog extends StatefulWidget {
  const RechargeCreditDialog({super.key});

  static Future<T?> show<T>(BuildContext context) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const RechargeCreditDialog(),
    );
  }

  @override
  State<RechargeCreditDialog> createState() => _RechargeCreditDialogState();
}

class _RechargeCreditDialogState extends State<RechargeCreditDialog> {
  final _phoneController = TextEditingController();
  final _trxController = TextEditingController();
  double? _selectedAmount;
  int? _calculatedCredits;
  bool _isSubmitting = false;
  bool _isRefreshing = false;

  Future<void> _refreshStatus() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    final creditService = Provider.of<CreditService>(context, listen: false);
    await creditService.syncFromFirestore();
    if (mounted) {
      setState(() => _isRefreshing = false);
      final lang = LanguageService.of(context, listen: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          duration: const Duration(seconds: 2),
          content: Text(
            lang.isBangla
                ? '✅ ব্যালেন্স আপডেট হয়েছে: ${creditService.credits} ক্রেডিট'
                : '✅ Balance updated: ${creditService.credits} Credits',
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    final cs = Provider.of<CreditService>(context, listen: false);
    unawaited(cs.syncPackagesFromFirestore());
    _phoneController.text = cs.bkashNumber;
    if (cs.packages.isNotEmpty) {
      final defaultPkg = cs.packages.firstWhere((p) => p.popular, orElse: () => cs.packages.first);
      _selectedAmount = defaultPkg.amount;
      _calculatedCredits = defaultPkg.credits;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _trxController.dispose();
    super.dispose();
  }

  void _onPackageSelected(double amount, int credits) {
    setState(() {
      _selectedAmount = amount;
      _calculatedCredits = credits;
    });
  }

  Future<void> _handleSubmit() async {
    final phone = _phoneController.text.trim();
    final trx = _trxController.text.trim();
    final lang = LanguageService.of(context, listen: false);

    if (phone.isEmpty || trx.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            lang.isBangla
                ? 'বিকাশ নম্বর এবং ট্রানজেকশন আইডি (TrxID) লিখুন'
                : 'Please enter sender bKash number and TrxID',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final creditService = Provider.of<CreditService>(context, listen: false);
    final selAmount = _selectedAmount ?? (creditService.packages.isNotEmpty ? creditService.packages.first.amount : 50.0);
    final selCredits = _calculatedCredits ?? (creditService.packages.isNotEmpty ? creditService.packages.first.credits : 10);

    final success = await creditService.submitBkashRecharge(
      bkashSender: phone,
      trxId: trx,
      amount: selAmount,
      requestedCredits: selCredits,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      _trxController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFD97706),
          duration: const Duration(seconds: 4),
          content: Text(
            lang.isBangla
                ? '⏳ রিচার্জ জমা হয়েছে! স্ট্যাটাস: পেন্ডিং। অ্যাডমিন TrxID যাচাই করার পর ক্রেডিট যোগ হবে।'
                : '⏳ Recharge submitted! Status: Pending. Admin will verify TrxID and credits will be added shortly.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            lang.isBangla
                ? 'এই ট্রানজেকশন আইডি (TrxID) পূর্বে ব্যবহার করা হয়েছে।'
                : 'This TrxID has already been submitted.',
          ),
        ),
      );
    }
  }

  String _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  Future<void> _launchEmail(BuildContext context, String email) async {
    final phone = _phoneController.text.trim();
    final phoneLine = phone.isNotEmpty
        ? 'My Registered Phone Number: $phone'
        : 'My Registered Phone Number: ';
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: _encodeQueryParameters(<String, String>{
        'subject': 'Rail Pro Credit Recharge Request',
        'body':
            'Hello Admin,\n\nI would like to recharge credits for Rail Pro.\n$phoneLine\nDesired Credits: \n\nThank you.',
      }),
    );
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        await Clipboard.setData(ClipboardData(text: email));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF0284C7),
              content: Text(
                LanguageService.of(context, listen: false).isBangla
                    ? 'ইমেইল অ্যাপ খুলতে পারেনি। ইমেইল অ্যাড্রেস কপি করা হয়েছে: $email'
                    : 'Could not open mail app. Email copied to clipboard: $email',
              ),
            ),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        await Clipboard.setData(ClipboardData(text: email));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF0284C7),
              content: Text(
                LanguageService.of(context, listen: false).isBangla
                    ? 'ইমেইল অ্যাড্রেস কপি করা হয়েছে: $email'
                    : 'Email copied to clipboard: $email',
              ),
            ),
          );
        }
      }
    }
  }

  Widget _buildEmailRechargeCard(
    bool isDark,
    LanguageService lang,
    String contactEmail,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0284C7).withValues(alpha: 0.12),
            const Color(0xFF0369A1).withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF0284C7).withValues(alpha: 0.28),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.mark_email_read_rounded,
                      size: 14,
                      color: Color(0xFF0284C7),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      lang.isBangla
                          ? 'ইমেইল রিচার্জ রিকুয়েস্ট'
                          : 'Email Recharge Request',
                      style: const TextStyle(
                        color: Color(0xFF0284C7),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  lang.isBangla ? 'অ্যাডমিন অ্যাসাইন' : 'Admin Managed',
                  style: const TextStyle(
                    color: Color(0xFF059669),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            lang.isBangla
                ? 'ক্রেডিট রিচার্জ করতে ইমেইলে যোগাযোগ করুন'
                : 'Contact via Email to Recharge Credits',
            style: TextStyle(
              color: AppColors.textPrimary(isDark),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            lang.isBangla
                ? 'সরাসরি অনলাইন পেমেন্ট উইন্ডো আপাতত বন্ধ রয়েছে। ক্রেডিট যুক্ত করতে নিচের ইমেইলে যোগাযোগ করুন। আপনার নিবন্ধিত ফোন নম্বর ও ক্রেডিটের পরিমাণ জানালে অ্যাডমিন দ্রুত ক্রেডিট যুক্ত করে দেবে।'
                : 'Direct online recharge form is currently disabled. Please contact via email to top up your balance. Send your registered phone number and desired credit amount to have admin assign your credits.',
            style: TextStyle(
              color: AppColors.textSecondary(isDark),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.inputFill(isDark),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF0284C7).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.email_outlined,
                  size: 20,
                  color: Color(0xFF0284C7),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SelectableText(
                    contactEmail,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.copy, size: 14, color: Colors.white),
                  label: Text(
                    lang.isBangla ? 'কপি' : 'Copy',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: contactEmail));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF0284C7),
                        content: Text(
                          lang.isBangla
                              ? 'ইমেইল অ্যাড্রেস কপি করা হয়েছে'
                              : 'Email address copied to clipboard',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 1,
              ),
              icon: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
              label: Text(
                lang.isBangla
                    ? 'সরাসরি ইমেইল অ্যাপ খুলুন'
                    : 'Open Email App Directly',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              onPressed: () => _launchEmail(context, contactEmail),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lang.isBangla
                      ? '📌 ইমেইল পাঠানোর নিয়মাবলী:'
                      : '📌 Email Guidelines:',
                  style: TextStyle(
                    color: AppColors.textPrimary(isDark),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                _buildGuideBullet(
                  lang.isBangla
                      ? 'বিষয় (Subject): "Rail Pro Credit Recharge"'
                      : 'Subject: "Rail Pro Credit Recharge"',
                  isDark,
                ),
                _buildGuideBullet(
                  lang.isBangla
                      ? 'আপনার রেল সেবা অ্যাকাউন্টের ফোন নম্বর উল্লেখ করুন'
                      : 'Specify your registered mobile number',
                  isDark,
                ),
                _buildGuideBullet(
                  lang.isBangla
                      ? 'প্রয়োজনীয় ক্রেডিটের পরিমাণ উল্লেখ করুন'
                      : 'Specify desired credit amount',
                  isDark,
                ),
                _buildGuideBullet(
                  lang.isBangla
                      ? 'অ্যাডমিন যাচাই শেষে সরাসরি অ্যাকাউন্টে ক্রেডিট রিচার্জ করে দেবেন'
                      : 'Admin will promptly credit your balance upon request',
                  isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideBullet(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(
              color: Color(0xFF0284C7),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.textSecondary(isDark),
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = LanguageService.of(context);
    final creditService = Provider.of<CreditService>(context);

    return ListenableBuilder(
      listenable: AppConfig.instance,
      builder: (context, _) {
        final directRecharge = AppConfig.instance.directRechargeEnabled;
        final contactEmail = AppConfig.instance.rechargeContactEmail;

        return DraggableScrollableSheet(
          initialChildSize: 0.88,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.cardBg(isDark),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Sheet handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Title and balance
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: directRecharge
                                ? const Color(0xFFE2136E) // bKash Pink
                                : const Color(0xFF0284C7), // Sky Blue
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            directRecharge
                                ? Icons.account_balance_wallet
                                : Icons.mark_email_read_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lang.isBangla
                                  ? (directRecharge
                                      ? 'ক্রেডিট রিচার্জ (bKash)'
                                      : 'ক্রেডিট রিচার্জ (ইমেইল)')
                                  : (directRecharge
                                      ? 'Credit Recharge (bKash)'
                                      : 'Credit Recharge (Email)'),
                              style: TextStyle(
                                color: AppColors.textPrimary(isDark),
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${lang.isBangla ? "বর্তমান ব্যালেন্স:" : "Current Balance:"} ${creditService.credits} ${lang.isBangla ? "ক্রেডিট" : "Credits"}',
                              style: const TextStyle(
                                color: Color(0xFF059669),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Content
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        if (!directRecharge) ...[
                          _buildEmailRechargeCard(isDark, lang, contactEmail),
                        ] else ...[
                    // ── 1. bKash Payment Instruction Card ───────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFE2136E).withValues(alpha: 0.12),
                            const Color(0xFFE2136E).withValues(alpha: 0.04),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2136E).withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline, color: Color(0xFFE2136E), size: 20),
                              const SizedBox(width: 8),
                              Text(
                                lang.isBangla ? 'টাকা পাঠানোর নিয়ম:' : 'bKash Send Money Instruction:',
                                style: const TextStyle(
                                  color: Color(0xFFE2136E),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            lang.isBangla
                                ? '১. আপনার bKash অ্যাপ থেকে নিচে দেওয়া নম্বরে "Send Money" করুন:'
                                : '1. Send Money from your bKash app to this personal number:',
                            style: TextStyle(color: AppColors.textPrimary(isDark), fontSize: 13),
                          ),
                          const SizedBox(height: 8),

                          // bKash Number Box with Copy Button
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.inputFill(isDark),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2136E).withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  creditService.bkashNumber,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const Spacer(),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE2136E),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.copy, size: 14, color: Colors.white),
                                  label: Text(
                                    lang.isBangla ? 'কপি' : 'Copy',
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: creditService.bkashNumber));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: const Color(0xFFE2136E),
                                        content: Text(
                                          lang.isBangla ? 'bKash নম্বর কপি করা হয়েছে' : 'bKash number copied',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            lang.isBangla
                                ? '২. টাকা পাঠানোর পর এসএমএস থেকে Transaction ID (TrxID) সংগ্রহ করে নিচের ফর্মে জমা দিন।'
                                : '2. After sending, collect the TrxID from SMS and submit in the form below.',
                            style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── 2. Package Selector (from Database) ───────────────────
                    Text(
                      lang.isBangla ? 'প্যাকেজ নির্বাচন করুন:' : 'Select Package:',
                      style: TextStyle(
                        color: AppColors.textPrimary(isDark),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: creditService.packages.map((pkg) {
                        final isSelected = _selectedAmount == pkg.amount;
                        return InkWell(
                          onTap: () => _onPackageSelected(pkg.amount, pkg.credits),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 96),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF059669)
                                  : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF047857) : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (pkg.popular) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    margin: const EdgeInsets.only(bottom: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD97706),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('POPULAR', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                                Text(
                                  '${pkg.credits} ক্রেডিট',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isSelected ? Colors.white : AppColors.textPrimary(isDark),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '৳${pkg.amount.toInt()}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected ? Colors.white70 : AppColors.textSecondary(isDark),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    // ── 3. Sender Phone and TrxID Form ───────────────────────
                    Text(
                      lang.isBangla ? 'আপনার প্রেরক বিকাশ নম্বর:' : 'Your Sender bKash Number:',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: '018XXXXXXXX',
                        filled: true,
                        fillColor: AppColors.inputFill(isDark),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.phone_android, size: 20),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Text(
                      lang.isBangla ? 'Transaction ID (TrxID):' : 'Transaction ID (TrxID):',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _trxController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'e.g. 9J47AB12',
                        filled: true,
                        fillColor: AppColors.inputFill(isDark),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.receipt_long, size: 20),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE2136E),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                        onPressed: _isSubmitting ? null : _handleSubmit,
                        child: _isSubmitting
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                lang.isBangla
                                    ? 'রিচার্জ নিশ্চিত করুন ($_calculatedCredits ক্রেডিট)'
                                    : 'Confirm Recharge ($_calculatedCredits Credits)',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                    ),
                  ],

                    // Notice with quick refresh button when user has pending recharge
                    if (creditService.transactions.any((tx) => tx.status.toLowerCase() == 'pending')) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                lang.isBangla
                                    ? 'আপনার রিচার্জটি অপেক্ষমাণ (Pending)। অ্যাডমিন অনুমোদন দিলে ক্রেডিট আপডেট হবে।'
                                    : 'Recharge is Pending verification by admin.',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFD97706)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _isRefreshing ? null : _refreshStatus,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD97706),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _isRefreshing
                                        ? const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                                          )
                                        : const Icon(Icons.refresh_rounded, size: 14, color: Colors.white),
                                    const SizedBox(width: 4),
                                    Text(
                                      lang.isBangla ? 'রিফ্রেশ' : 'Refresh',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // ── 4. Transaction History Table ────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.history_rounded, size: 20, color: Color(0xFF059669)),
                            const SizedBox(width: 8),
                            Text(
                              lang.isBangla ? 'রিচার্জের তালিকা' : 'Recharge History Table',
                              style: TextStyle(
                                color: AppColors.textPrimary(isDark),
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        // Refresh button in table header
                        InkWell(
                          onTap: _isRefreshing ? null : _refreshStatus,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF059669).withValues(alpha: 0.3),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _isRefreshing
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF059669)),
                                      )
                                    : const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFF059669)),
                                const SizedBox(width: 4),
                                Text(
                                  lang.isBangla ? 'স্ট্যাটাস রিফ্রেশ' : 'Refresh Status',
                                  style: const TextStyle(
                                    color: Color(0xFF059669),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (creditService.transactions.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.inputFill(isDark),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.inputBorder(isDark)),
                        ),
                        child: Center(
                          child: Text(
                            lang.isBangla
                                ? 'কোনো রিচার্জের ইতিহাস পাওয়া যায়নি।'
                                : 'No recharge transactions recorded yet.',
                            style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 12),
                          ),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.cardBorder(isDark)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(
                                isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              ),
                              columns: [
                                DataColumn(label: Text(lang.isBangla ? 'তারিখ' : 'Date')),
                                DataColumn(label: Text(lang.isBangla ? 'TrxID' : 'TrxID')),
                                DataColumn(label: Text(lang.isBangla ? 'বিকাশ নম্বর' : 'bKash No')),
                                DataColumn(label: Text(lang.isBangla ? 'টাকা' : 'Amount')),
                                DataColumn(label: Text(lang.isBangla ? 'ক্রেডিট' : 'Credits')),
                                DataColumn(label: Text(lang.isBangla ? 'স্ট্যাটাস' : 'Status')),
                              ],
                              rows: creditService.transactions.map((tx) {
                                final dateStr = DateFormat('dd MMM, hh:mm a').format(tx.createdAt);
                                return DataRow(
                                  cells: [
                                    DataCell(Text(dateStr, style: const TextStyle(fontSize: 11))),
                                    DataCell(Text(tx.trxId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                    DataCell(Text(tx.bkashSender, style: const TextStyle(fontSize: 11))),
                                    DataCell(Text('৳${tx.amount.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                    DataCell(Text('+${tx.credits}', style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 12))),
                                    DataCell(
                                      Builder(builder: (context) {
                                        final isPending = tx.status.toLowerCase() == 'pending';
                                        final isApproved = tx.status.toLowerCase() == 'approved';
                                        final badgeBg = isApproved
                                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                            : (isPending
                                                ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                                : const Color(0xFFEF4444).withValues(alpha: 0.15));
                                        final badgeTextColor = isApproved
                                            ? const Color(0xFF059669)
                                            : (isPending
                                                ? const Color(0xFFD97706)
                                                : const Color(0xFFDC2626));
                                        final badgeText = isPending
                                            ? (lang.isBangla ? 'পেন্ডিং' : 'Pending')
                                            : (isApproved
                                                ? (lang.isBangla ? 'অনুমোদিত' : 'Approved')
                                                : (lang.isBangla ? 'বাতিল' : 'Rejected'));

                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: badgeBg,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            badgeText,
                                            style: TextStyle(
                                              color: badgeTextColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
      },
    );
  }
}

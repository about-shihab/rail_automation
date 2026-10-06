import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/auth_session.dart';
import '../services/booking_service.dart';
import '../services/credit_service.dart';
import '../services/firebase_user_service.dart';
import '../services/language_service.dart';
import '../services/monitor_service.dart';
import '../services/notification_service.dart';
import '../services/secure_store.dart';
import '../services/theme_service.dart';
import '../services/web_session_service.dart';
import '../widgets/train_navigation_bar.dart';
import '../utils/app_theme.dart';
import 'admin_screen.dart';
import 'monitor_dashboard_screen.dart';
import 'recharge_credit_dialog.dart';
import 'search_screen.dart';
import 'trips_screen.dart';
import 'webview_login_screen.dart';

/// Root screen with a bottom navigation bar: Search · Monitor · Alerts · More.
class AppShell extends StatefulWidget {
  final int initialTab;
  const AppShell({super.key, this.initialTab = 0});

  static const tabSearch = 0,
      tabMonitor = 1,
      tabAlerts = 2,
      tabTrips = 2,
      tabMore = 3;
  static final ValueNotifier<int> tab = ValueNotifier<int>(0);
  static bool _alive = false;

  /// Close any pushed pages and switch to [index].
  static void goTo(BuildContext context, int index) {
    if (_alive) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      tab.value = index;
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AppShell(initialTab: index)),
        (_) => false,
      );
    }
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    AppShell._alive = true;
    AppShell.tab.value = widget.initialTab;
  }

  @override
  void dispose() {
    AppShell._alive = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<MonitorService>();
    final lang = context.watch<LanguageService>();
    return ValueListenableBuilder<int>(
      valueListenable: AppShell.tab,
      builder: (context, index, _) => Scaffold(
        body: Column(
          children: [
            if (monitor.needsTurnstile)
              Material(
                color: const Color(0xFFDC2626),
                elevation: 4,
                child: InkWell(
                  onTap: () =>
                      context.read<MonitorService>().resolveTurnstile(),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.shield_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              lang.tr(
                                'Security check · Continue',
                                'নিরাপত্তা যাচাই · চালিয়ে যান',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: index,
                children: const [
                  SearchScreen(),
                  _MonitorTab(),
                  TripsScreen(),
                  ProfileTab(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: TrainNavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => AppShell.tab.value = i,
          destinations: [
            TrainDestination(label: lang.tr('Search', 'অনুসন্ধান')),
            TrainDestination(
              label: lang.tr('Tickets', 'টিকেট'),
              showBadge: monitor.isMonitoring,
              badgeColor: AppColors.primary,
            ),
            TrainDestination(
              label: lang.tr('Trips', 'ট্রিপস'),
              showBadge: monitor.needsTurnstile,
              badgeColor: AppColors.error,
            ),
            TrainDestination(label: lang.tr('Profile', 'প্রোফাইল')),
          ],
        ),
      ),
    );
  }
}

// ── Monitor tab: dashboard when a search exists, friendly empty state otherwise
class _MonitorTab extends StatelessWidget {
  const _MonitorTab();
  @override
  Widget build(BuildContext context) {
    final m = context.watch<MonitorService>();
    final lang = context.watch<LanguageService>();
    if (m.dateOfJourney.isNotEmpty) return const MonitorDashboardScreen();
    return _Empty(
      icon: Icons.radar_rounded,
      title: lang.tr('No active watch', 'কোনো সক্রিয় নজরদারি নেই'),
      body: lang.tr(
        'Search for a train and tap Watch to get notified when seats open up.',
        'ট্রেন অনুসন্ধান করুন এবং সিট খালি হলে নোটিফিকেশন পেতে নজরদারিতে রাখুন।',
      ),
      action: lang.tr('Search trains', 'ট্রেন অনুসন্ধান'),
      onAction: () => AppShell.tab.value = AppShell.tabSearch,
    );
  }
}

// ── Profile tab: user profile, credits, appearance, language, logout ────────
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  Future<void> _logout(BuildContext context) async {
    final lang = context.read<LanguageService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(
          Theme.of(context).brightness == Brightness.dark,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(lang.tr('Sign Out?', 'লগআউট করতে চান?')),
        content: Text(
          lang.tr(
            'Are you sure you want to sign out of your Railway account?',
            'আপনি কি নিশ্চিত যে আপনার বাংলাদেশ রেলওয়ে অ্যাকাউন্ট থেকে লগআউট করতে চান?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.tr('Cancel', 'বাতিল')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lang.tr('Sign Out', 'লগআউট')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await context.read<MonitorService>().clearSearch();
    try {
      await WebSessionService.clear();
    } catch (_) {}
    await FirebaseUserService().clearSession();
    await AuthSession.clear();
    await BookingService.clear();
    await SecureStore.delete('rail_action_token');
    await SecureStore.delete('rail_hold_seconds');
    await SecureStore.delete('rail_user');
    await NotificationService().clearAlerts();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const WebviewLoginScreen(clearSession: true),
        ),
        (_) => false,
      );
    }
  }

  void _showLanguageSheet(
    BuildContext context,
    LanguageService lang,
    bool isDark,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                lang.tr('Select Language', 'ভাষা নির্বাচন করুন'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.language_rounded,
                  color: AppColors.primary,
                ),
                title: const Text(
                  'English',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: !lang.isBangla
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.primary,
                      )
                    : null,
                onTap: () {
                  lang.setLanguage(AppLanguage.en);
                  Navigator.pop(ctx);
                },
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.translate_rounded,
                  color: AppColors.primary,
                ),
                title: const Text(
                  'বাংলা (Bangla)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: lang.isBangla
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.primary,
                      )
                    : null,
                onTap: () {
                  lang.setLanguage(AppLanguage.bn);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = context.watch<ThemeService>();
    final credit = context.watch<CreditService>();
    final lang = context.watch<LanguageService>();
    final fbUser = context.watch<FirebaseUserService>();
    final isAdmin = fbUser.isAdmin;
    final isBlocked = fbUser.isBlocked;
    final userPhone =
        FirebaseUserService().currentPhone ??
        (lang.isBangla ? 'রেলওয়ে ব্যবহারকারী' : 'Railway User');

    Widget tile(
      IconData icon,
      String title, {
      String? sub,
      Widget? trailing,
      VoidCallback? onTap,
    }) => ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: sub == null ? null : Text(sub),
      trailing:
          trailing ??
          (onTap != null ? const Icon(Icons.chevron_right_rounded) : null),
      onTap: onTap,
    );

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      appBar: AppBar(title: Text(lang.tr('Profile', 'প্রোফাইল')), elevation: 0),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (isBlocked) ...[
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.block_rounded,
                    color: AppColors.error,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lang.tr(
                            'Account Suspended',
                            'অ্যাকাউন্ট স্থগিত করা হয়েছে',
                          ),
                          style: const TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lang.tr(
                            'Your account has been suspended by an administrator. Please contact support.',
                            'আপনার অ্যাকাউন্টটি স্থগিত করা হয়েছে। সহায়তার জন্য প্রশাসকের সাথে যোগাযোগ করুন।',
                          ),
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          // ── Real User Profile Card ──
          AppCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  child: const Icon(
                    Icons.person_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userPhone,
                        style: TextStyle(
                          color: AppColors.textPrimary(isDark),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.success,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            lang.tr(
                              'Active Railway Session',
                              'সক্রিয় রেলওয়ে সেশন',
                            ),
                            style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Credits & Recharge Card ──
          AppCard(
            child: Column(
              children: [
                tile(
                  credit.credits <= 0
                      ? Icons.bolt_rounded
                      : Icons.account_balance_wallet_outlined,
                  credit.credits <= 0
                      ? lang.tr('Credits: 0', 'ক্রেডিট: ০')
                      : lang.tr('Credits', 'ক্রেডিট'),
                  sub: credit.credits <= 0
                      ? lang.tr(
                          'Recharge required to book tickets · Tap to Buy Credit',
                          'টিকেট কাটতে ক্রেডিট প্রয়োজন · রিচার্জ করতে ট্যাপ করুন',
                        )
                      : lang.tr(
                          '${credit.credits} available · Tap to recharge',
                          '${credit.credits} ক্রেডিট উপলব্ধ · রিচার্জ করতে ট্যাপ করুন',
                        ),
                  trailing: credit.credits <= 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF59E0B)),
                          ),
                          child: Text(
                            lang.tr('Buy Credit', 'ক্রেডিট কিনুন'),
                            style: const TextStyle(
                              color: Color(0xFFF59E0B),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : null,
                  onTap: () => RechargeCreditDialog.show(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── User Management (visible to admins only) ──
          if (isAdmin) ...[
            AppCard(
              child: tile(
                Icons.admin_panel_settings_rounded,
                lang.tr('User Management', 'ইউজার ম্যানেজমেন্ট'),
                sub: lang.tr(
                  'Approve transactions, credits, block & notify',
                  'লেনদেন অনুমোদন, ক্রেডিট নিয়ন্ত্রণ ও নোটিফিকেশন',
                ),
                trailing: const AdminPendingBadge(),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminScreen()),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Settings (Dark mode & Language only) ──
          AppCard(
            child: Column(
              children: [
                tile(
                  Icons.dark_mode_outlined,
                  lang.tr('Dark mode', 'ডার্ক মোড'),
                  trailing: Switch(
                    value: theme.isDarkMode,
                    onChanged: (_) => theme.toggleTheme(),
                  ),
                ),
                tile(
                  Icons.translate_rounded,
                  lang.tr('Language', 'ভাষা'),
                  sub: lang.isBangla ? 'বাংলা' : 'English',
                  onTap: () => _showLanguageSheet(context, lang, isDark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Developer Information (Expandable, Collapsed Initially) ──
          _ExpandableDeveloperCard(isDark: isDark, lang: lang),
          const SizedBox(height: 14),

          AppCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(lang.tr('Disclaimer', 'দায়মুক্তি')),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    lang.tr(
                      'Rail Pro is an independent automation and ticket assistant. It is not affiliated with Bangladesh Railway (BR) or Shohoz. Reservations and payments are handled by the official Railway portal.',
                      'রেল প্রো একটি স্বাধীন টিকেট সহায়ক। এটি বাংলাদেশ রেলওয়ে বা সহজের অনুমোদিত অ্যাপ নয়। বুকিং ও পেমেন্ট সরকারি রেলওয়ে পোর্টালে সম্পন্ন হয়।',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textMuted(isDark),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Sign Out Card ──
          AppCard(
            child: tile(
              Icons.logout_rounded,
              lang.tr('Sign Out', 'লগআউট'),
              sub: lang.tr(
                'Switch or disconnect Railway account',
                'রেলওয়ে অ্যাকাউন্ট পরিবর্তন বা সংযোগ বিচ্ছিন্ন করুন',
              ),
              onTap: () => _logout(context),
            ),
          ),
          const SizedBox(height: 20),

          // ── Version & Footer ──
          Center(
            child: Text(
              lang.tr(
                'Rail Pro v1.0.0 · Developed by Abdulla Al Mamun',
                'রেল প্রো v১.০.০ · প্রস্তুতকারক: আবদুল্লাহ আল মামুন',
              ),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted(isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandableDeveloperCard extends StatefulWidget {
  final bool isDark;
  final LanguageService lang;
  const _ExpandableDeveloperCard({required this.isDark, required this.lang});

  @override
  State<_ExpandableDeveloperCard> createState() =>
      _ExpandableDeveloperCardState();
}

class _ExpandableDeveloperCardState extends State<_ExpandableDeveloperCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.code_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lang.tr('Developer Information', 'ডেভেলপার তথ্য'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary(widget.isDark),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _expanded
                              ? lang.tr(
                                  'Tap to collapse',
                                  'সংক্ষেপ করতে ট্যাপ করুন',
                                )
                              : lang.tr(
                                  'Abdulla Al Mamun · Tap to expand',
                                  'আবদুল্লাহ আল মামুন · বিস্তারিত দেখতে ট্যাপ করুন',
                                ),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted(widget.isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted(widget.isDark),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.person_outline_rounded,
                color: AppColors.primary,
              ),
              title: const Text(
                'Abdulla Al Mamun',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                lang.tr(
                  'Lead Developer & Creator',
                  'প্রধান ডেভেলপার এবং নির্মাতা',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.email_outlined,
                color: AppColors.primary,
              ),
              title: const Text(
                'connect.abdulla@gmail.com',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                lang.tr(
                  'Tap to copy contact email',
                  'ইমেইল কপি করতে ট্যাপ করুন',
                ),
              ),
              trailing: const Icon(
                Icons.copy_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              onTap: () {
                Clipboard.setData(
                  const ClipboardData(text: 'connect.abdulla@gmail.com'),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          lang.tr(
                            'Email copied to clipboard',
                            'ইমেইল ক্লিপবোর্ডে কপি করা হয়েছে',
                          ),
                        ),
                      ],
                    ),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    backgroundColor: AppColors.primary,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title, body, action;
  final VoidCallback onAction;
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
  });
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primary.withValues(alpha: .12),
                child: Icon(icon, size: 38, color: AppColors.primary),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted(isDark)),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: action,
                icon: Icons.search_rounded,
                onPressed: onAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

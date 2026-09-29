import 'package:flutter/material.dart';
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
import '../widgets/turnstile_sheet.dart';
import '../utils/app_theme.dart';
import 'monitor_dashboard_screen.dart';
import 'recharge_credit_dialog.dart';
import 'search_screen.dart';
import 'trips_screen.dart';
import 'webview_login_screen.dart';

/// Root screen with a bottom navigation bar: Search · Monitor · Alerts · More.
class AppShell extends StatefulWidget {
  final int initialTab;
  const AppShell({super.key, this.initialTab = 0});

  static const tabSearch = 0, tabMonitor = 1, tabAlerts = 2, tabMore = 3;
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
                  onTap: () async {
                    final token = await TurnstileDialog.show(context);
                    if (token != null && token.isNotEmpty && context.mounted) {
                      context.read<MonitorService>().onTurnstileSolved(token);
                    }
                  },
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.shield_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Security Verification Required • Tap to solve & auto-book',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: IndexedStack(index: index, children: const [
                SearchScreen(),
                _MonitorTab(),
                TripsScreen(),
                _ProfileTab(),
              ]),
            ),
          ],
        ),
        bottomNavigationBar: TrainNavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => AppShell.tab.value = i,
          destinations: [
            const TrainDestination(
              label: 'Search',
            ),
            TrainDestination(
              label: 'Tickets',
              showBadge: monitor.isMonitoring,
              badgeColor: AppColors.primary,
            ),
            TrainDestination(
              label: 'Trips',
              showBadge: monitor.needsTurnstile,
              badgeColor: AppColors.error,
            ),
            const TrainDestination(
              label: 'Profile',
            ),
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
    if (m.dateOfJourney.isNotEmpty) return const MonitorDashboardScreen();
    return _Empty(
      icon: Icons.radar_rounded,
      title: 'No active watch',
      body: 'Search for a train and tap Watch to get notified when seats open up.',
      action: 'Search trains',
      onAction: () => AppShell.tab.value = AppShell.tabSearch,
    );
  }
}

// ── Profile tab: user profile, credits, appearance, language, logout ────────
class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(
          Theme.of(context).brightness == Brightness.dark,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out?'),
        content: const Text(
          'Are you sure you want to sign out of your Railway account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = context.watch<ThemeService>();
    final credit = context.watch<CreditService>();
    final lang = context.watch<LanguageService>();
    final userPhone = FirebaseUserService().currentPhone ?? 'Railway User';

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
      appBar: AppBar(title: const Text('Profile'), elevation: 0),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
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
                          const Text(
                            'Active Railway Session',
                            style: TextStyle(
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
                  credit.credits <= 0 ? 'Credits: 0' : 'Credits',
                  sub: credit.credits <= 0
                      ? 'Recharge required to book tickets · Tap to Buy Credit'
                      : '${credit.credits} available · Tap to recharge',
                  trailing: credit.credits <= 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF59E0B)),
                          ),
                          child: const Text(
                            'Buy Credit',
                            style: TextStyle(
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

          // ── Settings (Dark mode & Language only - NO mock data, NO test notification) ──
          AppCard(
            child: Column(
              children: [
                tile(
                  Icons.dark_mode_outlined,
                  'Dark mode',
                  trailing: Switch(
                    value: theme.isDarkMode,
                    onChanged: (_) => theme.toggleTheme(),
                  ),
                ),
                tile(
                  Icons.translate_rounded,
                  'Language',
                  sub: lang.isBangla ? 'বাংলা' : 'English',
                  onTap:
                      () => lang.setLanguage(
                        lang.isBangla ? AppLanguage.en : AppLanguage.bn,
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
              'Sign Out',
              sub: 'Switch or disconnect Railway account',
              onTap: () => _logout(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title, body, action;
  final VoidCallback onAction;
  const _Empty({required this.icon, required this.title, required this.body,
      required this.action, required this.onAction});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primary.withValues(alpha: .12),
                child: Icon(icon, size: 38, color: AppColors.primary)),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted(isDark))),
            const SizedBox(height: 24),
            PrimaryButton(label: action, icon: Icons.search_rounded, onPressed: onAction),
          ]),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/auth_session.dart';
import '../services/api_service.dart';
import '../services/monitor_service.dart';
import '../services/app_config.dart';
import '../services/theme_service.dart';
import '../services/language_service.dart';
import '../services/booking_service.dart';
import '../services/secure_store.dart';
import '../services/notification_service.dart';
import '../services/web_session_service.dart';
import '../services/firebase_user_service.dart';
import '../services/credit_service.dart';
import '../utils/app_theme.dart';
import '../widgets/fancy_train_loader.dart';
import 'recharge_credit_dialog.dart';
import 'webview_login_screen.dart';
import 'train_selection_screen.dart';
import 'monitor_dashboard_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with TickerProviderStateMixin {
  List<String> get _stations => AppConfig.instance.strings('stations');
  List<String> get _classes => AppConfig.instance.strings('seat_classes');

  String _fromCity = 'Dhaka';
  String _toCity = 'Chattogram';
  DateTime _date = DateTime.now().add(const Duration(days: 3));
  String _selectedClass = 'ALL';
  AuthSession? _auth;
  bool _loading = false;

  late final AnimationController _heroCtrl = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 800),
  )..forward();

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    super.dispose();
  }

  Future<void> _initSession() async {
    final session = await AuthSession.load();
    if (!mounted) return;
    if (session == null || !session.isValid) {
      if (mounted) {
        Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const WebviewLoginScreen(clearSession: true)));
      }
      return;
    }
    setState(() => _auth = session);
    unawaited(FirebaseUserService().syncUserOnLogin(session));
    // If monitor active, jump straight to dashboard
    final monitor = context.read<MonitorService>();
    if (monitor.dateOfJourney.isNotEmpty && mounted) {
      Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const MonitorDashboardScreen()));
    }
  }

  Future<void> _logout() async {
    await context.read<MonitorService>().clearSearch();
    try { await WebSessionService.clear(); } catch (_) {}
    await FirebaseUserService().clearSession();
    await AuthSession.clear();
    await BookingService.clear();
    await SecureStore.delete('rail_action_token');
    await SecureStore.delete('rail_hold_seconds');
    await SecureStore.delete('rail_user');
    await NotificationService().clearAlerts();
    if (mounted) {
      Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const WebviewLoginScreen(clearSession: true)), (_) => false);
    }
  }

  Future<void> _search() async {
    if (_loading) return;
    if (_fromCity == _toCity) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose different departure and arrival stations.')));
      return;
    }
    if (_auth == null || !_auth!.isValid) { _logout(); return; }
    setState(() => _loading = true);
    final date = DateFormat('dd-MMM-yyyy').format(_date);
    try {
      final result = await ApiService.searchTrips(
        fromCity: _fromCity, toCity: _toCity,
        dateOfJourney: date, seatClass: _selectedClass, authSession: _auth!,
      );
      if (mounted) {
        setState(() => _loading = false);
        Navigator.push(context, MaterialPageRoute(builder: (_) =>
          TrainSelectionScreen(
            searchResponse: result, fromCity: _fromCity, toCity: _toCity,
            dateOfJourney: date, initialClass: _selectedClass,
          )));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  void _swap() => setState(() { final t = _fromCity; _fromCity = _toCity; _toCity = t; });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeService = context.watch<ThemeService>();
    final credit = context.watch<CreditService>();
    final monitor = context.watch<MonitorService>();
    final dateLabel = DateFormat('EEE, dd MMM').format(_date);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      body: Stack(children: [
        CustomScrollView(slivers: [
          // ── Sticky gradient header ──────────────────────────────────
          SliverAppBar(
            expandedHeight: 170,
            pinned: true,
            stretch: true,
            backgroundColor: AppColors.appBarGradientStart,
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: _HeroHeader(
                fromCity: _fromCity, toCity: _toCity,
                auth: _auth, onLogout: _logout,
              ),
            ),
            actions: [
              // Credit pill
              GestureDetector(
                onTap: () => RechargeCreditDialog.show(context),
                child: _CreditPill(credits: credit.credits),
              ),
              // Theme toggle
              _IconAction(
                icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                onTap: themeService.toggleTheme,
              ),
              // Dashboard
              _IconAction(
                icon: Icons.radar_rounded,
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MonitorDashboardScreen())),
              ),
              const SizedBox(width: 4),
            ],
          ),

          // ── Search Form ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _heroCtrl,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                child: Column(
                  children: [
                    if (monitor.isMonitoring) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Active Auto-Search Running',
                                    style: TextStyle(
                                      color: AppColors.textPrimary(isDark),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Target: ${monitor.targetTrain ?? "All"} • ${monitor.fromCity} → ${monitor.toCity}',
                                    style: TextStyle(
                                      color: AppColors.textMuted(isDark),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const MonitorDashboardScreen()),
                              ),
                              child: const Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    AppCard(
                      child: Column(children: [
                    // From / To
                    _StationPicker(
                      fromCity: _fromCity, toCity: _toCity,
                      stations: _stations, isDark: isDark,
                      onFromChanged: (v) { if (v != null) setState(() => _fromCity = v); },
                      onToChanged: (v) { if (v != null) setState(() => _toCity = v); },
                      onSwap: _swap,
                    ),
                    const SizedBox(height: 12),

                    // Date + Class row
                    Row(children: [
                      Expanded(child: _TapField(
                        icon: Icons.calendar_month_rounded,
                        label: dateLabel,
                        isDark: isDark,
                        onTap: () async {
                          final p = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 30)),
                            builder: (ctx, child) => Theme(
                              data: Theme.of(ctx).copyWith(colorScheme: isDark
                                ? const ColorScheme.dark(primary: AppColors.primary, surface: AppColors.darkCard)
                                : const ColorScheme.light(primary: AppColors.primaryDark, surface: Colors.white)),
                              child: child!,
                            ),
                          );
                          if (p != null) setState(() => _date = p);
                        },
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: _ClassDrop(
                        value: _selectedClass,
                        classes: _classes,
                        isDark: isDark,
                        onChanged: (v) { if (v != null) setState(() => _selectedClass = v); },
                      )),
                    ]),
                    const SizedBox(height: 16),

                    // Search button
                    PrimaryButton(
                      label: 'Search Trains',
                      icon: Icons.search_rounded,
                      loading: _loading,
                      onPressed: _loading ? null : _search,
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        ]),

        // Loading overlay
        if (_loading)
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.scaffoldBg(isDark).withValues(alpha: 0.9),
              child: FancyTrainLoader(
                message: LanguageService.of(context, listen: false).t('searching'),
                showCard: true,
              ),
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final String fromCity;
  final String toCity;
  final AuthSession? auth;
  final VoidCallback onLogout;

  const _HeroHeader({required this.fromCity, required this.toCity, this.auth, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.appBarGradientStart, AppColors.appBarGradientEnd, Color(0xFF00C896)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // App identity row
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.train_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                const Text('Rail Sheba Pro',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                // Account avatar
                GestureDetector(
                  onTap: onLogout,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.person_rounded, color: Colors.white70, size: 15),
                      const SizedBox(width: 5),
                      Text(
                        auth?.phoneNumber?.replaceRange(6, null, '…') ?? '—',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              // Route preview
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Text(fromCity, style: const TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.east_rounded, color: Colors.white.withValues(alpha: 0.7), size: 20),
                ),
                Text(toCity, style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _StationPicker extends StatelessWidget {
  final String fromCity, toCity;
  final List<String> stations;
  final bool isDark;
  final ValueChanged<String?> onFromChanged, onToChanged;
  final VoidCallback onSwap;

  const _StationPicker({
    required this.fromCity, required this.toCity,
    required this.stations, required this.isDark,
    required this.onFromChanged, required this.onToChanged, required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(child: Column(children: [
        _DropField(label: 'From', value: fromCity, icon: Icons.trip_origin_rounded,
          iconColor: AppColors.primary, stations: stations, isDark: isDark, onChanged: onFromChanged),
        const SizedBox(height: 10),
        _DropField(label: 'To', value: toCity, icon: Icons.location_on_rounded,
          iconColor: AppColors.error, stations: stations, isDark: isDark, onChanged: onToChanged),
      ])),
      GestureDetector(
        onTap: onSwap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.swap_vert_rounded, color: AppColors.primary, size: 20),
        ),
      ),
    ]);
  }
}

class _DropField extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color iconColor;
  final List<String> stations;
  final bool isDark;
  final ValueChanged<String?> onChanged;
  const _DropField({required this.label, required this.value, required this.icon,
    required this.iconColor, required this.stations, required this.isDark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      dropdownColor: AppColors.cardBg(isDark),
      style: TextStyle(color: AppColors.textPrimary(isDark), fontSize: 14, fontWeight: FontWeight.w600),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: iconColor, size: 18),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: stations.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
      onChanged: onChanged,
    );
  }
}

class _TapField extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _TapField({required this.icon, required this.label, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.inputFill(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.inputBorder(isDark)),
        ),
        child: Row(children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
            color: AppColors.textPrimary(isDark), fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
      ),
    );
  }
}

class _ClassDrop extends StatelessWidget {
  final String value;
  final List<String> classes;
  final bool isDark;
  final ValueChanged<String?> onChanged;
  const _ClassDrop({required this.value, required this.classes, required this.isDark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey(value),
      initialValue: value,
      dropdownColor: AppColors.cardBg(isDark),
      style: TextStyle(color: AppColors.textPrimary(isDark), fontSize: 13, fontWeight: FontWeight.w600),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Class',
        prefixIcon: const Icon(Icons.airline_seat_recline_extra_rounded, color: AppColors.primary, size: 18),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      items: classes.map((c) => DropdownMenuItem(
        value: c,
        child: Text(c == 'ALL' ? 'Any' : c, overflow: TextOverflow.ellipsis),
      )).toList(),
      onChanged: onChanged,
    );
  }
}

class _CreditPill extends StatelessWidget {
  final int credits;
  const _CreditPill({required this.credits});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.bolt_rounded, color: AppColors.gold, size: 14),
        const SizedBox(width: 3),
        Text('$credits', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ]),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconAction({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 22),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

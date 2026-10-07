import '../services/railway_credentials_rejected.dart';
import '../services/login_recovery_required.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_shell.dart';

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
import '../widgets/station_autocomplete.dart';
import '../widgets/journey_search_button.dart';

import 'package:flutter/services.dart';

import '../utils/railway_stations.dart';
import 'recharge_credit_dialog.dart';
import 'webview_login_screen.dart';
import 'train_selection_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with TickerProviderStateMixin {
  List<String> get _stations {
    final fromConfig = AppConfig.instance.strings('stations');
    if (fromConfig.length >= railwayStations.length) return fromConfig;
    return railwayStations;
  }

  List<String> get _classes => AppConfig.instance.strings('seat_classes');

  String _fromCity = '';
  String _toCity = '';
  DateTime _date = DateTime.now().add(const Duration(days: 3));
  String _selectedClass = 'ALL';
  AuthSession? _auth;
  bool _loading = false;

  late final AnimationController _heroCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
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
    if (session == null) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const WebviewLoginScreen(clearSession: true),
          ),
        );
      }
      return;
    }
    setState(() => _auth = session);
    unawaited(FirebaseUserService().syncUserOnLogin(session));

    // Load user's previous search station history if available
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedFrom = prefs.getString('rps_last_from_station');
      final savedTo = prefs.getString('rps_last_to_station');
      if (mounted) {
        setState(() {
          if (savedFrom != null && savedFrom.trim().isNotEmpty) {
            _fromCity = savedFrom.trim();
          }
          if (savedTo != null && savedTo.trim().isNotEmpty) {
            _toCity = savedTo.trim();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveStationHistory(String from, String to) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (from.trim().isNotEmpty) {
        await prefs.setString('rps_last_from_station', from.trim());
      }
      if (to.trim().isNotEmpty) {
        await prefs.setString('rps_last_to_station', to.trim());
      }
    } catch (_) {}
  }

  Future<void> _logout() async {
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
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const WebviewLoginScreen(clearSession: true),
        ),
        (_) => false,
      );
    }
  }

  Future<void> _search() async {
    if (_loading) return;
    final lang = LanguageService.of(context, listen: false);
    if (CreditService().credits <= 0) {
      RechargeCreditDialog.show(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lang.tr(
              'You have 0 credits. Please buy credits to search and auto-book.',
              'আপনার কোনো ক্রেডিট নেই। টিকেট অনুসন্ধান ও বুকিং করতে ক্রেডিট কিনুন।',
            ),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_fromCity.trim().isEmpty || _toCity.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lang.tr(
              'Please select both departure and arrival stations.',
              'অনুগ্রহ করে যাত্রা শুরুর ও গন্তব্যের স্টেশন নির্বাচন করুন।',
            ),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_fromCity.trim().toLowerCase() == _toCity.trim().toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lang.tr(
              'Departure and arrival stations cannot be the same. Choose different stations.',
              'যাত্রা শুরুর এবং গন্তব্যের স্টেশন একই হতে পারে না।',
            ),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await _saveStationHistory(_fromCity, _toCity);
    if (_auth == null) {
      _logout();
      return;
    }
    setState(() => _loading = true);
    final date = DateFormat('dd-MMM-yyyy').format(_date);
    try {
      final result = await ApiService.searchTrips(
        fromCity: _fromCity,
        toCity: _toCity,
        dateOfJourney: date,
        seatClass: _selectedClass,
        authSession: _auth!,
      );
      if (mounted) {
        setState(() => _loading = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TrainSelectionScreen(
              searchResponse: result,
              fromCity: _fromCity,
              toCity: _toCity,
              dateOfJourney: date,
              initialClass: _selectedClass,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        if (RailwayCredentialsRejected.isError(e)) {
          _logout();
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            action: e is LoginRecoveryRequired
                ? SnackBarAction(
                    label: LanguageService.instance.tr('Log in', 'লগইন'),
                    textColor: Colors.white,
                    onPressed: () =>
                        NotificationService().openBooking('rail://login'),
                  )
                : null,
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  void _handleFromChanged(String station) {
    final lang = LanguageService.of(context, listen: false);
    if (station.trim().isNotEmpty &&
        station.trim().toLowerCase() == _toCity.trim().toLowerCase()) {
      setState(() {
        final prev = _fromCity;
        _fromCity = station;
        _toCity = prev;
      });
      _saveStationHistory(_fromCity, _toCity);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lang.tr(
              'Swapped stations: From and To cannot be the same.',
              'স্টেশন অদলবদল করা হয়েছে: শুরুর ও গন্তব্যের স্টেশন এক হতে পারে না।',
            ),
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() => _fromCity = station);
      _saveStationHistory(station, _toCity);
    }
  }

  void _handleToChanged(String station) {
    final lang = LanguageService.of(context, listen: false);
    if (station.trim().isNotEmpty &&
        station.trim().toLowerCase() == _fromCity.trim().toLowerCase()) {
      setState(() {
        final prev = _toCity;
        _toCity = station;
        _fromCity = prev;
      });
      _saveStationHistory(_fromCity, _toCity);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lang.tr(
              'Swapped stations: From and To cannot be the same.',
              'স্টেশন অদলবদল করা হয়েছে: শুরুর ও গন্তব্যের স্টেশন এক হতে পারে না।',
            ),
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() => _toCity = station);
      _saveStationHistory(_fromCity, station);
    }
  }

  void _swap() {
    HapticFeedback.selectionClick();
    setState(() {
      final t = _fromCity;
      _fromCity = _toCity;
      _toCity = t;
    });
    _saveStationHistory(_fromCity, _toCity);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeService = context.watch<ThemeService>();
    final credit = context.watch<CreditService>();
    final monitor = context.watch<MonitorService>();
    final lang = context.watch<LanguageService>();
    final dateLabel = DateFormat('EEE, dd MMM').format(_date);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ── Professional pinned gradient header ──────────────────
              SliverAppBar(
                pinned: true,
                elevation: 2,
                toolbarHeight: 64,
                backgroundColor: AppColors.appBarGradientStart,
                flexibleSpace: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.appBarGradientStart,
                        AppColors.appBarGradientEnd,
                        Color(0xFF00C896),
                      ],
                      stops: [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    const AppBrandIcon(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Rail Pro',
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            lang.tr(
                              'Smart Rail Automation',
                              'স্মার্ট রেল অটোমেশন',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  // Credit pill
                  GestureDetector(
                    onTap: () => RechargeCreditDialog.show(context),
                    child: _CreditPill(credits: credit.credits, lang: lang),
                  ),
                  // Theme toggle
                  _IconAction(
                    icon: isDark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    onTap: themeService.toggleTheme,
                  ),
                  // Dashboard / Live Monitor
                  _IconAction(
                    icon: Icons.radar_rounded,
                    onTap: () => AppShell.goTo(context, AppShell.tabMonitor),
                  ),
                  const SizedBox(width: 4),
                ],
              ),

              // ── Search Form ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: AnimatedBuilder(
                  animation: _heroCtrl,
                  builder: (context, child) {
                    final t = MediaQuery.disableAnimationsOf(context)
                        ? 1.0
                        : Curves.easeOutCubic.transform(_heroCtrl.value);
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, 18 * (1 - t)),
                        child: child,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                    child: Column(
                      children: [
                        if (monitor.isMonitoring) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.4),
                              ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lang.tr(
                                          'Watching seats',
                                          'আসন খোঁজা হচ্ছে',
                                        ),
                                        style: TextStyle(
                                          color: AppColors.textPrimary(isDark),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${lang.tr("Target", "টার্গেট")}: ${monitor.targetTrain ?? (lang.isBangla ? "সকল ট্রেন" : "All")} • ${monitor.fromCity} → ${monitor.toCity}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () => AppShell.goTo(
                                    context,
                                    AppShell.tabMonitor,
                                  ),
                                  child: Text(
                                    lang.tr('View', 'দেখুন'),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        AppCard(
                          child: Column(
                            children: [
                              // From / To
                              _StationPicker(
                                fromCity: _fromCity,
                                toCity: _toCity,
                                stations: _stations,
                                isDark: isDark,
                                lang: lang,
                                onFromChanged: _handleFromChanged,
                                onToChanged: _handleToChanged,
                                onSwap: _swap,
                              ),
                              const SizedBox(height: 12),

                              // Date + Class row
                              Row(
                                children: [
                                  Expanded(
                                    child: _TapField(
                                      icon: Icons.calendar_month_rounded,
                                      label: dateLabel,
                                      isDark: isDark,
                                      onTap: () async {
                                        final p = await showDatePicker(
                                          context: context,
                                          initialDate: _date,
                                          firstDate: DateTime.now(),
                                          lastDate: DateTime.now().add(
                                            const Duration(days: 30),
                                          ),
                                          builder: (ctx, child) => Theme(
                                            data: Theme.of(ctx).copyWith(
                                              colorScheme: isDark
                                                  ? const ColorScheme.dark(
                                                      primary:
                                                          AppColors.primary,
                                                      surface:
                                                          AppColors.darkCard,
                                                    )
                                                  : const ColorScheme.light(
                                                      primary:
                                                          AppColors.primaryDark,
                                                      surface: Colors.white,
                                                    ),
                                            ),
                                            child: child!,
                                          ),
                                        );
                                        if (p != null) {
                                          setState(() => _date = p);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _ClassDrop(
                                      value: _selectedClass,
                                      classes: _classes,
                                      isDark: isDark,
                                      lang: lang,
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() => _selectedClass = v);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Search / Buy Credit button
                              JourneySearchButton(
                                label: credit.credits <= 0
                                    ? lang.tr('Add credits', 'ক্রেডিট যোগ করুন')
                                    : lang.tr(
                                        'Search Trains',
                                        'ট্রেন অনুসন্ধান',
                                      ),
                                icon: credit.credits <= 0
                                    ? Icons.bolt_rounded
                                    : Icons.search_rounded,
                                loading: _loading,
                                onPressed: _loading
                                    ? null
                                    : (credit.credits <= 0
                                          ? () => RechargeCreditDialog.show(
                                              context,
                                            )
                                          : _search),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Loading overlay
          if (_loading)
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.scaffoldBg(isDark).withValues(alpha: 0.9),
                child: FancyTrainLoader(
                  message: LanguageService.of(
                    context,
                    listen: false,
                  ).t('searching'),
                  showCard: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StationPicker extends StatelessWidget {
  final String fromCity, toCity;
  final List<String> stations;
  final bool isDark;
  final LanguageService lang;
  final ValueChanged<String> onFromChanged, onToChanged;
  final VoidCallback onSwap;

  const _StationPicker({
    required this.fromCity,
    required this.toCity,
    required this.stations,
    required this.isDark,
    required this.lang,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            children: [
              StationAutocomplete(
                label: lang.tr('From', 'কোথা থেকে'),
                value: fromCity,
                otherValue: toCity,
                icon: Icons.trip_origin_rounded,
                stations: stations,
                onSelected: onFromChanged,
              ),
              const SizedBox(height: 10),
              StationAutocomplete(
                label: lang.tr('To', 'কোথায় যাবেন'),
                value: toCity,
                otherValue: fromCity,
                icon: Icons.location_on_rounded,
                stations: stations,
                onSelected: onToChanged,
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: onSwap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.35),
              ),
            ),
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              transitionBuilder: (child, animation) => RotationTransition(
                turns: Tween<double>(begin: 0.5, end: 1).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                Icons.swap_vert_rounded,
                key: ValueKey('$fromCity/$toCity'),
                color: AppColors.primary,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TapField extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _TapField({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

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
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textPrimary(isDark),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassDrop extends StatelessWidget {
  final String value;
  final List<String> classes;
  final bool isDark;
  final LanguageService lang;
  final ValueChanged<String?> onChanged;
  const _ClassDrop({
    required this.value,
    required this.classes,
    required this.isDark,
    required this.lang,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey(value),
      initialValue: value,
      dropdownColor: AppColors.cardBg(isDark),
      style: TextStyle(
        fontFamily: 'Roboto',
        color: AppColors.textPrimary(isDark),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: lang.tr('Class', 'শ্রেণি'),
        prefixIcon: const Icon(
          Icons.airline_seat_recline_extra_rounded,
          color: AppColors.primary,
          size: 18,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
      ),
      items: classes
          .map(
            (c) => DropdownMenuItem(
              value: c,
              child: Text(
                c == 'ALL' ? lang.tr('Random / Any Class', 'যেকোনো শ্রেণি') : c,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _CreditPill extends StatelessWidget {
  final int credits;
  final LanguageService lang;
  const _CreditPill({required this.credits, required this.lang});
  @override
  Widget build(BuildContext context) {
    final isZero = credits <= 0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isZero
            ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
            : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: isZero
            ? Border.all(color: const Color(0xFFF59E0B), width: 1.0)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt_rounded, color: AppColors.gold, size: 14),
          const SizedBox(width: 3),
          Text(
            isZero ? lang.tr('0 • Buy', '০ • কিনুন') : '$credits',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
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

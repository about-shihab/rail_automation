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
import 'package:flutter/services.dart';
import '../utils/railway_stations.dart';
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

    // If monitor active, jump straight to dashboard
    final monitor = context.read<MonitorService>();
    if (monitor.dateOfJourney.isNotEmpty && mounted) {
      AppShell.tab.value = AppShell.tabMonitor;
    }
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
    if (CreditService().credits <= 0) {
      RechargeCreditDialog.show(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have 0 credits. Please buy credits to search and auto-book.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_fromCity.trim().isEmpty || _toCity.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both departure and arrival stations.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_fromCity.trim().toLowerCase() == _toCity.trim().toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Departure and arrival stations cannot be the same. Choose different stations.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await _saveStationHistory(_fromCity, _toCity);
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

  void _handleFromChanged(String station) {
    if (station.trim().isNotEmpty && station.trim().toLowerCase() == _toCity.trim().toLowerCase()) {
      setState(() {
        final prev = _fromCity;
        _fromCity = station;
        _toCity = prev;
      });
      _saveStationHistory(_fromCity, _toCity);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Swapped stations: From and To cannot be the same.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() => _fromCity = station);
      _saveStationHistory(station, _toCity);
    }
  }

  void _handleToChanged(String station) {
    if (station.trim().isNotEmpty && station.trim().toLowerCase() == _fromCity.trim().toLowerCase()) {
      setState(() {
        final prev = _toCity;
        _toCity = station;
        _fromCity = prev;
      });
      _saveStationHistory(_fromCity, _toCity);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Swapped stations: From and To cannot be the same.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() => _toCity = station);
      _saveStationHistory(_fromCity, station);
    }
  }

  void _swap() {
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
    final dateLabel = DateFormat('EEE, dd MMM').format(_date);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      body: Stack(children: [
        CustomScrollView(slivers: [
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
                Container(
                  padding: const EdgeInsets.all(7.5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1),
                  ),
                  child: const Icon(Icons.train_rounded, color: Colors.white, size: 21),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Rail Pro',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Smart Rail Automation',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ],
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
                              onPressed: () => AppShell.goTo(context, AppShell.tabMonitor),
                              child: const Text('View', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (credit.credits <= 0) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1504) : const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFF59E0B),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 24),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '0 Credits Available',
                                        style: TextStyle(
                                          color: isDark ? Colors.white : const Color(0xFF92400E),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Each successful booking consumes 1 credit. Please buy credit via bKash to search and auto-book.',
                                        style: TextStyle(
                                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF78350F),
                                          fontSize: 11.5,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF59E0B),
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                                label: const Text(
                                  'Buy Credit Now (bKash)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                                onPressed: () => RechargeCreditDialog.show(context),
                              ),
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
                      onFromChanged: _handleFromChanged,
                      onToChanged: _handleToChanged,
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

                    // Search / Buy Credit button
                    PrimaryButton(
                      label: credit.credits <= 0
                          ? 'Buy Credit to Search'
                          : 'Search Trains',
                      icon: credit.credits <= 0
                          ? Icons.bolt_rounded
                          : Icons.search_rounded,
                      loading: _loading,
                      onPressed: _loading
                          ? null
                          : (credit.credits <= 0
                              ? () => RechargeCreditDialog.show(context)
                              : _search),
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


class _StationPicker extends StatelessWidget {
  final String fromCity, toCity;
  final List<String> stations;
  final bool isDark;
  final ValueChanged<String> onFromChanged, onToChanged;
  final VoidCallback onSwap;

  const _StationPicker({
    required this.fromCity,
    required this.toCity,
    required this.stations,
    required this.isDark,
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
              _SearchAutoSelectField(
                label: 'From',
                value: fromCity,
                otherValue: toCity,
                icon: Icons.trip_origin_rounded,
                iconColor: AppColors.primary,
                stations: stations,
                isDark: isDark,
                onSelected: onFromChanged,
              ),
              const SizedBox(height: 10),
              _SearchAutoSelectField(
                label: 'To',
                value: toCity,
                otherValue: fromCity,
                icon: Icons.location_on_rounded,
                iconColor: AppColors.error,
                stations: stations,
                isDark: isDark,
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
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
            ),
            child: const Icon(Icons.swap_vert_rounded, color: AppColors.primary, size: 20),
          ),
        ),
      ],
    );
  }
}

class _SearchAutoSelectField extends StatefulWidget {
  final String label;
  final String value;
  final String otherValue;
  final IconData icon;
  final Color iconColor;
  final List<String> stations;
  final bool isDark;
  final ValueChanged<String> onSelected;

  const _SearchAutoSelectField({
    required this.label,
    required this.value,
    required this.otherValue,
    required this.icon,
    required this.iconColor,
    required this.stations,
    required this.isDark,
    required this.onSelected,
  });

  @override
  State<_SearchAutoSelectField> createState() => _SearchAutoSelectFieldState();
}

class _SearchAutoSelectFieldState extends State<_SearchAutoSelectField> {
  TextEditingController? _textController;

  @override
  void didUpdateWidget(_SearchAutoSelectField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (_textController != null && _textController!.text != widget.value) {
        _textController!.text = widget.value;
      }
    }
  }

  void _openSearchModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _StationSearchSheet(
        label: widget.label,
        currentStation: widget.value,
        otherStation: widget.otherValue,
        allStations: widget.stations,
        isDark: widget.isDark,
        onSelected: (selected) {
          widget.onSelected(selected);
          _textController?.text = selected;
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RawAutocomplete<String>(
          initialValue: TextEditingValue(text: widget.value),
          optionsBuilder: (TextEditingValue textEditingValue) {
            final query = textEditingValue.text.trim().toLowerCase();
            final pool = widget.stations.where(
              (s) => s.toLowerCase() != widget.otherValue.toLowerCase(),
            );
            if (query.isEmpty) {
              return pool.take(8);
            }
            return pool.where((s) => s.toLowerCase().contains(query)).take(25);
          },
          onSelected: (String selection) {
            if (selection.toLowerCase() != widget.otherValue.toLowerCase()) {
              widget.onSelected(selection);
              _textController?.text = selection;
            }
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            _textController = controller;
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(
                color: AppColors.textPrimary(widget.isDark),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                labelText: widget.label,
                prefixIcon: Icon(widget.icon, color: widget.iconColor, size: 18),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (controller.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        color: widget.isDark ? Colors.white38 : Colors.black38,
                        onPressed: () {
                          controller.clear();
                          widget.onSelected('');
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.search_rounded, size: 18),
                      color: widget.iconColor,
                      tooltip: 'Search ${widget.label} Station',
                      onPressed: () => _openSearchModal(context),
                    ),
                  ],
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onFieldSubmitted: (v) {
                final trimmed = v.trim();
                final match = widget.stations.firstWhere(
                  (s) => s.toLowerCase() == trimmed.toLowerCase() && s.toLowerCase() != widget.otherValue.toLowerCase(),
                  orElse: () => '',
                );
                if (match.isNotEmpty) {
                  widget.onSelected(match);
                  controller.text = match;
                } else if (trimmed.isNotEmpty) {
                  final partial = widget.stations.firstWhere(
                    (s) => s.toLowerCase().contains(trimmed.toLowerCase()) && s.toLowerCase() != widget.otherValue.toLowerCase(),
                    orElse: () => '',
                  );
                  if (partial.isNotEmpty) {
                    widget.onSelected(partial);
                    controller.text = partial;
                  }
                }
                onFieldSubmitted();
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(14),
                color: widget.isDark ? const Color(0xFF0C1626) : Colors.white,
                shadowColor: Colors.black45,
                child: Container(
                  width: constraints.maxWidth,
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: widget.isDark ? const Color(0xFF1E3A55) : const Color(0xFFCBDCF0),
                      width: 1,
                    ),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: widget.isDark ? Colors.white10 : Colors.black12,
                    ),
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.train_rounded, size: 15, color: widget.iconColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  option,
                                  style: TextStyle(
                                    color: widget.isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StationSearchSheet extends StatefulWidget {
  final String label;
  final String currentStation;
  final String otherStation;
  final List<String> allStations;
  final bool isDark;
  final ValueChanged<String> onSelected;

  const _StationSearchSheet({
    required this.label,
    required this.currentStation,
    required this.otherStation,
    required this.allStations,
    required this.isDark,
    required this.onSelected,
  });

  @override
  State<_StationSearchSheet> createState() => _StationSearchSheetState();
}

class _StationSearchSheetState extends State<_StationSearchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? const Color(0xFF091220) : Colors.white;
    final other = widget.otherStation.toLowerCase();
    final query = _filter.trim().toLowerCase();

    final filtered = widget.allStations.where((s) {
      if (s.toLowerCase() == other) return false;
      if (query.isEmpty) return true;
      return s.toLowerCase().contains(query);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: widget.isDark ? const Color(0xFF00D59B).withValues(alpha: 0.3) : const Color(0xFF00D59B).withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 24, offset: Offset(0, -4)),
        ],
      ),
      padding: EdgeInsets.only(
        top: 14,
        left: 18,
        right: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle pill
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: widget.isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.label == 'From' ? Icons.trip_origin_rounded : Icons.location_on_rounded,
                  color: widget.label == 'From' ? AppColors.primary : AppColors.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select ${widget.label} Station',
                      style: TextStyle(
                        color: AppColors.textPrimary(widget.isDark),
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Cannot be same as ${widget.otherStation} • ${widget.allStations.length} stations available',
                      style: TextStyle(
                        color: AppColors.textSecondary(widget.isDark),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                color: widget.isDark ? Colors.white70 : Colors.black54,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Search Input with auto-focus
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            style: TextStyle(
              color: AppColors.textPrimary(widget.isDark),
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: 'Search station (e.g. Dhaka, Cox\'s Bazar, Sylhet)...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.primary),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _filter = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),

          const SizedBox(height: 10),

          // Popular Quick-Pick Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: popularStations.where((s) => s.toLowerCase() != other).map((station) {
                final isCurrent = station.toLowerCase() == widget.currentStation.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    avatar: Icon(
                      Icons.train_rounded,
                      size: 13,
                      color: isCurrent ? Colors.white : AppColors.primary,
                    ),
                    label: Text(
                      station,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isCurrent
                            ? Colors.white
                            : (widget.isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                      ),
                    ),
                    backgroundColor: isCurrent
                        ? AppColors.primary
                        : (widget.isDark ? const Color(0xFF142032) : const Color(0xFFF1F5F9)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isCurrent
                            ? AppColors.primary
                            : (widget.isDark ? const Color(0xFF1E3A55) : const Color(0xFFCBDCF0)),
                      ),
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      widget.onSelected(station);
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 8),

          // Result Count
          Text(
            '${filtered.length} stations found',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted(widget.isDark),
            ),
          ),

          const SizedBox(height: 6),

          // Station List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No matching stations found',
                      style: TextStyle(
                        color: AppColors.textSecondary(widget.isDark),
                        fontSize: 13,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: widget.isDark ? Colors.white10 : Colors.black12,
                    ),
                    itemBuilder: (context, index) {
                      final station = filtered[index];
                      final isCurrent = station.toLowerCase() == widget.currentStation.toLowerCase();
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        leading: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCurrent
                                ? AppColors.primary.withValues(alpha: 0.2)
                                : (widget.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
                          ),
                          child: Icon(
                            Icons.train_rounded,
                            size: 16,
                            color: isCurrent ? AppColors.primary : (widget.isDark ? Colors.white70 : Colors.black54),
                          ),
                        ),
                        title: Text(
                          station,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                            color: isCurrent ? AppColors.primary : AppColors.textPrimary(widget.isDark),
                          ),
                        ),
                        trailing: isCurrent
                            ? const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
                            : null,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onSelected(station);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
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
        child: Text(c == 'ALL' ? 'Random / Any Class' : c, overflow: TextOverflow.ellipsis),
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
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.bolt_rounded, color: AppColors.gold, size: 14),
        const SizedBox(width: 3),
        Text(
          isZero ? '0 • Buy' : '$credits',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
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

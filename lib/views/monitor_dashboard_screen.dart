import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/monitor_service.dart';
import '../services/notification_service.dart';
import '../services/theme_service.dart';
import '../services/language_service.dart';
import '../utils/app_theme.dart';
import 'booking_screen.dart';
import 'search_screen.dart';
import 'webview_login_screen.dart';

class MonitorDashboardScreen extends StatefulWidget {
  const MonitorDashboardScreen({super.key});

  @override
  State<MonitorDashboardScreen> createState() => _MonitorDashboardScreenState();
}

class _MonitorDashboardScreenState extends State<MonitorDashboardScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  late final AnimationController _radarController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  bool _isSoundEnabled = true;

  @override
  void dispose() {
    _pulseController.dispose();
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeService = Provider.of<ThemeService>(context);
    final langService = LanguageService.of(context);
    final monitor = context.watch<MonitorService>();

    final active = monitor.isMonitoring;
    final hasSearch = monitor.dateOfJourney.isNotEmpty;
    final authError = monitor.lastError != null &&
        RegExp('login|logged|auth|401|session', caseSensitive: false)
            .hasMatch(monitor.lastError!);

    final results = monitor.lastTrains.where(
      (train) =>
          monitor.targetTrain == null || train.tripNumber == monitor.targetTrain,
    );

    int totalAvailableOnline = 0;
    for (final train in results) {
      for (final seat in train.seatTypes) {
        if (monitor.targetSeatClass == null || monitor.targetSeatClass == seat.type) {
          totalAvailableOnline += seat.seatCounts.online;
        }
      }
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      appBar: AppBar(
        backgroundColor: AppColors.appBarGreen,
        elevation: 2,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.radar, color: Colors.tealAccent, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  langService.t('ticket_radar'),
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(
                  active ? langService.t('searching_active') : langService.t('radar_paused'),
                  style: TextStyle(
                    color: active ? const Color(0xFF6EE7B7) : Colors.white70,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Language toggle
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            onPressed: langService.toggleLanguage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                langService.isBangla ? 'EN' : 'বাং',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          // Audio Mute Toggle
          IconButton(
            tooltip: _isSoundEnabled ? langService.t('sound_alert') : 'Muted',
            icon: Icon(
              _isSoundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: _isSoundEnabled ? Colors.amberAccent : Colors.white60,
            ),
            onPressed: () {
              setState(() => _isSoundEnabled = !_isSoundEnabled);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 1),
                  content: Text(
                    _isSoundEnabled
                        ? (langService.isBangla ? 'শব্দ এলার্ট সক্রিয়' : 'Sound alert enabled')
                        : (langService.isBangla ? 'শব্দ এলার্ট বন্ধ' : 'Sound alert muted'),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: themeService.isDarkMode ? 'লাইট মোড' : 'ডার্ক মোড',
            icon: Icon(
              themeService.isDarkMode ? Icons.light_mode : Icons.dark_mode,
              color: Colors.white,
            ),
            onPressed: themeService.toggleTheme,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            // 1. Radar Command Center Card
            _buildRadarHeroCard(
              context: context,
              active: active,
              authError: authError,
              monitor: monitor,
              langService: langService,
              isDark: isDark,
              totalSeats: totalAvailableOnline,
            ),
            const SizedBox(height: 16),

            // 2. Active Route & Target Train HUD
            if (hasSearch)
              _buildJourneyHUD(
                context: context,
                monitor: monitor,
                langService: langService,
                isDark: isDark,
              ),

            // 3. Auth error banner if any
            if (authError) ...[
              const SizedBox(height: 14),
              _buildAuthErrorBanner(context, langService),
            ],

            const SizedBox(height: 18),

            // 4. Live Availability Matrix & Train Cards
            _buildLiveResultsSection(
              context: context,
              monitor: monitor,
              results: results,
              langService: langService,
              isDark: isDark,
              totalSeats: totalAvailableOnline,
            ),

            const SizedBox(height: 16),

            // 6. Quick Radar Controls Strip
            _buildControlsStrip(
              context: context,
              active: active,
              hasSearch: hasSearch,
              monitor: monitor,
              langService: langService,
              isDark: isDark,
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarHeroCard({
    required BuildContext context,
    required bool active,
    required bool authError,
    required MonitorService monitor,
    required LanguageService langService,
    required bool isDark,
    required int totalSeats,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF064E3B), const Color(0xFF0F766E), const Color(0xFF134E4A)]
              : [const Color(0xFF047857), const Color(0xFF059669), const Color(0xFF0D9488)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.25),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        children: [
          // Radar Visual
          SizedBox(
            height: 140,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Animated Radar sweep & ripples
                AnimatedBuilder(
                  animation: _radarController,
                  builder: (_, child) {
                    return CustomPaint(
                      size: const Size(140, 140),
                      painter: _RadarSweepPainter(
                        progress: _radarController.value,
                        active: active,
                      ),
                    );
                  },
                ),
                // Center train badge with pulsing ring
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, child) {
                    final scale = active ? 1.0 + 0.08 * math.sin(_pulseController.value * 2 * math.pi) : 1.0;
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: totalSeats > 0
                              ? const Color(0xFFFDE68A)
                              : (active ? const Color(0xFFD1FAE5) : const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: (totalSeats > 0 ? Colors.amber : const Color(0xFF10B981))
                                  .withValues(alpha: active ? 0.6 : 0.2),
                              blurRadius: active ? 16 : 4,
                              spreadRadius: active ? 3 : 0,
                            ),
                          ],
                        ),
                        child: Icon(
                          totalSeats > 0 ? Icons.celebration_rounded : Icons.train_rounded,
                          size: 34,
                          color: totalSeats > 0
                              ? const Color(0xFFB45309)
                              : (active ? const Color(0xFF065F46) : const Color(0xFF475569)),
                        ),
                      ),
                    );
                  },
                ),
                // Status Chip on Radar
                Positioned(
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active ? const Color(0xFF34D399) : Colors.white24,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: active ? const Color(0xFF34D399) : Colors.amber,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          active
                              ? (langService.isBangla ? 'রাডার সচল' : 'RADAR ACTIVE')
                              : (langService.isBangla ? 'রাডার স্থগিত' : 'RADAR PAUSED'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Title & Status
          Text(
            totalSeats > 0
                ? (langService.isBangla ? '🎉 টিকিট পাওয়া গেছে!' : '🎉 Tickets Available Now!')
                : authError
                    ? langService.t('auth_expired')
                    : active
                        ? (langService.isBangla ? 'সার্ভারে টিকিট খোঁজা হচ্ছে' : 'Scanning Railway Servers...')
                        : (langService.isBangla ? 'অনুসন্ধান বিরতিতে রয়েছে' : 'Radar is Paused'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            totalSeats > 0
                ? (langService.isBangla
                    ? 'মোট $totalSeats টি আসন খালি পাওয়া গেছে। দ্রুত বুকিং করুন!'
                    : 'Total $totalSeats seats found vacant. Book immediately!')
                : (langService.isBangla
                    ? 'আসন খালি হওয়ামাত্র আপনার ফোনে শব্দ ও নোটিফিকেশন আসবে।'
                    : 'Instant alarm and notification will ring the moment a seat opens.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFD1FAE5),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJourneyHUD({
    required BuildContext context,
    required MonitorService monitor,
    required LanguageService langService,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder(isDark)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                langService.t('active_route'),
                style: TextStyle(
                  color: AppColors.textPrimary(isDark),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      '${langService.t('check_interval')}: 15s',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Route display with arrow
          Row(
            children: [
              Expanded(
                child: Text(
                  monitor.fromCity,
                  style: TextStyle(
                    color: AppColors.textPrimary(isDark),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward_rounded, color: AppColors.primary, size: 20),
              ),
              Expanded(
                child: Text(
                  monitor.toCity,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: AppColors.textPrimary(isDark),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Detail Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildHUDChip(
                icon: Icons.calendar_today_rounded,
                text: monitor.dateOfJourney,
                isDark: isDark,
              ),
              _buildHUDChip(
                icon: Icons.train_rounded,
                text: monitor.targetTrain ?? langService.t('all_trains'),
                isDark: isDark,
              ),
              _buildHUDChip(
                icon: Icons.airline_seat_recline_extra_rounded,
                text: monitor.targetSeatClass ?? (langService.isBangla ? 'যেকোনো আসন' : 'Any Class'),
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildHUDChip({required IconData icon, required String text, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.inputFill(isDark),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inputBorder(isDark)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: AppColors.textPrimary(isDark),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthErrorBanner(BuildContext context, LanguageService langService) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              langService.t('auth_expired'),
              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WebviewLoginScreen(clearSession: true)),
            ),
            child: Text(
              langService.t('relogin'),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveResultsSection({
    required BuildContext context,
    required MonitorService monitor,
    required Iterable results,
    required LanguageService langService,
    required bool isDark,
    required int totalSeats,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.event_seat_rounded, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              langService.t('available_seats'),
              style: TextStyle(
                color: AppColors.textPrimary(isDark),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (totalSeats > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$totalSeats ${langService.isBangla ? "টি আসন" : "seats"}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (totalSeats == 0)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.cardBg(isDark),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder(isDark)),
            ),
            child: Column(
              children: [
                const Icon(Icons.radar_rounded, size: 36, color: AppColors.primary),
                const SizedBox(height: 12),
                Text(
                  langService.t('no_seats_yet'),
                  style: TextStyle(
                    color: AppColors.textPrimary(isDark),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  langService.isBangla
                      ? 'রাডার প্রতি ১৫ সেকেন্ড পর পর স্বয়ংক্রিয়ভাবে নতুন আসন খুঁজছে...'
                      : 'Radar is auto-scanning every 15s for cancellations...',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 12),
                ),
              ],
            ),
          ),

        for (final train in results)
          for (final seat in train.seatTypes)
            if (seat.seatCounts.online > 0 &&
                (monitor.targetSeatClass == null || monitor.targetSeatClass == seat.type))
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardBg(isDark),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFD1FAE5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.confirmation_number_rounded, color: Color(0xFF047857), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            train.tripNumber,
                            style: TextStyle(
                              color: AppColors.textPrimary(isDark),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${seat.displayName} • ${seat.seatCounts.online} ${langService.isBangla ? "আসন বাকি" : "seats left"}',
                            style: const TextStyle(
                              color: Color(0xFF059669),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      icon: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 16),
                      label: Text(
                        langService.t('book_now'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BookingScreen(
                            url: NotificationService.bookingUrl(
                              monitor.fromCity,
                              monitor.toCity,
                              monitor.dateOfJourney,
                              seat.type,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ],
    );
  }

  Widget _buildControlsStrip({
    required BuildContext context,
    required bool active,
    required bool hasSearch,
    required MonitorService monitor,
    required LanguageService langService,
    required bool isDark,
  }) {
    return Column(
      children: [
        // ── Active Notifier Warning Banner ───────────────────────────────────
        if (active)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF59E0B), width: 1.4),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    langService.isBangla
                        ? 'নতুন রুট খুঁজলে এই নোটিফায়ার বন্ধ হয়ে যাবে।'
                        : 'Starting a new search will stop the current notifier.',
                    style: const TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // ── Stop Button ──────────────────────────────────────────────────────
        if (active)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.amberAccent, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.amberAccent),
              label: Text(
                langService.t('stop_monitoring'),
                style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              onPressed: monitor.stopMonitoring,
            ),
          ),
        // ── Resume Button ────────────────────────────────────────────────────
        if (!active && hasSearch)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 3,
              ),
              icon: const Icon(Icons.play_circle_outline, color: Colors.white),
              label: Text(
                langService.t('resume_monitoring'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              onPressed: () => monitor.startMonitoring(
                fromCity: monitor.fromCity,
                toCity: monitor.toCity,
                dateOfJourney: monitor.dateOfJourney,
                targetTrain: monitor.targetTrain,
                targetSeatClass: monitor.targetSeatClass,
              ),
            ),
          ),
        const SizedBox(height: 10),
        // ── New Search Button (with confirmation when active) ─────────────
        SizedBox(
          width: double.infinity,
          height: 46,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isDark ? Colors.white24 : Colors.black12,
                ),
              ),
            ),
            icon: const Icon(Icons.search_rounded, size: 18),
            label: Text(
              langService.isBangla ? 'নতুন যাত্রা অনুসন্ধান করুন' : 'Search Another Route',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () => active
                ? _showNewSearchConfirmDialog(context, monitor, langService)
                : Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchScreen()),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _showNewSearchConfirmDialog(
    BuildContext context,
    MonitorService monitor,
    LanguageService langService,
  ) async {
    final isBangla = langService.isBangla;
    // Capture navigator BEFORE any async gap.
    final nav = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
            const SizedBox(width: 10),
            Text(
              isBangla ? 'নোটিফায়ার বন্ধ হবে' : 'Notifier Will Stop',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          isBangla
              ? 'আপনার সক্রিয় টিকেট নোটিফায়ার বন্ধ হয়ে যাবে এবং নতুন রুট খোঁজা শুরু হবে। চালিয়ে যেতে চান?'
              : 'Your active ticket notifier will be stopped and a new route search will begin. Each user can only have one active notifier. Continue?',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              isBangla ? 'না, থাকুক' : 'Keep Active',
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isBangla ? 'হ্যাঁ, নতুন খুঁজুন' : 'Yes, New Search',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      monitor.stopMonitoring();
      if (!mounted) return;
      await nav.push(
        MaterialPageRoute(builder: (_) => const SearchScreen()),
      );
    }
  }
}

class _RadarSweepPainter extends CustomPainter {
  final double progress;
  final bool active;

  _RadarSweepPainter({required this.progress, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Rings
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: active ? 0.18 : 0.08);

    canvas.drawCircle(center, radius * 0.45, ringPaint);
    canvas.drawCircle(center, radius * 0.72, ringPaint);
    canvas.drawCircle(center, radius * 0.98, ringPaint);

    // Crosshairs
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: active ? 0.12 : 0.05);

    canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), linePaint);
    canvas.drawLine(Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy + radius), linePaint);

    if (!active) return;

    // Sweeping Radar Cone
    final sweepAngle = progress * 2 * math.pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: 0.0,
        endAngle: math.pi / 2,
        colors: [
          const Color(0xFF34D399).withValues(alpha: 0.45),
          const Color(0xFF10B981).withValues(alpha: 0.15),
          Colors.transparent,
        ],
        transform: GradientRotation(sweepAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius * 0.98, sweepPaint);

    // Leading scan line
    final scanLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = const Color(0xFF6EE7B7).withValues(alpha: 0.7);

    final endX = center.dx + radius * 0.98 * math.cos(sweepAngle + math.pi / 2);
    final endY = center.dy + radius * 0.98 * math.sin(sweepAngle + math.pi / 2);
    canvas.drawLine(center, Offset(endX, endY), scanLinePaint);
  }

  @override
  bool shouldRepaint(covariant _RadarSweepPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.active != active;
  }
}

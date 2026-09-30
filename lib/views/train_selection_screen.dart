import 'package:flutter/material.dart';
import 'app_shell.dart';
import 'package:provider/provider.dart';

import '../models/auth_session.dart';
import '../models/train_trip.dart';
import '../models/seat_type.dart';
import '../services/monitor_service.dart';
import '../services/booking_service.dart';
import '../services/credit_service.dart';
import '../utils/app_theme.dart';
import '../widgets/seat_badge.dart';
import '../services/app_config.dart';
import 'monitor_dashboard_screen.dart';
import 'webview_login_screen.dart';
import 'seat_booking_screen.dart';
import 'recharge_credit_dialog.dart';
import 'watch_options_dialog.dart';
import 'reservation_screen.dart';

class TrainSelectionScreen extends StatelessWidget {
  final TripSearchResponse searchResponse;
  final String fromCity, toCity, dateOfJourney;
  final String? initialClass;

  const TrainSelectionScreen({
    super.key,
    required this.searchResponse,
    required this.fromCity,
    required this.toCity,
    required this.dateOfJourney,
    this.initialClass,
  });

  Future<void> _watch(
    BuildContext context, {
    required String train,
    String? seatClass,
  }) async {
    final monitor = context.read<MonitorService>();
    if (await BookingService.pending() != null) {
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReservationScreen()),
        );
      }
      return;
    }
    final session = await AuthSession.load();
    if (!context.mounted) return;
    if (session == null || !session.isValid) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WebviewLoginScreen()),
      );
      return;
    }

    if (train.isEmpty) {
      return;
    }

    final isSameRoute = monitor.isMonitoring &&
        monitor.fromCity.toLowerCase() == fromCity.toLowerCase() &&
        monitor.toCity.toLowerCase() == toCity.toLowerCase() &&
        monitor.dateOfJourney == dateOfJourney;

    // Multi-train support: if monitoring same route, allow adding or removing trains
    if (monitor.isMonitoring) {
      if (isSameRoute) {
        if (monitor.isTrainMonitored(train)) {
          final action = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.radar_rounded, color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      train,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Text(
                '$train is actively being monitored for auto-booking.',
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'remove'),
                  child: const Text('Remove from Search', style: TextStyle(color: AppColors.error)),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'view'),
                  child: const Text('View in Monitor'),
                ),
              ],
            ),
          );
          if (!context.mounted) return;
          if (action == 'view') {
            AppShell.goTo(context, AppShell.tabMonitor);
          } else if (action == 'remove') {
            monitor.removeTrainFromMonitoring(train);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Removed $train from active auto-booking.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        } else {
          monitor.addTrainToMonitoring(train);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Added $train to active auto-booking! (Monitoring ${monitor.targetTrains.length} trains)'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.primaryDark,
            ),
          );
          return;
        }
      } else {
        // Different route
        final currentTrain = monitor.targetTrain;
        final stopAndProceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Stop Current Search First',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Text(
              'A search is already active for ${monitor.fromCity} → ${monitor.toCity} ("${currentTrain ?? 'Active'}").\n\nStop the current search to monitor this route?',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep Current', style: TextStyle(color: Colors.white60)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Stop & Switch'),
              ),
            ],
          ),
        );

        if (stopAndProceed != true || !context.mounted) return;
        monitor.stopMonitoring();
        await monitor.clearSearch();
        if (!context.mounted) return;
      }
    }
    if (seatClass == null) {
      final selectedTrain = searchResponse.trains.firstWhere(
        (t) => t.tripNumber == train,
      );
      if (selectedTrain.seatTypes.isEmpty) return;
      final selected = await showModalBottomSheet<SeatType>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ClassSheet(seatTypes: selectedTrain.seatTypes),
      );
      if (selected == null || !context.mounted) return;
      seatClass = (selected.type.toUpperCase() == 'ALL' ||
              selected.type.toUpperCase() == 'RANDOM')
          ? null
          : selected.type;
    }
    if (CreditService().credits <= 0) {
      RechargeCreditDialog.show(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have 0 credits. Please buy credits to auto-book tickets.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final effectiveClass = seatClass;
    final intent = await showWatchOptions(
      context,
      seatClass: effectiveClass,
      trainName: train,
    );
    if (intent == null || !context.mounted) return;
    final selectedTrain = searchResponse.trains.where((t) => t.tripNumber == train).firstOrNull;
    monitor.startMonitoring(
      intent: intent,
      fromCity: fromCity,
      toCity: toCity,
      dateOfJourney: dateOfJourney,
      targetTrain: train,
      targetSeatClass: effectiveClass,
      departureDateTimeJd: selectedTrain?.departureDateTimeJd,
      departureDateTime: selectedTrain?.departureDateTime,
    );
    AppShell.goTo(context, AppShell.tabMonitor);
  }

  Future<void> _openMultiTrainAutoBook(BuildContext context) async {
    final session = await AuthSession.load();
    if (!context.mounted) return;
    if (session == null || !session.isValid) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WebviewLoginScreen()),
      );
      return;
    }

    if (CreditService().credits <= 0) {
      RechargeCreditDialog.show(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have 0 credits. Please buy credits to auto-book tickets.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final monitor = Provider.of<MonitorService>(context, listen: false);
    final isSameRoute = monitor.isMonitoring &&
        monitor.fromCity.toLowerCase() == fromCity.toLowerCase() &&
        monitor.toCity.toLowerCase() == toCity.toLowerCase() &&
        monitor.dateOfJourney == dateOfJourney;

    final selectedTrains = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MultiTrainSheet(
        trains: searchResponse.trains,
        initialSelected: isSameRoute ? monitor.targetTrains : const [],
      ),
    );

    if (selectedTrains == null || selectedTrains.isEmpty || !context.mounted) return;

    final intent = await showWatchOptions(
      context,
      seatClass: initialClass,
      targetTrains: selectedTrains,
    );
    if (intent == null || !context.mounted) return;

    monitor.startMonitoring(
      intent: intent,
      fromCity: fromCity,
      toCity: toCity,
      dateOfJourney: dateOfJourney,
      targetTrains: selectedTrains,
      targetSeatClass: initialClass,
    );
    AppShell.goTo(context, AppShell.tabMonitor);
  }

  Future<void> _book(BuildContext context, TrainTrip train) async {
    if (CreditService().credits <= 0) {
      RechargeCreditDialog.show(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have 0 credits. Please buy credits to book seats.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final session = await AuthSession.load();
    if (!context.mounted) return;
    if (session == null || !session.isValid) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const WebviewLoginScreen(clearSession: true),
        ),
      );
      return;
    }
    final available = train.seatTypes.where((s) => s.isAvailable).toList();
    if (available.isEmpty) return;

    final seatType = available.length == 1
        ? available.first
        : await showModalBottomSheet<SeatType>(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (_) => _ClassSheet(seatTypes: available),
          );
    if (seatType == null || !context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeatBookingScreen(
          train: train,
          seatType: seatType,
          fromCity: fromCity,
          toCity: toCity,
          dateOfJourney: dateOfJourney,
          authSession: session,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trains = searchResponse.trains;
    final totalSeats = trains.fold<int>(0, (s, t) => s + t.totalOnlineSeats);
    final credit = context.watch<CreditService>();
    final monitor = context.watch<MonitorService>();

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.appBarGradientStart,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.appBarGradientStart,
                      AppColors.appBarGradientEnd,
                    ],
                  ),
                ),
              ),
            ),
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$fromCity  →  $toCity',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  dateOfJourney,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            actions: [
              GestureDetector(
                onTap: () => RechargeCreditDialog.show(context),
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 4,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        color: AppColors.gold,
                        size: 14,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${credit.credits}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.radar_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: () => AppShell.goTo(context, AppShell.tabMonitor),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: Container(
                color: AppColors.appBarGradientEnd,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    _Chip(Icons.train_rounded, '${trains.length}', 'trains'),
                    const SizedBox(width: 8),
                    if (totalSeats > 0)
                      _Chip(
                        Icons.event_seat_rounded,
                        '$totalSeats',
                        'seats',
                        highlight: true,
                      ),
                    const Spacer(),
                    if (monitor.isMonitoring)
                      GestureDetector(
                        onTap: () => AppShell.goTo(context, AppShell.tabMonitor),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Active: ${monitor.targetTrain ?? "Searching"}',
                                style: const TextStyle(
                                  color: Colors.white,
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
              ),
            ),
          ),
          // ── Zero Credits Warning ─────────────────────────────────────────
          if (credit.credits <= 0)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1504) : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '0 Credits Available',
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF92400E),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '1 credit is deducted per successful booking. Please buy credit to auto-book.',
                            style: TextStyle(
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF78350F),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => RechargeCreditDialog.show(context),
                      child: const Text('Buy Credit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),

          // ── Multi-Train Auto-Book Banner ──────────────────────────────────
          if (trains.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F2419) : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.playlist_add_check_rounded, color: AppColors.primary, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Multi-Train Auto-Booking',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Select multiple trains on this route. Same API checks all. Each train auto-book to OTP send costs 1 credit.',
                            style: TextStyle(
                              color: AppColors.textSecondary(isDark),
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 14),
                      label: const Text('Select', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () => _openMultiTrainAutoBook(context),
                    ),
                  ],
                ),
              ),
            ),

          // ── Train Cards ──────────────────────────────────────────────────
          trains.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.train_outlined,
                          size: 64,
                          color: AppColors.textMuted(isDark),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No trains found',
                          style: TextStyle(
                            color: AppColors.textMuted(isDark),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final isMon = monitor.isMonitoring &&
                            (fromCity.toLowerCase() == monitor.fromCity.toLowerCase() &&
                             toCity.toLowerCase() == monitor.toCity.toLowerCase() &&
                             dateOfJourney == monitor.dateOfJourney) &&
                            monitor.isTrainMonitored(trains[i].tripNumber);
                        return _TrainCard(
                          train: trains[i],
                          isDark: isDark,
                          isMonitored: isMon,
                          onWatch: () => _watch(ctx, train: trains[i].tripNumber),
                          onBook: () => _book(ctx, trains[i]),
                          onSeatWatch: (seat) => _watch(
                            ctx,
                            train: trains[i].tripNumber,
                            seatClass: seat.type,
                          ),
                        );
                      },
                      childCount: trains.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Train Card — compact, icon-driven
// ─────────────────────────────────────────────────────────────────────────────

class _TrainCard extends StatelessWidget {
  final TrainTrip train;
  final bool isDark;
  final bool isMonitored;
  final VoidCallback onWatch, onBook;
  final ValueChanged<SeatType> onSeatWatch;

  const _TrainCard({
    required this.train,
    required this.isDark,
    this.isMonitored = false,
    required this.onWatch,
    required this.onBook,
    required this.onSeatWatch,
  });

  @override
  Widget build(BuildContext context) {
    final hasSeats = train.hasAnyOnlineSeats;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isMonitored
              ? AppColors.primary
              : hasSeats
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.cardBorder(isDark),
          width: isMonitored ? 2.0 : (hasSeats ? 1.5 : 1.0),
        ),
        boxShadow: (isMonitored || (hasSeats && isDark))
            ? [
                BoxShadow(
                  color: (isMonitored ? AppColors.primary : AppColors.primary)
                      .withValues(alpha: isMonitored ? 0.25 : 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: name + time + availability ───────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        train.tripNumber,
                        style: TextStyle(
                          color: AppColors.textPrimary(isDark),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            train.departureDateTime,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '  →  ',
                            style: TextStyle(
                              color: AppColors.textMuted(isDark),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            train.arrivalDateTime,
                            style: TextStyle(
                              color: AppColors.textSecondary(isDark),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.info.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              train.travelTime,
                              style: const TextStyle(
                                color: AppColors.info,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Availability count badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: hasSeats
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.error.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: hasSeats
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : AppColors.error.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${train.totalOnlineSeats}',
                        style: TextStyle(
                          color: hasSeats
                              ? AppColors.primary
                              : AppColors.textMuted(isDark),
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          height: 1.0,
                        ),
                      ),
                      Text(
                        'seats',
                        style: TextStyle(
                          color: hasSeats
                              ? AppColors.primary.withValues(alpha: 0.7)
                              : AppColors.textMuted(isDark),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Seat class badges ───────────────────────────────────────
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: train.seatTypes
                  .map((s) => SeatBadge(seat: s, onTap: () => onSeatWatch(s)))
                  .toList(),
            ),

            // Low availability warning
            if (train.totalOnlineSeats > 0 &&
                train.totalOnlineSeats <
                    AppConfig.instance.number(
                      'low_availability_threshold',
                    )) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 12,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Only ${train.totalOnlineSeats} left — act fast',
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),
            // ── Action row: icon buttons ─────────────────────────────────
            Row(
              children: [
                // Watch (bell) / Active status
                Expanded(
                  child: _ActionBtn(
                    icon: isMonitored
                        ? Icons.radar_rounded
                        : Icons.notifications_outlined,
                    label: isMonitored ? 'Active • View' : 'Auto-book',
                    color: isMonitored ? AppColors.accent : AppColors.primary,
                    onTap: onWatch,
                    filled: isMonitored || !hasSeats,
                  ),
                ),
                if (hasSeats) ...[
                  const SizedBox(width: 8),
                  // Book
                  Expanded(
                    child: _ActionBtn(
                      icon: Icons.east_rounded,
                      label: 'Book',
                      color: AppColors.primary,
                      onTap: onBook,
                      filled: true,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      backgroundColor: filled ? color : color.withValues(alpha: .08),
      foregroundColor: filled
          ? Colors.black87
          : Theme.of(context).colorScheme.onSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return FilledButton.icon(
      onPressed: onTap,
      style: style,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final bool highlight;
  const _Chip(this.icon, this.value, this.label, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlight
              ? AppColors.primary.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: highlight ? AppColors.primary : Colors.white70,
          ),
          const SizedBox(width: 4),
          Text(
            '$value $label',
            style: TextStyle(
              color: highlight ? AppColors.primary : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Seat class bottom sheet ──────────────────────────────────────────────────

class _ClassSheet extends StatelessWidget {
  final List<SeatType> seatTypes;
  const _ClassSheet({required this.seatTypes});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalSeats = seatTypes.fold<int>(
      0,
      (sum, s) => sum + s.seatCounts.online,
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted(isDark),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Choose Class',
                  style: TextStyle(
                    color: AppColors.textPrimary(isDark),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (totalSeats > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '$totalSeats total seats',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Option 1: Random Class (Whichever is Available) ──────────────
          GestureDetector(
            onTap: () => Navigator.pop(context, SeatType.randomClass),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.10),
                    AppColors.accent.withValues(alpha: isDark ? 0.12 : 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.shuffle_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Random Class (Any Available)',
                              style: TextStyle(
                                color: AppColors.textPrimary(isDark),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'FASTEST',
                                style: TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          totalSeats > 0
                              ? 'Whichever class has seats available • $totalSeats seats total'
                              : 'Auto-books whichever class becomes available',
                          style: TextStyle(
                            color: AppColors.textSecondary(isDark),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // ── Option 2+: Specific Seat Classes ─────────────────────────────
          ...seatTypes.map(
            (seat) => GestureDetector(
              onTap: () => Navigator.pop(context, seat),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.inputFill(isDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.airline_seat_recline_extra_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            seat.displayName,
                            style: TextStyle(
                              color: AppColors.textPrimary(isDark),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${seat.seatCounts.online} seats  •  ৳${seat.fare}',
                            style: TextStyle(
                              color: AppColors.textSecondary(isDark),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MultiTrainSheet extends StatefulWidget {
  final List<TrainTrip> trains;
  final List<String> initialSelected;
  const _MultiTrainSheet({required this.trains, required this.initialSelected});

  @override
  State<_MultiTrainSheet> createState() => _MultiTrainSheetState();
}

class _MultiTrainSheetState extends State<_MultiTrainSheet> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(
      widget.initialSelected.isNotEmpty
          ? widget.initialSelected
          : widget.trains.map((t) => t.tripNumber),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
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
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.playlist_add_check_rounded, color: AppColors.primary, size: 24),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Select Trains for Auto-Book',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_selected.length == widget.trains.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(widget.trains.map((t) => t.tripNumber));
                    }
                  });
                },
                child: Text(
                  _selected.length == widget.trains.length ? 'Deselect All' : 'Select All',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.bolt_rounded, color: AppColors.primary, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All selected trains are checked together in each search. Reserving seats and sending OTP costs 1 credit per train.',
                    style: TextStyle(fontSize: 11, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: widget.trains.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final train = widget.trains[i];
                final isChecked = _selected.contains(train.tripNumber);
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isChecked,
                  activeColor: AppColors.primary,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selected.add(train.tripNumber);
                      } else {
                        _selected.remove(train.tripNumber);
                      }
                    });
                  },
                  title: Text(
                    train.tripNumber,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    '${train.departureDateTime} → ${train.arrivalDateTime} • ${train.totalOnlineSeats} seats',
                    style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 11),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: _selected.isEmpty
                ? 'Select At Least 1 Train'
                : 'Auto-Book (${_selected.length} Train${_selected.length > 1 ? 's' : ''})',
            icon: Icons.check_circle_rounded,
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context, _selected.toList()),
          ),
        ],
      ),
    );
  }
}

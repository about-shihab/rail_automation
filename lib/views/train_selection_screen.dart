import 'dart:async';

import 'package:flutter/material.dart';
import 'app_shell.dart';
import 'package:provider/provider.dart';

import '../models/auth_session.dart';
import '../models/train_trip.dart';
import '../models/seat_type.dart';
import '../services/monitor_service.dart';
import '../services/booking_service.dart';
import '../services/credit_service.dart';
import '../services/language_service.dart';
import '../utils/app_theme.dart';
import '../widgets/seat_badge.dart';
import '../services/app_config.dart';
import 'webview_login_screen.dart';
import 'seat_booking_screen.dart';
import 'recharge_credit_dialog.dart';
import 'watch_options_dialog.dart';
import 'intermediate_station_screen.dart';
import '../services/login_flow.dart';
import '../services/intermediate_station_search.dart';
import '../services/rail_api_client.dart';
import '../utils/railway_stations.dart';

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
        AppShell.goTo(context, AppShell.tabMonitor);
      }
      return;
    }
    final session = await AuthSession.load();
    if (!context.mounted) return;
    if (session == null) {
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
          AppShell.goTo(context, AppShell.tabMonitor);
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
    final selectedTrain = searchResponse.trains.where((t) => t.tripNumber == train).firstOrNull;
    final isLowProbability = _isTrainLowProbability(selectedTrain, effectiveClass);

    if (isLowProbability && selectedTrain != null) {
      final depTime = MonitorService.parseDepartureDateTime(
        departureDateTimeJd: selectedTrain.departureDateTimeJd,
        departureDateTime: selectedTrain.departureDateTime,
        dateOfJourney: dateOfJourney,
        departureFullDate: selectedTrain.departureFullDate,
      );
      final hoursLeft = depTime != null ? depTime.difference(DateTime.now()).inMinutes / 60.0 : 5.0;
      final proceed = await _showLowProbabilityWarning(
        context,
        trainName: train,
        hoursLeft: hoursLeft,
      );
      if (proceed != true || !context.mounted) return;
    }

    final intent = await showWatchOptions(
      context,
      seatClass: effectiveClass,
      trainName: train,
      isLowProbability: isLowProbability,
    );
    if (intent == null || !context.mounted) return;
    AppShell.goTo(context, AppShell.tabMonitor);
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
  }

  bool _isTrainLowProbability(TrainTrip? train, String? seatClass) =>
      isTrainLowProbability(
        train: train,
        seatClass: seatClass,
        dateOfJourney: dateOfJourney,
      );

  static bool isTrainLowProbability({
    required TrainTrip? train,
    String? seatClass,
    required String dateOfJourney,
    DateTime? now,
  }) {
    if (train == null) return false;
    final bool hasSeats = seatClass != null
        ? train.seatTypes.any((s) => s.type == seatClass && s.seatCounts.online > 0)
        : train.totalOnlineSeats > 0;
    if (hasSeats) return false;

    final depTime = MonitorService.parseDepartureDateTime(
      departureDateTimeJd: train.departureDateTimeJd,
      departureDateTime: train.departureDateTime,
      dateOfJourney: dateOfJourney,
      departureFullDate: train.departureFullDate,
    );
    if (depTime == null) return false;

    final currentTime = now ?? DateTime.now();
    final diff = depTime.difference(currentTime);
    return diff.inMinutes > 0 && diff.inMinutes < 360;
  }

  Future<bool> _showLowProbabilityWarning(
    BuildContext context, {
    required String trainName,
    required double hoursLeft,
  }) async {
    final lang = LanguageService.of(context, listen: false);
    final hoursStr = hoursLeft.toStringAsFixed(1);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFF59E0B),
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                lang.tr('Low Ticket Probability', 'টিকিট পাওয়ার সম্ভাবনা অত্যন্ত কম'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          lang.tr(
            'This train ($trainName) departs in less than 6 hours ($hoursStr hrs left) and currently has 0 available seats. At this last hour, ticket cancellation or release probability is very low.\n\nDo you still want to proceed with auto-booking?',
            '$trainName ট্রেনের প্রস্থান হতে ৬ ঘণ্টারও কম সময় বাকি (আর মাত্র $hoursStr ঘণ্টা) এবং বর্তমানে কোনো আসন খালি নেই। শেষ মুহূর্তে আসন খালি হওয়ার বা টিকিট পাওয়ার সম্ভাবনা অত্যন্ত কম।\n\nআপনি কি তবুও অটো-বুক চালু করতে চান?',
          ),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              lang.tr('Cancel', 'বাতিল'),
              style: const TextStyle(color: Colors.white60),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              lang.tr('Auto-Book Anyway', 'তবুও অটো-বুক চালু করুন'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _openMultiTrainAutoBook(BuildContext context) async {
    if (await BookingService.pending() != null) {
      if (context.mounted) AppShell.goTo(context, AppShell.tabMonitor);
      return;
    }
    final session = await AuthSession.load();
    if (!context.mounted) return;
    if (session == null) {
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

    if (selectedTrains == null || selectedTrains.isEmpty || !context.mounted) {
      return;
    }

    final lowProbTrains = searchResponse.trains.where(
      (t) => selectedTrains.contains(t.tripNumber) && _isTrainLowProbability(t, initialClass),
    ).toList();
    final hasLowProb = lowProbTrains.isNotEmpty;
    if (hasLowProb) {
      final proceed = await _showLowProbabilityWarning(
        context,
        trainName: lowProbTrains.map((t) => t.tripNumber).join(', '),
        hoursLeft: 6.0,
      );
      if (proceed != true || !context.mounted) return;
    }

    final intent = await showWatchOptions(
      context,
      seatClass: initialClass,
      targetTrains: selectedTrains,
      isLowProbability: hasLowProb,
    );
    if (intent == null || !context.mounted) return;

    AppShell.goTo(context, AppShell.tabMonitor);
    monitor.startMonitoring(
      intent: intent,
      fromCity: fromCity,
      toCity: toCity,
      dateOfJourney: dateOfJourney,
      targetTrains: selectedTrains,
      targetSeatClass: initialClass,
    );
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
    if (session == null) {
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

    // If random seat class was selected, resolve to SNIGDHA (or available class with valid tripId)
    // because Railway response provides layouts across all classes.
    final effectiveSeatType = (seatType.type.toUpperCase() == 'ALL' ||
            seatType.type.toUpperCase() == 'RANDOM' ||
            seatType.tripId == null)
        ? train.seatTypes.firstWhere(
            (s) => s.type.toUpperCase() == 'SNIGDHA' && s.tripId != null,
            orElse: () => train.seatTypes.firstWhere(
              (s) => s.isAvailable && s.tripId != null,
              orElse: () => train.seatTypes.firstWhere(
                (s) => s.tripId != null,
                orElse: () => train.seatTypes.first,
              ),
            ),
          )
        : seatType;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeatBookingScreen(
          train: train,
          seatType: effectiveSeatType,
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
    final lang = context.watch<LanguageService>();
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
                    _Chip(Icons.train_rounded, '${trains.length}', lang.tr('trains', 'টি ট্রেন')),
                    const SizedBox(width: 8),
                    if (totalSeats > 0)
                      _Chip(
                        Icons.event_seat_rounded,
                        '$totalSeats',
                        lang.tr('seats', 'টি আসন'),
                        highlight: true,
                      ),
                    if (monitor.isMonitoring)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () => AppShell.goTo(context, AppShell.tabMonitor),
                            child: Container(
                              margin: const EdgeInsets.only(left: 8),
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
                                  Flexible(
                                    child: Text(
                                      '${lang.tr("Active", "সক্রিয়")}: ${monitor.targetTrain ?? lang.tr("Searching", "অনুসন্ধান চলছে")}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                            lang.tr('0 Credits Available', '০ ক্রেডিট অবশিষ্ট আছে'),
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF92400E),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lang.tr('1 credit is deducted per successful booking. Please buy credit to auto-book.', 'প্রতিটি সফল বুকিংয়ে ১ ক্রেডিট কাটা হবে। অটো-বুক করতে ক্রেডিট কিনুন।'),
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
                      child: Text(lang.tr('Buy Credit', 'ক্রেডিট কিনুন'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                          Text(
                            lang.tr('Multi-Train Auto-Booking', 'একাধিক ট্রেন অটো-বুকিং'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lang.tr('Select multiple trains on this route. Same API checks all. Each train auto-book to OTP send costs 1 credit.', 'এই রুটের একাধিক ট্রেন বাছাই করুন। সব ট্রেন একই সাথে চেক হবে। ওটিপি পাঠানোর জন্য প্রতি ট্রেনে ১ ক্রেডিট লাগবে।'),
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
                      label: Text(lang.tr('Select Train', 'ট্রেন বাছাই'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () => _openMultiTrainAutoBook(context),
                    ),
                  ],
                ),
              ),
            ),

          // ── Sequential Via Route Pacing Banner ────────────────────────────
          SliverToBoxAdapter(
            child: ValueListenableBuilder<int>(
              valueListenable: _LazyIntermediateQueue.queueCountNotifier,
              builder: (context, queueCount, _) {
                final cooldown = RailApiClient.cooldownRemaining;
                final isThrottled = cooldown > Duration.zero;
                if (queueCount <= 0 && !isThrottled) {
                  return const SizedBox.shrink();
                }
                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isThrottled
                        ? (isDark ? const Color(0xFF2E1500) : const Color(0xFFFFF7ED))
                        : (isDark ? const Color(0xFF0B192C) : const Color(0xFFF0FDF4)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isThrottled
                          ? const Color(0xFFF97316).withValues(alpha: 0.6)
                          : const Color(0xFF10B981).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isThrottled ? Icons.hourglass_top_rounded : Icons.sync_rounded,
                        size: 15,
                        color: isThrottled ? const Color(0xFFF97316) : const Color(0xFF10B981),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isThrottled
                              ? lang.tr(
                                  'Railway server busy. Pacing searches smoothly to protect your session.',
                                  'রেলওয়ে সার্ভারে অতিরিক্ত চাপ। সেশন সচল রাখতে অনুসন্ধান ধীরে পরিচালনা করা হচ্ছে।',
                                )
                              : lang.tr(
                                  'Checking via routes one train at a time to prevent server congestion...',
                                  'সার্ভারের চাপ কমাতে একটি করে ট্রেনের ভায়া রুট খোঁজা হচ্ছে...',
                                ),
                          style: TextStyle(
                            fontSize: 11,
                            color: isThrottled
                                ? (isDark ? const Color(0xFFFDBA74) : const Color(0xFFC2410C))
                                : (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857)),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
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
                          lang.tr('No trains found', 'কোনো ট্রেন পাওয়া যায়নি'),
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
                          from: fromCity,
                          to: toCity,
                          date: dateOfJourney,
                          seatClass: initialClass,
                          isDark: isDark,
                          isMonitored: isMon,
                          onWatch: () => _watch(ctx, train: trains[i].tripNumber),
                          onBook: () => _book(ctx, trains[i]),
                          onIntermediateSearch: () => Navigator.push(
                            ctx,
                            MaterialPageRoute(
                              builder: (_) => IntermediateStationScreen(
                                train: trains[i],
                                from: fromCity,
                                to: toCity,
                                date: dateOfJourney,
                                seatClass: initialClass,
                              ),
                            ),
                          ),
                          showIntermediateSearch:
                              !trains[i].hasAnyOnlineSeats ||
                              (initialClass != null &&
                                  initialClass != 'ALL' &&
                                  initialClass != 'RANDOM' &&
                                  !(trains[i].seatTypeByName(initialClass!)
                                          ?.isAvailable ??
                                      false)),
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
  final String from;
  final String to;
  final String date;
  final String? seatClass;
  final bool isDark;
  final bool isMonitored;
  final VoidCallback onWatch, onBook, onIntermediateSearch;
  final bool showIntermediateSearch;
  final ValueChanged<SeatType> onSeatWatch;

  const _TrainCard({
    required this.train,
    required this.from,
    required this.to,
    required this.date,
    this.seatClass,
    required this.isDark,
    this.isMonitored = false,
    required this.onWatch,
    required this.onBook,
    required this.onIntermediateSearch,
    required this.showIntermediateSearch,
    required this.onSeatWatch,
  });

  @override
  Widget build(BuildContext context) {
    final hasSeats = train.hasAnyOnlineSeats;
    final lang = context.watch<LanguageService>();

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
                        lang.tr('seats', 'আসন'),
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
                    '${lang.tr("Only", "মাত্র")} ${train.totalOnlineSeats} ${lang.tr("left — act fast", "টি বাকি — দ্রুত বুক করুন")}',
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
            if (showIntermediateSearch) ...[
              _LazyIntermediateSearchCard(
                train: train,
                from: from,
                to: to,
                date: date,
                seatClass: seatClass,
                isDark: isDark,
                onOpenFull: onIntermediateSearch,
              ),
              const SizedBox(height: 8),
            ],
            // ── Action row: icon buttons ─────────────────────────────────
            Row(
              children: [
                // Watch (bell) / Active status
                Expanded(
                  child: _ActionBtn(
                    icon: isMonitored
                        ? Icons.radar_rounded
                        : Icons.notifications_outlined,
                    label: isMonitored ? lang.tr('Active • View', 'সক্রিয় • দেখুন') : lang.tr('Auto-book', 'অটো-বুক'),
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
                      label: lang.tr('Book', 'বুক করুন'),
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

/// Fast, automatic lazy loading intermediate station search card.
/// Automatically scans in-between stations progressively without blocking the main UI.
class _LazyIntermediateSearchCard extends StatefulWidget {
  final TrainTrip train;
  final String from;
  final String to;
  final String date;
  final String? seatClass;
  final bool isDark;
  final VoidCallback onOpenFull;

  const _LazyIntermediateSearchCard({
    required this.train,
    required this.from,
    required this.to,
    required this.date,
    this.seatClass,
    required this.isDark,
    required this.onOpenFull,
  });

  @override
  State<_LazyIntermediateSearchCard> createState() => _LazyIntermediateSearchCardState();
}

class _LazyTrainTask {
  final String key;
  final String trainNumber;
  final bool Function() isMounted;
  final void Function(bool inQueue, bool loading) onStatusChanged;
  final Future<void> Function() execute;

  _LazyTrainTask({
    required this.key,
    required this.trainNumber,
    required this.isMounted,
    required this.onStatusChanged,
    required this.execute,
  });
}

/// Sequential queue coordinator for intermediate station lazy searches.
/// Ensures searches happen strictly one train at a time, spaced out by pacing delay
/// to protect Bangladesh Railway servers from receiving concurrent bursts.
class _LazyIntermediateQueue {
  static final List<_LazyTrainTask> _tasks = [];
  static bool _running = false;
  static final ValueNotifier<int> queueCountNotifier = ValueNotifier(0);
  static final ValueNotifier<String?> currentTrainNotifier = ValueNotifier(null);

  static void enqueue(_LazyTrainTask task) {
    _tasks.removeWhere((t) => t.key == task.key);
    _tasks.add(task);
    _notifyQueue();
    scheduleMicrotask(_processNext);
  }

  static void cancel(String key) {
    _tasks.removeWhere((t) => t.key == key);
    _notifyQueue();
  }

  static void _notifyQueue() {
    scheduleMicrotask(() {
      queueCountNotifier.value = _tasks.length;
    });
  }

  static Future<void> _processNext() async {
    if (_running) return;
    _running = true;

    try {
      while (_tasks.isNotEmpty) {
        final task = _tasks.removeAt(0);
        _notifyQueue();

        if (!task.isMounted()) {
          continue;
        }

        // Check if server rate limit cooldown is active
        final cooldown = RailApiClient.cooldownRemaining;
        if (cooldown > Duration.zero) {
          await Future.delayed(cooldown);
        }

        currentTrainNotifier.value = task.trainNumber;
        task.onStatusChanged(false, true); // inQueue=false, loading=true

        try {
          await task.execute();
        } catch (_) {
          // Handled within task
        } finally {
          currentTrainNotifier.value = null;
        }

        // Pacing delay between trains so requests are strictly sequential and spaced out
        if (_tasks.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } finally {
      _running = false;
      currentTrainNotifier.value = null;
      _notifyQueue();
    }
  }
}

class _LazyIntermediateSearchCardState extends State<_LazyIntermediateSearchCard> {
  static final Map<String, List<IntermediateJourney>> _cache = {};
  bool _inQueue = false;
  bool _loading = false;
  List<IntermediateJourney> _results = [];

  String get _key =>
      '${widget.train.tripNumber}_${canonicalStation(widget.from)}_${canonicalStation(widget.to)}_${widget.date}_${widget.seatClass ?? 'ALL'}';

  @override
  void initState() {
    super.initState();
    final cached = _cache[_key];
    if (cached != null) {
      _results = cached;
      _inQueue = false;
      _loading = false;
    } else {
      _inQueue = true;
      _loading = false;
      _LazyIntermediateQueue.enqueue(
        _LazyTrainTask(
          key: _key,
          trainNumber: widget.train.tripNumber,
          isMounted: () => mounted,
          onStatusChanged: (inQueue, loading) {
            if (mounted) {
              setState(() {
                _inQueue = inQueue;
                _loading = loading;
              });
            }
          },
          execute: _runLazySearch,
        ),
      );
    }
  }

  @override
  void dispose() {
    _LazyIntermediateQueue.cancel(_key);
    super.dispose();
  }

  Future<void> _runLazySearch() async {
    try {
      final auth = await AuthSession.load();
      if (auth == null || !auth.isValid) {
        if (mounted) {
          setState(() {
            _loading = false;
            _inQueue = false;
          });
        }
        return;
      }

      final res = await IntermediateStationSearch.search(
        train: widget.train,
        from: widget.from,
        to: widget.to,
        date: widget.date,
        auth: auth,
        seatClass: widget.seatClass,
        cancelled: () => !mounted,
        onResults: (partial) {
          if (mounted && partial.isNotEmpty) {
            setState(() {
              _results = List.from(partial);
              _cache[_key] = _results;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _results = res;
          _cache[_key] = res;
          _loading = false;
          _inQueue = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _inQueue = false;
        });
      }
    }
  }

  Future<void> _bookLeg(IntermediateJourney journey, bool isFirstLeg) async {
    final baseTrain = isFirstLeg ? journey.first : journey.second;
    final legSeat = isFirstLeg ? journey.firstSeat : journey.secondSeat;
    final legFrom = isFirstLeg ? canonicalStation(widget.from) : journey.canonicalVia;
    final legTo = isFirstLeg ? journey.canonicalVia : canonicalStation(widget.to);
    final legDate = isFirstLeg ? journey.firstDate : journey.secondDate;

    // Dedicated single-ticket trip prevents redundant search / parallel booking calls
    final legTrain = TrainTrip(
      tripNumber: baseTrain.tripNumber,
      departureDateTime: baseTrain.departureDateTime,
      departureFullDate: baseTrain.departureFullDate,
      departureDateTimeJd: baseTrain.departureDateTimeJd,
      arrivalDateTime: baseTrain.arrivalDateTime,
      travelTime: baseTrain.travelTime,
      originCityName: legFrom,
      destinationCityName: legTo,
      trainModel: baseTrain.trainModel,
      isOpenForAll: baseTrain.isOpenForAll,
      seatTypes: [legSeat],
      boardingPoints: baseTrain.boardingPoints,
    );

    var auth = await AuthSession.load();
    if (auth == null || !auth.isValid) {
      final ok = await LoginFlow.openManualLogin();
      if (!ok) return;
      auth = await AuthSession.load();
      if (auth == null || !auth.isValid) return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeatBookingScreen(
          train: legTrain,
          seatType: legSeat,
          fromCity: legFrom,
          toCity: legTo,
          dateOfJourney: legDate,
          authSession: auth!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    final isDark = widget.isDark;

    if (_results.isNotEmpty) {
      final best = _results.first;

      return Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF042017) : const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.4),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.alt_route_rounded, size: 16, color: Color(0xFF10B981)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${lang.tr("Via Route Found", "ভায়া রুট পাওয়া গেছে")}: ${best.via}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
                InkWell(
                  onTap: widget.onOpenFull,
                  child: Text(
                    lang.tr('Search via intermediate station', 'মধ্যবর্তী স্টেশন হয়ে খুঁজুন'),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF10B981),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              lang.tr(
                'Two separate single tickets (up to 4 seats each). Book one ticket at a time.',
                'দুটি আলাদা একক টিকিট (প্রতিটিতে সর্বোচ্চ ৪ আসন)। একটি করে বুক করুন।',
              ),
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted(isDark),
              ),
            ),
            const SizedBox(height: 10),

            // Single Ticket 1 (Leg 1: From -> Via)
            _buildSingleTicketCard(
              context: context,
              legNumber: 1,
              from: widget.from,
              to: best.via,
              trainNumber: best.first.tripNumber,
              seat: best.firstSeat,
              isDark: isDark,
              onBook: () => _bookLeg(best, true),
            ),

            const SizedBox(height: 8),

            // Single Ticket 2 (Leg 2: Via -> To)
            _buildSingleTicketCard(
              context: context,
              legNumber: 2,
              from: best.via,
              to: widget.to,
              trainNumber: best.second.tripNumber,
              seat: best.secondSeat,
              isDark: isDark,
              onBook: () => _bookLeg(best, false),
            ),
          ],
        ),
      );
    }

    // Simple, clean loader while searching or waiting in sequential queue
    if (_results.isEmpty && (_loading || _inQueue)) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
            width: 0.9,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDark ? const Color(0xFF10B981) : const Color(0xFF059669),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _inQueue
                    ? lang.tr('Queued for via search...', 'ভায়া অনুসন্ধানের অপেক্ষায়...')
                    : lang.tr('Checking via routes...', 'ভায়া রুট খোঁজা হচ্ছে...'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            InkWell(
              onTap: widget.onOpenFull,
              child: Text(
                lang.tr('Search via intermediate station', 'মধ্যবর্তী স্টেশন হয়ে খুঁজুন'),
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF10B981),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildSingleTicketCard({
    required BuildContext context,
    required int legNumber,
    required String from,
    required String to,
    required String trainNumber,
    required SeatType seat,
    required bool isDark,
    required VoidCallback onBook,
  }) {
    final lang = LanguageService.of(context);
    final fareNum = double.tryParse(seat.fare) ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${lang.tr("Leg", "অংশ")} $legNumber',
              style: const TextStyle(
                color: Color(0xFF10B981),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$from ➔ $to',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(isDark),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$trainNumber · ${seat.displayName}: ${seat.seatCounts.online} ${lang.tr("seats", "আসন")}${fareNum > 0 ? " · ৳${fareNum.toStringAsFixed(0)}" : ""}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted(isDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            onPressed: onBook,
            child: Text(
              '${lang.tr("Book", "বুক")} $legNumber',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
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
    final lang = context.watch<LanguageService>();
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
                  lang.tr('Choose Class', 'শ্রেণি বাছাই করুন'),
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
                    '$totalSeats ${lang.tr("total seats", "মোট আসন")}',
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
                              lang.tr('Random Class (Any Available)', 'যেকোনো শ্রেণি (আসন পেলেই)'),
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
                              child: Text(
                                lang.tr('FASTEST', 'সবচেয়ে দ্রুত'),
                                style: const TextStyle(
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
                              ? (lang.isBangla
                                  ? 'যে শ্রেণিতে সিট পাওয়া যাবে • মোট $totalSeats সিট'
                                  : 'Whichever class has seats available • $totalSeats seats total')
                              : lang.tr('Auto-books whichever class becomes available', 'যেকোনো শ্রেণিতে সিট খালি হলেই অটো-বুক হবে'),
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
                            '${seat.seatCounts.online} ${lang.tr("seats", "আসন")}  •  ৳${seat.fare}',
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
    final lang = context.watch<LanguageService>();
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
              Expanded(
                child: Text(
                  lang.tr('Select Trains for Auto-Book', 'অটো-বুকের জন্য ট্রেন নির্বাচন'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                  _selected.length == widget.trains.length
                      ? lang.tr('Deselect All', 'সব বাতিল')
                      : lang.tr('Select All', 'সব নির্বাচন'),
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
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lang.tr(
                      'All selected trains are checked together in each search. Reserving seats and sending OTP costs 1 credit per train.',
                      'নির্বাচিত সব ট্রেন একসাথে চেক করা হবে। আসন সংরক্ষণ ও ওটিপি পাঠাতে ট্রেনপ্রতি ১ ক্রেডিট লাগবে।',
                    ),
                    style: const TextStyle(fontSize: 11, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: widget.trains.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
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
                    '${train.departureDateTime} → ${train.arrivalDateTime} • ${train.totalOnlineSeats} ${lang.tr("seats", "আসন")}',
                    style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 11),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: _selected.isEmpty
                ? lang.tr('Select At Least 1 Train', 'কমপক্ষে ১টি ট্রেন নির্বাচন করুন')
                : (lang.isBangla
                    ? 'অটো-বুক (${_selected.length}টি ট্রেন)'
                    : 'Auto-Book (${_selected.length} Train${_selected.length > 1 ? "s" : ""})'),
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

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/trip_record.dart';
import '../services/booking_service.dart';
import '../services/trip_history_service.dart';
import '../utils/app_theme.dart';
import 'booking_screen.dart';
import 'reservation_screen.dart';

enum _TripFilter { all, successful, failed }

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  _TripFilter _filter = _TripFilter.all;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final history = TripHistoryService();

    return ListenableBuilder(
      listenable: history,
      builder: (context, _) {
        final allTrips = history.trips;

        final successfulTrips = allTrips
            .where((t) =>
                t.status == TripBookingStatus.successful ||
                t.status == TripBookingStatus.awaitingOtp)
            .toList();

        final failedTrips = allTrips
            .where((t) =>
                t.status == TripBookingStatus.failed ||
                t.status == TripBookingStatus.expired)
            .toList();

        List<TripRecord> filtered;
        switch (_filter) {
          case _TripFilter.all:
            filtered = allTrips;
            break;
          case _TripFilter.successful:
            filtered = successfulTrips;
            break;
          case _TripFilter.failed:
            filtered = failedTrips;
            break;
        }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.appBarGradientStart,
                AppColors.appBarGradientEnd,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.luggage_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trips & Bookings',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'History of auto-booked and reserved tickets',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (allTrips.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear history',
                      icon: const Icon(
                        Icons.delete_sweep_outlined,
                        color: Colors.white70,
                        size: 22,
                      ),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.cardBg(isDark),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            title: Text(
                              'Clear Trip History?',
                              style: TextStyle(
                                color: AppColors.textPrimary(isDark),
                              ),
                            ),
                            content: Text(
                              'This will clear all saved successful and failed booking records on this device.',
                              style: TextStyle(
                                color: AppColors.textSecondary(isDark),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.error,
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Clear All'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await history.clearHistory();
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Filter Chips Row
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                _filterChip(
                  label: 'All (${allTrips.length})',
                  selected: _filter == _TripFilter.all,
                  onTap: () => setState(() => _filter = _TripFilter.all),
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'Successful (${successfulTrips.length})',
                  selected: _filter == _TripFilter.successful,
                  onTap: () => setState(() => _filter = _TripFilter.successful),
                  color: AppColors.primary,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'Failed (${failedTrips.length})',
                  selected: _filter == _TripFilter.failed,
                  onTap: () => setState(() => _filter = _TripFilter.failed),
                  color: AppColors.error,
                  isDark: isDark,
                ),
              ],
            ),
          ),

          // Trip Cards List
          Expanded(
            child: filtered.isEmpty
                ? _emptyState(isDark)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _TripCard(record: item, isDark: isDark);
                    },
                  ),
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? color,
    required bool isDark,
  }) {
    final activeColor = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.18)
              : AppColors.cardBg(isDark),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? activeColor
                : AppColors.cardBorder(isDark),
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected
                ? (isDark ? Colors.white : activeColor)
                : AppColors.textSecondary(isDark),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.train_rounded,
                size: 34,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _filter == _TripFilter.all
                  ? 'No Booking History Yet'
                  : _filter == _TripFilter.successful
                      ? 'No Successful Bookings'
                      : 'No Failed Bookings',
              style: TextStyle(
                color: AppColors.textPrimary(isDark),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Successful reservations and failed auto-book attempts will automatically be recorded here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary(isDark),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final TripRecord record;
  final bool isDark;

  const _TripCard({required this.record, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isSuccess = record.status == TripBookingStatus.successful;
    final isReserved = record.status == TripBookingStatus.awaitingOtp;
    final isExpired = record.status == TripBookingStatus.expired;
    final isFailed = record.status == TripBookingStatus.failed;

    Color badgeColor;
    IconData badgeIcon;
    String badgeText;

    if (isSuccess) {
      badgeColor = AppColors.success;
      badgeIcon = Icons.check_circle_rounded;
      badgeText = 'SUCCESSFUL';
    } else if (isReserved) {
      badgeColor = AppColors.primary;
      badgeIcon = Icons.hourglass_top_rounded;
      badgeText = 'RESERVED (OTP)';
    } else if (isExpired) {
      badgeColor = AppColors.warning;
      badgeIcon = Icons.timer_off_outlined;
      badgeText = 'EXPIRED (5m Limit)';
    } else {
      badgeColor = AppColors.error;
      badgeIcon = Icons.cancel_outlined;
      badgeText = 'FAILED';
    }

    final formattedTime = DateFormat('dd MMM, hh:mm a').format(record.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isReserved
              ? AppColors.primary.withValues(alpha: 0.5)
              : AppColors.cardBorder(isDark),
          width: isReserved ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top Row: Status badge + Auto-book indicator + Time ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: badgeColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 12, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(
                      badgeText,
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (record.isAutoBook)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, size: 11, color: AppColors.gold),
                      SizedBox(width: 2),
                      Text(
                        'Auto-book',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              Text(
                formattedTime,
                style: TextStyle(
                  color: AppColors.textMuted(isDark),
                  fontSize: 11,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Train Trip Name & Route ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.trainName,
                      style: TextStyle(
                        color: AppColors.textPrimary(isDark),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          record.fromCity,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        Text(
                          '  →  ',
                          style: TextStyle(
                            color: AppColors.textMuted(isDark),
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          record.toCity,
                          style: TextStyle(
                            color: AppColors.textPrimary(isDark),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Journey Date Badge
              if (record.dateOfJourney.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.inputFill(isDark),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 11,
                        color: AppColors.textMuted(isDark),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        record.dateOfJourney,
                        style: TextStyle(
                          color: AppColors.textSecondary(isDark),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Seats, Coach & Fare Row ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.inputFill(isDark),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                // Seat Class
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    record.seatClass.isNotEmpty ? record.seatClass : 'CLASS',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Seats / Coach details
                Expanded(
                  child: Text(
                    record.seatNumbers.isNotEmpty
                        ? 'Coach ${record.coachName}: ${record.seatNumbers.join(", ")}'
                        : (record.coachName.isNotEmpty
                            ? 'Coach: ${record.coachName}'
                            : (isFailed ? 'No seats held' : 'Seats pending')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary(isDark),
                      fontSize: 11.5,
                    ),
                  ),
                ),
                if (record.totalFare > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '৳${record.totalFare.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: AppColors.textPrimary(isDark),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Failure reason / Expiry note (if any) ──
          if (record.failureReason != null && record.failureReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (isExpired ? AppColors.warning : AppColors.error)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (isExpired ? AppColors.warning : AppColors.error)
                      .withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isExpired
                        ? Icons.timer_off_outlined
                        : Icons.error_outline_rounded,
                    size: 13,
                    color: isExpired ? AppColors.warning : AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      record.failureReason!,
                      style: TextStyle(
                        color: isExpired ? AppColors.warning : AppColors.error,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Live Action Button (if currently awaiting OTP) ──
          if (isReserved) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text(
                  'Continue Reservation & OTP',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ReservationScreen()),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/auth_session.dart';
import '../models/train_trip.dart';
import '../models/seat_type.dart';
import '../services/monitor_service.dart';
import '../utils/app_theme.dart';
import '../widgets/seat_badge.dart';
import 'monitor_dashboard_screen.dart';
import 'webview_login_screen.dart';

class TrainSelectionScreen extends StatelessWidget {
  final TripSearchResponse searchResponse;
  final String fromCity;
  final String toCity;
  final String dateOfJourney;
  final String? initialClass;

  const TrainSelectionScreen({
    super.key,
    required this.searchResponse,
    required this.fromCity,
    required this.toCity,
    required this.dateOfJourney,
    this.initialClass,
  });

  void _startMonitoring(
    BuildContext context, {
    String? trainName,
    String? seatClass,
  }) async {
    final session = await AuthSession.load();
    if (session == null || !session.isValid) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('অনুগ্রহ করে প্রথমে লগইন করুন।'),
          ),
        );
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WebviewLoginScreen()),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final monitor = Provider.of<MonitorService>(context, listen: false);
    monitor.startMonitoring(
      fromCity: fromCity,
      toCity: toCity,
      dateOfJourney: dateOfJourney,
      targetTrain: trainName,
      targetSeatClass: seatClass,
    );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MonitorDashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trains = searchResponse.trains;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      appBar: AppBar(
        backgroundColor: AppColors.appBarGreen,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$fromCity ➔ $toCity',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '$dateOfJourney  •  টিকেট আছে',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'টিকেট আসলে জানানোর ড্যাশবোর্ড',
            icon: const Icon(Icons.radar, color: Colors.tealAccent),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MonitorDashboardScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Route & Global Alert banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.cardBg(isDark),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${trains.length} টি ট্রেন পাওয়া গেছে',
                        style: TextStyle(
                          color: AppColors.textPrimary(isDark),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'টিকেট ছাড়ার সাথে সাথে নোটিফিকেশন পেতে আসন নির্বাচন করুন বা সবগুলোর জন্য জানান।',
                        style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.notifications_active, size: 16, color: Colors.white),
                  label: const Text(
                    'সব ট্রেনের জন্য জানান',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  onPressed: () => _startMonitoring(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
          // Train Cards List
          Expanded(
            child: trains.isEmpty
                ? Center(
                    child: Text(
                      'নির্বাচিত রুটে কোনো ট্রেন পাওয়া যায়নি।',
                      style: TextStyle(color: AppColors.textMuted(isDark)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: trains.length,
                    itemBuilder: (context, index) {
                      final train = trains[index];
                      return _buildTrainCard(context, train, isDark);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainCard(BuildContext context, TrainTrip train, bool isDark) {
    final hasSeats = train.hasAnyOnlineSeats;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasSeats
              ? const Color(0xFF10B981)
              : AppColors.cardBorder(isDark),
          width: hasSeats ? 1.5 : 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Train Header & Times
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.train, color: isDark ? Colors.tealAccent : const Color(0xFF059669), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        train.tripNumber,
                        style: TextStyle(
                          color: AppColors.textPrimary(isDark),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            train.departureDateTime,
                            style: TextStyle(
                              color: isDark ? Colors.tealAccent : const Color(0xFF059669),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(' ➔ ', style: TextStyle(color: AppColors.textMuted(isDark))),
                          Text(
                            train.arrivalDateTime,
                            style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 13),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '(${train.travelTime})',
                            style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Total seats badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasSeats
                        ? (isDark ? const Color(0xFF065F46) : const Color(0xFFECFDF5))
                        : (isDark ? Colors.red.withValues(alpha: 0.15) : const Color(0xFFFEE2E2)),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: hasSeats ? const Color(0xFF10B981) : Colors.redAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    hasSeats ? '${train.totalOnlineSeats} টি আসন আছে' : 'আসন খালি নেই',
                    style: TextStyle(
                      color: hasSeats
                          ? (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857))
                          : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: AppColors.cardBorder(isDark), height: 1),
            const SizedBox(height: 10),
            // Coach / Seat Classes list
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: train.seatTypes.map((seat) {
                return SeatBadge(
                  seat: seat,
                  onTap: () {
                    _showMonitorOptionSheet(context, train, seat);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            // Action Buttons Row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.tealAccent : const Color(0xFF059669),
                    side: BorderSide(color: isDark ? Colors.tealAccent : const Color(0xFF059669)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.notifications_active_outlined, size: 16),
                  label: const Text('টিকেট আসলে জানান', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _startMonitoring(context, trainName: train.tripNumber),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showMonitorOptionSheet(BuildContext context, TrainTrip train, SeatType seat) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active, color: Color(0xFF059669)),
                const SizedBox(width: 8),
                Text(
                  'টিকেট আসলে জানান',
                  style: TextStyle(
                    color: AppColors.textPrimary(isDark),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder(isDark)),
              ),
              child: Text(
                'ট্রেন: ${train.tripNumber}\nশ্রেণি: ${seat.displayName} (${seat.type})\nভাড়া: ৳${seat.fare} | বর্তমান আসন: ${seat.seatCounts.online}\n\nসিট খালি হওয়ার সাথে সাথে ফোনে অডিবল অ্যালার্ম ও নোটিফিকেশন দেওয়া হবে।',
                style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 13, height: 1.4),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.alarm_on, color: Colors.white),
                label: Text(
                  'এই ট্রেনের ${seat.type} আসন আসলে জানান',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _startMonitoring(
                    context,
                    trainName: train.tripNumber,
                    seatClass: seat.type,
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary(isDark),
                  side: BorderSide(color: AppColors.cardBorder(isDark)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('বাতিল'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/auth_session.dart';
import '../models/train_trip.dart';
import '../models/seat_type.dart';
import '../services/monitor_service.dart';
import '../services/language_service.dart';
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

  Future<void> _startMonitoring(
    BuildContext context, {
    String? trainName,
    String? seatClass,
  }) async {
    // Capture dependencies before any async gap
    final nav = Navigator.of(context);
    final monitor = Provider.of<MonitorService>(context, listen: false);
    final lang = LanguageService.of(context, listen: false);

    final session = await AuthSession.load();

    if (session == null || !session.isValid) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(lang.t('login_required')),
          ),
        );
        nav.push(MaterialPageRoute(builder: (_) => const WebviewLoginScreen()));
      }
      return;
    }

    monitor.startMonitoring(
      fromCity: fromCity,
      toCity: toCity,
      dateOfJourney: dateOfJourney,
      targetTrain: trainName,
      targetSeatClass: seatClass,
    );

    nav.push(MaterialPageRoute(builder: (_) => const MonitorDashboardScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final langService = LanguageService.of(context);
    final trains = searchResponse.trains;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      appBar: AppBar(
        backgroundColor: AppColors.appBarGreen,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$fromCity → $toCity',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              dateOfJourney,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
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
          IconButton(
            tooltip: langService.t('radar_dashboard'),
            icon: const Icon(Icons.radar, color: Colors.tealAccent),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MonitorDashboardScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Summary Banner ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.cardBg(isDark),
              border: Border(
                bottom: BorderSide(color: AppColors.cardBorder(isDark)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${trains.length} ${langService.t('trains_found')}',
                        style: TextStyle(
                          color: AppColors.textPrimary(isDark),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        langService.t('notify_hint'),
                        style: TextStyle(
                          color: AppColors.textSecondary(isDark),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.notifications_active_rounded, size: 16, color: Colors.white),
                  label: Text(
                    langService.t('notify_all_trains'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  onPressed: () => _startMonitoring(context),
                ),
              ],
            ),
          ),

          // ── Train Cards List ──────────────────────────────────────────────
          Expanded(
            child: trains.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.train_outlined, size: 48, color: AppColors.textMuted(isDark)),
                        const SizedBox(height: 12),
                        Text(
                          langService.t('no_trains_found'),
                          style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: trains.length,
                    itemBuilder: (context, index) {
                      return _buildTrainCard(context, trains[index], isDark, langService);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainCard(
    BuildContext context,
    TrainTrip train,
    bool isDark,
    LanguageService lang,
  ) {
    final hasSeats = train.hasAnyOnlineSeats;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasSeats ? const Color(0xFF10B981) : AppColors.cardBorder(isDark),
          width: hasSeats ? 1.5 : 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        children: [
          // ── Train Header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                // Train icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: hasSeats
                        ? const Color(0xFFECFDF5)
                        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.train_rounded,
                    color: hasSeats ? const Color(0xFF059669) : AppColors.textMuted(isDark),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                // Train name & times
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
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            train.departureDateTime,
                            style: const TextStyle(
                              color: Color(0xFF059669),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '  →  ',
                            style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 12),
                          ),
                          Text(
                            train.arrivalDateTime,
                            style: TextStyle(
                              color: AppColors.textSecondary(isDark),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(${train.travelTime})',
                            style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Seat count badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: hasSeats
                        ? const Color(0xFFECFDF5)
                        : (isDark ? Colors.red.withValues(alpha: 0.1) : const Color(0xFFFEE2E2)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasSeats
                          ? const Color(0xFF10B981)
                          : Colors.redAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    hasSeats
                        ? '${train.totalOnlineSeats} ${lang.t('seats_available')}'
                        : lang.t('no_seats'),
                    style: TextStyle(
                      color: hasSeats ? const Color(0xFF047857) : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Seat Badges ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: train.seatTypes.map((seat) {
                return SeatBadge(
                  seat: seat,
                  onTap: () => _showMonitorOptionSheet(context, train, seat, lang),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),

          // ── Action Button ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF059669),
                    side: const BorderSide(color: Color(0xFF059669)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.notifications_active_outlined, size: 16),
                  label: Text(
                    lang.t('notify_this_train'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _startMonitoring(context, trainName: train.tripNumber),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMonitorOptionSheet(
    BuildContext context,
    TrainTrip train,
    SeatType seat,
    LanguageService lang,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg(isDark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sheet title
            Row(
              children: [
                const Icon(Icons.notifications_active_rounded, color: Color(0xFF059669)),
                const SizedBox(width: 10),
                Text(
                  lang.t('monitor_sheet_title'),
                  style: TextStyle(
                    color: AppColors.textPrimary(isDark),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Info card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder(isDark)),
              ),
              child: Column(
                children: [
                  _buildInfoRow(lang.t('train_label'), train.tripNumber, isDark),
                  const SizedBox(height: 6),
                  _buildInfoRow(lang.t('class_label'), '${seat.displayName} (${seat.type})', isDark),
                  const SizedBox(height: 6),
                  _buildInfoRow(lang.t('fare_label'), '৳${seat.fare}', isDark),
                  const SizedBox(height: 6),
                  _buildInfoRow(
                    lang.t('current_seats'),
                    seat.seatCounts.online.toString(),
                    isDark,
                    valueColor: seat.seatCounts.online > 0 ? const Color(0xFF059669) : Colors.redAccent,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              lang.t('monitor_sheet_desc'),
              style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 20),

            // Start Alert button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.alarm_on_rounded, color: Colors.white),
                label: Text(
                  '${lang.t('start_alert_for')}: ${seat.type}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
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

            // Cancel button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary(isDark),
                  side: BorderSide(color: AppColors.cardBorder(isDark)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: Text(lang.t('cancel')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 12)),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.textPrimary(isDark),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}


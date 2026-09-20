import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/monitor_service.dart';
import '../services/notification_service.dart';
import '../services/pro_service.dart';
import '../services/theme_service.dart';
import '../utils/app_theme.dart';
import 'webview_login_screen.dart';

class MonitorDashboardScreen extends StatelessWidget {
  const MonitorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final proService = Provider.of<ProService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeService = Provider.of<ThemeService>(context);

    return Consumer<MonitorService>(
      builder: (context, monitor, child) {
        return Scaffold(
          backgroundColor: AppColors.scaffoldBg(isDark),
          appBar: AppBar(
            backgroundColor: AppColors.appBarGreen,
            elevation: 2,
            title: const Text(
              'টিকেট নোটিফায়ার',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              IconButton(
                tooltip: isDark ? 'লাইট মোড চালু করুন' : 'ডার্ক মোড চালু করুন',
                icon: Icon(
                  isDark ? Icons.light_mode : Icons.dark_mode,
                  color: Colors.white,
                ),
                onPressed: themeService.toggleTheme,
              ),
              IconButton(
                tooltip: 'লগ মুছুন',
                icon: const Icon(Icons.delete_outline, color: Colors.white70),
                onPressed: monitor.clearLogs,
              ),
              IconButton(
                tooltip: 'টেস্ট নোটিফিকেশন',
                icon: const Icon(Icons.notifications_active, color: Colors.amberAccent),
                onPressed: () {
                  NotificationService().testNotification();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('টেস্ট এলার্ট পাঠানো হয়েছে! নোটিফিকেশন বার চেক করুন।'),
                    ),
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // 1-Hour Free Limit vs Pro Cloud Timer Banner
              _buildTimerBanner(context, monitor, proService, isDark),

              // Active Status Header Card
              _buildStatusCard(context, monitor, proService, isDark),

              // Polling Interval & Control Bar
              _buildIntervalControl(context, monitor, isDark),

              // Error Banner (if any)
              _buildErrorBanner(context, monitor, isDark),

              // Activity Log Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'লাইভ নোটিফিকেশন হিস্ট্রি',
                      style: TextStyle(
                        color: AppColors.textSecondary(isDark),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${monitor.logs.length} ইভেন্ট',
                      style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 11),
                    ),
                  ],
                ),
              ),

              // Logs List
              Expanded(
                child: monitor.logs.isEmpty
                    ? Center(
                        child: Text(
                          'এখনো কোনো অনুসন্ধান কার্যক্রম শুরু হয়নি। নিচের বাটনে চাপুন।',
                          style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: monitor.logs.length,
                        itemBuilder: (context, index) {
                          final log = monitor.logs[index];
                          return _buildLogItem(log, isDark);
                        },
                      ),
              ),
            ],
          ),
          bottomNavigationBar: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBg(isDark),
              border: Border(top: BorderSide(color: AppColors.cardBorder(isDark))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: monitor.isMonitoring
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF059669),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                    icon: Icon(
                      monitor.isMonitoring ? Icons.stop : Icons.notifications_active,
                      color: Colors.white,
                    ),
                    label: Text(
                      monitor.isMonitoring
                          ? 'এলার্ট বন্ধ করুন'
                          : 'টিকেট আসলে জানাবেন (চালু করুন)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      if (monitor.isMonitoring) {
                        monitor.stopMonitoring();
                      } else {
                        if (monitor.isLimitReached && !proService.isPro) {
                          _showProUpgradeModal(context, proService, isDark);
                          return;
                        }
                        monitor.startMonitoring(
                          fromCity: monitor.fromCity,
                          toCity: monitor.toCity,
                          dateOfJourney: monitor.dateOfJourney,
                          targetTrain: monitor.targetTrain,
                          targetSeatClass: monitor.targetSeatClass,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimerBanner(
    BuildContext context,
    MonitorService monitor,
    ProService proService,
    bool isDark,
  ) {
    final isPro = proService.isPro;
    final isExpired = monitor.isLimitReached;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPro
            ? (isDark ? const Color(0xFF78350F).withValues(alpha: 0.3) : const Color(0xFFFEF3C7))
            : (isExpired
                ? (isDark ? Colors.red.withValues(alpha: 0.2) : const Color(0xFFFEE2E2))
                : (isDark ? AppColors.cardBg(true) : const Color(0xFFF0FDF4))),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPro
              ? Colors.amber
              : (isExpired ? Colors.redAccent : const Color(0xFF059669).withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isPro
                    ? Icons.cloud_done
                    : (isExpired ? Icons.timer_off : Icons.timer),
                color: isPro
                    ? Colors.amber
                    : (isExpired ? Colors.redAccent : const Color(0xFF059669)),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPro
                          ? '২৪/৭ ক্লাউড সার্ভার নোটিফিকেশন (প্রো)'
                          : (isExpired
                              ? '১ ঘণ্টার ফ্রি লিমিট শেষ হয়েছে!'
                              : 'ফ্রি টিয়ার: ১ ঘণ্টার নোটিফিকেশন লিমিট'),
                      style: TextStyle(
                        color: isPro
                            ? (isDark ? Colors.amber : const Color(0xFFB45309))
                            : (isExpired ? Colors.redAccent : (isDark ? Colors.white : const Color(0xFF0F172A))),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      isPro
                          ? 'মোবাইল বন্ধ থাকলেও ব্যাকগ্রাউন্ডে চেক করবে'
                          : monitor.remainingTimeFormatted,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isPro)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isExpired ? Colors.redAccent : Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () => _showProUpgradeModal(context, proService, isDark),
                  child: Text(
                    isExpired ? 'আনলক প্রো' : 'গো প্রো',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          if (!isPro) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: monitor.freeProgressFraction,
              backgroundColor: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
              color: isExpired ? Colors.redAccent : const Color(0xFF10B981),
              minHeight: 4,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    MonitorService monitor,
    ProService proService,
    bool isDark,
  ) {
    final isActive = monitor.isMonitoring;

    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? const Color(0xFF10B981) : AppColors.cardBorder(isDark),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? const Color(0xFF10B981) : Colors.grey,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.6),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isActive ? 'টিকেট খোঁজ করা হচ্ছে' : 'এলার্ট সাময়িক বন্ধ',
                style: TextStyle(
                  color: isActive
                      ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                      : AppColors.textMuted(isDark),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (monitor.lastCheckedAt != null)
                Text(
                  'সর্বশেষ: ${_formatTime(monitor.lastCheckedAt!)}',
                  style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: AppColors.cardBorder(isDark), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.route, color: Color(0xFF059669), size: 18),
              const SizedBox(width: 8),
              Text(
                '${monitor.fromCity} ➔ ${monitor.toCity}',
                style: TextStyle(
                  color: AppColors.textPrimary(isDark),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  monitor.dateOfJourney.isNotEmpty ? monitor.dateOfJourney : 'সেট করা নেই',
                  style: const TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'উদ্দিষ্ট ট্রেন: ',
                style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 12),
              ),
              Text(
                monitor.targetTrain ?? 'সব ট্রেন',
                style: const TextStyle(
                  color: Color(0xFFD97706),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                'শ্রেণী: ',
                style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 12),
              ),
              Text(
                monitor.targetSeatClass ?? 'যে কোনো',
                style: const TextStyle(
                  color: Color(0xFFD97706),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatMetric('মোট চেক', '${monitor.totalChecksCount}', isDark: isDark),
              _buildStatMetric('আসন পাওয়া গেছে', '${monitor.seatsFoundCount}', isAccent: true, isDark: isDark),
              _buildStatMetric('অটো-চেক', '২ মি (${monitor.secondsUntilNextCheck}s)', isDark: isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatMetric(String label, String value, {bool isAccent = false, required bool isDark}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: isAccent
                ? const Color(0xFF10B981)
                : AppColors.textPrimary(isDark),
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildIntervalControl(BuildContext context, MonitorService monitor, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder(isDark)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, color: Color(0xFF059669), size: 20),
          const SizedBox(width: 8),
          Text(
            'চেক ব্যবধান: ${monitor.intervalSeconds}s',
            style: TextStyle(color: AppColors.textPrimary(isDark), fontSize: 13),
          ),
          Expanded(
            child: Slider(
              value: monitor.intervalSeconds.toDouble().clamp(10.0, 300.0),
              min: 10,
              max: 300,
              divisions: 29,
              activeColor: const Color(0xFF059669),
              inactiveColor: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
              onChanged: (val) {
                monitor.setInterval(val.round());
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, MonitorService monitor, bool isDark) {
    if (monitor.lastError == null || monitor.lastError!.isEmpty) {
      return const SizedBox.shrink();
    }
    final isAuthError = monitor.lastError!.toLowerCase().contains('login') ||
        monitor.lastError!.toLowerCase().contains('auth') ||
        monitor.lastError!.contains('401');

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.red.withValues(alpha: 0.15) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              monitor.lastError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isAuthError)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WebviewLoginScreen()),
                );
              },
              child: const Text('লগইন করুন', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Widget _buildLogItem(MonitorLog log, bool isDark) {
    final color = log.isAlert
        ? const Color(0xFF10B981)
        : (log.isError
            ? Colors.redAccent
            : AppColors.textPrimary(isDark));
    final bgColor = log.isAlert
        ? const Color(0xFF059669).withValues(alpha: isDark ? 0.25 : 0.1)
        : (log.isError
            ? Colors.red.withValues(alpha: isDark ? 0.1 : 0.05)
            : (isDark ? Colors.transparent : Colors.white));

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: log.isAlert
              ? const Color(0xFF10B981)
              : (log.isError ? Colors.redAccent.withValues(alpha: 0.3) : AppColors.cardBorder(isDark)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatTime(log.time),
            style: TextStyle(
              color: AppColors.textMuted(isDark),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              log.message,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: log.isAlert ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showProUpgradeModal(BuildContext context, ProService proService, bool isDark) {
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
            Row(
              children: [
                const Icon(Icons.workspace_premium, color: Colors.amberAccent, size: 28),
                const SizedBox(width: 10),
                Text(
                  'প্রো টিয়ার সুবিধা',
                  style: TextStyle(
                    color: AppColors.textPrimary(isDark),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'ফ্রি এলার্ট সেবা ১ ঘণ্টার জন্য সীমাবদ্ধ। প্রো টিয়ারে ডেডিকেটেড ক্লাউড সার্ভার ২৪/৭ ট্রেনের টিকিট চেক করবে এবং টিকিট পাওয়ামাত্র ইনস্ট্যান্ট অ্যালার্ম বাজিয়ে জানাবে।',
              style: TextStyle(
                color: AppColors.textSecondary(isDark),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            _buildBenefitRow(Icons.cloud_sync, 'ডেডিকেটেড সার্ভারে ২৪/৭ অটোমেটিক চেক', isDark),
            _buildBenefitRow(Icons.timer_off, 'আনলিমিটেড সময়সীমা (১ ঘণ্টার কোনো সীমাবদ্ধতা নেই)', isDark),
            _buildBenefitRow(Icons.battery_charging_full, 'মোবাইলে কোনো চার্জ বা ডাটা অপচয় হবে না', isDark),
            _buildBenefitRow(Icons.notifications_active, 'ইনস্ট্যান্ট হাই-প্রায়োরিটি রিংটোন নোটিফিকেশন', isDark),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.bolt, color: Colors.white),
                label: const Text(
                  'প্রো সক্রিয় করুন (২৪/৭ অটোমেটিক এলার্ট)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: () async {
                  await proService.setProStatus(true);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('🎉 প্রো আনলক হয়েছে! ২৪/৭ সার্ভার এলার্ট সক্রিয়।'),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitRow(IconData icon, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

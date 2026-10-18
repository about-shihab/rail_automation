import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_service.dart';
import '../services/language_service.dart';
import '../utils/app_theme.dart';

class AppUpdateDialog extends StatelessWidget {
  final bool force;
  const AppUpdateDialog({super.key, this.force = false});

  static Future<void> show(BuildContext context, {bool force = false}) async {
    final updates = AppUpdateService.instance;
    final isForced = force || updates.required;
    await showDialog<void>(
      context: context,
      barrierDismissible: !isForced,
      builder: (_) => AppUpdateDialog(force: isForced),
    );
  }

  @override
  Widget build(BuildContext context) {
    final updates = AppUpdateService.instance;
    final policy = updates.policy;
    final lang = LanguageService.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final newVersion = policy?.version ?? 'Latest';
    final currentVersion = updates.installedVersion.isNotEmpty
        ? updates.installedVersion
        : '1.0.0';

    return PopScope(
      canPop: !force,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppColors.cardBg(isDark),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon Header with Gradient Ring
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: force
                        ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                        : [AppColors.primary, AppColors.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (force ? const Color(0xFFEF4444) : AppColors.primary)
                          .withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                force
                    ? lang.tr('Mandatory Update', 'বাধ্যতামূলক আপডেট')
                    : lang.tr('Update Available', 'নতুন আপডেট পাওয়া গেছে'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(isDark),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              // Version Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'v$currentVersion → v$newVersion',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Description
              Text(
                force
                    ? lang.tr(
                        'This version is required to continue searching and booking train seats. Please update now.',
                        'বুকিং ও অনুসন্ধান চালিয়ে যেতে এই আপডেটটি বাধ্যতামূলক। অনুগ্রহ করে এখনই আপডেট করুন।',
                      )
                    : lang.tr(
                        'A newer version of Rail Pro is available with latest features and performance enhancements.',
                        'রেল প্রো-এর নতুন সংস্করণ পাওয়া গেছে। নতুন সুবিধা ও দ্রুত গতির জন্য এখনই আপডেট করুন।',
                      ),
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppColors.textSecondary(isDark),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Action Buttons
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: Text(
                    lang.tr('Update Now', 'এখনই আপডেট করুন'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: force
                        ? const Color(0xFFEF4444)
                        : AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () async {
                    if (policy != null) {
                      try {
                        await launchUrl(
                          policy.download,
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (_) {}
                    }
                  },
                ),
              ),

              if (!force) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    if (policy != null) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString(
                        'dismissed_update_version',
                        policy.version,
                      );
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(
                    lang.tr('Later', 'পরে'),
                    style: TextStyle(
                      color: AppColors.textMuted(isDark),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

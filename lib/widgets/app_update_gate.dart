import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_service.dart';
import '../services/language_service.dart';

class AppUpdateGate extends StatelessWidget {
  const AppUpdateGate({super.key, required this.child, this.service});
  final Widget child;
  final AppUpdateService? service;

  @override
  Widget build(BuildContext context) {
    final updates = service ?? AppUpdateService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([updates, LanguageService.instance]),
      builder: (context, _) {
        if (!updates.required) return child;
        final tr = LanguageService.instance.tr;
        // Replace the navigator subtree so dialogs, notification deep links,
        // and Android Back cannot bypass the mandatory update screen.
        return PopScope(
          canPop: false,
          child: Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.system_update_rounded, size: 72),
                        const SizedBox(height: 24),
                        Text(
                          tr('Update Rail Pro', 'Rail Pro আপডেট করুন'),
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr(
                            'Install the latest version to continue booking. Your saved search remains on this device.',
                            'বুকিং চালিয়ে যেতে নতুন সংস্করণ ইনস্টল করুন। আপনার সংরক্ষিত সার্চ এই ডিভাইসেই থাকবে।',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${updates.installedVersion} → ${updates.policy!.version}',
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          icon: const Icon(Icons.download_rounded),
                          label: Text(
                            tr('Download update', 'আপডেট ডাউনলোড করুন'),
                          ),
                          onPressed: () async {
                            var opened = false;
                            try {
                              opened = await launchUrl(
                                updates.policy!.download,
                                mode: LaunchMode.externalApplication,
                              );
                            } catch (_) {}
                            if (!opened && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    tr(
                                      'Could not open the download. Try again.',
                                      'ডাউনলোড খোলা যায়নি। আবার চেষ্টা করুন।',
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        TextButton(
                          onPressed: updates.checking
                              ? null
                              : () => updates.refresh(force: true),
                          child: Text(tr('Check again', 'আবার যাচাই করুন')),
                        ),
                        if (updates.checking) const LinearProgressIndicator(),
                        if (updates.error != null)
                          Text(
                            tr(
                              'Update information is unavailable. Please check your connection.',
                              'আপডেটের তথ্য পাওয়া যাচ্ছে না। ইন্টারনেট সংযোগ যাচাই করুন।',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 12),
                        Text(
                          tr(
                            'Open the downloaded APK and approve installation. Keep the existing app installed.',
                            'ডাউনলোড করা APK খুলে ইনস্টল করার অনুমতি দিন। আগের অ্যাপ আনইনস্টল করবেন না।',
                          ),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

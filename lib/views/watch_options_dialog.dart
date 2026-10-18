import 'package:flutter/material.dart';

import '../models/booking_intent.dart';
import '../services/app_config.dart';
import '../services/credit_service.dart';
import '../services/language_service.dart';
import '../services/sms_service.dart';
import '../utils/app_theme.dart';
import '../widgets/journey_search_button.dart';
import 'recharge_credit_dialog.dart';

Future<BookingIntent?> showWatchOptions(
  BuildContext context, {
  String? seatClass,
  String? trainName,
  List<String>? targetTrains,
  String? scheduledStart,
  bool isLowProbability = false,
}) => showModalBottomSheet<BookingIntent>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => _WatchSheet(
    seatClass: seatClass,
    trainName: trainName,
    targetTrains: targetTrains,
    scheduledStart: scheduledStart,
    isLowProbability: isLowProbability,
  ),
);

class _WatchSheet extends StatefulWidget {
  final String? seatClass;
  final String? trainName;
  final List<String>? targetTrains;
  final String? scheduledStart;
  final bool isLowProbability;
  const _WatchSheet({
    this.seatClass,
    this.trainName,
    this.targetTrains,
    this.scheduledStart,
    this.isLowProbability = false,
  });
  @override
  State<_WatchSheet> createState() => _WatchSheetState();
}

class _WatchSheetState extends State<_WatchSheet> {
  int _quantity = 1;
  bool _autoVerify = true;
  bool _busy = false;

  Future<void> _start() async {
    if (_busy) return;
    if (CreditService().credits <= 0) {
      Navigator.pop(context);
      RechargeCreditDialog.show(context);
      return;
    }
    setState(() => _busy = true);
    final verify = _autoVerify && await SmsService().requestSmsPermission();
    if (!mounted) return;
    final effectiveTrains =
        widget.targetTrains != null && widget.targetTrains!.isNotEmpty
        ? widget.targetTrains!
        : (widget.trainName != null && widget.trainName!.isNotEmpty
              ? [widget.trainName!]
              : const <String>[]);
    Navigator.pop(
      context,
      BookingIntent(
        autoReserve: true,
        quantity: _quantity,
        autoVerify: verify,
        targetTrains: effectiveTrains,
      ),
    );
  }

  String _number(int value, LanguageService lang) {
    if (!lang.isBangla) return '$value';
    const digits = '০১২৩৪৫৬৭৮৯';
    return '$value'.split('').map((c) => digits[int.parse(c)]).join();
  }

  String _className(LanguageService lang) {
    final code = widget.seatClass?.toUpperCase();
    return switch (code) {
      null || 'ALL' || 'RANDOM' => lang.tr('Any class', 'যেকোনো শ্রেণি'),
      'SNIGDHA' => lang.tr('Snigdha', 'স্নিগ্ধা'),
      'S_CHAIR' => lang.tr('Shovon Chair', 'শোভন চেয়ার'),
      'AC_S' => lang.tr('AC Seat', 'এসি সিট'),
      'AC_B' => lang.tr('AC Berth', 'এসি বার্থ'),
      'F_SEAT' => lang.tr('First Class Seat', 'প্রথম শ্রেণি সিট'),
      'F_BERTH' => lang.tr('First Class Berth', 'প্রথম শ্রেণি বার্থ'),
      'SHOVON' => lang.tr('Shovon', 'শোভন'),
      _ => widget.seatClass!,
    };
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageService.of(context);
    final credit = CreditService();
    return ListenableBuilder(
      listenable: Listenable.merge([lang, credit]),
      builder: (context, _) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final trains = widget.targetTrains?.isNotEmpty == true
            ? widget.targetTrains!
            : widget.trainName?.isNotEmpty == true
            ? [widget.trainName!]
            : <String>[];
        final cardColor = dark
            ? const Color(0xFF142533)
            : const Color(0xFFF3F8F6);
        final borderColor = dark
            ? const Color(0xFF25404A)
            : const Color(0xFFDEEBE6);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 +
                MediaQuery.viewInsetsOf(context).bottom +
                MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.primary,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      lang.tr('Auto-booking', 'অটো-বুকিং'),
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: lang.tr('Close', 'বন্ধ করুন'),
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppColors.textMuted(dark),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (widget.scheduledStart != null) ...[
                Text(
                  lang.tr(
                    'Search starts ${widget.scheduledStart} (Bangladesh time), when your journey is within 10 days. Any train on this route can be booked in your selected class. Monitoring continues until departure.',
                    'যাত্রার ১০ দিন আগে ${widget.scheduledStart} (বাংলাদেশ সময়) থেকে অনুসন্ধান শুরু হবে। এই রুটের যেকোনো ট্রেনে আপনার নির্বাচিত শ্রেণিতে বুকিং হবে। ট্রেন ছাড়া পর্যন্ত অনুসন্ধান চলবে।',
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.train_rounded,
                            color: AppColors.primary,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            trains.isEmpty
                                ? lang.tr('All trains', 'সব ট্রেন')
                                : trains.join('\n'),
                            style: TextStyle(
                              color: AppColors.textPrimary(dark),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.event_seat_outlined,
                          size: 17,
                          color: AppColors.textSecondary(dark),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _className(lang),
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary(dark),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Material(
                color: cardColor,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: borderColor),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              lang.tr('Seats', 'আসন'),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Material(
                            color: AppColors.cardBg(dark),
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                              side: BorderSide(color: borderColor),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: lang.tr('Fewer seats', 'আসন কমান'),
                                  onPressed: !_busy && _quantity > 1
                                      ? () => setState(() => _quantity--)
                                      : null,
                                  icon: const Icon(
                                    Icons.remove_rounded,
                                    size: 19,
                                  ),
                                ),
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    _number(_quantity, lang),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: lang.tr('More seats', 'আসন বাড়ান'),
                                  style: IconButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                  ),
                                  onPressed:
                                      !_busy &&
                                          _quantity <
                                              AppConfig.instance.number(
                                                'max_seats',
                                              )
                                      ? () => setState(() => _quantity++)
                                      : null,
                                  icon: const Icon(Icons.add_rounded, size: 19),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: borderColor,
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.only(
                        left: 14,
                        right: 10,
                      ),
                      title: Text(
                        lang.tr('Auto-verify OTP', 'স্বয়ংক্রিয় ওটিপি যাচাই'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        lang.tr(
                          'Google asks to read this OTP when the SMS arrives',
                          'ওটিপির SMS এলে Google সেটি পড়ার অনুমতি চাইবে',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary(dark),
                        ),
                      ),
                      value: _autoVerify,
                      onChanged: _busy
                          ? null
                          : (v) async {
                              if (v) {
                                final ok = await SmsService()
                                    .requestSmsPermission();
                                if (mounted) setState(() => _autoVerify = ok);
                              } else {
                                setState(() => _autoVerify = false);
                              }
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    color: AppColors.primary,
                    size: 17,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      lang.tr(
                        '1 credit per train when OTP is sent',
                        'ওটিপি পাঠালে প্রতি ট্রেনে ১ ক্রেডিট',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(dark),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                lang.tr(
                  'Payment required to confirm seats.',
                  'আসন নিশ্চিত করতে পেমেন্ট করতে হবে।',
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted(dark),
                ),
              ),
              if (widget.isLowProbability) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFF59E0B),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          lang.tr(
                            'Warning: Departure in < 6 hrs with 0 available seats. Ticket availability probability is low.',
                            'সতর্কতা: যাত্রা শুরুর ৬ ঘণ্টার কম বাকি এবং কোনো আসন খালি নেই। টিকিট পাওয়ার সম্ভাবনা অত্যন্ত কম।',
                          ),
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              JourneySearchButton(
                label: credit.credits <= 0
                    ? lang.tr('Add credits', 'ক্রেডিট যোগ করুন')
                    : widget.scheduledStart != null
                    ? lang.tr('Schedule', 'সময়সূচি করুন')
                    : lang.tr('Start', 'শুরু করুন'),
                icon: credit.credits <= 0
                    ? Icons.bolt_rounded
                    : Icons.play_arrow_rounded,
                loading: _busy,
                onPressed: _busy ? null : _start,
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../models/booking_intent.dart';
import '../services/app_config.dart';
import '../services/sms_service.dart';
import '../utils/app_theme.dart';

Future<BookingIntent?> showWatchOptions(
  BuildContext context, {
  String? seatClass,
}) => showModalBottomSheet<BookingIntent>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => _WatchSheet(seatClass: seatClass),
);

class _WatchSheet extends StatefulWidget {
  final String? seatClass;
  const _WatchSheet({this.seatClass});
  @override
  State<_WatchSheet> createState() => _WatchSheetState();
}

class _WatchSheetState extends State<_WatchSheet> {
  int _quantity = 1;
  bool _autoVerify = true;
  bool _busy = false;

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    final verify = _autoVerify && await SmsService().requestSmsPermission();
    if (!mounted) return;
    Navigator.pop(
      context,
      BookingIntent(autoReserve: true, quantity: _quantity, autoVerify: verify),
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      24,
      8,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.auto_awesome_outlined,
          size: 32,
          color: AppColors.primaryDark,
        ),
        const SizedBox(height: 16),
        Text(
          'Let us find your seats',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          'We’ll watch your journey and try to reserve seats as soon as they’re available. You finish the payment.',
          style: TextStyle(height: 1.6),
        ),
        const SizedBox(height: 20),
        Chip(
          avatar: const Icon(Icons.event_seat_outlined, size: 18),
          label: Text(widget.seatClass ?? 'Any available class'),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                'How many seats?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Fewer seats',
              onPressed: !_busy && _quantity > 1
                  ? () => setState(() => _quantity--)
                  : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '$_quantity',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'More seats',
              onPressed:
                  !_busy && _quantity < AppConfig.instance.number('max_seats')
                  ? () => setState(() => _quantity++)
                  : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Verify Railway SMS automatically'),
          subtitle: const Text(
            'Requires SMS permission on Android. Otherwise, we’ll ask you to enter the code.',
          ),
          value: _autoVerify,
          onChanged: _busy ? null : (v) => setState(() => _autoVerify = v),
        ),
        const SizedBox(height: 16),
        const Text(
          'If Railway needs you to sign in or complete verification, we’ll ask you to continue. A seat is confirmed only after payment.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Start auto-booking',
          icon: Icons.arrow_forward_rounded,
          loading: _busy,
          onPressed: _busy ? null : _start,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Not now'),
          ),
        ),
      ],
    ),
  );
}

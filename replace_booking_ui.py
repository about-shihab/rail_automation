from pathlib import Path
Path('lib/views/seat_booking_screen.dart').write_text('''import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/auth_session.dart';
import '../models/train_trip.dart';
import '../models/seat_type.dart';
import '../models/seat_layout.dart';
import '../services/api_service.dart';
import '../services/app_config.dart';
import '../services/booking_service.dart';
import '../services/monitor_service.dart';
import '../services/notification_service.dart';
import '../services/otp_verifier.dart';
import '../services/sms_service.dart';
import 'booking_screen.dart';
import 'reservation_screen.dart';

class SeatBookingScreen extends StatefulWidget {
  final TrainTrip train;
  final SeatType seatType;
  final String fromCity, toCity, dateOfJourney;
  final AuthSession authSession;
  const SeatBookingScreen({super.key, required this.train, required this.seatType,
    required this.fromCity, required this.toCity, required this.dateOfJourney, required this.authSession});
  @override
  State<SeatBookingScreen> createState() => _SeatBookingScreenState();
}
class _SeatBookingScreenState extends State<SeatBookingScreen> {
  SeatLayoutResponse? _layout;
  String? _error;
  bool _busy = false;
  bool _sms = false;
  final Set<SeatItem> _selected = {};
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _busy = true; _error = null; });
    try {
      if (widget.seatType.tripId == null || widget.seatType.tripRouteId == null) throw StateError('Missing trip information');
      final layout = await ApiService.fetchSeatLayout(tripId: widget.seatType.tripId!, tripRouteId: widget.seatType.tripRouteId!, authSession: widget.authSession);
      if (mounted) setState(() { _layout = layout; _selected.clear(); });
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _reserve() async {
    if (_busy || _selected.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      await context.read<MonitorService>().clearSearch();
      final state = await BookingService.reserve(train: widget.train, seat: widget.seatType,
        from: widget.fromCity, to: widget.toCity, date: widget.dateOfJourney,
        auth: widget.authSession, quantity: _selected.length, selectedSeats: _selected.toList());
      if (_sms) await OtpVerifier.listen();
      await NotificationService().showReservation(state);
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ReservationScreen()));
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.train.tripNumber)),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Text('${widget.fromCity} → ${widget.toCity} • ${widget.dateOfJourney}'),
      Text('${widget.seatType.displayName} • Fare ${widget.seatType.fare} BDT'),
      const Text('Select seats in one coach. Availability is checked again before reservation.'),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      for (final coach in _layout?.coaches ?? <CoachLayout>[]) ...[
        Padding(padding: const EdgeInsets.only(top: 16), child: Text('${coach.floorName} • ${coach.availableSeatsCount} available')),
        Wrap(spacing: 6, children: [for (final seat in coach.layout.expand((r) => r).where((s) => !s.isEmptySpace))
          FilterChip(label: Text(seat.seatNumber), selected: _selected.contains(seat),
            onSelected: _busy || !seat.isAvailable ? null : (v) => setState(() {
              if (!v) { _selected.remove(seat); return; }
              final coachIds = coach.layout.expand((r) => r).map((s) => s.ticketId).toSet();
              if (_selected.any((s) => !coachIds.contains(s.ticketId))) _selected.clear();
              if (_selected.length < AppConfig.instance.number('max_seats')) _selected.add(seat);
            })),
        ]),
      ],
      SwitchListTile(title: const Text('Verify railway SMS OTP automatically'), value: _sms,
        onChanged: (v) async { final allowed = v && await SmsService().requestSmsPermission(); if (mounted) setState(() => _sms = allowed); }),
      FilledButton(onPressed: _busy || _selected.isEmpty ? null : _reserve, child: Text('Reserve ${_selected.length} seat(s)')),
      TextButton(onPressed: _busy ? null : _load, child: const Text('Refresh seats')),
      TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReservationScreen())), child: const Text('View pending reservation')),
      OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingScreen(url:
        NotificationService.bookingUrl(widget.fromCity, widget.toCity, widget.dateOfJourney, widget.seatType.type)))), child: const Text('Book on the official Railway page')),
    ]),
  );
}
''',encoding='utf-8')

p=Path('lib/views/train_selection_screen.dart');s=p.read_text(encoding='utf-8')
s=s.replace("import 'recharge_credit_dialog.dart';", "import 'recharge_credit_dialog.dart';\nimport 'watch_options_dialog.dart';")
s=s.replace('    monitor.startMonitoring(','''    if (!context.mounted) return;
    final intent = await showWatchOptions(context, seatClass: seatClass);
    if (intent == null || !context.mounted) return;
    monitor.startMonitoring(
      intent: intent,''',1)
s=s.replace('    final seatType = train.seatTypes.firstWhere(\n      (s) => s.seatCounts.online > 0,\n      orElse: () => train.seatTypes.first,\n    );', '''    if (!context.mounted) return;
    final available = train.seatTypes.where((s) => s.isAvailable).toList();
    if (available.isEmpty) return;
    final seatType = await showDialog<SeatType>(context: context, builder: (ctx) => SimpleDialog(
      title: const Text('Choose seat class'), children: available.map((seat) => SimpleDialogOption(
        child: Text('${seat.displayName} • ${seat.seatCounts.online} seats • BDT ${seat.fare}'),
        onPressed: () => Navigator.pop(ctx, seat),
      )).toList(),
    ));
    if (seatType == null || !context.mounted) return;''')
p.write_text(s,encoding='utf-8')

p=Path('lib/services/notification_service.dart');s=p.read_text(encoding='utf-8')
s=s.replace("import '../views/booking_screen.dart';", "import '../views/booking_screen.dart';\nimport 'booking_service.dart';\nimport '../views/reservation_screen.dart';")
s=s.replace('  void openPendingBooking()', '''  Future<void> clearAlerts() async {
    _pendingBooking = null;
    if (_isInitialized) await _notificationsPlugin.cancelAll();
  }

  Future<void> showReservation(Map<String, dynamic> state) async {
    final expiry = DateTime.tryParse(state['expiresAt'] ?? '');
    final ready = state['status'] == 'readyForPayment';
    await _notificationsPlugin.show(
      id: 772,
      title: ready ? 'OTP verified • Purchase your ticket' : 'Seats reserved • Verify OTP',
      body: '${state['train']['trip_number']} • ${state['seatClass']['type']}',
      payload: ready ? BookingService.tripInfoUrl : 'rail://reservation',
      notificationDetails: NotificationDetails(android: AndroidNotificationDetails(
        'br_reservations', 'Reserved tickets', importance: Importance.max, priority: Priority.high,
        when: expiry?.millisecondsSinceEpoch,
        usesChronometer: expiry != null, chronometerCountDown: expiry != null,
        timeoutAfter: expiry == null ? null : expiry.difference(DateTime.now()).inMilliseconds.clamp(1, 3600000),
        actions: [AndroidNotificationAction('purchase', ready ? 'Purchase ticket' : 'Verify OTP', showsUserInterface: true)],
      ), iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true)),
    );
  }

  void openPendingBooking()''')
s=s.replace('    final uri = Uri.tryParse(payload);', '''    if (payload == 'rail://reservation') {
      final navigator = navigatorKey.currentState;
      if (navigator == null) { _pendingBooking = payload; return; }
      _pendingBooking = null;
      navigator.push(MaterialPageRoute(builder: (_) => const ReservationScreen()));
      return;
    }
    final uri = Uri.tryParse(payload);''')
s=s.replace("      ticker: 'Seat Alert',", "      ticker: 'Seat Alert',\n      actions: const [AndroidNotificationAction('book', 'Purchase ticket', showsUserInterface: true)],")
p.write_text(s,encoding='utf-8')

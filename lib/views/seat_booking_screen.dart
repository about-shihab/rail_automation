import 'package:flutter/material.dart';
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
import '../utils/app_theme.dart';
import '../widgets/turnstile_sheet.dart';
import 'booking_screen.dart';
import 'reservation_screen.dart';

class SeatBookingScreen extends StatefulWidget {
  final TrainTrip train;
  final SeatType seatType;
  final String fromCity, toCity, dateOfJourney;
  final AuthSession authSession;

  const SeatBookingScreen({
    super.key,
    required this.train,
    required this.seatType,
    required this.fromCity,
    required this.toCity,
    required this.dateOfJourney,
    required this.authSession,
  });

  @override
  State<SeatBookingScreen> createState() => _SeatBookingScreenState();
}

class _SeatBookingScreenState extends State<SeatBookingScreen> {
  SeatLayoutResponse? _layout;
  String? _error;
  String? _cftToken;
  bool _busy = false;
  bool _smsVerify = false;
  final Set<SeatItem> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? cftToken}) async {
    if (_busy) return;
    if (cftToken != null) _cftToken = cftToken;
    setState(() { _busy = true; _error = null; });
    try {
      if (widget.seatType.tripId == null || widget.seatType.tripRouteId == null) {
        throw StateError('Missing trip information');
      }
      final layout = await ApiService.fetchSeatLayout(
        tripId: widget.seatType.tripId!,
        tripRouteId: widget.seatType.tripRouteId!,
        authSession: widget.authSession,
        cftResponse: _cftToken,
      );
      if (mounted) setState(() { _layout = layout; _selected.clear(); });
    } catch (e) {
      final errStr = e.toString().replaceAll('Exception: ', '');
      if (errStr.contains('422') && cftToken == null && mounted) {
        setState(() => _busy = false);
        final token = await TurnstileSheet.show(context);
        if (token != null && token.isNotEmpty && mounted) {
          _cftToken = token;
          return _load(cftToken: token);
        }
      }
      if (mounted) setState(() => _error = errStr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyAndRetry() async {
    final token = await TurnstileSheet.show(context);
    if (token != null && token.isNotEmpty && mounted) {
      _load(cftToken: token);
    } else if (mounted) {
      _openOfficialBooking();
    }
  }

  void _openOfficialBooking() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingScreen(
          url: NotificationService.bookingUrl(
            widget.fromCity,
            widget.toCity,
            widget.dateOfJourney,
            widget.seatType.type,
          ),
        ),
      ),
    );
  }

  Future<void> _reserve() async {
    if (_busy || _selected.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      await context.read<MonitorService>().clearSearch();
      final state = await BookingService.reserve(
        train: widget.train,
        seat: widget.seatType,
        from: widget.fromCity,
        to: widget.toCity,
        date: widget.dateOfJourney,
        auth: widget.authSession,
        quantity: _selected.length,
        selectedSeats: _selected.toList(),
        autoVerify: _smsVerify,
        cftResponse: _cftToken,
      );
      if (_smsVerify) await OtpVerifier.listen();
      await NotificationService().showReservation(state);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ReservationScreen()),
        );
      }
    } catch (e) {
      final errStr = e.toString().replaceAll('StateError: ', '').replaceAll('Exception: ', '');
      if (errStr.contains('422') && mounted) {
        setState(() => _busy = false);
        final token = await TurnstileSheet.show(context);
        if (token != null && token.isNotEmpty && mounted) {
          _cftToken = token;
          return _reserve();
        }
      }
      if (mounted) setState(() => _error = errStr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxSeats = AppConfig.instance.number('max_seats');

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      appBar: GradientAppBar(
        title: widget.train.tripNumber,
        subtitle: '${widget.fromCity} → ${widget.toCity} • ${widget.dateOfJourney}',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Seat Class Info Bar ──────────────────────────────────────
          Container(
            color: AppColors.appBarGradientEnd,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                StatusBadge(
                  label: widget.seatType.displayName,
                  color: AppColors.primary,
                  icon: Icons.airline_seat_recline_extra_rounded,
                ),
                const SizedBox(width: 8),
                StatusBadge(
                  label: 'BDT ${widget.seatType.fare}',
                  color: AppColors.gold,
                  icon: Icons.currency_exchange_rounded,
                ),
                const Spacer(),
                if (_selected.isNotEmpty)
                  StatusBadge(
                    label: '${_selected.length} selected',
                    color: AppColors.info,
                    icon: Icons.check_circle_outline_rounded,
                  ),
              ],
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────
          Expanded(
            child: _busy && _layout == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                        ),
                        const SizedBox(height: 16),
                        Text('Loading seat layout...', style: TextStyle(color: AppColors.textSecondary(isDark))),
                      ],
                    ),
                  )
                : _error != null && _layout == null
                    ? _buildErrorState(isDark)
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Error banner
                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12))),
                                  ]),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (_error!.contains('422')) ...[
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                          icon: const Icon(Icons.shield_rounded, size: 14),
                                          label: const Text('Verify Security', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          onPressed: _verifyAndRetry,
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                        label: const Text('Open Official Page', style: TextStyle(fontSize: 12)),
                                        onPressed: _openOfficialBooking,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Instructions
                          AppCard(
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, color: AppColors.info, size: 18),
                                const SizedBox(width: 10),
                                Expanded(child: Text(
                                  'Select up to $maxSeats seats from one coach. Tap a seat to select it.',
                                  style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 13, height: 1.4),
                                )),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Coach layouts
                          for (final coach in _layout?.coaches ?? <CoachLayout>[]) ...[
                            _CoachCard(
                              coach: coach,
                              selected: _selected,
                              isDark: isDark,
                              maxSeats: maxSeats,
                              allCoachIds: coach.layout.expand((r) => r).map((s) => s.ticketId).toSet(),
                              onSeatTap: (seat) => setState(() {
                                if (_selected.contains(seat)) {
                                  _selected.remove(seat);
                                  return;
                                }
                                // Enforce single-coach rule
                                final coachIds = coach.layout.expand((r) => r).map((s) => s.ticketId).toSet();
                                if (_selected.any((s) => !coachIds.contains(s.ticketId))) _selected.clear();
                                if (_selected.length < maxSeats) _selected.add(seat);
                              }),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // SMS verify toggle
                          AppCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Auto-verify OTP via SMS', style: TextStyle(
                                        color: AppColors.textPrimary(isDark),
                                        fontWeight: FontWeight.bold, fontSize: 13,
                                      )),
                                      Text('Railway SMS is read and verified automatically',
                                        style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 11)),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _smsVerify,
                                  activeThumbColor: AppColors.primary,
                                  onChanged: (v) async {
                                    final ok = v && await SmsService().requestSmsPermission();
                                    if (mounted) setState(() => _smsVerify = ok);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Reserve Button
                          PrimaryButton(
                            label: _selected.isEmpty
                                ? 'Select Seats to Continue'
                                : 'Reserve ${_selected.length} Seat${_selected.length > 1 ? 's' : ''}',
                            icon: Icons.event_seat_rounded,
                            loading: _busy,
                            onPressed: _selected.isEmpty || _busy ? null : _reserve,
                          ),
                          const SizedBox(height: 10),

                          // Official site fallback
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textSecondary(isDark),
                                side: BorderSide(color: AppColors.cardBorder(isDark)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              icon: const Icon(Icons.open_in_new_rounded, size: 16),
                              label: const Text('Book on Official Railway Site', style: TextStyle(fontWeight: FontWeight.bold)),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => BookingScreen(
                                  url: NotificationService.bookingUrl(widget.fromCity, widget.toCity, widget.dateOfJourney, widget.seatType.type),
                                )),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    final is422 = _error?.contains('422') ?? false;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              is422 ? Icons.security_rounded : Icons.wifi_off_rounded,
              size: 64,
              color: is422 ? AppColors.primary : AppColors.error.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              is422 ? 'Railway Security Verification' : 'Failed to load seat layout',
              style: TextStyle(
                color: AppColors.textPrimary(isDark),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              is422
                  ? 'Railway requires a quick Cloudflare security check before displaying real-time seats.'
                  : (_error ?? ''),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 13),
            ),
            const SizedBox(height: 24),
            if (is422) ...[
              PrimaryButton(
                label: 'Verify with Security Check',
                icon: Icons.shield_rounded,
                onPressed: _verifyAndRetry,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open Official Booking Page'),
                onPressed: _openOfficialBooking,
              ),
            ] else ...[
              PrimaryButton(
                label: 'Try Again',
                icon: Icons.refresh_rounded,
                onPressed: () => _load(),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open Official Booking Page'),
                onPressed: _openOfficialBooking,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Coach Card ───────────────────────────────────────────────────────────────

class _CoachCard extends StatelessWidget {
  final CoachLayout coach;
  final Set<SeatItem> selected;
  final bool isDark;
  final int maxSeats;
  final Set<int> allCoachIds;
  final ValueChanged<SeatItem> onSeatTap;

  const _CoachCard({
    required this.coach,
    required this.selected,
    required this.isDark,
    required this.maxSeats,
    required this.allCoachIds,
    required this.onSeatTap,
  });

  @override
  Widget build(BuildContext context) {
    final seats = coach.layout.expand((r) => r).where((s) => !s.isEmptySpace).toList();
    final isCoachSelected = selected.any((s) => allCoachIds.contains(s.ticketId));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCoachSelected ? AppColors.primary.withValues(alpha: 0.5) : AppColors.cardBorder(isDark),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Coach header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isCoachSelected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.inputFill(isDark),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Coach ${coach.floorName}',
                    style: TextStyle(
                      color: isCoachSelected ? AppColors.primary : AppColors.textPrimary(isDark),
                      fontWeight: FontWeight.bold, fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${coach.availableSeatsCount} available',
                  style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 12)),
                const Spacer(),
                Text('Fare: BDT ${coach.seatFare}',
                  style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 11)),
              ],
            ),
          ),

          // Seats grid
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: seats.map((seat) {
                final isSelected = selected.contains(seat);
                final isAvailable = seat.isAvailable;
                final canSelect = isAvailable && (
                  isSelected ||
                  (selected.length < maxSeats &&
                    (selected.isEmpty || allCoachIds.containsAll(selected.map((s) => s.ticketId))))
                );

                Color bgColor;
                Color textColor;
                Color borderColor;

                if (isSelected) {
                  bgColor = AppColors.primary;
                  textColor = Colors.black87;
                  borderColor = AppColors.primary;
                } else if (!isAvailable) {
                  bgColor = AppColors.error.withValues(alpha: 0.08);
                  textColor = AppColors.textMuted(isDark);
                  borderColor = AppColors.error.withValues(alpha: 0.2);
                } else {
                  bgColor = AppColors.primary.withValues(alpha: 0.08);
                  textColor = AppColors.primary;
                  borderColor = AppColors.primary.withValues(alpha: 0.4);
                }

                return GestureDetector(
                  onTap: canSelect ? () => onSeatTap(seat) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(
                      seat.seatNumber,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Legend
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(
              children: [
                _LegendDot(color: AppColors.primary.withValues(alpha: 0.08), border: AppColors.primary.withValues(alpha: 0.4), label: 'Available'),
                const SizedBox(width: 12),
                _LegendDot(color: AppColors.primary, border: AppColors.primary, label: 'Selected', textColor: Colors.black87),
                const SizedBox(width: 12),
                _LegendDot(color: AppColors.error.withValues(alpha: 0.08), border: AppColors.error.withValues(alpha: 0.2), label: 'Booked'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final Color border;
  final String label;
  final Color? textColor;
  const _LegendDot({required this.color, required this.border, required this.label, this.textColor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(3),
            border: Border.all(color: border),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: textColor ?? AppColors.textMuted(isDark), fontSize: 11)),
      ],
    );
  }
}

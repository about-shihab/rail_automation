import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/auth_session.dart';
import '../models/seat_type.dart';
import '../models/train_trip.dart';
import '../services/intermediate_station_search.dart';
import '../services/language_service.dart';
import '../services/login_flow.dart';
import '../utils/app_theme.dart';
import '../utils/friendly_error.dart';
import 'seat_booking_screen.dart';
import 'train_selection_screen.dart';

class IntermediateStationScreen extends StatefulWidget {
  final TrainTrip train;
  final String from, to, date;
  final String? seatClass;

  const IntermediateStationScreen({
    super.key,
    required this.train,
    required this.from,
    required this.to,
    required this.date,
    this.seatClass,
  });

  @override
  State<IntermediateStationScreen> createState() =>
      _IntermediateStationScreenState();
}

class _IntermediateStationScreenState extends State<IntermediateStationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  AuthSession? _auth;
  bool _loading = true;
  String? _error;

  List<RouteStation> _routeStations = [];
  List<IntermediateJourney> _splitJourneys = [];

  // Matrix / Station-to-Station Explorer state
  RouteStation? _selectedFromStation;
  RouteStation? _selectedToStation;
  bool _checkingSegment = false;
  StationPairAvailability? _segmentResult;
  String? _segmentError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        _ensureRouteStationsLoaded();
      }
    });
    _initialize();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      _auth = await AuthSession.load();
      if (_auth == null) {
        throw StateError('Please log in to search intermediate stations.');
      }

      final results = await IntermediateStationSearch.search(
        train: widget.train,
        from: widget.from,
        to: widget.to,
        date: widget.date,
        auth: _auth!,
        seatClass: widget.seatClass,
        cancelled: () => !mounted,
      );
      if (mounted) {
        setState(() {
          _splitJourneys = results;
        });
      }
    } catch (e) {
      if (mounted) _error = friendlyErrorMessage(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ensureRouteStationsLoaded() async {
    if (_routeStations.isNotEmpty) return;
    try {
      final model = IntermediateStationSearch.extractTrainModel(widget.train);
      final stations = await IntermediateStationSearch.fetchTrainRouteStations(
        trainModel: model,
        departureDate: widget.date,
        auth: _auth,
      );
      if (mounted) {
        setState(() {
          _routeStations = stations;
          final startIdx =
              IntermediateStationSearch.findStationIndex(stations, widget.from);
          final endIdx =
              IntermediateStationSearch.findStationIndex(stations, widget.to);
          if (startIdx >= 0) _selectedFromStation = stations[startIdx];
          if (endIdx >= 0) _selectedToStation = stations[endIdx];
        });
      }
    } catch (_) {}
  }

  Future<void> _checkSelectedSegment() async {
    if (_selectedFromStation == null || _selectedToStation == null) return;
    if (_auth == null) {
      final loggedIn = await LoginFlow.openManualLogin();
      if (!loggedIn || !mounted) return;
      _auth = await AuthSession.load();
      if (_auth == null) return;
    }

    setState(() {
      _checkingSegment = true;
      _segmentError = null;
      _segmentResult = null;
    });

    try {
      final res = await IntermediateStationSearch.searchStationPair(
        from: _selectedFromStation!,
        to: _selectedToStation!,
        date: widget.date,
        targetTrain: widget.train,
        auth: _auth!,
        seatClass: widget.seatClass,
      );
      if (mounted) setState(() => _segmentResult = res);
    } catch (e) {
      if (mounted) setState(() => _segmentError = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _checkingSegment = false);
    }
  }

  void _openLeg(IntermediateJourney journey, bool first) {
    final train = first ? journey.first : journey.second;
    final seat = first ? journey.firstSeat : journey.secondSeat;
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrainSelectionScreen(
          searchResponse: TripSearchResponse(
            trains: [
              TrainTrip.fromJson({
                ...train.toJson(),
                'seat_types': [seat.toJson()],
              }),
            ],
          ),
          fromCity: first ? widget.from : journey.via,
          toCity: first ? journey.via : widget.to,
          dateOfJourney: first ? journey.firstDate : journey.secondDate,
          initialClass: journey.firstSeat.type,
        ),
      ),
    );
  }

  Future<void> _bookLegDirect(TrainTrip legTrain, SeatType seat, String legFrom, String legTo, String legDate) async {
    HapticFeedback.selectionClick();
    var auth = _auth ?? await AuthSession.load();
    if (auth == null || !auth.isLoggedIn) {
      final success = await LoginFlow.openManualLogin();
      if (!success) return;
      auth = await AuthSession.load();
      if (auth == null) return;
    }
    _auth = auth;

    final readyTrain = TrainTrip.fromJson({
      ...legTrain.toJson(),
      'boarding_points': legTrain.boardingPoints.isNotEmpty
          ? legTrain.boardingPoints.map((e) => e.toJson()).toList()
          : [
              BoardingPoint(
                locationName: legFrom,
                locationTime: legTrain.departureDateTime,
                locationDate: legDate,
              ).toJson(),
            ],
    });

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeatBookingScreen(
          train: readyTrain,
          seatType: seat,
          fromCity: legFrom,
          toCity: legTo,
          dateOfJourney: legDate,
          authSession: auth!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = context.watch<LanguageService>();

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(isDark),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.train.tripNumber,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              '${widget.from} → ${widget.to} · ${widget.date}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            Tab(
              icon: const Icon(Icons.alt_route_rounded, size: 20),
              text: lang.tr('Split Tickets', 'ব্রেক জার্নি'),
            ),
            Tab(
              icon: const Icon(Icons.grid_view_rounded, size: 20),
              text: lang.tr('Route Matrix', 'স্টেশন রুট ও আসন'),
            ),
          ],
        ),
      ),
      body: _loading
          ? _buildLoadingView(isDark, lang)
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSplitJourneyTab(isDark, lang),
                _buildMatrixTab(isDark, lang),
              ],
            ),
    );
  }

  Widget _buildLoadingView(bool isDark, LanguageService lang) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 20),
            Text(
              lang.tr(
                'Searching between-station availability…',
                'মধ্যবর্তী স্টেশনের আসন খোঁজা হচ্ছে…',
              ),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppColors.textPrimary(isDark),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              lang.tr(
                'Checking intermediate route stops on ${widget.train.tripNumber}',
                '${widget.train.tripNumber} এর সব স্টেশনের আসন যাচাই করা হচ্ছে',
              ),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted(isDark),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitJourneyTab(bool isDark, LanguageService lang) {
    if (_auth == null) {
      return _buildLoginRequiredCard(isDark, lang);
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.warning, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: AppColors.textPrimary(isDark), fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _initialize,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(lang.tr('Retry Search', 'আবার খুঁজুন')),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Informational banner
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  lang.tr(
                    'Each option needs two separate tickets on the same train. You may need to change seats at the intermediate station. Availability can change; buying one ticket does not guarantee the other.',
                    'প্রতিটি বিকল্পে একই ট্রেনের দুটি আলাদা টিকিট লাগবে। মধ্যবর্তী স্টেশনে আসন বদলাতে হতে পারে। আসন পরিবর্তন হতে পারে; একটি টিকিট কিনলে অন্যটি নিশ্চিত হয় না।',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textPrimary(isDark),
                  ),
                ),
              ),
            ],
          ),
        ),

        if (_splitJourneys.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.cardBg(isDark),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.cardBorder(isDark)),
            ),
            child: Column(
              children: [
                Icon(Icons.alt_route_rounded, size: 54, color: AppColors.textMuted(isDark)),
                const SizedBox(height: 14),
                Text(
                  lang.tr(
                    'No two-ticket journey is available through an intermediate station in this class. Try another train or class.',
                    'এই শ্রেণিতে মধ্যবর্তী স্টেশন হয়ে দুই টিকিটের যাত্রা পাওয়া যায়নি। অন্য ট্রেন বা শ্রেণি চেষ্টা করুন।',
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.textPrimary(isDark),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  lang.tr(
                    'Try checking individual station pairs or quota hopping in the Route Matrix tab.',
                    'স্টেশন রুট ট্যাবে গিয়ে যেকোনো নির্দিষ্ট স্টেশনের টিকিট দেখতে পারেন।',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted(isDark),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => _tabController.animateTo(1),
                  child: Text(lang.tr('Open Route Matrix', 'রুট ম্যাট্রিক্স দেখুন')),
                ),
              ],
            ),
          )
        else
          ..._splitJourneys.map((journey) => _buildSplitJourneyCard(journey, isDark, lang)),
      ],
    );
  }

  Widget _buildSplitJourneyCard(IntermediateJourney journey, bool isDark, LanguageService lang) {
    final fare1 = double.tryParse(journey.firstSeat.fare) ?? 0.0;
    final fare2 = double.tryParse(journey.secondSeat.fare) ?? 0.0;
    final totalFare = fare1 + fare2;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(isDark),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder(isDark)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: From -> Via -> To
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.from} → ${journey.via} → ${widget.to}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.textPrimary(isDark),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${journey.seats} ${lang.tr('seats on both legs', 'আসন দুই অংশে')}',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Class badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                journey.firstSeat.displayName,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),

            const Divider(height: 24),

            // Leg 1 details
            _buildLegSection(
              sectionHeader: '${lang.tr('Leg 1', '১ম অংশ')}: ${widget.from} → ${journey.via}',
              buttonTitle: '${lang.tr('View leg 1', 'প্রথম অংশ দেখুন')}: ${widget.from} → ${journey.via}',
              date: journey.firstDate,
              depTime: journey.first.departureDateTime,
              arrTime: journey.first.arrivalDateTime,
              legTrain: journey.first,
              seat: journey.firstSeat,
              legFrom: widget.from,
              legTo: journey.via,
              onView: () => _openLeg(journey, true),
              isDark: isDark,
              lang: lang,
            ),

            const SizedBox(height: 12),

            // Leg 2 details
            _buildLegSection(
              sectionHeader: '${lang.tr('Leg 2', '২য় অংশ')}: ${journey.via} → ${widget.to}',
              buttonTitle: '${lang.tr('View leg 2', 'দ্বিতীয় অংশ দেখুন')}: ${journey.via} → ${widget.to}',
              date: journey.secondDate,
              depTime: journey.second.departureDateTime,
              arrTime: journey.second.arrivalDateTime,
              legTrain: journey.second,
              seat: journey.secondSeat,
              legFrom: journey.via,
              legTo: widget.to,
              onView: () => _openLeg(journey, false),
              isDark: isDark,
              lang: lang,
            ),

            const Divider(height: 24),

            // Fare and Summary
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lang.tr('Base fares', 'মূল ভাড়া'),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted(isDark),
                      ),
                    ),
                    Text(
                      '৳${totalFare.toStringAsFixed(0)} (৳${journey.firstSeat.fare} + ৳${journey.secondSeat.fare})',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary(isDark),
                      ),
                    ),
                  ],
                ),
                Text(
                  lang.tr('Via transfer at ${journey.via}', '${journey.via}-এ বদল'),
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textMuted(isDark),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegSection({
    required String sectionHeader,
    required String buttonTitle,
    required String date,
    required String depTime,
    required String arrTime,
    required TrainTrip legTrain,
    required SeatType seat,
    required String legFrom,
    required String legTo,
    required VoidCallback onView,
    required bool isDark,
    required LanguageService lang,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  sectionHeader,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textPrimary(isDark),
                  ),
                ),
              ),
              Text(
                date,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted(isDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                depTime.isNotEmpty ? depTime : '—',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              Text('  →  ', style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 11)),
              Text(
                arrTime.isNotEmpty ? arrTime : '—',
                style: TextStyle(color: AppColors.textSecondary(isDark), fontSize: 12),
              ),
              const Spacer(),
              Text(
                '৳${seat.fare}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onView,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  ),
                  child: Text(buttonTitle, style: const TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _bookLegDirect(legTrain, seat, legFrom, legTo, date),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                ),
                icon: const Icon(Icons.event_seat_rounded, size: 14),
                label: Text(
                  '${lang.tr('Book', 'বুক')} (${seat.type})',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMatrixTab(bool isDark, LanguageService lang) {
    if (_routeStations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                lang.tr(
                  'Loading route stops for ${widget.train.tripNumber}…',
                  '${widget.train.tripNumber} এর স্টেশন তালিকা লোড হচ্ছে…',
                ),
                style: TextStyle(color: AppColors.textMuted(isDark), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Interactive Segment Checker Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBg(isDark),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.cardBorder(isDark)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.hub_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    lang.tr('Between-Station Checker', 'স্টেশন থেকে স্টেশন যাচাই'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.textPrimary(isDark),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                lang.tr(
                  'Select any two stations on this train to check seat availability.',
                  'এই ট্রেনের যেকোনো দুটি স্টেশন বাছাই করে আসন সংখ্যা যাচাই করুন।',
                ),
                style: TextStyle(fontSize: 12, color: AppColors.textMuted(isDark)),
              ),
              const SizedBox(height: 16),

              // From dropdown
              _buildStationDropdown(
                label: lang.tr('From (Boarding)', 'যাত্রার স্টেশন'),
                selected: _selectedFromStation,
                stations: _routeStations,
                isDark: isDark,
                onChanged: (st) => setState(() => _selectedFromStation = st),
              ),
              const SizedBox(height: 12),

              // To dropdown
              _buildStationDropdown(
                label: lang.tr('To (Destination)', 'গন্তব্য স্টেশন'),
                selected: _selectedToStation,
                stations: _routeStations,
                isDark: isDark,
                onChanged: (st) => setState(() => _selectedToStation = st),
              ),
              const SizedBox(height: 16),

              // Check button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _checkingSegment ? null : _checkSelectedSegment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _checkingSegment
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.search_rounded),
                  label: Text(
                    lang.tr('Check Seats', 'আসন পরীক্ষা করুন'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),

              // Segment result display
              if (_segmentResult != null) ...[
                const SizedBox(height: 16),
                _buildSegmentResultCard(_segmentResult!, isDark, lang),
              ] else if (_segmentError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _segmentError!,
                  style: const TextStyle(color: AppColors.warning, fontSize: 12),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Route Station Stops List
        Text(
          lang.tr('Complete Train Route Stops', 'ট্রেনের সকল স্টপের সময়সূচি'),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: AppColors.textPrimary(isDark),
          ),
        ),
        const SizedBox(height: 10),

        ..._routeStations.map((station) {
          final isUserStart = _selectedFromStation?.city == station.city;
          final isUserEnd = _selectedToStation?.city == station.city;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isUserStart || isUserEnd
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.cardBg(isDark),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isUserStart || isUserEnd
                    ? AppColors.primary
                    : AppColors.cardBorder(isDark),
                width: isUserStart || isUserEnd ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: isUserStart || isUserEnd
                      ? AppColors.primary
                      : AppColors.cardBorder(isDark),
                  child: Text(
                    '${station.sequence + 1}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isUserStart || isUserEnd ? Colors.white : AppColors.textMuted(isDark),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.textPrimary(isDark),
                        ),
                      ),
                      if (station.haltTime.isNotEmpty) ...[
                        Text(
                          '${lang.tr('Halt', 'যাত্রাবিরতি')}: ${station.haltTime}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted(isDark),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (station.arrivalTime.isNotEmpty)
                      Text(
                        '${lang.tr('Arr', 'পৌঁছাবে')}: ${station.arrivalTime}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary(isDark),
                        ),
                      ),
                    if (station.departureTime.isNotEmpty)
                      Text(
                        '${lang.tr('Dep', 'ছাড়বে')}: ${station.departureTime}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStationDropdown({
    required String label,
    required RouteStation? selected,
    required List<RouteStation> stations,
    required bool isDark,
    required ValueChanged<RouteStation?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary(isDark),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkInput : AppColors.lightInput,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.cardBorder(isDark)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<RouteStation>(
              value: selected,
              isExpanded: true,
              dropdownColor: AppColors.cardBg(isDark),
              items: stations.map((st) {
                return DropdownMenuItem<RouteStation>(
                  value: st,
                  child: Text(
                    '${st.sequence + 1}. ${st.name}',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary(isDark),
                    ),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentResultCard(StationPairAvailability res, bool isDark, LanguageService lang) {
    if (!res.hasSeats || res.train == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_seat_rounded, color: AppColors.warning, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                lang.tr(
                  'No seats available between ${res.from.name} and ${res.to.name} for this train.',
                  '${res.from.name} থেকে ${res.to.name}-এ এই ট্রেনে কোনো আসন খালি নেই।',
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary(isDark),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${res.from.name} → ${res.to.name}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.textPrimary(isDark),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${res.totalSeats} ${lang.tr('Seats Available', 'আসন আছে')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: res.seatTypes.map((seat) {
              return ActionChip(
                backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                label: Text(
                  '${seat.type} (${seat.seatCounts.online}) · ৳${seat.fare}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AppColors.primary,
                  ),
                ),
                onPressed: () {
                  if (_auth == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SeatBookingScreen(
                        train: res.train!,
                        seatType: seat,
                        fromCity: res.from.city,
                        toCity: res.to.city,
                        dateOfJourney: widget.date,
                        authSession: _auth!,
                      ),
                    ),
                  );
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginRequiredCard(bool isDark, LanguageService lang) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.cardBg(isDark),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.cardBorder(isDark)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_person_rounded, size: 48, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                lang.tr(
                  'Railway Account Login Required',
                  'রেলওয়ে অ্যাকাউন্টে লগইন প্রয়োজন',
                ),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.textPrimary(isDark),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                lang.tr(
                  'Please sign in to your Bangladesh Railway account to check live intermediate seat availability and book split tickets.',
                  'লাইভ মধ্যবর্তী স্টেশনের আসন দেখা ও ব্রেক জার্নি টিকিট কাটার জন্য আপনার রেলওয়ে অ্যাকাউন্টে লগইন করুন।',
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(isDark),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  final ok = await LoginFlow.openManualLogin();
                  if (ok && mounted) {
                    _initialize();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.login_rounded),
                label: Text(lang.tr('Log in via Railway', 'রেলওয়েতে লগইন করুন')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

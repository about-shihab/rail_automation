import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/auth_session.dart';
import '../models/train_trip.dart';
import '../services/intermediate_station_search.dart';
import '../services/language_service.dart';
import '../utils/friendly_error.dart';
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

class _IntermediateStationScreenState extends State<IntermediateStationScreen> {
  List<IntermediateJourney> _results = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = await AuthSession.load();
      if (auth == null) {
        throw StateError('Please log in to search intermediate stations.');
      }
      final results = await IntermediateStationSearch.search(
        train: widget.train,
        from: widget.from,
        to: widget.to,
        date: widget.date,
        auth: auth,
        seatClass: widget.seatClass,
        cancelled: () => !mounted,
      );
      if (mounted) setState(() => _results = results);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openLeg(IntermediateJourney journey, bool first) {
    final train = first ? journey.first : journey.second;
    final seat = first ? journey.firstSeat : journey.secondSeat;
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

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(lang.tr('Intermediate stations', 'মধ্যবর্তী স্টেশন')),
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    lang.tr(
                      'Checking both legs on this train…',
                      'এই ট্রেনের দুই অংশে আসন খোঁজা হচ্ছে…',
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.train.tripNumber,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text('${widget.from} → ${widget.to} · ${widget.date}'),
                const SizedBox(height: 12),
                Text(
                  lang.tr(
                    'Each option needs two separate tickets on the same train. You may need to change seats at the intermediate station. Availability can change; buying one ticket does not guarantee the other.',
                    'প্রতিটি বিকল্পে একই ট্রেনের দুটি আলাদা টিকিট লাগবে। মধ্যবর্তী স্টেশনে আসন বদলাতে হতে পারে। আসন পরিবর্তন হতে পারে; একটি টিকিট কিনলে অন্যটি নিশ্চিত হয় না।',
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Text(_error!),
                  TextButton(
                    onPressed: _search,
                    child: Text(lang.tr('Try again', 'আবার চেষ্টা করুন')),
                  ),
                ] else if (_results.isEmpty)
                  Text(
                    lang.tr(
                      'No two-ticket journey is available through an intermediate station in this class. Try another train or class.',
                      'এই শ্রেণিতে মধ্যবর্তী স্টেশন হয়ে দুই টিকিটের যাত্রা পাওয়া যায়নি। অন্য ট্রেন বা শ্রেণি চেষ্টা করুন।',
                    ),
                  ),
                ..._results.map(
                  (journey) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.from} → ${journey.via} → ${widget.to}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${journey.firstSeat.displayName} · ${journey.seats} ${lang.tr('seats on both legs', 'আসন দুই অংশে')}',
                          ),
                          Text('${journey.firstDate} / ${journey.secondDate}'),
                          const SizedBox(height: 8),
                          Text(
                            '${lang.tr('Base fares', 'মূল ভাড়া')}: ৳${journey.firstSeat.fare} + ৳${journey.secondSeat.fare}',
                          ),
                          TextButton(
                            onPressed: () => _openLeg(journey, true),
                            child: Text(
                              '${lang.tr('View leg 1', 'প্রথম অংশ দেখুন')}: ${widget.from} → ${journey.via}',
                            ),
                          ),
                          TextButton(
                            onPressed: () => _openLeg(journey, false),
                            child: Text(
                              '${lang.tr('View leg 2', 'দ্বিতীয় অংশ দেখুন')}: ${journey.via} → ${widget.to}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

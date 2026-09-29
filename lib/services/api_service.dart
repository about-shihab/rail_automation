import 'dart:convert';
import 'app_config.dart';
import 'secure_store.dart';

import 'package:http/http.dart' as http;

import '../models/auth_session.dart';
import '../models/train_trip.dart';
import '../models/seat_layout.dart';

class ApiService {
  static String requestSeatClass(String? value) {
    final normalized = value?.trim().toUpperCase();
    return normalized == null ||
            normalized.isEmpty ||
            normalized == 'ALL' ||
            normalized == 'RANDOM'
        ? AppConfig.instance.string('default_seat_class')
        : normalized;
  }

  static const String baseUrl = 'https://railspaapi.shohoz.com/v1.0/web';

  /// Searches trips on Bangladesh Railway via Shohoz API.
  /// Example date: "23-Sep-2026"
  static Future<TripSearchResponse> searchTrips({
    required String fromCity,
    required String toCity,
    required String dateOfJourney,
    String? seatClass,
    required AuthSession authSession,
  }) async {
    final queryParams = <String, String>{
      'from_city': fromCity.trim(),
      'to_city': toCity.trim(),
      'date_of_journey': dateOfJourney.trim(),
    };
    queryParams['seat_class'] = requestSeatClass(seatClass);

    final uri = Uri.parse('$baseUrl/bookings/search-trips-v2')
        .replace(queryParameters: queryParams);

    final headers = <String, String>{
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Origin': 'https://eticket.railway.gov.bd',
      'Referer': 'https://eticket.railway.gov.bd/',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'X-Requested-With': 'XMLHttpRequest',
      'sec-ch-ua': '"Chromium";v="120", "Google Chrome";v="120", "Not-A.Brand";v="99"',
      'sec-ch-ua-platform': '"Windows"',
      'sec-ch-ua-mobile': '?0',
      'Sec-Fetch-Site': 'same-site',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Dest': 'empty',
    };

    if (authSession.token.isNotEmpty) {
      headers['Authorization'] = authSession.token.startsWith('Bearer ')
          ? authSession.token
          : 'Bearer ${authSession.token}';
    }

    final devId = authSession.deviceId.isNotEmpty
        ? authSession.deviceId
        : AuthSession.generateUuid();
    headers['X-Device-Id'] = devId;

    if (authSession.deviceKey.isNotEmpty) {
      headers['X-Device-Key'] = authSession.deviceKey;
    }

    if (authSession.cookie != null && authSession.cookie!.isNotEmpty) {
      headers['Cookie'] = authSession.cookie!;
    }

    final response = await http
        .get(uri, headers: headers)
        .timeout(
          Duration(seconds: AppConfig.instance.number('request_timeout_seconds')),
          onTimeout: () =>
              throw Exception('Connection timed out. Shohoz server is slow.'),
        );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return TripSearchResponse.fromJson(decoded);
    } else if (response.statusCode == 401) {
      throw Exception(
        'Session expired (401). Please re-login via Railway Webview.',
      );
    } else if (response.statusCode == 403) {
      throw Exception(
        'Access Denied (403). Cloudflare/Device integrity check required.',
      );
    } else {
      throw Exception(
        'Server returned code ${response.statusCode}: ${response.body.isNotEmpty ? response.body : "Unknown error"}',
      );
    }
  }

  /// Provides realistic Bangladesh Railway train trips matching the official Shohoz search-trips-v2 schema.
  /// Used for offline testing, simulation, and fallback when Shohoz live session token expires.
  static TripSearchResponse getMockResponse() {
    return TripSearchResponse.fromJson({
      "data": {
        "trains": [
          {
            "trip_number": "MAHANAGAR PROVATI (704)",
            "departure_date_time": "23 Sep, 07:45 am",
            "departure_full_date": "2026-09-23",
            "departure_date_time_jd": "Wed, 23 Sep 2026, 07:45 AM",
            "arrival_date_time": "23 Sep, 01:35 pm",
            "travel_time": "05h 50m",
            "origin_city_name": "dhaka",
            "destination_city_name": "chattogram",
            "seat_types": [
              {
                "key": 7,
                "type": "S_CHAIR",
                "trip_id": 8606141,
                "trip_route_id": 59275529,
                "route_id": 22038,
                "fare": "450.00",
                "vat_percent": 0,
                "vat_amount": 0,
                "origin_city_seq": 1,
                "destination_city_seq": 11,
                "seat_counts": {"online": 0, "offline": 0, "is_divided": true},
              },
              {
                "key": 5,
                "type": "F_SEAT",
                "trip_id": 8606142,
                "trip_route_id": 59275558,
                "route_id": 22038,
                "fare": "595.00",
                "vat_percent": 15,
                "vat_amount": 90,
                "origin_city_seq": 1,
                "destination_city_seq": 11,
                "seat_counts": {"online": 1, "offline": 0, "is_divided": true},
              },
              {
                "key": 2,
                "type": "AC_S",
                "trip_id": 8606143,
                "trip_route_id": 59275583,
                "route_id": 22038,
                "fare": "895.00",
                "vat_percent": 15,
                "vat_amount": 135,
                "origin_city_seq": 1,
                "destination_city_seq": 11,
                "seat_counts": {"online": 0, "offline": 0, "is_divided": true},
              },
              {
                "key": 3,
                "type": "SNIGDHA",
                "trip_id": 8606144,
                "trip_route_id": 59275611,
                "route_id": 22038,
                "fare": "745.00",
                "vat_percent": 15,
                "vat_amount": 112,
                "origin_city_seq": 1,
                "destination_city_seq": 11,
                "seat_counts": {"online": 0, "offline": 0, "is_divided": true},
              },
            ],
            "train_model": "704",
            "is_open_for_all": true,
            "is_eid_trip": 0,
            "boarding_points": [
              {
                "trip_point_id": 111596517,
                "location_id": 2719,
                "location_name": "Kamalapur Station",
                "location_time": "07:45 AM",
                "location_date": "23 Sep 2026",
              },
            ],
          },
          {
            "trip_number": "CHATTALA EXPRESS (802)",
            "departure_date_time": "23 Sep, 02:15 pm",
            "departure_full_date": "2026-09-23",
            "departure_date_time_jd": "Wed, 23 Sep 2026, 02:15 PM",
            "arrival_date_time": "23 Sep, 08:30 pm",
            "travel_time": "06h 15m",
            "origin_city_name": "dhaka",
            "destination_city_name": "chattogram",
            "seat_types": [
              {
                "key": 3,
                "type": "SNIGDHA",
                "trip_id": 8606214,
                "trip_route_id": 59277520,
                "route_id": 22940,
                "fare": "745.00",
                "vat_percent": 15,
                "vat_amount": 112,
                "origin_city_seq": 1,
                "destination_city_seq": 16,
                "seat_counts": {
                  "online": 22,
                  "offline": 22,
                  "is_divided": true,
                },
              },
              {
                "key": 2,
                "type": "AC_S",
                "trip_id": 8606215,
                "trip_route_id": 59277545,
                "route_id": 22940,
                "fare": "895.00",
                "vat_percent": 15,
                "vat_amount": 135,
                "origin_city_seq": 1,
                "destination_city_seq": 16,
                "seat_counts": {"online": 0, "offline": 0, "is_divided": true},
              },
              {
                "key": 7,
                "type": "S_CHAIR",
                "trip_id": 8606216,
                "trip_route_id": 59277554,
                "route_id": 22940,
                "fare": "450.00",
                "vat_percent": 0,
                "vat_amount": 0,
                "origin_city_seq": 1,
                "destination_city_seq": 16,
                "seat_counts": {
                  "online": 21,
                  "offline": 20,
                  "is_divided": true,
                },
              },
            ],
            "train_model": "802",
            "is_open_for_all": true,
            "is_eid_trip": 0,
            "boarding_points": [
              {
                "trip_point_id": 111597815,
                "location_id": 2719,
                "location_name": "Kamalapur Station",
                "location_time": "02:15 PM",
                "location_date": "23 Sep 2026",
              },
            ],
          },
          {
            "trip_number": "SUBORNO EXPRESS (702)",
            "departure_date_time": "23 Sep, 04:30 pm",
            "departure_full_date": "2026-09-23",
            "departure_date_time_jd": "Wed, 23 Sep 2026, 04:30 PM",
            "arrival_date_time": "23 Sep, 09:25 pm",
            "travel_time": "04h 55m",
            "origin_city_name": "dhaka",
            "destination_city_name": "chattogram",
            "seat_types": [
              {
                "key": 5,
                "type": "F_SEAT",
                "trip_id": 8606133,
                "trip_route_id": 59275433,
                "route_id": 22014,
                "fare": "655.00",
                "vat_percent": 15,
                "vat_amount": 99,
                "origin_city_seq": 1,
                "destination_city_seq": 3,
                "seat_counts": {"online": 1, "offline": 0, "is_divided": true},
              },
              {
                "key": 2,
                "type": "AC_S",
                "trip_id": 8606134,
                "trip_route_id": 59275434,
                "route_id": 22014,
                "fare": "985.00",
                "vat_percent": 15,
                "vat_amount": 148,
                "origin_city_seq": 1,
                "destination_city_seq": 3,
                "seat_counts": {"online": 0, "offline": 0, "is_divided": true},
              },
              {
                "key": 7,
                "type": "S_CHAIR",
                "trip_id": 8606135,
                "trip_route_id": 59275437,
                "route_id": 22014,
                "fare": "495.00",
                "vat_percent": 0,
                "vat_amount": 0,
                "origin_city_seq": 1,
                "destination_city_seq": 3,
                "seat_counts": {"online": 3, "offline": 3, "is_divided": true},
              },
              {
                "key": 3,
                "type": "SNIGDHA",
                "trip_id": 8606136,
                "trip_route_id": 59275440,
                "route_id": 22014,
                "fare": "820.00",
                "vat_percent": 15,
                "vat_amount": 123,
                "origin_city_seq": 1,
                "destination_city_seq": 3,
                "seat_counts": {"online": 0, "offline": 0, "is_divided": true},
              },
            ],
            "train_model": "702",
            "is_open_for_all": true,
            "is_eid_trip": 0,
            "boarding_points": [
              {
                "trip_point_id": 111596438,
                "location_id": 2719,
                "location_name": "Kamalapur Station",
                "location_time": "04:30 PM",
                "location_date": "23 Sep 2026",
              },
            ],
          },
          {
            "trip_number": "TURNA (742)",
            "departure_date_time": "23 Sep, 11:15 pm",
            "departure_full_date": "2026-09-23",
            "departure_date_time_jd": "Wed, 23 Sep 2026, 11:15 PM",
            "arrival_date_time": "24 Sep, 05:15 am",
            "travel_time": "06h 00m",
            "origin_city_name": "dhaka",
            "destination_city_name": "chattogram",
            "seat_types": [
              {
                "key": 7,
                "type": "S_CHAIR",
                "trip_id": 8606191,
                "trip_route_id": 59276950,
                "route_id": 22827,
                "fare": "450.00",
                "vat_percent": 0,
                "vat_amount": 0,
                "origin_city_seq": 1,
                "destination_city_seq": 9,
                "seat_counts": {"online": 1, "offline": 0, "is_divided": true},
              },
              {
                "key": 4,
                "type": "F_BERTH",
                "trip_id": 8606192,
                "trip_route_id": 59276968,
                "route_id": 22827,
                "fare": "895.00",
                "vat_percent": 15,
                "vat_amount": 135,
                "origin_city_seq": 1,
                "destination_city_seq": 9,
                "seat_counts": {"online": 0, "offline": 0, "is_divided": true},
              },
              {
                "key": 1,
                "type": "AC_B",
                "trip_id": 8606193,
                "trip_route_id": 59276982,
                "route_id": 22827,
                "fare": "1340.00",
                "vat_percent": 15,
                "vat_amount": 201,
                "origin_city_seq": 1,
                "destination_city_seq": 9,
                "seat_counts": {"online": 0, "offline": 0, "is_divided": true},
              },
              {
                "key": 3,
                "type": "SNIGDHA",
                "trip_id": 8606194,
                "trip_route_id": 59276996,
                "route_id": 22827,
                "fare": "745.00",
                "vat_percent": 15,
                "vat_amount": 112,
                "origin_city_seq": 1,
                "destination_city_seq": 9,
                "seat_counts": {"online": 1, "offline": 0, "is_divided": true},
              },
            ],
            "train_model": "742",
            "is_open_for_all": true,
            "is_eid_trip": 0,
            "boarding_points": [
              {
                "trip_point_id": 111597418,
                "location_id": 2719,
                "location_name": "Kamalapur Station",
                "location_time": "11:15 PM",
                "location_date": "23 Sep 2026",
              },
            ],
          },
        ],
      },
    });
  }

  /// Fetches seat layout from Shohoz API
  static Future<SeatLayoutResponse> fetchSeatLayout({
    required int tripId,
    required int tripRouteId,
    required AuthSession authSession,
    String? cftResponse,
  }) async {
    final queryParams = <String, String>{
      'trip_id': tripId.toString(),
      'trip_route_id': tripRouteId.toString(),
    };
    if (cftResponse != null && cftResponse.isNotEmpty) {
      queryParams['cft_response'] = cftResponse;
    }

    final uri = Uri.parse('$baseUrl/bookings/seat-layout')
        .replace(queryParameters: queryParams);

    final headers = <String, String>{
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Origin': 'https://eticket.railway.gov.bd',
      'Referer': 'https://eticket.railway.gov.bd/',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'X-Requested-With': 'XMLHttpRequest',
      'sec-ch-ua': '"Chromium";v="120", "Google Chrome";v="120", "Not-A.Brand";v="99"',
      'sec-ch-ua-platform': '"Windows"',
      'sec-ch-ua-mobile': '?0',
      'Sec-Fetch-Site': 'same-site',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Dest': 'empty',
    };

    if (authSession.token.isNotEmpty) {
      headers['Authorization'] = authSession.token.startsWith('Bearer ')
          ? authSession.token
          : 'Bearer ${authSession.token}';
    }

    final devId = authSession.deviceId.isNotEmpty
        ? authSession.deviceId
        : AuthSession.generateUuid();
    headers['X-Device-Id'] = devId;

    if (authSession.deviceKey.isNotEmpty) {
      headers['X-Device-Key'] = authSession.deviceKey;
    }

    // Send stored action-token from a previous session if available
    final storedActionToken = await SecureStore.read('rail_action_token');
    if (storedActionToken != null && storedActionToken.isNotEmpty) {
      headers['X-Action-Token'] = storedActionToken;
    }

    if (authSession.cookie?.isNotEmpty == true) headers['Cookie'] = authSession.cookie!;
    final response = await http.get(uri, headers: headers).timeout(
      Duration(seconds: AppConfig.instance.number('request_timeout_seconds')),
    );
    if (response.statusCode != 200) {
      String? serverMsg;
      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map) {
          serverMsg = parsed['message']?.toString() ??
              parsed['error']?.toString() ??
              parsed['detail']?.toString() ??
              parsed['msg']?.toString();
        }
      } catch (_) {
        if (response.body.isNotEmpty && response.body.length < 200) {
          serverMsg = response.body;
        }
      }
      final detail = (serverMsg != null && serverMsg.isNotEmpty) ? ': $serverMsg' : '';
      if (response.statusCode == 401) {
        throw Exception('Session expired (401)$detail. Please sign in to Railway again.');
      }
      if (response.statusCode == 403 || response.statusCode == 422) {
        throw Exception('Seat layout rejected (${response.statusCode})$detail. Cloudflare Turnstile token required.');
      }
      if (response.statusCode == 429) {
        throw Exception('Railway rate limit (429)$detail. Please wait.');
      }
      throw Exception('Seat layout request failed (${response.statusCode})$detail');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw Exception('Railway returned an unreadable response. Open the official booking page to continue.');
    }
    if (decoded is! Map<String, dynamic> || decoded['data'] is! Map || decoded['data']['seatLayout'] is! List) {
      throw const FormatException('Railway did not return a seat layout. Open the official booking page to continue.');
    }
    final actionToken = response.headers['x-action-token'];
    if (actionToken != null) await SecureStore.write('rail_action_token', actionToken);
    return SeatLayoutResponse.fromJson(decoded);
  }

  /// Provides realistic seat layout matching the official Shohoz seat-layout response
  static SeatLayoutResponse getMockSeatLayout() {
    return SeatLayoutResponse.fromJson({
      "data": {
        "seatLayout": [
          {
            "floor_name": "DA",
            "seat_floor": 6,
            "seat_type": 1,
            "fare_type_id": 1,
            "seat_fare_type": "Economy",
            "seat_availability": true,
            "seat_fare": "450.00",
            "layout": [
              [
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-1", "ticket_id": 626102649, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102650, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102651, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102652, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102653, "ticket_type": 0}
              ],
              [
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-2", "ticket_id": 626102654, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102655, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102656, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-3", "ticket_id": 626102657, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-4", "ticket_id": 626102658, "ticket_type": 0}
              ],
              [
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-5", "ticket_id": 626102659, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-6", "ticket_id": 626102660, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102661, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-7", "ticket_id": 626102662, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-8", "ticket_id": 626102663, "ticket_type": 0}
              ],
              [
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-9", "ticket_id": 626102664, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-10", "ticket_id": 626102665, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102666, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-11", "ticket_id": 626102667, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-12", "ticket_id": 626102668, "ticket_type": 0}
              ],
              [
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-13", "ticket_id": 626102669, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-14", "ticket_id": 626102670, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102671, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-15", "ticket_id": 626102672, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-16", "ticket_id": 626102673, "ticket_type": 0}
              ],
              [
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-21", "ticket_id": 626102679, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-22", "ticket_id": 626102680, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102681, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-23", "ticket_id": 626102682, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-24", "ticket_id": 626102683, "ticket_type": 0}
              ],
              [
                {"isHidden": false, "seat_availability": 0, "seat_number": "DA-25", "ticket_id": 626102684, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-26", "ticket_id": 626102685, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102686, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-27", "ticket_id": 626102687, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-28", "ticket_id": 626102688, "ticket_type": 1}
              ],
              [
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-29", "ticket_id": 626102689, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-30", "ticket_id": 626102690, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102691, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-31", "ticket_id": 626102692, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-32", "ticket_id": 626102693, "ticket_type": 1}
              ],
              [
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-33", "ticket_id": 626102699, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-34", "ticket_id": 626102700, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102701, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-35", "ticket_id": 626102702, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-36", "ticket_id": 626102703, "ticket_type": 1}
              ],
              [
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-37", "ticket_id": 626102704, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-38", "ticket_id": 626102705, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102706, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-39", "ticket_id": 626102707, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 1, "seat_number": "DA-40", "ticket_id": 626102708, "ticket_type": 1}
              ]
            ]
          },
          {
            "floor_name": "KA",
            "seat_floor": 1,
            "seat_type": 1,
            "fare_type_id": 1,
            "seat_fare_type": "Economy",
            "seat_availability": false,
            "seat_fare": "450.00",
            "layout": [
              [
                {"isHidden": false, "seat_availability": 0, "seat_number": "KA-1", "ticket_id": 626102254, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102255, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102256, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102257, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102258, "ticket_type": 0}
              ],
              [
                {"isHidden": false, "seat_availability": 0, "seat_number": "KA-2", "ticket_id": 626102259, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102260, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102261, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "KA-3", "ticket_id": 626102262, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 0, "seat_number": "KA-4", "ticket_id": 626102263, "ticket_type": 1}
              ]
            ]
          },
          {
            "floor_name": "JHA",
            "seat_floor": 2,
            "seat_type": 1,
            "fare_type_id": 1,
            "seat_fare_type": "Economy",
            "seat_availability": true,
            "seat_fare": "450.00",
            "layout": [
              [
                {"isHidden": false, "seat_availability": 0, "seat_number": "JHA-1", "ticket_id": 626102289, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102290, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102291, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "JHA-3", "ticket_id": 626102297, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 1, "seat_number": "JHA-4", "ticket_id": 626102298, "ticket_type": 1}
              ],
              [
                {"isHidden": false, "seat_availability": 1, "seat_number": "JHA-5", "ticket_id": 626102299, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 1, "seat_number": "JHA-6", "ticket_id": 626102300, "ticket_type": 1},
                {"isHidden": false, "seat_availability": 0, "seat_number": "", "ticket_id": 626102301, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "JHA-7", "ticket_id": 626102302, "ticket_type": 0},
                {"isHidden": false, "seat_availability": 0, "seat_number": "JHA-8", "ticket_id": 626102303, "ticket_type": 0}
              ]
            ]
          }
        ]
      }
    });
  }
}

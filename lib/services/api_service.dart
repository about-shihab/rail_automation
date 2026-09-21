import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/auth_session.dart';
import '../models/train_trip.dart';

class ApiService {
  static String requestSeatClass(String? value) {
    final normalized = value?.trim().toUpperCase();
    return normalized == null || normalized.isEmpty || normalized == 'ALL'
        ? 'SNIGDHA'
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
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Origin': 'https://eticket.railway.gov.bd',
      'Referer': 'https://eticket.railway.gov.bd/',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'X-Requested-With': 'XMLHttpRequest',
      'sec-ch-ua-platform': '"Windows"',
      'sec-ch-ua-mobile': '?0',
    };

    if (authSession.token.isNotEmpty) {
      headers['Authorization'] = authSession.token.startsWith('Bearer ')
          ? authSession.token
          : 'Bearer ${authSession.token}';
    }

    final devId = authSession.deviceId.isNotEmpty
        ? authSession.deviceId
        : AuthSession.generateUuid();
    headers['x-device-id'] = devId;
    headers['X-Device-Id'] = devId;

    if (authSession.deviceKey.isNotEmpty) {
      headers['x-device-key'] = authSession.deviceKey;
      headers['X-Device-Key'] = authSession.deviceKey;
    }

    if (authSession.cookie != null && authSession.cookie!.isNotEmpty) {
      headers['Cookie'] = authSession.cookie!;
    }

    final response = await http
        .get(uri, headers: headers)
        .timeout(
          const Duration(seconds: 15),
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
}

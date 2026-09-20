import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rail_automation/models/train_trip.dart';

void main() {
  test('Parses Bangladesh Railway Shohoz search-trips response correctly', () {
    const rawJson = '''{
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
                        "seat_counts": {
                            "online": 0,
                            "offline": 0,
                            "is_divided": true
                        }
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
                        "seat_counts": {
                            "online": 1,
                            "offline": 0,
                            "is_divided": true
                        }
                    }
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
                        "location_date": "23 Sep 2026"
                    }
                ]
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
                            "is_divided": true
                        }
                    }
                ],
                "train_model": "802",
                "is_open_for_all": true,
                "is_eid_trip": 0,
                "boarding_points": []
            }
        ],
        "selected_seat_class": "SNIGDHA"
    },
    "extra": {
        "hash": "EF19EFA325123043835C7D7AFBD760DA"
    }
}''';

    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final res = TripSearchResponse.fromJson(decoded);

    expect(res.trains.length, 2);
    expect(res.selectedSeatClass, 'SNIGDHA');
    expect(res.hash, 'EF19EFA325123043835C7D7AFBD760DA');

    final train1 = res.trains[0];
    expect(train1.tripNumber, 'MAHANAGAR PROVATI (704)');
    expect(train1.totalOnlineSeats, 1);
    expect(train1.hasAnyOnlineSeats, true);
    expect(train1.seatTypes.length, 2);
    expect(train1.seatTypes[0].type, 'S_CHAIR');
    expect(train1.seatTypes[0].seatCounts.online, 0);
    expect(train1.seatTypes[0].isAvailable, false);
    expect(train1.seatTypes[1].type, 'F_SEAT');
    expect(train1.seatTypes[1].seatCounts.online, 1);
    expect(train1.seatTypes[1].isAvailable, true);

    final train2 = res.trains[1];
    expect(train2.tripNumber, 'CHATTALA EXPRESS (802)');
    expect(train2.seatTypes[0].type, 'SNIGDHA');
    expect(train2.seatTypes[0].seatCounts.online, 22);
    expect(train2.seatTypes[0].isAvailable, true);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:rail_automation/utils/railway_stations.dart';
import 'package:rail_automation/services/app_config.dart';

void main() {
  group('Bangladesh Railway Stations List Tests', () {
    test('Contains exactly 256 canonical stations', () {
      expect(railwayStations.length, 256);
      expect(railwayStations.contains('Dhaka'), true);
      expect(railwayStations.contains("Cox's Bazar"), true);
      expect(railwayStations.contains('Chattogram'), true);
      expect(railwayStations.contains('Ullapara'), true);
      expect(railwayStations.contains('Abdulpur'), true);
    });

    test('All station names are unique and non-empty', () {
      final set = railwayStations.toSet();
      expect(set.length, railwayStations.length);
      for (final station in railwayStations) {
        expect(station.trim().isNotEmpty, true);
      }
    });

    test('AppConfig default stations include all canonical railway stations', () {
      final configStations = AppConfig.instance.strings('stations');
      expect(configStations.length, 256);
      expect(configStations.contains('Dhaka'), true);
      expect(configStations.contains('Chattogram'), true);
    });

    test('Auto-select filter excludes the other station', () {
      const fromStation = 'Dhaka';
      const toStation = 'Chattogram';

      // Suggestions for From should not contain toStation
      final fromPool = railwayStations.where(
        (s) => s.toLowerCase() != toStation.toLowerCase(),
      );
      expect(fromPool.contains('Chattogram'), false);
      expect(fromPool.contains('Dhaka'), true);

      // Suggestions for To should not contain fromStation
      final toPool = railwayStations.where(
        (s) => s.toLowerCase() != fromStation.toLowerCase(),
      );
      expect(toPool.contains('Dhaka'), false);
      expect(toPool.contains('Chattogram'), true);
    });

    test('Searching "cox" returns "Cox\'s Bazar"', () {
      final matches = railwayStations.where(
        (s) => s.toLowerCase().contains('cox'),
      ).toList();
      expect(matches.contains("Cox's Bazar"), true);
    });

    test('Popular stations are all part of the main 256 stations list', () {
      for (final p in popularStations) {
        expect(railwayStations.contains(p), true, reason: '$p should be in railwayStations');
      }
    });
  });
}

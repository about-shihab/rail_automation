import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rail_automation/models/booking_intent.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MonitorService monitor;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    monitor = MonitorService(proService: ProService());
  });

  tearDown(() {
    monitor.dispose();
  });

  test('removing only monitored train stops search monitoring completely', () async {
    monitor.startMonitoring(
      fromCity: 'Chattogram',
      toCity: 'Dhaka',
      dateOfJourney: '26-Oct-2026',
      targetTrains: ['CHATTALA EXPRESS (801)'],
      intent: const BookingIntent(),
    );

    expect(monitor.isMonitoring, isTrue);
    expect(monitor.isTrainMonitored('CHATTALA EXPRESS (801)'), isTrue);
    expect(monitor.isTrainMonitored('MAHANAGAR GODHULI (703)'), isFalse);

    // Remove from search
    monitor.removeTrainFromMonitoring('CHATTALA EXPRESS (801)');

    // Search monitor must be stopped and NO trains should be monitored
    expect(monitor.isMonitoring, isFalse);
    expect(monitor.isTrainMonitored('CHATTALA EXPRESS (801)'), isFalse);
    expect(monitor.isTrainMonitored('MAHANAGAR GODHULI (703)'), isFalse);
    expect(monitor.isTrainMonitored('COXS BAZAR EXPRESS (813)'), isFalse);
  });

  test('removing from route-level search monitor stops monitoring completely', () async {
    monitor.startMonitoring(
      fromCity: 'Chattogram',
      toCity: 'Dhaka',
      dateOfJourney: '26-Oct-2026',
      intent: const BookingIntent(),
    );

    expect(monitor.isMonitoring, isTrue);
    expect(monitor.isTrainMonitored('CHATTALA EXPRESS (801)'), isTrue);
    expect(monitor.isTrainMonitored('MAHANAGAR GODHULI (703)'), isTrue);

    // Remove from search
    monitor.removeTrainFromMonitoring('CHATTALA EXPRESS (801)');

    // Search monitor must be stopped and NO trains should be monitored
    expect(monitor.isMonitoring, isFalse);
    expect(monitor.isTrainMonitored('CHATTALA EXPRESS (801)'), isFalse);
    expect(monitor.isTrainMonitored('MAHANAGAR GODHULI (703)'), isFalse);
  });

  test('removing one train from multi-train search keeps remaining train monitored', () async {
    monitor.startMonitoring(
      fromCity: 'Chattogram',
      toCity: 'Dhaka',
      dateOfJourney: '26-Oct-2026',
      targetTrains: ['CHATTALA EXPRESS (801)', 'MAHANAGAR GODHULI (703)'],
      intent: const BookingIntent(),
    );

    expect(monitor.isMonitoring, isTrue);
    expect(monitor.isTrainMonitored('CHATTALA EXPRESS (801)'), isTrue);
    expect(monitor.isTrainMonitored('MAHANAGAR GODHULI (703)'), isTrue);
    expect(monitor.isTrainMonitored('COXS BAZAR EXPRESS (813)'), isFalse);

    // Remove only CHATTALA EXPRESS (801)
    monitor.removeTrainFromMonitoring('CHATTALA EXPRESS (801)');

    // Monitor stays active for the other train only
    expect(monitor.isMonitoring, isTrue);
    expect(monitor.isTrainMonitored('CHATTALA EXPRESS (801)'), isFalse);
    expect(monitor.isTrainMonitored('MAHANAGAR GODHULI (703)'), isTrue);
    expect(monitor.isTrainMonitored('COXS BAZAR EXPRESS (813)'), isFalse);
  });
}

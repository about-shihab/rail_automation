import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rail_automation/services/app_config.dart';
import 'package:rail_automation/services/sms_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('com.example.rail_automation/sms');
  const events = MethodChannel('com.example.rail_automation/sms_stream');
  final service = SmsService();

  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(methods, (_) async => true);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(events, (_) async => null);
  });
  tearDown(() async {
    service.stopListening();
    await Future<void>.delayed(Duration.zero);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(methods, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(events, null);
  });

  test('preparation waits for native listener readiness', () async {
    final calls = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call.method);
      return false;
    });
    expect(await service.prepareListening(), isFalse);
    expect(calls, ['prepareListening']);
  });

  test('missing native availability never pretends permission was granted', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(methods, (_) async => null);
    expect(await service.hasPermission(), isFalse);
    expect(await service.requestSmsPermission(), isFalse);
  });

  testWidgets('a Railway OTP arriving after 25 seconds is still accepted', (tester) async {
    var unavailable = false;
    String? code;
    await service.startListening(
      onOtpReceived: (value) => code = value,
      onUnavailable: () => unavailable = true,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(unavailable, isFalse);
    binding.defaultBinaryMessenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'sender': '', 'body': 'Your Bangladesh Railway OTP is 012345',
      }),
      (_) {},
    );
    await tester.pump();
    expect(code, '012345');
    await tester.pump(Duration(seconds: AppConfig.instance.number('otp_window_seconds')));
    expect(unavailable, isTrue);
  });
}

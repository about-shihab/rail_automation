import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rail_automation/services/voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'awaitSpeakCompletion') return 1;
          if (call.method == 'setLanguage') return 1;
          if (call.method == 'setPitch') return 1;
          if (call.method == 'setSpeechRate') return 1;
          if (call.method == 'setVolume') return 1;
          if (call.method == 'getVoices') {
            return [
              {'name': 'bn-bd-x-ban-network', 'locale': 'bn-BD', 'gender': 'female'},
              {'name': 'en-us-x-sfg-network', 'locale': 'en-US', 'gender': 'female'},
            ];
          }
          if (call.method == 'setVoice') return 1;
          if (call.method == 'speak') return 1;
          if (call.method == 'stop') return 1;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('VoiceService configures natural female Bangla voice and announces booking confirmation', () async {
    final service = VoiceService();
    await service.speakBookingConfirmed(force: true);

    expect(calls.any((c) => c.method == 'setLanguage' && c.arguments.toString().contains('bn')), isTrue);
    expect(calls.any((c) => c.method == 'setPitch'), isTrue);
    expect(calls.any((c) => c.method == 'setSpeechRate'), isTrue);
    expect(
      calls.any(
        (c) =>
            c.method == 'speak' &&
            c.arguments.toString().contains('আপনার টিকেট বুকিং কনফার্ম করা হয়েছে, টিকেটের মূল্য পরিশোধ করুন'),
      ),
      isTrue,
    );
  });
}

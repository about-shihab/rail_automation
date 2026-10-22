import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  VoiceService._internal();
  static final VoiceService instance = VoiceService._internal();
  factory VoiceService() => instance;

  FlutterTts? _tts;
  bool _initialized = false;

  FlutterTts get _client => _tts ??= FlutterTts();

  /// Initialize TTS settings prioritizing a natural female Bengali voice
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final tts = _client;
      await tts.awaitSpeakCompletion(true);

      // Attempt to configure Bengali locale
      try {
        await tts.setLanguage('bn-BD');
      } catch (_) {
        try {
          await tts.setLanguage('bn');
        } catch (_) {}
      }

      // Configure natural female voice parameters
      // Pitch > 1.0 (e.g. 1.15) gives a natural female timbre
      // Rate ~0.48 gives clear, human-like cadence for Bangla pronunciation
      await tts.setPitch(1.15);
      await tts.setSpeechRate(0.48);
      await tts.setVolume(1.0);

      // Look through available voices to select Google's natural Bengali female voice
      try {
        final voices = await tts.getVoices;
        if (voices is List) {
          Map<dynamic, dynamic>? bestFemaleVoice;
          for (final voice in voices) {
            if (voice is! Map) continue;
            final name = (voice['name'] ?? '').toString().toLowerCase();
            final locale = (voice['locale'] ?? '').toString().toLowerCase();
            final gender = (voice['gender'] ?? '').toString().toLowerCase();

            if (locale.contains('bn')) {
              final isFemale = gender.contains('female') ||
                  name.contains('female') ||
                  name.contains('woman') ||
                  name.contains('ban-network') || // Google neural female (bn-BD)
                  name.contains('bin-network'); // Google neural female (bn-IN)

              if (isFemale) {
                bestFemaleVoice = voice;
                break;
              } else {
                bestFemaleVoice ??= voice;
              }
            }
          }

          if (bestFemaleVoice != null) {
            final voiceMap = Map<String, String>.from(
              bestFemaleVoice.map((k, v) => MapEntry(k.toString(), v.toString())),
            );
            await tts.setVoice(voiceMap);
            debugPrint('🔊 [VoiceService] Selected voice: ${bestFemaleVoice['name']}');
          }
        }
      } catch (e) {
        debugPrint('⚠️ [VoiceService] Voice selection skipped: $e');
      }

      _initialized = true;
    } catch (e) {
      debugPrint('⚠️ [VoiceService] Initialization skipped: $e');
    }
  }

  /// Audio voice disabled per requirement; loud train whistle and vibration are used for alerts.
  Future<void> speakBookingConfirmed({bool force = false}) async {
    return;
  }

  /// Audio voice disabled per requirement; loud train whistle and vibration are used for alerts.
  Future<void> speak(String text, {bool force = false}) async {
    return;
  }

  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}

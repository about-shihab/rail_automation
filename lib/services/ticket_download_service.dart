import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TicketDownloadService {
  static const _channel = MethodChannel('com.example.rail_automation/overlay');

  /// Saves the PDF bytes to the device's Downloads/RailPro directory
  /// and opens the system PDF viewer so the user can inspect or print the ticket.
  static Future<String?> saveAndOpenTicketPdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final res = await _channel.invokeMethod<String>(
          'saveAndOpenPdf',
          {'bytes': bytes, 'fileName': fileName},
        );
        return res;
      } catch (e) {
        return null;
      }
    }
    return null;
  }
}

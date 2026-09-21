import 'package:flutter/foundation.dart';
import '../models/auth_session.dart';

/// Pro features are not yet available. isPro is always false until
/// a payment/subscription system is implemented.
class ProService extends ChangeNotifier {

  bool _isPro = false;

  bool get isPro => _isPro;
  bool get isServerSyncing => false;
  String? get serverMonitorTaskId => null;

  ProService();

  /// Updates Pro status from Firebase Firestore.
  void updateProStatus(bool value) {
    if (_isPro != value) {
      _isPro = value;
      notifyListeners();
    }
  }

  // Kept for API compatibility
  Future<void> setProStatus(bool value) async {
    updateProStatus(value);
  }

  /// Server-side monitoring — reserved for Pro. Always returns false.
  Future<bool> startServerCloudMonitoring({
    required AuthSession session,
    required String fromCity,
    required String toCity,
    required String dateOfJourney,
    String? targetTrain,
    String? targetSeatClass,
  }) async {
    return false; // Pro not yet available
  }

  Future<void> stopServerCloudMonitoring() async {}
}

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC_RgzCBaymHWY-RfhGwDyDICGw_kX7ywQ',
    appId: '1:161962645432:android:afe9a0a8756151df96214d',
    messagingSenderId: '161962645432',
    projectId: 'railautomation-1993',
    storageBucket: 'railautomation-1993.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC_RgzCBaymHWY-RfhGwDyDICGw_kX7ywQ',
    appId: '1:161962645432:ios:afe9a0a8756151df96214d',
    messagingSenderId: '161962645432',
    projectId: 'railautomation-1993',
    storageBucket: 'railautomation-1993.firebasestorage.app',
    iosBundleId: 'com.example.railAutomation',
  );
}

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

/// Firebase options generated from google-services.json.
///
/// For Windows: replace the appId with your actual Windows app ID
/// from the Firebase Console (Project Settings > General > Your apps).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCt8pJsHrkKt9IMC0egWrHLDCcfj9bUip8',
    appId: '1:545311301769:android:916147c4c032e8206e2658',
    messagingSenderId: '545311301769',
    projectId: 'musync-6e5aa',
    storageBucket: 'musync-6e5aa.firebasestorage.app',
  );

  // Windows placeholder — Firebase is skipped on Windows (see firebase_service.dart)
  // To enable Firebase on Windows, replace with real app ID from Firebase Console
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCt8pJsHrkKt9IMC0egWrHLDCcfj9bUip8',
    appId: '1:545311301769:windows:PLACEHOLDER_REPLACE_ME',
    messagingSenderId: '545311301769',
    projectId: 'musync-6e5aa',
    storageBucket: 'musync-6e5aa.firebasestorage.app',
  );
}

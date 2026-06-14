import 'package:firebase_core/firebase_core.dart';

/// Firebase config for PosEx Android push (FCM).
/// Add Android app `lk.posex.posex_app` in Firebase Console and replace
/// androidAppId if push registration fails.
class DefaultFirebaseOptions {
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBLifvHU4hgVdtWeLB_iq_cPKAPQyO4UpA',
    appId: '1:605381881810:android:posex_app_placeholder',
    messagingSenderId: '605381881810',
    projectId: 'pos-pro-logging',
    storageBucket: 'pos-pro-logging.firebasestorage.app',
  );

  static FirebaseOptions get currentPlatform => android;
}

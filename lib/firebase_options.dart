import 'package:firebase_core/firebase_core.dart';

/// Firebase config for PosEx Android push (FCM).
/// Generated from Firebase project `pos-pro-logging`, app `lk.posex.posex_app`.
class DefaultFirebaseOptions {
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBInqIICsct4f4TkJZBGupYkqVaRxaQAkA',
    appId: '1:605381881810:android:d6d5a9ba17da8e04ff220b',
    messagingSenderId: '605381881810',
    projectId: 'pos-pro-logging',
    storageBucket: 'pos-pro-logging.firebasestorage.app',
  );

  static FirebaseOptions get currentPlatform => android;
}

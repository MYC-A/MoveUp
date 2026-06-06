import 'package:firebase_core/firebase_core.dart';

class AppFirebaseOptions {
  static const String apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  static bool get isConfigured {
    return apiKey.isNotEmpty &&
        appId.isNotEmpty &&
        messagingSenderId.isNotEmpty &&
        projectId.isNotEmpty;
  }

  static List<String> get missingConfigKeys {
    return [
      if (apiKey.isEmpty) 'FIREBASE_API_KEY',
      if (appId.isEmpty) 'FIREBASE_APP_ID',
      if (messagingSenderId.isEmpty) 'FIREBASE_MESSAGING_SENDER_ID',
      if (projectId.isEmpty) 'FIREBASE_PROJECT_ID',
    ];
  }

  static FirebaseOptions? get currentPlatform {
    if (!isConfigured) return null;

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
    );
  }
}

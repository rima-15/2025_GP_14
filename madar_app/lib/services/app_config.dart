import 'package:cloud_functions/cloud_functions.dart';

class AppConfig {
  static String _googleApiKey = '';

  static String get googleApiKey => _googleApiKey;

  static Future<void> init() async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('getConfig');
    final result = await callable.call();
    _googleApiKey = (result.data['googleApiKey'] as String?) ?? '';
  }
}

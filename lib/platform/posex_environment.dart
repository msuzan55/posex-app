import 'package:shared_preferences/shared_preferences.dart';

/// Which PosEx web site the native shell loads.
class PosexEnvironment {
  PosexEnvironment._();

  static const prefsKey = 'posex_web_environment';

  static const test = 'test';
  static const app = 'app';

  static const testUrl = 'https://posex.lk/test/';
  static const appUrl = 'https://posex.lk/app/';

  static String urlFor(String env) =>
      env == app ? appUrl : testUrl;

  static String labelFor(String env) =>
      env == app ? 'posex.lk/app' : 'posex.lk/test';

  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(prefsKey);
    if (value == app || value == test) return value!;
    return test;
  }

  static Future<void> save(String env) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, env == app ? app : test);
  }
}

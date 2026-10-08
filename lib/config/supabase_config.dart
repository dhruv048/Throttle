import 'env.dart';

/// Runtime config. Prefer `--dart-define` or fill [Env] in `env.dart`.
class SupabaseConfig {
  SupabaseConfig._();

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: Env.supabaseUrl,
  );

  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: Env.supabaseAnonKey,
  );

  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: Env.googleWebClientId,
  );

  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: Env.googleIosClientId,
  );

  static const authRedirect = 'com.wheelsclub.app://login-callback';

  static bool get isConfigured =>
      url.isNotEmpty &&
      !url.contains('YOUR_') &&
      anonKey.isNotEmpty &&
      !anonKey.contains('YOUR_');
}


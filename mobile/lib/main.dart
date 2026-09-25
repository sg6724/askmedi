import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.assertConfigured();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    // `publishableKey` replaces the deprecated `anonKey`; it accepts either key.
    publishableKey: AppConfig.supabaseAnonKey,
  );
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const AskMediApp(),
    ),
  );
}

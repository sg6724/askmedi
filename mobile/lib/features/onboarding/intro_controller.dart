import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Whether this device has already seen the welcome slides.
class IntroController extends Notifier<bool> {
  static const _key = 'intro_seen';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  Future<void> markSeen() async {
    await ref.read(sharedPreferencesProvider).setBool(_key, true);
    state = true;
  }
}

final introSeenProvider = NotifierProvider<IntroController, bool>(
  IntroController.new,
);

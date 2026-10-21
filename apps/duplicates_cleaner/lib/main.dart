import 'package:flutter/material.dart';

import 'app.dart';
import 'services/premium_service.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsStore.load();
  final premium = await PremiumService.load();
  runApp(DuplicatesCleanerApp(settings: settings, premium: premium));
}

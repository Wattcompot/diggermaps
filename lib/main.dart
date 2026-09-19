import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'presentation/screens/map_screen.dart';
import 'presentation/widgets/app_notifications.dart';
import 'presentation/widgets/app_scroll.dart';
import 'theme/app_theme.dart';

const _spectralCacheCleanupKey = 'spectral_cache_cleanup_days';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  await initializeDateFormatting('ru_RU');

  // Для Android используем стандартную фабрику sqflite
  // sqflite_ffi удален для оптимизации размера APK

  try {
    if (!kIsWeb) {
      final dir = await getApplicationDocumentsDirectory();
      await Hive.initFlutter(dir.path);
    } else {
      await Hive.initFlutter();
    }
  } catch (_) {
    await Hive.initFlutter();
  }

  final preferences = await SharedPreferences.getInstance();
  if (!kIsWeb) {
    try {
      await FMTCObjectBoxBackend().initialise();
      for (final name in const ['esri_base', 'base_layers']) {
        final store = FMTCStore(name);
        if (!await store.manage.ready) await store.manage.create();
      }
      const sentinelStore = FMTCStore('sentinelStore');
      if (!await sentinelStore.manage.ready) {
        await sentinelStore.manage.create(maxLength: 1000);
      } else if (await sentinelStore.manage.maxLength != 1000) {
        await sentinelStore.manage.setMaxLength(1000);
      }
      final cleanupDays = preferences.getInt(_spectralCacheCleanupKey) ?? 30;
      if (cleanupDays > 0) {
        await sentinelStore.manage.removeTilesOlderThan(
          expiry: DateTime.now().subtract(Duration(days: cleanupDays)),
        );
      }
    } catch (_) {
      // Network tiles keep working if the optional disk cache is unavailable.
    }
  }
  runApp(DiggerMapsApp(preferences: preferences));
}

class DiggerMapsApp extends StatefulWidget {
  const DiggerMapsApp({required this.preferences, super.key});

  final SharedPreferences preferences;

  static Future<void> setThemeMode(BuildContext context, ThemeMode mode) =>
      context
          .findAncestorStateOfType<_DiggerMapsAppState>()!
          .setThemeMode(mode);

  @override
  State<DiggerMapsApp> createState() => _DiggerMapsAppState();
}

class _DiggerMapsAppState extends State<DiggerMapsApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = switch (widget.preferences.getString('theme_mode')) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await widget.preferences.setString('theme_mode', mode.name);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DiggerMaps',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Единый scrollbar для всех вертикальных списков/меню.
      scrollBehavior: appScrollBehavior,
      // Единый канал SnackBar поверх маршрутов, диалогов и bottom sheet.
      builder: (context, child) =>
          AppNotificationsHost(child: child ?? const SizedBox.shrink()),
      home: ThemeModeScope(
        mode: _themeMode,
        onChanged: setThemeMode,
        child: const MapScreen(),
      ),
    );
  }
}

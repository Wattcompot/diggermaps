import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme/app_theme.dart';

const _spectralCacheCleanupKey = 'spectral_cache_cleanup_days';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.initialCleanupDays,
    required this.metricUnits,
    required this.onMetricChanged,
    required this.onCleanupDaysChanged,
    required this.onClearCache,
  });

  final int initialCleanupDays;
  final bool metricUnits;
  final ValueChanged<bool> onMetricChanged;
  final ValueChanged<int> onCleanupDaysChanged;
  final VoidCallback onClearCache;

  static Future<void> show(
    BuildContext context, {
    required int initialCleanupDays,
    required bool metricUnits,
    required ValueChanged<bool> onMetricChanged,
    required ValueChanged<int> onCleanupDaysChanged,
    required VoidCallback onClearCache,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (_) => SettingsSheet(
        initialCleanupDays: initialCleanupDays,
        metricUnits: metricUnits,
        onMetricChanged: onMetricChanged,
        onCleanupDaysChanged: onCleanupDaysChanged,
        onClearCache: onClearCache,
      ),
    );
  }

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late int _cleanupDays;
  late bool _metricUnits;

  @override
  void initState() {
    super.initState();
    _cleanupDays = widget.initialCleanupDays;
    _metricUnits = widget.metricUnits;
    _loadSpectralCacheSettings();
  }

  Future<void> _loadSpectralCacheSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final value = preferences.getInt(_spectralCacheCleanupKey) ?? 30;
      if (mounted) setState(() => _cleanupDays = value);
    } catch (_) {
      // Keep the supplied default when preferences are unavailable.
    }
  }

  Future<void> _setSpectralCacheCleanupDays(int days) async {
    setState(() => _cleanupDays = days);
    widget.onCleanupDaysChanged(days);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(_spectralCacheCleanupKey, days);
      if (days > 0 && !kIsWeb) {
        const store = FMTCStore('sentinelStore');
        if (await store.manage.ready) {
          await store.manage.removeTilesOlderThan(
            expiry: DateTime.now().subtract(Duration(days: days)),
          );
        }
      }
    } catch (_) {
      if (mounted) _showMessage('Не удалось изменить автоочистку');
    }
  }

  Future<void> _clearSpectralCache() async {
    if (kIsWeb) {
      _showMessage('Очистка кэша недоступна в браузере');
      return;
    }
    try {
      const store = FMTCStore('sentinelStore');
      if (await store.manage.ready) await store.manage.reset();
      if (!mounted) return;
      widget.onClearCache();
      _showMessage('Кэш снимков очищен');
    } catch (_) {
      if (mounted) _showMessage('Не удалось очистить кэш снимков');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeModeScope.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SwitchListTile(
            title: const Text('Метрическая система'),
            value: _metricUnits,
            onChanged: (value) {
              setState(() => _metricUnits = value);
              widget.onMetricChanged(value);
            },
          ),
          ListTile(
            title: const Text('Тема'),
            trailing: DropdownButton<ThemeMode>(
              value: theme.mode,
              items: const <DropdownMenuItem<ThemeMode>>[
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text('Светлая'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text('Тёмная'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('Системная'),
                ),
              ],
              onChanged: (value) {
                if (value != null) theme.onChanged(value);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Очистить кэш снимков'),
            onTap: _clearSpectralCache,
          ),
          ListTile(
            leading: const Icon(Icons.update_outlined),
            title: const Text('Автоочистка кэша'),
            trailing: DropdownButton<int>(
              value: _cleanupDays,
              items: const <DropdownMenuItem<int>>[
                DropdownMenuItem(value: 7, child: Text('7 дней')),
                DropdownMenuItem(value: 30, child: Text('30 дней')),
                DropdownMenuItem(value: 0, child: Text('Не удалять')),
              ],
              onChanged: (value) {
                if (value != null) _setSpectralCacheCleanupDays(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}

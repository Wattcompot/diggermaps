import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../data/models/drawing.dart';
import '../../../data/models/track.dart';
import '../../../data/models/user_marker.dart';
import '../../../theme/app_theme.dart';

class MapDrawer extends StatelessWidget {
  const MapDrawer({
    super.key,
    required this.markers,
    required this.drawings,
    required this.tracks,
    required this.importedCount,
    required this.customCount,
    required this.onMyObjectsTap,
    required this.onMyMapsTap,
    required this.onSettingsTap,
    required this.onAboutTap,
    required this.onAuthTap,
    required this.onPremiumTap,
    required this.onSupportEmailTap,
    required this.onSupportSiteTap,
    required this.onSupportDocsTap,
  });

  final List<UserMarker> markers;
  final List<Drawing> drawings;
  final List<Track> tracks;
  final int importedCount;
  final int customCount;
  final VoidCallback onMyObjectsTap;
  final VoidCallback onMyMapsTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onAboutTap;
  final VoidCallback onAuthTap;
  final VoidCallback onPremiumTap;
  final VoidCallback onSupportEmailTap;
  final VoidCallback onSupportSiteTap;
  final VoidCallback onSupportDocsTap;

  void _closeThen(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppThemeTokens.of(context);
    final muted = tokens.onSurfaceMuted;
    User? user;
    try {
      user = FirebaseAuth.instance.currentUser;
    } catch (_) {
      // Firebase is optional in local builds without an initialized app.
    }
    final userName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : user?.email?.trim().isNotEmpty == true
            ? user!.email!.trim()
            : 'Пользователь';
    final photoUrl = user?.photoURL?.trim();

    return Drawer(
      child: Column(
        children: <Widget>[
          Material(
            color: theme.colorScheme.primary.withValues(alpha: 0.14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.explore_rounded,
                    color: tokens.primaryAccent,
                    size: 34,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'DiggerMaps',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Полевые карты и находки',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Профиль',
                style: theme.textTheme.labelLarge?.copyWith(color: muted),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl == null || photoUrl.isEmpty
                      ? Icon(
                          Icons.person_outline,
                          color: tokens.onSurfaceIcon,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        user == null ? 'Гость' : userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        user == null ? 'Статус: Free' : 'Бесплатно',
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: SizedBox(
              width: double.infinity,
              child: user == null
                  ? FilledButton(
                      onPressed: onAuthTap,
                      child: const Text('Войти или зарегистрироваться'),
                    )
                  : OutlinedButton(
                      onPressed: onPremiumTap,
                      child: const Text('Перейти на Premium'),
                    ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
                  child: Text(
                    'Навигация',
                    style: theme.textTheme.labelLarge?.copyWith(color: muted),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: const Text('Мои объекты'),
                  subtitle: Text(
                    '${markers.length + drawings.length + tracks.length} объектов',
                  ),
                  onTap: () => _closeThen(context, onMyObjectsTap),
                ),
                ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: const Text('Мои карты'),
                  subtitle: Text(
                    '$importedCount импортированных, '
                    '$customCount пользовательских',
                  ),
                  onTap: () => _closeThen(context, onMyMapsTap),
                ),
                ListTile(
                  enabled: false,
                  leading: Icon(Icons.groups_outlined, color: muted),
                  title: Text('Команды', style: TextStyle(color: muted)),
                  trailing: Icon(Icons.lock_outline, color: muted, size: 19),
                ),
                ExpansionTile(
                  leading: const Icon(Icons.support_agent_outlined),
                  title: const Text('Поддержка'),
                  children: <Widget>[
                    ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 72, right: 16),
                      leading: const Icon(Icons.mail_outline, size: 20),
                      title: const Text('Написать разработчикам'),
                      onTap: onSupportEmailTap,
                    ),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 72, right: 16),
                      leading: const Icon(Icons.public, size: 20),
                      title: const Text('Сайт'),
                      onTap: onSupportSiteTap,
                    ),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 72, right: 16),
                      leading: const Icon(Icons.menu_book_outlined, size: 20),
                      title: const Text('Инструкция'),
                      onTap: onSupportDocsTap,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Настройки'),
                  onTap: () => _closeThen(context, onSettingsTap),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('О приложении'),
                  onTap: () => _closeThen(context, onAboutTap),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

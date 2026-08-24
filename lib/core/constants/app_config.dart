/// Конфигурация, передаваемая во время сборки.
///
/// Не храните ключи в исходниках: Android APK можно декомпилировать.
/// Запуск: `flutter run --dart-define=WIKIMAPIA_API_KEY=...`.
class AppConfig {
  const AppConfig._();

  static const appName = 'DiggerMaps';
  static const wikimapiaApiKey = String.fromEnvironment(
    'WIKIMAPIA_API_KEY',
    defaultValue:
        '0EBBFAB5-ABDC29C7-A148FDE8-82D1415F-8343B240-92C89CA1-F1BC519D-A34BE967',
  );
  static const nominatimUserAgent = String.fromEnvironment(
      'NOMINATIM_USER_AGENT',
      defaultValue: 'DiggerMaps/0.1');
}

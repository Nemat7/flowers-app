/// Адрес backend'а. По умолчанию — локальная машина (web-разработка).
///
/// Для сборок на устройство `localhost` указывает на сам телефон, поэтому
/// хост передаётся при сборке:
/// `flutter build apk --dart-define=SERVER_HOST=192.168.1.83:8002`.
/// На проде добавится `--dart-define=SERVER_SCHEME=https` — тогда и WebSocket
/// переключится на wss автоматически.
library;

const String kServerHost = String.fromEnvironment(
  'SERVER_HOST',
  defaultValue: 'localhost:8002',
);

const String kServerScheme = String.fromEnvironment(
  'SERVER_SCHEME',
  defaultValue: 'http',
);

const bool _isSecure = kServerScheme == 'https';

/// База REST API (api.md: `/api/v1/`).
const String kApiBaseUrl = '$kServerScheme://$kServerHost/api/v1';

/// Хост для относительных media-путей («/media/shops/1.jpg»).
const String kMediaBaseUrl = '$kServerScheme://$kServerHost';

/// Базовый URL WebSocket-каналов (api.md §7).
const String kWsBaseUrl = _isSecure ? 'wss://$kServerHost' : 'ws://$kServerHost';

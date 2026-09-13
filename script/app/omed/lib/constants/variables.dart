class AppVariables {
  AppVariables._();

  // Application
  static const String appName = 'OMED';
  static const String appVersion = '0.1.0';

  // WebSocket
  static const String websocketHost = '127.0.0.1';
  static const int websocketPort = 8765;

  static String get websocketUrl => 'ws://$websocketHost:$websocketPort';
}

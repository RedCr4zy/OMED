// =========================================
//       Parametres generaux historiques
// =========================================
/// Regroupe des valeurs constantes de configuration de l'application.
///
/// Les constantes WebSocket ci-dessous appartiennent a l'ancien transport
/// local; elles sont conservees ici mais le parcours audio actuel ne les utilise
/// plus (il passe par le service MIDI natif).
class AppVariables {
  /// Constructeur prive : acces aux valeurs par les membres statiques.
  AppVariables._();

  // Identite affichee et version de l'application.
  static const String appName = 'OMED';
  static const String appVersion = '0.1.0';

  // Parametres de l'ancien serveur WebSocket local (non utilises actuellement).
  static const String websocketHost = '127.0.0.1';
  static const int websocketPort = 8765;

  /// Compose l'URL WebSocket a partir de l'hote et du port historiques.
  static String get websocketUrl => 'ws://$websocketHost:$websocketPort';
}

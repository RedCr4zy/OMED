// Bibliotheques Dart pour les operations asynchrones et les tests de plateforme.
import 'dart:async';
import 'dart:io';

// Services Flutter et integration de l'authentification Supabase.
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Ecrans principaux et services partages de l'application.
import 'home.dart';
import 'service/audio_service.dart';
import 'service/ble_service.dart';
import 'welcome.dart';

/// Point d'entree de l'application.
///
/// Charge d'abord la configuration locale, puis initialise Supabase avant
/// d'afficher l'interface. Le fichier `lib/.env.local` doit exister localement
/// et fournir `supabaseUrl` ainsi que `supabasePublishableKey`.
///
/// Exemple de contenu attendu dans ce fichier (ne pas y placer de secret prive) :
/// ```dotenv
/// supabaseUrl=https://exemple.supabase.co
/// supabasePublishableKey=votre-cle-publiable
/// ```
Future<void> main() async {
  // Initialise le pont Flutter avant d'utiliser les plugins natifs.
  WidgetsFlutterBinding.ensureInitialized();

  // Charge les variables d'environnement embarquees comme assets Flutter.
  await dotenv.load(fileName: 'lib/.env.local');

  // Configure le client Supabase utilise ensuite par l'authentification.
  // PKCE protege le retour OAuth en separant l'autorisation de l'echange du code.
  await Supabase.initialize(
    url: dotenv.env['supabaseUrl']!,
    publishableKey: dotenv.env['supabasePublishableKey']!,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // Affiche le widget racine uniquement apres l'initialisation des services.
  runApp(const MainApp());
}

// =========================================
//                 Application
// =========================================
/// Widget racine : conserve les ecouteurs globaux pendant la vie de l'application.
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

/// Gere les services partages, les liens OAuth et le cycle de vie Flutter.
class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  // Les services sont des singletons : l'ecran d'accueil utilise les memes instances.
  final AudioService _audio = AudioService.instance;
  final BleService _ble = BleService.instance;

  // AppLinks recoit les URI envoyees par le systeme, notamment le retour OAuth.
  final AppLinks _appLinks = AppLinks();

  // Ces abonnements doivent etre annules quand le widget racine est detruit.
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<Uri>? _appLinksSubscription;

  @override
  void initState() {
    super.initState();

    // Enregistre ce widget pour recevoir les changements d'etat de l'application.
    WidgetsBinding.instance.addObserver(this);

    // Demarre le moteur MIDI et verifie la disponibilite du Bluetooth sans
    // retarder l'affichage initial de l'interface.
    unawaited(_audio.initialize());
    unawaited(_ble.initialize());

    // L'interface doit se reconstruire lorsque la session Supabase change,
    // afin de montrer l'accueil connecte ou l'ecran de connexion.
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      _,
    ) {
      if (mounted) setState(() {});
    });

    // Le retour OAuth par lien profond est actuellement configure pour Linux.
    if (Platform.isLinux) {
      _appLinksSubscription = _appLinks.uriLinkStream.listen(
        _handleAppLink,
        onError: (Object error) => debugPrint('OAuth callback error: $error'),
      );
    }
  }

  /// Traite un lien profond contenant le code de retour OAuth de Supabase.
  ///
  /// Ignore les URI qui ne sont pas destinees a OMED ou qui ne contiennent pas
  /// de code. `getSessionFromUrl` echange ce code et etablit la session.
  Future<void> _handleAppLink(Uri uri) async {
    // Le scheme doit correspondre au scheme de liens profonds configure pour OMED.
    if (uri.scheme != 'omed' ||
        (!uri.queryParameters.containsKey('code') &&
            !uri.queryParameters.containsKey('auth_code'))) {
      return;
    }

    // L'echange OAuth peut echouer (code expire, configuration invalide, reseau).
    // L'erreur est journalisee pour le diagnostic plutot que masquee.
    try {
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
    } catch (error) {
      debugPrint('OAuth callback failed: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A la reprise, relit l'etat de l'adaptateur BLE (Bluetooth active, autorisation).
    if (state == AppLifecycleState.resumed) {
      unawaited(_ble.initialize());
      return;
    }

    // Arrete le son lorsque l'application passe en arriere-plan ou se ferme,
    // afin d'eviter qu'une note reste tenue apres la perte de l'interface.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(
        _audio.stopAllNotes().catchError(
          (Object error) => debugPrint('Unable to stop notes on pause: $error'),
        ),
      );
    }
  }

  @override
  void dispose() {
    // Retire l'observateur et libere les ecouteurs associes a ce widget.
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _appLinksSubscription?.cancel();

    // Les fermetures des moteurs sont asynchrones; elles sont lancees sans
    // bloquer dispose et leurs erreurs sont envoyees aux journaux Flutter.
    unawaited(
      _audio.shutdown().catchError(
        (Object error) => debugPrint('Audio shutdown failed: $error'),
      ),
    );
    unawaited(
      _ble.shutdown().catchError(
        (Object error) => debugPrint('Bluetooth shutdown failed: $error'),
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // =========================================
    //            Configuration generale
    // =========================================
    // Le choix de l'ecran depend de la session actuellement connue de Supabase.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OMED',

      // Une session valide ouvre directement l'accueil; sinon, affiche la connexion.
      home: Supabase.instance.client.auth.currentSession != null
          ? const Home()
          : Welcome(),

      // Route nommee utilisee apres une authentification reussie.
      routes: {'/home': (context) => const Home()},
    );
  }
}

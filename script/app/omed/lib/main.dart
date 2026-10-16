import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'dart:async';
import 'dart:io';

import 'welcome.dart';
import 'home.dart';
import 'service/websocket_service.dart';
import 'service/sound_service.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: 'lib/.env.local');

  await Supabase.initialize(
    url: dotenv.env['supabaseUrl']!,
    publishableKey: dotenv.env['supabasePublishableKey']!,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  final appLinks = AppLinks();

  if (Platform.isLinux) {
    appLinks.uriLinkStream.listen((uri) async {
      if (uri.scheme == 'omed' &&
          (uri.queryParameters.containsKey('code') ||
              uri.queryParameters.containsKey('auth_code'))) {
        try {
          await Supabase.instance.client.auth.getSessionFromUrl(uri);
          print('✅ Authentification OAuth réussie');
        } catch (error) {
          print('❌ ERREUR auth : $error');
        }
      }
    });
  }

  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});
  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  StreamSubscription<Map<String, dynamic>>? _sub;
  StreamSubscription<AuthState>? authSubscription;
  Process? linuxPythonProcess;

  static const pythonChannel = MethodChannel('omed/python');

  @override
  void initState() {
    super.initState();
    _init();

    authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _init() async {
    print('🔵 _init() démarré');

    // 1. Serveur Python
    if (Platform.isAndroid) {
      print('🔵 Android → Chaquopy');
      try {
        await pythonChannel.invokeMethod('startServer');
        print('🔵 Chaquopy OK');
      } catch (e) {
        print('🔴 Erreur Chaquopy : $e');
        return;
      }
    } else {
      print('🔵 Desktop → Process.start');
      try {
        linuxPythonProcess = await Process.start('python3', [
          'android/app/src/main/python/server.py',
        ]);
        print('🔵 Process démarré');
      } catch (e) {
        print('🔴 Erreur Process : $e');
        return;
      }
    }

    // 2. WebSocket
    print('🔵 Connexion WebSocket...');
    await WebsocketService.instance.initialize();
    print('🔵 WebSocket connecté');

    // 3. SoundFont
    // 3. SoundFont (Android uniquement)
    if (Platform.isAndroid) {
      try {
        await SoundService.instance.init();
        print('🔵 SoundService OK');
      } catch (e) {
        print('🔴 Erreur SoundFont : $e');
      }
    }

    if (Platform.isLinux) {
      try {
        await SoundService.instance.init();
        print('🔵 SoundService OK');
      } catch (e) {
        print('Erreur SoundFont : $e');
      }
    }

    // 4. Listener
    print('🔵 Abonnement listener...');
    _sub = WebsocketService.instance.onMessage.listen((data) {
      if (data['command'] == 'playSound') {
        print('🔵 playSound reçu, _sfId = ${SoundService.instance.sfId}');
        if (Platform.isAndroid) {
          SoundService.instance.playNote(
            bank: data['bank'] ?? 0,
            instrument: data['instrument'] as int,
            note: data['note'] as int,
            durationMs: (data['duration'] as num?)?.toInt() ?? 500,
          );
        }
      }
    });
    print('🔵 _init() terminé');
  }

  @override
  void dispose() {
    _sub?.cancel();
    authSubscription?.cancel();
    linuxPythonProcess?.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "OMED",
      home: Supabase.instance.client.auth.currentSession != null
          ? const Home()
          : Welcome(),
      routes: {'/home': (context) => const Home()},
    );
  }
}

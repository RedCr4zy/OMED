import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home.dart';
import 'service/audio_service.dart';
import 'service/ble_service.dart';
import 'welcome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: 'lib/.env.local');
  await Supabase.initialize(
    url: dotenv.env['supabaseUrl']!,
    publishableKey: dotenv.env['supabasePublishableKey']!,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  final AudioService _audio = AudioService.instance;
  final BleService _ble = BleService.instance;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<Uri>? _appLinksSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_audio.initialize());
    unawaited(_ble.initialize());
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      _,
    ) {
      if (mounted) setState(() {});
    });
    if (Platform.isLinux) {
      _appLinksSubscription = _appLinks.uriLinkStream.listen(
        _handleAppLink,
        onError: (Object error) => debugPrint('OAuth callback error: $error'),
      );
    }
  }

  Future<void> _handleAppLink(Uri uri) async {
    if (uri.scheme != 'omed' ||
        (!uri.queryParameters.containsKey('code') &&
            !uri.queryParameters.containsKey('auth_code'))) {
      return;
    }
    try {
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
    } catch (error) {
      debugPrint('OAuth callback failed: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_ble.initialize());
      return;
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _appLinksSubscription?.cancel();
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OMED',
      home: Supabase.instance.client.auth.currentSession != null
          ? const Home()
          : Welcome(),
      routes: {'/home': (context) => const Home()},
    );
  }
}

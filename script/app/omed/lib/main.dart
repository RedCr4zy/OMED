import 'package:flutter/material.dart';

import 'package:web_socket_channel/web_socket_channel.dart';

import './constants/colors.dart';

import './constants/variables.dart';

// ============================================================
// >>> AJOUT : MethodChannel + Timer
// ============================================================

import 'package:flutter/services.dart';

import 'dart:async';

// ============================================================
// <<< FIN AJOUT
// ============================================================

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final input = TextEditingController();

  late WebSocketChannel channel;

  // ==========================================================
  // >>> AJOUT : communication avec Python
  // ==========================================================

  static const pythonChannel = MethodChannel('omed/python');

  final List<String> pythonLogs = [];

  Timer? pythonLogTimer;

  // ==========================================================
  // <<< FIN AJOUT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    channel = WebSocketChannel.connect(Uri.parse(AppVariables.websocketUrl));

    channel.stream.listen((message) {
      print('Message reçu : $message');
    });

    // ========================================================
    // >>> AJOUT : lancement du serveur Python
    // ========================================================

    startPythonServer();

    // ========================================================
    // <<< FIN AJOUT
    // ========================================================
  }

  // ==========================================================
  // >>> AJOUT : démarrer Python
  // ==========================================================

  Future<void> startPythonServer() async {
    try {
      await pythonChannel.invokeMethod('startServer');

      print('Serveur Python lancé.');

      startPythonLogReader();
    } catch (error) {
      print('Erreur lors du lancement du serveur Python : $error');

      setState(() {
        pythonLogs.add('[ERREUR] Impossible de lancer Python : $error');
      });
    }
  }

  // ==========================================================
  // >>> AJOUT : récupérer les logs Python
  // ==========================================================

  void startPythonLogReader() {
    pythonLogTimer?.cancel();

    pythonLogTimer = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) async {
      try {
        final logs = await pythonChannel.invokeMethod<List<dynamic>>('getLogs');

        if (logs == null || logs.isEmpty) {
          return;
        }

        setState(() {
          pythonLogs.addAll(logs.map((log) => log.toString()));
        });
      } catch (error) {
        print('Erreur récupération logs Python : $error');
      }
    });
  }

  // ==========================================================
  // <<< FIN AJOUT : logs Python
  // ==========================================================

  void sendMessage(String message) {
    print(message);

    channel.sink.add(message);
  }

  @override
  void dispose() {
    // ========================================================
    // >>> AJOUT : arrêter le timer Python
    // ========================================================

    pythonLogTimer?.cancel();

    // ========================================================
    // <<< FIN AJOUT
    // ========================================================

    input.dispose();

    channel.sink.close();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: AppVariables.appName + AppVariables.appVersion,

      home: Scaffold(
        backgroundColor: AppColors.background,

        body: Center(
          child: Column(
            children: [
              Text(
                AppVariables.appName,

                style: TextStyle(fontSize: 40, color: AppColors.textPrimary),
              ),

              Text(
                AppVariables.appVersion,

                style: TextStyle(fontSize: 20, color: AppColors.textSecondary),
              ),

              const SizedBox(height: 80),

              TextField(
                controller: input,

                style: TextStyle(fontSize: 20, color: AppColors.textPrimary),

                decoration: InputDecoration(
                  enabledBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(10)),

                    borderSide: BorderSide(
                      width: 2.0,
                      color: AppColors.secondary,
                    ),
                  ),

                  focusedBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(100)),

                    borderSide: BorderSide(
                      width: 2.0,
                      color: AppColors.primary,
                    ),
                  ),
                ),

                onSubmitted: (_) {
                  sendMessage(input.text);
                },
              ),

              const SizedBox(height: 40),

              ElevatedButton(
                onPressed: () {
                  sendMessage(input.text);
                },

                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                ),

                child: Text(
                  "Submit",

                  style: TextStyle(fontSize: 40, color: AppColors.textPrimary),
                ),
              ),

              // ==================================================
              // >>> AJOUT : CONSOLE PYTHON
              // ==================================================
              const SizedBox(height: 40),

              Text(
                "Console Python",

                style: TextStyle(fontSize: 25, color: AppColors.textPrimary),
              ),

              const SizedBox(height: 10),

              Expanded(
                child: Container(
                  width: double.infinity,

                  margin: const EdgeInsets.symmetric(horizontal: 20),

                  padding: const EdgeInsets.all(10),

                  decoration: BoxDecoration(
                    color: Colors.black,

                    borderRadius: BorderRadius.circular(10),

                    border: Border.all(color: AppColors.secondary, width: 2),
                  ),

                  child: SingleChildScrollView(
                    reverse: true,

                    child: Text(
                      pythonLogs.isEmpty
                          ? "En attente du serveur Python..."
                          : pythonLogs.join('\n'),

                      style: const TextStyle(
                        color: Colors.white,

                        fontFamily: 'monospace',

                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),

              // ==================================================
              // <<< FIN AJOUT : CONSOLE PYTHON
              // ==================================================
            ],
          ),
        ),
      ),
    );
  }
}

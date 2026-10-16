import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';

class WebsocketService {
  WebsocketService._();
  static final WebsocketService instance = WebsocketService._();

  WebSocketChannel? channel;
  Process? linuxPythonProcess;
  Timer? pythonLogTimer;
  final List<String> pythonLogs = [];

  final _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void _notify() => _listeners.forEach((l) => l());

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;



  void _onDataReceived(Map<String, dynamic> data) {
    _messageController.add(data);
  }



  Future<void> initialize() async {
    if (Platform.isLinux) {
      await _startLinux();
    }
    await Future.delayed(const Duration(milliseconds: 500));
    await _connectWebSocket();
  }



  Future<void> _startLinux() async {
    try {
      linuxPythonProcess = await Process.start('python3', [
        'android/app/src/main/python/server.py',
      ]);
      linuxPythonProcess!.stdout
          .transform(const SystemEncoding().decoder)
          .listen((data) {
            pythonLogs.addAll(data.split('\n').where((l) => l.isNotEmpty));
            _notify();
          });
      linuxPythonProcess!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((data) {
            pythonLogs.addAll(data.split('\n').where((l) => l.isNotEmpty));
            _notify();
          });
    } catch (e) {
      pythonLogs.add('[ERREUR] $e');
      _notify();
    }
  }



  Future<void> _connectWebSocket() async {
    for (int i = 1; i <= 20; i++) {
      try {
        final c = WebSocketChannel.connect(Uri.parse('ws://localhost:8765'));
        await c.ready;
        channel = c;

        // Le listener est configuré ici, une fois, et tourne en permanence
        channel!.stream.listen((msg) {
          final data = jsonDecode(msg as String) as Map<String, dynamic>;
          _messageController.add(data); // ✅ alimente le broadcast stream
        });

        print('WebSocket connecté.');
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  void send(Map<String, dynamic> message) {
    channel?.sink.add(jsonEncode(message));
  }

  void dispose() {
    pythonLogTimer?.cancel();
    linuxPythonProcess?.kill();
    channel?.sink.close();
  }
}

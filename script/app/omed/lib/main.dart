import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import './constants/colors.dart';
import './constants/variables.dart';

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

  @override
  void initState() {
    channel = WebSocketChannel.connect(Uri.parse(AppVariables.websocketUrl));
    super.initState();
    channel.stream.listen((message) {
      print('Message reçu : $message');
    });
  }

  void sendMessage(String message) {
    print(message);
    channel.sink.add(message);
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

              SizedBox(height: 80),

              TextField(
                controller: input,
                style: TextStyle(fontSize: 20, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide(
                      width: 2.0,
                      color: AppColors.secondary,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(100)),
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

              SizedBox(height: 40),

              ElevatedButton(
                onPressed: () => {sendMessage(input.text)},
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                ),
                child: Text(
                  "Submit",
                  style: TextStyle(fontSize: 40, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'dart:async';

import 'constants/colors.dart';
import 'service/websocket_service.dart';

import 'service/sound_service.dart';

import 'package:flutter_midi_pro/flutter_midi_pro.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  StreamSubscription<Map<String, dynamic>>? _sub;

  SoundfontPreset? _selectedPreset;
  int _selectedNote = 60;

  @override
  void initState() {
    super.initState();

    final presets = SoundService.instance.presets;
    if (presets.isNotEmpty) {
      _selectedPreset = presets.first;
    }
  }

  String _noteName(int midiNote) {
    const names = [
      'Do',
      'Do♯',
      'Ré',
      'Ré♯',
      'Mi',
      'Fa',
      'Fa♯',
      'Sol',
      'Sol♯',
      'La',
      'La♯',
      'Si',
    ];

    return '${names[midiNote % 12]} ${midiNote ~/ 12 - 1}';
  }

  void _playNote() {
    final preset = _selectedPreset;
    if (preset == null) return;

    WebsocketService.instance.send({
      'command': 'playSound',
      'bank': preset.bank,
      'instrument': preset.program,
      'note': _selectedNote,
      'duration': 500,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.transparent,
        destinations: [
          NavigationDestination(icon: Icon(Icons.abc), label: 'Test'),
          NavigationDestination(
            icon: Icon(Icons.track_changes),
            label: 'Test 2',
          ),
        ],
      ),
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;

          final circleSize = width * 0.3 * 3.25;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -(circleSize) / 2,
                top: height * 0,
                width: circleSize,
                height: circleSize,
                child: Image(
                  image: AssetImage('lib/assets/bg-circle-glow.png'),
                  fit: BoxFit.fill,
                ),
              ),

              Positioned(
                top: height * 0.7,
                right: -(circleSize) / 1.5,
                child: Image(
                  image: AssetImage('lib/assets/bg-circle-glow.png'),
                ),
              ),

              Center(
                child: Column(
                  children: [
                    SizedBox(height: height * 0.2),
                    Text(
                      'OMED',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 40,
                      ),
                    ),

                    DropdownButtonFormField<SoundfontPreset>(
                      value: _selectedPreset,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Instrument',
                        border: OutlineInputBorder(),
                      ),
                      items: SoundService.instance.presets.map((preset) {
                        return DropdownMenuItem<SoundfontPreset>(
                          value: preset,
                          child: Text(
                            '${preset.name} (banque ${preset.bank}, programme ${preset.program})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (preset) {
                        setState(() => _selectedPreset = preset);
                      },
                    ),

                    const SizedBox(height: 20),

                    DropdownButtonFormField<int>(
                      value: _selectedNote,
                      decoration: const InputDecoration(
                        labelText: 'Note',
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(49, (i) => i + 36).map((note) {
                        return DropdownMenuItem<int>(
                          value: note,
                          child: Text('$note — ${_noteName(note)}'),
                        );
                      }).toList(),
                      onChanged: (note) {
                        if (note != null) {
                          setState(() => _selectedNote = note);
                        }
                      },
                    ),

                    const SizedBox(height: 20),

                    ElevatedButton.icon(
                      onPressed: _selectedPreset == null ? null : _playNote,
                      icon: const Icon(Icons.music_note),
                      label: const Text('Jouer la note'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

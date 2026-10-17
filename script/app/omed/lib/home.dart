import 'dart:async';

import 'package:flutter/material.dart';

import 'constants/colors.dart';
import 'service/audio_service.dart';
import 'service/ble_service.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final AudioService _audio = AudioService.instance;
  final BleService _ble = BleService.instance;
  Timer? _noteTimer;
  int _selectedNote = 60;

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

  Future<void> _playNote() async {
    final note = _selectedNote;
    _noteTimer?.cancel();
    try {
      await _audio.stopAllNotes();
      await _audio.noteOn(note);
      _noteTimer = Timer(const Duration(milliseconds: 500), () {
        unawaited(_run(_audio.noteOff(note)));
      });
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _run(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _noteTimer?.cancel();
    unawaited(
      _audio.stopAllNotes().catchError(
        (Object error) =>
            debugPrint('Stop notes on screen disposal failed: $error'),
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final circleSize = constraints.maxWidth * 0.95;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -circleSize * 0.52,
                top: -circleSize * 0.42,
                width: circleSize,
                height: circleSize,
                child: Image.asset(
                  'lib/assets/bg-circle-glow.png',
                  fit: BoxFit.fill,
                ),
              ),
              Positioned(
                right: -circleSize * 0.52,
                bottom: -circleSize * 0.42,
                width: circleSize,
                height: circleSize,
                child: Image.asset(
                  'lib/assets/bg-circle-glow.png',
                  fit: BoxFit.fill,
                ),
              ),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_audio, _ble]),
                      builder: (context, _) => SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'OMED',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 40,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 28),
                            _buildAudioControls(),
                            const SizedBox(height: 28),
                            _buildBleControls(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAudioControls() {
    final audioReady = _audio.status == AudioStatus.ready;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Synthétiseur MIDI',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(_audioStatusLabel),
            if (_audio.status == AudioStatus.initializing) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_audio.errorMessage case final message?) ...[
              const SizedBox(height: 10),
              _ErrorText(message),
            ],
            if (_audio.status == AudioStatus.error) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => unawaited(_run(_audio.initialize())),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
            if (audioReady) ...[
              const SizedBox(height: 18),
              DropdownButtonFormField<AudioPreset>(
                key: ValueKey('audio-${_audio.presets.length}'),
                initialValue: _audio.selectedPreset,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Instrument',
                  border: OutlineInputBorder(),
                ),
                items: _audio.presets.map((preset) {
                  return DropdownMenuItem<AudioPreset>(
                    value: preset,
                    child: Text(
                      '${preset.name} (banque ${preset.bank}, programme ${preset.program})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (preset) {
                  if (preset != null) {
                    _noteTimer?.cancel();
                    unawaited(_run(_audio.selectPreset(preset)));
                  }
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                key: const ValueKey('midi-note'),
                initialValue: _selectedNote,
                decoration: const InputDecoration(
                  labelText: 'Note MIDI',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(49, (index) => index + 36).map((note) {
                  return DropdownMenuItem<int>(
                    value: note,
                    child: Text('$note — ${_noteName(note)}'),
                  );
                }).toList(),
                onChanged: (note) {
                  if (note != null) setState(() => _selectedNote = note);
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _playNote,
                icon: const Icon(Icons.music_note),
                label: const Text('Jouer la note'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBleControls() {
    final isScanning = _ble.status == BleStatus.scanning;
    final isConnected = _ble.status == BleStatus.connected;
    final canScan =
        _ble.status == BleStatus.ready || _ble.status == BleStatus.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Contrôleur ESP32',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(_bleStatusLabel),
            if (_ble.errorMessage case final message?) ...[
              const SizedBox(height: 10),
              _ErrorText(message),
            ],
            const SizedBox(height: 12),
            if (isConnected)
              OutlinedButton.icon(
                onPressed: () => unawaited(_run(_ble.disconnect())),
                icon: const Icon(Icons.bluetooth_disabled),
                label: const Text('Déconnecter'),
              )
            else
              OutlinedButton.icon(
                onPressed: isScanning
                    ? () => unawaited(_run(_ble.stopScan()))
                    : canScan
                    ? () => unawaited(_run(_ble.startScan()))
                    : null,
                icon: Icon(isScanning ? Icons.stop : Icons.bluetooth_searching),
                label: Text(isScanning ? 'Arrêter la recherche' : 'Rechercher'),
              ),
            if (isScanning) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            if (!isScanning && _ble.devices.isEmpty && canScan) ...[
              const SizedBox(height: 12),
              const Text('Aucun contrôleur trouvé.'),
            ],
            if (_ble.devices.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final device in _ble.devices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bluetooth),
                  title: Text(device.name),
                  subtitle: Text(
                    '${device.id}${device.rssi == null ? '' : ' · ${device.rssi} dBm'}',
                  ),
                  trailing: isConnected && _ble.connectedDeviceId == device.id
                      ? const Icon(Icons.check_circle)
                      : IconButton(
                          tooltip: 'Connecter',
                          onPressed:
                              isScanning ||
                                  _ble.status == BleStatus.connecting ||
                                  _ble.status == BleStatus.disconnecting ||
                                  isConnected
                              ? null
                              : () => unawaited(_run(_ble.connect(device))),
                          icon: const Icon(Icons.link),
                        ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String get _audioStatusLabel => switch (_audio.status) {
    AudioStatus.uninitialized => 'En attente du moteur audio.',
    AudioStatus.initializing => 'Chargement de FluidSynth et du SoundFont…',
    AudioStatus.ready =>
      '${_audio.presets.length} instruments prêts avec FluidSynth.',
    AudioStatus.error => 'Le moteur audio n’a pas pu démarrer.',
  };

  String get _bleStatusLabel => switch (_ble.status) {
    BleStatus.checking => 'Vérification du Bluetooth…',
    BleStatus.unavailable => 'Bluetooth indisponible.',
    BleStatus.ready => 'Prêt à rechercher le service OMED.',
    BleStatus.scanning => 'Recherche d’un contrôleur OMED pendant 15 secondes…',
    BleStatus.connecting => 'Connexion au contrôleur…',
    BleStatus.disconnecting => 'Déconnexion du contrôleur…',
    BleStatus.connected => 'Connecté : ${_ble.connectedDeviceId}',
    BleStatus.error => 'Une erreur Bluetooth est survenue.',
  };
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:omed/service/audio_service.dart';

// =========================================
//        Tests unitaires du service audio
// =========================================
/// Verifie le contrat Dart de l'audio sans charger de moteur natif.
void main() {
  // Chaque test injecte un faux backend pour rester independant du materiel.
  group('AudioService', () {
    // L'initialisation choisit un preset et les commandes sont retransmises.
    test('initializes presets and forwards MIDI commands', () async {
      final backend = _FakeAudioBackend();
      final service = AudioService(backendFactory: () => backend);
      addTearDown(service.dispose);

      await service.initialize();

      expect(service.status, AudioStatus.ready);
      expect(service.selectedPreset, _FakeAudioBackend.preset);
      expect(backend.selectedPreset, _FakeAudioBackend.preset);

      await service.noteOn(60, velocity: 90);
      await service.noteOff(60);
      await service.stopAllNotes();

      expect(backend.commands, ['noteOn:60:90', 'noteOff:60', 'stopAll']);
    });

    // Une erreur du moteur doit rester disponible pour l'ecran d'accueil.
    test('retains initialization errors for the UI', () async {
      final service = AudioService(
        backendFactory: () => _FakeAudioBackend(
          initializationError: StateError('missing audio device'),
        ),
      );
      addTearDown(service.dispose);

      await service.initialize();

      expect(service.status, AudioStatus.error);
      expect(service.errorMessage, contains('missing audio device'));
    });

    // Les numeros MIDI sont toujours limites a 7 bits.
    test('rejects MIDI values outside the protocol range', () async {
      final service = AudioService(backendFactory: _FakeAudioBackend.new);
      addTearDown(service.dispose);
      await service.initialize();

      await expectLater(service.noteOn(128), throwsRangeError);
      await expectLater(service.noteOff(-1), throwsRangeError);
    });
  });
}

/// Simulation minimale du backend pour verifier les appels du service.
class _FakeAudioBackend implements AudioBackend {
  _FakeAudioBackend({this.initializationError});

  static const preset = AudioPreset(name: 'Piano', bank: 0, program: 0);
  final Object? initializationError;
  final List<String> commands = [];
  AudioPreset? selectedPreset;

  /// Renvoie le preset fictif ou simule une erreur de chargement.
  @override
  Future<List<AudioPreset>> initialize() async {
    if (initializationError case final error?) throw error;
    return const [preset];
  }

  /// Memorise le preset demande par AudioService.
  @override
  Future<void> selectPreset(AudioPreset preset) async {
    selectedPreset = preset;
  }

  /// Enregistre un evenement Note On pour l'assertion du test.
  @override
  Future<void> noteOn(int note, int velocity) async {
    commands.add('noteOn:$note:$velocity');
  }

  /// Enregistre un evenement Note Off pour l'assertion du test.
  @override
  Future<void> noteOff(int note) async {
    commands.add('noteOff:$note');
  }

  /// Enregistre la coupure globale des notes.
  @override
  Future<void> stopAllNotes() async {
    commands.add('stopAll');
  }

  /// Aucun ressource native n'est necessaire pour ce faux backend.
  @override
  Future<void> dispose() async {}
}

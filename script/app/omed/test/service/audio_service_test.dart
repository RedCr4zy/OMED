import 'package:flutter_test/flutter_test.dart';
import 'package:omed/service/audio_service.dart';

void main() {
  group('AudioService', () {
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

    test('rejects MIDI values outside the protocol range', () async {
      final service = AudioService(backendFactory: _FakeAudioBackend.new);
      addTearDown(service.dispose);
      await service.initialize();

      await expectLater(service.noteOn(128), throwsRangeError);
      await expectLater(service.noteOff(-1), throwsRangeError);
    });
  });
}

class _FakeAudioBackend implements AudioBackend {
  _FakeAudioBackend({this.initializationError});

  static const preset = AudioPreset(name: 'Piano', bank: 0, program: 0);
  final Object? initializationError;
  final List<String> commands = [];
  AudioPreset? selectedPreset;

  @override
  Future<List<AudioPreset>> initialize() async {
    if (initializationError case final error?) throw error;
    return const [preset];
  }

  @override
  Future<void> selectPreset(AudioPreset preset) async {
    selectedPreset = preset;
  }

  @override
  Future<void> noteOn(int note, int velocity) async {
    commands.add('noteOn:$note:$velocity');
  }

  @override
  Future<void> noteOff(int note) async {
    commands.add('noteOff:$note');
  }

  @override
  Future<void> stopAllNotes() async {
    commands.add('stopAll');
  }

  @override
  Future<void> dispose() async {}
}

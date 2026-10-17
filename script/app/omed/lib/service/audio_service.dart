import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';

const soundfontAssetPath = 'lib/assets/soundfonts/FluidR3_GM.sf2';

enum AudioStatus { uninitialized, initializing, ready, error }

@immutable
class AudioPreset {
  const AudioPreset({
    required this.name,
    required this.bank,
    required this.program,
  });

  final String name;
  final int bank;
  final int program;
}

abstract interface class AudioBackend {
  Future<List<AudioPreset>> initialize();
  Future<void> selectPreset(AudioPreset preset);
  Future<void> noteOn(int note, int velocity);
  Future<void> noteOff(int note);
  Future<void> stopAllNotes();
  Future<void> dispose();
}

class AudioService extends ChangeNotifier {
  AudioService({@visibleForTesting this.backendFactory});

  static final AudioService instance = AudioService();

  @visibleForTesting
  final AudioBackend Function()? backendFactory;
  AudioStatus status = AudioStatus.uninitialized;
  List<AudioPreset> presets = const [];
  AudioPreset? selectedPreset;
  String? errorMessage;

  AudioBackend? _backend;
  Future<void>? _initialization;

  Future<void> initialize() {
    if (status == AudioStatus.ready) return Future<void>.value();
    final pending = _initialization;
    if (pending != null) return pending;

    final future = Future<void>.microtask(_initialize);
    _initialization = future;
    return future.whenComplete(() {
      if (identical(_initialization, future)) _initialization = null;
    });
  }

  Future<void> _initialize() async {
    status = AudioStatus.initializing;
    presets = const [];
    selectedPreset = null;
    errorMessage = null;
    notifyListeners();

    AudioBackend? backend;
    try {
      backend = _createBackend();
      _backend = backend;
      presets = await backend.initialize();
      if (presets.isEmpty) {
        throw StateError('Le SoundFont ne contient aucun preset utilisable.');
      }
      selectedPreset = presets.first;
      await backend.selectPreset(selectedPreset!);
      status = AudioStatus.ready;
    } catch (error) {
      status = AudioStatus.error;
      errorMessage = error.toString();
      _backend = null;
      if (backend != null) {
        try {
          await backend.dispose();
        } catch (cleanupError) {
          errorMessage =
              '$errorMessage\nÉchec du nettoyage audio : $cleanupError';
        }
      }
    }
    notifyListeners();
  }

  AudioBackend _createBackend() {
    final factory = backendFactory;
    if (factory != null) return factory();
    if (Platform.isAndroid) return AndroidFluidSynthBackend();
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return DesktopFluidSynthBackend();
    }
    throw UnsupportedError('Audio non pris en charge sur cette plateforme.');
  }

  Future<void> selectPreset(AudioPreset preset) async {
    final backend = _requireBackend();
    try {
      await backend.stopAllNotes();
      await backend.selectPreset(preset);
      selectedPreset = preset;
      errorMessage = null;
    } catch (error) {
      errorMessage = 'Impossible de sélectionner ${preset.name} : $error';
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> noteOn(int note, {int velocity = 100}) async {
    _validateMidiValue(note, 'note');
    _validateMidiValue(velocity, 'velocity');
    try {
      await _requireBackend().noteOn(note, velocity);
      errorMessage = null;
    } catch (error) {
      errorMessage = 'Impossible de jouer la note : $error';
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> noteOff(int note) async {
    _validateMidiValue(note, 'note');
    try {
      await _requireBackend().noteOff(note);
      errorMessage = null;
    } catch (error) {
      errorMessage = 'Impossible d’arrêter la note : $error';
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> stopAllNotes() async {
    final backend = _backend;
    if (status != AudioStatus.ready || backend == null) return;
    try {
      await backend.stopAllNotes();
      errorMessage = null;
    } catch (error) {
      errorMessage = 'Impossible d’arrêter les notes : $error';
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  AudioBackend _requireBackend() {
    if (status != AudioStatus.ready || _backend == null) {
      throw StateError(errorMessage ?? 'Le moteur audio n’est pas prêt.');
    }
    return _backend!;
  }

  void _validateMidiValue(int value, String name) {
    if (value < 0 || value > 127) {
      throw RangeError.range(value, 0, 127, name);
    }
  }

  Future<void> shutdown() async {
    final backend = _backend;
    _backend = null;
    if (backend != null) {
      try {
        await backend.stopAllNotes();
      } finally {
        await backend.dispose();
      }
    }
  }

  @override
  void dispose() {
    unawaited(
      shutdown().catchError(
        (Object error) => debugPrint('Audio shutdown failed: $error'),
      ),
    );
    super.dispose();
  }
}

class AndroidFluidSynthBackend implements AudioBackend {
  final MidiPro _midi = MidiPro();
  int? _soundfontId;

  @override
  Future<List<AudioPreset>> initialize() async {
    await _midi.init(sampleRate: 48000, bufferSize: 128, polyphony: 128);
    try {
      _soundfontId = await _midi.loadSoundfontAsset(
        assetPath: soundfontAssetPath,
      );
      final presets = await _midi.getPresets(_soundfontId!);
      return presets
          .map(
            (preset) => AudioPreset(
              name: preset.name,
              bank: preset.bank,
              program: preset.program,
            ),
          )
          .toList(growable: false);
    } catch (_) {
      await _midi.dispose();
      rethrow;
    }
  }

  int get _id =>
      _soundfontId ??
      (throw StateError('Le SoundFont Android n’est pas chargé.'));

  @override
  Future<void> selectPreset(AudioPreset preset) => _midi.selectInstrument(
    sfId: _id,
    channel: 0,
    bank: preset.bank,
    program: preset.program,
  );

  @override
  Future<void> noteOn(int note, int velocity) =>
      _midi.playNote(sfId: _id, channel: 0, key: note, velocity: velocity);

  @override
  Future<void> noteOff(int note) =>
      _midi.stopNote(sfId: _id, channel: 0, key: note);

  @override
  Future<void> stopAllNotes() => _midi.stopAllNotes(sfId: _id);

  @override
  Future<void> dispose() async {
    if (_midi.isInitialized) await _midi.dispose();
    _soundfontId = null;
  }
}

class DesktopFluidSynthBackend implements AudioBackend {
  _FluidSynthBindings? _bindings;
  Pointer<Void>? _settings;
  Pointer<Void>? _synth;
  Pointer<Void>? _driver;
  int? _soundfontId;

  @override
  Future<List<AudioPreset>> initialize() async {
    final bindings = _FluidSynthBindings.open();
    _bindings = bindings;
    final soundfontPath = _findSoundfont();
    final resources = await Isolate.run(
      () => _createDesktopEngineInBackground(soundfontPath),
    );
    _settings = Pointer<Void>.fromAddress(resources[0]);
    _synth = Pointer<Void>.fromAddress(resources[1]);
    _driver = Pointer<Void>.fromAddress(resources[2]);
    _soundfontId = resources[3];

    final soundfont = bindings.getSoundfontById(_synth!, _soundfontId!);
    if (soundfont == nullptr) {
      throw StateError('FluidSynth n’a pas retrouvé le SoundFont chargé.');
    }

    final presets = <AudioPreset>[];
    bindings.startPresetIteration(soundfont);
    while (true) {
      final preset = bindings.nextPreset(soundfont);
      if (preset == nullptr) break;
      final name = bindings.presetName(preset);
      if (name == nullptr) continue;
      presets.add(
        AudioPreset(
          name: name.cast<Utf8>().toDartString(),
          bank: bindings.presetBank(preset),
          program: bindings.presetProgram(preset),
        ),
      );
    }

    presets.sort((a, b) {
      final bankOrder = a.bank.compareTo(b.bank);
      return bankOrder == 0 ? a.program.compareTo(b.program) : bankOrder;
    });
    return presets;
  }

  String _findSoundfont() {
    const relativePath = soundfontAssetPath;
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final candidates = <String>[
      relativePath,
      '${Directory.current.path}/$relativePath',
      '${executableDirectory.path}/data/flutter_assets/$relativePath',
      '${executableDirectory.path}/../Resources/flutter_assets/$relativePath',
      '${executableDirectory.path}/../Frameworks/App.framework/Resources/flutter_assets/$relativePath',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return File(candidate).absolute.path;
    }
    throw StateError(
      'SoundFont introuvable. Vérifiez que $relativePath est inclus dans les assets.',
    );
  }

  _FluidSynthBindings get _api =>
      _bindings ?? (throw StateError('FluidSynth n’est pas initialisé.'));

  Pointer<Void> get _activeSynth =>
      _synth ??
      (throw StateError('Le synthétiseur FluidSynth n’est pas prêt.'));

  int get _activeSoundfontId =>
      _soundfontId ??
      (throw StateError('Le SoundFont FluidSynth n’est pas chargé.'));

  @override
  Future<void> selectPreset(AudioPreset preset) async {
    final result = _api.selectProgram(
      _activeSynth,
      0,
      _activeSoundfontId,
      preset.bank,
      preset.program,
    );
    if (result != 0) {
      throw StateError('FluidSynth n’a pas sélectionné ${preset.name}.');
    }
  }

  @override
  Future<void> noteOn(int note, int velocity) async {
    if (_api.noteOn(_activeSynth, 0, note, velocity) != 0) {
      throw StateError('FluidSynth a refusé la note MIDI $note.');
    }
  }

  @override
  Future<void> noteOff(int note) async {
    if (_api.noteOff(_activeSynth, 0, note) != 0) {
      throw StateError('FluidSynth n’a pas arrêté la note MIDI $note.');
    }
  }

  @override
  Future<void> stopAllNotes() async {
    if (_api.allSoundsOff(_activeSynth, 0) != 0) {
      throw StateError('FluidSynth n’a pas arrêté les sons du canal MIDI.');
    }
  }

  @override
  Future<void> dispose() async {
    final api = _bindings;
    if (api == null) return;

    final synth = _synth;
    final driver = _driver;
    if (driver != null) api.deleteAudioDriver(driver);
    if (synth != null) {
      final soundfontId = _soundfontId;
      if (soundfontId != null) api.unloadSoundfont(synth, soundfontId, 1);
      api.deleteSynth(synth);
    }
    final settings = _settings;
    if (settings != null) api.deleteSettings(settings);

    _driver = null;
    _synth = null;
    _settings = null;
    _soundfontId = null;
    _bindings = null;
  }
}

List<int> _createDesktopEngineInBackground(String soundfontPath) {
  final bindings = _FluidSynthBindings.open();
  Pointer<Void>? settings;
  Pointer<Void>? synth;
  Pointer<Void>? driver;
  int? soundfontId;
  Pointer<Utf8>? nativePath;
  try {
    settings = bindings.newSettings();
    if (settings == nullptr) {
      throw StateError('FluidSynth n’a pas créé ses paramètres.');
    }

    synth = bindings.newSynth(settings);
    if (synth == nullptr) {
      throw StateError('FluidSynth n’a pas créé le synthétiseur.');
    }

    driver = bindings.newAudioDriver(settings, synth);
    if (driver == nullptr) {
      throw StateError(
        'FluidSynth n’a pas pu ouvrir la sortie audio par défaut. '
        'Vérifiez qu’un périphérique audio est disponible.',
      );
    }

    nativePath = soundfontPath.toNativeUtf8(allocator: calloc);
    soundfontId = bindings.loadSoundfont(synth, nativePath.cast<Uint8>(), 1);
    if (soundfontId < 0) {
      throw StateError('FluidSynth n’a pas pu charger $soundfontPath.');
    }

    bindings.setGain(synth, 0.7);
    return [settings.address, synth.address, driver.address, soundfontId];
  } catch (_) {
    if (driver != null) bindings.deleteAudioDriver(driver);
    if (synth != null) {
      if (soundfontId != null && soundfontId >= 0) {
        bindings.unloadSoundfont(synth, soundfontId, 1);
      }
      bindings.deleteSynth(synth);
    }
    if (settings != null) bindings.deleteSettings(settings);
    rethrow;
  } finally {
    final path = nativePath;
    if (path != null) calloc.free(path);
  }
}

class _FluidSynthBindings {
  _FluidSynthBindings(DynamicLibrary library)
    : newSettings = library
          .lookupFunction<_NewSettingsNative, _NewSettingsDart>(
            'new_fluid_settings',
          ),
      deleteSettings = library.lookupFunction<_DeleteNative, _DeleteDart>(
        'delete_fluid_settings',
      ),
      newSynth = library
          .lookupFunction<_NewWithSettingsNative, _NewWithSettingsDart>(
            'new_fluid_synth',
          ),
      deleteSynth = library.lookupFunction<_DeleteNative, _DeleteDart>(
        'delete_fluid_synth',
      ),
      newAudioDriver = library
          .lookupFunction<_NewAudioDriverNative, _NewAudioDriverDart>(
            'new_fluid_audio_driver',
          ),
      deleteAudioDriver = library.lookupFunction<_DeleteNative, _DeleteDart>(
        'delete_fluid_audio_driver',
      ),
      loadSoundfont = library
          .lookupFunction<_LoadSoundfontNative, _LoadSoundfontDart>(
            'fluid_synth_sfload',
          ),
      unloadSoundfont = library
          .lookupFunction<_UnloadSoundfontNative, _UnloadSoundfontDart>(
            'fluid_synth_sfunload',
          ),
      getSoundfontById = library
          .lookupFunction<_GetSoundfontNative, _GetSoundfontDart>(
            'fluid_synth_get_sfont_by_id',
          ),
      startPresetIteration = library
          .lookupFunction<
            _StartPresetIterationNative,
            _StartPresetIterationDart
          >('fluid_sfont_iteration_start'),
      nextPreset = library.lookupFunction<_NextPresetNative, _NextPresetDart>(
        'fluid_sfont_iteration_next',
      ),
      presetName = library.lookupFunction<_PresetNameNative, _PresetNameDart>(
        'fluid_preset_get_name',
      ),
      presetBank = library.lookupFunction<_PresetIntNative, _PresetIntDart>(
        'fluid_preset_get_banknum',
      ),
      presetProgram = library.lookupFunction<_PresetIntNative, _PresetIntDart>(
        'fluid_preset_get_num',
      ),
      selectProgram = library
          .lookupFunction<_SelectProgramNative, _SelectProgramDart>(
            'fluid_synth_program_select',
          ),
      noteOn = library.lookupFunction<_NoteOnNative, _NoteOnDart>(
        'fluid_synth_noteon',
      ),
      noteOff = library.lookupFunction<_NoteOffNative, _NoteOffDart>(
        'fluid_synth_noteoff',
      ),
      allSoundsOff = library
          .lookupFunction<_AllSoundsOffNative, _AllSoundsOffDart>(
            'fluid_synth_all_sounds_off',
          ),
      setGain = library.lookupFunction<_SetGainNative, _SetGainDart>(
        'fluid_synth_set_gain',
      );

  static _FluidSynthBindings open() {
    final candidates = switch (Platform.operatingSystem) {
      'linux' => ['libfluidsynth.so.3', 'libfluidsynth.so'],
      'windows' => [
        'libfluidsynth-3.dll',
        'libfluidsynth.dll',
        'fluidsynth.dll',
      ],
      'macos' => [
        '${File(Platform.resolvedExecutable).parent.path}/../Frameworks/libfluidsynth.3.dylib',
        '${File(Platform.resolvedExecutable).parent.path}/../Frameworks/libfluidsynth.dylib',
        'libfluidsynth.3.dylib',
        'libfluidsynth.dylib',
        '/opt/homebrew/lib/libfluidsynth.3.dylib',
        '/usr/local/lib/libfluidsynth.3.dylib',
      ],
      _ => const <String>[],
    };

    final errors = <String>[];
    for (final candidate in candidates) {
      try {
        return _FluidSynthBindings(DynamicLibrary.open(candidate));
      } catch (error) {
        errors.add('$candidate: $error');
      }
    }
    throw StateError(
      'Impossible de charger FluidSynth. Installez une version compatible '
      '(2.4 ou supérieure) et vérifiez son chemin de bibliothèque.\n'
      '${errors.join('\n')}',
    );
  }

  final Pointer<Void> Function() newSettings;
  final void Function(Pointer<Void>) deleteSettings;
  final Pointer<Void> Function(Pointer<Void>) newSynth;
  final void Function(Pointer<Void>) deleteSynth;
  final Pointer<Void> Function(Pointer<Void>, Pointer<Void>) newAudioDriver;
  final void Function(Pointer<Void>) deleteAudioDriver;
  final int Function(Pointer<Void>, Pointer<Uint8>, int) loadSoundfont;
  final int Function(Pointer<Void>, int, int) unloadSoundfont;
  final Pointer<Void> Function(Pointer<Void>, int) getSoundfontById;
  final void Function(Pointer<Void>) startPresetIteration;
  final Pointer<Void> Function(Pointer<Void>) nextPreset;
  final Pointer<Uint8> Function(Pointer<Void>) presetName;
  final int Function(Pointer<Void>) presetBank;
  final int Function(Pointer<Void>) presetProgram;
  final int Function(Pointer<Void>, int, int, int, int) selectProgram;
  final int Function(Pointer<Void>, int, int, int) noteOn;
  final int Function(Pointer<Void>, int, int) noteOff;
  final int Function(Pointer<Void>, int) allSoundsOff;
  final void Function(Pointer<Void>, double) setGain;
}

typedef _NewSettingsNative = Pointer<Void> Function();
typedef _NewSettingsDart = Pointer<Void> Function();
typedef _DeleteNative = Void Function(Pointer<Void>);
typedef _DeleteDart = void Function(Pointer<Void>);
typedef _NewWithSettingsNative = Pointer<Void> Function(Pointer<Void>);
typedef _NewWithSettingsDart = Pointer<Void> Function(Pointer<Void>);
typedef _NewAudioDriverNative = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Void>,
);
typedef _NewAudioDriverDart = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Void>,
);
typedef _LoadSoundfontNative = Int32 Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Int32,
);
typedef _LoadSoundfontDart = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _UnloadSoundfontNative = Int32 Function(Pointer<Void>, Int32, Int32);
typedef _UnloadSoundfontDart = int Function(Pointer<Void>, int, int);
typedef _GetSoundfontNative = Pointer<Void> Function(Pointer<Void>, Int32);
typedef _GetSoundfontDart = Pointer<Void> Function(Pointer<Void>, int);
typedef _StartPresetIterationNative = Void Function(Pointer<Void>);
typedef _StartPresetIterationDart = void Function(Pointer<Void>);
typedef _NextPresetNative = Pointer<Void> Function(Pointer<Void>);
typedef _NextPresetDart = Pointer<Void> Function(Pointer<Void>);
typedef _PresetNameNative = Pointer<Uint8> Function(Pointer<Void>);
typedef _PresetNameDart = Pointer<Uint8> Function(Pointer<Void>);
typedef _PresetIntNative = Int32 Function(Pointer<Void>);
typedef _PresetIntDart = int Function(Pointer<Void>);
typedef _SelectProgramNative = Int32 Function(
  Pointer<Void>,
  Int32,
  Int32,
  Int32,
  Int32,
);
typedef _SelectProgramDart = int Function(Pointer<Void>, int, int, int, int);
typedef _NoteOnNative = Int32 Function(Pointer<Void>, Int32, Int32, Int32);
typedef _NoteOnDart = int Function(Pointer<Void>, int, int, int);
typedef _NoteOffNative = Int32 Function(Pointer<Void>, Int32, Int32);
typedef _NoteOffDart = int Function(Pointer<Void>, int, int);
typedef _AllSoundsOffNative = Int32 Function(Pointer<Void>, Int32);
typedef _AllSoundsOffDart = int Function(Pointer<Void>, int);
typedef _SetGainNative = Void Function(Pointer<Void>, Float);
typedef _SetGainDart = void Function(Pointer<Void>, double);

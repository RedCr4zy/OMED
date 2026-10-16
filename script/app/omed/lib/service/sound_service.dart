import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';

class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();
  MidiPro? _midiPro;
  Process? _fluidsynth;
  int? _sfId;
  int? get sfId => _sfId;
  List<SoundfontPreset> presets = [];
  Future<void> init() async {
    print('🟡 SoundService.init() appelé');
    if (Platform.isLinux) {
      await _initLinux();
      return;
    }
    if (Platform.isAndroid) {
      _midiPro = MidiPro();
      await _midiPro!.init();
      _sfId = await _midiPro!.loadSoundfontAsset(
        assetPath: 'lib/assets/soundfonts/FluidR3_GM.sf2',
      );
      presets = await _midiPro!.getPresets(_sfId!);
      print('🎹 Nombre de presets : ${presets.length}');
      return;
    }
    throw UnsupportedError('Plateforme audio non prise en charge');
  }

  Future<void> _initLinux() async {
    final data = await rootBundle.load('lib/assets/soundfonts/FluidR3_GM.sf2');
    final file = File('${Directory.systemTemp.path}/omed_FluidR3_GM.sf2');
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    _fluidsynth = await Process.start('fluidsynth', [
      '-a',
      'pulseaudio',
      '-n',
      '-g',
      '0.7',
      file.path,
    ]);
    _fluidsynth!.stdout
        .transform(const SystemEncoding().decoder)
        .listen((text) => print('FluidSynth: $text'));
    _fluidsynth!.stderr
        .transform(const SystemEncoding().decoder)
        .listen((text) => print('FluidSynth erreur: $text'));
    _fluidsynth!.exitCode.then((code) {
      print('FluidSynth arrêté avec le code $code');
      _fluidsynth = null;
    });
    // Laisse le temps au moteur de démarrer.
    await Future.delayed(const Duration(milliseconds: 700));
    if (_fluidsynth == null) {
      throw Exception('FluidSynth ne démarre pas');
    }
    print('🎹 FluidSynth démarré sous Linux');
  }

  Future<void> playNote({
    required int bank,
    required int instrument,
    required int note,
    int durationMs = 500,
  }) async {
    if (Platform.isLinux) {
      final process = _fluidsynth;
      if (process == null) return;
      process.stdin.writeln('select 0 1 $bank $instrument');
      process.stdin.writeln('noteon 0 $note 100');
      await Future.delayed(Duration(milliseconds: durationMs));
      if (identical(process, _fluidsynth)) {
        process.stdin.writeln('noteoff 0 $note');
      }
      return;
    }
    final midi = _midiPro;
    final sfId = _sfId;
    if (midi == null || sfId == null) return;
    midi.selectInstrument(
      sfId: sfId,
      channel: 0,
      bank: bank,
      program: instrument,
    );
    midi.playNote(sfId: sfId, channel: 0, key: note, velocity: 100);
    await Future.delayed(Duration(milliseconds: durationMs));
    midi.stopNote(sfId: sfId, channel: 0, key: note);
  }

  Future<void> dispose() async {
    final process = _fluidsynth;
    _fluidsynth = null;
    if (process != null) {
      process.stdin.writeln('quit');
      await process.stdin.flush();
      await process.stdin.close();
      process.kill();
    }
    final midi = _midiPro;
    if (midi != null) {
      await midi.dispose();
      _midiPro = null;
    }
    _sfId = null;
  }
}

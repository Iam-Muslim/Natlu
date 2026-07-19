import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

class AudioProcessor {
  // ── Audio format constants ─────────────────────────────────────────────────
  static const int sampleRate = 16000;
  static const int numChannels = 1;
  static const int bytesPerSample = 2; // 16-bit PCM
  static const int bytesPerSec = sampleRate * numChannels * bytesPerSample;

  static const int chunkMs =
      320; // Matches model's min streaming chunk (chunk_size=8 = 320ms)
  static const int chunkBytes = (bytesPerSec * chunkMs) ~/ 1000;

  Uint8List _frameBuffer = Uint8List(0);
  final Float32List _reusableVadBuffer = Float32List(32000);

  // ── VAD State ──────────────────────────────────────────────────────────
  VoiceActivityDetector? _vad;
  bool _vadWasDetected = false;
  int _silenceMs = 0;

  // Static Soft-Limiter for budget Android devices without hardware AGC
  static double _tanh(double x) {
    if (x > 15.0) return 1.0;
    if (x < -15.0) return -1.0;
    final double e2x = math.exp(2.0 * x);
    return (e2x - 1.0) / (e2x + 1.0);
  }

  // Pre-roll keeps audio BEFORE the VAD becomes confident, ensuring consonant attacks aren't lost
  final List<Uint8List> _preRollBufferList = [];
  static const int maxPreRollFrames = 2; // 640ms pre-roll (2 × 320ms)

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;

  Future<String> _extractAsset(String assetPath) async {
    final Directory docDir = await getApplicationSupportDirectory();
    final String prefix = 'v2_silero_';
    final File file = File(
      '${docDir.path}/$prefix${assetPath.split('/').last}',
    );

    if (await file.exists()) {
      return file.path;
    }

    final ByteData data = await rootBundle.load(assetPath);
    final Uint8List bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _initVad() async {
    if (_vad != null) return;
    initBindings(); // from sherpa_onnx

    final String modelPath = await _extractAsset(
      'assets/model/silero_vad.onnx',
    );

    if (!File(modelPath).existsSync()) {
      throw Exception('CRITICAL: Silero VAD model missing on disk.');
    }

    final config = VadModelConfig(
      sileroVad: SileroVadModelConfig(
        model: modelPath,
        threshold:
            0.05, // Lowered threshold to prevent premature slicing on soft voices
        minSilenceDuration:
            0.45, // 450ms bridges natural Quranic pauses (Ikhfa/Waqf) without chopping words
        minSpeechDuration:
            0.2, // 200ms prevents transient mic bumps/clicks from triggering false phonemes
        windowSize: 512, // 32ms step size @ 16kHz
        maxSpeechDuration: 1000.0,
      ),
      sampleRate: sampleRate,
      numThreads: 1,
    );

    _vad = VoiceActivityDetector(config: config, bufferSizeInSeconds: 10.0);
  }

  /// Start recording and streaming raw PCM continuously.
  Future<void> start({
    required void Function(Uint8List chunk, bool isFinal) onChunk,
  }) async {
    await stopAndGetAudio();
    await _initVad();

    _vad?.reset();
    _vadWasDetected = false;
    _silenceMs = 0;
    _preRollBufferList.clear();

    _recorder = AudioRecorder();

    final recordStream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: numChannels,
        autoGain: true, // Hardware/OS-level AGC handles low-quality mics safely
        echoCancel: false, // Keep echo cancel off unless using speakers
        noiseSuppress: false, // OS-level noise suppression
      ),
    );

    _subscription = recordStream.listen((Uint8List rawData) {
      // Ensure 16-bit alignment for downstream operations
      if (rawData.offsetInBytes % 2 != 0) {
        rawData = Uint8List.fromList(rawData);
      }

      Uint8List allBytes;
      if (_frameBuffer.isEmpty) {
        allBytes = rawData;
      } else {
        allBytes = Uint8List(_frameBuffer.length + rawData.length);
        allBytes.setAll(0, _frameBuffer);
        allBytes.setAll(_frameBuffer.length, rawData);
      }

      int offset = 0;
      // We process strictly in chunkBytes (160ms) blocks
      while (allBytes.length - offset >= chunkBytes) {
        final chunk = Uint8List.view(
          allBytes.buffer,
          allBytes.offsetInBytes + offset,
          chunkBytes,
        );
        offset += chunkBytes;

        final chunkCopy = Uint8List.fromList(chunk);

        // Feed chunk to VAD
        final int16 = chunkCopy.buffer.asInt16List(
          chunkCopy.offsetInBytes,
          chunkCopy.lengthInBytes ~/ 2,
        );
        
        // Pass the raw, unmodified audio directly to the VAD buffer.
        // We do not apply any static gain or artificial limiting, as it can
        // distort the audio before entering the ASR and VAD.
        for (int i = 0; i < int16.length; i++) {
          _reusableVadBuffer[i] = int16[i] / 32768.0;
        }

        _vad!.acceptWaveform(
          Float32List.sublistView(_reusableVadBuffer, 0, int16.length),
        );
        bool isDetected = _vad!.isDetected();

        if (isDetected) {
          _silenceMs = 0;
          if (!_vadWasDetected) {
            _vadWasDetected = true;
            // Flush pre-roll
            for (var pr in _preRollBufferList) {
              onChunk(pr, false);
            }
            _preRollBufferList.clear();
          }
          onChunk(chunkCopy, false);
        } else {
          if (_vadWasDetected) {
            _silenceMs += chunkMs; // 320ms per frame

            // Use a stable 3500ms threshold to give plenty of breathing room.
            int thresholdMs = 3500;

            if (_silenceMs >= thresholdMs) {
              // Silence duration exceeded the dynamic threshold
              onChunk(Uint8List(0), true);
              _vadWasDetected = false;
              _silenceMs = 0;
            } else {
              // Protect potential Madds! Send audio even if VAD thinks it's silence.
              onChunk(chunkCopy, false);
            }
          } else {
            // Not detected: maintain pre-roll to catch the onset when speech starts
            _preRollBufferList.add(chunkCopy);
            if (_preRollBufferList.length > maxPreRollFrames) {
              _preRollBufferList.removeAt(0);
            }
          }
        }
      }

      // Keep the remainder for the next stream event
      if (offset < allBytes.length) {
        _frameBuffer = Uint8List.fromList(
          Uint8List.view(allBytes.buffer, allBytes.offsetInBytes + offset),
        );
      } else {
        _frameBuffer = Uint8List(0);
      }
    });
  }

  void clearBuffer() {
    // Left for compatibility with Orhcestrator
  }

  Future<void> stopAndGetAudio() async {
    await _subscription?.cancel();
    _subscription = null;

    await _recorder?.stop();
    await _recorder?.dispose();
    _recorder = null;

    _frameBuffer = Uint8List(0);
    _vadWasDetected = false;
    _silenceMs = 0;
    _preRollBufferList.clear();
    _vad?.reset();
  }
}

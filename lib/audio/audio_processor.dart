import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class AudioProcessor {
  // ── Audio format constants ─────────────────────────────────────────────────
  /// The sample rate that the ASR model and VAD expect.
  static const int targetSampleRate = 16000;

  static const int recordSampleRate = 16000;
  static const int numChannels = 1;
  static const int bytesPerSample = 2; // 16-bit PCM

  static const int chunkMs = 100;

  static const int recordChunkBytes =
      (recordSampleRate * numChannels * bytesPerSample * chunkMs) ~/ 1000;

  Uint8List _frameBuffer = Uint8List(0);
  final List<double> _debugAudioBuffer = [];

  // ── No VAD ─────────────────────────────────────────────────────────────
  // We stream all audio directly to Sherpa ONNX. This completely eliminates
  // the problem of dropped phonemes and calibration issues between different
  // devices' microphone sensitivities.

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;

  Future<void> start({
    required void Function(Float32List chunk, bool isFinal) onChunk,
  }) async {
    await stopAndGetAudio();

    _recorder = AudioRecorder();

    if (kDebugMode) {
      debugPrint('[AudioProcessor] Recording at ${recordSampleRate}Hz');
    }

    final recordStream = await _recorder!.startStream(
      // We explicitly disable ALL hardware processing to ensure the "ه"
      // breathy sound isn't filtered out as background noise by Android.
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: recordSampleRate, // 16000
        numChannels: numChannels,
        autoGain: true,
        echoCancel: false,
        noiseSuppress: false,
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
      // Process in exact 320ms blocks
      while (allBytes.length - offset >= recordChunkBytes) {
        final byteView = Uint8List.view(
          allBytes.buffer,
          allBytes.offsetInBytes + offset,
          recordChunkBytes,
        );
        offset += recordChunkBytes;

        final int16samples = Int16List.view(
          byteView.buffer,
          byteView.offsetInBytes,
          recordChunkBytes ~/ bytesPerSample,
        );

        final float32Samples = Float32List(int16samples.length);
        double peakAmplitude = 0.0;
        const double volumeBoost =
            25.0; // Lowered from 50.0 to prevent 1.0000 clipping

        for (int i = 0; i < int16samples.length; i++) {
          // Pure linear volume boost (no non-linear compression!)
          double floatVal = (int16samples[i] / 32768.0) * volumeBoost;

          // Hard limit to prevent digital wrap-around, but preserve 100% of the acoustic harmonics below 1.0
          if (floatVal > 1.0) floatVal = 1.0;
          if (floatVal < -1.0) floatVal = -1.0;

          float32Samples[i] = floatVal;

          if (floatVal.abs() > peakAmplitude) {
            peakAmplitude = floatVal.abs();
          }
        }

        // ── NOISE GATE (Fixes broken hardware suppression) ──
        // If the loudest sound in this 320ms window is just the amplified
        // room hiss/static (e.g. < 0.15), we zero out the entire chunk.
        // Pure 0.0 tells Kaldi to stop hallucinating fricatives and wait.
        if (peakAmplitude < 0.15) {
          float32Samples.fillRange(0, float32Samples.length, 0.0);
        }

        if (kDebugMode) {
          debugPrint(
            '[AudioProcessor] Peak Amplitude: ${peakAmplitude.toStringAsFixed(4)}',
          );
        }

        _debugAudioBuffer.addAll(float32Samples);

        // Stream all audio directly to Sherpa ASR!
        onChunk(float32Samples, false);
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
    // Left for compatibility with Orchestrator
  }

  Future<void> stopAndGetAudio() async {
    await _subscription?.cancel();
    _subscription = null;

    await _recorder?.stop();
    await _recorder?.dispose();
    _recorder = null;

    _frameBuffer = Uint8List(0);

    if (_debugAudioBuffer.isNotEmpty) {
      try {
        File file;
        try {
          // Try to save directly to the public Downloads folder so you can open it on your phone easily
          file = File('/storage/emulated/0/Download/debug_kaldi_audio.wav');
          // Touch the file to see if we have permissions
          if (!file.existsSync()) file.createSync(recursive: true);
        } catch (_) {
          // Fallback to Android/data/com.recitequran/files/ if Downloads is blocked by Android 11+ permissions
          final extDir = await getExternalStorageDirectory();
          file = File('${extDir?.path}/debug_kaldi_audio.wav');
        }

        final pcmBytes = Uint8List(_debugAudioBuffer.length * 2);
        final ByteData byteData = ByteData.view(pcmBytes.buffer);
        for (int i = 0; i < _debugAudioBuffer.length; i++) {
          double f = _debugAudioBuffer[i];
          if (f > 1.0) f = 1.0;
          if (f < -1.0) f = -1.0;
          int intVal = (f * 32767.0).toInt();
          byteData.setInt16(i * 2, intVal, Endian.little);
        }

        final header = _buildWavHeader(pcmBytes.length);
        final fileBytes = BytesBuilder()
          ..add(header)
          ..add(pcmBytes);

        await file.writeAsBytes(fileBytes.takeBytes());
        debugPrint('💾 DEBUG WAV SAVED TO: ${file.path}');
      } catch (e) {
        debugPrint('❌ Failed to save WAV: $e');
      }
      _debugAudioBuffer.clear();
    }
  }

  Uint8List _buildWavHeader(int dataLength) {
    final channels = 1;
    final sampleRate = 16000;
    final byteRate = sampleRate * channels * 2; // 16-bit

    final header = Uint8List(44);
    final ByteData bd = ByteData.view(header.buffer);

    bd.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    bd.setUint32(4, 36 + dataLength, Endian.little);
    bd.setUint32(8, 0x57415645, Endian.big); // "WAVE"
    bd.setUint32(12, 0x666D7420, Endian.big); // "fmt "
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, channels * 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    bd.setUint32(36, 0x64617461, Endian.big); // "data"
    bd.setUint32(40, dataLength, Endian.little);

    return header;
  }
}

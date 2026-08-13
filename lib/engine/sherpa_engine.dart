// lib/engine/sherpa_engine.dart
// Cache-aware streaming CTC engine for Muno459/quran_phoneme_zipformer (Muno459/zipformer_p-arabic)
//
// Model specs:
//   Architecture     = Zipformer2 causal streaming CTC (~65.5M parameters)
//   Tokens/Units     = 250 phoneme units (consonant+ḥaraka units) + blank_id
//   Front end        = 80-bin kaldi fbank (povey window, 25ms / 10ms shift, 16 kHz)
//   decode_chunk_len = 24 encoder frames / step (1000ms streaming profile -> 5.83 WER / 11.63% PER)
//   left_context     = 256 encoder frames cache
//   subsampling      = 8
//   hop_length       = 160 samples (10ms)
//   → 1 encoder frame = 80ms of audio

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

import '../utils/debug_logger.dart';
import 'models/sherpa_protocol.dart';

class TranscriptionResult {
  final String text;
  final bool isFinal;
  final int startTime;
  final List<String> tokens;
  final List<double> timestamps;
  final List<double> ysProbs;
  final int streamEpoch;

  TranscriptionResult({
    required this.text,
    this.isFinal = false,
    this.startTime = 0,
    this.tokens = const [],
    this.timestamps = const [],
    this.ysProbs = const [],
    this.streamEpoch = 0,
  });
}

class SherpaEngine {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;

  final StreamController<TranscriptionResult> _outputController =
      StreamController<TranscriptionResult>.broadcast();

  bool _isInitialized = false;
  Future<void>? _initFuture;
  final List<SherpaCommand> _pendingChunks = [];
  int _currentStreamEpoch = 0;

  bool get isInitialized => _isInitialized;
  int get currentStreamEpoch => _currentStreamEpoch;
  Stream<TranscriptionResult> get transcriptionStream =>
      _outputController.stream;

  Future<String> _extractAsset(String assetPath) async {
    final Directory docDir = await getApplicationSupportDirectory();
    final String prefix = 'v2_zipformer_';
    final File file = File(
      '${docDir.path}/$prefix${assetPath.split('/').last}',
    );

    if (await file.exists()) {
      return file.path;
    }

    final targetPath = file.path;

    // Load asset on the main thread where ServicesBinding is initialized
    final ByteData data = await rootBundle.load(assetPath);
    final Uint8List bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    // Transfer ownership of the massive byte array to the background isolate
    // to prevent a 130MB Out-Of-Memory (OOM) copy spike on low-RAM devices (e.g. Redmi).
    final transferable = TransferableTypedData.fromList([bytes]);

    // Write to disk in a background isolate to prevent UI freezing
    await Isolate.run(() async {
      final transferredBytes = transferable.materialize().asUint8List();
      await File(targetPath).writeAsBytes(transferredBytes, flush: true);
    });

    if (await file.length() == 0) {
      throw Exception(
        'CRITICAL: $assetPath copied as 0 bytes — check pubspec.yaml.',
      );
    }

    return file.path;
  }

  /// Pre-extract model assets from bundle to app documents directory.
  Future<void> preExtractAssets() async {
    await _extractAsset('assets/model/zipformer_p_arabic_v2.int8.onnx');
    await _extractAsset('assets/model/tokens.txt');
  }

  Future<void> initialize() {
    if (_isInitialized) return Future.value();
    if (_initFuture != null) return _initFuture!;
    _initFuture = _doInitialize();
    return _initFuture!;
  }

  Future<void> _doInitialize() async {
    _currentStreamEpoch = 0;
    if (_isolate != null) {
      if (_sendPort != null) {
        _sendPort!.send(const SherpaDestroyCommand());
        await Future.delayed(const Duration(milliseconds: 100));
      }
      _isolate?.kill(priority: Isolate.immediate);
    }
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;

    final String modelPath = await _extractAsset(
      'assets/model/zipformer_p_arabic_v2.int8.onnx',
    );
    final String tokensPath = await _extractAsset('assets/model/tokens.txt');

    final completer = Completer<void>();
    _receivePort = ReceivePort();

    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _sendPort!.send(
          SherpaInitCommand(modelPath: modelPath, tokensPath: tokensPath),
        );
      } else if (message is SherpaInitSuccessEvent) {
        _isInitialized = true;
        _initFuture = null;
        completer.complete();
        for (final pending in _pendingChunks) {
          _sendPort?.send(pending);
        }
        _pendingChunks.clear();
      } else if (message is SherpaInitErrorEvent) {
        _initFuture = null;
        completer.completeError(Exception(message.error));
      } else if (message is SherpaTranscriptionEvent) {
        final int latency =
            DateTime.now().millisecondsSinceEpoch - message.startTime;

        if (kDebugMode) {
          DebugLogger.updateAsrBuffer(message.text);

          if (message.isFinal) {
            DebugLogger.log('ASR', '⚡ Endpoint detected (${latency}ms)');
          }

          if (message.ysProbs.isNotEmpty) {
            final minLogProb = message.ysProbs.reduce(
              (curr, next) => curr < next ? curr : next,
            );
            final double minConfidencePercentage = exp(minLogProb) * 100;
            if (minConfidencePercentage < 80.0) {
              DebugLogger.log(
                'ASR-CONFIDENCE',
                '⚠️ Low confidence detected: ${minConfidencePercentage.toStringAsFixed(1)}%',
              );
            }
          }
        }

        _outputController.add(
          TranscriptionResult(
            text: message.text,
            isFinal: message.isFinal,
            startTime: message.startTime,
            tokens: message.tokens,
            timestamps: message.timestamps,
            ysProbs: message.ysProbs,
            streamEpoch: message.streamEpoch,
          ),
        );
      }
    });

    _isolate = await Isolate.spawn(_isolateEntry, _receivePort!.sendPort);
    await completer.future;
  }

  /// Feed a normalized float chunk [-1.0, 1.0] (16 kHz mono) into the recognizer.
  bool transcribe(Float32List audioChunk, {bool isFinal = false}) {
    final transferable = TransferableTypedData.fromList([audioChunk]);
    final cmd = SherpaRecognizeCommand(
      chunk: transferable,
      isFinal: isFinal,
      startTime: DateTime.now().millisecondsSinceEpoch,
    );

    if (!_isInitialized) {
      if (_initFuture != null) {
        _pendingChunks.add(cmd);
      }
      return true;
    }

    _sendPort?.send(cmd);
    return true;
  }

  /// Hard reset: wipes the Sherpa stream and primes with silence.
  void resetBuffer() {
    _currentStreamEpoch++;
    _pendingChunks.clear();
    final cmd = const SherpaResetCommand();
    if (!_isInitialized && _initFuture != null) {
      _pendingChunks.add(cmd);
    } else {
      _sendPort?.send(cmd);
    }
  }

  /// Flush-then-Reset: crosses an Ayah boundary cleanly without loss of speech.
  void flushThenReset() {
    _currentStreamEpoch++;
    _pendingChunks.clear();
    final cmd = const SherpaFlushCommand();
    if (!_isInitialized && _initFuture != null) {
      _pendingChunks.add(cmd);
    } else {
      _sendPort?.send(cmd);
    }
  }

  void destroy() {
    if (!_isInitialized && _isolate == null) return;
    _isInitialized = false;
    _initFuture = null;
    _pendingChunks.clear();
    _sendPort?.send(const SherpaDestroyCommand());
    Future.delayed(const Duration(milliseconds: 200), () {
      _isolate?.kill(priority: Isolate.immediate);
      _receivePort?.close();
      _isolate = null;
      _sendPort = null;
      _receivePort = null;
    });
  }

  // ─── Isolate Worker ────────────────────────────────────────────────────────
  static void _isolateEntry(SendPort mainSendPort) {
    initBindings();

    final ReceivePort port = ReceivePort();
    mainSendPort.send(port.sendPort);

    OnlineRecognizer? recognizer;
    OnlineStream? stream;
    final Float32List primingBuffer = Float32List(
      4800,
    ); // 300ms pre-roll silence
    int isolateStreamEpoch = 0;

    port.listen((msg) {
      if (msg is! SherpaCommand) return;

      switch (msg) {
        case SherpaInitCommand(:final modelPath, :final tokensPath):
          try {
            if (!File(modelPath).existsSync() ||
                !File(tokensPath).existsSync()) {
              throw Exception('CRITICAL: ONNX model files missing on disk.');
            }

            OnlineRecognizer? tryCreateRecognizer(String provider) {
              return OnlineRecognizer(
                OnlineRecognizerConfig(
                  feat: FeatureConfig(sampleRate: 16000, featureDim: 80),
                  model: OnlineModelConfig(
                    zipformer2Ctc: OnlineZipformer2CtcModelConfig(
                      model: modelPath,
                    ),
                    tokens: tokensPath,
                    numThreads: 2,
                    modelType: 'zipformer2_ctc',
                    provider: provider,
                    debug: kDebugMode,
                  ),
                  enableEndpoint: true,
                  rule1MinTrailingSilence: 10.0,
                  rule2MinTrailingSilence:
                      4.0, // Increased to 4s for Voice Search
                  rule3MinUtteranceLength:
                      9999.0, // Effectively disabled max utterance length
                ),
              );
            }

            try {
              recognizer = tryCreateRecognizer(
                Platform.isAndroid ? 'xnnpack' : 'cpu',
              );
            } catch (e) {
              if (Platform.isAndroid) {
                // Cannot use DebugLogger directly in isolate, send via port
                // Hardware acceleration failed (Custom ROM HAL). Falling back to pure CPU.
                recognizer = tryCreateRecognizer('cpu');
              } else {
                rethrow;
              }
            }

            stream = recognizer!.createStream();
            stream!.acceptWaveform(sampleRate: 16000, samples: primingBuffer);
            while (recognizer!.isReady(stream!)) {
              recognizer!.decode(stream!);
            }

            mainSendPort.send(const SherpaInitSuccessEvent());
          } catch (e) {
            mainSendPort.send(SherpaInitErrorEvent(e.toString()));
          }

        case SherpaRecognizeCommand(
          :final chunk,
          :final isFinal,
          :final startTime,
        ):
          if (recognizer == null || stream == null) return;

          final rawBytesTemp = chunk.materialize().asUint8List();
          final rawBytes = rawBytesTemp.offsetInBytes % 4 != 0
              ? Uint8List.fromList(rawBytesTemp)
              : rawBytesTemp;

          if (rawBytes.isNotEmpty) {
            final floats = rawBytes.buffer.asFloat32List(
              rawBytes.offsetInBytes,
              rawBytes.lengthInBytes ~/ 4,
            );
            stream!.acceptWaveform(sampleRate: 16000, samples: floats);
          }

          while (recognizer!.isReady(stream!)) {
            recognizer!.decode(stream!);
          }

          List<double> extractYsProbs(dynamic result) {
            try {
              return List<double>.from(result.ysProbs);
            } catch (_) {
              return [];
            }
          }

          final partial = recognizer!.getResult(stream!);
          final bool endpointDetected = recognizer!.isEndpoint(stream!);

          if (!endpointDetected && !isFinal) {
            mainSendPort.send(
              SherpaTranscriptionEvent(
                text: partial.text,
                tokens: List<String>.from(partial.tokens),
                timestamps: List<double>.from(partial.timestamps),
                ysProbs: extractYsProbs(partial),
                isFinal: false,
                startTime: startTime,
                streamEpoch: isolateStreamEpoch,
              ),
            );
          }

          if (isFinal || endpointDetected) {
            if (isFinal) {
              stream!.inputFinished();
            }
            while (recognizer!.isReady(stream!)) {
              recognizer!.decode(stream!);
            }
            final finalResult = recognizer!.getResult(stream!);

            mainSendPort.send(
              SherpaTranscriptionEvent(
                text: finalResult.text,
                tokens: List<String>.from(finalResult.tokens),
                timestamps: List<double>.from(finalResult.timestamps),
                ysProbs: extractYsProbs(finalResult),
                isFinal: true,
                startTime: startTime,
                streamEpoch: isolateStreamEpoch,
              ),
            );
          }

        case SherpaFlushCommand():
          break;

        case SherpaResetCommand():
          isolateStreamEpoch++;
          if (recognizer != null && stream != null) {
            recognizer!.reset(stream!);
            stream!.acceptWaveform(sampleRate: 16000, samples: primingBuffer);
            while (recognizer!.isReady(stream!)) {
              recognizer!.decode(stream!);
            }
          }

        case SherpaDestroyCommand():
          stream?.free();
          recognizer?.free();
          stream = null;
          recognizer = null;
      }
    });
  }
}

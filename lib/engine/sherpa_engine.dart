// lib/engine/sherpa_engine.dart
// Cache-aware streaming CTC engine for Muno459/quran_phoneme_zipformer (Muno459/zipformer_p-arabic)
//
// Model specs (from official model documentation & ONNX metadata):
//   Architecture     = Zipformer2 causal streaming CTC (~65.5M parameters)
//   Tokens/Units     = 250 phoneme units (consonant+ḥaraka units) + blank_id
//   Front end        = 80-bin kaldi fbank (povey window, 25ms / 10ms shift, 16 kHz)
//   decode_chunk_len = 24 encoder frames / step (1000ms streaming profile -> 5.83 WER / 11.63% PER)
//   left_context     = 256 encoder frames cache
//   subsampling      = 8
//   hop_length       = 160 samples (10ms)
//   → 1 encoder frame = 80ms of audio
//
// Sherpa-ONNX uses OnlineZipformer2CtcModelConfig which handles the cache tensors
// internally — we just call acceptWaveform() and decode().

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';
import '../utils/debug_logger.dart';

class TranscriptionResult {
  final String text;
  final bool isFinal;
  final int startTime;
  final List<String> tokens;
  final List<double> timestamps;

  // Newly merged SherpaONNX deep metrics
  final List<double> ysProbs;

  TranscriptionResult({
    required this.text,
    this.isFinal = false,
    this.startTime = 0,
    this.tokens = const [],
    this.timestamps = const [],
    this.ysProbs = const [],
  });
}

enum _EngineCommand { init, recognize, reset, flushThenReset, destroy }

class _IsolateMessage {
  final _EngineCommand command;
  final dynamic payload;
  _IsolateMessage(this.command, [this.payload]);
}

class SherpaEngine {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;

  final StreamController<TranscriptionResult> _outputController =
      StreamController<TranscriptionResult>.broadcast();

  bool _isInitialized = false;
  Future<void>? _initFuture;
  final List<Map<String, dynamic>> _pendingChunks = [];

  bool get isInitialized => _isInitialized;
  Stream<TranscriptionResult> get transcriptionStream =>
      _outputController.stream;

  Future<String> _extractAsset(String assetPath) async {
    final Directory docDir = await getApplicationSupportDirectory();
    // Prefix with version to force re-extraction on updates
    final String prefix = 'v2_zipformer_';
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
    if (_isolate != null) {
      if (_sendPort != null) {
        _sendPort!.send(_IsolateMessage(_EngineCommand.destroy));
        await Future.delayed(
          const Duration(milliseconds: 100),
        ); // Give C++ time to free memory
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
          _IsolateMessage(_EngineCommand.init, {
            'modelPath': modelPath,
            'tokensPath': tokensPath,
          }),
        );
      } else if (message == 'INIT_DONE') {
        _isInitialized = true;
        _initFuture = null;
        completer.complete();
        for (final pending in _pendingChunks) {
          final transferable = TransferableTypedData.fromList([
            pending['chunk'] as Float32List,
          ]);
          _sendPort?.send(
            _IsolateMessage(_EngineCommand.recognize, {
              'chunk': transferable,
              'isFinal': pending['isFinal'],
              'startTime': pending['startTime'],
            }),
          );
        }
        _pendingChunks.clear();
      } else if (message is String && message.startsWith('INIT_ERROR:')) {
        _initFuture = null;
        completer.completeError(Exception(message.substring(11)));
      } else if (message is Map) {
        final int startTime = message['startTime'] as int;
        final int latency = DateTime.now().millisecondsSinceEpoch - startTime;

        final ysProbs = List<double>.from(message['ysProbs'] ?? []);
        final text = message['text'] as String;
        final bool isFinal = message['isFinal'] as bool;

        if (kDebugMode) {
          DebugLogger.updateAsrBuffer(text);

          if (isFinal) {
            DebugLogger.log('ASR', '⚡ Endpoint detected (${latency}ms)');
          }

          DebugLogger.log('ASR-METRICS', '--- VERIFYING SHERPA METRICS ---');
          DebugLogger.log('ASR-METRICS', 'RAW Tokens:  ${message['tokens']}');
          DebugLogger.log('ASR-METRICS', 'RAW ysProbs: $ysProbs');
          DebugLogger.log('ASR-METRICS', '---------------------------------');

          // Debug Print: Check if any token had unusually low acoustic confidence
          if (ysProbs.isNotEmpty) {
            final minLogProb = ysProbs.reduce(
              (curr, next) => curr < next ? curr : next,
            );
            // Convert log-probability to a percentage (e.g., -0.001818 -> 0.998 -> 99.8%)
            final double minConfidencePercentage = exp(minLogProb) * 100;

            // Now we can use normal percentages. If confidence drops below 80%:
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
            text: text,
            isFinal: isFinal,
            startTime: startTime,
            tokens: List<String>.from(message['tokens'] ?? []),
            timestamps: List<double>.from(message['timestamps'] ?? []),
            ysProbs: ysProbs,
          ),
        );
      }
    });

    _isolate = await Isolate.spawn(_isolateEntry, _receivePort!.sendPort);
    await completer.future;
  }

  /// Feed a normalized float chunk [-1.0, 1.0] (16 kHz mono) into the recognizer.
  /// [isFinal] = true flushes the current utterance.
  bool transcribe(Float32List audioChunk, {bool isFinal = false}) {
    if (!_isInitialized) {
      if (_initFuture != null) {
        _pendingChunks.add({
          'chunk': audioChunk,
          'isFinal': isFinal,
          'startTime': DateTime.now().millisecondsSinceEpoch,
        });
      }
      return true;
    }
    final transferable = TransferableTypedData.fromList([audioChunk]);
    _sendPort?.send(
      _IsolateMessage(_EngineCommand.recognize, {
        'chunk': transferable,
        'isFinal': isFinal,
        'startTime': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    return true;
  }

  /// Hard reset: wipes the Sherpa stream and primes with silence.
  /// Use ONLY for explicit user actions (stop button, manual ayah jump).
  /// Do NOT call at automatic ayah boundaries — use [flushThenReset] instead.
  void resetBuffer() {
    _pendingChunks.clear();
    _sendPort?.send(_IsolateMessage(_EngineCommand.reset));
  }

  /// Flush-then-Reset: the correct way to cross an ayah boundary.
  ///
  /// The Zipformer model was trained on isolated ayah clips. Carrying cache
  /// state across a boundary is out-of-distribution and causes hallucinations.
  ///
  /// Order (per model author's warning):
  ///   1. Push ~1.05 s of silence through the CURRENT live cache
  ///      → drains the right-context buffer and emits the last-word tail
  ///   2. Collect and emit whatever comes out as isFinal=true
  ///   3. THEN zero the states for the next ayah
  ///   4. Feed 300ms priming silence for the next ayah's left-context
  void flushThenReset() {
    _pendingChunks.clear();
    _sendPort?.send(_IsolateMessage(_EngineCommand.flushThenReset));
  }

  void destroy() {
    if (!_isInitialized && _isolate == null) return;
    _isInitialized = false;
    _initFuture = null;
    _pendingChunks.clear();
    _sendPort?.send(_IsolateMessage(_EngineCommand.destroy));
    Future.delayed(const Duration(milliseconds: 200), () {
      _isolate?.kill(priority: Isolate.immediate);
      _receivePort?.close();
      _isolate = null;
      _sendPort = null;
      _receivePort = null;
    });
  }

  // ─── Isolate ──────────────────────────────────────────────────────────────
  static void _isolateEntry(SendPort mainSendPort) {
    initBindings();

    final ReceivePort port = ReceivePort();
    mainSendPort.send(port.sendPort);

    OnlineRecognizer? recognizer;
    OnlineStream? stream;
    final Float32List primingBuffer = Float32List(
      4800,
    ); // 300ms pre-roll silence initialized once

    port.listen((message) {
      if (message is! _IsolateMessage) return;

      switch (message.command) {
        case _EngineCommand.init:
          final paths = message.payload as Map<String, String>;
          try {
            if (!File(paths['modelPath']!).existsSync() ||
                !File(paths['tokensPath']!).existsSync()) {
              throw Exception('CRITICAL: ONNX model files missing on disk.');
            }

            OnlineRecognizer? tryCreateRecognizer(String provider) {
              return OnlineRecognizer(
                OnlineRecognizerConfig(
                  feat: FeatureConfig(sampleRate: 16000, featureDim: 80),
                  model: OnlineModelConfig(
                    zipformer2Ctc: OnlineZipformer2CtcModelConfig(
                      model: paths['modelPath']!,
                    ),
                    tokens: paths['tokensPath']!,
                    numThreads:
                        2, // 2 threads gives ~40% latency reduction on mobile multi-core ARM chips
                    modelType: 'zipformer2_ctc',
                    provider: provider,
                    debug: kDebugMode,
                  ),
                  enableEndpoint: true,
                  rule1MinTrailingSilence: 10.0,
                  rule2MinTrailingSilence: 2.2,
                  rule3MinUtteranceLength: 30.0,
                ),
              );
            }

            try {
              recognizer = tryCreateRecognizer(
                Platform.isAndroid ? 'xnnpack' : 'cpu',
              );
            } catch (providerError) {
              if (Platform.isAndroid) {
                // Fallback gracefully to 'cpu' if xnnpack/NEON is unsupported on this chipset
                recognizer = tryCreateRecognizer('cpu');
              } else {
                rethrow;
              }
            }

            stream = recognizer!.createStream();

            // Priming preroll: feed 300ms of pre-allocated silence and decode immediately
            // so the zeros prime the Zipformer attention cache (left_context) for the VERY FIRST utterance!
            stream!.acceptWaveform(sampleRate: 16000, samples: primingBuffer);
            while (recognizer!.isReady(stream!)) {
              recognizer!.decode(stream!);
            }

            mainSendPort.send('INIT_DONE');
          } catch (e) {
            mainSendPort.send('INIT_ERROR:$e');
          }

        case _EngineCommand.recognize:
          if (recognizer == null || stream == null) return;

          final payload = message.payload as Map<String, dynamic>;
          final transferable = payload['chunk'] as TransferableTypedData;
          final rawBytesTemp = transferable.materialize().asUint8List();
          final rawBytes = rawBytesTemp.offsetInBytes % 4 != 0
              ? Uint8List.fromList(rawBytesTemp)
              : rawBytesTemp;
          final isFinal = payload['isFinal'] as bool;
          final startTime = payload['startTime'] as int;

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
          // ════════════════════════════════════════════════════════════════════════════
          // [CROSS-PLATFORM COMPATIBILITY]
          // If the iOS/Web version uses the OFFICIAL unmodified sherpa_onnx package,
          // the `OnlineRecognizerResult` class will NOT have the `ysProbs` property.
          // To prevent Dart from throwing a compiler error or crashing the app, we
          // cast the result to `dynamic` and try to extract it at runtime. If it fails,
          // we gracefully return an empty array `[]`.
          // ════════════════════════════════════════════════════════════════════════════
          List<double> extractYsProbs(dynamic result) {
            try {
              return List<double>.from(result.ysProbs);
            } catch (_) {
              return [];
            }
          }

          final partial = recognizer!.getResult(stream!);
          bool endpointDetected = recognizer!.isEndpoint(stream!);

          // If endpoint isn't detected and it's not manually finalized, send partial.
          if (!endpointDetected && !isFinal) {
            mainSendPort.send({
              'text': partial.text,
              'tokens': partial.tokens,
              'timestamps': partial.timestamps,
              'ysProbs': extractYsProbs(partial),
              'isFinal': false,
              'startTime': startTime,
            });
          }

          if (isFinal || endpointDetected) {
            if (isFinal) {
              stream!.inputFinished();
            }
            while (recognizer!.isReady(stream!)) {
              recognizer!.decode(stream!);
            }
            final final_ = recognizer!.getResult(stream!);

            mainSendPort.send({
              'text': final_.text,
              'tokens': final_.tokens,
              'timestamps': final_.timestamps,
              'ysProbs': extractYsProbs(final_),
              'isFinal': true,
              'startTime': startTime,
            });
            // ── IMPORTANT: Do NOT reset the stream here ──────────────────────
            // The model was trained on isolated ayah clips. Resetting the cache
            // automatically on every VAD silence endpoint is WRONG during tracking:
            //   - A reciter may pause mid-ayah (breath). Resetting destroys the
            //     left-context that helps the model track the current ayah.
            //   - At a true ayah boundary, the HighlightingController calls
            //     flushThenReset() which properly drains the right-context buffer
            //     BEFORE zeroing state, preventing loss of the last word's tail.
            // We intentionally leave the stream/cache live here.
            // ─────────────────────────────────────────────────────────────────
          }

        case _EngineCommand.flushThenReset:
          // ── Flush-then-Reset (Ayah Boundary) ────────────────────────────────
          // Step 1: Push ~1.05 s of silence through the LIVE cache.
          //   The Zipformer right-context buffer is ~1.05 s (encode 1000ms profile).
          //   Feeding zeros through the current stream causes the model to flush
          //   whatever partial phonemes are still in its right-context window.
          //   This guarantees the final word's tail is emitted before we reset.
          if (recognizer != null && stream != null) {
            // 1.05 s of silence at 16 kHz = 16,800 samples
            final flushSilence = Float32List(16800);
            stream!.acceptWaveform(sampleRate: 16000, samples: flushSilence);
            while (recognizer!.isReady(stream!)) {
              recognizer!.decode(stream!);
            }

            // Step 2: Emit whatever came out of the flush as a final result.
            final flushed = recognizer!.getResult(stream!);
            if (flushed.text.isNotEmpty) {
              mainSendPort.send({
                'text': flushed.text,
                'tokens': flushed.tokens,
                'timestamps': flushed.timestamps,
                'ysProbs': <double>[],
                'isFinal': true,
                'startTime': DateTime.now().millisecondsSinceEpoch,
              });
            }

            // Step 3: NOW zero the states — cache is fully drained.
            recognizer!.reset(stream!);

            // Step 4: Prime the fresh cache with 300ms silence so the next ayah
            // starts with a warmed left-context (not cold zeros).
            stream!.acceptWaveform(sampleRate: 16000, samples: primingBuffer);
            while (recognizer!.isReady(stream!)) {
              recognizer!.decode(stream!);
            }
          }

        case _EngineCommand.reset:
          // ── Hard Reset (explicit user action only) ───────────────────────────
          // Used for: stop button, manual ayah jump, voice search start.
          // NOT used for automatic ayah-advance (use flushThenReset for that).
          if (recognizer != null && stream != null) {
            recognizer!.reset(stream!);
            // Priming preroll: feed 300ms of pre-allocated silence and decode immediately
            // so the zeros prime the Zipformer attention cache (left_context) without delaying incoming speech!
            stream!.acceptWaveform(sampleRate: 16000, samples: primingBuffer);
            while (recognizer!.isReady(stream!)) {
              recognizer!.decode(stream!);
            }
          }

        case _EngineCommand.destroy:
          stream?.free();
          recognizer?.free();
          stream = null;
          recognizer = null;
      }
    });
  }
}

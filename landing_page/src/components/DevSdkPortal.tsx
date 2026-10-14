import React, { useState } from 'react';
import { LangMode } from '../types';
import { RAWIS_DATA, COUNTING_SCHOOLS } from '../data/recitationData';
import {
  Code2,
  Copy,
  Check,
  Search,
  ArrowUpRight,
  Sparkles,
  Zap,
  Sliders,
  Radio,
  Book,
  DownloadCloud,
  FileCode,
  ShieldCheck,
  Smartphone,
  Gauge,
  Layers,
  HelpCircle,
  ExternalLink,
  Info
} from 'lucide-react';

interface DevSdkPortalProps {
  lang: LangMode;
}

export const DevSdkPortal: React.FC<DevSdkPortalProps> = ({ lang }) => {
  const isAr = lang === 'ar';
  const [activeTab, setActiveTab] = useState<string>('quickstart');
  const [copiedKey, setCopiedKey] = useState<string | null>(null);
  const [apiSearchQuery, setApiSearchQuery] = useState<string>('');

  // Interactive TrackerConfig Live Generator State
  const [configSpeed, setConfigSpeed] = useState<'normal' | 'fast' | 'slow'>('normal');
  const [configStrictness, setConfigStrictness] = useState<'normal' | 'strict' | 'easy'>('normal');
  const [configEarlyMatching, setConfigEarlyMatching] = useState<boolean>(true);
  const [configAutoReanchor, setConfigAutoReanchor] = useState<boolean>(true);
  const [configStallThreshold, setConfigStallThreshold] = useState<number>(24);

  const copyToClipboard = (text: string, key: string) => {
    navigator.clipboard.writeText(text);
    setCopiedKey(key);
    setTimeout(() => setCopiedKey(null), 2000);
  };

  const tabs = [
    { id: 'quickstart', label: isAr ? 'البدء السريع' : '⚡ 60s Quickstart' },
    { id: 'generator', label: isAr ? 'مولد الإعدادات' : '⚙️ Config Generator' },
    { id: 'audio', label: isAr ? 'الصوت والصلاحيات' : '🎧 Audio & Permissions' },
    { id: 'search', label: isAr ? 'البحث الصوتي' : '🎙️ Voice Search' },
    { id: 'tajweed', label: isAr ? 'لوحة التجويد' : '🎯 Tajweed Sheet' },
    { id: 'riwayat', label: isAr ? 'الروايات ومذاهب العد' : '📖 20 Rawis Map' },
    { id: 'model', label: isAr ? 'تضمين النموذج' : '📦 Model Deployment' },
    { id: 'state', label: isAr ? 'إدارة الحالة' : '🧩 State Architecture' },
    { id: 'api', label: isAr ? 'مرجع الدوال' : '⚡ API Reference' },
  ];

  const generatedDartConfig = `// Generated from ReciteQuran Config Builder
final config = TrackerConfig(
  recitationSpeed: RecitationSpeed.${configSpeed},
  matchingStrictness: MatchingStrictness.${configStrictness},
  enableEarlyMatching: ${configEarlyMatching}, // ${configEarlyMatching ? 'Frontier Shield active: eliminates long vowel lag' : 'Requires reciter to complete full vowel duration'}
  enableAutoReanchor: ${configAutoReanchor}, // ${configAutoReanchor ? 'STRONGLY RECOMMENDED: Hands-free page recovery if reader skips lines' : 'Strict position lock for rigorous memorization exams'}
  reanchorStallThreshold: ${configStallThreshold}, // ~${Math.round(configStallThreshold / 6)} words stall window before re-anchoring
);`;

  const apiMethods = [
    {
      sig: 'ReciteQuran({ required QuranRepository repository, SherpaEngine? engine, TrackerConfig config, bool isTajweed })',
      desc: 'Constructor for the main tracking facade. Set isTajweed: false for fluid dictation or true for strict exam.',
      category: 'Core Engine'
    },
    {
      sig: 'Future<void> tracker.initialize()',
      desc: 'Initializes the C++ ONNX runtime engine and phonetic alignment isolate. Call once during app/page load.',
      category: 'Lifecycle'
    },
    {
      sig: 'void tracker.setTargetSurah(int surahNumber, {int startGlobalWord = 0, bool forceClear = true})',
      desc: 'Configures active recognition window. Resets phonetic buffers and aligns internal word pointers.',
      category: 'Navigation'
    },
    {
      sig: 'bool tracker.feedAudioChunk(Float32List chunk, {bool isFinal = false})',
      desc: 'Streams 16kHz Mono Float32 frames [-1.0, 1.0] from microphone into the background Zipformer neural model.',
      category: 'Audio Feeding'
    },
    {
      sig: 'Stream<WordMatchedEvent> get tracker.onWordMatched',
      desc: 'Emits live WordMatchedEvent objects containing wordId, score, cleanAsr, isGreen, isYellow, isRed, and tajweedErrors.',
      category: 'Event Stream'
    },
    {
      sig: 'Stream<String> get tracker.onTranscript',
      desc: 'Emits live raw phonetic token stream emitted directly from the Zipformer acoustic decoder.',
      category: 'Event Stream'
    },
    {
      sig: 'AudioProcessor({ int recordSampleRate = 16000, int numChannels = 1, int chunkMs = 480 })',
      desc: 'Cross-platform microphone capture engine. Automatically bypasses hardware AGC and echo cancelers.',
      category: 'Audio Pipeline'
    },
    {
      sig: 'VoiceSearchController({ required SherpaEngine engine, QuranRepository? repository })',
      desc: 'Tarteel-style "Recite to Navigate" controller. Pre-indexes all 6,236 Ayahs via 64-bit Myers bit-parallel engine.',
      category: 'Voice Navigation'
    },
    {
      sig: 'TajweedErrorSheet.show(BuildContext context, { required String wordUthmani, required List<Map> errors, bool isArabic })',
      desc: 'Pre-built bilingual bottom sheet dialog with pedagogical scholarly advice and correction remedies.',
      category: 'Tajweed UI'
    },
    {
      sig: 'LcsOmissionDetector.detectOmission({ required List<String> phonemesPerWord, required String emittedPhonemes })',
      desc: 'Best-Drop LCS algorithm detecting skipped words, shortfall, and confidence gap in Hifdh memorization mode.',
      category: 'Memorization Mode'
    },
    {
      sig: 'QiraatAyahMapper.mapAyah({ required int surah, required int ayah, required QuranRiwayah fromRiwayah, required QuranRiwayah toRiwayah })',
      desc: 'Canonical verse index translator mapping between 20 canonical Rawis and 6 counting traditions.',
      category: 'Multi-Riwayah'
    },
    {
      sig: 'ModelDownloader.downloadModel({ void Function(int received, int total)? onProgress })',
      desc: 'Streams the ~69MB Zipformer ONNX model weights on first launch, keeping app store install size under 15MB.',
      category: 'Model Deployment'
    }
  ];

  const filteredApiMethods = apiMethods.filter(
    (m) =>
      m.sig.toLowerCase().includes(apiSearchQuery.toLowerCase()) ||
      m.desc.toLowerCase().includes(apiSearchQuery.toLowerCase()) ||
      m.category.toLowerCase().includes(apiSearchQuery.toLowerCase())
  );

  return (
    <section id="developer-sdk" className="py-20 border-b border-[var(--line)]">
      <div className="max-w-[1248px] mx-auto px-4 sm:px-6">
        
        {/* Section Header */}
        <div className="flex flex-col md:flex-row md:items-end justify-between gap-6 mb-10">
          <div className="space-y-2 max-w-[760px]">
            <span className="ql-meta text-xs font-semibold tracking-wider uppercase text-[var(--brand)] font-code">
              {isAr ? 'التوثيق الرسمي لحزمة recite_quran' : 'package:recite_quran · Official Technical Portal'}
            </span>
            <h2 className="text-2xl sm:text-4xl font-extrabold tracking-[-0.02em] text-[var(--ink)]">
              {isAr ? 'التوثيق الشامل لمطوري الحزمة' : 'Complete Developer Documentation'}
            </h2>
            <p className="text-sm sm:text-[15px] text-[var(--ink-muted)] leading-[1.65]">
              {isAr
                ? 'شرح تقني شامل ودقيق مستند بالكامل إلى الكود المصدري الرسمي للحزمة على GitHub دون أي تخمين، لدمج محرك التتبع الصوتي والتجويد والبحث في تطبيقات Flutter خلال دقائق.'
                : 'Meticulously documented directly from the official GitHub repository specifications. Everything you need to integrate on-device speech tracking, Myers voice navigation, and Tajweed verification into Flutter applications.'}
            </p>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <a
              href="https://pub.dev/packages/recite_quran"
              target="_blank"
              rel="noopener noreferrer"
              className="ql-btn ql-btn-sm ql-btn-secondary font-code"
            >
              <span>pub.dev/packages/recite_quran</span>
              <ArrowUpRight className="w-3.5 h-3.5" />
            </a>
          </div>
        </div>

        {/* Master Panel */}
        <div className="ql-panel">
          
          {/* Scrollable Tab Navigation Bar */}
          <div className="flex items-center gap-1.5 p-1 overflow-x-auto">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`ql-btn ql-btn-sm ${
                  activeTab === tab.id
                    ? 'ql-btn-primary !h-[38px]'
                    : 'ql-btn-quiet text-[var(--ink-muted)] hover:text-[var(--ink)] !h-[38px]'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          {/* Raised Content Viewport */}
          <div className="ql-raised p-6 sm:p-8 space-y-8">
            
            {/* TAB 1: 60-SEC QUICKSTART */}
            {activeTab === 'quickstart' && (
              <div className="space-y-6">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-4 border-b border-[var(--line)] gap-2">
                  <div>
                    <h3 className="text-lg font-bold text-[var(--ink)]">
                      {isAr ? '⚡ دليل البدء السريع خلال دقيقة واحدة' : '⚡ 60-Second Quick Start Guide'}
                    </h3>
                    <p className="text-xs text-[var(--ink-muted)]">
                      {isAr
                        ? 'دمج تتبع الكلمات الصوتي المباشر في تطبيق Flutter في 4 خطوات بسيطة ومباشرة.'
                        : 'Embed real-time word tracking into your Flutter app in four simple steps.'}
                    </p>
                  </div>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  
                  {/* Step 1 */}
                  <div className="p-4 rounded-[var(--radius-surface)] border border-[var(--line)] bg-[var(--surface)] space-y-2">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-[var(--ink)] font-code">01. pubspec.yaml</span>
                      <button
                        onClick={() => copyToClipboard('dependencies:\n  flutter:\n    sdk: flutter\n  recite_quran: ^1.0.5', 'step1')}
                        className="p-1 rounded text-[var(--ink-muted)] hover:text-[var(--ink)] cursor-pointer"
                        title="Copy"
                      >
                        {copiedKey === 'step1' ? <Check className="w-3.5 h-3.5 text-[var(--state-correct)]" /> : <Copy className="w-3.5 h-3.5" />}
                      </button>
                    </div>
                    <pre className="p-3 rounded-[var(--radius-control)] bg-[var(--paper)] border border-[var(--line)] text-xs font-code overflow-x-auto text-[var(--ink)] leading-relaxed">
{`dependencies:
  flutter:
    sdk: flutter
  recite_quran: ^1.0.5`}
                    </pre>
                  </div>

                  {/* Step 2 */}
                  <div className="p-4 rounded-[var(--radius-surface)] border border-[var(--line)] bg-[var(--surface)] space-y-2">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-[var(--ink)] font-code">02. Download Model (69MB ONNX)</span>
                      <button
                        onClick={() => copyToClipboard('dart run recite_quran:download_model', 'step2')}
                        className="p-1 rounded text-[var(--ink-muted)] hover:text-[var(--ink)] cursor-pointer"
                        title="Copy"
                      >
                        {copiedKey === 'step2' ? <Check className="w-3.5 h-3.5 text-[var(--state-correct)]" /> : <Copy className="w-3.5 h-3.5" />}
                      </button>
                    </div>
                    <pre className="p-3 rounded-[var(--radius-control)] bg-[var(--paper)] border border-[var(--line)] text-xs font-code overflow-x-auto text-[var(--ink)] leading-relaxed">
{`# Downloads Zipformer acoustic model weights
dart run recite_quran:download_model`}
                    </pre>
                  </div>

                </div>

                {/* Step 3: Minimal 1-File Working Code */}
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-bold text-[var(--ink)] font-code">03 & 04. Initialize Engine & Stream Audio (lib/main.dart)</span>
                    <button
                      onClick={() =>
                        copyToClipboard(
`import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Quran repository & load Surat Al-Fatiha
  final repository = QuranRepository(QuranMetadataService());
  await repository.loadSurahAsync(1);

  // 2. Initialize tracking engine (enableAutoReanchor recommended for readers)
  final tracker = ReciteQuran(
    repository: repository,
    config: const TrackerConfig(
      enableEarlyMatching: true,
      enableAutoReanchor: true, // Auto-recovers page position hands-free
    ),
    isTajweed: false, // Dictation / Tilawah mode
  );
  await tracker.initialize();
  tracker.setTargetSurah(1);

  // 3. Listen to real-time word matches
  tracker.onWordMatched.listen((event) {
    if (event.isGreen) {
      print('🟢 Word \${event.wordId} matched correctly!');
    } else if (event.isYellow) {
      print('🟡 Word \${event.wordId} has a Tajweed slip (\${event.tajweedErrors})');
    } else if (event.isRed) {
      print('🔴 Word \${event.wordId} was skipped.');
    }
  });

  // 4. Stream audio from microphone (16kHz Float32 mono)
  final audio = AudioProcessor();
  await audio.start(
    onChunk: (Float32List chunk, bool isFinal) {
      tracker.feedAudioChunk(chunk, isFinal: isFinal);
    },
  );
}`,
                          'quickcode'
                        )
                      }
                      className="ql-btn ql-btn-sm ql-btn-secondary text-xs"
                    >
                      {copiedKey === 'quickcode' ? <Check className="w-3.5 h-3.5 text-[var(--state-correct)]" /> : <Copy className="w-3.5 h-3.5" />}
                      <span>{copiedKey === 'quickcode' ? 'Copied Full Code!' : 'Copy Snippet'}</span>
                    </button>
                  </div>

                  <pre className="p-4 rounded-[var(--radius-control)] bg-[var(--paper)] border border-[var(--line)] text-xs font-code overflow-x-auto text-[var(--ink)] leading-relaxed max-h-[360px]">
{`import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Quran repository & load Surat Al-Fatiha
  final repository = QuranRepository(QuranMetadataService());
  await repository.loadSurahAsync(1);

  // 2. Initialize tracking engine (enableAutoReanchor recommended for readers)
  final tracker = ReciteQuran(
    repository: repository,
    config: const TrackerConfig(
      enableEarlyMatching: true,
      enableAutoReanchor: true, // Auto-recovers page position hands-free
    ),
    isTajweed: false, // Dictation / Tilawah mode
  );
  await tracker.initialize();
  tracker.setTargetSurah(1);

  // 3. Listen to real-time word matches
  tracker.onWordMatched.listen((event) {
    if (event.isGreen) {
      print('🟢 Word \${event.wordId} matched correctly!');
    } else if (event.isYellow) {
      print('🟡 Word \${event.wordId} has a Tajweed slip (\${event.tajweedErrors})');
    } else if (event.isRed) {
      print('🔴 Word \${event.wordId} was skipped.');
    }
  });

  // 4. Stream audio from microphone (16kHz Float32 mono)
  final audio = AudioProcessor();
  await audio.start(
    onChunk: (Float32List chunk, bool isFinal) {
      tracker.feedAudioChunk(chunk, isFinal: isFinal);
    },
  );
}`}
                  </pre>
                </div>
              </div>
            )}

            {/* TAB 2: CONFIG GENERATOR */}
            {activeTab === 'generator' && (
              <div className="space-y-6">
                <div className="pb-4 border-b border-[var(--line)]">
                  <h3 className="text-lg font-bold text-[var(--ink)]">
                    {isAr ? '⚙️ المولد التفاعلي لإعدادات TrackerConfig' : '⚙️ Interactive TrackerConfig Generator'}
                  </h3>
                  <p className="text-xs text-[var(--ink-muted)]">
                    {isAr
                      ? 'ضبط معايير التلاوة بدقة وفق نمط استخدامك: قراءة حرة للمصحف، اختبار حفظ صارم، أو مراجعة سريعة.'
                      : 'Tune recitation parameters for your specific use-case: hands-free reader, strict examiner, or fast revision.'}
                  </p>
                </div>

                <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
                  
                  {/* Left Controls */}
                  <div className="lg:col-span-6 space-y-5">
                    
                    {/* Recitation Speed */}
                    <div className="space-y-2">
                      <label className="text-xs font-semibold text-[var(--ink)] block">
                        Recitation Speed (سرعة التلاوة)
                      </label>
                      <div className="ql-seg w-full">
                        {(['slow', 'normal', 'fast'] as const).map((spd) => (
                          <button
                            key={spd}
                            onClick={() => setConfigSpeed(spd)}
                            className={`ql-seg-btn flex-1 ${configSpeed === spd ? 'on' : ''}`}
                          >
                            {spd === 'slow' ? 'Slow (تحقيق)' : spd === 'normal' ? 'Normal (تدوير)' : 'Fast (حدر)'}
                          </button>
                        ))}
                      </div>
                    </div>

                    {/* Matching Strictness */}
                    <div className="space-y-2">
                      <label className="text-xs font-semibold text-[var(--ink)] block">
                        Matching Strictness (درجة التشدد)
                      </label>
                      <div className="ql-seg w-full">
                        {(['easy', 'normal', 'strict'] as const).map((st) => (
                          <button
                            key={st}
                            onClick={() => setConfigStrictness(st)}
                            className={`ql-seg-btn flex-1 ${configStrictness === st ? 'on' : ''}`}
                          >
                            {st === 'easy' ? 'Easy (ميسر)' : st === 'normal' ? 'Normal (معتدل)' : 'Strict (امتحان دقيق)'}
                          </button>
                        ))}
                      </div>
                    </div>

                    {/* Early Matching Toggle */}
                    <div className="p-3.5 rounded-[var(--radius-control)] bg-[var(--surface)] border border-[var(--line)] flex items-center justify-between gap-4">
                      <div>
                        <div className="text-xs font-bold text-[var(--ink)]">
                          enableEarlyMatching (Frontier Shield)
                        </div>
                        <div className="text-[11px] text-[var(--ink-muted)]">
                          Reserves long vowels (Madd Lazim 6 Harakat) to advance the cursor instantly without waiting for speech pause.
                        </div>
                      </div>
                      <input
                        type="checkbox"
                        checked={configEarlyMatching}
                        onChange={(e) => setConfigEarlyMatching(e.target.checked)}
                        className="w-4 h-4 accent-[var(--brand)] rounded cursor-pointer shrink-0"
                      />
                    </div>

                    {/* Auto Re-anchor Toggle */}
                    <div className="p-3.5 rounded-[var(--radius-control)] bg-[var(--surface)] border border-[var(--line)] flex items-center justify-between gap-4">
                      <div>
                        <div className="text-xs font-bold text-[var(--ink)] flex items-center gap-1.5">
                          <span>enableAutoReanchor (Hands-Free Recovery)</span>
                          <span className="text-[10px] px-1.5 py-0.5 rounded bg-[var(--state-correct-tint)] text-[var(--state-correct)] font-code font-bold">
                            RECOMMENDED
                          </span>
                        </div>
                        <div className="text-[11px] text-[var(--ink-muted)]">
                          Recovers position hands-free if reader looks away or skips lines. Protected by Anti-Ambiguity Guard (Δdist &lt; 3).
                        </div>
                      </div>
                      <input
                        type="checkbox"
                        checked={configAutoReanchor}
                        onChange={(e) => setConfigAutoReanchor(e.target.checked)}
                        className="w-4 h-4 accent-[var(--brand)] rounded cursor-pointer shrink-0"
                      />
                    </div>

                    {/* Reanchor Stall Threshold Slider */}
                    <div className="space-y-1.5">
                      <div className="flex items-center justify-between text-xs">
                        <span className="font-semibold text-[var(--ink)]">reanchorStallThreshold</span>
                        <span className="font-code text-[var(--brand)]">{configStallThreshold} phonemes (~{Math.round(configStallThreshold / 6)} words)</span>
                      </div>
                      <input
                        type="range"
                        min={12}
                        max={48}
                        step={6}
                        value={configStallThreshold}
                        onChange={(e) => setConfigStallThreshold(Number(e.target.value))}
                        className="w-full accent-[var(--brand)] cursor-pointer"
                      />
                      <div className="flex justify-between text-[10px] text-[var(--ink-muted)] font-code">
                        <span>12 (Agile / 2 words)</span>
                        <span>24 (Standard / 4 words)</span>
                        <span>48 (Patient / 8 words)</span>
                      </div>
                    </div>

                  </div>

                  {/* Right Generated Code */}
                  <div className="lg:col-span-6 space-y-3">
                    <div className="flex items-center justify-between text-xs font-code text-[var(--ink-muted)]">
                      <span>Generated Dart Code</span>
                      <button
                        onClick={() => copyToClipboard(generatedDartConfig, 'config_gen')}
                        className="p-1.5 rounded hover:bg-[var(--surface-hover)] text-[var(--ink)] transition-colors cursor-pointer flex items-center gap-1"
                      >
                        {copiedKey === 'config_gen' ? <Check className="w-3.5 h-3.5 text-[var(--state-correct)]" /> : <Copy className="w-3.5 h-3.5" />}
                        <span>{copiedKey === 'config_gen' ? 'Copied Config!' : 'Copy'}</span>
                      </button>
                    </div>

                    <pre className="p-4 rounded-[var(--radius-control)] bg-[var(--paper)] border border-[var(--line)] text-xs font-code overflow-x-auto text-[var(--ink)] leading-relaxed">
                      <code>{generatedDartConfig}</code>
                    </pre>

                    <div className="p-3.5 rounded-[var(--radius-control)] bg-[var(--surface)] border border-[var(--line)] text-xs text-[var(--ink-muted)] space-y-1">
                      <div className="font-bold text-[var(--ink)]">💡 Architecture Tip:</div>
                      <div>
                        Use <code className="text-[var(--brand)]">TrackerConfig.dictation()</code> for regular reading and <code className="text-[var(--brand)]">TrackerConfig.strict()</code> for official Hifdh certification exams.
                      </div>
                    </div>

                  </div>

                </div>
              </div>
            )}

            {/* TAB 3: AUDIO & PERMISSIONS */}
            {activeTab === 'audio' && (
              <div className="space-y-6">
                <div className="pb-4 border-b border-[var(--line)]">
                  <h3 className="text-lg font-bold text-[var(--ink)]">
                    {isAr ? '🎧 مسار معالجة الصوت وصلاحيات النظام' : '🎧 Audio Pipeline & Native Permissions'}
                  </h3>
                  <p className="text-xs text-[var(--ink-muted)]">
                    {isAr
                      ? 'تهيئة تدفق الصوت 16kHz PCM Float32 وتجاوز فلاتر العتاد على نظامي iOS و Android.'
                      : 'Configuring 16kHz PCM Float32 streaming and bypassing hardware filters on iOS and Android.'}
                  </p>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  
                  {/* Android Manifest */}
                  <div className="p-4 rounded-[var(--radius-surface)] border border-[var(--line)] bg-[var(--surface)] space-y-2">
                    <div className="flex items-center justify-between text-xs font-code font-bold text-[var(--ink)]">
                      <span>android/app/src/main/AndroidManifest.xml</span>
                      <button
                        onClick={() => copyToClipboard('<uses-permission android:name="android.permission.RECORD_AUDIO" />', 'android_perm')}
                        className="p-1 rounded text-[var(--ink-muted)] hover:text-[var(--ink)] cursor-pointer"
                      >
                        {copiedKey === 'android_perm' ? <Check className="w-3.5 h-3.5 text-[var(--state-correct)]" /> : <Copy className="w-3.5 h-3.5" />}
                      </button>
                    </div>
                    <pre className="p-3 rounded-[var(--radius-control)] bg-[var(--paper)] border border-[var(--line)] text-xs font-code text-[var(--ink)] overflow-x-auto">
{`<manifest ...>
    <!-- Required for real-time recitation tracking -->
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
</manifest>`}
                    </pre>
                  </div>

                  {/* iOS Info.plist */}
                  <div className="p-4 rounded-[var(--radius-surface)] border border-[var(--line)] bg-[var(--surface)] space-y-2">
                    <div className="flex items-center justify-between text-xs font-code font-bold text-[var(--ink)]">
                      <span>ios/Runner/Info.plist</span>
                      <button
                        onClick={() => copyToClipboard('<key>NSMicrophoneUsageDescription</key>\n<string>We need microphone access to track your Quran recitation in real-time.</string>', 'ios_perm')}
                        className="p-1 rounded text-[var(--ink-muted)] hover:text-[var(--ink)] cursor-pointer"
                      >
                        {copiedKey === 'ios_perm' ? <Check className="w-3.5 h-3.5 text-[var(--state-correct)]" /> : <Copy className="w-3.5 h-3.5" />}
                      </button>
                    </div>
                    <pre className="p-3 rounded-[var(--radius-control)] bg-[var(--paper)] border border-[var(--line)] text-xs font-code text-[var(--ink)] overflow-x-auto">
{`<key>NSMicrophoneUsageDescription</key>
<string>We need microphone access to track your Quran recitation in real-time on-device.</string>`}
                    </pre>
                  </div>

                </div>

                {/* AudioProcessor Code */}
                <div className="space-y-2">
                  <div className="flex items-center justify-between text-xs font-code text-[var(--ink-muted)]">
                    <span>AudioProcessor Integration & Chunk Streaming</span>
                    <button
                      onClick={() =>
                        copyToClipboard(
`final audio = AudioProcessor();

// 1. Request microphone permission
final granted = await audio.hasPermission();
if (!granted) return;

// 2. Start streaming 16kHz Float32 mono chunks (480ms each)
await audio.start(
  onChunk: (Float32List chunk, bool isFinal) {
    tracker.feedAudioChunk(chunk, isFinal: isFinal);
  },
);

// 3. Graceful shutdown
await audio.stop();
audio.dispose();`,
                          'audio_code'
                        )
                      }
                      className="ql-btn ql-btn-sm ql-btn-secondary text-xs"
                    >
                      {copiedKey === 'audio_code' ? <Check className="w-3.5 h-3.5 text-[var(--state-correct)]" /> : <Copy className="w-3.5 h-3.5" />}
                      <span>{copiedKey === 'audio_code' ? 'Copied Audio Code!' : 'Copy Snippet'}</span>
                    </button>
                  </div>

                  <pre className="p-4 rounded-[var(--radius-control)] bg-[var(--paper)] border border-[var(--line)] text-xs font-code overflow-x-auto text-[var(--ink)] leading-relaxed">
{`final audio = AudioProcessor();

// 1. Request microphone permission
final granted = await audio.hasPermission();
if (!granted) return;

// 2. Start streaming 16kHz Float32 mono chunks (480ms each)
await audio.start(
  onChunk: (Float32List chunk, bool isFinal) {
    tracker.feedAudioChunk(chunk, isFinal: isFinal);
  },
);

// 3. Graceful shutdown
await audio.stop();
audio.dispose();`}
                  </pre>
                </div>

              </div>
            )}

            {/* TAB 4: VOICE SEARCH */}
            {activeTab === 'search' && (
              <div className="space-y-6">
                <div className="pb-4 border-b border-[var(--line)]">
                  <h3 className="text-lg font-bold text-[var(--ink)]">
                    {isAr ? '🎙️ البحث الصوتي "اتلو لتنتقل" بخوارزمية Myers' : '🎙️ "Recite to Navigate" Myers Bit-Parallel Voice Search'}
                  </h3>
                  <p className="text-xs text-[var(--ink-muted)]">
                    {isAr
                      ? 'بحث فوري فائق السرعة في أقل من 15 ملي ثانية عبر 6,236 آية. اتلُ أي مقطع للانتقال مباشرة للصفحة والسورة.'
                      : 'Instant sub-15ms search across all 6,236 Ayahs. Recite any phrase to jump directly to page & surah.'}
                  </p>
                </div>

                <div className="space-y-3">
                  <div className="flex items-center justify-between text-xs font-code text-[var(--ink-muted)]">
                    <span>VoiceSearchController Dart Example</span>
                    <button
                      onClick={() =>
                        copyToClipboard(
`import 'package:recite_quran/recite_quran.dart';

final searchController = VoiceSearchController(
  engine: sherpaEngine,
  repository: quranRepository,
);

// 1. Preload 64-bit Myers index during app startup
await searchController.preloadIndex();

// 2. Start microphone listener
await searchController.startListening();

// 3. React to live candidate matches
searchController.currentResult.addListener(() {
  final AyahSearchResult? result = searchController.currentResult.value;
  if (result != null && result.topMatch != null) {
    final AyahSearchMatch match = result.topMatch!;
    print('Match: Surah \${match.surah}, Ayah \${match.ayah}');
    print('Score: \${match.score}, Distance: \${match.distance}');
    print('Arabic: \${match.textUthmani}');

    // Jump to Mus'haf page directly!
    navigateToPage(match.surah, match.ayah);
  }
});

// 4. Stop listening when navigated
await searchController.stopListening();`,
                          'search_code'
                        )
                      }
                      className="ql-btn ql-btn-sm ql-btn-secondary text-xs"
                    >
                      {copiedKey === 'search_code' ? <Check className="w-3.5 h-3.5 text-[var(--state-correct)]" /> : <Copy className="w-3.5 h-3.5" />}
                      <span>{copiedKey === 'search_code' ? 'Copied Search Code!' : 'Copy Snippet'}</span>
                    </button>
                  </div>

                  <pre className="p-4 rounded-[var(--radius-control)] bg-[var(--paper)] border border-[var(--line)] text-xs font-code overflow-x-auto text-[var(--ink)] leading-relaxed">
{`import 'package:recite_quran/recite_quran.dart';

final searchController = VoiceSearchController(
  engine: sherpaEngine,
  repository: quranRepository,
);

// 1. Preload 64-bit Myers index during app startup
await searchController.preloadIndex();

// 2. Start microphone listener
await searchController.startListening();

// 3. React to live candidate matches
searchController.currentResult.addListener(() {
  final AyahSearchResult? result = searchController.currentResult.value;
  if (result != null && result.topMatch != null) {
    final AyahSearchMatch match = result.topMatch!;
    print('Match: Surah \${match.surah}, Ayah \${match.ayah}');
    print('Score: \${match.score}, Distance: \${match.distance}');
    print('Arabic: \${match.textUthmani}');

    // Jump to Mus'haf page directly!
    navigateToPage(match.surah, match.ayah);
  }
});

// 4. Stop listening when navigated
await searchController.stopListening();`}
                  </pre>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  <div className="p-3 rounded-[var(--radius-control)] bg-[var(--surface)] border border-[var(--line)]">
                    <div className="text-xs font-bold text-[var(--ink)] font-code">6,236 Ayahs</div>
                    <div className="text-[11px] text-[var(--ink-muted)]">Complete Quran pre-indexed in 64-bit bitmasks</div>
                  </div>
                  <div className="p-3 rounded-[var(--radius-control)] bg-[var(--surface)] border border-[var(--line)]">
                    <div className="text-xs font-bold text-[var(--state-correct)] font-code">&lt; 15ms Latency</div>
                    <div className="text-[11px] text-[var(--ink-muted)]">Sub-frame search duration on budget mobile phones</div>
                  </div>
                  <div className="p-3 rounded-[var(--radius-control)] bg-[var(--surface)] border border-[var(--line)]">
                    <div className="text-xs font-bold text-[var(--ink)] font-code">Accent Tolerant</div>
                    <div className="text-[11px] text-[var(--ink-muted)]">Normalized phonetic matching absorbs dialect slips</div>
                  </div>
                </div>

              </div>
            )}

            {/* TAB 5: TAJWEED SHEET */}
            {activeTab === 'tajweed' && (
              <div className="space-y-6">
                <div className="pb-4 border-b border-[var(--line)]">
                  <h3 className="text-lg font-bold text-[var(--ink)]">
                    {isAr ? '🎯 فحص التجويد الصوتي والنافذة الإرشادية' : '🎯 Tajweed Verification & Pre-Built Modal Dialog'}
                  </h3>
                  <p className="text-xs text-[var(--ink-muted)]">
                    {isAr
                      ? 'فحص أزمنة المدود، أحكام الغنة، والشدات مع نافذة تصحيح مسبقة البناء جاهزة للعرض للقارئ.'
                      : 'Acoustic Madd duration checks, Ghunnah nasalization, and pre-built bilingual correction sheets.'}
                  </p>
                </div>

                <div className="space-y-3">
                  <div className="flex items-center justify-between text-xs font-code text-[var(--ink-muted)]">
                    <span>Handling WordMatchedEvent & Displaying Sheet</span>
                    <button
                      onClick={() =>
                        copyToClipboard(
`tracker.onWordMatched.listen((event) {
  if (event.isGreen) {
    // Valid pronunciation & proper Tajweed
    setWordHighlight(event.wordId, HighlightStatus.correct);
  } else if (event.isYellow) {
    // Valid word, but Tajweed slip (لحن خفي) detected!
    setWordHighlight(event.wordId, HighlightStatus.tajweedSlip);

    // Option A: Open pre-built bottom modal on tap
    onWordTapped: () {
      TajweedErrorSheet.show(
        context,
        wordUthmani: 'الضَّالِّينَ',
        errors: event.tajweedErrors!,
        isArabic: true,
      );
    };

    // Option B: Or inspect pedagogical advice programmatically
    for (final err in event.tajweedErrors!) {
      final info = ErrorExplainer.explain(err, isArabic: true);
      print('Rule: \${info.title}');
      print('Description: \${info.description}');
      print('Remedy: \${info.remedy}');
    }
  } else if (event.isRed) {
    // Word skipped or gross mispronunciation (لحن جلي)
    setWordHighlight(event.wordId, HighlightStatus.omitted);
  }
});`,
                          'tajweed_code'
                        )
                      }
                      className="ql-btn ql-btn-sm ql-btn-secondary text-xs"
                    >
                      {copiedKey === 'tajweed_code' ? <Check className="w-3.5 h-3.5 text-[var(--state-correct)]" /> : <Copy className="w-3.5 h-3.5" />}
                      <span>{copiedKey === 'tajweed_code' ? 'Copied Tajweed Code!' : 'Copy Snippet'}</span>
                    </button>
                  </div>

                  <pre className="p-4 rounded-[var(--radius-control)] bg-[var(--paper)] border border-[var(--line)] text-xs font-code overflow-x-auto text-[var(--ink)] leading-relaxed">
{`tracker.onWordMatched.listen((event) {
  if (event.isGreen) {
    // Valid pronunciation & proper Tajweed
    setWordHighlight(event.wordId, HighlightStatus.correct);
  } else if (event.isYellow) {
    // Valid word, but Tajweed slip (لحن خفي) detected!
    setWordHighlight(event.wordId, HighlightStatus.tajweedSlip);

    // Option A: Open pre-built bottom modal on tap
    onWordTapped: () {
      TajweedErrorSheet.show(
        context,
        wordUthmani: 'الضَّالِّينَ',
        errors: event.tajweedErrors!,
        isArabic: true,
      );
    };

    // Option B: Or inspect pedagogical advice programmatically
    for (final err in event.tajweedErrors!) {
      final info = ErrorExplainer.explain(err, isArabic: true);
      print('Rule: \${info.title}');
      print('Description: \${info.description}');
      print('Remedy: \${info.remedy}');
    }
  } else if (event.isRed) {
    // Word skipped or gross mispronunciation (لحن جلي)
    setWordHighlight(event.wordId, HighlightStatus.omitted);
  }
});`}
                  </pre>
                </div>

              </div>
            )}

            {/* TAB 6: 20 RAWIS MAP */}
            {activeTab === 'riwayat' && (
              <div className="space-y-6">
                <div className="pb-4 border-b border-[var(--line)]">
                  <h3 className="text-lg font-bold text-[var(--ink)]">
                    {isAr ? '📖 خريطة الرواة العشرين ومذاهب العد الستة' : '📖 20 Canonical Rawis & 6 Counting Madhhabs'}
                  </h3>
                  <p className="text-xs text-[var(--ink-muted)]">
                    {isAr
                      ? 'مطابقة معيارية دقيقة لأرقام ومواضع الآيات بين الروايات العشرين ومذاهب العد المعتمدة.'
                      : 'Integrated canonical verse index mapping based on verified Quranpedia datasets.'}
                  </p>
                </div>

                {/* 20 Rawis Table */}
                <div className="overflow-x-auto rounded-[var(--radius-control)] border border-[var(--line)]">
                  <table className="w-full text-start text-xs">
                    <thead className="bg-[var(--surface)] text-[var(--ink)] font-code border-b border-[var(--line)]">
                      <tr>
                        <th className="p-3 text-start">{isAr ? 'الإمام والمدينة' : 'Imam & Region'}</th>
                        <th className="p-3 text-start">{isAr ? 'الرواة' : 'Canonical Rawis (الرواة)'}</th>
                        <th className="p-3 text-start">{isAr ? 'الانتشار الجغرافي' : 'Primary Geography'}</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-[var(--line)] text-[var(--ink-muted)]">
                      {RAWIS_DATA.map((r, i) => (
                        <tr key={i} className="hover:bg-[var(--surface-hover)]">
                          <td className="p-3 font-semibold text-[var(--ink)]">{r.imam}</td>
                          <td className="p-3 font-code">{r.rawis.join(', ')}</td>
                          <td className="p-3">{r.popularIn}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>

                {/* Counting Schools Table */}
                <div className="space-y-2">
                  <div className="text-xs font-bold text-[var(--ink)] font-code">
                    6 Canonical Counting Schools (مذاهب العدّ الستة)
                  </div>
                  <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2">
                    {COUNTING_SCHOOLS.map((c, i) => (
                      <div key={i} className="p-3 rounded-[var(--radius-control)] bg-[var(--surface)] border border-[var(--line)]">
                        <div className="text-xs font-bold text-[var(--ink)]">{c.name}</div>
                        <div className="text-sm font-code text-[var(--brand)] font-bold my-1">{c.count}</div>
                        <div className="text-[10.5px] text-[var(--ink-muted)]">{c.description}</div>
                      </div>
                    ))}
                  </div>
                </div>

              </div>
            )}

            {/* TAB 7: MODEL DEPLOYMENT */}
            {activeTab === 'model' && (
              <div className="space-y-6">
                <div className="pb-4 border-b border-[var(--line)]">
                  <h3 className="text-lg font-bold text-[var(--ink)]">
                    {isAr ? '📦 خيارات نشر وتضمين النموذج العصبي' : '📦 Neural Model Deployment (On-Demand vs Bundled)'}
                  </h3>
                  <p className="text-xs text-[var(--ink-muted)]">
                    {isAr
                      ? 'نشر نموذج Zipformer بحجم 69 ميجابايت عبر التحميل عند أول فتح أو تضمينه محلياً للعمل أوفلاين دون اتصال.'
                      : 'Deploy the quantized 69MB Zipformer INT8 neural model via on-demand download or zero-network offline bundling.'}
                  </p>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  
                  {/* Strategy A */}
                  <div className="p-5 rounded-[var(--radius-surface)] border border-[var(--line)] bg-[var(--surface)] space-y-3">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-[var(--brand)] font-code uppercase">Strategy A: On-Demand</span>
                      <span className="text-[10px] px-1.5 py-0.5 rounded bg-[var(--brand-tint)] text-[var(--brand)] font-code">
                        ~12MB Store Size
                      </span>
                    </div>
                    <p className="text-xs text-[var(--ink-muted)] leading-relaxed">
                      Keep your app store download small (10–15MB). Download the 69MB Zipformer neural model on first launch with visual progress.
                    </p>
                    <pre className="p-3 rounded-[var(--radius-control)] bg-[var(--paper)] border border-[var(--line)] text-xs font-code overflow-x-auto text-[var(--ink)]">
{`await ModelDownloader.downloadModel(
  onProgress: (received, total) {
    final percent = (received / total) * 100;
    print('Downloading model: \${percent.toStringAsFixed(1)}%');
  },
);`}
                    </pre>
                  </div>

                  {/* Strategy B */}
                  <div className="p-5 rounded-[var(--radius-surface)] border border-[var(--line)] bg-[var(--surface)] space-y-3">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-[var(--state-correct)] font-code uppercase">Strategy B: Offline Bundle</span>
                      <span className="text-[10px] px-1.5 py-0.5 rounded bg-[var(--state-correct-tint)] text-[var(--state-correct)] font-code">
                        100% Offline Out-of-Box
                      </span>
                    </div>
                    <p className="text-xs text-[var(--ink-muted)] leading-relaxed">
                      Bundle the model directly inside your APK / IPA. Zero internet connection required from the very first tap.
                    </p>
                    <pre className="p-3 rounded-[var(--radius-control)] bg-[var(--paper)] border border-[var(--line)] text-xs font-code overflow-x-auto text-[var(--ink)]">
{`# pubspec.yaml
flutter:
  assets:
    - assets/model/zipformer_p_arabic_v3.int8.onnx
    - assets/model/tokens.txt`}
                    </pre>
                  </div>

                </div>

                <div className="p-4 rounded-[var(--radius-control)] bg-[var(--surface)] border border-[var(--line)] flex items-center justify-between text-xs">
                  <div className="flex items-center gap-2 text-[var(--ink)]">
                    <DownloadCloud className="w-4 h-4 text-[var(--brand)] shrink-0" />
                    <span>HuggingFace Acoustic Weights: <strong>Quran-Lab/zipformer_p-arabic-v3</strong></span>
                  </div>
                  <a
                    href="https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="ql-btn ql-btn-sm ql-btn-secondary font-code text-xs !h-[30px]"
                  >
                    <span>View on HuggingFace</span>
                    <ArrowUpRight className="w-3 h-3" />
                  </a>
                </div>

              </div>
            )}

            {/* TAB 8: STATE ARCHITECTURE */}
            {activeTab === 'state' && (
              <div className="space-y-6">
                <div className="pb-4 border-b border-[var(--line)]">
                  <h3 className="text-lg font-bold text-[var(--ink)]">
                    {isAr ? '🧩 المعمارية البرمجية وإدارة الحالة (Riverpod / BLoC)' : '🧩 Clean Architecture & State Management (Riverpod / Bloc)'}
                  </h3>
                  <p className="text-xs text-[var(--ink-muted)]">
                    {isAr
                      ? 'نمط عملي مجرب لربط ReciteQuran في Riverpod StateNotifier أو BLoC دون أي تأثير على سلاسة الواجهة.'
                      : 'Production recipe for wiring ReciteQuran into Riverpod StateNotifier or BLoC with zero UI thread contention.'}
                  </p>
                </div>

                <div className="space-y-3">
                  <div className="flex items-center justify-between text-xs font-code text-[var(--ink-muted)]">
                    <span>Riverpod RecitationNotifier Recipe</span>
                    <button
                      onClick={() =>
                        copyToClipboard(
`import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recite_quran/recite_quran.dart';

class RecitationState {
  final int activeWordId;
  final bool isListening;
  final List<int> greenWords;
  final List<int> yellowWords;
  final List<int> redWords;

  const RecitationState({
    this.activeWordId = 0,
    this.isListening = false,
    this.greenWords = const [],
    this.yellowWords = const [],
    this.redWords = const [],
  });
}

class RecitationNotifier extends StateNotifier<RecitationState> {
  final ReciteQuran tracker;
  final AudioProcessor audio = AudioProcessor();

  RecitationNotifier(this.tracker) : super(const RecitationState()) {
    tracker.onWordMatched.listen((event) {
      if (event.isGreen) {
        state = RecitationState(
          activeWordId: event.wordId,
          isListening: state.isListening,
          greenWords: [...state.greenWords, event.wordId],
          yellowWords: state.yellowWords,
          redWords: state.redWords,
        );
      }
    });
  }

  Future<void> start() async {
    await audio.start(onChunk: (chunk, isFinal) {
      tracker.feedAudioChunk(chunk, isFinal: isFinal);
    });
    state = RecitationState(isListening: true);
  }

  Future<void> stop() async {
    await audio.stop();
    state = RecitationState(isListening: false);
  }
}`,
                          'riverpod_code'
                        )
                      }
                      className="ql-btn ql-btn-sm ql-btn-secondary text-xs"
                    >
                      {copiedKey === 'riverpod_code' ? <Check className="w-3.5 h-3.5 text-[var(--state-correct)]" /> : <Copy className="w-3.5 h-3.5" />}
                      <span>{copiedKey === 'riverpod_code' ? 'Copied Recipe!' : 'Copy Snippet'}</span>
                    </button>
                  </div>

                  <pre className="p-4 rounded-[var(--radius-control)] bg-[var(--paper)] border border-[var(--line)] text-xs font-code overflow-x-auto text-[var(--ink)] leading-relaxed">
{`import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recite_quran/recite_quran.dart';

class RecitationNotifier extends StateNotifier<RecitationState> {
  final ReciteQuran tracker;
  final AudioProcessor audio = AudioProcessor();

  RecitationNotifier(this.tracker) : super(const RecitationState()) {
    tracker.onWordMatched.listen((event) {
      if (event.isGreen) {
        state = state.copyWith(activeWordId: event.wordId, greenWords: [...state.greenWords, event.wordId]);
      } else if (event.isYellow) {
        state = state.copyWith(yellowWords: [...state.yellowWords, event.wordId]);
      }
    });
  }

  Future<void> start() async {
    await audio.start(onChunk: (chunk, isFinal) => tracker.feedAudioChunk(chunk, isFinal: isFinal));
    state = state.copyWith(isListening: true);
  }

  Future<void> stop() async {
    await audio.stop();
    state = state.copyWith(isListening: false);
  }
}`}
                  </pre>
                </div>

              </div>
            )}

            {/* TAB 9: API REFERENCE */}
            {activeTab === 'api' && (
              <div className="space-y-6">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between pb-4 border-b border-[var(--line)] gap-3">
                  <div>
                    <h3 className="text-lg font-bold text-[var(--ink)]">
                      {isAr ? '⚡ المرجع السريع لدوال وواجهات الحزمة' : '⚡ High-Density API Reference Cheat Sheet'}
                    </h3>
                    <p className="text-xs text-[var(--ink-muted)]">
                      {isAr
                        ? 'كافة الدوال والمعاملات ومسارات الأحداث في حزمة package:recite_quran.'
                        : 'Every method signature, constructor, and stream in package:recite_quran.'}
                    </p>
                  </div>
                  
                  {/* Search Bar */}
                  <div className="relative w-full sm:w-64">
                    <Search className={`w-3.5 h-3.5 absolute ${isAr ? 'right-3' : 'left-3'} top-1/2 -translate-y-1/2 text-[var(--ink-muted)] pointer-events-none`} />
                    <input
                      type="text"
                      placeholder={isAr ? 'ابحث في دوال الحزمة...' : 'Search API signatures...'}
                      value={apiSearchQuery}
                      onChange={(e) => setApiSearchQuery(e.target.value)}
                      className={`w-full ${isAr ? 'pr-9 pl-3 text-right' : 'pl-9 pr-3 text-left'} py-1.5 rounded-[var(--radius-control)] bg-[var(--surface)] border border-[var(--line)] text-xs text-[var(--ink)] font-code placeholder:text-[var(--ink-faint)] focus:outline-none focus:border-[var(--brand)]`}
                    />
                  </div>
                </div>

                <div className="space-y-3">
                  {filteredApiMethods.map((m, i) => (
                    <div
                      key={i}
                      className="p-4 rounded-[var(--radius-control)] bg-[var(--surface)] border border-[var(--line)] space-y-1.5 transition-colors hover:border-[var(--line-strong)]"
                    >
                      <div className="flex items-center justify-between gap-3">
                        <span className="text-xs font-code font-bold text-[var(--brand)] overflow-x-auto">
                          {m.sig}
                        </span>
                        <span className="ql-tag font-code !h-5 !text-[10px] shrink-0">
                          {m.category}
                        </span>
                      </div>
                      <p className="text-xs text-[var(--ink-muted)] leading-relaxed">
                        {m.desc}
                      </p>
                    </div>
                  ))}
                  {filteredApiMethods.length === 0 && (
                    <div className="p-8 text-center text-xs text-[var(--ink-muted)]">
                      No matching API signatures found for "{apiSearchQuery}".
                    </div>
                  )}
                </div>

              </div>
            )}

          </div>

        </div>

      </div>
    </section>
  );
};

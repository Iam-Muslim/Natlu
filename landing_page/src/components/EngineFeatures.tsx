import React, { useState } from 'react';
import { LangMode } from '../types';
import {
  Compass,
  CheckCircle2,
  Mic,
  Search,
  BookMarked,
  Layers,
  Cpu,
  ShieldCheck,
  Copy,
  Check
} from 'lucide-react';

interface EngineFeaturesProps {
  lang: LangMode;
}

export const EngineFeatures: React.FC<EngineFeaturesProps> = ({ lang }) => {
  const isAr = lang === 'ar';
  const [activeFeatureIndex, setActiveFeatureIndex] = useState<number>(0);
  const [copied, setCopied] = useState<boolean>(false);

  const features = [
    {
      id: 'dictation',
      shortTitle: 'Auto-Scroll',
      shortTitleAr: 'التمرير التلقائي',
      title: 'Hands-Free Dictation & Auto-Scroll',
      titleAr: 'محرك القراءة الحرة والتمرير التلقائي',
      badge: '2D DP Matrix',
      icon: Compass,
      summary:
        'Eliminates long vowel latency with Early Matching and recovers lost positions via Auto Re-anchoring without touching the screen.',
      summaryAr:
        'محاذاة فائقة السرعة مع تقنية المطابقة المبكرة لمنع التأخير في المدود الطويلة، وإعادة التموضع التلقائي دون لمس الهاتف.',
      bullets: [
        'Early Matching: Bypasses long vowel wait cycles (Madd Lazim 6 Harakat) to advance the cursor instantly.',
        'Auto Re-anchoring: Automatically recovers reading position if the user looks away or skips lines hands-free.',
        'Anti-Ambiguity Guard (Δdist < 3): Suppresses jumping between repeated refrains (e.g., 31 repetitions in Ar-Rahman).',
        '2D Dynamic Programming Levenshtein matrix tailored specifically for Arabic phonotactics and Wasl rules.'
      ],
      bulletsAr: [
        'المطابقة المبكرة: تتجاوز انتظار انتهاء المدود الطويلة (كالمد اللازم 6 حركات) لنقل المؤشر فور استقرار الصوت.',
        'إعادة التموضع التلقائي: استعادة موضع القارئ في الصفحة فور تجاوزه لسطر أو آية دون الحاجة للمس الشاشة.',
        'حارس المتشابهات اللفظية (Δdist < 3): يمنع القفز الخاطئ بين الآيات المتكررة مثل 31 تكرارًا في سورة الرحمن.',
        'مصفوفة برمجة ديناميكية 2D تأخذ في الاعتبار همزات الوصل وأحكام الإدغام التلقائي.'
      ],
      codeSnippet: `// 1. Hands-Free Dictation Configuration
final dictationConfig = TrackerConfig.normal(
  enableEarlyMatching: true,  // Eliminates Madd delay
  enableAutoReanchor: true,   // Recovers jumps hands-free (RECOMMENDED)
  reanchorStallThreshold: 24, // ~4 words stall window
);

final tracker = ReciteQuran(
  repository: repository,
  config: dictationConfig,
  isTajweed: false, // Fluid tilawah mode
);
await tracker.initialize();
tracker.setTargetSurah(1);`
    },
    {
      id: 'neural_asr',
      shortTitle: 'Neural ASR',
      shortTitleAr: 'الاستدلال العصبي',
      title: 'On-Device Neural ASR (Zipformer v3)',
      titleAr: 'الاستدلال العصبي الصوتي On-Device',
      badge: 'Zipformer v3',
      icon: Cpu,
      summary:
        'Next-generation pruned stateless Zipformer neural network optimized for Quranic phonemes, running 100% locally with sub-25ms latency.',
      summaryAr:
        'شبكة عصبية متطورة (Zipformer v3) مدربة على الفونيمات القرآنية، تعمل محلياً بالكامل على معالج الهاتف بسرعة استجابة أقل من 25 مللي ثانية دون إنترنت.',
      bullets: [
        'Pruned stateless transducer architecture (Zipformer-v3) compiled via ONNX Runtime Mobile.',
        '100% offline inference with zero telemetry, zero cloud costs, and zero network requirement.',
        'Pre-quantized int8/fp16 neural weights consuming under 38MB RAM during active speech inference.',
        'Continuous streaming chunk recognition (480ms frames) running entirely in a background Dart isolate.'
      ],
      bulletsAr: [
        'معمارية Zipformer-v3 المحسنة والمصغرة، مجهزة للعمل عبر ONNX Runtime على معالجات ARM و Apple Silicon.',
        'استدلال صوتي محلي 100% على جهاز المستخدم مع خصوصية تامة وحماية كاملة للبيانات الصوتية.',
        'استهلاك اقتصادي للذاكرة (أقل من 38 ميغابايت) باستخدام أوزان int8/fp16 المحسنة.',
        'تدفق صوتي مستمر (إطارات 480ms) في Isolate خلفي مستقل لمنع أي تأخير في سلاسة واجهة المستخدم.'
      ],
      codeSnippet: `// 2. On-Device Neural ASR (Zipformer v3)
final recognizer = SherpaOnnxRecognizer(
  modelPath: 'assets/models/zipformer_arabic_v3.onnx',
  tokensPath: 'assets/models/tokens.txt',
  numThreads: 2,
  provider: 'cpu', // Optimized ARM NEON / CoreML
);

await recognizer.initialize();

// Stream live microphone frames into neural recognizer:
recognizer.acceptWaveform(samples: float32Chunk, sampleRate: 16000);
while (recognizer.isReady()) {
  recognizer.decode();
  final String phonemes = recognizer.getResult().text;
  tracker.feedDecodedPhonemes(phonemes);
}`
    },
    {
      id: 'tajweed_checking',
      shortTitle: 'Tajweed Check',
      shortTitleAr: 'فحص التجويد',
      title: 'Acoustic Tajweed Checking & Verification',
      titleAr: 'فحص وتدقيق أحكام التجويد الصوتي',
      badge: 'Tajweed Matrix',
      icon: ShieldCheck,
      summary:
        'Deterministic acoustic rule grading for Madd durations, Ghunnah, Shaddah, and Qalqalah with immediate pedagogical corrective advice.',
      summaryAr:
        'فحص صوتي دقيق لأحكام التجويد: أزمنة المدود، الغنن، الشدات، والقلقلة مع لوحة إرشادية فورية لتصحيح النطق والتلاوة.',
      bullets: [
        'Acoustic duration evaluation for Madd (2, 4, 6 Harakat) against calibrated Tadweer tempos.',
        'Frequency-envelope nasalization detector (Ghunnah & Ikhfa) with Shaddah stress validation.',
        'Precise classification between minor phonetic slips (لحن خفي) and major omissions (لحن جلي).',
        'Built-in pedagogical TajweedErrorSheet offering authorized Sheikh correction advice in real time.'
      ],
      bulletsAr: [
        'قياس صوتي دقيق لأزمنة المدود (حركتان، 4، 6 حركات) وفق سرعة تلاوة القارئ (تدوير، تحقيق، حدر).',
        'كشف صوتي دقيق لأحكام الغنة والإخفاء والإدغام مع التحقق من شدة الحروف المشددة والقلقلة.',
        'تمييز دقيق بين اللحن الخفي (نقص مد أو غنة) واللحن الجلي (تغيير حركة أو حرف) بإشعارات لونية فورية.',
        'واجهة تصحيح مدمجة (TajweedErrorSheet) تعرض نصيحة التصحيح التجويدي المعتمدة فور وقوع الخطأ.'
      ],
      codeSnippet: `// 3. Acoustic Tajweed Checking & Verification
final tajweedTracker = ReciteQuran(
  repository: quranRepository,
  isTajweed: true, // Activates deterministic Tajweed rule matrix
  config: const TrackerConfig(
    matchingStrictness: MatchingStrictness.strict,
    enableEarlyMatching: false, // Enforces full vowel duration
    enableAutoReanchor: false,  // Uncorrected skips flagged RED
  ),
);

// Stream real-time Tajweed errors:
tajweedTracker.onTajweedSlip.listen((TajweedSlip slip) {
  if (slip.isKhafi) {
    // Minor slip (e.g., Madd or Ghunnah duration shortfall)
    showTajweedWarning(slip.rule, expectedHarakat: slip.expected);
  } else if (slip.isJali) {
    // Major phonetic error (Harakah or letter substitution)
    highlightErrorWord(slip.wordId, color: Colors.red);
  }
});`
    },
    {
      id: 'search',
      shortTitle: 'Voice Search',
      shortTitleAr: 'البحث الصوتي',
      title: '"Recite to Navigate" Voice Search',
      titleAr: 'البحث الصوتي الفوري عن الآيات ("اتلُ لتصل")',
      badge: 'Myers Parallel',
      icon: Search,
      summary:
        'Speak any ayah fragment to instantly identify surah, ayah number, and page in under 15ms across the entire Mus\'haf.',
      summaryAr:
        'اتلُ أي مقطع من أي آية في القرآن العظيم للانتقال الفوري إلى موضعها في المصحف في أقل من 15 مللي ثانية.',
      bullets: [
        'Scans entire Quran corpus in sub-15ms on standard mobile CPUs.',
        'Myers bit-parallel approximate string matching algorithm running on 64-bit words.',
        'Resilient to dialectal accents, minor tashkeel slips, and microphone background noise.',
        'Returns ranked candidate list with confidence scores and direct Mus\'haf page indices.'
      ],
      bulletsAr: [
        'مسح فوري لآيات المصحف الشريف كاملة في أقل من 15 مللي ثانية على معالج الهاتف.',
        'خوارزمية مايرز للمطابقة التقريبية المتوازية فائقة الكفاءة على كلمات 64-بت.',
        'تحمل كامل لاختلاف اللهجات وأخطاء التشكيل البسيطة والضوضاء المحيطة.',
        'إرجاع قائمة بالآيات المطابقة مرتبة حسب نسبة الثقة ورقم الصفحة في المصحف.'
      ],
      codeSnippet: `// 4. Myers Bit-Parallel Voice Navigation
final searchController = VoiceSearchController(
  engine: sherpaEngine,
  repository: repository,
);

// Pre-compute 64-bit Myers index in background isolate
await searchController.preloadIndex();

// Listen to microphone and stream live candidates
await searchController.startListening();

searchController.currentResult.addListener(() {
  final AyahSearchResult? result = searchController.currentResult.value;
  if (result != null && result.topMatch != null) {
    final AyahSearchMatch match = result.topMatch!;
    navigateToAyah(surah: match.surah, ayah: match.ayah);
  }
});`
    },
    {
      id: 'hifdh',
      shortTitle: 'Hifdh Mode',
      shortTitleAr: 'تثبيت الحفظ',
      title: 'Tarteel-Style Hifdh Memorization Mode',
      titleAr: 'وضع اختبار وتثبيت الحفظ (تحفيظ ومراجعة)',
      badge: 'Best-Drop LCS',
      icon: BookMarked,
      summary:
        'Progressively reveals words only as recited correctly from memory, flagging omissions and skipped passages.',
      summaryAr:
        'إخفاء الكلمات وكشفها تدريجيًا فقط عند تلاوتها صحيحة من الذاكرة، مع كشف فوري للكلمات المتروكة.',
      bullets: [
        'Conceals upcoming text on screen, testing reciter memory without visual prompting.',
        'Best-Drop Longest Common Subsequence (LCS) word omission detection (Dr. Omar Abu Hafs / Tasmee3 findings).',
        'Identifies skipped verses, repeated refrains, and line confusion in real time.',
        'Detailed revision score and mistake summary generated upon completing each Hizb/Juz.'
      ],
      bulletsAr: [
        'إخفاء الآيات القادمة على الشاشة لاختبار الذاكرة دون غش بصري.',
        'خوارزمية Best-Drop LCS لكشف الكلمات المنسية أو المتروكة بدقة متناهية (أبحاث د. عمر أبو حفص / سراج).',
        'كشف الآيات المتداخلة في المتشابهات وتكرار المقاطع في الوقت الفعلي.',
        'تقرير إحصائي تفصيلي للأخطاء ونقاط التثبيت عند الانتهاء من الورد أو الجزء.'
      ],
      codeSnippet: `// 5. Best-Drop LCS Omission Detection
final omission = LcsOmissionDetector.detectOmission(
  phonemesPerWord: surahPhonemesList,
  emittedPhonemes: reciterEmittedPhonemes,
);

if (omission.isOmissionDetected) {
  print('Skipped word index: \${omission.omittedWordIndex}');
  print('Phoneme shortfall: \${omission.shortfall}');
  print('Confidence gap: \${omission.confidenceGap}');
}`
    },
    {
      id: 'audio',
      shortTitle: 'Audio Engine',
      shortTitleAr: 'معالج الصوت',
      title: 'Production 16kHz Audio Pipeline',
      titleAr: 'خط المعالجة الصوتية الخام 16 كيلوهرتز',
      badge: '16kHz Mono',
      icon: Mic,
      summary:
        'Microphone capture engine streaming 16kHz Mono Float32 frames directly into background C++ inference.',
      summaryAr:
        'معالج صوتي متكامل يرسل تدفق 16 كيلوهرتز أحادي القناة إلى المعالج العصبي دون أي تشويش.',
      bullets: [
        'Captures 16kHz Mono Float32 frames [-1.0, 1.0] in 480ms chunks (7,680 samples).',
        'Bypasses system Automatic Gain Control (AGC) and echo cancelers that distort Tajweed acoustics.',
        'Zero UI thread blocking: Neural inference and DP alignment execute entirely in a dedicated background Isolate.',
        'Gracefully handles OS audio interruptions, phone calls, and Bluetooth headset disconnects.'
      ],
      bulletsAr: [
        'التقاط إطارات صوتية 16kHz أحادية بنطاق Float32 [-1.0, 1.0] في مقاطع 480ms.',
        'تجاوز فلاتر النظام التلقائية (AGC) التي تشوه مخارج الحروف وأزمنة الغنن.',
        'عزل تام عن واجهة المستخدم: يعمل الاستدلال العصبي والمحاذاة في Isolate خلفي مستقل 60/120fps.',
        'معالجة سلسة لانقطاعات الصوت والمكالمات الهاتفية وسماعات البلوتوث.'
      ],
      codeSnippet: `// 6. Raw Audio Capture & Feeding Pipeline
final audioProcessor = AudioProcessor();
final hasPermission = await audioProcessor.hasPermission();

if (hasPermission) {
  await audioProcessor.start(
    onChunk: (Float32List chunk, bool isFinal) {
      // Direct stream into background Zipformer recognizer
      tracker.feedAudioChunk(chunk, isFinal: isFinal);
    },
  );
}`
    },
    {
      id: 'riwayat',
      shortTitle: 'Multi-Riwayah',
      shortTitleAr: 'الروايات الـ 20',
      title: 'Multi-Riwayah & 20 Canonical Rawis',
      titleAr: 'دعم الروايات الـ 20 ومذاهب العدّ الستة',
      badge: '20 Rawis',
      icon: Layers,
      summary:
        'First-class support for Islamic recitation traditions with canonical verse index mapping across traditions.',
      summaryAr:
        'دعم أصيل لكافة القراءات العشر المتواترة والرواة الـ 20 مع تسوية أرقام الآيات بمذاهب العد الستة.',
      bullets: [
        '10 Mutawatir Qira\'at & 20 Canonical Rawis: Hafs, Warsh, Qalun, Al-Duri, Shu\'bah, etc.',
        '6 Counting Madhhabs: Kufi (6,236), Madani (6,214), Basri (6,204), Makki (6,219), Dimashqi (6,226), Homsi (6,232).',
        'QiraatAyahMapper resolves verse index offsets and differences based on Quranpedia datasets.',
        'Full support for Riwayat-specific Wasl, Naql, Tashil, and Imalah phoneme rules.'
      ],
      bulletsAr: [
        'القراءات العشر والرواة الـ 20: حفص، ورش، قالون، الدوري، شعبة، السوسي، وغيرهم.',
        'مذاهب العد الستة: الكوفي (6,236)، المدني (6,214)، البصري (6,204)، المكي (6,219)، الدمشقي (6,226)، الحمصي (6,232).',
        'فئة QiraatAyahMapper لربط أرقام الآيات بين الروايات المختلفة بالاعتماد على موسوعة القرآن (Quranpedia).',
        'دعم كامل لأحكام النقل والتسهيل والإمالة الخاصة بكل رواية.'
      ],
      codeSnippet: `// 7. Multi-Riwayah Verse Translation
final mappedAyah = QiraatAyahMapper.mapAyah(
  surah: 1,
  ayah: 1,
  fromRiwayah: QuranRiwayah.hafs, // Kufi counting: Basmalah is Ayah 1
  toRiwayah: QuranRiwayah.warsh,  // Madani counting: Basmalah is not Ayah 1
);

print('Warsh equivalent: Ayah \${mappedAyah}');`
    }
  ];

  const activeFeature = features[activeFeatureIndex];

  const copyCode = (code: string) => {
    navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <section id="engine-features" className="py-20 border-b border-[var(--line)]">
      <div className="max-w-[1248px] mx-auto px-4 sm:px-6">
        
        {/* Section Header */}
        <div className="max-w-[760px] space-y-3 mb-12">
          <span className="ql-meta text-xs font-semibold tracking-wider uppercase text-[var(--brand)] font-code">
            {isAr ? 'مميزات المحرك المعمارية والتقنية' : 'Core Architecture & Features'}
          </span>
          <h2 className="text-2xl sm:text-4xl font-extrabold tracking-[-0.02em] text-[var(--ink)]">
            {isAr ? 'المميزات السبع الأساسية لمحرك ReciteQuran' : 'Seven Production-Grade Engine Features'}
          </h2>
          <p className="text-sm sm:text-[15px] text-[var(--ink-muted)] leading-[1.65]">
            {isAr
              ? 'صُمم المحرك بأعلى المعايير ليعمل محلياً بالكامل (On-Device) على الهواتف والأجهزة الذكية دون الحاجة إلى إنترنت، مع دقة صوتية متناهية وسرعة استجابة فائقة.'
              : 'Engineered for zero-latency, private, on-device mobile execution. Discover how the engine unifies acoustic neural modeling, 2D dynamic programming, deterministic Tajweed checking, and classical pedagogy.'}
          </p>
        </div>

        {/* Feature Navigation - Eye-comfortable 7-item modern segmented strip */}
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-7 gap-2 sm:gap-2.5 mb-8">
          {features.map((feat, idx) => {
            const IconComponent = feat.icon;
            const isActive = activeFeatureIndex === idx;
            return (
              <button
                key={feat.id}
                onClick={() => setActiveFeatureIndex(idx)}
                className={`p-3 rounded-[var(--radius-control)] border text-start transition-all cursor-pointer relative group ${
                  isActive
                    ? 'bg-[var(--surface-hover)] border-[var(--brand)] shadow-xs ring-1 ring-[var(--brand)]/30'
                    : 'bg-[var(--surface)] border-[var(--line)] hover:border-[var(--line-strong)] hover:bg-[var(--surface-hover)]/50'
                }`}
              >
                <div className="flex items-center justify-between mb-2">
                  <span className="text-[11px] font-code text-[var(--ink-muted)]">0{idx + 1}</span>
                  <IconComponent
                    className={`w-3.5 h-3.5 transition-colors ${
                      isActive ? 'text-[var(--brand)]' : 'text-[var(--ink-muted)] group-hover:text-[var(--ink)]'
                    }`}
                  />
                </div>
                <div className="text-[12px] font-bold text-[var(--ink)] truncate leading-tight">
                  {isAr ? feat.shortTitleAr : feat.shortTitle}
                </div>
                <div className="text-[10px] text-[var(--ink-muted)] font-code truncate mt-1">
                  {feat.badge}
                </div>
              </button>
            );
          })}
        </div>

        {/* Master Detail Card */}
        <div className="ql-raised p-6 sm:p-8">
          
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
            
            {/* Left: Deep Feature Specification */}
            <div className="lg:col-span-6 space-y-6">
              
              <div className="space-y-2">
                <div className="flex items-center gap-2.5">
                  <span className="ql-tag font-code text-xs">
                    {activeFeature.badge}
                  </span>
                  <span className="text-xs font-code text-[var(--ink-muted)]">
                    {isAr ? `الميزة 0${activeFeatureIndex + 1}` : `Feature 0${activeFeatureIndex + 1}`}
                  </span>
                </div>
                <h3 className="text-xl sm:text-2xl font-bold text-[var(--ink)]">
                  {isAr ? activeFeature.titleAr : activeFeature.title}
                </h3>
                <p className="text-sm text-[var(--ink-muted)] leading-relaxed">
                  {isAr ? activeFeature.summaryAr : activeFeature.summary}
                </p>
              </div>

              {/* Bullet Specs */}
              <div className="space-y-3 pt-2">
                <div className="text-xs font-bold font-code uppercase tracking-wider text-[var(--ink)]">
                  {isAr ? 'المواصفات التقنية:' : 'Technical Specifications:'}
                </div>
                <ul className="space-y-2.5 text-xs sm:text-[13px] text-[var(--ink-muted)]">
                  {(isAr ? activeFeature.bulletsAr : activeFeature.bullets).map((bullet, bIdx) => (
                    <li key={bIdx} className="flex items-start gap-2.5">
                      <CheckCircle2 className="w-4 h-4 text-[var(--state-correct)] shrink-0 mt-0.5" />
                      <span>{bullet}</span>
                    </li>
                  ))}
                </ul>
              </div>

            </div>

            {/* Right: Verified Code Implementation Snippet */}
            <div className="lg:col-span-6 space-y-3">
              <div className="flex items-center justify-between text-xs font-code text-[var(--ink-muted)]">
                <span>Verified Dart Implementation</span>
                <button
                  onClick={() => copyCode(activeFeature.codeSnippet)}
                  className="flex items-center gap-1.5 text-xs p-1.5 rounded hover:bg-[var(--surface-hover)] text-[var(--ink)] transition-colors cursor-pointer"
                >
                  {copied ? <Check className="w-3.5 h-3.5 text-[var(--state-correct)]" /> : <Copy className="w-3.5 h-3.5" />}
                  <span>{copied ? 'Copied!' : 'Copy Code'}</span>
                </button>
              </div>

              <div className="relative rounded-[var(--radius-control)] overflow-hidden border border-[var(--line-strong)] bg-[var(--paper)]">
                <pre className="p-4 text-xs font-code text-[var(--ink)] overflow-x-auto leading-relaxed" dir="ltr">
                  <code>{activeFeature.codeSnippet}</code>
                </pre>
              </div>

              {/* Invariant Footer Strip */}
              <div className="p-3 rounded-[var(--radius-control)] bg-[var(--surface)] border border-[var(--line)] flex items-center justify-between text-[11px] font-code text-[var(--ink-muted)]">
                <span>Thread-safe · Background Isolate</span>
                <span className="text-[var(--state-correct)] font-semibold">Zero-Network Required</span>
              </div>

            </div>

          </div>

        </div>

      </div>
    </section>
  );
};

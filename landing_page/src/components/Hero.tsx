import React, { useState } from 'react';
import { LangMode } from '../types';
import { Copy, Check, ArrowUpRight, Terminal, Cpu, Globe } from 'lucide-react';

interface HeroProps {
  lang: LangMode;
  onExploreSdk: () => void;
  onExploreNatlu: () => void;
}

const GooglePlayIcon: React.FC<{ className?: string }> = ({ className = 'w-3 h-3' }) => (
  <svg className={className} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M3.609 1.814L13.793 12 3.61 22.186c-.37-.36-.61-.88-.61-1.476V3.29c0-.596.24-1.116.609-1.476zm11.24 11.24l2.42-2.42-12.01-6.93 9.59 9.35zm0 1.892l-9.59 9.35 12.01-6.93-2.42-2.42zm1.48-1.48l3.69 2.13c1.02.59 1.02 1.55 0 2.14l-3.69 2.13-2.58-2.58 2.58-1.69z" />
  </svg>
);

const AppleIcon: React.FC<{ className?: string }> = ({ className = 'w-3 h-3' }) => (
  <svg className={className} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M15.97 6.37c.62-.75 1.04-1.8 0.93-2.85-.9.04-1.99.6-2.63 1.35-.57.65-1.07 1.72-.94 2.74 1 .08 2.02-.49 2.64-1.24z" />
  </svg>
);

export const Hero: React.FC<HeroProps> = ({ lang, onExploreSdk, onExploreNatlu }) => {
  const [copied, setCopied] = useState(false);
  const [installTab, setInstallTab] = useState<'flutter' | 'dart' | 'pubspec'>('flutter');
  const [heroCodeTab, setHeroCodeTab] = useState<'reader' | 'stream' | 'tajweed' | 'search'>('reader');
  const isAr = lang === 'ar';

  const installCommands = {
    flutter: 'flutter pub add recite_quran',
    dart: 'dart pub add recite_quran',
    pubspec: 'recite_quran: ^1.0.5',
  };

  const copyCommand = () => {
    navigator.clipboard.writeText(installCommands[installTab]);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const heroCodeSnippets = {
    reader: `// Hands-Free Reader (Auto-Reanchor)
final tracker = ReciteQuran(
  repository: quranRepository,
  config: const TrackerConfig(
    enableEarlyMatching: true,
    enableAutoReanchor: true,
  ),
  isTajweed: false,
);
await tracker.initialize();
tracker.setTargetSurah(1);`,

    stream: `// Real-Time Word Event Stream
tracker.onWordMatched.listen((event) {
  if (event.isGreen) {
    highlightWord(event.wordId, color: Colors.green);
  } else if (event.isYellow) {
    showTajweedWarning(event.tajweedErrors);
  } else if (event.isRed) {
    markOmission(event.wordId);
  }
});`,

    tajweed: `// Strict Tajweed Examination
final examTracker = ReciteQuran(
  repository: quranRepository,
  isTajweed: true,
  config: const TrackerConfig(
    matchingStrictness: MatchingStrictness.strict,
    enableEarlyMatching: false,
    enableAutoReanchor: false,
  ),
);`,

    search: `// "Recite to Navigate" Voice Search
final search = VoiceSearchController(engine: sherpaEngine);
await search.preloadIndex();

search.currentResult.addListener(() {
  final match = search.currentResult.value?.topMatch;
  if (match != null) {
    navigateToSurah(match.surah, ayah: match.ayah);
  }
});`
  };

  return (
    <section className="relative pt-36 pb-16 border-b border-[var(--line)] overflow-hidden">
      
      {/* Soothing Ambient Aura */}
      <div
        className="absolute top-10 left-1/2 -translate-x-1/2 w-[720px] h-[280px] pointer-events-none opacity-20 blur-3xl -z-10"
        style={{
          background: 'radial-gradient(ellipse at center, var(--brand-tint) 0%, transparent 70%)',
        }}
      />

      <div className="max-w-[1248px] mx-auto px-4 sm:px-6">
        
        {/* Top Bar: Package & Model on Start · App Links on End */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-4 mb-8 border-b border-[var(--line)]">
          
          {/* Start: Package & Model Links Side by Side */}
          <div className="flex flex-wrap items-center justify-center sm:justify-start gap-2">
            <a
              href="https://pub.dev/packages/recite_quran"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 h-[28px] px-3 rounded-lg border border-[var(--line)] bg-[var(--surface)] hover:bg-[var(--surface-hover)] hover:border-[var(--line-strong)] text-[12px] font-code text-[var(--ink)] transition-all cursor-pointer shadow-2xs"
            >
              <span className="w-1.5 h-1.5 rounded-full bg-[var(--brand)] shrink-0" />
              <span>pub.dev/packages/recite_quran</span>
              <ArrowUpRight className="w-3 h-3 text-[var(--ink-muted)] shrink-0" />
            </a>

            <a
              href="https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 h-[28px] px-3 rounded-lg border border-[var(--brand)]/30 bg-[var(--brand-tint)] hover:bg-[var(--brand-tint-hover)] text-[12px] font-code text-[var(--brand)] transition-all cursor-pointer shadow-2xs"
            >
              <Cpu className="w-3.5 h-3.5 shrink-0" />
              <span>Zipformer v3 (Hugging Face)</span>
              <ArrowUpRight className="w-3 h-3 shrink-0" />
            </a>
          </div>

          {/* End: Compact Segmented Links for Natlu App */}
          <div className="flex flex-wrap items-center justify-center sm:justify-end gap-1.5 font-code text-[12px]">
            {/* Web App Link */}
            <a
              href="https://recitequran.pages.dev/recite"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 h-[28px] px-3 rounded-lg border border-[var(--brand)]/30 bg-[var(--brand-tint)] text-[var(--brand)] hover:bg-[var(--brand-tint-hover)] transition-all cursor-pointer shadow-2xs"
              title="Open Natlu Web App"
            >
              <Globe className="w-3.5 h-3.5 shrink-0" />
              <span>{isAr ? 'تطبيق الويب' : 'Web App'}</span>
              <ArrowUpRight className="w-2.5 h-2.5 opacity-70 shrink-0" />
            </a>

            {/* Google Play */}
            <a
              href="https://play.google.com/store/apps/details?id=com.recitequran.app"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 h-[28px] px-3 rounded-lg border border-[var(--line)] bg-[var(--surface)] hover:bg-[var(--surface-hover)] text-[var(--ink)] transition-all cursor-pointer shadow-2xs"
              title="Google Play"
            >
              <GooglePlayIcon className="w-3.5 h-3.5 shrink-0" />
              <span>Google Play</span>
            </a>

            {/* App Store */}
            <a
              href="https://apps.apple.com/app/id6806614841"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 h-[28px] px-3 rounded-lg border border-[var(--line)] bg-[var(--surface)] hover:bg-[var(--surface-hover)] text-[var(--ink)] transition-all cursor-pointer shadow-2xs"
              title="App Store"
            >
              <AppleIcon className="w-3.5 h-3.5 shrink-0" />
              <span>App Store</span>
            </a>
          </div>

        </div>

        <div className="grid grid-cols-1 lg:grid-cols-12 gap-10 items-center">
          
          {/* Left Column: Developer Value Proposition */}
          <div className="lg:col-span-7 space-y-5">

            {/* Display Headline: The Great Quran */}
            <h1 className="text-4xl sm:text-5xl lg:text-[46px] font-extrabold tracking-[-0.03em] leading-[1.14] text-[var(--ink)] text-balance">
              {isAr ? 'القرآن العظيم' : 'The Great Quran'}
            </h1>

            {/* Body Description */}
            <p className="text-base text-[var(--ink-muted)] max-w-[620px] leading-[1.65]">
              {isAr ? (
                <>
                  البديل المفتوح المصدر لـ{' '}
                  <span dir="ltr" className="font-semibold text-[var(--ink)]">
                    Tarteel AI
                  </span>
                  ؛ تتبع صوتي مباشر كلمة بكلمة، تقليب تلقائي للصفحات مع التلاوة دون لمس الشاشة، فحص أحكام التجويد، وبحث صوتي سريع — يعمل محلياً بالكامل على الجهاز{' '}
                  <span dir="ltr" className="font-semibold text-[var(--ink)]">
                    (On-Device)
                  </span>{' '}
                  في سبيل الله سبحانه وتعالى.
                </>
              ) : (
                <>
                  The open-source, on-device Tarteel AI alternative for Flutter. Real-time word tracking, hands-free page navigation, acoustic Tajweed verification, and voice search — running 100% locally on-device, for the sake of Allah{' '}
                  <bdi dir="rtl" className="font-ui-ar">
                    (سبحانه وتعالى)
                  </bdi>
                  <span dir="ltr">.</span>
                </>
              )}
            </p>

            {/* Install Box */}
            <div className="space-y-2 pt-1 max-w-lg">
              <div className="flex items-center gap-2 text-xs text-[var(--ink-muted)] font-code">
                <button
                  onClick={() => setInstallTab('flutter')}
                  className={`cursor-pointer transition-colors ${
                    installTab === 'flutter' ? 'text-[var(--ink)] font-bold' : 'hover:text-[var(--ink)]'
                  }`}
                >
                  flutter pub add
                </button>
                <span>·</span>
                <button
                  onClick={() => setInstallTab('dart')}
                  className={`cursor-pointer transition-colors ${
                    installTab === 'dart' ? 'text-[var(--ink)] font-bold' : 'hover:text-[var(--ink)]'
                  }`}
                >
                  dart pub add
                </button>
                <span>·</span>
                <button
                  onClick={() => setInstallTab('pubspec')}
                  className={`cursor-pointer transition-colors ${
                    installTab === 'pubspec' ? 'text-[var(--ink)] font-bold' : 'hover:text-[var(--ink)]'
                  }`}
                >
                  pubspec.yaml
                </button>
              </div>

              <div className="flex items-center justify-between px-3.5 py-2.5 rounded-[var(--radius-control)] border border-[var(--line-strong)] bg-[var(--surface)] font-code text-xs sm:text-[13px] text-[var(--ink)]">
                <div className="flex items-center gap-2.5 select-all overflow-x-auto" dir="ltr">
                  <Terminal className="w-4 h-4 text-[var(--brand)] shrink-0" />
                  <span className="whitespace-nowrap">{installCommands[installTab]}</span>
                </div>
                <button
                  onClick={copyCommand}
                  className="ms-3 p-1 rounded hover:bg-[var(--surface-hover)] text-[var(--ink-muted)] hover:text-[var(--ink)] transition-colors cursor-pointer shrink-0"
                  title="Copy command"
                >
                  {copied ? <Check className="w-4 h-4 text-[var(--state-correct)]" /> : <Copy className="w-4 h-4" />}
                </button>
              </div>
            </div>

            {/* Action Buttons */}
            <div className="flex flex-wrap items-center gap-3 pt-1">
              <button
                onClick={onExploreSdk}
                className="ql-btn ql-btn-md ql-btn-primary"
              >
                <span>{isAr ? 'توثيق الحزمة للمطورين' : 'Package Developer Docs'}</span>
                <ArrowUpRight className="w-4 h-4 shrink-0" />
              </button>

              <button
                onClick={onExploreNatlu}
                className="ql-btn ql-btn-md ql-btn-secondary"
              >
                <span>{isAr ? 'تطبيق اتلو (النموذج المرجعي)' : 'Natlu Reference App'}</span>
              </button>
            </div>

            {/* Minimal Invariants Strip */}
            <div className="pt-3 border-t border-[var(--line)] flex flex-wrap items-center gap-4 text-xs text-[var(--ink-muted)] font-code">
              <div>
                <span className="text-[var(--ink)] font-semibold">{isAr ? 'زمن الاستجابة: ' : 'Latency: '}</span>
                <span dir="ltr">&lt; 15ms</span>
              </div>
              <span aria-hidden="true">·</span>
              <div>
                <span className="text-[var(--ink)] font-semibold">{isAr ? 'المعمارية: ' : 'Architecture: '}</span>
                <span dir="ltr">On-Device C++ ONNX</span>
              </div>
              <span aria-hidden="true">·</span>
              <div>
                <span className="text-[var(--ink)] font-semibold">{isAr ? 'الغاية: ' : 'Purpose: '}</span>
                <span>
                  {isAr ? (
                    'في سبيل الله سبحانه وتعالى'
                  ) : (
                    <>
                      For the sake of Allah <bdi dir="rtl" className="font-ui-ar">(سبحانه وتعالى)</bdi>
                    </>
                  )}
                </span>
              </div>
            </div>

          </div>

          {/* Right Column: Focused Clean Code Inspector */}
          <div className="lg:col-span-5">
            <div className="ql-raised p-5 space-y-4">
              
              {/* Header with Switcher Tabs */}
              <div className="flex items-center justify-between pb-3 border-b border-[var(--line)]">
                <div className="flex items-center gap-1.5">
                  <span className="w-2.5 h-2.5 rounded-full bg-red-400/80" />
                  <span className="w-2.5 h-2.5 rounded-full bg-amber-400/80" />
                  <span className="w-2.5 h-2.5 rounded-full bg-emerald-400/80" />
                  <span className="text-xs font-code font-semibold text-[var(--ink-muted)] ms-2">
                    Flutter / Dart
                  </span>
                </div>
                <span className="text-xs font-code text-[var(--ink-muted)]" dir="ltr">
                  package:recite_quran
                </span>
              </div>

              {/* Snippet Tabs */}
              <div className="flex items-center gap-1 overflow-x-auto pb-1">
                {(['reader', 'stream', 'tajweed', 'search'] as const).map((tab) => (
                  <button
                    key={tab}
                    onClick={() => setHeroCodeTab(tab)}
                    className={`px-2.5 py-1 rounded text-xs font-code transition-colors cursor-pointer capitalize ${
                      heroCodeTab === tab
                        ? 'bg-[var(--brand-tint)] text-[var(--brand)] font-bold'
                        : 'text-[var(--ink-muted)] hover:text-[var(--ink)]'
                    }`}
                  >
                    {tab === 'reader' ? (isAr ? 'القراءة والتمرير' : 'Dictation') : tab === 'stream' ? (isAr ? 'الأحداث المباشرة' : 'Events') : tab === 'tajweed' ? (isAr ? 'فحص التجويد' : 'Tajweed') : (isAr ? 'البحث الصوتي' : 'Voice Search')}
                  </button>
                ))}
              </div>

              {/* Code Pre Block */}
              <pre className="p-4 rounded-[var(--radius-control)] bg-[var(--paper)] border border-[var(--line)] text-xs font-code overflow-x-auto text-[var(--ink)] leading-relaxed h-[255px]" dir="ltr">
                <code>{heroCodeSnippets[heroCodeTab]}</code>
              </pre>
            </div>
          </div>

        </div>

      </div>

    </section>
  );
};

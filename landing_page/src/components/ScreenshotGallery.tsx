import React, { useState } from 'react';
import { LangMode, AppScreenshot } from '../types';
import { APP_SCREENSHOTS } from '../data/recitationData';
import { Maximize2, X, ArrowUpRight, Package } from 'lucide-react';

interface ScreenshotGalleryProps {
  lang: LangMode;
}

export const ScreenshotGallery: React.FC<ScreenshotGalleryProps> = ({ lang }) => {
  const isAr = lang === 'ar';
  const [selectedScreenshot, setSelectedScreenshot] = useState<AppScreenshot | null>(null);

  return (
    <section id="natlu-example" className="py-16 border-b border-[var(--line)]">
      <div className="max-w-[1248px] mx-auto px-4 sm:px-6">
        
        {/* Section Header */}
        <div className="flex flex-col md:flex-row md:items-end justify-between gap-6 mb-8">
          <div className="space-y-1.5 max-w-[720px]">
            <h2 className="text-2xl sm:text-3xl font-extrabold tracking-[-0.02em] text-[var(--ink)]">
              {isAr ? 'تطبيق اتلو — نموذج عملي معتمد على حزمة recite_quran' : 'Natlu: Built with recite_quran as Backend'}
            </h2>
            <p className="text-sm text-[var(--ink-muted)] leading-[1.6]">
              {isAr
                ? 'تطبيق قرآني متكامل لـ Flutter يعتمد على حزمة recite_quran كمحرك أساسي لمعالجة الصوت ومحاذاة التلاوة، مع واجهة مصحف المدينة المنورة 15 سطرًا.'
                : 'A production Flutter app that uses package:recite_quran as its core recognition and alignment backend, pairing it with a 15-line Madani Mus\'haf UI.'}
            </p>
          </div>

          <div className="flex flex-wrap items-center gap-2 shrink-0">
            <a
              href="https://recitequran.pages.dev/recite"
              target="_blank"
              rel="noopener noreferrer"
              className="ql-btn ql-btn-sm ql-btn-primary text-xs"
            >
              <span>{isAr ? 'تطبيق الويب' : 'Web App'}</span>
              <ArrowUpRight className="w-3.5 h-3.5" />
            </a>

            <a
              href="https://play.google.com/store/apps/details?id=com.recitequran.app"
              target="_blank"
              rel="noopener noreferrer"
              className="ql-btn ql-btn-sm ql-btn-secondary text-xs"
            >
              <span>Google Play</span>
            </a>

            <a
              href="https://apps.apple.com/app/id6806614841"
              target="_blank"
              rel="noopener noreferrer"
              className="ql-btn ql-btn-sm ql-btn-secondary text-xs"
            >
              <span>App Store</span>
            </a>

            <a
              href="https://github.com/Iam-Muslim/Natlu"
              target="_blank"
              rel="noopener noreferrer"
              className="ql-btn ql-btn-sm ql-btn-secondary text-xs"
            >
              <span>GitHub</span>
              <ArrowUpRight className="w-3.5 h-3.5 text-[var(--ink-muted)]" />
            </a>
          </div>
        </div>

        {/* Concise Backend Explanation Box */}
        <div className="p-4 rounded-[var(--radius-surface)] bg-[var(--surface)] border border-[var(--line)] mb-8 flex flex-col sm:flex-row sm:items-center justify-between gap-3 text-xs">
          <div className="flex items-center gap-2.5 text-[var(--ink)]">
            <Package className="w-4 h-4 text-[var(--brand)] shrink-0" />
            <span>
              {isAr
                ? 'يعتمد تطبيق اتلو في ملف pubspec.yaml على recite_quran: ^1.0.5 لكافة مهام التتبع الصوتي والتجويد والبحث.'
                : 'Natlu relies on recite_quran: ^1.0.5 in pubspec.yaml for all audio processing, DP alignment, and Myers search.'}
            </span>
          </div>
          <span className="font-code text-[var(--ink-muted)] shrink-0">
            Android · iOS · Web · Desktop
          </span>
        </div>

        {/* Compact, Smaller Smartphone Cards Grid (Full-Screen Stretched, Zero Top Bar/Notch/Battery) */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 sm:gap-6">
          {APP_SCREENSHOTS.map((item) => (
            <div
              key={item.id}
              className="ql-raised p-3 flex flex-col justify-between group transition-all duration-300 hover:border-[var(--line-strong)]"
            >
              {/* Phone Screen Bezel: Exact 1080x2340 Mobile Aspect Ratio (No cropping at bottom) */}
              <div
                className="relative rounded-[16px] overflow-hidden bg-black border border-[var(--line-strong)] w-full max-w-[210px] mx-auto aspect-[1080/2340] shadow-md cursor-pointer group/screen flex items-center justify-center"
                onClick={() => setSelectedScreenshot(item)}
              >
                {/* 100% Fully Visible App Screenshot (Zero bottom or top crop) */}
                <img
                  src={item.image}
                  alt={isAr ? item.titleAr : item.title}
                  loading="lazy"
                  referrerPolicy="no-referrer"
                  className="w-full h-full object-contain block transition-transform duration-300 group-hover/screen:scale-[1.02]"
                />

                {/* Hover Inspect Overlay */}
                <div className="absolute inset-0 bg-black/40 opacity-0 group-hover/screen:opacity-100 transition-opacity flex items-center justify-center gap-1.5 text-white font-medium text-[11px] backdrop-blur-xs">
                  <Maximize2 className="w-3.5 h-3.5 text-white" />
                  <span>{isAr ? 'تكبير' : 'Zoom'}</span>
                </div>
              </div>

              {/* Minimal Title & Caption */}
              <div className="pt-3 text-center space-y-1">
                <h3 className="text-xs font-bold text-[var(--ink)]">
                  {isAr ? item.titleAr : item.title}
                </h3>
                <p className="text-[11px] text-[var(--ink-muted)] line-clamp-1">
                  {isAr ? item.taglineAr : item.tagline}
                </p>
              </div>

            </div>
          ))}
        </div>

        {/* Lightbox Modal */}
        {selectedScreenshot && (
          <div
            className="fixed inset-0 z-50 bg-[var(--scrim)] backdrop-blur-md flex items-center justify-center p-4 sm:p-6 overflow-y-auto"
            onClick={() => setSelectedScreenshot(null)}
          >
            <div
              className="relative max-w-2xl w-full ql-raised p-5 sm:p-6 shadow-3 overflow-hidden flex flex-col sm:flex-row gap-6 items-center my-auto max-h-[90vh]"
              onClick={(e) => e.stopPropagation()}
            >
              <button
                onClick={() => setSelectedScreenshot(null)}
                className="absolute top-3 right-3 p-1.5 rounded-[var(--radius-control)] text-[var(--ink-muted)] hover:text-[var(--ink)] hover:bg-[var(--surface)] transition-colors cursor-pointer z-10"
              >
                <X className="w-4 h-4" />
              </button>

              <div className="rounded-[16px] overflow-hidden border border-[var(--line)] max-h-[75vh] sm:max-h-[520px] aspect-[1080/2340] bg-black shadow-md shrink-0 flex items-center justify-center">
                <img
                  src={selectedScreenshot.image}
                  alt={selectedScreenshot.title}
                  className="h-full w-auto max-h-[75vh] sm:max-h-[520px] object-contain block"
                />
              </div>

              <div className="space-y-3 flex-1">
                <h3 className="text-xl font-bold text-[var(--ink)]">
                  {isAr ? selectedScreenshot.titleAr : selectedScreenshot.title}
                </h3>
                <p className="text-xs text-[var(--ink-muted)] leading-relaxed">
                  {isAr ? selectedScreenshot.taglineAr : selectedScreenshot.tagline}
                </p>

                <div className="pt-2 border-t border-[var(--line)] space-y-1.5 text-xs text-[var(--ink-muted)]">
                  {(isAr ? selectedScreenshot.highlightsAr : selectedScreenshot.highlights).map((h, i) => (
                    <div key={i} className="flex items-start gap-2">
                      <span className="text-[var(--state-correct)] font-bold">·</span>
                      <span>{h}</span>
                    </div>
                  ))}
                </div>

                <div className="pt-3">
                  <a
                    href="https://github.com/Iam-Muslim/Natlu"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="ql-btn ql-btn-sm ql-btn-secondary text-xs"
                  >
                    <span>{isAr ? 'مستودع اتلو على GitHub' : 'Natlu GitHub Repo'}</span>
                    <ArrowUpRight className="w-3.5 h-3.5" />
                  </a>
                </div>
              </div>

            </div>
          </div>
        )}

      </div>
    </section>
  );
};

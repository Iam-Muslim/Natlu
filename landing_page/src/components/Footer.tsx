import React from 'react';
import { LangMode } from '../types';
import { ArrowUpRight } from 'lucide-react';

interface FooterProps {
  lang: LangMode;
  onScrollTo: (sectionId: string) => void;
}

export const Footer: React.FC<FooterProps> = ({ lang, onScrollTo }) => {
  const isAr = lang === 'ar';

  return (
    <footer className="py-12 bg-[var(--paper)]">
      <div className="max-w-[1248px] mx-auto px-4 sm:px-6">
        
        <div className="ql-raised p-8 space-y-6">
          
          <div className="grid grid-cols-1 md:grid-cols-12 gap-8 items-start">
            
            {/* About Column */}
            <div className="md:col-span-6 space-y-2">
              <div className="flex items-center gap-2.5">
                <span
                  className="inline-flex items-center gap-[2.5px] h-[20px] text-[var(--brand)]"
                  aria-hidden="true"
                >
                  <span className="w-[3px] h-[6px] bg-current rounded-full" />
                  <span className="w-[3px] h-[13px] bg-current rounded-full" />
                  <span className="w-[3px] h-[20px] bg-current rounded-full" />
                  <span className="w-[3px] h-[13px] bg-current rounded-full" />
                  <span className="w-[3px] h-[6px] bg-current rounded-full" />
                </span>
                <span className="text-sm font-bold text-[var(--ink)]">
                  ReciteQuran <span className="font-ui-ar font-normal text-xs text-[var(--ink-muted)]">· اتلو القرآن</span>
                </span>
              </div>
              <p className="text-xs text-[var(--ink-muted)] leading-[1.65] max-w-md">
                {isAr ? (
                  <>
                    محرك ذكاء اصطناعي مفتوح على الهاتف لتصحيح وتتبع تلاوة القرآن العظيم لتطبيقات{' '}
                    <span dir="ltr" className="font-semibold text-[var(--ink)]">Flutter</span>، في سبيل الله سبحانه وتعالى وحده.
                  </>
                ) : (
                  <>
                    Open-source, on-device AI for real-time Quran recitation tracking in Flutter apps. Dedicated for the sake of Allah{' '}
                    <bdi dir="rtl" className="font-ui-ar">
                      (سبحانه وتعالى)
                    </bdi>{' '}
                    alone.
                  </>
                )}
              </p>
            </div>

            {/* Quick Links Column */}
            <div className="md:col-span-3 space-y-1.5">
              <div className="text-xs font-semibold uppercase text-[var(--ink)] font-code">
                {isAr ? 'الأقسام' : 'Navigation'}
              </div>
              <div className="flex flex-col gap-1.5 text-xs text-[var(--ink-muted)]">
                <button
                  onClick={() => onScrollTo('engine-features')}
                  className="hover:text-[var(--ink)] text-start transition-colors cursor-pointer"
                >
                  {isAr ? 'ميزات المحرك' : 'Engine Features'}
                </button>
                <button
                  onClick={() => onScrollTo('developer-sdk')}
                  className="hover:text-[var(--ink)] text-start transition-colors cursor-pointer"
                >
                  {isAr ? 'توثيق الحزمة' : 'Package Docs'}
                </button>
                <button
                  onClick={() => onScrollTo('natlu-example')}
                  className="hover:text-[var(--ink)] text-start transition-colors cursor-pointer"
                >
                  {isAr ? 'تطبيق اتلو' : 'Natlu App'}
                </button>
                <button
                  onClick={() => onScrollTo('for-the-sake-of-allah')}
                  className="hover:text-[var(--ink)] text-start transition-colors cursor-pointer"
                >
                  {isAr ? (
                    'في سبيل الله سبحانه وتعالى'
                  ) : (
                    <>
                      For the sake of Allah <bdi dir="rtl" className="font-ui-ar">(سبحانه وتعالى)</bdi>
                    </>
                  )}
                </button>
              </div>
            </div>

            {/* Source Code Repositories */}
            <div className="md:col-span-3 space-y-1.5">
              <div className="text-xs font-semibold uppercase text-[var(--ink)] font-code">
                {isAr ? 'المصادر البرمجية' : 'Source Code'}
              </div>
              <div className="flex flex-col gap-1.5 text-xs">
                <a
                  href="https://pub.dev/packages/recite_quran"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1.5 text-[var(--ink-muted)] hover:text-[var(--ink)] font-code"
                >
                  <span dir="ltr">pub.dev/packages/recite_quran</span>
                  <ArrowUpRight className="w-3 h-3 text-[var(--brand)]" />
                </a>
                <a
                  href="https://github.com/Iam-Muslim/ReciteQuran"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1.5 text-[var(--ink-muted)] hover:text-[var(--ink)] font-code"
                >
                  <span dir="ltr">ReciteQuran GitHub</span>
                  <ArrowUpRight className="w-3 h-3 text-[var(--brand)]" />
                </a>
                <a
                  href="https://github.com/Iam-Muslim/Natlu"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1.5 text-[var(--ink-muted)] hover:text-[var(--ink)] font-code"
                >
                  <span dir="ltr">Natlu App GitHub</span>
                  <ArrowUpRight className="w-3 h-3 text-[var(--brand)]" />
                </a>
              </div>
            </div>

          </div>

          {/* Bottom Bar - Guaranteed BiDi Alignment */}
          <div className="pt-4 border-t border-[var(--line)] flex flex-col sm:flex-row items-center justify-between gap-3 text-xs text-[var(--ink-muted)] font-code">
            <span dir="ltr" className="inline-flex items-center gap-1 text-start">
              <span>Free and open source for the sake of Allah</span>
              <bdi dir="rtl" className="font-ui-ar text-[var(--ink)]">(سبحانه وتعالى)</bdi>
              <span>alone.</span>
            </span>
            <span className="font-ui-ar text-start" dir="rtl">
              لوجه الله سبحانه وتعالى وحده · في سبيل الله
            </span>
          </div>

        </div>

      </div>
    </footer>
  );
};

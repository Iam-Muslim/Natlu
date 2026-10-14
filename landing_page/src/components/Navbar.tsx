import React, { useState, useEffect } from 'react';
import { ThemeMode, LangMode } from '../types';
import { ArrowUpRight } from 'lucide-react';

interface NavbarProps {
  theme: ThemeMode;
  onToggleTheme: () => void;
  lang: LangMode;
  onToggleLang: () => void;
  onScrollTo: (sectionId: string) => void;
}

export const Navbar: React.FC<NavbarProps> = ({
  theme,
  onToggleTheme,
  lang,
  onToggleLang,
  onScrollTo,
}) => {
  const isAr = lang === 'ar';
  const [scrollProgress, setScrollProgress] = useState(0);

  useEffect(() => {
    const handleScroll = () => {
      const totalScroll = document.documentElement.scrollHeight - window.innerHeight;
      if (totalScroll > 0) {
        setScrollProgress((window.scrollY / totalScroll) * 100);
      }
    };

    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  return (
    <>
      {/* Reading scroll progress line */}
      <div
        className="fixed top-0 left-0 h-[2px] bg-[var(--brand)] z-[60] transition-all duration-75 ease-out opacity-90"
        style={{ width: `${scrollProgress}%` }}
      />

      <header className="ql-header">
        <div className="ql-bar">

          {/* Left: Brand Lockup */}
          <div className="flex items-center gap-3 shrink-0">
            <a
              href="/"
              onClick={(e) => {
                e.preventDefault();
                window.scrollTo({ top: 0, behavior: 'smooth' });
              }}
              className="flex items-center gap-2.5 group text-decoration-none"
              aria-label="ReciteQuran home"
            >
              {/* Minimalist modern waveform badge */}
              <div className="relative flex items-center justify-center w-8 h-8 rounded-xl bg-[var(--surface)] border border-[var(--line)] shadow-xs group-hover:border-[var(--brand)]/40 transition-colors">
                <span
                  className="inline-flex items-center gap-[2px] h-[16px] text-[var(--brand)] shrink-0"
                  aria-hidden="true"
                >
                  <span className="w-[2px] h-[6px] bg-current rounded-full group-hover:h-[9px] transition-all" />
                  <span className="w-[2px] h-[12px] bg-current rounded-full group-hover:h-[15px] transition-all" />
                  <span className="w-[2px] h-[16px] bg-current rounded-full group-hover:h-[12px] transition-all" />
                  <span className="w-[2px] h-[11px] bg-current rounded-full group-hover:h-[7px] transition-all" />
                  <span className="w-[2px] h-[5px] bg-current rounded-full group-hover:h-[11px] transition-all" />
                </span>
              </div>

              <div className="flex items-baseline gap-2">
                <span className="text-[15.5px] font-bold tracking-tight text-[var(--ink)]">
                  ReciteQuran
                </span>
                <span className="font-ui-ar text-xs font-medium text-[var(--ink-muted)]">
                  اتلو القرآن
                </span>
              </div>
            </a>
          </div>

          {/* Center: Navigation Links */}
          <nav className="hidden lg:flex items-center gap-1 text-[13px] font-medium text-[var(--ink-muted)]" aria-label="Main">
            <button
              onClick={() => onScrollTo('engine-features')}
              className="px-3.5 py-1.5 rounded-full hover:bg-[var(--surface)] hover:text-[var(--ink)] transition-all cursor-pointer"
            >
              {isAr ? 'ميزات المحرك' : 'Features'}
            </button>
            <button
              onClick={() => onScrollTo('developer-sdk')}
              className="px-3.5 py-1.5 rounded-full hover:bg-[var(--surface)] hover:text-[var(--ink)] transition-all cursor-pointer"
            >
              {isAr ? 'توثيق الحزمة' : 'Package Docs'}
            </button>
            <button
              onClick={() => onScrollTo('natlu-example')}
              className="px-3.5 py-1.5 rounded-full hover:bg-[var(--surface)] hover:text-[var(--ink)] transition-all cursor-pointer"
            >
              {isAr ? 'تطبيق اتلو' : 'Natlu App'}
            </button>
            <button
              onClick={() => onScrollTo('for-the-sake-of-allah')}
              className="px-3.5 py-1.5 rounded-full hover:bg-[var(--surface)] hover:text-[var(--ink)] transition-all cursor-pointer"
            >
              {isAr ? (
                'في سبيل الله سبحانه وتعالى'
              ) : (
                <>
                  For the sake of Allah <bdi dir="rtl" className="font-ui-ar">(سبحانه وتعالى)</bdi>
                </>
              )}
            </button>
          </nav>

          {/* Right: Controls & CTAs */}
          <div className="flex items-center gap-1.5 sm:gap-2 shrink-0">

            {/* Language Toggle */}
            <button
              onClick={onToggleLang}
              className="h-[32px] px-2.5 rounded-lg border border-[var(--line)] bg-[var(--surface)]/80 hover:bg-[var(--surface-hover)] text-xs font-semibold text-[var(--ink)] transition-all cursor-pointer active:scale-95"
              title={isAr ? 'Switch to English' : 'التحويل للعربية'}
            >
              {isAr ? 'EN' : 'عربي'}
            </button>

            {/* Theme Toggle - Minimal text White / Black (no icons as requested) */}
            <button
              onClick={onToggleTheme}
              className="h-[32px] px-2.5 rounded-lg border border-[var(--line)] bg-[var(--surface)]/80 hover:bg-[var(--surface-hover)] text-xs font-code font-semibold text-[var(--ink)] transition-all cursor-pointer active:scale-95"
              title={theme === 'dark' ? 'Switch to White mode' : 'Switch to Black mode'}
            >
              {theme === 'dark' ? 'White' : 'Black'}
            </button>

            {/* GitHub Repo Button (Text only, no logo as requested) */}
            <a
              href="https://github.com/Iam-Muslim/Natlu"
              target="_blank"
              rel="noopener noreferrer"
              className="hidden sm:inline-flex items-center gap-1.5 h-[32px] px-3 rounded-lg border border-[var(--line)] bg-[var(--surface)]/80 hover:bg-[var(--surface-hover)] text-xs font-medium text-[var(--ink)] transition-all active:scale-95"
            >
              <span>GitHub</span>
              <ArrowUpRight className="w-3 h-3 text-[var(--ink-muted)]" />
            </a>

            {/* Quickstart / Package CTA - Direct pub.dev package link */}
            <a
              href="https://pub.dev/packages/recite_quran"
              target="_blank"
              rel="noopener noreferrer"
              className="h-[32px] px-3.5 rounded-lg bg-[var(--brand)] hover:bg-[var(--brand-hover)] text-[var(--on-brand)] text-xs font-semibold shadow-xs active:scale-95 transition-all inline-flex items-center gap-1.5 cursor-pointer"
              title="Get recite_quran on pub.dev"
            >
              <span>{isAr ? 'الحزمة على pub.dev' : 'Get Package'}</span>
              <ArrowUpRight className="w-3.5 h-3.5 shrink-0" />
            </a>

          </div>

        </div>

        {/* Directly down the top bar: Quranic Blessing Ribbon (Centered height, no dots) */}
        <div className="flex justify-center mt-1.5 pointer-events-none">
          <div className="ql-blessing-pill" dir="rtl" lang="ar">
            <span className="ql-blessing-text">بفضل الله و برحمته</span>
          </div>
        </div>
      </header>
    </>
  );
};

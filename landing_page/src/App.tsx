import React, { useState, useEffect } from 'react';
import { ThemeMode, LangMode } from './types';
import { Navbar } from './components/Navbar';
import { Hero } from './components/Hero';
import { EngineFeatures } from './components/EngineFeatures';
import { DevSdkPortal } from './components/DevSdkPortal';
import { ScreenshotGallery } from './components/ScreenshotGallery';
import { SacredCovenant } from './components/SacredCovenant';
import { Footer } from './components/Footer';

export default function App() {
  const [theme, setTheme] = useState<ThemeMode>('dark');
  const [lang, setLang] = useState<LangMode>('en');

  // Sync theme with QuranLab data-theme attribute
  useEffect(() => {
    const root = document.documentElement;
    root.setAttribute('data-theme', theme);
    if (theme === 'dark') {
      root.classList.add('dark');
      root.classList.remove('light');
    } else {
      root.classList.remove('dark');
      root.classList.add('light');
    }
  }, [theme]);

  // Set document direction and lang
  useEffect(() => {
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
  }, [lang]);

  const toggleTheme = () => {
    setTheme((prev) => (prev === 'dark' ? 'light' : 'dark'));
  };

  const toggleLang = () => {
    setLang((prev) => (prev === 'en' ? 'ar' : 'en'));
  };

  const scrollToSection = (sectionId: string) => {
    const el = document.getElementById(sectionId);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth' });
    }
  };

  return (
    <div className={`min-h-screen flex flex-col bg-[var(--paper)] text-[var(--ink)] ${lang === 'ar' ? 'font-ui-ar' : 'font-ui'} transition-colors duration-200`}>
      {/* Top Bar Navigation */}
      <Navbar
        theme={theme}
        onToggleTheme={toggleTheme}
        lang={lang}
        onToggleLang={toggleLang}
        onScrollTo={scrollToSection}
      />

      {/* Main Content Sections */}
      <main className="flex-1">
        {/* Hero Section focused entirely on ReciteQuran package */}
        <Hero
          lang={lang}
          onExploreSdk={() => scrollToSection('developer-sdk')}
          onExploreNatlu={() => scrollToSection('natlu-example')}
        />

        {/* 6 Core Engine Capabilities Deep Dive */}
        <EngineFeatures lang={lang} />

        {/* ReciteQuran Developer Hub & Flutter Integration Documentation */}
        <DevSdkPortal lang={lang} />

        {/* Natlu Mobile UI & Screenshots Showcase (Flagship Reference App) */}
        <ScreenshotGallery lang={lang} />

        {/* Dedicated for the Sake of Allah Alone */}
        <SacredCovenant lang={lang} />
      </main>

      {/* QuranLab Footer */}
      <Footer lang={lang} onScrollTo={scrollToSection} />
    </div>
  );
}

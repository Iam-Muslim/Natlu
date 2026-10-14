import React from 'react';
import { LangMode } from '../types';

interface SacredCovenantProps {
  lang: LangMode;
}

export const SacredCovenant: React.FC<SacredCovenantProps> = ({ lang }) => {
  const isAr = lang === 'ar';

  return (
    <section id="for-the-sake-of-allah" className="py-20 border-b border-[var(--line)]">
      <div className="max-w-[1248px] mx-auto px-4 sm:px-6">

        {/* Ayah Header */}
        <div className="text-center max-w-[720px] mx-auto space-y-3 mb-10">
          <div className="font-quran text-2xl sm:text-3xl lg:text-4xl text-[var(--ink)] leading-relaxed select-none" dir="rtl">
            وَمَا أَسْأَلُكُمْ عَلَيْهِ مِنْ أَجْرٍ إِنْ أَجْرِيَ إِلَّا عَلَىٰ رَبِّ الْعَالَمِينَ
          </div>
          <h2 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-[var(--ink)] pt-1">
            {isAr ? (
              'في سبيل الله سبحانه وتعالى وحده'
            ) : (
              <>
                For the Sake of Allah <bdi dir="rtl" className="font-ui-ar">(سبحانه وتعالى)</bdi> Alone
              </>
            )}
          </h2>
        </div>

        {/* 3 Core Principles */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-5 mb-10">

          <div className="ql-raised p-6 space-y-2">
            <h3 className="text-sm font-bold text-[var(--ink)]">
              {isAr ? '1. مجاني 100% لجميع المسلمين' : '1. 100% Free for All Users'}
            </h3>
            <p className="text-xs text-[var(--ink-muted)] leading-[1.6]">
              {isAr
                ? 'استخدام هذا المحرك متاح ومفتوح للتطبيقات والخدمات المجانية تمامًا لجميع المسلمين دون أي مقابل مالي، خالصاً في سبيل الله سبحانه وتعالى.'
                : 'This engine and its algorithms are dedicated to be used exclusively in applications that remain 100% free of charge to all end users.'}
            </p>
          </div>

          <div className="ql-raised p-6 space-y-2">
            <h3 className="text-sm font-bold text-[var(--ink)]">
              {isAr ? '2. حظر تام للتربح أو الإعلانات' : '2. Strict Non-Commercialization'}
            </h3>
            <p className="text-xs text-[var(--ink-muted)] leading-[1.6]">
              {isAr ? (
                'يحظر منعًا باتًا بيع التطبيق أو وضعه خلف اشتراكات مدفوعة أو إعلانات ربحية أو استخراج أي عائد مالي منه بأي شكل، فهو في سبيل الله سبحانه وتعالى.'
              ) : (
                <>
                  Strictly prohibited from being monetized, placed behind subscriptions, paywalls, or in-app ads. It is entirely for the sake of Allah{' '}
                  <bdi dir="rtl" className="font-ui-ar">
                    (سبحانه وتعالى)
                  </bdi>
                  .
                </>
              )}
            </p>
          </div>

          <div className="ql-raised p-6 space-y-2">
            <h3 className="text-sm font-bold text-[var(--ink)]">
              {isAr ? '3. وسيلة مساعدة للتعلم' : '3. Educational Practice Aid'}
            </h3>
            <p className="text-xs text-[var(--ink-muted)] leading-[1.6]">
              {isAr
                ? 'هذا المحرك أداة تقنية مساعدة للمراجعة وتثبيت الحفظ، ولا يغني عن التلقي والمشافهة أمام المشايخ والمعلمين المتقنين.'
                : 'An algorithmic revision assistant for personal practice and self-testing. It does not replace direct recitation before qualified teachers.'}
            </p>
          </div>

        </div>

        {/* Minimal Acknowledgments without external links */}
        <div className="ql-raised p-5 text-center max-w-2xl mx-auto space-y-1">
          <p className="text-sm font-semibold text-[var(--ink)] leading-relaxed">
            {isAr
              ? 'الحمد لله الشكر لله تعالى'
              : 'Alhamdulillah — Praise and gratitude belong to Allah Almighty alone'}
          </p>
          <div className="font-ui-ar text-xs text-[var(--ink-muted)] pt-1">
            هذا من فضل ربي — ربنا تقبل منا إنك أنت السميع العليم
          </div>
        </div>

      </div>
    </section>
  );
};

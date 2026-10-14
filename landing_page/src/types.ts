export type ThemeMode = 'dark' | 'light';
export type LangMode = 'en' | 'ar';

export interface QuranWord {
  id: number;
  surah: number;
  ayah: number;
  arabic: string;
  transliteration: string;
  translation: string;
  phonemes: string;
  tajweedRule?: string;
  status: 'pending' | 'matched' | 'tajweed-slip' | 'skipped';
  isGreen?: boolean;
  isYellow?: boolean;
  isRed?: boolean;
  errorDetail?: string;
}

export interface AppScreenshot {
  id: string;
  title: string;
  titleAr: string;
  tagline: string;
  taglineAr: string;
  image: string;
  featureKey: string;
  highlights: string[];
  highlightsAr: string[];
}

export interface SdkDocTab {
  id: string;
  label: string;
  labelAr: string;
  description: string;
  descriptionAr: string;
}

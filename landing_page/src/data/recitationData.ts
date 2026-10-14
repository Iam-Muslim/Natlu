import { QuranWord, AppScreenshot } from '../types';

export const FATIHA_WORDS: QuranWord[] = [
  // Ayah 1
  { id: 1, surah: 1, ayah: 1, arabic: 'بِسْمِ', transliteration: 'Bismi', translation: 'In the name', phonemes: 'b-i-s-m-i', status: 'pending' },
  { id: 2, surah: 1, ayah: 1, arabic: 'اللَّهِ', transliteration: 'Allahi', translation: 'of Allah', phonemes: 'l-l-a-h-i', tajweedRule: 'Tarqeeq (Thin Lam)', status: 'pending' },
  { id: 3, surah: 1, ayah: 1, arabic: 'الرَّحْمَٰنِ', transliteration: 'Ar-Rahmani', translation: 'the Entirely Merciful', phonemes: 'r-r-a-h-m-a-a-n-i', tajweedRule: 'Madd Asli (2 Harakat)', status: 'pending' },
  { id: 4, surah: 1, ayah: 1, arabic: 'الرَّحِيمِ', transliteration: 'Ar-Raheem', translation: 'the Especially Merciful', phonemes: 'r-r-a-h-ee-m', tajweedRule: 'Madd Arid Li-Sukoon (2-6 Harakat)', status: 'pending' },
  // Ayah 2
  { id: 5, surah: 1, ayah: 2, arabic: 'الْحَمْدُ', transliteration: 'Al-hamdu', translation: '[All] praise is', phonemes: 'a-l-h-a-m-d-u', tajweedRule: 'Idhar Qamari', status: 'pending' },
  { id: 6, surah: 1, ayah: 2, arabic: 'لِلَّهِ', transliteration: 'Lillahi', translation: 'due to Allah', phonemes: 'l-i-l-l-a-h-i', status: 'pending' },
  { id: 7, surah: 1, ayah: 2, arabic: 'رَبِّ', transliteration: 'Rabbi', translation: 'Lord', phonemes: 'r-a-b-b-i', tajweedRule: 'Tafkheem Ra', status: 'pending' },
  { id: 8, surah: 1, ayah: 2, arabic: 'الْعَالَمِينَ', transliteration: 'Al-\'Alameen', translation: 'of the worlds', phonemes: 'a-l-aa-l-a-m-ee-n', tajweedRule: 'Madd Arid Li-Sukoon', status: 'pending' },
  // Ayah 3
  { id: 9, surah: 1, ayah: 3, arabic: 'الرَّحْمَٰنِ', transliteration: 'Ar-Rahmani', translation: 'The Entirely Merciful', phonemes: 'r-r-a-h-m-a-a-n-i', status: 'pending' },
  { id: 10, surah: 1, ayah: 3, arabic: 'الرَّحِيمِ', transliteration: 'Ar-Raheem', translation: 'The Especially Merciful', phonemes: 'r-r-a-h-ee-m', status: 'pending' },
  // Ayah 4
  { id: 11, surah: 1, ayah: 4, arabic: 'مَالِكِ', transliteration: 'Maliki', translation: 'Sovereign', phonemes: 'm-aa-l-i-k-i', tajweedRule: 'Madd Asli', status: 'pending' },
  { id: 12, surah: 1, ayah: 4, arabic: 'يَوْمِ', transliteration: 'Yawmi', translation: 'of the Day', phonemes: 'y-a-w-m-i', tajweedRule: 'Harf Leen', status: 'pending' },
  { id: 13, surah: 1, ayah: 4, arabic: 'الدِّينِ', transliteration: 'Ad-Deen', translation: 'of Recompense', phonemes: 'd-d-ee-n', status: 'pending' },
  // Ayah 5
  { id: 14, surah: 1, ayah: 5, arabic: 'إِيَّاكَ', transliteration: 'Iyyaka', translation: 'It is You', phonemes: 'i-y-y-aa-k-a', tajweedRule: 'Shaddah Ya', status: 'pending' },
  { id: 15, surah: 1, ayah: 5, arabic: 'نَعْبُدُ', transliteration: 'Na\'budu', translation: 'we worship', phonemes: 'n-a-\'-b-u-d-u', tajweedRule: 'Ayn Articulation', status: 'pending' },
  { id: 16, surah: 1, ayah: 5, arabic: 'وَإِيَّاكَ', transliteration: 'Wa-iyyaka', translation: 'and You', phonemes: 'w-a-i-y-y-aa-k-a', status: 'pending' },
  { id: 17, surah: 1, ayah: 5, arabic: 'نَسْتَعِينُ', transliteration: 'Nasta\'een', translation: 'we ask for help', phonemes: 'n-a-s-t-a-\'-ee-n', tajweedRule: 'Madd Arid Li-Sukoon', status: 'pending' },
  // Ayah 6
  { id: 18, surah: 1, ayah: 6, arabic: 'اهْدِنَا', transliteration: 'Ihdina', translation: 'Guide us to', phonemes: 'i-h-d-i-n-aa', tajweedRule: 'Hams on Ha', status: 'pending' },
  { id: 19, surah: 1, ayah: 6, arabic: 'الصِّرَاطَ', transliteration: 'As-Sirata', translation: 'the straight path', phonemes: 's-s-i-r-aa-t-a', tajweedRule: 'Itbaq Sad & Ta', status: 'pending' },
  { id: 20, surah: 1, ayah: 6, arabic: 'الْمُسْتَقِيمَ', transliteration: 'Al-Mustaqeem', translation: 'the straight', phonemes: 'a-l-m-u-s-t-a-q-ee-m', tajweedRule: 'Qaf Isti\'la', status: 'pending' },
  // Ayah 7
  { id: 21, surah: 1, ayah: 7, arabic: 'صِرَاطَ', transliteration: 'Sirata', translation: 'The path of', phonemes: 's-i-r-aa-t-a', status: 'pending' },
  { id: 22, surah: 1, ayah: 7, arabic: 'الَّذِينَ', transliteration: 'Alladheena', translation: 'those upon whom', phonemes: 'a-l-l-a-dh-ee-n-a', status: 'pending' },
  { id: 23, surah: 1, ayah: 7, arabic: 'أَنْعَمْتَ', transliteration: 'An\'amta', translation: 'You have bestowed favor', phonemes: 'a-n-\'-a-m-t-a', tajweedRule: 'Idhar Halqi (Nun before Ayn)', status: 'pending' },
  { id: 24, surah: 1, ayah: 7, arabic: 'عَلَيْهِمْ', transliteration: '\'Alayhim', translation: 'upon them', phonemes: '\'-a-l-a-y-h-i-m', status: 'pending' },
  { id: 25, surah: 1, ayah: 7, arabic: 'غَيْرِ', transliteration: 'Ghayril', translation: 'not of those who', phonemes: 'gh-a-y-r-i', tajweedRule: 'Ghayn Isti\'la', status: 'pending' },
  { id: 26, surah: 1, ayah: 7, arabic: 'الْمَغْضُوبِ', transliteration: 'Al-Maghdoobi', translation: 'evoked [Your] anger', phonemes: 'a-l-m-a-gh-d-oo-b-i', tajweedRule: 'Dhad Istitala', status: 'pending' },
  { id: 27, surah: 1, ayah: 7, arabic: 'عَلَيْهِمْ', transliteration: '\'Alayhim', translation: 'or of those', phonemes: '\'-a-l-a-y-h-i-m', status: 'pending' },
  { id: 28, surah: 1, ayah: 7, arabic: 'وَلَا', transliteration: 'Wa-la', translation: 'who are', phonemes: 'w-a-l-aa', status: 'pending' },
  { id: 29, surah: 1, ayah: 7, arabic: 'الضَّالِّينَ', transliteration: 'Ad-Daaalleen', translation: 'astray', phonemes: 'd-d-aa-l-l-ee-n', tajweedRule: 'Madd Lazim Kalimi Muthaqqal (6 Harakat)', status: 'pending' }
];

export const APP_SCREENSHOTS: AppScreenshot[] = [
  {
    id: 'fatiha',
    title: 'Real-Time Word Tracking',
    titleAr: 'تتبع الكلمات المباشر أثناء التلاوة',
    tagline: 'Instant green/yellow/red highlight as you recite',
    taglineAr: 'تمييز فوري للكلمات بالألوان مع صوتك: الأخضر للإتقان، والأصفر للتنبيه، والأحمر للخطأ',
    image: './screenshots/1.png?v=2',
    featureKey: 'Word Tracking & ASR',
    highlights: [
      'Zero-latency acoustic phoneme alignment via Zipformer ONNX',
      'Instant color transitions for correct, slip, or skipped words',
      'Auto-scrolls page cleanly as your recitation progresses'
    ],
    highlightsAr: [
      'محاذاة صوتية فورية على مستوى الفونيم عبر نموذج Zipformer محلياً دون أي خادم',
      'تحول لوني تلقائي للكلمة فور نطقها: صحيح، أو ملاحظة تجويدية، أو كلمة متروكة',
      'تقليب وتمرير تلقائي للصفحات بسلاسة تامة مع تقدم تلاوتك'
    ]
  },
  {
    id: 'qamar',
    title: '15-Line Madani Mus\'haf Layout',
    titleAr: 'مصحف المدينة المنورة 15 سطرًا',
    tagline: 'Faithful typography matching printed King Fahd Mus\'haf',
    taglineAr: 'رسم عثماني مطابق لمصحف مجمع الملك فهد لراحة العين والقراءة المطولة',
    image: './screenshots/2.png?v=2',
    featureKey: 'Mus\'haf Layout Engine',
    highlights: [
      'Pixel-perfect 15-line verse justification with ligature support',
      'Warm parchment night palette tuned specifically for eye comfort',
      'Custom ayah markers, surah title banners, and sajdah indicators'
    ],
    highlightsAr: [
      'ضبط دقيق لأسطر المصحف (15 سطرًا بالصفحة) مع دعم كامل للرسم العثماني',
      'درجات ألوان دافئة مريحة للعين مخصصة للقراءة الليلية دون إجهاد',
      'فواصل الآيات، وترويسات السور، وعلامات السجدات والأجزاء الأصلية'
    ]
  },
  {
    id: 'search',
    title: '"Recite to Navigate" Voice Search',
    titleAr: 'البحث الصوتي المباشر بالتلاوة',
    tagline: 'Speak any ayah segment to instantly jump to page & surah',
    taglineAr: 'اتلُ أي مقطع من أي سورة للانتقال المباشر لصفحتها وموضعها في المصحف',
    image: './screenshots/3.png?v=2',
    featureKey: 'Myers Bit-Parallel Search',
    highlights: [
      '6,236 Ayah instant lookup within 15 milliseconds',
      'Myers bit-parallel approximate string matching engine',
      'Resilient to dialectal pronunciation variations and minor slips'
    ],
    highlightsAr: [
      'استدعاء فوري لجميع آيات القرآن العظيم (6,236 آية) في أقل من 15 مللي ثانية',
      'خوارزمية مايرز (Myers) للمطابقة الصوتية التقريبية فائقة السرعة',
      'مرونة عالية مع اختلاف اللهجات وأخطاء التشكيل العارضة والضوضاء'
    ]
  },
  {
    id: 'tajweed',
    title: 'Acoustic Tajweed Checking & Verification',
    titleAr: 'فحص وتدقيق أحكام التجويد الصوتي',
    tagline: 'Real-time acoustic analysis of Madd timing, Ghunnah, and Shaddah',
    taglineAr: 'تحليل صوتي فوري لأزمنة المدود والغنن والشدات مع لوحة إرشادية لتصحيح التلاوة',
    image: './screenshots/4.png?v=2',
    featureKey: 'Acoustic Tajweed Matrix',
    highlights: [
      'Millisecond vowel duration grading (2, 4, 6 Harakat) calibrated against reciter Tadweer tempo',
      'Acoustic envelope detection for Ghunnah, Ikhfa, Qalqalah, and Shaddah hold pressure',
      'Interactive Tajweed sheet distinguishing Lahun Khafi from Lahun Jali with corrective Sheikh audio replay'
    ],
    highlightsAr: [
      'قياس صوتي دقيق لأزمنة المدود (حركتان، 4، 6 حركات) بالمللي ثانية وفق سرعة تدوير القارئ',
      'فحص صوتي لأزمنة الغنة والإخفاء مع التحقق من نبر الشدة وضغط الحروف المشددة والقلقلة',
      'لوحة تفاعلية فورية تميز اللحن الخفي عن اللحن الجلي مع نصائح تصحيح واستماع مرجعي للشيخ الحصري'
    ]
  }
];

export const RAWIS_DATA = [
  { imam: 'Nafi\' (المدينة)', rawis: ['Qalun (قالون)', 'Warsh (ورش)'], popularIn: 'North & West Africa' },
  { imam: 'Ibn Kathir (مكة)', rawis: ['Al-Bazzi (البزي)', 'Qunbul (قنبل)'], popularIn: 'Hijaz' },
  { imam: 'Abu Amr (البصرة)', rawis: ['Al-Duri (الدوري)', 'Al-Susi (السوسي)'], popularIn: 'Sudan & East Africa' },
  { imam: 'Ibn Amir (الشام)', rawis: ['Hisham (هشام)', 'Ibn Dhakwan (ابن ذكوان)'], popularIn: 'Levant' },
  { imam: 'Asim (الكوفة)', rawis: ['Shu\'bah (شعبة)', 'Hafs (حفص)'], popularIn: 'Global Standard (Hafs)' },
  { imam: 'Hamzah (الكوفة)', rawis: ['Khalaf (خلف)', 'Khallad (خلاد)'], popularIn: 'Specialized Academies' },
  { imam: 'Al-Kisa\'i (الكوفة)', rawis: ['Abu al-Harith (أبو الحارث)', 'Al-Duri (الدوري)'], popularIn: 'Classical Halqat' }
];

export const COUNTING_SCHOOLS = [
  { name: 'Kufi (الكوفي)', count: '6,236', description: 'Global Hafs Standard' },
  { name: 'Madani I & II (المدني)', count: '6,214 / 6,217', description: 'Warsh & Qalun' },
  { name: 'Basri (البصري)', count: '6,204', description: 'Abu Amr & Al-Duri' },
  { name: 'Makki (المكي)', count: '6,219', description: 'Ibn Kathir' },
  { name: 'Dimashqi (الدمشقي)', count: '6,226', description: 'Ibn Amir' },
  { name: 'Homsi (الحمصي)', count: '6,232', description: 'Levantine Tradition' }
];

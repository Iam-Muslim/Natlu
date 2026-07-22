import Foundation

enum L10n {
    static func text(_ key: Key, language: AppLanguage) -> String { language == .ar ? key.ar : key.en }
    enum Key {
        case record, listening, errorDetails, settings, chooseSurah, searchSurah
        case read, hide, tajweed, stop, language, theme, fontSize, scrollSpeed
        case light, dark, voiceSearch, loading, noMatch, microphonePermission, done, cancel
        case voiceSearchInstruction, voiceSearchSafety, keepReciting, exactMatchPending
        case ambiguousAyah, confirmingAyah, exactAyahFound
        var ar: String {
            switch self {
            case .record: "تسجيل"; case .listening: "جاري الاستماع…"; case .errorDetails: "تفاصيل الأخطاء"
            case .settings: "الإعدادات"; case .chooseSurah: "اختر السورة"; case .searchSurah: "ابحث عن سورة"
            case .read: "قراءة"; case .hide: "إخفاء"; case .tajweed: "تجويد"; case .stop: "إيقاف"
            case .language: "اللغة"; case .theme: "المظهر"; case .fontSize: "حجم الخط"
            case .scrollSpeed: "سرعة التمرير"; case .light: "أبيض"; case .dark: "أسود"
            case .voiceSearch: "البحث بالصوت"; case .loading: "جاري تجهيز المصحف…"
            case .noMatch: "لم يتم العثور على آية"; case .microphonePermission: "يرجى السماح باستخدام الميكروفون"
            case .done: "تم"; case .cancel: "إلغاء"
            case .voiceSearchInstruction: "اقرأ جزءًا من أي آية"
            case .voiceSearchSafety: "نسمح بأخطاء النموذج، ولن ننتقل حتى تتأكد الآية الفريدة مرتين."
            case .keepReciting: "واصل التلاوة حتى يصبح التطابق فريدًا."
            case .exactMatchPending: "لا يوجد تطابق موثوق حتى الآن. واصل التلاوة بشكل طبيعي."
            case .ambiguousAyah: "هذا المقطع موجود في أكثر من آية. واصل التلاوة."
            case .confirmingAyah: "وجدنا آية محتملة. واصل التلاوة قليلًا للتأكيد."
            case .exactAyahFound: "تم تأكيد الآية. جارٍ الانتقال…"
            }
        }
        var en: String {
            switch self {
            case .record: "Record"; case .listening: "Listening…"; case .errorDetails: "Error Details"
            case .settings: "Settings"; case .chooseSurah: "Choose Surah"; case .searchSurah: "Search surah"
            case .read: "Read"; case .hide: "Hide"; case .tajweed: "Tajweed"; case .stop: "Stop"
            case .language: "Language"; case .theme: "Theme"; case .fontSize: "Font Size"
            case .scrollSpeed: "Scroll Speed"; case .light: "Light"; case .dark: "Dark"
            case .voiceSearch: "Voice Search"; case .loading: "Preparing the Quran…"
            case .noMatch: "No ayah found"; case .microphonePermission: "Please allow microphone access"
            case .done: "Done"; case .cancel: "Cancel"
            case .voiceSearchInstruction: "Recite any part of an ayah"
            case .voiceSearchSafety: "Model errors are allowed. A unique ayah must be confirmed twice before opening."
            case .keepReciting: "Keep reciting until the match becomes unique."
            case .exactMatchPending: "No confident match yet. Continue reciting normally."
            case .ambiguousAyah: "This passage occurs in more than one ayah. Keep reciting."
            case .confirmingAyah: "Possible ayah found. Keep reciting briefly to confirm it."
            case .exactAyahFound: "Ayah confirmed. Opening it…"
            }
        }
    }
}

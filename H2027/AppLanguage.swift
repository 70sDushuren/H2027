import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en-GB"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case traditionalCantonese = "yue-Hant"
    case portuguese = "pt-PT"

    var id: Self { self }
    var locale: Locale { Locale(identifier: rawValue) }

    var nativeTitle: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .traditionalCantonese: "繁體粵語"
        case .portuguese: "Português"
        }
    }
}

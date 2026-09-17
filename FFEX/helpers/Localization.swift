import Foundation
import SwiftUI

// MARK: - Languages

enum FFLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "ffex.language"

    case english    = "en"
    case indonesian = "id"
    case vietnamese = "vi"
    case portuguese = "pt-BR"
    case moroccan   = "ar-MA"
    case arabic     = "ar"
    case taiwanese  = "zh-TW"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:    return "English"
        case .indonesian: return "Indonesia"
        case .vietnamese: return "Tiếng Việt"
        case .portuguese: return "Português (BR)"
        case .moroccan:   return "Darija (المغرب)"
        case .arabic:     return "العربية"
        case .taiwanese:  return "繁體中文"
        }
    }

    var isRTL: Bool { self == .arabic || self == .moroccan }

    func t(_ key: String) -> String { strings[key] ?? key }

    // MARK: - String tables

    private var strings: [String: String] {
        switch self {

        case .english: return [
            "select_language":       "Select Language",
            "continue":              "Continue",
            "app_name":              "FFEX",
            "key_placeholder":       "FFEX-XXXX-XXXXX",
            "validate":              "VALIDATE",
            "validating":            "Validating...",
            "key_invalid":           "Invalid or expired key",
            "logout":                "Logout",
            "logout_confirm_title":  "Logout",
            "logout_confirm_msg":    "You will need to enter your key again.",
            "logout_confirm_yes":    "Logout",
            "logout_confirm_cancel": "Cancel",
            "device":                "Device",
            "ios_version":           "iOS",
            "expires":               "Expires In",
            "verified":              "VERIFIED",
            "status_online":         "STATUS : ONLINE",
            "status_offline":        "STATUS : OFFLINE",
            "inject":                "INJECT",
            "unavailable":           "UNAVAILABLE",
            "injecting":             "Injecting...",
            "inject_success":        "Injection complete. Launching game.",
            "inject_failed":         "Injection failed.",
            "telegram":              "t.me/ffexternal",
            "supported":             "Supported",
            "not_supported":         "Not supported on this iOS version",
            "game_ff":               "Free Fire",
            "game_ffmax":            "Free Fire MAX",
            "checking":              "Checking...",
        ]

        case .indonesian: return [
            "select_language":       "Pilih Bahasa",
            "continue":              "Lanjut",
            "app_name":              "FFEX",
            "key_placeholder":       "FFEX-XXXX-XXXXX",
            "validate":              "VALIDASI",
            "validating":            "Memvalidasi...",
            "key_invalid":           "Kunci tidak valid atau sudah kedaluwarsa",
            "logout":                "Keluar",
            "logout_confirm_title":  "Keluar",
            "logout_confirm_msg":    "Anda perlu memasukkan kunci lagi.",
            "logout_confirm_yes":    "Keluar",
            "logout_confirm_cancel": "Batal",
            "device":                "Perangkat",
            "ios_version":           "iOS",
            "expires":               "Berakhir Dalam",
            "verified":              "TERVERIFIKASI",
            "status_online":         "STATUS : ONLINE",
            "status_offline":        "STATUS : OFFLINE",
            "inject":                "INJECT",
            "unavailable":           "TIDAK TERSEDIA",
            "injecting":             "Menginjeksi...",
            "inject_success":        "Injeksi selesai. Membuka game.",
            "inject_failed":         "Injeksi gagal.",
            "telegram":              "t.me/ffexternal",
            "supported":             "Didukung",
            "not_supported":         "Versi iOS ini tidak didukung",
            "game_ff":               "Free Fire",
            "game_ffmax":            "Free Fire MAX",
            "checking":              "Memeriksa...",
        ]

        case .vietnamese: return [
            "select_language":       "Chọn ngôn ngữ",
            "continue":              "Tiếp tục",
            "app_name":              "FFEX",
            "key_placeholder":       "FFEX-XXXX-XXXXX",
            "validate":              "XÁC NHẬN",
            "validating":            "Đang xác nhận...",
            "key_invalid":           "Khóa không hợp lệ hoặc đã hết hạn",
            "logout":                "Đăng xuất",
            "logout_confirm_title":  "Đăng xuất",
            "logout_confirm_msg":    "Bạn sẽ cần nhập lại khóa của mình.",
            "logout_confirm_yes":    "Đăng xuất",
            "logout_confirm_cancel": "Hủy",
            "device":                "Thiết bị",
            "ios_version":           "iOS",
            "expires":               "Hết hạn trong",
            "verified":              "ĐÃ XÁC NHẬN",
            "status_online":         "TRẠNG THÁI : ONLINE",
            "status_offline":        "TRẠNG THÁI : OFFLINE",
            "inject":                "TIÊM",
            "unavailable":           "KHÔNG KHẢ DỤNG",
            "injecting":             "Đang tiêm...",
            "inject_success":        "Tiêm xong. Đang khởi động game.",
            "inject_failed":         "Tiêm thất bại.",
            "telegram":              "t.me/ffexternal",
            "supported":             "Được hỗ trợ",
            "not_supported":         "Phiên bản iOS này không được hỗ trợ",
            "game_ff":               "Free Fire",
            "game_ffmax":            "Free Fire MAX",
            "checking":              "Đang kiểm tra...",
        ]

        case .portuguese: return [
            "select_language":       "Selecionar idioma",
            "continue":              "Continuar",
            "app_name":              "FFEX",
            "key_placeholder":       "FFEX-XXXX-XXXXX",
            "validate":              "VALIDAR",
            "validating":            "Validando...",
            "key_invalid":           "Chave inválida ou expirada",
            "logout":                "Sair",
            "logout_confirm_title":  "Sair",
            "logout_confirm_msg":    "Você precisará inserir sua chave novamente.",
            "logout_confirm_yes":    "Sair",
            "logout_confirm_cancel": "Cancelar",
            "device":                "Dispositivo",
            "ios_version":           "iOS",
            "expires":               "Expira Em",
            "verified":              "VERIFICADO",
            "status_online":         "STATUS : ONLINE",
            "status_offline":        "STATUS : OFFLINE",
            "inject":                "INJETAR",
            "unavailable":           "INDISPONÍVEL",
            "injecting":             "Injetando...",
            "inject_success":        "Injeção completa. Iniciando jogo.",
            "inject_failed":         "Falha na injeção.",
            "telegram":              "t.me/ffexternal",
            "supported":             "Suportado",
            "not_supported":         "Esta versão do iOS não é suportada",
            "game_ff":               "Free Fire",
            "game_ffmax":            "Free Fire MAX",
            "checking":              "Verificando...",
        ]

        case .moroccan: return [
            "select_language":       "اختيار اللغة",
            "continue":              "متابعة",
            "app_name":              "FFEX",
            "key_placeholder":       "FFEX-XXXX-XXXXX",
            "validate":              "تحقق",
            "validating":            "جاري التحقق...",
            "key_invalid":           "المفتاح غير صالح أو منتهي",
            "logout":                "تسجيل خروج",
            "logout_confirm_title":  "تسجيل خروج",
            "logout_confirm_msg":    "ستحتاج إلى إدخال مفتاحك مرة أخرى.",
            "logout_confirm_yes":    "خروج",
            "logout_confirm_cancel": "إلغاء",
            "device":                "الجهاز",
            "ios_version":           "iOS",
            "expires":               "ينتهي خلال",
            "verified":              "تم التحقق",
            "status_online":         "الحالة : متصل",
            "status_offline":        "الحالة : غير متصل",
            "inject":                "حقن",
            "unavailable":           "غير متاح",
            "injecting":             "جاري الحقن...",
            "inject_success":        "اكتمل الحقن. جاري تشغيل اللعبة.",
            "inject_failed":         "فشل الحقن.",
            "telegram":              "t.me/ffexternal",
            "supported":             "مدعوم",
            "not_supported":         "إصدار iOS هذا غير مدعوم",
            "game_ff":               "فري فاير",
            "game_ffmax":            "فري فاير MAX",
            "checking":              "جاري الفحص...",
        ]

        case .arabic: return [
            "select_language":       "اختر اللغة",
            "continue":              "متابعة",
            "app_name":              "FFEX",
            "key_placeholder":       "FFEX-XXXX-XXXXX",
            "validate":              "تحقق",
            "validating":            "جاري التحقق...",
            "key_invalid":           "المفتاح غير صالح أو منتهي الصلاحية",
            "logout":                "تسجيل خروج",
            "logout_confirm_title":  "تسجيل خروج",
            "logout_confirm_msg":    "ستحتاج إلى إدخال مفتاحك مرة أخرى.",
            "logout_confirm_yes":    "خروج",
            "logout_confirm_cancel": "إلغاء",
            "device":                "الجهاز",
            "ios_version":           "iOS",
            "expires":               "ينتهي خلال",
            "verified":              "تم التحقق",
            "status_online":         "الحالة : متصل",
            "status_offline":        "الحالة : غير متصل",
            "inject":                "حقن",
            "unavailable":           "غير متاح",
            "injecting":             "جاري الحقن...",
            "inject_success":        "اكتمل الحقن. جاري تشغيل اللعبة.",
            "inject_failed":         "فشل الحقن.",
            "telegram":              "t.me/ffexternal",
            "supported":             "مدعوم",
            "not_supported":         "إصدار iOS هذا غير مدعوم",
            "game_ff":               "فري فاير",
            "game_ffmax":            "فري فاير MAX",
            "checking":              "جاري الفحص...",
        ]

        case .taiwanese: return [
            "select_language":       "選擇語言",
            "continue":              "繼續",
            "app_name":              "FFEX",
            "key_placeholder":       "FFEX-XXXX-XXXXX",
            "validate":              "驗證",
            "validating":            "驗證中...",
            "key_invalid":           "密鑰無效或已過期",
            "logout":                "登出",
            "logout_confirm_title":  "登出",
            "logout_confirm_msg":    "您需要重新輸入密鑰。",
            "logout_confirm_yes":    "登出",
            "logout_confirm_cancel": "取消",
            "device":                "裝置",
            "ios_version":           "iOS",
            "expires":               "到期時間",
            "verified":              "已驗證",
            "status_online":         "狀態：在線",
            "status_offline":        "狀態：離線",
            "inject":                "注入",
            "unavailable":           "不可用",
            "injecting":             "注入中...",
            "inject_success":        "注入完成。正在啟動遊戲。",
            "inject_failed":         "注入失敗。",
            "telegram":              "t.me/ffexternal",
            "supported":             "已支援",
            "not_supported":         "此 iOS 版本不受支援",
            "game_ff":               "Free Fire",
            "game_ffmax":            "Free Fire MAX",
            "checking":              "檢查中...",
        ]
        }
    }
}

// MARK: - LanguageStore

final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()
    @Published var current: FFLanguage = .english

    init() {
        if let raw = UserDefaults.standard.string(forKey: FFLanguage.storageKey),
           let lang = FFLanguage(rawValue: raw) {
            current = lang
        }
    }

    func select(_ lang: FFLanguage) {
        current = lang
        UserDefaults.standard.set(lang.rawValue, forKey: FFLanguage.storageKey)
    }

    func t(_ key: String) -> String { current.t(key) }
}

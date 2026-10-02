import SwiftUI
import UIKit

// Barvy vychází z bauhaus.cz (#CC0000, #333333, #008740), stejné jako webová verze.
extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let ponkRed = Color(light: 0xCC0000, dark: 0xF2433A)
    static let ponkRedDeep = Color(light: 0xA50C16, dark: 0xFF6A5E)
    static let ponkGreen = Color(light: 0x008740, dark: 0x3CC27A)
    static let ponkPage = Color(light: 0xECEDEE, dark: 0x161718)
    static let ponkSurface = Color(light: 0xFFFFFF, dark: 0x202123)
    static let ponkSurface2 = Color(light: 0xF5F5F6, dark: 0x2A2B2E)
    static let ponkInk = Color(light: 0x262626, dark: 0xF0F0F1)
    static let ponkMuted = Color(light: 0x6B6D70, dark: 0xA2A4A8)
    static let ponkLine = Color(light: 0xD8D9DB, dark: 0x36383B)
    static let ponkShelf = Color(light: 0xD8D9DB, dark: 0x2E3033)
    static let ponkLabel = Color(light: 0x262626, dark: 0xF0F0F1)
    static let ponkLabelInk = Color(light: 0xFFFFFF, dark: 0x161718)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// --- písmo -----------------------------------------------------------------

enum PonkFont: String, CaseIterable, Identifiable {
    case barlow, sofia, encode, fira, saira

    var id: String { rawValue }

    var postScriptBase: String {
        switch self {
        case .barlow: return "BarlowSemiCondensed"
        case .sofia: return "SofiaSansSemiCondensed"
        case .encode: return "EncodeSansSemiCondensed"
        case .fira: return "FiraSansCondensed"
        case .saira: return "SairaSemiCondensed"
        }
    }

    var displayName: String {
        switch self {
        case .barlow: return "Barlow Semi Condensed"
        case .sofia: return "Sofia Sans Semi Condensed"
        case .encode: return "Encode Sans Semi Condensed"
        case .fira: return "Fira Sans Condensed"
        case .saira: return "Saira Semi Condensed"
        }
    }

    static var current: PonkFont {
        PonkFont(rawValue: UserDefaults.standard.string(forKey: "font") ?? "") ?? .barlow
    }
}

enum PonkWeight {
    case regular, semibold, heavy

    var suffix: String {
        switch self {
        case .regular: return "Regular"
        case .semibold: return "SemiBold"
        case .heavy: return "ExtraBold"
        }
    }
}

extension Font {
    /// Písmo aplikace; roste s nastavenou velikostí textu v iOS (Dynamic Type).
    static func ponk(_ size: CGFloat, _ weight: PonkWeight = .regular,
                     relativeTo style: Font.TextStyle = .body, font: PonkFont = .current) -> Font {
        .custom("\(font.postScriptBase)-\(weight.suffix)", size: size, relativeTo: style)
    }
}

// --- formátování -----------------------------------------------------------

enum Fmt {
    static let money: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static let money2: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "cs_CZ")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let isoDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()
}

func money(_ v: Double?) -> String {
    guard let v else { return "–" }
    return Fmt.money.string(from: NSNumber(value: v.rounded())) ?? String(Int(v))
}

func money2(_ v: Double) -> String { Fmt.money2.string(from: NSNumber(value: v)) ?? String(v) }

func dayDate(_ iso: String?) -> Date? {
    guard let iso else { return nil }
    return Fmt.isoDay.date(from: String(iso.prefix(10)))
}

/// "2. 10."
func shortDay(_ iso: String?) -> String {
    guard let d = dayDate(iso) else { return "" }
    let c = Calendar.current.dateComponents([.day, .month], from: d)
    return "\(c.day ?? 0). \(c.month ?? 0)."
}

/// "2. 10. 6:05"
func shortDayTime(_ iso: String?) -> String {
    guard let iso, let d = Fmt.isoDateTime.date(from: String(iso.prefix(19))) else { return "zatím nikdy" }
    return d.formatted(.dateTime.day().month(.defaultDigits).hour().minute().locale(Locale(identifier: "cs_CZ")))
}

func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    n == 1 ? one : (2...4).contains(n) ? few : many
}

func productImageURL(_ path: String?, w: Int = 300, h: Int = 372) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    return URL(string: "https://www.bauhaus.cz/img/\(w)/\(h)/resize/catalog/product\(path)")
}

/// Popis z Bauhausu je HTML – pro aplikaci stačí čistý text s odstavci.
func plainText(fromHTML html: String) -> String {
    var s = html
    for tag in ["</p>", "<br>", "<br/>", "<br />", "</li>", "</h3>", "</h4>"] {
        s = s.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
    }
    s = s.replacingOccurrences(of: "<li>", with: "• ", options: .caseInsensitive)
    s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    let entities = ["&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&lt;": "<", "&gt;": ">"]
    for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
    s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

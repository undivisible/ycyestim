import SwiftUI

// MARK: - Color from Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Date Extensions

extension Date {
    static var now: Date { Date() }
}

// MARK: - View: Glass Background Effect (iOS 26+ forward compatibility)

extension View {
    /// Apply glass background effect with fallback for older iOS versions
    func glassBackgroundEffectCompat(displayStyle: GlassDisplayStyle = .automatic) -> some View {
        if #available(iOS 26.0, *) {
            return AnyView(self.glassBackgroundEffect(displayStyle: displayStyle))
        } else {
            return AnyView(self.background(.ultraThinMaterial))
        }
    }
}

enum GlassDisplayStyle {
    case automatic
    case prominent
    case secondary
}

// MARK: - Double Extensions

extension Double {
    func rounded(to places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

// MARK: - String Extensions

extension String {
    var isValidConnectCode: Bool {
        let parts = trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
    }
}

// MARK: - Int Extensions

extension Int {
    var formattedDuration: String {
        let min = self / 60
        let sec = self % 60
        return String(format: "%02d:%02d", min, sec)
    }
}

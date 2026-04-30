import SwiftUI

enum AURAVisualStyle {
    enum Colors {
        static let background = Color(hex: "#0E1110")
        static let surface1 = Color(hex: "#151817")
        static let surface2 = Color(hex: "#1D2120")
        static let surface3 = Color(hex: "#272C2A")
        static let border = Color(hex: "#343A37")
        static let textPrimary = Color(hex: "#EEF2F0")
        static let textSecondary = Color(hex: "#A9B3AF")
        static let textTertiary = Color(hex: "#68726E")
        static let accent = Color(hex: "#4F8CFF")
        static let accentHover = Color(hex: "#3676EF")
        static let success = Color(hex: "#34D399")
        static let warning = Color(hex: "#F5B84B")
        static let danger = Color(hex: "#F87171")
    }

    enum Radius {
        static let panel: CGFloat = 18
        static let card: CGFloat = 12
        static let control: CGFloat = 9
    }

    enum Shadow {
        static let panel = Color.black.opacity(0.34)
        static let glow = Colors.accent.opacity(0.36)
    }
}

struct AURAPrimaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 6 : 9)
            .frame(minHeight: compact ? 26 : 32)
            .background(
                RoundedRectangle(cornerRadius: AURAVisualStyle.Radius.control, style: .continuous)
                    .fill(configuration.isPressed ? AURAVisualStyle.Colors.accentHover : AURAVisualStyle.Colors.accent)
            )
            .shadow(color: AURAVisualStyle.Colors.accent.opacity(configuration.isPressed ? 0.18 : 0.28), radius: 8, x: 0, y: 2)
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

struct AURASecondaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(AURAVisualStyle.Colors.textSecondary)
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 5 : 8)
            .frame(minHeight: compact ? 24 : 30)
            .background(
                RoundedRectangle(cornerRadius: AURAVisualStyle.Radius.control, style: .continuous)
                    .fill(configuration.isPressed ? AURAVisualStyle.Colors.surface3 : AURAVisualStyle.Colors.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AURAVisualStyle.Radius.control, style: .continuous)
                    .strokeBorder(AURAVisualStyle.Colors.border.opacity(0.9), lineWidth: 0.75)
            )
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let red: UInt64
        let green: UInt64
        let blue: UInt64
        switch hex.count {
        case 6:
            red = (int >> 16) & 0xFF
            green = (int >> 8) & 0xFF
            blue = int & 0xFF
        default:
            red = 255
            green = 255
            blue = 255
        }
        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: 1
        )
    }
}

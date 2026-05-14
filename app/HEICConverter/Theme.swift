import SwiftUI

enum Theme {

    // MARK: - Colors (from DESIGN.md)
    enum Color {
        static let surface              = SwiftUI.Color(light: "FAF9FE", dark: "1A1B1F")
        static let surfaceContainerLow  = SwiftUI.Color(light: "F4F3F8", dark: "23242A")
        static let surfaceContainer     = SwiftUI.Color(light: "EEEDF3", dark: "2A2B30")
        static let surfaceContainerHigh = SwiftUI.Color(light: "E9E7ED", dark: "2F3034")
        static let onSurface            = SwiftUI.Color(light: "1A1B1F", dark: "F1F0F5")
        static let onSurfaceVariant     = SwiftUI.Color(light: "414755", dark: "C1C6D7")
        static let outline              = SwiftUI.Color(light: "717786", dark: "8B909E")
        static let outlineVariant       = SwiftUI.Color(light: "C1C6D7", dark: "414755")
        static let primary              = SwiftUI.Color(light: "0058BC", dark: "ADC6FF")
        static let onPrimary            = SwiftUI.Color(light: "FFFFFF", dark: "001A41")
        static let error                = SwiftUI.Color(light: "BA1A1A", dark: "FFB4AB")
    }

    // MARK: - Typography (SF Pro — DESIGN.md sizes preserved)
    enum Type {
        static let headlineLg = Font.system(size: 24, weight: .semibold).tracking(-0.48)
        static let headlineMd = Font.system(size: 18, weight: .semibold).tracking(-0.18)
        static let bodyLg     = Font.system(size: 15, weight: .regular).tracking(-0.15)
        static let bodyMd     = Font.system(size: 13, weight: .regular)
        static let bodyMdMed  = Font.system(size: 13, weight: .medium)
        static let labelMd    = Font.system(size: 11, weight: .medium).tracking(0.22)
        static let labelSm    = Font.system(size: 10, weight: .semibold).tracking(0.5)
    }

    // MARK: - Geometry
    enum Radius {
        static let sm: CGFloat   = 8
        static let md: CGFloat   = 16
        static let lg: CGFloat   = 24
        static let pill: CGFloat = 999
    }

    enum Space {
        static let unit: CGFloat        = 4
        static let elementGap: CGFloat  = 8
        static let gutter: CGFloat      = 16
        static let container: CGFloat   = 24
    }
}

// MARK: - Color(light:dark:) helper

private extension Color {
    init(light: String, dark: String) {
        self.init(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(hex: dark)
                : NSColor(hex: light)
        }))
    }
}

private extension NSColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(
            red:   CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8)  & 0xFF) / 255,
            blue:  CGFloat(v         & 0xFF) / 255,
            alpha: 1
        )
    }
}

import SwiftUI
import AppKit

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

enum AppColors {
    // MARK: - Layout

    static let sidebarBackground = Color(nsColor: NSColor(name: "sidebarBackground") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.11, alpha: 1)
            : NSColor(white: 0.945, alpha: 1)
    })

    static let contentBackground = Color(nsColor: NSColor(name: "contentBackground") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.15, alpha: 1)
            : NSColor(white: 1.0, alpha: 1)
    })

    static let contentBorder = Color(nsColor: NSColor(name: "contentBorder") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.22, alpha: 1)
            : NSColor(white: 0.87, alpha: 1)
    })

    static let cardBackground = Color(nsColor: NSColor(name: "cardBackground") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.18, alpha: 1)
            : NSColor(white: 0.96, alpha: 1)
    })

    // MARK: - Sidebar background as NSColor (for window.backgroundColor)

    static let sidebarBackgroundNS: NSColor = NSColor(name: "sidebarBackgroundNS") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.11, alpha: 1)
            : NSColor(white: 0.945, alpha: 1)
    }

    static let sidebarBackgroundDimmedNS: NSColor = NSColor(name: "sidebarBackgroundDimmedNS") { appearance in
        let base: CGFloat = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.11 : 0.945
        return NSColor(white: base * 0.76, alpha: 1)  // matches Color.black.opacity(0.24) overlay
    }

    // MARK: - Text

    static let primaryText = Color(nsColor: NSColor(name: "primaryText") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.92, alpha: 1)
            : NSColor(white: 0.10, alpha: 1)
    })

    static let secondaryText = Color(nsColor: NSColor(name: "secondaryText") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.55, alpha: 1)
            : NSColor(white: 0.40, alpha: 1)
    })

    static let tertiaryText = Color(nsColor: NSColor(name: "tertiaryText") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.40, alpha: 1)
            : NSColor(white: 0.60, alpha: 1)
    })

    // MARK: - Button Colors

    enum ButtonColors {
        // Primary
        static func primaryBackground(isHovered: Bool, isPressed: Bool) -> Color {
            if isPressed { return Color.accentColor.opacity(0.7) }
            if isHovered { return Color.accentColor.opacity(0.85) }
            return Color.accentColor
        }
        static let primaryForeground = Color.white

        // Secondary
        private static let secondaryBgNormal = Color(nsColor: NSColor(name: "secBgNormal") { $0.isDark ? NSColor(white: 0.18, alpha: 1) : NSColor(white: 0.92, alpha: 1) })
        private static let secondaryBgHover = Color(nsColor: NSColor(name: "secBgHover") { $0.isDark ? NSColor(white: 0.22, alpha: 1) : NSColor(white: 0.88, alpha: 1) })
        private static let secondaryBgPressed = Color(nsColor: NSColor(name: "secBgPressed") { $0.isDark ? NSColor(white: 0.26, alpha: 1) : NSColor(white: 0.84, alpha: 1) })

        static func secondaryBackground(isHovered: Bool, isPressed: Bool) -> Color {
            if isPressed { return secondaryBgPressed }
            if isHovered { return secondaryBgHover }
            return secondaryBgNormal
        }
        static let secondaryForeground = Color(nsColor: NSColor(name: "secondaryBtnFg") { $0.isDark ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.20, alpha: 1) })

        // Subtle
        private static let subtleBgHover = Color(nsColor: NSColor(name: "subtleBgHover") { $0.isDark ? NSColor(white: 0.20, alpha: 1) : NSColor(white: 0.87, alpha: 1) })
        private static let subtleBgActive = Color(nsColor: NSColor(name: "subtleBgActive") { $0.isDark ? NSColor(white: 0.22, alpha: 1) : NSColor(white: 0.86, alpha: 1) })
        private static let subtleBgPressed = Color(nsColor: NSColor(name: "subtleBgPressed") { $0.isDark ? NSColor(white: 0.25, alpha: 1) : NSColor(white: 0.83, alpha: 1) })

        static func subtleBackground(isHovered: Bool, isPressed: Bool, isActive: Bool) -> Color {
            if isPressed { return subtleBgPressed }
            if isActive { return subtleBgActive }
            if isHovered { return subtleBgHover }
            return Color.clear
        }
        static func subtleForeground(isActive: Bool) -> Color {
            return Color(nsColor: NSColor(name: "subtleFg") { $0.isDark ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.10, alpha: 1) })
        }
    }
}

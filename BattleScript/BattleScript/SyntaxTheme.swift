import AppKit

enum HighlighterStyle: String, CaseIterable {
    case xcode = "Xcode"
    case vscode = "VS Code"
}

struct SyntaxTheme {
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    static let italicFont: NSFont = {
        NSFontManager.shared.convert(
            NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            toHaveTrait: .italicFontMask
        )
    }()

    static var currentStyle: HighlighterStyle {
        HighlighterStyle(rawValue: UserDefaults.standard.string(forKey: "highlighterStyle") ?? "") ?? .xcode
    }

    // Style-aware fonts
    static var keywordFont: NSFont {
        currentStyle == .xcode ? boldFont : font
    }
    static var typeFont: NSFont {
        currentStyle == .xcode ? boldFont : font
    }
    static var attributeFont: NSFont {
        currentStyle == .xcode ? boldFont : font
    }
    static var commentFont: NSFont {
        currentStyle == .vscode ? italicFont : font
    }

    private static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // Appearance-aware colors
    static var keyword: NSColor {
        isDark ? NSColor(red: 0.78, green: 0.46, blue: 0.96, alpha: 1.0)       // Purple (dark)
               : NSColor(red: 0.61, green: 0.10, blue: 0.87, alpha: 1.0)       // Purple (light)
    }
    static var block: NSColor {
        isDark ? NSColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1.0)        // Orange (dark)
               : NSColor(red: 0.80, green: 0.40, blue: 0.0, alpha: 1.0)        // Orange (light)
    }
    static var `operator`: NSColor {
        isDark ? NSColor(red: 0.35, green: 0.82, blue: 0.95, alpha: 1.0)       // Cyan (dark)
               : NSColor(red: 0.0, green: 0.50, blue: 0.65, alpha: 1.0)        // Teal (light)
    }
    static var string: NSColor {
        isDark ? NSColor(red: 0.99, green: 0.42, blue: 0.42, alpha: 1.0)       // Red (dark)
               : NSColor(red: 0.77, green: 0.10, blue: 0.09, alpha: 1.0)       // Red (light)
    }
    static var number: NSColor {
        isDark ? NSColor(red: 0.95, green: 0.80, blue: 0.30, alpha: 1.0)       // Gold (dark)
               : NSColor(red: 0.11, green: 0.00, blue: 0.81, alpha: 1.0)       // Blue (light - Xcode style)
    }
    static var comment: NSColor {
        isDark ? NSColor(red: 0.55, green: 0.58, blue: 0.60, alpha: 1.0)       // Gray (dark)
               : NSColor(red: 0.38, green: 0.45, blue: 0.38, alpha: 1.0)       // Green-gray (light)
    }
    static var specialValue: NSColor {
        isDark ? NSColor(red: 0.40, green: 0.85, blue: 0.55, alpha: 1.0)       // Green (dark)
               : NSColor(red: 0.15, green: 0.55, blue: 0.25, alpha: 1.0)       // Green (light)
    }
    static var action: NSColor {
        isDark ? NSColor(red: 0.40, green: 0.65, blue: 1.0, alpha: 1.0)        // Blue (dark)
               : NSColor(red: 0.15, green: 0.35, blue: 0.80, alpha: 1.0)       // Blue (light)
    }
    static var preprocessor: NSColor {
        isDark ? NSColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1.0)        // Orange (dark)
               : NSColor(red: 0.43, green: 0.30, blue: 0.15, alpha: 1.0)       // Brown (light)
    }
    static var type: NSColor {
        isDark ? NSColor(red: 0.30, green: 0.80, blue: 0.77, alpha: 1.0)       // Teal (dark)
               : NSColor(red: 0.11, green: 0.43, blue: 0.55, alpha: 1.0)       // Dark teal (light)
    }
    static var defaultText: NSColor {
        isDark ? NSColor(red: 0.87, green: 0.87, blue: 0.87, alpha: 1.0)       // Light gray (dark)
               : NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)          // Black (light)
    }
    static var register: NSColor {
        isDark ? NSColor(red: 0.65, green: 0.55, blue: 0.95, alpha: 1.0)       // Light purple (dark)
               : NSColor(red: 0.40, green: 0.20, blue: 0.75, alpha: 1.0)       // Purple (light)
    }
    static var directive: NSColor {
        isDark ? NSColor(red: 0.85, green: 0.65, blue: 0.40, alpha: 1.0)       // Brown/tan (dark)
               : NSColor(red: 0.50, green: 0.35, blue: 0.15, alpha: 1.0)       // Brown (light)
    }
    static var objcDirective: NSColor {
        isDark ? NSColor(red: 0.90, green: 0.50, blue: 0.30, alpha: 1.0)       // Warm orange (dark)
               : NSColor(red: 0.65, green: 0.30, blue: 0.10, alpha: 1.0)       // Dark orange (light)
    }
    static var functionCall: NSColor {
        isDark ? NSColor(red: 0.40, green: 0.75, blue: 0.95, alpha: 1.0)       // Light blue (dark)
               : NSColor(red: 0.15, green: 0.40, blue: 0.70, alpha: 1.0)       // Dark blue (light)
    }
    static var attribute: NSColor {
        isDark ? NSColor(red: 0.90, green: 0.50, blue: 0.30, alpha: 1.0)       // Warm orange (dark)
               : NSColor(red: 0.60, green: 0.30, blue: 0.05, alpha: 1.0)       // Brown (light)
    }
    static var selfKeyword: NSColor {
        isDark ? NSColor(red: 0.99, green: 0.42, blue: 0.56, alpha: 1.0)       // Pink (dark)
               : NSColor(red: 0.75, green: 0.10, blue: 0.35, alpha: 1.0)       // Dark pink (light)
    }
    static var property: NSColor {
        isDark ? NSColor(red: 0.55, green: 0.82, blue: 0.95, alpha: 1.0)       // Pale blue (dark)
               : NSColor(red: 0.20, green: 0.45, blue: 0.60, alpha: 1.0)       // Steel blue (light)
    }
}

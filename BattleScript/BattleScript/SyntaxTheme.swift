import AppKit

enum HighlighterStyle: String, CaseIterable {
    case xcode = "Xcode"
    case vscode = "VSCode"
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
    // Xcode: bold keywords/types/attributes, regular comments
    // VSCode: italic comments, regular keywords/types/attributes
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
        font
    }

    private static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    private static var isXcode: Bool { currentStyle == .xcode }

    // Helper to pick from 4 variants: (xcode dark, xcode light, vscode dark, vscode light)
    private static func color(xd: UInt32, xl: UInt32, vd: UInt32, vl: UInt32) -> NSColor {
        let hex = isXcode ? (isDark ? xd : xl) : (isDark ? vd : vl)
        return NSColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    // MARK: - Syntax Colors
    // VSCode colors sourced from VSCode Dark Modern & Light Modern themes

    static var keyword: NSColor {
        //        Xcode Dark     Xcode Light    VSCode Dark         VSCode Light
        color(xd: 0xFF7AB2, xl: 0xAD3DA4, vd: 0xC586C0, vl: 0xAF00DB)
    }
    static var block: NSColor {
        color(xd: 0xFF7AB2, xl: 0xAD3DA4, vd: 0xC586C0, vl: 0xAF00DB)
    }
    // Declaration keywords (func, let, var, class, struct, etc.) - blue in VSCode
    static var declarationKeyword: NSColor {
        color(xd: 0xFF7AB2, xl: 0xAD3DA4, vd: 0x569CD6, vl: 0x0000FF)
    }
    static var `operator`: NSColor {
        color(xd: 0xA3B1BF, xl: 0x262626, vd: 0xD4D4D4, vl: 0x000000)
    }
    static var string: NSColor {
        color(xd: 0xFC6A5D, xl: 0xD12F1B, vd: 0xCE9178, vl: 0xA31515)
    }
    static var number: NSColor {
        color(xd: 0xD9C97C, xl: 0x272AD8, vd: 0xB5CEA8, vl: 0x098658)
    }
    static var comment: NSColor {
        color(xd: 0x7F8C99, xl: 0x536579, vd: 0x6A9955, vl: 0x008000)
    }
    static var specialValue: NSColor {
        color(xd: 0x78C2B3, xl: 0x3E8087, vd: 0x569CD6, vl: 0x0000FF)
    }
    static var action: NSColor {
        color(xd: 0xB281EB, xl: 0x804FB8, vd: 0xDCDCAA, vl: 0x795E26)
    }
    static var preprocessor: NSColor {
        color(xd: 0xFFA14F, xl: 0x78492A, vd: 0xC586C0, vl: 0x0000FF)
    }
    static var type: NSColor {
        color(xd: 0x4EB0CC, xl: 0x3E8087, vd: 0x4EC9B0, vl: 0x267F99)
    }
    static var defaultText: NSColor {
        color(xd: 0xDFDFE0, xl: 0x000000, vd: 0xD4D4D4, vl: 0x000000)
    }
    static var register: NSColor {
        color(xd: 0xD0A8FF, xl: 0x713DA9, vd: 0x9CDCFE, vl: 0x001080)
    }
    static var directive: NSColor {
        color(xd: 0xFFA14F, xl: 0x78492A, vd: 0xC586C0, vl: 0x0000FF)
    }
    static var objcDirective: NSColor {
        color(xd: 0xFD8F3F, xl: 0x643820, vd: 0xC586C0, vl: 0x0000FF)
    }
    static var functionCall: NSColor {
        color(xd: 0x67B7A4, xl: 0x316E74, vd: 0xDCDCAA, vl: 0x795E26)
    }
    static var attribute: NSColor {
        color(xd: 0xFD8F3F, xl: 0x643820, vd: 0xDCDCAA, vl: 0x795E26)
    }
    static var selfKeyword: NSColor {
        color(xd: 0xFF7AB2, xl: 0xAD3DA4, vd: 0x569CD6, vl: 0x0000FF)
    }
    static var property: NSColor {
        color(xd: 0x4EB0CC, xl: 0x3E8087, vd: 0x9CDCFE, vl: 0x001080)
    }
    // All identifiers (variables, functions, etc.) - Xcode colors everything, VSCode colors variables
    static var identifier: NSColor {
        color(xd: 0x67B7A4, xl: 0x316E74, vd: 0x9CDCFE, vl: 0x001080)
    }

    // MARK: - Bracket Pair Colorization (VSCode only; Xcode uses default text)
    static var bracket1: NSColor {
        color(xd: 0xA3B1BF, xl: 0x262626, vd: 0xFFD700, vl: 0x0431FA)
    }
    static var bracket2: NSColor {
        color(xd: 0xA3B1BF, xl: 0x262626, vd: 0xDA70D6, vl: 0x319331)
    }
    static var bracket3: NSColor {
        color(xd: 0xA3B1BF, xl: 0x262626, vd: 0x179FFF, vl: 0x7B3814)
    }
    static var bracketColors: [NSColor] { [bracket1, bracket2, bracket3] }
    static var bracketPairEnabled: Bool { currentStyle == .vscode }
}

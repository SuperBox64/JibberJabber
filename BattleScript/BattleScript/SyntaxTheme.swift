import AppKit

struct SyntaxTheme {
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

    // Token colors (dark-mode friendly)
    static let keyword = NSColor(red: 0.78, green: 0.46, blue: 0.96, alpha: 1.0)       // Purple
    static let block = NSColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1.0)           // Orange
    static let `operator` = NSColor(red: 0.35, green: 0.82, blue: 0.95, alpha: 1.0)     // Cyan
    static let string = NSColor(red: 0.99, green: 0.42, blue: 0.42, alpha: 1.0)         // Red
    static let number = NSColor(red: 0.95, green: 0.80, blue: 0.30, alpha: 1.0)         // Gold
    static let comment = NSColor(red: 0.55, green: 0.58, blue: 0.60, alpha: 1.0)        // Gray
    static let specialValue = NSColor(red: 0.40, green: 0.85, blue: 0.55, alpha: 1.0)   // Green
    static let action = NSColor(red: 0.40, green: 0.65, blue: 1.0, alpha: 1.0)          // Blue
    static let preprocessor = NSColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1.0)    // Orange
    static let type = NSColor(red: 0.30, green: 0.80, blue: 0.77, alpha: 1.0)           // Teal
    static let defaultText = NSColor(red: 0.87, green: 0.87, blue: 0.87, alpha: 1.0)    // Light gray
    static let register = NSColor(red: 0.65, green: 0.55, blue: 0.95, alpha: 1.0)       // Light purple
    static let directive = NSColor(red: 0.85, green: 0.65, blue: 0.40, alpha: 1.0)      // Brown/tan
    static let objcDirective = NSColor(red: 0.90, green: 0.50, blue: 0.30, alpha: 1.0)  // Warm orange
}

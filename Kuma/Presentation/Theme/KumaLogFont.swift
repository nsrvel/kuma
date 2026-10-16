import AppKit
import CoreText
import SwiftUI

/// Typography for inspector system activity log (bundled JetBrains Mono Nerd Font).
public enum KumaLogFont {
    private static var didRegisterBundledFont = false
    /// PostScript name after ATSApplicationFontsPath registration.
    public static let nerdPostScriptName = "JetBrainsMonoNF-Regular"
    private static let messageSize: CGFloat = 11
    private static let timestampSize: CGFloat = 10

    private static let fallbackMessage = Font.system(size: messageSize, weight: .regular, design: .monospaced)
    private static let fallbackTimestamp = Font.system(size: timestampSize, weight: .regular, design: .monospaced)

    private static var resolvedMessage: Font?
    private static var resolvedTimestamp: Font?

    public static var logMessage: Font {
        if let resolvedMessage { return resolvedMessage }
        let font = resolveNerdFont(size: messageSize) ?? fallbackMessage
        resolvedMessage = font
        return font
    }

    public static var logTimestamp: Font {
        if let resolvedTimestamp { return resolvedTimestamp }
        let font = resolveNerdFont(size: timestampSize) ?? fallbackTimestamp
        resolvedTimestamp = font
        return font
    }

    private static func resolveNerdFont(size: CGFloat) -> Font? {
        guard NSFont(name: nerdPostScriptName, size: size) != nil else { return nil }
        return .custom(nerdPostScriptName, size: size)
    }

    public static var isNerdFontAvailable: Bool {
        NSFont(name: nerdPostScriptName, size: messageSize) != nil
    }

    /// Call once at launch (`KumaApp.onAppear`) so `Font.custom` resolves before the log panel opens.
    public static func registerBundledFonts() {
        guard !didRegisterBundledFont else { return }
        didRegisterBundledFont = true
        guard let url = Bundle.main.url(forResource: "JetBrainsMonoNerdFont-Regular", withExtension: "ttf") else {
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        resolvedMessage = nil
        resolvedTimestamp = nil
    }
}

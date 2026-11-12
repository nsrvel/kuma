import SwiftUI

// MARK: - Spacing Scale (Zero Magic Numbers)

public enum KumaSpacing {
    /// 4pt — Micro spacing (icon gaps, tight badges)
    public static let xs: CGFloat = 4
    /// 8pt — Small spacing (card internal padding, chip padding)
    public static let sm: CGFloat = 8
    /// 12pt — Medium spacing (form field gap, list item gap)
    public static let md: CGFloat = 12
    /// 16pt — Large spacing (container padding, standard section margins)
    public static let lg: CGFloat = 16
    /// 24pt — Extra large spacing (wizard section gaps)
    public static let xl: CGFloat = 24
    /// 32pt — Hero / Onboarding header spacing
    public static let xxl: CGFloat = 32
}

// MARK: - Corner Radius Scale

public enum KumaRadius {
    /// 6pt — Small elements (tags, badges, inner buttons)
    public static let sm: CGFloat = 6
    /// 10pt — Standard controls (text fields, cards, list rows)
    public static let md: CGFloat = 10
    /// 14pt — Large containers (dialogs, inspector panels, popovers)
    public static let lg: CGFloat = 14
    /// 20pt — Hero elements / Avatars
    public static let xl: CGFloat = 20
}

// MARK: - Typography Scale (macOS SF Pro Native)

public enum KumaFont {
    /// 38pt Bold Rounded — Welcome hero headlines
    public static let hero = Font.system(size: 38, weight: .bold, design: .rounded)
    /// 26pt Bold Rounded — Wizard step titles (balanced scale for content steps)
    public static let stepTitle = Font.system(size: 26, weight: .bold, design: .rounded)
    /// 18pt Bold — Section titles, Window header
    public static let title = Font.system(size: 18, weight: .bold, design: .default)
    /// 16pt Semibold — Section titles, Empty state titles
    public static let title3 = Font.system(size: 16, weight: .semibold, design: .default)
    /// 14pt Semibold — Card titles, primary actions
    public static let heading = Font.system(size: 14, weight: .semibold, design: .default)
    /// 13pt Bold — Card bold labels
    public static let bodyBold = Font.system(size: 13, weight: .bold, design: .default)
    /// 13pt Medium — Form labels, emphasized body
    public static let bodyMedium = Font.system(size: 13, weight: .medium, design: .default)
    /// 13pt Regular — Standard body text, descriptions
    public static let body = Font.system(size: 13, weight: .regular, design: .default)
    /// 15pt Regular — Welcome & hero subheadings
    public static let heroSubtitle = Font.system(size: 15, weight: .regular, design: .default)
    /// 11pt Medium — Subtitles, metadata, status labels
    public static let subheadline = Font.system(size: 11, weight: .medium, design: .default)
    /// 10pt Regular — Footnotes, timestamp, secondary hints
    public static let caption = Font.system(size: 10, weight: .regular, design: .default)
    /// 10pt Bold / Semibold — Section uppercase headers
    public static let captionBold = Font.system(size: 10, weight: .bold, design: .default)
    /// 12pt Monospaced — Ports, URLs, CLI commands, logs
    public static let code = Font.system(size: 12, weight: .regular, design: .monospaced)
}

// MARK: - Semantic Colors & Tints

public enum KumaColors {
    // Surfaces & Canvases (100% Pure Native SwiftUI / AppKit Semantic Colors)
    /// Main Window & Dialog Canvas Background (Native macOS Window Canvas)
    public static let canvasBackground = Color(nsColor: .windowBackgroundColor)

    /// Card Surface with Calibrated Depth (Subtle translucent depth in Dark & Crisp Light Slate in Light)
    public static let surfaceBackground = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.27, green: 0.27, blue: 0.27, alpha: 0.22) // Exact #232323 & #333333 in Dark
            : NSColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1.0)   // #F2F2F5 Soft Light Slate (Clearly pops over Pure White Canvas)
    }))
    /// Secondary / Sub-panel Surface
    public static let surfaceSecondary = Color(nsColor: .controlBackgroundColor)
    /// Input Field Background Surface (opaque inset in dark, white in light)
    public static let inputBackground = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.11, alpha: 1.0)
            : NSColor.white
    }))
    /// Input Field Hairline Border
    public static let inputBorder = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.08) // Soft hairline border in Dark
            : NSColor(white: 0.0, alpha: 0.12) // Crisp subtle border in Light
    }))
    /// Text field fill — same opaque surface as `inputBackground` / Service Name.
    public static var inputFieldFill: Color { inputBackground }
    /// Default unfocused text field stroke.
    public static var inputFieldStroke: Color { inputBorder.opacity(0.6) }
    /// Native Hairline Border & Separator Line
    public static let borderSubtle = Color(nsColor: .separatorColor)

    // Service Execution States (delegate to KumaStatus)
    public static let statusRunning = KumaStatus.runningIndicator
    public static let statusStarting = KumaStatus.transitionalIndicator
    public static let statusStopped = KumaStatus.idleIndicator
    public static let statusFailed = KumaStatus.failedIndicator
    public static let statusDisabled = KumaStatus.disabledIndicator
}

public enum KumaTheme {
    public enum Window {
        // Onboarding Floating Window
        public static let onboardingWidth: CGFloat = 680
        public static let onboardingHeight: CGFloat = 500

        // Main Workspace Window
        public static let minWidth: CGFloat = 1000
        public static let minHeight: CGFloat = 640
        public static let idealWidth: CGFloat = 1260
        public static let idealHeight: CGFloat = 760
    }

    public enum Inspector {
        public static let widthMin: CGFloat = 335
        public static let widthIdeal: CGFloat = 450
        public static let widthMax: CGFloat = 565
    }

    public enum Sidebar {
        public static let widthMin: CGFloat = 200
        public static let widthIdeal: CGFloat = 220
        public static let widthMax: CGFloat = 280

        public static let rowMinHeight: CGFloat = 20
        public static let rowVerticalPadding: CGFloat = 5
        public static let rowHorizontalPadding: CGFloat = 8
        public static let rowCornerRadius: CGFloat = 8

        public static let indentWidth: CGFloat = 4
        public static let specialHeaderTopPadding: CGFloat = 12

        public static let workspaceIconSize: CGFloat = 22
        public static let workspaceCornerRadius: CGFloat = 5
        public static let actionButtonSize: CGFloat = 20

        public static let hoverBgOpacity: Double = 0.08
        public static let selectedBgOpacity: Double = 0.08
        public static let dividerColor = Color.primary.opacity(0.06)
    }

    public enum Workspace {
        /// Popover Switcher menu width
        public static let popoverWidth: CGFloat = 275
        /// Modal form sheet width (Create / Edit)
        public static let formSheetWidth: CGFloat = 440
        public static let formSheetMinHeightCompact: CGFloat = 300
    }

    public enum Deck {
        public static let gridPadding: CGFloat = 16
        public static let gutter: CGFloat = 16
        public static let cardMinWidth: CGFloat = 296
        public static let cardIdealWidth: CGFloat = 320
        public static let cardMaxWidth: CGFloat = 368
    }
}

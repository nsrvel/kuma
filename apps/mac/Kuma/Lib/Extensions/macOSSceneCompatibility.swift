import AppKit
import SwiftUI

// ponytail: macOS 14 lacks Scene chrome APIs added in 15; shims keep one deployment target without forking KumaApp.

extension View {
    @ViewBuilder
    func kumaMainWorkspaceChrome() -> some View {
        if #available(macOS 15.0, *) {
            toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
    }

    @ViewBuilder
    func kumaOnboardingWindowDragSupport() -> some View {
        if #available(macOS 15.0, *) {
            gesture(WindowDragGesture())
        } else {
            background(OnboardingMovableWindowBackground())
        }
    }
}

private struct OnboardingMovableWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.isMovableByWindowBackground = true
    }
}

extension Scene {
    func kumaDisabledWindowRestoration() -> some Scene {
        if #available(macOS 15.0, *) {
            return restorationBehavior(.disabled)
        }
        return self
    }

    func kumaOnboardingWindowChrome() -> some Scene {
        if #available(macOS 15.0, *) {
            return self
                .windowStyle(.plain)
                .windowBackgroundDragBehavior(.enabled)
                .defaultLaunchBehavior(.suppressed)
                .restorationBehavior(.disabled)
        }
        return self.windowStyle(.hiddenTitleBar)
    }
}

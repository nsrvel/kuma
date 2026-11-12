import Foundation
import Observation
import os

public enum AppPhase: String, Sendable, Equatable {
    case onboarding
    case mainWorkspace
}

@MainActor
@Observable
public final class AppCoordinator {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "AppCoordinator")

    public static let completedOnboardingKey = KumaSettingsKey.hasCompletedOnboarding

    public private(set) var currentPhase: AppPhase
    private let userDefaults: UserDefaults

    public init(initialPhase: AppPhase? = nil, userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let initialPhase {
            self.currentPhase = initialPhase
        } else {
            let hasCompleted = userDefaults.bool(forKey: Self.completedOnboardingKey)
            self.currentPhase = hasCompleted ? .mainWorkspace : .onboarding
        }
        Self.logger.debug("AppCoordinator initialized with phase: \(self.currentPhase.rawValue)")
    }

    /// Transitions to a new phase and persists completed onboarding state when moving to mainWorkspace.
    public func transitionTo(_ phase: AppPhase) {
        Self.logger.info("Transitioning AppPhase to: \(phase.rawValue)")
        self.currentPhase = phase
        if phase == .mainWorkspace {
            userDefaults.set(true, forKey: Self.completedOnboardingKey)
        } else if phase == .onboarding {
            userDefaults.set(false, forKey: Self.completedOnboardingKey)
        }
    }

    /// Triggers onboarding from menu bar / help menu / factory reset.
    public func resetToOnboarding() {
        Self.logger.info("Resetting phase to onboarding")
        transitionTo(.onboarding)
    }
}

import Foundation

/// Onboarding step enumeration
enum OnboardingStep: Int, Codable, CaseIterable {
    case welcome = 0
    case displayName = 1
    case username = 2
    case preferences = 3
    case walkthrough = 4
    case terms = 5

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .displayName: return "Set Up Profile"
        case .username: return "Choose Username"
        case .preferences: return "Preferences"
        case .walkthrough: return "Quick Tour"
        case .terms: return "Terms & Privacy"
        }
    }

    var next: OnboardingStep? {
        let allSteps = OnboardingStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: self),
              currentIndex + 1 < allSteps.count else {
            return nil
        }
        return allSteps[currentIndex + 1]
    }

    var previous: OnboardingStep? {
        let allSteps = OnboardingStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: self),
              currentIndex > 0 else {
            return nil
        }
        return allSteps[currentIndex - 1]
    }
}

/// State tracking for onboarding flow
struct OnboardingState {
    var currentStep: OnboardingStep
    var displayName: String
    var username: String?
    var preferences: UserPreferences
    var hasAcceptedTerms: Bool
    var walkthroughCompleted: Bool

    init(
        currentStep: OnboardingStep = .welcome,
        displayName: String = "",
        username: String? = nil,
        preferences: UserPreferences = UserPreferences(),
        hasAcceptedTerms: Bool = false,
        walkthroughCompleted: Bool = false
    ) {
        self.currentStep = currentStep
        self.displayName = displayName
        self.username = username
        self.preferences = preferences
        self.hasAcceptedTerms = hasAcceptedTerms
        self.walkthroughCompleted = walkthroughCompleted
    }

    var isComplete: Bool {
        return !displayName.isEmpty && hasAcceptedTerms
    }

    var progress: Double {
        let totalSteps = Double(OnboardingStep.allCases.count)
        let currentStepIndex = Double(currentStep.rawValue + 1)
        return currentStepIndex / totalSteps
    }
}

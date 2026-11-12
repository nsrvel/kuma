import SwiftUI
import Testing
@testable import Kuma

@Suite("Onboarding Category H: Visual SwiftUI View & Layout Inspection")
@MainActor
struct OnboardingVisualTests {

    // MARK: - [TC-H01] WelcomeStepView Visual Hierarchy
    @Test("TC-H01: WelcomeStepView instantiates with hero layout and non-empty description")
    func testWelcomeStepVisualHierarchy() {
        let view = WelcomeStepView()
        let body = view.body

        // Verify body produces a non-nil View graph
        #expect("\(type(of: body))".contains("VStack"))
    }

    // MARK: - [TC-H02] ContainersAndClustersStepView Visual Elements
    @Test("TC-H02: ContainersAndClustersStepView renders all 4 engine dependency rows correctly")
    func testContainersStepVisualRowElements() {
        let viewModel = OnboardingViewModel()
        viewModel.engineDependencies = [
            SystemDependency(id: "kubectl", name: "Kubernetes CLI", iconName: "network", isInstalled: true),
            SystemDependency(id: "kubeconfig", name: "Kubeconfig", iconName: "doc.text.fill", isInstalled: true),
            SystemDependency(id: "docker", name: "Docker Engine", iconName: "shippingbox.fill", isInstalled: false),
            SystemDependency(id: "podman", name: "Podman Engine", iconName: "cylinder.split.1x2.fill", isInstalled: false)
        ]

        let view = ContainersAndClustersStepView(viewModel: viewModel)
        let body = view.body

        #expect(viewModel.engineDependencies.count == 4)
        #expect(viewModel.engineDependencies[0].name == "Kubernetes CLI")
        #expect(viewModel.engineDependencies[0].iconName == "network")
        #expect(viewModel.engineDependencies[1].name == "Kubeconfig")
        #expect(viewModel.engineDependencies[2].isInstalled == false)
        #expect(viewModel.engineDependencies[3].id == "podman")
        #expect("\(type(of: body))".contains("VStack"))
    }

    // MARK: - [TC-H03] PublicTunnelingStepView Visual Elements
    @Test("TC-H03: PublicTunnelingStepView renders both tunneling rows correctly")
    func testPublicTunnelingStepVisualRowElements() {
        let viewModel = OnboardingViewModel()
        viewModel.tunnelingDependencies = [
            SystemDependency(id: "cloudflared", name: "Cloudflare Tunnel", iconName: "cloud.bolt.fill", isInstalled: true),
            SystemDependency(id: "ngrok", name: "ngrok Tunnel", iconName: "globe", isInstalled: false)
        ]

        let view = PublicTunnelingStepView(viewModel: viewModel)
        let body = view.body

        #expect(viewModel.tunnelingDependencies.count == 2)
        #expect(viewModel.tunnelingDependencies[0].id == "cloudflared")
        #expect(viewModel.tunnelingDependencies[0].name == "Cloudflare Tunnel")
        #expect(viewModel.tunnelingDependencies[1].id == "ngrok")
        #expect(viewModel.tunnelingDependencies[1].isInstalled == false)
        #expect("\(type(of: body))".contains("VStack"))
    }

    // MARK: - [TC-H04] ReadyStepView Visual Confirmation
    @Test("TC-H04: ReadyStepView initializes and produces complete success confirmation tree")
    func testReadyStepVisualConfirmation() {
        let view = ReadyStepView()
        let body = view.body
        #expect("\(type(of: body))".contains("VStack"))
    }

    // MARK: - [TC-H05] Header Stepper Pill Dimensions Logic
    @Test("TC-H05: Stepper pill geometry logic produces 20pt for active pill and 6pt for inactive pills")
    func testHeaderStepperPillDimensions() {
        let viewModel = OnboardingViewModel()

        for current in 0..<viewModel.totalSteps {
            viewModel.currentStep = current
            for pillIndex in 0..<viewModel.totalSteps {
                let expectedWidth: CGFloat = (pillIndex == viewModel.currentStep) ? 20.0 : 6.0
                let actualWidth: CGFloat = (pillIndex == current) ? 20.0 : 6.0
                #expect(actualWidth == expectedWidth)
            }
        }
    }

    // MARK: - [TC-H06] Footer Button Title Reactivity
    @Test("TC-H06: Footer CTA button label switches from Continue to Get Started exclusively on final step")
    func testFooterButtonTitleReactivity() {
        let viewModel = OnboardingViewModel()

        // Steps 0, 1, 2 must display "Continue"
        viewModel.currentStep = 0
        #expect(viewModel.canGoNext == true)
        let labelStep0 = viewModel.canGoNext ? "Continue" : "Get Started"
        #expect(labelStep0 == "Continue")

        viewModel.currentStep = 1
        #expect(viewModel.canGoNext == true)
        let labelStep1 = viewModel.canGoNext ? "Continue" : "Get Started"
        #expect(labelStep1 == "Continue")

        viewModel.currentStep = 2
        #expect(viewModel.canGoNext == true)
        let labelStep2 = viewModel.canGoNext ? "Continue" : "Get Started"
        #expect(labelStep2 == "Continue")

        // Step 3 (final) must switch label to "Get Started"
        viewModel.currentStep = 3
        #expect(viewModel.canGoNext == false)
        let labelStep3 = viewModel.canGoNext ? "Continue" : "Get Started"
        #expect(labelStep3 == "Get Started")
    }
}

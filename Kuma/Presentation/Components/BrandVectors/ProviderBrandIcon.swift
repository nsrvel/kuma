import SwiftUI

public struct ProviderBrandIcon: View {
    public let category: ProviderCategory
    public var tunnelType: String? = nil
    public var size: CGFloat = 14
    public var rasterize: Bool = true

    public init(
        category: ProviderCategory,
        tunnelType: String? = nil,
        size: CGFloat = 14,
        rasterize: Bool = true
    ) {
        self.category = category
        self.tunnelType = tunnelType
        self.size = size
        self.rasterize = rasterize
    }

    public var body: some View {
        Group {
            switch category {
            case .docker:
                brandVector(DockerBrandVector())
            case .kubernetes:
                brandVector(KubernetesBrandVector())
            case .podman:
                brandVector(PodmanBrandVector())
            case .shell:
                Image(systemName: "terminal.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            case .ssh:
                Image(systemName: "server.rack")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            case .httpCheck:
                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            case .tunnel:
                Image(systemName: "cloud.bolt.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            case .processMonitor:
                Image(systemName: "cpu.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            }
        }
    }

    @ViewBuilder
    private func brandVector<V: View>(_ vector: V) -> some View {
        let framed = vector.frame(width: size, height: size)
        if rasterize {
            framed.drawingGroup(opaque: false, colorMode: .nonLinear)
        } else {
            framed
        }
    }
}

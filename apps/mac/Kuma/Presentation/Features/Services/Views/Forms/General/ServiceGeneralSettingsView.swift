import SwiftUI

public struct ServiceGeneralSettingsView: View {
    @Binding public var name: String
    @Binding public var serviceDescription: String
    public var placeholder: String
    public var icon: String
    public var subtitle: String?

    public init(
        name: Binding<String>,
        serviceDescription: Binding<String>,
        placeholder: String = "Postgres DB",
        icon: String = "info.circle",
        subtitle: String? = nil
    ) {
        self._name = name
        self._serviceDescription = serviceDescription
        self.placeholder = placeholder
        self.icon = icon
        self.subtitle = subtitle
    }

    public var body: some View {
        KumaFormSection(
            icon: icon,
            title: "General",
            subtitle: subtitle
        ) {
            VStack(alignment: .leading, spacing: 12) {
                KumaTextField(
                    label: "Service Name",
                    value: $name,
                    placeholder: placeholder
                )

                KumaTextArea(
                    label: "Description",
                    value: $serviceDescription,
                    placeholder: "Purpose or notes",
                    minHeight: 52
                )
            }
        }
    }
}

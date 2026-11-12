import SwiftUI

public struct ServiceProvidersInlineFormView: View {
    public let isEditing: Bool
    @Binding public var formType: ProviderCategory
    @Binding public var formLabel: String
    public let onSave: () -> Void
    public let onCancel: () -> Void

    public var body: some View {
        KumaFormInlinePanel(
            headerTitle: isEditing ? "Edit Provider" : "New Provider",
            headerIcon: "square.stack.3d.down.right.fill",
            closeAccessibilityLabel: "Cancel add provider",
            onCancel: onCancel,
            onPrimary: onSave
        ) {
            VStack(alignment: .leading, spacing: KumaSpacing.md) {
                KumaRowPickerField(
                    label: "Provider Type",
                    description: "Select runtime engine.",
                    options: ProviderCategory.allCases.map(\.rawValue),
                    selection: Binding(
                        get: { formType.rawValue },
                        set: { if let cat = ProviderCategory(rawValue: $0) { formType = cat } }
                    ),
                    titleResolver: { (ProviderCategory(rawValue: $0) ?? .docker).sidebarLabel }
                )

                Divider().opacity(0.3)

                KumaTextField(
                    label: "Custom Label (Optional)",
                    value: $formLabel,
                    placeholder: "Staging"
                )
            }
            .padding(.top, KumaSpacing.xs)
            .padding(.bottom, KumaSpacing.xs)
        }
    }
}

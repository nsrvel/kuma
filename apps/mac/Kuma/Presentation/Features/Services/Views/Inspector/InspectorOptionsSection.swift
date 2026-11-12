import SwiftUI

public struct InspectorOptionsSection: View {
    public var activeProvider: Binding<Provider>?
    public let isLocked: Bool
    public var onProviderFieldChanged: (() -> Void)?
    @Binding public var isDisabled: Bool
    public let isRunning: Bool
    public let onDelete: () -> Void

    public init(
        activeProvider: Binding<Provider>? = nil,
        isLocked: Bool = false,
        onProviderFieldChanged: (() -> Void)? = nil,
        isDisabled: Binding<Bool>,
        isRunning: Bool = false,
        onDelete: @escaping () -> Void
    ) {
        self.activeProvider = activeProvider
        self.isLocked = isLocked
        self.onProviderFieldChanged = onProviderFieldChanged
        self._isDisabled = isDisabled
        self.isRunning = isRunning
        self.onDelete = onDelete
    }

    private var showsAutoReconnect: Bool {
        guard let activeProvider else { return false }
        return activeProvider.wrappedValue.type.supportsAutoReconnect
    }

    public var body: some View {
        KumaFormSection(
            icon: "gearshape.fill",
            title: "Options"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if showsAutoReconnect, let activeProvider {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto Reconnect")
                                .font(KumaFont.body)
                            Text("Up to 3 retries after disconnect.")
                                .font(KumaFont.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { activeProvider.wrappedValue.autoReconnect ?? false },
                            set: {
                                activeProvider.wrappedValue.autoReconnect = $0
                                onProviderFieldChanged?()
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .accessibilityLabel("Auto reconnect")
                        .disabled(isLocked)
                    }

                    Divider().opacity(0.4)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Disable Service")
                            .font(KumaFont.body)
                        Text("Excluded from bulk actions.")
                            .font(KumaFont.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $isDisabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .accessibilityLabel("Disable service")
                        .disabled(isRunning)
                }

                Divider().opacity(0.4)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete Service")
                            .font(KumaFont.body)
                            .foregroundStyle(.red)
                        Text("Permanent removal.")
                            .font(KumaFont.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Delete") {
                        onDelete()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                    .disabled(isRunning)
                }
            }
        }
    }
}

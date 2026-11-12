import AppKit
import SwiftUI

public struct KumaPortMappingItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var local: String
    public var remote: String

    public init(id: UUID = UUID(), local: String = "", remote: String = "") {
        self.id = id
        self.local = local
        self.remote = remote
    }

    public var isValid: Bool {
        guard let localVal = Int(local), let remoteVal = Int(remote) else { return false }
        return localVal > 0 && localVal <= 65535 && remoteVal > 0 && remoteVal <= 65535
    }
}

public struct KumaPortMappingRow: View {
    @Binding public var item: KumaPortMappingItem
    public let onDelete: () -> Void

    @FocusState private var isLocalFocused: Bool
    @FocusState private var isRemoteFocused: Bool

    public init(item: Binding<KumaPortMappingItem>, onDelete: @escaping () -> Void) {
        self._item = item
        self.onDelete = onDelete
    }

    private var isLocalValid: Bool {
        guard !item.local.isEmpty else { return true }
        guard let val = Int(item.local) else { return false }
        return val > 0 && val <= 65535
    }

    private var isRemoteValid: Bool {
        guard !item.remote.isEmpty else { return true }
        guard let val = Int(item.remote) else { return false }
        return val > 0 && val <= 65535
    }

    public var body: some View {
        HStack(spacing: KumaSpacing.sm) {
            portField(
                placeholder: "Local",
                text: $item.local,
                isFocused: $isLocalFocused,
                isValid: isLocalValid
            )
            .frame(maxWidth: .infinity)

            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 2)

            portField(
                placeholder: "Remote",
                text: $item.remote,
                isFocused: $isRemoteFocused,
                isValid: isRemoteValid
            )
            .frame(maxWidth: .infinity)

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.red.opacity(0.75))
            }
            .buttonStyle(.plain)
            .padding(.leading, 2)
        }
        .frame(maxWidth: .infinity)
    }

    /// Avoids macOS `TextField(_:text:)` prompt shifting when focused (especially with center alignment).
    private func portField(
        placeholder: String,
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        isValid: Bool
    ) -> some View {
        ZStack {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(KumaFont.body)
                    .foregroundStyle(Color(nsColor: .placeholderTextColor))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }

            TextField("", text: text)
                .font(KumaFont.body)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .multilineTextAlignment(.center)
        }
        .padding(KumaSpacing.sm)
        .background(KumaColors.inputFieldFill, in: RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous)
                .stroke(
                    !isValid ? Color.red.opacity(0.8) : (isFocused.wrappedValue ? Color.accentColor : KumaColors.inputFieldStroke),
                    lineWidth: isFocused.wrappedValue || !isValid ? 1.5 : 0.5
                )
        )
    }
}

public struct KumaPortMappingEditor: View {
    public let label: String
    @Binding public var items: [KumaPortMappingItem]
    public init(label: String = "", items: Binding<[KumaPortMappingItem]>) {
        self.label = label
        self._items = items
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KumaSpacing.sm) {
            if !label.isEmpty {
                Text(label)
                    .font(KumaFont.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach($items) { $item in
                KumaPortMappingRow(item: $item, onDelete: {
                    if items.count > 1 {
                        items.removeAll(where: { $0.id == item.id })
                    } else {
                        item.local = ""
                        item.remote = ""
                    }
                })
            }

            if hasInvalidPorts {
                KumaNoticeBanner(
                    style: .error,
                    title: "Invalid Port Number",
                    message: "Port must be a valid integer between 1 and 65535."
                )
                .padding(.top, 2)
            }

            HStack {
                KumaFormAddActionButton(
                    style: .textLink,
                    title: "Add port mapping",
                    helpWhenEnabled: "Add port mapping",
                    helpWhenDisabled: "Stop service to edit ports",
                    action: { items.append(KumaPortMappingItem()) }
                )

                Spacer()
            }
            .padding(.top, 4)
            .padding(.horizontal, 2)
        }
        .onAppear {
            if items.isEmpty {
                items.append(KumaPortMappingItem())
            }
        }
    }

    private var hasInvalidPorts: Bool {
        items.contains { item in
            let local = item.local.trimmingCharacters(in: .whitespacesAndNewlines)
            let remote = item.remote.trimmingCharacters(in: .whitespacesAndNewlines)

            let isLocalBad = !local.isEmpty && (Int(local) == nil || Int(local)! <= 0 || Int(local)! > 65535)
            let isRemoteBad = !remote.isEmpty && (Int(remote) == nil || Int(remote)! <= 0 || Int(remote)! > 65535)

            return isLocalBad || isRemoteBad
        }
    }
}

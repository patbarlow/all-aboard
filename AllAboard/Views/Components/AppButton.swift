import SwiftUI

// MARK: - AppButton

struct AppButton: View {
    enum Variant {
        case primary
        case secondary
        case subtle
    }

    enum IconPlacement {
        case leading
        case trailing
    }

    private let label: String?
    private let systemImage: String?
    private let iconPlacement: IconPlacement
    private let variant: Variant
    private let isActive: Bool
    private let fullWidth: Bool
    private let action: () -> Void

    @State private var isHovered = false

    // Label only
    init(_ label: String, variant: Variant = .secondary, isActive: Bool = false, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = nil
        self.iconPlacement = .leading
        self.variant = variant
        self.isActive = isActive
        self.fullWidth = fullWidth
        self.action = action
    }

    // Icon only
    init(systemImage: String, variant: Variant = .secondary, isActive: Bool = false, action: @escaping () -> Void) {
        self.label = nil
        self.systemImage = systemImage
        self.iconPlacement = .leading
        self.variant = variant
        self.isActive = isActive
        self.fullWidth = false
        self.action = action
    }

    // Label + icon
    init(_ label: String, systemImage: String, iconPlacement: IconPlacement = .leading, variant: Variant = .secondary, isActive: Bool = false, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.iconPlacement = iconPlacement
        self.variant = variant
        self.isActive = isActive
        self.fullWidth = fullWidth
        self.action = action
    }

    private var isIconOnly: Bool { label == nil && systemImage != nil }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage, iconPlacement == .leading {
                    Image(systemName: systemImage)
                        .font(.system(size: 13))
                }
                if let label {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                if let systemImage, iconPlacement == .trailing {
                    Image(systemName: systemImage)
                        .font(.system(size: 13))
                }
                if fullWidth {
                    Spacer()
                }
            }
            .frame(height: 32)
            .frame(minWidth: isIconOnly ? 32 : nil)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, isIconOnly ? 0 : 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppButtonStyle(variant: variant, isHovered: isHovered, isActive: isActive))
        .onHover { isHovered = $0 }
    }
}

// MARK: - Button Style

private struct AppButtonStyle: ButtonStyle {
    let variant: AppButton.Variant
    let isHovered: Bool
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .animation(.easeInOut(duration: 0.1), value: isHovered)
            .animation(.easeInOut(duration: 0.05), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return AppColors.ButtonColors.primaryBackground(isHovered: isHovered, isPressed: isPressed)
        case .secondary:
            return AppColors.ButtonColors.secondaryBackground(isHovered: isHovered, isPressed: isPressed)
        case .subtle:
            return AppColors.ButtonColors.subtleBackground(isHovered: isHovered, isPressed: isPressed, isActive: isActive)
        }
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return AppColors.ButtonColors.primaryForeground
        case .secondary:
            return AppColors.ButtonColors.secondaryForeground
        case .subtle:
            return AppColors.ButtonColors.subtleForeground(isActive: isActive)
        }
    }
}

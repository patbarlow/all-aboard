import SwiftUI

// MARK: - Sidebar Heading

struct SidebarHeading: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppColors.tertiaryText)
    }
}

// MARK: - SidebarItem

/// A multi-line sidebar row that reuses AppButton's subtle-variant color logic.
/// Used for trip rows which need two lines (origin + destination).
struct SidebarItem<Content: View>: View {
    let isActive: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppColors.ButtonColors.subtleBackground(
                            isHovered: isHovered,
                            isPressed: false,
                            isActive: isActive
                        ))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

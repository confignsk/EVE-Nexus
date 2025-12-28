import SwiftUI

// MARK: - 条件性刷新 Modifier

struct ConditionalRefreshableModifier: ViewModifier {
    let isEnabled: Bool
    let action: () async -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.refreshable {
                await action()
            }
        } else {
            content
        }
    }
}

extension View {
    func conditionalRefreshable(isEnabled: Bool, action: @escaping () async -> Void) -> some View {
        modifier(ConditionalRefreshableModifier(isEnabled: isEnabled, action: action))
    }
}

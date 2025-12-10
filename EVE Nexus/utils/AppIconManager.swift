import Foundation
import UIKit

class AppIconManager: ObservableObject {
    static let shared = AppIconManager()

    @Published var currentIconName: String? = nil

    // 所有可用的备用图标
    let availableIcons: [AppIcon] = [
        AppIcon(id: nil, name: "Default", displayName: NSLocalizedString("App_Icon_Default", comment: "")),
        AppIcon(id: "AppIcon_DED", name: "DED", displayName: NSLocalizedString("App_Icon_DED", comment: "")),
        AppIcon(id: "AppIcon_Faction", name: "Faction", displayName: NSLocalizedString("App_Icon_Faction", comment: "")),
        AppIcon(id: "AppIcon_Officer", name: "Officer", displayName: NSLocalizedString("App_Icon_Office", comment: "")),
        AppIcon(id: "AppIcon_T2", name: "T2", displayName: NSLocalizedString("App_Icon_T2", comment: "")),
        AppIcon(id: "AppIcon_T3", name: "T3", displayName: NSLocalizedString("App_Icon_T3", comment: "")),
    ]

    private let iconKey = "selectedAppIcon"

    private init() {
        loadCurrentIcon()
    }

    // 加载当前图标
    private func loadCurrentIcon() {
        if let savedIcon = UserDefaults.standard.string(forKey: iconKey) {
            currentIconName = savedIcon.isEmpty ? nil : savedIcon
        } else {
            currentIconName = nil
        }
    }

    // 切换图标
    @MainActor
    func setIcon(_ iconId: String?) async throws {
        // 确保所有 UIApplication 调用都在主线程
        guard UIApplication.shared.supportsAlternateIcons else {
            Logger.error("设备不支持备用图标")
            throw AppIconError.notSupported
        }

        let iconName = iconId?.isEmpty == true ? nil : iconId

        Logger.info("尝试切换图标到: \(iconName ?? "默认")")

        do {
            // setAlternateIconName 必须在主线程调用
            try await UIApplication.shared.setAlternateIconName(iconName)

            // 更新状态
            currentIconName = iconName
            UserDefaults.standard.set(iconName ?? "", forKey: iconKey)

            Logger.info("应用图标已成功切换为: \(iconName ?? "默认")")
        } catch {
            Logger.error("切换应用图标失败 - 图标ID: \(iconName ?? "nil"), 错误: \(error.localizedDescription)")
            Logger.error("错误详情: \(error)")
            throw error
        }
    }

    // 获取当前图标信息
    func getCurrentIcon() -> AppIcon? {
        if let current = currentIconName {
            return availableIcons.first { $0.id == current }
        }
        return availableIcons.first { $0.id == nil }
    }
}

struct AppIcon: Identifiable {
    let id: String?
    let name: String
    let displayName: String
}

enum AppIconError: LocalizedError {
    case notSupported

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return NSLocalizedString("App_Icon_Not_Supported", comment: "")
        }
    }
}

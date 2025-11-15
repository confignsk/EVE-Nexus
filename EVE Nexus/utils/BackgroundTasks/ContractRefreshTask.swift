import Foundation

/// 合同数据更新后台任务
/// 负责每4小时更新一次当前所选角色的个人合同数据
/// 使用 BGProcessingTask 以获得更长的执行时间
@MainActor
class ContractRefreshTask: BaseProcessingTask {
    static let identifier = "com.evenexus.contractrefresh"
    static let interval: TimeInterval = 60 * 60 // 1小时

    init() {
        super.init(identifier: Self.identifier, interval: Self.interval)
    }

    override func perform() async {
        Logger.notice("开始执行后台合同数据更新")

        // 获取当前所选角色ID
        let currentCharacterId = UserDefaults.standard.integer(forKey: "currentCharacterId")
        guard currentCharacterId != 0 else {
            Logger.info("没有当前所选角色，跳过合同数据更新")
            return
        }

        // 检查角色是否存在且token未过期
        guard let characterAuth = EVELogin.shared.getCharacterByID(currentCharacterId) else {
            Logger.warning("找不到当前所选角色: \(currentCharacterId)")
            return
        }

        if characterAuth.character.refreshTokenExpired {
            Logger.warning("当前所选角色token已过期，跳过合同数据更新: \(currentCharacterId)")
            return
        }

        // 检查任务是否被取消
        if Task.isCancelled {
            Logger.warning("合同数据更新任务被取消")
            return
        }

        do {
            // 强制刷新合同数据
            _ = try await CharacterContractsAPI.shared.fetchContracts(
                characterId: currentCharacterId,
                forceRefresh: true
            )
            Logger.success("成功更新合同数据: \(currentCharacterId)")
        } catch {
            Logger.error("更新合同数据失败: \(currentCharacterId), 错误: \(error)")
        }
    }
}

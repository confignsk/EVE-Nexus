import Foundation

/// 钱包数据更新后台任务
/// 负责定期更新当前所选角色的钱包流水和交易数据
/// 使用 BGProcessingTask 以获得更长的执行时间
@MainActor
class WalletRefreshTask: BaseProcessingTask {
    static let identifier = "com.evenexus.walletrefresh"
    static let interval: TimeInterval = 60 * 60 // 1小时

    init() {
        super.init(identifier: Self.identifier, interval: Self.interval)
    }

    override func perform() async {
        Logger.notice("开始执行后台钱包数据更新")

        // 获取当前所选角色ID
        let currentCharacterId = UserDefaults.standard.integer(forKey: "currentCharacterId")
        guard currentCharacterId != 0 else {
            Logger.info("没有当前所选角色，跳过钱包数据更新")
            return
        }

        // 检查角色是否存在且token未过期
        guard let characterAuth = EVELogin.shared.getCharacterByID(currentCharacterId) else {
            Logger.warning("找不到当前所选角色: \(currentCharacterId)")
            return
        }

        if characterAuth.character.refreshTokenExpired {
            Logger.warning("当前所选角色token已过期，跳过钱包数据更新: \(currentCharacterId)")
            return
        }

        // 检查任务是否被取消
        if Task.isCancelled {
            Logger.warning("钱包数据更新任务被取消")
            return
        }

        // 并发加载钱包流水和交易数据
        async let journalTask = loadWalletJournal(characterId: currentCharacterId)
        async let transactionsTask = loadWalletTransactions(characterId: currentCharacterId)

        // 等待两个任务完成
        let (journalResult, transactionsResult) = await (journalTask, transactionsTask)

        // 记录结果
        if journalResult {
            Logger.success("成功更新钱包流水数据: \(currentCharacterId)")
        } else {
            Logger.error("更新钱包流水数据失败: \(currentCharacterId)")
        }

        if transactionsResult {
            Logger.success("成功更新钱包交易数据: \(currentCharacterId)")
        } else {
            Logger.error("更新钱包交易数据失败: \(currentCharacterId)")
        }
    }

    /// 加载钱包流水数据
    private func loadWalletJournal(characterId: Int) async -> Bool {
        do {
            _ = try await CharacterWalletAPI.shared.getWalletJournal(
                characterId: characterId,
                forceRefresh: true
            )
            return true
        } catch {
            Logger.error("加载钱包流水失败: \(characterId), 错误: \(error)")
            return false
        }
    }

    /// 加载钱包交易数据
    private func loadWalletTransactions(characterId: Int) async -> Bool {
        do {
            _ = try await CharacterWalletAPI.shared.getWalletTransactions(
                characterId: characterId,
                forceRefresh: true
            )
            return true
        } catch {
            Logger.error("加载钱包交易失败: \(characterId), 错误: \(error)")
            return false
        }
    }
}


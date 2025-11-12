import BackgroundTasks
import Foundation

// MARK: - 后台任务刷新间隔配置（调试用）

/// 数据刷新任务间隔（秒）
private let DATA_REFRESH_INTERVAL: TimeInterval = 1 * 60 * 60

/// 后台任务标识符
enum BackgroundTaskIdentifier: String {
    case dataRefresh = "com.evenexus.datarefresh"

    var identifier: String {
        return rawValue
    }
}

/// 后台任务管理器
@MainActor
class BackgroundTaskManager: ObservableObject {
    static let shared = BackgroundTaskManager()

    private init() {
        registerBackgroundTasks()
    }

    /// 注册后台任务
    private func registerBackgroundTasks() {
        // 注册数据刷新任务
        let dataRefreshRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIdentifier.dataRefresh.identifier,
            using: nil
        ) { task in
            Logger.info("数据刷新任务被系统触发，标识符: \(BackgroundTaskIdentifier.dataRefresh.identifier)")
            self.handleDataRefreshTask(task: task as! BGAppRefreshTask)
        }

        Logger.info("后台任务注册完成 - 数据刷新: \(dataRefreshRegistered)")
        Logger.info("数据刷新任务标识符: \(BackgroundTaskIdentifier.dataRefresh.identifier)")
    }

    /// 处理数据刷新任务
    private func handleDataRefreshTask(task: BGAppRefreshTask) {
        Logger.info("开始执行数据刷新任务")

        // 设置任务过期处理
        task.expirationHandler = {
            Logger.warning("数据刷新任务已过期")
            task.setTaskCompleted(success: false)
        }

        // 执行数据刷新
        Task {
            await performDataRefresh()
            task.setTaskCompleted(success: true)
            Logger.info("数据刷新任务完成")

            // 安排下一次刷新
            scheduleDataRefresh()
        }
    }

    /// 执行数据刷新
    private func performDataRefresh() async {
        Logger.info("开始执行后台数据刷新")

        let characters = EVELogin.shared.loadCharacters()
        guard !characters.isEmpty else {
            Logger.info("没有需要刷新的角色")
            return
        }

        // 刷新所有角色的基本信息
        for characterAuth in characters {
            let characterId = characterAuth.character.CharacterID

            // 跳过token已过期的角色
            if characterAuth.character.refreshTokenExpired {
                Logger.warning("跳过token已过期的角色: \(characterId)")
                continue
            }

            do {
                // 刷新角色详细信息
                try await refreshCharacterData(characterId: characterId)
                Logger.success("成功刷新角色数据: \(characterId)")
            } catch {
                Logger.error("刷新角色数据失败: \(characterId), 错误: \(error)")
            }
        }

        // 刷新公共数据
        await refreshPublicData()

        Logger.success("后台数据刷新完成")
    }

    /// 刷新单个角色的数据（仅钱包和位置信息）
    private func refreshCharacterData(characterId: Int) async throws {
        // 获取角色信息
        guard var character = EVELogin.shared.getCharacterByID(characterId)?.character else {
            throw NetworkError.invalidData
        }

        // 并发获取钱包余额和位置信息
        async let balance = CharacterWalletAPI.shared.getWalletBalance(characterId: characterId)
        async let location = CharacterLocationAPI.shared.fetchCharacterLocation(characterId: characterId)

        let (balanceResult, locationResult) = try await (balance, location)

        // 获取位置详细信息
        let databaseManager = DatabaseManager()
        let locationInfo = await getSolarSystemInfo(
            solarSystemId: locationResult.solar_system_id,
            databaseManager: databaseManager
        )

        // 只更新钱包和位置信息
        character.walletBalance = balanceResult
        character.location = locationInfo
        character.locationStatus = locationResult.locationStatus

        // 保存更新后的信息
        try await EVELogin.shared.saveCharacterInfo(character)
    }

    /// 刷新公共数据（仅主权数据）
    private func refreshPublicData() async {
        // 刷新主权数据
        Task.detached(priority: .background) {
            do {
                _ = try await SovereigntyDataAPI.shared.fetchSovereigntyData(forceRefresh: false)
                Logger.success("主权数据刷新完成")
            } catch {
                Logger.error("主权数据刷新失败: \(error)")
            }
        }
    }

    /// 安排数据刷新任务
    func scheduleDataRefresh() {
        let taskIdentifier = BackgroundTaskIdentifier.dataRefresh.identifier

        // 先取消之前的任务，避免创建重复任务
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        Logger.notice("已移除旧的后台任务，标识符: \(taskIdentifier)")

        let request = BGAppRefreshTaskRequest(
            identifier: taskIdentifier
        )

        // 设置下次刷新时间
        request.earliestBeginDate = Date(timeIntervalSinceNow: DATA_REFRESH_INTERVAL)

        do {
            try BGTaskScheduler.shared.submit(request)

            // 格式化日期为本地时区显示
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.locale = Locale.current

            let formattedDate = request.earliestBeginDate.map { dateFormatter.string(from: $0) } ?? "未知"
            Logger.success("数据刷新任务已安排: \(formattedDate)")
            Logger.info("数据刷新任务标识符: \(taskIdentifier)")
        } catch {
            Logger.error("安排数据刷新任务失败: \(error)")
            Logger.error("错误详情: \(error.localizedDescription)")
        }
    }

    /// 取消所有后台任务
    func cancelAllTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: BackgroundTaskIdentifier.dataRefresh.identifier)
        Logger.warning("所有后台任务已取消")
    }

    /// 在应用启动时调用，安排后台任务
    func scheduleBackgroundTasks() {
        scheduleDataRefresh()
    }
}

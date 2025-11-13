import BackgroundTasks
import Foundation

// MARK: - 后台任务刷新间隔配置

/// 数据刷新任务间隔（秒）
private let DATA_REFRESH_INTERVAL: TimeInterval = 1 * 60 * 60

/// 后台任务标识符
private let backgroundTaskIdentifier = "com.evenexus.datarefresh"

/// 后台任务管理器
@MainActor
class BackgroundTaskManager: ObservableObject {
    static let shared = BackgroundTaskManager()

    private var refreshTask: Task<Void, Never>?

    private init() {
        registerBackgroundTasks()
    }

    /// 注册后台任务
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            Logger.info("数据刷新任务被系统触发")
            self.handleDataRefreshTask(task: task as! BGAppRefreshTask)
        }

        Logger.info("后台任务注册完成，标识符: \(backgroundTaskIdentifier)")
    }

    /// 处理数据刷新任务
    private func handleDataRefreshTask(task: BGAppRefreshTask) {
        Logger.info("开始执行数据刷新任务")

        // 安排下一次刷新任务
        scheduleDataRefresh()

        // 创建刷新任务
        refreshTask = Task {
            await performDataRefresh()
            
            // 通知系统后台任务已完成
            // 只要任务执行完成就标记为成功，部分数据刷新失败不影响任务状态
            task.setTaskCompleted(success: true)
            Logger.info("数据刷新任务完成")
        }

        // 提供过期处理器，在系统需要终止任务时取消任务
        task.expirationHandler = {
            Logger.warning("数据刷新任务已过期，取消任务")
            self.refreshTask?.cancel()
            task.setTaskCompleted(success: false)
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
            // 检查任务是否被取消
            if Task.isCancelled {
                Logger.warning("数据刷新任务被取消")
                return
            }

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
                // 继续处理其他角色，不中断整个任务
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
        do {
            _ = try await SovereigntyDataAPI.shared.fetchSovereigntyData(forceRefresh: false)
            Logger.success("主权数据刷新完成")
        } catch {
            Logger.error("主权数据刷新失败: \(error)")
        }
    }

    /// 安排数据刷新任务
    func scheduleDataRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
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
        } catch {
            Logger.error("安排数据刷新任务失败: \(error)")
        }
    }

    /// 取消所有后台任务
    func cancelAllTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
        refreshTask?.cancel()
        Logger.warning("所有后台任务已取消")
    }
}

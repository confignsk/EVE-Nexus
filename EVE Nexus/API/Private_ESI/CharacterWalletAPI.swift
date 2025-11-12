import Foundation

class CharacterWalletAPI {
    static let shared = CharacterWalletAPI()

    // 缓存结构
    private struct CacheEntry: Codable {
        let value: String // 改用字符串存储以保持精度
        let timestamp: Date
    }

    // 添加并发队列用于同步访问
    private let cacheQueue = DispatchQueue(
        label: "com.eve-nexus.wallet-cache", attributes: .concurrent
    )

    // 内存缓存
    private var memoryCache: [Int: CacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 20 * 60 // 20分钟缓存，钱包余额使用

    // UserDefaults键前缀
    private let walletCachePrefix = "wallet_cache_"

    private let queryInterval: TimeInterval = 3600 // 1小时的查询间隔
    private let journalCacheTimeout: TimeInterval = 3600 // 1小时的流水缓存超时时间

    // 获取钱包流水缓存目录
    private func getWalletJournalCacheDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[
            0
        ]
        let cacheDirectory = documentsPath.appendingPathComponent("CharWallet")

        // 如果目录不存在，创建它
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            Logger.info("创建钱包流水缓存目录: \(cacheDirectory.path)")
            try? FileManager.default.createDirectory(
                at: cacheDirectory, withIntermediateDirectories: true
            )
        }

        return cacheDirectory
    }

    // 获取钱包流水缓存文件路径
    private func getJournalCacheFilePath(characterId: Int) -> URL {
        let cacheDirectory = getWalletJournalCacheDirectory()
        return cacheDirectory.appendingPathComponent("Journal_\(characterId).json")
    }

    // 获取钱包交易记录缓存文件路径
    private func getTransactionsCacheFilePath(characterId: Int) -> URL {
        let cacheDirectory = getWalletJournalCacheDirectory()
        return cacheDirectory.appendingPathComponent("Transactions_\(characterId).json")
    }

    // 检查钱包流水缓存是否过期
    private func isJournalCacheExpired(characterId: Int) -> Bool {
        let filePath = getJournalCacheFilePath(characterId: characterId)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            Logger.info("钱包流水缓存文件不存在，需要刷新 - 文件路径: \(filePath.path)")
            return true
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let timeInterval = Date().timeIntervalSince(modificationDate)
                let remainingTime = journalCacheTimeout - timeInterval
                let remainingMinutes = Int(remainingTime / 60)
                let remainingSeconds = Int(remainingTime.truncatingRemainder(dividingBy: 60))
                let isExpired = timeInterval > journalCacheTimeout

                Logger.info(
                    "钱包流水缓存状态检查 - 角色ID: \(characterId), 文件修改时间: \(modificationDate), 当前时间: \(Date()), 时间间隔: \(timeInterval)秒, 剩余时间: \(remainingMinutes)分\(remainingSeconds)秒, 是否过期: \(isExpired)"
                )
                return isExpired
            }
        } catch {
            Logger.error("获取钱包流水缓存文件属性失败: \(error) - 文件路径: \(filePath.path)")
        }

        return true
    }

    // 检查钱包交易记录缓存是否过期
    private func isTransactionsCacheExpired(characterId: Int) -> Bool {
        let filePath = getTransactionsCacheFilePath(characterId: characterId)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            Logger.info("钱包交易记录缓存文件不存在，需要刷新 - 文件路径: \(filePath.path)")
            return true
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let timeInterval = Date().timeIntervalSince(modificationDate)
                let remainingTime = queryInterval - timeInterval
                let remainingMinutes = Int(remainingTime / 60)
                let remainingSeconds = Int(remainingTime.truncatingRemainder(dividingBy: 60))
                let isExpired = timeInterval > queryInterval

                Logger.info(
                    "钱包交易记录缓存状态检查 - 角色ID: \(characterId), 文件修改时间: \(modificationDate), 当前时间: \(Date()), 时间间隔: \(timeInterval)秒, 剩余时间: \(remainingMinutes)分\(remainingSeconds)秒, 是否过期: \(isExpired)"
                )
                return isExpired
            }
        } catch {
            Logger.error("获取钱包交易记录缓存文件属性失败: \(error) - 文件路径: \(filePath.path)")
        }

        return true
    }

    /// 使指定角色的钱包相关缓存失效（包括流水、交易记录和钱包余额）
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - invalidateWalletBalance: 是否同时失效钱包余额缓存，默认为true
    private func invalidateCharacterWalletCache(characterId: Int, invalidateWalletBalance: Bool = true) {
        let journalFilePath = getJournalCacheFilePath(characterId: characterId)
        let transactionsFilePath = getTransactionsCacheFilePath(characterId: characterId)

        // 删除流水记录缓存文件
        if FileManager.default.fileExists(atPath: journalFilePath.path) {
            do {
                try FileManager.default.removeItem(at: journalFilePath)
                Logger.info("已删除角色钱包流水缓存文件 - 角色ID: \(characterId), 文件路径: \(journalFilePath.path)")
            } catch {
                Logger.error("删除角色钱包流水缓存文件失败 - 角色ID: \(characterId), 错误: \(error)")
            }
        }

        // 删除交易记录缓存文件
        if FileManager.default.fileExists(atPath: transactionsFilePath.path) {
            do {
                try FileManager.default.removeItem(at: transactionsFilePath)
                Logger.info("已删除角色钱包交易记录缓存文件 - 角色ID: \(characterId), 文件路径: \(transactionsFilePath.path)")
            } catch {
                Logger.error("删除角色钱包交易记录缓存文件失败 - 角色ID: \(characterId), 错误: \(error)")
            }
        }

        // 删除角色钱包余额缓存（内存和磁盘）
        if invalidateWalletBalance {
            // 清除内存缓存
            cacheQueue.async(flags: .barrier) {
                self.memoryCache.removeValue(forKey: characterId)
            }

            // 清除磁盘缓存（UserDefaults）
            let cacheKey = walletCachePrefix + String(characterId)
            UserDefaults.standard.removeObject(forKey: cacheKey)
            Logger.info("已删除角色钱包余额缓存 - 角色ID: \(characterId)")
        }
    }

    private init() {
        // 从 UserDefaults 恢复缓存
        let defaults = UserDefaults.standard
        Logger.debug("正在从 UserDefaults 读取所有钱包缓存键")
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix(walletCachePrefix),
               let data = defaults.data(forKey: key),
               let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
               let characterId = Int(key.replacingOccurrences(of: walletCachePrefix, with: ""))
            {
                memoryCache[characterId] = entry
            }
        }
    }

    // 安全地获取钱包缓存
    private func getWalletMemoryCache(characterId: Int) -> CacheEntry? {
        var result: CacheEntry?
        cacheQueue.sync {
            result = memoryCache[characterId]
        }
        return result
    }

    // 安全地设置钱包缓存
    private func setWalletMemoryCache(characterId: Int, cache: CacheEntry) {
        cacheQueue.async(flags: .barrier) {
            self.memoryCache[characterId] = cache
        }
    }

    // 检查缓存是否有效
    private func isCacheValid(_ cache: CacheEntry?) -> Bool {
        guard let cache = cache else {
            Logger.info("钱包缓存为空")
            return false
        }
        let timeInterval = Date().timeIntervalSince(cache.timestamp)
        let isValid = timeInterval < cacheTimeout
        Logger.info(
            "钱包缓存时间检查 - 缓存时间: \(cache.timestamp), 当前时间: \(Date()), 时间间隔: \(timeInterval)秒, 超时时间: \(cacheTimeout)秒, 是否有效: \(isValid)"
        )
        return isValid
    }

    // 从UserDefaults获取缓存
    private func getDiskCache(characterId: Int) -> CacheEntry? {
        let key = walletCachePrefix + String(characterId)
        guard let data = UserDefaults.standard.data(forKey: key) else {
            Logger.info("钱包磁盘缓存不存在 - Key: \(key)")
            return nil
        }

        guard let cache = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
            Logger.error("钱包磁盘缓存解码失败 - Key: \(key)")
            return nil
        }

        Logger.success("成功读取钱包磁盘缓存 - Key: \(key), 缓存时间: \(cache.timestamp), 值: \(cache.value)")
        return cache
    }

    // 保存缓存到UserDefaults
    private func saveToDiskCache(characterId: Int, cache: CacheEntry) {
        let key = walletCachePrefix + String(characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            Logger.info(
                "保存钱包缓存到磁盘 - Key: \(key), 缓存时间: \(cache.timestamp), 值: \(cache.value), 数据大小: \(encoded.count) bytes"
            )
            UserDefaults.standard.set(encoded, forKey: key)
        } else {
            Logger.error("保存钱包缓存到磁盘失败 - Key: \(key)")
        }
    }

    // 获取缓存的钱包余额（异步方法）
    func getCachedWalletBalance(characterId: Int) async -> String {
        // 1. 先检查内存缓存
        if let memoryCached = getWalletMemoryCache(characterId: characterId) {
            return memoryCached.value
        }

        // 2. 如果内存缓存不可用，检查磁盘缓存
        if let diskCached = getDiskCache(characterId: characterId) {
            // 更新内存缓存
            setWalletMemoryCache(characterId: characterId, cache: diskCached)
            return diskCached.value
        }

        return "-"
    }

    // 获取钱包余额（异步方法，用于后台刷新）
    func getWalletBalance(characterId: Int, forceRefresh: Bool = false) async throws -> Double {
        // 如果是强制刷新，先使关联缓存失效
        if forceRefresh {
            Logger.info("强制刷新角色钱包，使关联缓存失效 - 角色ID: \(characterId)")
            invalidateCharacterWalletCache(characterId: characterId)
        }

        // 如果不是强制刷新，检查缓存是否有效
        if !forceRefresh {
            // 检查缓存
            let cachedResult: Double? = {
                if let memoryCached = getWalletMemoryCache(characterId: characterId),
                   isCacheValid(memoryCached)
                {
                    Logger.info("使用内存缓存的钱包余额数据 - 角色ID: \(characterId)")
                    return Double(memoryCached.value)
                }

                if let diskCached = getDiskCache(characterId: characterId),
                   isCacheValid(diskCached)
                {
                    Logger.info("使用磁盘缓存的钱包余额数据 - 角色ID: \(characterId)")
                    setWalletMemoryCache(characterId: characterId, cache: diskCached)
                    return Double(diskCached.value)
                }

                return nil
            }()

            if let cachedValue = cachedResult {
                return cachedValue
            }

            Logger.info("缓存未命中或已过期,需要从服务器获取钱包数据 - 角色ID: \(characterId)")
        }

        let urlString = "https://esi.evetech.net/characters/\(characterId)/wallet/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        guard
            let stringValue = String(data: data, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines)
        else {
            Logger.error("无法解析钱包余额数据: \(String(data: data, encoding: .utf8) ?? "无数据")")
            throw NetworkError.invalidResponse
        }

        Logger.info("ESI响应: 钱包余额 = \(stringValue) ISK")

        // 创建新的缓存条目，直接存储字符串值
        let cacheEntry = CacheEntry(value: stringValue, timestamp: Date())

        // 更新内存缓存
        setWalletMemoryCache(characterId: characterId, cache: cacheEntry)

        // 更新磁盘缓存
        saveToDiskCache(characterId: characterId, cache: cacheEntry)

        return Double(stringValue) ?? 0.0
    }

    // 从缓存文件获取钱包流水
    private func getWalletJournalFromCache(characterId: Int) -> [[String: Any]]? {
        let filePath = getJournalCacheFilePath(characterId: characterId)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            Logger.info("钱包流水缓存文件不存在 - 角色ID: \(characterId), 文件路径: \(filePath.path)")
            return nil
        }

        Logger.info("开始读取钱包流水缓存文件 - 角色ID: \(characterId), 文件路径: \(filePath.path)")

        do {
            let data = try Data(contentsOf: filePath)
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])

            if let journalEntries = jsonObject as? [[String: Any]] {
                Logger.info(
                    "成功从缓存文件读取钱包流水 - 角色ID: \(characterId), 记录数量: \(journalEntries.count), 文件大小: \(data.count) bytes"
                )
                return journalEntries
            } else {
                Logger.error("钱包流水缓存文件格式不正确 - 角色ID: \(characterId), 文件路径: \(filePath.path)")
                return nil
            }
        } catch {
            Logger.error(
                "读取钱包流水缓存文件失败 - 角色ID: \(characterId), 错误: \(error), 文件路径: \(filePath.path)")
            return nil
        }
    }

    // 保存钱包流水到缓存文件
    private func saveWalletJournalToCache(characterId: Int, entries: [[String: Any]]) -> Bool {
        let filePath = getJournalCacheFilePath(characterId: characterId)

        Logger.info(
            "开始保存钱包流水到缓存文件 - 角色ID: \(characterId), 记录数量: \(entries.count), 文件路径: \(filePath.path)")

        do {
            let jsonData = try JSONSerialization.data(
                withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]
            )
            try jsonData.write(to: filePath)
            Logger.info(
                "成功保存钱包流水到缓存文件 - 角色ID: \(characterId), 记录数量: \(entries.count), 文件大小: \(jsonData.count) bytes, 文件路径: \(filePath.path)"
            )
            return true
        } catch {
            Logger.error(
                "保存钱包流水到缓存文件失败 - 角色ID: \(characterId), 错误: \(error), 文件路径: \(filePath.path)")
            return false
        }
    }

    // 从缓存文件获取钱包交易记录
    private func getWalletTransactionsFromCache(characterId: Int) -> [[String: Any]]? {
        let filePath = getTransactionsCacheFilePath(characterId: characterId)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            Logger.info("钱包交易记录缓存文件不存在 - 角色ID: \(characterId), 文件路径: \(filePath.path)")
            return nil
        }

        Logger.info("开始读取钱包交易记录缓存文件 - 角色ID: \(characterId), 文件路径: \(filePath.path)")

        do {
            let data = try Data(contentsOf: filePath)
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])

            if let transactionEntries = jsonObject as? [[String: Any]] {
                Logger.info(
                    "成功从缓存文件读取钱包交易记录 - 角色ID: \(characterId), 记录数量: \(transactionEntries.count), 文件大小: \(data.count) bytes"
                )
                return transactionEntries
            } else {
                Logger.error("钱包交易记录缓存文件格式不正确 - 角色ID: \(characterId), 文件路径: \(filePath.path)")
                return nil
            }
        } catch {
            Logger.error(
                "读取钱包交易记录缓存文件失败 - 角色ID: \(characterId), 错误: \(error), 文件路径: \(filePath.path)")
            return nil
        }
    }

    // 保存钱包交易记录到缓存文件
    private func saveWalletTransactionsToCache(characterId: Int, entries: [[String: Any]]) -> Bool {
        let filePath = getTransactionsCacheFilePath(characterId: characterId)

        Logger.info(
            "开始保存钱包交易记录到缓存文件 - 角色ID: \(characterId), 记录数量: \(entries.count), 文件路径: \(filePath.path)")

        do {
            let jsonData = try JSONSerialization.data(
                withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]
            )
            try jsonData.write(to: filePath)
            Logger.info(
                "成功保存钱包交易记录到缓存文件 - 角色ID: \(characterId), 记录数量: \(entries.count), 文件大小: \(jsonData.count) bytes, 文件路径: \(filePath.path)"
            )
            return true
        } catch {
            Logger.error(
                "保存钱包交易记录到缓存文件失败 - 角色ID: \(characterId), 错误: \(error), 文件路径: \(filePath.path)")
            return false
        }
    }

    // 获取钱包流水
    func getWalletJournal(characterId: Int, forceRefresh: Bool = false) async throws
        -> String?
    {
        Logger.info("开始获取钱包流水 - 角色ID: \(characterId), 强制刷新: \(forceRefresh)")

        // 如果是强制刷新，先使关联缓存失效
        if forceRefresh {
            Logger.info("强制刷新角色钱包流水，使关联缓存失效 - 角色ID: \(characterId)")
            invalidateCharacterWalletCache(characterId: characterId)
        }

        // 如果强制刷新或缓存过期，则从网络获取
        if forceRefresh || isJournalCacheExpired(characterId: characterId) {
            Logger.info("钱包流水缓存过期或需要强制刷新，从网络获取数据 - 角色ID: \(characterId)")
            let journalData = try await fetchJournalFromServer(characterId: characterId)
            if !saveWalletJournalToCache(characterId: characterId, entries: journalData) {
                Logger.error("保存钱包流水到缓存文件失败 - 角色ID: \(characterId)")
            }
        } else {
            Logger.info("使用缓存文件中的钱包流水数据 - 角色ID: \(characterId)")
        }

        // 从缓存文件获取数据并返回
        if let results = getWalletJournalFromCache(characterId: characterId) {
            let jsonData = try JSONSerialization.data(
                withJSONObject: results, options: [.prettyPrinted, .sortedKeys]
            )
            Logger.info("钱包流水数据处理完成 - 角色ID: \(characterId), JSON大小: \(jsonData.count) bytes")
            return String(data: jsonData, encoding: .utf8)
        }

        Logger.error("无法获取钱包流水数据 - 角色ID: \(characterId)")
        return nil
    }

    // 从服务器获取钱包流水
    private func fetchJournalFromServer(characterId: Int) async throws -> [[String: Any]] {
        let baseUrlString =
            "https://esi.evetech.net/characters/\(characterId)/wallet/journal/?datasource=tranquility"
        guard let baseUrl = URL(string: baseUrlString) else {
            throw NetworkError.invalidURL
        }

        let journalEntries = try await NetworkManager.shared.fetchPaginatedData(
            from: baseUrl,
            characterId: characterId,
            maxConcurrentPages: 3,
            decoder: { data in
                guard
                    let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else {
                    throw NetworkError.invalidResponse
                }
                return entries
            },
            progressCallback: { currentPage, totalPages in
                Logger.debug("正在获取第 \(currentPage)/\(totalPages) 页钱包流水数据")
            }
        )

        Logger.info("钱包流水获取完成，共\(journalEntries.count)条记录")
        return journalEntries
    }

    // 获取钱包交易记录
    func getWalletTransactions(characterId: Int, forceRefresh: Bool = false) async throws
        -> String?
    {
        Logger.info("开始获取钱包交易记录 - 角色ID: \(characterId), 强制刷新: \(forceRefresh)")

        // 如果是强制刷新，先使关联缓存失效
        if forceRefresh {
            Logger.info("强制刷新角色钱包交易记录，使关联缓存失效 - 角色ID: \(characterId)")
            invalidateCharacterWalletCache(characterId: characterId)
        }

        // 如果强制刷新或缓存过期，则从网络获取
        if forceRefresh || isTransactionsCacheExpired(characterId: characterId) {
            Logger.info("钱包交易记录缓存过期或需要强制刷新，从网络获取数据 - 角色ID: \(characterId)")
            let transactionData = try await fetchTransactionsFromServer(characterId: characterId)
            if !saveWalletTransactionsToCache(characterId: characterId, entries: transactionData) {
                Logger.error("保存钱包交易记录到缓存文件失败 - 角色ID: \(characterId)")
            }
        } else {
            Logger.info("使用缓存文件中的钱包交易记录数据 - 角色ID: \(characterId)")
        }

        // 从缓存文件获取数据并返回
        if let results = getWalletTransactionsFromCache(characterId: characterId) {
            let jsonData = try JSONSerialization.data(
                withJSONObject: results, options: [.prettyPrinted, .sortedKeys]
            )
            Logger.info("钱包交易记录数据处理完成 - 角色ID: \(characterId), JSON大小: \(jsonData.count) bytes")
            return String(data: jsonData, encoding: .utf8)
        }

        Logger.error("无法获取钱包交易记录数据 - 角色ID: \(characterId)")
        return nil
    }

    // 从服务器获取交易记录
    private func fetchTransactionsFromServer(characterId: Int) async throws -> [[String: Any]] {
        let urlString =
            "https://esi.evetech.net/characters/\(characterId)/wallet/transactions/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        guard let transactions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            throw NetworkError.invalidResponse
        }

        Logger.success("成功获取钱包交易记录，共\(transactions.count)条记录")
        return transactions
    }
}

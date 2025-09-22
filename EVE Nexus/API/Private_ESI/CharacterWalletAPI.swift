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

    // 钱包交易记录缓存前缀
    private let lastTransactionQueryKey = "LastWalletTransactionQuery_"
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

    // 获取交易记录最后查询时间（保留原有逻辑）
    private func getLastTransactionQueryTime(characterId: Int) -> Date? {
        let key = lastTransactionQueryKey + String(characterId)
        return UserDefaults.standard.object(forKey: key) as? Date
    }

    // 更新交易记录最后查询时间（保留原有逻辑）
    private func updateLastTransactionQueryTime(characterId: Int) {
        let key = lastTransactionQueryKey + String(characterId)
        UserDefaults.standard.set(Date(), forKey: key)
    }

    // 检查交易记录是否需要刷新
    private func shouldRefreshTransactionData(characterId: Int) -> Bool {
        guard let lastQuery = getLastTransactionQueryTime(characterId: characterId) else {
            Logger.debug("没有找到上次交易记录查询时间记录，需要刷新数据")
            return true
        }

        let timeInterval = Date().timeIntervalSince(lastQuery)
        let remainingTime = queryInterval - timeInterval
        let remainingMinutes = Int(remainingTime / 60)
        let remainingSeconds = Int(remainingTime.truncatingRemainder(dividingBy: 60))

        Logger.debug("钱包交易记录下次刷新剩余时间: \(remainingMinutes)分\(remainingSeconds)秒")
        return timeInterval > queryInterval
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

        Logger.info("成功读取钱包磁盘缓存 - Key: \(key), 缓存时间: \(cache.timestamp), 值: \(cache.value)")
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

    // 获取钱包流水
    func getWalletJournal(characterId: Int, forceRefresh: Bool = false) async throws
        -> String?
    {
        Logger.info("开始获取钱包流水 - 角色ID: \(characterId), 强制刷新: \(forceRefresh)")

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

    // 从数据库获取钱包交易记录
    private func getWalletTransactionsFromDB(characterId: Int) -> [[String: Any]]? {
        let query = """
            SELECT transaction_id, client_id, date, is_buy, is_personal,
                   journal_ref_id, location_id, quantity, type_id,
                   unit_price, last_updated
            FROM wallet_transactions 
            WHERE character_id = ? 
            ORDER BY date DESC 
            LIMIT 1000
        """

        if case let .success(results) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [characterId]
        ) {
            // 将整数转换回布尔值
            return results.map { row in
                var mutableRow = row
                if let isBuy = row["is_buy"] as? Int64 {
                    mutableRow["is_buy"] = isBuy != 0
                }
                if let isPersonal = row["is_personal"] as? Int64 {
                    mutableRow["is_personal"] = isPersonal != 0
                }
                return mutableRow
            }
        }
        return nil
    }

    // 保存钱包交易记录到数据库
    private func saveWalletTransactionsToDB(characterId: Int, entries: [[String: Any]]) -> Bool {
        // 如果没有条目需要保存，直接返回成功
        if entries.isEmpty {
            Logger.info("没有钱包交易记录需要保存")
            return true
        }

        // 首先获取已存在的交易ID
        let checkQuery = "SELECT transaction_id FROM wallet_transactions WHERE character_id = ?"
        guard
            case let .success(existingResults) = CharacterDatabaseManager.shared.executeQuery(
                checkQuery, parameters: [characterId]
            )
        else {
            Logger.error("查询现有交易记录失败")
            return false
        }

        let existingIds = Set(existingResults.compactMap { ($0["transaction_id"] as? Int64) })

        // 过滤出需要插入的新记录
        let newEntries = entries.filter { entry in
            let transactionId = entry["transaction_id"] as? Int64 ?? 0
            return !existingIds.contains(transactionId)
        }

        // 如果没有新记录，直接返回成功
        if newEntries.isEmpty {
            Logger.info("无需新增交易记录")
            return true
        }

        Logger.info("准备插入\(newEntries.count)条新钱包交易记录")

        // 开始事务
        _ = CharacterDatabaseManager.shared.executeQuery("BEGIN TRANSACTION")

        // 计算每批次的大小（每条记录11个参数）
        let batchSize = 100 // 每批次处理100条记录
        var success = true

        // 分批处理数据
        for batchStart in stride(from: 0, to: newEntries.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, newEntries.count)
            let currentBatch = Array(newEntries[batchStart ..< batchEnd])

            // 构建批量插入语句
            let placeholders = Array(
                repeating: "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", count: currentBatch.count
            ).joined(separator: ",")
            let insertSQL = """
                INSERT OR REPLACE INTO wallet_transactions (
                    transaction_id, character_id, client_id, date, is_buy,
                    is_personal, journal_ref_id, location_id, quantity,
                    type_id, unit_price
                ) VALUES \(placeholders)
            """

            // 准备参数数组
            var parameters: [Any] = []
            for entry in currentBatch {
                let transactionId = entry["transaction_id"] as? Int64 ?? 0

                // 将布尔值转换为整数
                let isBuy = (entry["is_buy"] as? Bool ?? false) ? 1 : 0
                let isPersonal = (entry["is_personal"] as? Bool ?? false) ? 1 : 0

                let params: [Any] = [
                    transactionId,
                    characterId,
                    entry["client_id"] as? Int ?? 0,
                    entry["date"] as? String ?? "",
                    isBuy,
                    isPersonal,
                    entry["journal_ref_id"] as? Int64 ?? 0,
                    entry["location_id"] as? Int64 ?? 0,
                    entry["quantity"] as? Int ?? 0,
                    entry["type_id"] as? Int ?? 0,
                    entry["unit_price"] as? Double ?? 0.0,
                ]
                parameters.append(contentsOf: params)
            }

            Logger.debug("执行批量插入钱包交易记录，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")

            // 执行批量插入
            if case let .error(message) = CharacterDatabaseManager.shared.executeQuery(
                insertSQL, parameters: parameters
            ) {
                Logger.error("批量插入钱包交易记录失败: \(message)")
                success = false
                break
            }
        }

        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            Logger.info("成功插入\(newEntries.count)条钱包交易记录到数据库")
            return true
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存钱包交易记录失败，执行回滚")
            return false
        }
    }

    // 获取钱包交易记录
    func getWalletTransactions(characterId: Int, forceRefresh: Bool = false) async throws
        -> String?
    {
        // 检查数据库中是否有数据，以及是否需要刷新
        let checkQuery = "SELECT COUNT(*) as count FROM wallet_transactions WHERE character_id = ?"
        let result = CharacterDatabaseManager.shared.executeQuery(
            checkQuery, parameters: [characterId]
        )
        let isEmpty =
            if case let .success(rows) = result,
            let row = rows.first,
            let count = row["count"] as? Int64 {
                count == 0
            } else {
                true
            }

        // 如果数据为空、强制刷新或达到查询间隔，则从网络获取
        if isEmpty || forceRefresh || shouldRefreshTransactionData(characterId: characterId) {
            Logger.debug("钱包交易记录为空或需要刷新，从网络获取数据")
            let transactionData = try await fetchTransactionsFromServer(characterId: characterId)
            if !saveWalletTransactionsToDB(characterId: characterId, entries: transactionData) {
                Logger.error("保存钱包交易记录到数据库失败")
            }
            // 更新最后查询时间
            updateLastTransactionQueryTime(characterId: characterId)
        } else {
            Logger.debug("使用数据库中的钱包交易记录数据")
        }

        // 从数据库获取数据并返回
        if let results = getWalletTransactionsFromDB(characterId: characterId) {
            let jsonData = try JSONSerialization.data(
                withJSONObject: results, options: [.prettyPrinted, .sortedKeys]
            )
            return String(data: jsonData, encoding: .utf8)
        }
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

        Logger.info("成功获取钱包交易记录，共\(transactions.count)条记录")
        return transactions
    }
}

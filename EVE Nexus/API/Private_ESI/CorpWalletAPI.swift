import Foundation

// 军团钱包数据模型
struct CorpWallet: Codable {
    let division: Int
    let balance: Double
    var name: String?
}

// 军团部门数据模型
struct CorpDivisions: Codable {
    let hangar: [DivisionInfo]
    let wallet: [DivisionInfo]
}

struct DivisionInfo: Codable {
    let division: Int
    let name: String?
}

@globalActor actor CorpWalletAPIActor {
    static let shared = CorpWalletAPIActor()
}

@CorpWalletAPIActor
class CorpWalletAPI {
    static let shared = CorpWalletAPI()

    // 军团钱包流水缓存超时时间
    private let journalCacheTimeout: TimeInterval = 3600 // 1小时的流水缓存超时时间

    private init() {}

    // 获取军团钱包流水缓存目录
    private func getCorpWalletJournalCacheDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[
            0
        ]
        let cacheDirectory = documentsPath.appendingPathComponent("CorpWallet")

        // 如果目录不存在，创建它
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            Logger.info("创建军团钱包流水缓存目录: \(cacheDirectory.path)")
            try? FileManager.default.createDirectory(
                at: cacheDirectory, withIntermediateDirectories: true
            )
        }

        return cacheDirectory
    }

    // 获取军团钱包流水缓存文件路径
    private func getCorpJournalCacheFilePath(corporationId: Int, division: Int) -> URL {
        let cacheDirectory = getCorpWalletJournalCacheDirectory()
        return cacheDirectory.appendingPathComponent(
            "CorpJournal_\(corporationId)_\(division).json")
    }

    // 检查军团钱包流水缓存是否过期
    private func isCorpJournalCacheExpired(corporationId: Int, division: Int) -> Bool {
        let filePath = getCorpJournalCacheFilePath(corporationId: corporationId, division: division)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            Logger.info(
                "军团钱包流水缓存文件不存在，需要刷新 - 军团ID: \(corporationId), 部门: \(division), 文件路径: \(filePath.path)"
            )
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
                    "军团钱包流水缓存状态检查 - 军团ID: \(corporationId), 部门: \(division), 文件修改时间: \(modificationDate), 当前时间: \(Date()), 时间间隔: \(timeInterval)秒, 剩余时间: \(remainingMinutes)分\(remainingSeconds)秒, 是否过期: \(isExpired)"
                )
                return isExpired
            }
        } catch {
            Logger.error(
                "获取军团钱包流水缓存文件属性失败: \(error) - 军团ID: \(corporationId), 部门: \(division), 文件路径: \(filePath.path)"
            )
        }

        return true
    }

    /// 获取军团钱包信息
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - forceRefresh: 是否强制刷新缓存
    /// - Returns: 军团钱包数组
    func fetchCorpWallets(characterId: Int, forceRefresh: Bool = false) async throws -> [CorpWallet] {
        // 1. 获取角色的军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        // 2. 获取部门信息
        let divisions = try await fetchCorpDivisions(
            characterId: characterId, forceRefresh: forceRefresh
        )

        // 3. 检查缓存
        let cacheKey = "corp_wallets_\(corporationId)"
        let cacheTimeKey = "corp_wallets_\(corporationId)_time"

        if !forceRefresh,
           let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let lastUpdateTime = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
           Date().timeIntervalSince(lastUpdateTime) < 60 * 60
        { // 60 分钟缓存
            do {
                var wallets = try JSONDecoder().decode([CorpWallet].self, from: cachedData)
                // 添加部门名称
                for i in 0 ..< wallets.count {
                    let division = wallets[i].division
                    if let divisionInfo = divisions.wallet.first(where: { $0.division == division }) {
                        wallets[i].name = getDivisionName(
                            division: division, type: "wallet", customName: divisionInfo.name
                        )
                    }
                }
                Logger.info("使用缓存的军团钱包数据 - 军团ID: \(corporationId)")
                return wallets
            } catch {
                Logger.error("解析缓存的军团钱包数据失败: \(error)")
            }
        }

        // 4. 构建请求
        let urlString =
            "https://esi.evetech.net/corporations/\(corporationId)/wallets/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        // 5. 发送请求
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url, characterId: characterId
        )
        var wallets = try JSONDecoder().decode([CorpWallet].self, from: data)

        // 6. 添加部门名称
        for i in 0 ..< wallets.count {
            let division = wallets[i].division
            if let divisionInfo = divisions.wallet.first(where: { $0.division == division }) {
                wallets[i].name = getDivisionName(
                    division: division, type: "wallet", customName: divisionInfo.name
                )
            }
        }

        // 7. 更新缓存
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)

        Logger.info("成功获取军团钱包数据 - 军团ID: \(corporationId)")
        return wallets
    }

    /// 获取军团部门信息
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - forceRefresh: 是否强制刷新缓存
    /// - Returns: 军团部门信息
    func fetchCorpDivisions(characterId: Int, forceRefresh: Bool = false) async throws
        -> CorpDivisions
    {
        // 1. 获取角色的军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        // 2. 检查缓存
        let cacheKey = "corp_divisions_\(corporationId)"
        let cacheTimeKey = "corp_divisions_\(corporationId)_time"

        if !forceRefresh,
           let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let lastUpdateTime = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
           Date().timeIntervalSince(lastUpdateTime) < 60 * 60
        { // 1小时缓存
            do {
                let divisions = try JSONDecoder().decode(CorpDivisions.self, from: cachedData)
                Logger.info("使用缓存的军团部门数据 - 军团ID: \(corporationId)")
                return divisions
            } catch {
                Logger.error("解析缓存的军团部门数据失败: \(error)")
            }
        }

        // 3. 构建请求
        let urlString =
            "https://esi.evetech.net/corporations/\(corporationId)/divisions/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        // 4. 发送请求
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url, characterId: characterId
        )
        let divisions = try JSONDecoder().decode(CorpDivisions.self, from: data)

        // 5. 更新缓存
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)

        Logger.info("成功获取军团部门数据 - 军团ID: \(corporationId)")
        return divisions
    }

    /// 获取部门名称
    /// - Parameters:
    ///   - division: 部门编号
    ///   - type: 部门类型 ("hangar" 或 "wallet")
    ///   - customName: 自定义名称
    /// - Returns: 本地化的部门名称
    func getDivisionName(division: Int, type: String, customName: String?) -> String {
        if let name = customName {
            // 如果是wallet类型且名称匹配"Wallet Division \d+"模式，则不使用customName
            if type == "wallet" {
                let pattern = "^Wallet Division \\d+$"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   regex.firstMatch(
                       in: name, options: [], range: NSRange(location: 0, length: name.utf16.count)
                   ) != nil
                {
                    // 使用默认格式
                    if division == 1 {
                        return String(
                            format: NSLocalizedString(
                                "Main_Corporation_Wallet_Division1", comment: ""
                            ),
                            division
                        )
                    } else {
                        return String(
                            format: NSLocalizedString(
                                "Main_Corporation_Wallet_Default", comment: ""
                            ),
                            division
                        )
                    }
                }
            }
            return name
        }

        // 根据类型返回默认名称
        if type == "hangar" {
            return String(
                format: NSLocalizedString("Main_Corporation_Hangar_Default", comment: ""), division
            )
        } else if type == "wallet" {
            if division == 1 {
                return String(
                    format: NSLocalizedString("Main_Corporation_Wallet_Division1", comment: ""),
                    division
                )
            } else {
                return String(
                    format: NSLocalizedString("Main_Corporation_Wallet_Default", comment: ""),
                    division
                )
            }
        } else {
            return NSLocalizedString("Unknown", comment: "")
        }
    }

    /// 从服务器获取军团钱包流水
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - division: 部门编号
    ///   - progressCallback: 加载进度回调
    /// - Returns: 钱包流水数组
    private func fetchCorpJournalFromServer(
        characterId: Int,
        corporationId: Int,
        division: Int,
        progressCallback: ((WalletLoadingProgress) -> Void)? = nil
    ) async throws -> [[String: Any]] {
        let baseUrlString =
            "https://esi.evetech.net/corporations/\(corporationId)/wallets/\(division)/journal/?datasource=tranquility"
        guard let baseUrl = URL(string: baseUrlString) else {
            throw NetworkError.invalidURL
        }

        return try await NetworkManager.shared.fetchPaginatedData(
            from: baseUrl,
            characterId: characterId,
            maxConcurrentPages: 5,
            decoder: { data in
                guard
                    let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else {
                    throw NetworkError.invalidResponse
                }
                return entries
            },
            progressCallback: { currentPage, _ in
                progressCallback?(.loading(page: currentPage))
            }
        )
    }

    /// 从缓存文件获取军团钱包流水
    /// - Parameters:
    ///   - corporationId: 军团ID
    ///   - division: 部门编号
    /// - Returns: 钱包流水数组
    private func getCorpWalletJournalFromCache(corporationId: Int, division: Int) -> [[String:
            Any]]?
    {
        let filePath = getCorpJournalCacheFilePath(corporationId: corporationId, division: division)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            Logger.info(
                "军团钱包流水缓存文件不存在 - 军团ID: \(corporationId), 部门: \(division), 文件路径: \(filePath.path)")
            return nil
        }

        Logger.info(
            "开始读取军团钱包流水缓存文件 - 军团ID: \(corporationId), 部门: \(division), 文件路径: \(filePath.path)")

        do {
            let data = try Data(contentsOf: filePath)
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])

            if let journalEntries = jsonObject as? [[String: Any]] {
                Logger.info(
                    "成功从缓存文件读取军团钱包流水 - 军团ID: \(corporationId), 部门: \(division), 记录数量: \(journalEntries.count), 文件大小: \(data.count) bytes"
                )
                return journalEntries
            } else {
                Logger.error(
                    "军团钱包流水缓存文件格式不正确 - 军团ID: \(corporationId), 部门: \(division), 文件路径: \(filePath.path)"
                )
                return nil
            }
        } catch {
            Logger.error(
                "读取军团钱包流水缓存文件失败 - 军团ID: \(corporationId), 部门: \(division), 错误: \(error), 文件路径: \(filePath.path)"
            )
            return nil
        }
    }

    /// 保存军团钱包流水到缓存文件
    /// - Parameters:
    ///   - corporationId: 军团ID
    ///   - division: 部门编号
    ///   - entries: 日志条目
    /// - Returns: 是否保存成功
    private func saveCorpWalletJournalToCache(
        corporationId: Int, division: Int, entries: [[String: Any]]
    ) -> Bool {
        let filePath = getCorpJournalCacheFilePath(corporationId: corporationId, division: division)

        Logger.info(
            "开始保存军团钱包流水到缓存文件 - 军团ID: \(corporationId), 部门: \(division), 记录数量: \(entries.count), 文件路径: \(filePath.path)"
        )

        do {
            let jsonData = try JSONSerialization.data(
                withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]
            )
            try jsonData.write(to: filePath)
            Logger.info(
                "成功保存军团钱包流水到缓存文件 - 军团ID: \(corporationId), 部门: \(division), 记录数量: \(entries.count), 文件大小: \(jsonData.count) bytes, 文件路径: \(filePath.path)"
            )
            return true
        } catch {
            Logger.error(
                "保存军团钱包流水到缓存文件失败 - 军团ID: \(corporationId), 部门: \(division), 错误: \(error), 文件路径: \(filePath.path)"
            )
            return false
        }
    }

    /// 获取军团钱包流水（公开方法）
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - division: 部门编号
    ///   - forceRefresh: 是否强制刷新
    ///   - progressCallback: 加载进度回调
    /// - Returns: JSON格式的日志数据
    func getCorpWalletJournal(
        characterId: Int,
        division: Int,
        forceRefresh: Bool = false,
        progressCallback: ((WalletLoadingProgress) -> Void)? = nil
    ) async throws -> String? {
        // 1. 获取军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        Logger.info(
            "开始获取军团钱包流水 - 角色ID: \(characterId), 军团ID: \(corporationId), 部门: \(division), 强制刷新: \(forceRefresh)"
        )

        // 2. 如果强制刷新或缓存过期，则从网络获取
        if forceRefresh
            || isCorpJournalCacheExpired(corporationId: corporationId, division: division)
        {
            Logger.info("军团钱包流水缓存过期或需要强制刷新，从网络获取数据 - 军团ID: \(corporationId), 部门: \(division)")
            let journalData = try await fetchCorpJournalFromServer(
                characterId: characterId,
                corporationId: corporationId,
                division: division,
                progressCallback: progressCallback
            )
            if !saveCorpWalletJournalToCache(
                corporationId: corporationId, division: division, entries: journalData
            ) {
                Logger.error("保存军团钱包流水到缓存文件失败 - 军团ID: \(corporationId), 部门: \(division)")
            }
        } else {
            Logger.info("使用缓存文件中的军团钱包流水数据 - 军团ID: \(corporationId), 部门: \(division)")
        }

        // 3. 从缓存文件获取数据并返回
        if let results = getCorpWalletJournalFromCache(
            corporationId: corporationId, division: division
        ) {
            let jsonData = try JSONSerialization.data(
                withJSONObject: results, options: [.prettyPrinted, .sortedKeys]
            )
            Logger.info(
                "军团钱包流水数据处理完成 - 军团ID: \(corporationId), 部门: \(division), JSON大小: \(jsonData.count) bytes"
            )
            return String(data: jsonData, encoding: .utf8)
        }

        Logger.error("无法获取军团钱包流水数据 - 军团ID: \(corporationId), 部门: \(division)")
        return nil
    }

    /// 获取军团钱包交易记录（公开方法）
    func getCorpWalletTransactions(
        characterId: Int, division: Int, forceRefresh: Bool = false
    ) async throws -> String? {
        // 1. 获取军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        // 2. 检查数据库中是否有数据
        let checkQuery =
            "SELECT COUNT(*) as count FROM corp_wallet_transactions WHERE corporation_id = ? AND division = ?"
        let result = CharacterDatabaseManager.shared.executeQuery(
            checkQuery, parameters: [corporationId, division]
        )
        let isEmpty =
            if case let .success(rows) = result,
            let row = rows.first,
            let count = row["count"] as? Int64 {
                count == 0
            } else {
                true
            }

        // 3. 如果数据为空或强制刷新，则从网络获取
        if isEmpty || forceRefresh {
            Logger.debug("军团钱包交易记录为空或需要刷新，从网络获取数据")
            let transactionData = try await fetchCorpTransactionsFromServer(
                characterId: characterId, corporationId: corporationId, division: division
            )
            if !saveCorpWalletTransactionsToDB(
                corporationId: corporationId, division: division, entries: transactionData
            ) {
                Logger.error("保存军团钱包交易记录到数据库失败")
            }
        } else {
            Logger.debug("使用数据库中的军团钱包交易记录数据")
        }

        // 4. 从数据库获取数据并返回
        if let results = getCorpWalletTransactionsFromDB(
            corporationId: corporationId, division: division
        ) {
            let jsonData = try JSONSerialization.data(
                withJSONObject: results, options: [.prettyPrinted, .sortedKeys]
            )
            return String(data: jsonData, encoding: .utf8)
        }
        return nil
    }

    /// 从服务器获取军团交易记录
    private func fetchCorpTransactionsFromServer(
        characterId: Int, corporationId: Int, division: Int
    ) async throws -> [[String: Any]] {
        let urlString =
            "https://esi.evetech.net/corporations/\(corporationId)/wallets/\(division)/transactions/"
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

        Logger.info("成功获取军团钱包交易记录，共\(transactions.count)条记录")
        return transactions
    }

    /// 从数据库获取军团钱包交易记录
    private func getCorpWalletTransactionsFromDB(corporationId: Int, division: Int) -> [[String:
            Any]]?
    {
        let query = """
            SELECT transaction_id, client_id, date, is_buy, is_personal,
                   journal_ref_id, location_id, quantity, type_id,
                   unit_price, last_updated
            FROM corp_wallet_transactions 
            WHERE corporation_id = ? AND division = ?
            ORDER BY date DESC 
            LIMIT 1000
        """

        if case let .success(results) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [corporationId, division]
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

    /// 保存军团钱包交易记录到数据库
    private func saveCorpWalletTransactionsToDB(
        corporationId: Int, division: Int, entries: [[String: Any]]
    ) -> Bool {
        // 首先获取已存在的交易ID
        let checkQuery =
            "SELECT transaction_id FROM corp_wallet_transactions WHERE corporation_id = ? AND division = ?"
        guard
            case let .success(existingResults) = CharacterDatabaseManager.shared.executeQuery(
                checkQuery, parameters: [corporationId, division]
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

        if newEntries.isEmpty {
            Logger.info("无需新增交易记录")
            return true
        }

        // 开始事务
        let beginTransaction = "BEGIN TRANSACTION"
        _ = CharacterDatabaseManager.shared.executeQuery(beginTransaction)

        // 计算每批次的大小（每条记录12个参数）
        let batchSize = 500 // 每批次处理500条记录
        var success = true

        // 分批处理数据
        for batchStart in stride(from: 0, to: newEntries.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, newEntries.count)
            let currentBatch = Array(newEntries[batchStart ..< batchEnd])

            // 构建批量插入语句
            let placeholders = Array(
                repeating: "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", count: currentBatch.count
            ).joined(separator: ",")
            let insertSQL = """
                INSERT OR REPLACE INTO corp_wallet_transactions (
                    transaction_id, corporation_id, division, client_id, date, is_buy,
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
                    corporationId,
                    division,
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

            Logger.debug("执行批量插入军团钱包交易记录，批次大小: \(currentBatch.count), 参数数量: \(parameters.count)")

            // 执行批量插入
            if case let .error(message) = CharacterDatabaseManager.shared.executeQuery(
                insertSQL, parameters: parameters
            ) {
                Logger.error("批量插入军团钱包交易记录失败: \(message)")
                success = false
                break
            }
        }

        // 根据执行结果提交或回滚事务
        if success {
            _ = CharacterDatabaseManager.shared.executeQuery("COMMIT")
            Logger.info("新增\(newEntries.count)条军团钱包交易记录到数据库")
            return true
        } else {
            _ = CharacterDatabaseManager.shared.executeQuery("ROLLBACK")
            Logger.error("保存军团钱包交易记录失败，执行回滚")
            return false
        }
    }
}

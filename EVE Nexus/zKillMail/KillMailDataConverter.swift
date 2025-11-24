import Foundation

// ESI API 响应数据结构
struct ESIKillMail: Codable {
    let killmail_id: Int
    let killmail_time: String // ISO 8601 格式
    let solar_system_id: Int
    let victim: ESIVictim
    let attackers: [ESIAttacker]?
    let items: [ESIItem]?
}

struct ESIVictim: Codable {
    let character_id: Int?
    let corporation_id: Int
    let alliance_id: Int?
    let ship_type_id: Int
    let damage_taken: Int
    let items: [ESIItem]?
}

struct ESIAttacker: Codable {
    let character_id: Int?
    let corporation_id: Int?
    let alliance_id: Int?
    let ship_type_id: Int?
    let weapon_type_id: Int?
    let damage_done: Int
    let final_blow: Bool
}

struct ESIItem: Codable {
    let item_type_id: Int
    let flag: Int
    let quantity_dropped: Int?
    let quantity_destroyed: Int?
    let singleton: Int
}

// 战斗记录数据转换器
// 将 zkillboard 列表数据 + ESI 详情数据转换为 evetools 兼容格式
class KillMailDataConverter {
    static let shared = KillMailDataConverter()
    private let databaseManager = DatabaseManager.shared
    private let maxConcurrentRequests = 10

    private init() {}

    // 主要转换方法
    // 输入：zkillboard 列表数据数组
    // 输出：evetools 兼容格式的字典数组
    func convertZKBListToEvetoolsFormat(
        zkbEntries: [ZKBKillMailEntry]
    ) async throws -> [[String: Any]] {
        Logger.debug("开始转换 \(zkbEntries.count) 个 killmail 数据")

        // 步骤 1: 并发获取 ESI 详情（最多10个并发）
        let esiDetails = try await fetchESIDetailsConcurrently(zkbEntries: zkbEntries)
        Logger.debug("成功获取 \(esiDetails.count) 个 ESI 详情")

        // 步骤 2: 解析 ESI 数据，提取关键字段并收集所有需要查询的 ID
        var extractedData: [(killmailId: Int, zkb: ZKBInfo, esi: ESIKillMail)] = []
        var characterIds = Set<Int>()
        var corporationIds = Set<Int>()
        var allianceIds = Set<Int>()
        var shipTypeIds = Set<Int>()
        var solarSystemIds = Set<Int>()

        for zkbEntry in zkbEntries {
            guard let esiDetail = esiDetails[zkbEntry.killmail_id] else {
                Logger.warning("缺少 killmail_id \(zkbEntry.killmail_id) 的 ESI 详情，跳过")
                continue
            }

            extractedData.append((zkbEntry.killmail_id, zkbEntry.zkb, esiDetail))

            // 收集 ID
            if let charId = esiDetail.victim.character_id {
                characterIds.insert(charId)
            }
            corporationIds.insert(esiDetail.victim.corporation_id)
            if let allyId = esiDetail.victim.alliance_id {
                allianceIds.insert(allyId)
            }
            shipTypeIds.insert(esiDetail.victim.ship_type_id)
            solarSystemIds.insert(esiDetail.solar_system_id)
        }

        Logger.debug("收集到 - 角色: \(characterIds.count), 军团: \(corporationIds.count), 联盟: \(allianceIds.count), 飞船: \(shipTypeIds.count), 星系: \(solarSystemIds.count)")

        // 步骤 3: 批量获取名称
        let allEntityIds = Array(characterIds) + Array(corporationIds) + Array(allianceIds)
        let namesMap = try await UniverseAPI.shared.getNamesWithFallback(ids: allEntityIds)
        Logger.debug("成功获取 \(namesMap.count) 个实体名称")

        // 按类别分类名称
        var characterNames: [Int: String] = [:]
        var corporationNames: [Int: String] = [:]
        var allianceNames: [Int: String] = [:]

        for (id, (name, category)) in namesMap {
            switch category {
            case "character":
                characterNames[id] = name
            case "corporation":
                corporationNames[id] = name
            case "alliance":
                allianceNames[id] = name
            default:
                break
            }
        }

        // 步骤 4: 批量 SQL 查询飞船信息
        let shipInfo = getShipInfo(for: Array(shipTypeIds))
        Logger.debug("成功查询 \(shipInfo.count) 个飞船信息")

        // 步骤 5: 批量 SQL 查询星系信息
        let systemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: Array(solarSystemIds),
            databaseManager: databaseManager
        )
        Logger.debug("成功查询 \(systemInfoMap.count) 个星系信息")

        // 步骤 6: 转换为 evetools 格式
        var result: [[String: Any]] = []

        for (killmailId, zkb, esi) in extractedData {
            var killmailDict: [String: Any] = [:]

            // 基本信息
            killmailDict["_id"] = killmailId
            killmailDict["killmail_id"] = killmailId

            // 时间（将 ISO 8601 转换为 Unix 时间戳）
            if let timestamp = convertISO8601ToTimestamp(esi.killmail_time) {
                killmailDict["time"] = timestamp
            }

            // 价值（从 zkb 获取）
            killmailDict["sumV"] = Int(zkb.totalValue)

            // 受害者信息
            var victDict: [String: Any] = [:]

            // 飞船信息
            let shipId = esi.victim.ship_type_id
            if let shipInfo = shipInfo[shipId] {
                victDict["ship"] = [
                    "id": shipId,
                    "name": shipInfo.name,
                ]
            } else {
                victDict["ship"] = [
                    "id": shipId,
                    "name": "Unknown Ship",
                ]
            }

            // 角色信息
            if let charId = esi.victim.character_id,
               let charName = characterNames[charId]
            {
                victDict["char"] = [
                    "id": charId,
                    "name": charName,
                ]
            } else if let charId = esi.victim.character_id {
                victDict["char"] = [
                    "id": charId,
                    "name": "Character \(charId)",
                ]
            }

            // 军团信息
            let corpId = esi.victim.corporation_id
            if let corpName = corporationNames[corpId] {
                victDict["corp"] = [
                    "id": corpId,
                    "name": corpName,
                ]
            } else {
                victDict["corp"] = [
                    "id": corpId,
                    "name": "Corporation \(corpId)",
                ]
            }

            // 联盟信息
            if let allyId = esi.victim.alliance_id,
               allyId > 0
            {
                if let allyName = allianceNames[allyId] {
                    victDict["ally"] = [
                        "id": allyId,
                        "name": allyName,
                    ]
                } else {
                    victDict["ally"] = [
                        "id": allyId,
                        "name": "Alliance \(allyId)",
                    ]
                }
            }

            // 伤害
            victDict["dmg"] = esi.victim.damage_taken

            killmailDict["vict"] = victDict

            // 星系信息
            let systemId = esi.solar_system_id
            if let systemInfo = systemInfoMap[systemId] {
                killmailDict["sys"] = [
                    "id": systemId,
                    "name": systemInfo.systemName,
                    "region": systemInfo.regionName,
                    "ss": String(format: "%.1f", systemInfo.security),
                ]
            } else {
                killmailDict["sys"] = [
                    "id": systemId,
                    "name": "System \(systemId)",
                    "region": "Unknown",
                    "ss": "0.0",
                ]
            }

            // 保留原始 zkb 数据
            killmailDict["zkb"] = [
                "locationID": zkb.locationID,
                "hash": zkb.hash,
                "fittedValue": zkb.fittedValue,
                "droppedValue": zkb.droppedValue,
                "destroyedValue": zkb.destroyedValue,
                "totalValue": zkb.totalValue,
                "points": zkb.points,
                "npc": zkb.npc,
                "solo": zkb.solo,
                "awox": zkb.awox,
                "labels": zkb.labels,
            ]

            result.append(killmailDict)
        }

        Logger.success("成功转换 \(result.count) 个 killmail 数据")
        return result
    }

    // 并发获取 ESI 详情（最多10个并发）
    private func fetchESIDetailsConcurrently(
        zkbEntries: [ZKBKillMailEntry]
    ) async throws -> [Int: ESIKillMail] {
        var results: [Int: ESIKillMail] = [:]
        var pendingEntries = zkbEntries

        await withTaskGroup(of: (Int, ESIKillMail?).self) { group in
            // 初始添加并发数量的任务
            for _ in 0 ..< min(maxConcurrentRequests, pendingEntries.count) {
                if pendingEntries.isEmpty { break }

                let entry = pendingEntries.removeFirst()
                group.addTask {
                    do {
                        let esiDetail = try await self.fetchESIDetail(
                            killmailId: entry.killmail_id,
                            hash: entry.zkb.hash
                        )
                        return (entry.killmail_id, esiDetail)
                    } catch {
                        Logger.error("获取 ESI 详情失败 - killmail_id: \(entry.killmail_id), error: \(error)")
                        return (entry.killmail_id, nil)
                    }
                }
            }

            // 处理结果并添加新任务
            while let (killmailId, esiDetail) = await group.next() {
                if let detail = esiDetail {
                    results[killmailId] = detail
                }

                // 如果还有待处理的条目，添加新任务
                if !pendingEntries.isEmpty {
                    let entry = pendingEntries.removeFirst()
                    group.addTask {
                        do {
                            let esiDetail = try await self.fetchESIDetail(
                                killmailId: entry.killmail_id,
                                hash: entry.zkb.hash
                            )
                            return (entry.killmail_id, esiDetail)
                        } catch {
                            Logger.error("获取 ESI 详情失败 - killmail_id: \(entry.killmail_id), error: \(error)")
                            return (entry.killmail_id, nil)
                        }
                    }
                }
            }
        }

        return results
    }

    // 获取单个 ESI 详情（带缓存）
    private func fetchESIDetail(killmailId: Int, hash: String) async throws -> ESIKillMail {
        // 检查缓存
        let fileManager = FileManager.default
        let cacheDirectory = try fileManager.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        .appendingPathComponent("ESIKillmails", isDirectory: true)

        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        let cacheFile = cacheDirectory.appendingPathComponent("\(killmailId).json")

        // 尝试从缓存读取
        if fileManager.fileExists(atPath: cacheFile.path) {
            let data = try Data(contentsOf: cacheFile)
            if let esiDetail = try? JSONDecoder().decode(ESIKillMail.self, from: data) {
                Logger.debug("从缓存读取 ESI 详情 - killmail_id: \(killmailId)")
                return esiDetail
            }
        }

        // 从网络获取
        Logger.debug("从 ESI 获取详情 - killmail_id: \(killmailId)")
        let url = URL(
            string: "https://esi.evetech.net/killmails/\(killmailId)/\(hash)/?datasource=tranquility"
        )!

        let headers = [
            "Accept-Encoding": "gzip",
            "Accept": "application/json",
        ]

        let data = try await NetworkManager.shared.fetchData(
            from: url,
            headers: headers
        )

        let esiDetail = try JSONDecoder().decode(ESIKillMail.self, from: data)

        // 写入缓存
        try data.write(to: cacheFile)
        Logger.debug("ESI 详情已缓存 - killmail_id: \(killmailId)")

        return esiDetail
    }

    // 批量查询飞船信息
    private func getShipInfo(for typeIds: [Int]) -> [Int: (name: String, iconFileName: String)] {
        guard !typeIds.isEmpty else { return [:] }

        let uniqueIds = Array(Set(typeIds))
        let placeholders = String(repeating: "?,", count: uniqueIds.count).dropLast()
        let query = """
            SELECT type_id, name, icon_filename 
            FROM types 
            WHERE type_id IN (\(placeholders))
        """

        let result = databaseManager.executeQuery(query, parameters: uniqueIds)
        var infoMap: [Int: (name: String, iconFileName: String)] = [:]

        if case let .success(rows) = result {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let iconFileName = row["icon_filename"] as? String
                {
                    infoMap[typeId] = (name: name, iconFileName: iconFileName)
                }
            }
        }

        return infoMap
    }

    // 将 ISO 8601 字符串转换为 Unix 时间戳
    private func convertISO8601ToTimestamp(_ iso8601String: String) -> Int? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = isoFormatter.date(from: iso8601String) {
            return Int(date.timeIntervalSince1970)
        }

        // 尝试不带毫秒的格式
        let isoFormatter2 = ISO8601DateFormatter()
        isoFormatter2.formatOptions = [.withInternetDateTime]

        if let date = isoFormatter2.date(from: iso8601String) {
            return Int(date.timeIntervalSince1970)
        }

        Logger.error("无法解析时间字符串: \(iso8601String)")
        return nil
    }

    // 获取单个 killmail 的完整详情（仅从 ESI，不包含价值信息）
    // 输入：killmail_id 和 hash（从列表数据中获取）
    // 输出：evetools 兼容格式的字典
    func fetchKillMailDetailFromESI(
        killmailId: Int,
        hash: String
    ) async throws -> [String: Any] {
        Logger.debug("开始获取 killmail 详情 - killmail_id: \(killmailId)")

        // 从 ESI 获取详情
        let esiDetail = try await fetchESIDetail(killmailId: killmailId, hash: hash)

        // 收集所有需要查询的 ID
        var characterIds = Set<Int>()
        var corporationIds = Set<Int>()
        var allianceIds = Set<Int>()
        var shipTypeIds = Set<Int>()
        var solarSystemIds = Set<Int>()

        // 受害者信息
        if let charId = esiDetail.victim.character_id {
            characterIds.insert(charId)
        }
        corporationIds.insert(esiDetail.victim.corporation_id)
        if let allyId = esiDetail.victim.alliance_id {
            allianceIds.insert(allyId)
        }
        shipTypeIds.insert(esiDetail.victim.ship_type_id)
        solarSystemIds.insert(esiDetail.solar_system_id)

        // 物品信息
        if let items = esiDetail.victim.items {
            for item in items {
                shipTypeIds.insert(item.item_type_id)
            }
        }

        Logger.debug("收集到 - 角色: \(characterIds.count), 军团: \(corporationIds.count), 联盟: \(allianceIds.count), 物品: \(shipTypeIds.count), 星系: \(solarSystemIds.count)")

        // 批量获取名称
        let allEntityIds = Array(characterIds) + Array(corporationIds) + Array(allianceIds)
        let namesMap = try await UniverseAPI.shared.getNamesWithFallback(ids: allEntityIds)

        // 按类别分类名称
        var characterNames: [Int: String] = [:]
        var corporationNames: [Int: String] = [:]
        var allianceNames: [Int: String] = [:]

        for (id, (name, category)) in namesMap {
            switch category {
            case "character":
                characterNames[id] = name
            case "corporation":
                corporationNames[id] = name
            case "alliance":
                allianceNames[id] = name
            default:
                break
            }
        }

        // 批量查询星系信息
        let systemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: Array(solarSystemIds),
            databaseManager: databaseManager
        )

        // 转换为 evetools 格式
        var killmailDict: [String: Any] = [:]

        // 基本信息
        killmailDict["_id"] = killmailId
        killmailDict["killmail_id"] = killmailId

        // 时间
        if let timestamp = convertISO8601ToTimestamp(esiDetail.killmail_time) {
            killmailDict["time"] = timestamp
        }

        // 受害者信息
        var victDict: [String: Any] = [:]

        // 飞船信息（使用 Int 格式，兼容旧代码）
        let shipId = esiDetail.victim.ship_type_id
        victDict["ship"] = shipId

        // 角色信息（使用 Int 格式）
        if let charId = esiDetail.victim.character_id {
            victDict["char"] = charId
        }

        // 军团信息（使用 Int 格式）
        victDict["corp"] = esiDetail.victim.corporation_id

        // 联盟信息（使用 Int 格式）
        if let allyId = esiDetail.victim.alliance_id, allyId > 0 {
            victDict["ally"] = allyId
        }

        // 伤害
        victDict["dmg"] = esiDetail.victim.damage_taken

        // 物品信息（转换为 evetools 格式）
        if let items = esiDetail.victim.items {
            var itms: [[Int]] = []
            for item in items {
                // evetools 格式: [flag, type_id, quantity_dropped, quantity_destroyed, singleton]
                let dropped = item.quantity_dropped ?? 0
                let destroyed = item.quantity_destroyed ?? 0
                itms.append([item.flag, item.item_type_id, dropped, destroyed, item.singleton])
            }
            victDict["itms"] = itms
        }

        killmailDict["vict"] = victDict

        // 星系信息
        let systemId = esiDetail.solar_system_id
        if let systemInfo = systemInfoMap[systemId] {
            killmailDict["sys"] = [
                "id": systemId,
                "name": systemInfo.systemName,
                "region": systemInfo.regionName,
                "ss": String(format: "%.1f", systemInfo.security),
            ]
        } else {
            killmailDict["sys"] = [
                "id": systemId,
                "name": "System \(systemId)",
                "region": "Unknown",
                "ss": "0.0",
            ]
        }

        // 名称信息（用于详情页显示）
        var namesDict: [String: [String: String]] = [:]
        var charsDict: [String: String] = [:]
        var corpsDict: [String: String] = [:]
        var allysDict: [String: String] = [:]

        for (id, name) in characterNames {
            charsDict[String(id)] = name
        }
        for (id, name) in corporationNames {
            corpsDict[String(id)] = name
        }
        for (id, name) in allianceNames {
            allysDict[String(id)] = name
        }

        namesDict["chars"] = charsDict
        namesDict["corps"] = corpsDict
        namesDict["allys"] = allysDict
        killmailDict["names"] = namesDict

        Logger.success("成功获取 killmail 详情 - killmail_id: \(killmailId)")
        return killmailDict
    }
}

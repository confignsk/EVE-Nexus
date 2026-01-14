import Foundation

// MARK: - 数据模型

/// Fuzzwork 市场聚合响应模型
struct FuzzworkAggregateResponse: Codable {
    // 键是 type_id（字符串），值是 FuzzworkTypeData
    // 使用自定义解码来处理动态键
    let data: [Int: FuzzworkTypeData]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dictionary = try container.decode([String: FuzzworkTypeData].self)

        var result: [Int: FuzzworkTypeData] = [:]
        for (key, value) in dictionary {
            if let typeId = Int(key) {
                result[typeId] = value
            }
        }
        data = result
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var dictionary: [String: FuzzworkTypeData] = [:]
        for (key, value) in data {
            dictionary[String(key)] = value
        }
        try container.encode(dictionary)
    }
}

struct FuzzworkTypeData: Codable {
    let buy: FuzzworkPriceData
    let sell: FuzzworkPriceData
}

struct FuzzworkPriceData: Codable {
    let max: String
    let min: String
    let weightedAverage: String
    let median: String
    let stddev: String
    let volume: String
    let orderCount: String
    let percentile: String

    enum CodingKeys: String, CodingKey {
        case max
        case min
        case weightedAverage
        case median
        case stddev
        case volume
        case orderCount
        case percentile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 辅助函数：将值转换为 String（支持 String 和 Int）
        func stringValue(for key: CodingKeys) throws -> String {
            if let stringValue = try? container.decode(String.self, forKey: key) {
                return stringValue
            } else if let intValue = try? container.decode(Int.self, forKey: key) {
                return String(intValue)
            } else if let doubleValue = try? container.decode(Double.self, forKey: key) {
                return String(doubleValue)
            } else {
                // 如果都失败，返回 "0"
                return "0"
            }
        }

        max = try stringValue(for: .max)
        min = try stringValue(for: .min)
        weightedAverage = try stringValue(for: .weightedAverage)
        median = try stringValue(for: .median)
        stddev = try stringValue(for: .stddev)
        volume = try stringValue(for: .volume)
        orderCount = try stringValue(for: .orderCount)
        percentile = try stringValue(for: .percentile)
    }
}

// MARK: - Fuzzwork Market API

/// Fuzzwork 市场聚合数据 API
///
/// 提供从 Fuzzwork 获取市场聚合数据的功能
/// API 文档: https://market.fuzzwork.co.uk/aggregates/
class FuzzworkMarketAPI {
    static let shared = FuzzworkMarketAPI()
    private let baseURL = "https://market.fuzzwork.co.uk/aggregates/"

    private init() {}

    /// 检查 Fuzzwork API 是否可用
    ///
    /// 通过请求物品 34 的价格来测试 API 可用性，超时时间为 3 秒
    /// - Parameter regionId: 星域/空间站ID，默认 60003760（Jita 4-4 空间站）
    /// - Returns: 如果能在 3 秒内正常返回则为 true，否则为 false
    func FuzzAvailable(regionId: Int = 60_003_760) async -> Bool {
        do {
            // 使用 withThrowingTaskGroup 实现超时控制
            return try await withThrowingTaskGroup(of: Bool.self) { group in
                // 添加 API 请求任务
                group.addTask { [weak self] in
                    guard let self = self else { return false }
                    do {
                        // 请求物品 34 的价格
                        let result = try await self.fetchMarketAggregates(regionId: regionId, typeIds: [34])
                        // 如果成功获取到数据，返回 true
                        return result[34] != nil
                    } catch {
                        Logger.debug("Fuzzwork API 可用性检查失败: \(error.localizedDescription)")
                        return false
                    }
                }

                // 添加超时任务
                group.addTask {
                    try await Task.sleep(nanoseconds: 3_000_000_000) // 3 秒
                    return false
                }

                // 等待第一个完成的任务
                if let result = try await group.next() {
                    // 取消其他任务
                    group.cancelAll()
                    return result
                }
                return false
            }
        } catch {
            Logger.debug("Fuzzwork API 可用性检查异常: \(error.localizedDescription)")
            return false
        }
    }

    /// 获取市场聚合数据
    ///
    /// 从 Fuzzwork API 获取指定星域/空间站和物品的市场聚合数据
    /// 支持任意长度的 typeIds 列表，自动分段并发请求（每段最多 1000 个）
    /// - Parameters:
    ///   - regionId: 星域ID（如 10000002 表示 The Forge）或空间站ID（如 60003760 表示 Jita 4-4 空间站），默认 60003760（Jita 4-4 空间站）
    ///   - typeIds: 物品ID数组（不设长度上限）
    /// - Returns: [物品ID: (buy价格, sell价格)]，其中 buy 取 max，sell 取 min。如果某个物品没有数据则不会包含在结果中
    /// - Throws: 网络错误或解析错误（部分请求失败不影响其他请求的结果）
    func fetchMarketAggregates(regionId: Int = 60_003_760, typeIds: [Int]) async throws -> [Int: (buy: Double, sell: Double)] {
        guard !typeIds.isEmpty else {
            return [:]
        }

        // 先对 typeIds 进行排序，确保一致性
        let sortedTypeIds = typeIds.sorted()

        // 将排序后的 typeIds 分割成每段最多 1000 个的多个批次
        let batchSize = 1000
        let batches = sortedTypeIds.chunked(into: batchSize)

        Logger.info("Fuzzwork API 开始获取市场聚合数据 - 星域ID: \(regionId), 物品总数: \(typeIds.count), 分 \(batches.count) 个批次并发请求")

        let startTime = Date()
        var allResults: [Int: (buy: Double, sell: Double)] = [:]

        // 使用 TaskGroup 并发发送多个批次请求
        try await withThrowingTaskGroup(of: [Int: (buy: Double, sell: Double)].self) { group in
            // 为每个批次创建任务
            for (index, batch) in batches.enumerated() {
                group.addTask { [weak self] in
                    guard let self = self else { return [:] }
                    do {
                        let result = try await self.fetchSingleBatch(regionId: regionId, typeIds: batch, batchIndex: index + 1, totalBatches: batches.count)
                        return result
                    } catch {
                        Logger.error("Fuzzwork API 批次 \(index + 1)/\(batches.count) 请求失败: \(error.localizedDescription)")
                        return [:] // 返回空字典，不影响其他批次
                    }
                }
            }

            // 收集所有批次的结果
            for try await batchResult in group {
                allResults.merge(batchResult) { _, new in new } // 如果有重复的 key，使用新值
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        Logger.success("Fuzzwork API 完成 - 成功获取 \(allResults.count)/\(typeIds.count) 个物品的价格数据，耗时: \(String(format: "%.2f", duration))秒")

        return allResults
    }

    /// 获取单个批次的市场聚合数据（内部方法）
    ///
    /// - Parameters:
    ///   - regionId: 星域ID
    ///   - typeIds: 单个批次的物品ID数组（最多 1000 个）
    ///   - batchIndex: 批次索引（用于日志）
    ///   - totalBatches: 总批次数（用于日志）
    /// - Returns: [物品ID: (buy价格, sell价格)]
    /// - Throws: 网络错误或解析错误
    private func fetchSingleBatch(regionId: Int, typeIds: [Int], batchIndex: Int, totalBatches: Int) async throws -> [Int: (buy: Double, sell: Double)] {
        // 确保 typeIds 已排序（虽然传入的应该已经是排序的，但为了保险起见再次排序）
        let sortedTypeIds = typeIds.sorted()

        // 构建URL，将排序后的 typeIds 用逗号连接
        let typesString = sortedTypeIds.map { String($0) }.joined(separator: ",")
        guard let url = URL(string: "\(baseURL)?region=\(regionId)&types=\(typesString)") else {
            throw NSError(
                domain: "FuzzworkMarketAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无效的URL"]
            )
        }

        Logger.debug("Fuzzwork API 批次 \(batchIndex)/\(totalBatches) 请求: \(typeIds.count) 个物品")

        // 使用 NetworkManager 发送请求（自动记录日志）
        let data = try await NetworkManager.shared.fetchData(
            from: url,
            method: "GET",
            forceRefresh: false,
            timeouts: [3, 5, 10] // 设置超时时间：3秒、5秒、10秒
        )

        // 解码响应
        let aggregateResponse = try JSONDecoder().decode(FuzzworkAggregateResponse.self, from: data)
        Logger.debug("Fuzzwork API 批次 \(batchIndex)/\(totalBatches) 成功获取 \(aggregateResponse.data.count) 个物品的价格数据")

        // 转换为返回格式：buy 取 max，sell 取 min
        var result: [Int: (buy: Double, sell: Double)] = [:]
        for (typeId, typeData) in aggregateResponse.data {
            // buy 价格取 max
            guard let buyPrice = Double(typeData.buy.max), buyPrice > 0 else {
                continue
            }

            // sell 价格取 min
            guard let sellPrice = Double(typeData.sell.min), sellPrice > 0 else {
                continue
            }

            result[typeId] = (buy: buyPrice, sell: sellPrice)
        }

        return result
    }
}

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

    /// 获取市场聚合数据
    ///
    /// 从 Fuzzwork API 获取指定星域和物品的市场聚合数据
    /// - Parameters:
    ///   - regionId: 星域ID，例如 10000002（The Forge，Jita所在星域）
    ///   - typeIds: 物品ID数组
    /// - Returns: [物品ID: (buy价格, sell价格)]，其中 buy 取 max，sell 取 min。如果某个物品没有数据则不会包含在结果中
    /// - Throws: 网络错误或解析错误
    func fetchMarketAggregates(regionId: Int, typeIds: [Int]) async throws -> [Int: (buy: Double, sell: Double)] {
        guard !typeIds.isEmpty else {
            return [:]
        }

        // 构建URL，将typeIds用逗号连接
        let typesString = typeIds.map { String($0) }.joined(separator: ",")
        guard let url = URL(string: "\(baseURL)?region=\(regionId)&types=\(typesString)") else {
            throw NSError(
                domain: "FuzzworkMarketAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无效的URL"]
            )
        }

        Logger.debug("Fuzzwork API 请求: \(url.absoluteString)")

        // 发送请求
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw NSError(
                domain: "FuzzworkMarketAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "HTTP请求失败，状态码: \((response as? HTTPURLResponse)?.statusCode ?? -1)"]
            )
        }

        // 解码响应
        do {
            let aggregateResponse = try JSONDecoder().decode(FuzzworkAggregateResponse.self, from: data)
            Logger.debug("Fuzzwork API 成功获取 \(aggregateResponse.data.count) 个物品的价格数据")

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

            Logger.debug("Fuzzwork API 成功解析 \(result.count) 个物品的价格")
            return result
        } catch {
            Logger.error("Fuzzwork API 解码失败: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                Logger.debug("响应内容: \(responseString)")
            }
            throw NSError(
                domain: "FuzzworkMarketAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "数据解码失败: \(error.localizedDescription)"]
            )
        }
    }
}

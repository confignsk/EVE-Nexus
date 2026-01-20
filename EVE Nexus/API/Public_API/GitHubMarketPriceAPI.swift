import Foundation

// MARK: - 数据模型

/// 市场价格项数据模型（单个物品的价格信息）
struct MarketPriceValue: Codable {
    let b: Double? // buy 价格（最高买价），可选，缺失时表示0
    let s: Double? // sell 价格（最低卖价），可选，缺失时表示0
}

/// GitHub市场价格数据模型（字典格式，key为typeId字符串）
typealias GitHubMarketPriceData = [String: MarketPriceValue]

// MARK: - GitHub Market Price API

/// GitHub 市场价格数据 API
///
/// 提供从 GitHub Releases 获取 Jita 4-4 空间站市场价格数据的功能
/// 数据来源: https://github.com/EstamelGG/EVE_MarketPrice_Fetch
class GitHubMarketPriceAPI {
    static let shared = GitHubMarketPriceAPI()

    /// 市场价格数据下载URL
    private let downloadURL = "https://github.com/EstamelGG/EVE_MarketPrice_Fetch/releases/download/market-prices/market_prices.json"
    private let cacheTimeoutInterval: TimeInterval = 0.5 * 60 * 60 // 0.5小时缓存有效期（GitHub数据）
    private let esiCacheTimeoutInterval: TimeInterval = 4 * 60 * 60 // 4小时缓存有效期（ESI构造数据）

    // ESI相关配置
    private let targetRegionID = 10_000_002 // The Forge
    private let targetSystemID = 30_000_142 // Jita
    private let esiBaseURL = "https://esi.evetech.net/markets"

    // Documents目录路径
    private var documentsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    // 缓存目录路径
    private var cacheDirectory: URL {
        let directory = documentsDirectory.appendingPathComponent("github_market_cache")

        // 确保目录存在
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                Logger.debug("创建 github_market_cache 目录: \(directory.path)")
            } catch {
                Logger.error("创建 github_market_cache 目录失败: \(error)")
            }
        }

        return directory
    }

    // 缓存文件路径（GitHub数据）
    private var cacheFilePath: URL {
        return cacheDirectory.appendingPathComponent("market_prices.json")
    }

    // ESI构造数据的缓存文件路径
    private var esiCacheFilePath: URL {
        return cacheDirectory.appendingPathComponent("market_prices_esi.json")
    }

    private init() {}

    /// 获取市场价格数据
    ///
    /// 优先从 GitHub 获取，如果失败则从 ESI 构造
    /// - Parameters:
    ///   - typeIds: 物品ID数组（可选，如果为空则返回所有数据）
    ///   - forceRefresh: 是否强制刷新缓存，默认false
    /// - Returns: [物品ID: (buy价格, sell价格)]，如果某个物品没有数据则不会包含在结果中
    /// - Throws: 网络错误或解析错误
    func fetchMarketPrices(
        typeIds: [Int]? = nil,
        forceRefresh: Bool = false
    ) async throws -> [Int: (buy: Double, sell: Double)] {
        // 如果不是强制刷新，尝试从缓存读取（优先GitHub缓存，其次ESI缓存）
        if !forceRefresh {
            // 先尝试GitHub缓存
            do {
                if let cachedData = try await loadCachedData() {
                    Logger.debug("从GitHub缓存加载市场价格数据，物品数量: \(cachedData.count)")
                    return filterPrices(cachedData, typeIds: typeIds)
                }
            } catch {
                Logger.debug("GitHub缓存不可用: \(error.localizedDescription)")
            }

            // 再尝试ESI缓存
            do {
                if let cachedData = try await loadESICachedData() {
                    Logger.debug("从ESI缓存加载市场价格数据，物品数量: \(cachedData.count)")
                    return filterPrices(cachedData, typeIds: typeIds)
                }
            } catch {
                Logger.debug("ESI缓存不可用: \(error.localizedDescription)")
            }
        }

        // 从 GitHub 获取最新数据
        Logger.info("开始从 GitHub 获取市场价格数据")
        let startTime = Date()

        do {
            let result = try await fetchFromURL(downloadURL)
            let duration = Date().timeIntervalSince(startTime)
            Logger.success("成功从GitHub获取市场价格数据，物品数量: \(result.count)，耗时: \(String(format: "%.2f", duration))秒")
            return filterPrices(result, typeIds: typeIds)
        } catch {
            Logger.warning("从GitHub获取失败，尝试从ESI构造: \(error.localizedDescription)")

            // GitHub失败，尝试从ESI构造
            do {
                let result = try await fetchFromESI()
                let duration = Date().timeIntervalSince(startTime)
                Logger.success("成功从ESI构造市场价格数据，物品数量: \(result.count)，耗时: \(String(format: "%.2f", duration))秒")
                return filterPrices(result, typeIds: typeIds)
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                Logger.error("所有获取方式均失败，耗时: \(String(format: "%.2f", duration))秒")
                throw NSError(
                    domain: "GitHubMarketPriceAPI",
                    code: -5,
                    userInfo: [
                        NSLocalizedDescriptionKey: "无法获取市场价格数据：GitHub和ESI均失败",
                        NSUnderlyingErrorKey: error,
                    ]
                )
            }
        }
    }

    /// 从指定URL下载并解析市场价格数据
    ///
    /// 使用5秒超时，总共3次重试（5秒，5秒，5秒）
    /// - Parameter urlString: 下载URL字符串
    /// - Returns: 解析后的价格数据
    /// - Throws: 网络错误或解析错误
    private func fetchFromURL(_ urlString: String) async throws -> [Int: (buy: Double, sell: Double)] {
        guard let downloadURL = URL(string: urlString) else {
            throw NSError(
                domain: "GitHubMarketPriceAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无效的下载 URL: \(urlString)"]
            )
        }

        let marketData = try await NetworkManager.shared.fetchData(
            from: downloadURL,
            method: "GET",
            forceRefresh: false,
            timeouts: [5] // 5秒超时，总共1次重试
        )

        // 解析数据
        let result = try parseMarketPriceData(from: marketData)

        // 保存到缓存
        await saveToCache(data: marketData)

        return result
    }

    /// 解析市场价格数据（从JSON数据转换为字典格式）
    ///
    /// - Parameter data: JSON数据
    /// - Returns: [物品ID: (buy价格, sell价格)]，只包含有有效价格的数据（b > 0 或 s > 0）
    /// - Throws: 解析错误
    private func parseMarketPriceData(from data: Data) throws -> [Int: (buy: Double, sell: Double)] {
        let marketPriceDict = try JSONDecoder().decode(GitHubMarketPriceData.self, from: data)

        var result: [Int: (buy: Double, sell: Double)] = [:]
        for (typeIdString, priceValue) in marketPriceDict {
            // 将字符串类型的typeId转换为Int
            guard let typeId = Int(typeIdString) else {
                Logger.warning("无法解析typeId: \(typeIdString)，跳过")
                continue
            }

            // 处理缺失字段：如果b或s为nil，则默认为0
            let buyPrice = priceValue.b ?? 0.0
            let sellPrice = priceValue.s ?? 0.0

            // 只包含有有效价格的数据（至少有一个价格大于0）
            if buyPrice > 0 || sellPrice > 0 {
                result[typeId] = (buy: buyPrice, sell: sellPrice)
            }
        }

        return result
    }

    /// 过滤价格数据（如果指定了 typeIds）
    private func filterPrices(
        _ prices: [Int: (buy: Double, sell: Double)],
        typeIds: [Int]?
    ) -> [Int: (buy: Double, sell: Double)] {
        guard let typeIds = typeIds, !typeIds.isEmpty else {
            return prices
        }

        var filtered: [Int: (buy: Double, sell: Double)] = [:]
        for typeId in typeIds {
            if let price = prices[typeId] {
                filtered[typeId] = price
            }
        }
        return filtered
    }

    /// 从缓存加载数据
    ///
    /// - Returns: 缓存的价格数据，如果缓存不存在或已过期则返回nil
    /// - Throws: 文件读取错误或解析错误（如果解析失败，调用方会重新下载）
    private func loadCachedData() async throws -> [Int: (buy: Double, sell: Double)]? {
        let filePath = cacheFilePath

        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            Logger.debug("缓存文件不存在")
            return nil
        }

        // 检查文件修改时间
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let timeSinceModification = Date().timeIntervalSince(modificationDate)
                if timeSinceModification > cacheTimeoutInterval {
                    Logger.debug("缓存已过期（\(Int(timeSinceModification / 60)) 分钟前），需要重新获取")
                    return nil
                }
            }
        } catch {
            Logger.warning("无法读取缓存文件属性: \(error.localizedDescription)")
            return nil
        }

        // 读取并解析缓存文件
        // 如果解析失败，抛出错误以便调用方重新下载
        let data = try Data(contentsOf: filePath)
        let result = try parseMarketPriceData(from: data)

        Logger.debug("从缓存 \(filePath) 加载了 \(result.count) 个物品的价格数据")
        return result
    }

    /// 保存数据到缓存
    private func saveToCache(data: Data) async {
        let filePath = cacheFilePath

        do {
            try data.write(to: filePath)
            Logger.debug("市场价格数据已保存到缓存: \(filePath.path)")
        } catch {
            Logger.error("保存缓存文件失败: \(error.localizedDescription)")
        }
    }

    // MARK: - ESI 构造方法

    /// 从 ESI 获取订单并构造市场价格数据
    ///
    /// - Returns: 解析后的价格数据
    /// - Throws: 网络错误或解析错误
    private func fetchFromESI() async throws -> [Int: (buy: Double, sell: Double)] {
        Logger.info("开始从 ESI 获取市场订单数据")

        // 1. 获取所有页面的订单数据
        let allOrders = try await fetchAllOrdersFromESI()
        Logger.debug("从 ESI 获取到 \(allOrders.count) 条订单")

        // 2. 处理订单数据
        let processedData = processOrdersFromESI(allOrders)
        Logger.debug("处理后的价格数据包含 \(processedData.count) 种物品")

        // 3. 转换为返回格式
        var result: [Int: (buy: Double, sell: Double)] = [:]
        for (typeIdString, priceValue) in processedData {
            guard let typeId = Int(typeIdString) else {
                Logger.warning("无法解析typeId: \(typeIdString)，跳过")
                continue
            }

            let buyPrice = priceValue.b ?? 0.0
            let sellPrice = priceValue.s ?? 0.0

            if buyPrice > 0 || sellPrice > 0 {
                result[typeId] = (buy: buyPrice, sell: sellPrice)
            }
        }

        // 4. 保存到ESI缓存
        await saveESIToCache(data: processedData)

        return result
    }

    /// 从 ESI 获取所有页面的订单数据
    ///
    /// - Returns: 所有订单数据
    /// - Throws: 网络错误
    private func fetchAllOrdersFromESI() async throws -> [MarketOrder] {
        // 构建基础URL
        let baseURL = URL(string: "\(esiBaseURL)/\(targetRegionID)/orders?order_type=all&datasource=tranquility")!

        // 使用 NetworkManager 的分页获取功能
        let allOrders = try await NetworkManager.shared.fetchPaginatedDataPublic(
            from: baseURL,
            maxConcurrentPages: 50, // 使用50个并发请求
            decoder: { data in
                try JSONDecoder().decode([MarketOrder].self, from: data)
            },
            progressCallback: { currentPage, totalPages in
                Logger.debug("ESI订单获取进度: \(currentPage)/\(totalPages)")
            }
        )

        return allOrders
    }

    /// 处理 ESI 订单数据，过滤并计算价格
    ///
    /// - Parameter orders: 订单列表
    /// - Returns: 处理后的数据字典，格式与GitHub数据一致
    private func processOrdersFromESI(_ orders: [MarketOrder]) -> GitHubMarketPriceData {
        // 1. 过滤 system_id = targetSystemID 的订单
        let filteredOrders = orders.filter { $0.systemId == targetSystemID }
        Logger.debug("过滤后剩余 \(filteredOrders.count) 条订单（system_id=\(targetSystemID)）")

        // 2. 按 type_id 分组
        var ordersByType: [Int: [MarketOrder]] = [:]
        for order in filteredOrders {
            ordersByType[order.typeId, default: []].append(order)
        }

        Logger.debug("共 \(ordersByType.count) 种不同的 type_id")

        // 3. 对每个 type_id，计算最高买价和最低卖价
        var result: GitHubMarketPriceData = [:]

        for (typeId, typeOrders) in ordersByType {
            let buyOrders = typeOrders.filter { $0.isBuyOrder }
            let sellOrders = typeOrders.filter { !$0.isBuyOrder }

            // 计算最高买价（买单中价格最高的）
            let maxBuyPrice = buyOrders.map { $0.price }.max() ?? 0.0

            // 计算最低卖价（卖单中价格最低的）
            let minSellPrice = sellOrders.map { $0.price }.min() ?? 0.0

            // 如果两者都为0，则跳过该条目
            if maxBuyPrice == 0 && minSellPrice == 0 {
                continue
            }

            // 构建结果对象，只包含非0的字段
            let buyPrice: Double? = maxBuyPrice > 0 ? maxBuyPrice : nil
            let sellPrice: Double? = minSellPrice > 0 ? minSellPrice : nil
            let item = MarketPriceValue(b: buyPrice, s: sellPrice)

            // 将typeId转换为字符串作为key
            result[String(typeId)] = item
        }

        return result
    }

    /// 从ESI缓存加载数据
    ///
    /// - Returns: 缓存的价格数据，如果缓存不存在或已过期则返回nil
    /// - Throws: 文件读取错误或解析错误
    private func loadESICachedData() async throws -> [Int: (buy: Double, sell: Double)]? {
        let filePath = esiCacheFilePath

        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            Logger.debug("ESI缓存文件不存在")
            return nil
        }

        // 检查文件修改时间
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let timeSinceModification = Date().timeIntervalSince(modificationDate)
                if timeSinceModification > esiCacheTimeoutInterval {
                    Logger.debug("ESI缓存已过期（\(Int(timeSinceModification / 60)) 分钟前），需要重新获取")
                    return nil
                }
            }
        } catch {
            Logger.warning("无法读取ESI缓存文件属性: \(error.localizedDescription)")
            return nil
        }

        // 读取并解析缓存文件
        let data = try Data(contentsOf: filePath)
        let result = try parseMarketPriceData(from: data)

        Logger.debug("从ESI缓存 \(filePath) 加载了 \(result.count) 个物品的价格数据")
        return result
    }

    /// 保存ESI数据到缓存
    ///
    /// - Parameter data: 要保存的数据字典
    private func saveESIToCache(data: GitHubMarketPriceData) async {
        let filePath = esiCacheFilePath

        do {
            let jsonData = try JSONEncoder().encode(data)
            try jsonData.write(to: filePath)
            Logger.debug("ESI市场价格数据已保存到缓存: \(filePath.path)")
        } catch {
            Logger.error("保存ESI缓存文件失败: \(error.localizedDescription)")
        }
    }
}

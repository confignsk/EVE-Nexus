import Foundation

/// 市场价格结构体
struct MarketPriceData {
    let adjustedPrice: Double // 调整价格
    let averagePrice: Double // 平均价格
}

/// 市场价格工具类
enum MarketPriceUtil {
    /// 获取多个物品的市场价格数据（包含调整价格和平均价格）
    /// - Parameter typeIds: 物品ID数组
    /// - Returns: [物品ID: 价格数据] 的字典，如果某个物品没有价格数据则不会包含在结果中
    /// - 会联网获取市场价格，如果获取失败，会尝试重新获取
    static func getMarketPrices(typeIds: [Int], forceRefresh: Bool = false) async -> [Int:
        MarketPriceData]
    {
        do {
            // 先尝试从缓存获取价格
            let prices = try await MarketPricesAPI.shared.fetchMarketPrices(
                forceRefresh: forceRefresh)
            Logger.debug("从缓存获取市场价格数据，总条目数: \(prices.count)")

            // 创建结果字典
            var result: [Int: MarketPriceData] = [:]

            // 从缓存中查找价格
            for price in prices {
                if typeIds.contains(price.type_id) {
                    // 如果adjusted_price不存在则设为0，如果average_price不存在则设为0
                    let adjustedPrice = price.adjusted_price ?? 0.0
                    let averagePrice = price.average_price ?? 0.0

                    result[price.type_id] = MarketPriceData(
                        adjustedPrice: adjustedPrice,
                        averagePrice: averagePrice
                    )
                }
            }

            return result
        } catch {
            Logger.error("获取市场价格失败: \(error)")
            return [:]
        }
    }

    /// 获取多个物品的实际市场卖出价格（基于当前市场订单）
    /// - Parameters:
    ///   - typeIds: 物品ID数组
    ///   - forceRefresh: 是否强制刷新
    /// - Returns: [物品ID: 卖价] 的字典，格式与getMarketPrices一致
    static func getMarketOrderPrices(typeIds: [Int], forceRefresh: Bool = false) async -> [Int:
        Double]
    {
        // 默认使用吉他(Jita)市场
        let regionID = 10_000_002 // The Forge (Jita所在星域)
        let systemID = 30_000_142 // Jita星系ID

        var result: [Int: Double] = [:]

        // 创建任务组并发获取市场订单
        var marketOrders: [Int: [MarketOrder]] = [:]
        let concurrency = max(1, min(10, typeIds.count))

        await withTaskGroup(of: (Int, [MarketOrder])?.self) { group in
            var pendingItems = Array(typeIds)

            // 初始添加并发数量的任务
            for _ in 0 ..< min(concurrency, pendingItems.count) {
                if let typeID = pendingItems.popLast() {
                    group.addTask {
                        do {
                            let orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                                typeID: typeID,
                                regionID: regionID,
                                forceRefresh: forceRefresh
                            )
                            return (typeID, orders)
                        } catch {
                            Logger.error("加载市场订单失败: \(error)")
                            return nil
                        }
                    }
                }
            }

            // 处理结果并添加新任务
            while let taskResult = await group.next() {
                if let (typeID, orders) = taskResult {
                    marketOrders[typeID] = orders
                }

                // 如果还有待处理的物品，添加新任务
                if let typeID = pendingItems.popLast() {
                    group.addTask {
                        do {
                            let orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                                typeID: typeID,
                                regionID: regionID,
                                forceRefresh: forceRefresh
                            )
                            return (typeID, orders)
                        } catch {
                            Logger.error("加载市场订单失败: \(error)")
                            return nil
                        }
                    }
                }
            }
        }

        // 计算每个物品的价格，只关注卖单价格
        for typeID in typeIds {
            guard let orders = marketOrders[typeID], !orders.isEmpty else {
                continue
            }

            // 只过滤卖单
            let sellOrders = orders.filter { !$0.isBuyOrder && $0.systemId == systemID }
                .sorted(by: { $0.price < $1.price }) // 卖单从低到高排序

            // 获取最低卖价
            if let lowestSellPrice = sellOrders.first?.price, lowestSellPrice > 0 {
                result[typeID] = lowestSellPrice
            }
        }

        return result
    }
}

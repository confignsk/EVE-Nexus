import Foundation

/// 市场价格数据结构体
///
/// 包含CCP官方提供的两种价格估算：
/// - adjustedPrice: 调整价格，用于工业税费、合同抵押等游戏机制计算
/// - averagePrice: 平均价格，用于一般价值估算
struct MarketPriceData {
    let adjustedPrice: Double // 调整价格（用于税费计算）
    let averagePrice: Double // 平均价格（用于价值估算）
}

/// 市场价格工具类 - 提供EIV价格和便捷的市场价格查询
///
/// 价格数据来源：
/// - EIV价格：来自 https://esi.evetech.net/markets/prices/（CCP官方统计数据）
/// - 市场订单价格：来自实时市场订单数据
///
/// 使用场景：
/// - 精炼税费计算：使用 adjustedPrice
/// - 合同估价：使用实时订单价格
/// - 技能注入器价格：使用Jita卖价
enum MarketPriceUtil {
    /// 获取多个物品的EIV价格数据（CCP官方估价）
    ///
    /// 使用场景：
    /// - 精炼税费计算：使用 adjustedPrice 计算税额
    /// - 工业成本估算：使用 adjustedPrice 作为基础成本
    /// - 合同抵押计算：使用 adjustedPrice
    ///
    /// 示例：
    /// ```swift
    /// // 获取精炼产出材料的EIV价格，用于计算税费
    /// let eivPrices = await MarketPriceUtil.getMarketPrices(
    ///     typeIds: [34, 35, 36]  // 三钛合金、类晶体胶矿、类银超金属
    /// )
    ///
    /// // 计算税额
    /// var totalEIV = 0.0
    /// for (materialID, quantity) in refineryOutputs {
    ///     if let priceData = eivPrices[materialID] {
    ///         totalEIV += priceData.adjustedPrice * Double(quantity)
    ///     }
    /// }
    /// let taxAmount = totalEIV * (taxRate / 100.0)
    /// ```
    ///
    /// 数据特点：
    /// - 数据来源：CCP官方统计，每日更新
    /// - 缓存时间：8小时
    /// - 覆盖范围：几乎所有可交易物品
    ///
    /// - Parameters:
    ///   - typeIds: 物品ID数组
    ///   - forceRefresh: 是否强制刷新缓存，默认false（使用8小时缓存）
    /// - Returns: [物品ID: 价格数据]，如果某个物品没有价格数据则不会包含在结果中
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

    /// 获取多个物品的Jita市场卖出价格（实时订单数据）- 便捷方法
    ///
    /// 使用场景：
    /// - 技能注入器价格查询：获取大型/小型注入器的Jita卖价
    /// - 装配价格计算：计算整套装配在Jita的卖价
    /// - 物品属性对比：显示多个物品的Jita市场价格
    ///
    /// 示例：
    /// ```swift
    /// // 场景1: 获取技能注入器价格
    /// let prices = await MarketPriceUtil.getMarketOrderPrices(
    ///     typeIds: [40520, 45635]  // 大型、小型注入器
    /// )
    /// let largePrice = prices[40520]  // 大型注入器Jita卖价
    /// let smallPrice = prices[45635]  // 小型注入器Jita卖价
    ///
    /// // 场景2: 计算装配价格
    /// let fitItemIds = [12076, 2048, 519]  // 装配中的模块ID
    /// let itemPrices = await MarketPriceUtil.getMarketOrderPrices(typeIds: fitItemIds)
    /// let totalValue = itemPrices.values.reduce(0, +)
    /// ```
    ///
    /// 数据特点：
    /// - 固定市场：Jita星域（10000002）的Jita星系（30000142）
    /// - 订单类型：只返回卖单的最低价格
    /// - 缓存时间：3小时（通过MarketOrdersAPI）
    /// - 实时性强：反映当前市场实际价格
    ///
    /// 注意：
    /// - 如果需要其他星域/星系，请使用 MarketOrdersUtil.loadOrders() + calculatePrice()
    /// - 如果需要买单价格，请使用 MarketOrdersUtil.calculatePrice()
    ///
    /// - Parameters:
    ///   - typeIds: 物品ID数组
    ///   - forceRefresh: 是否强制刷新缓存，默认false（使用3小时缓存）
    /// - Returns: [物品ID: Jita卖价]，无订单的物品不会包含在结果中
    static func getJitaOrderPrices(typeIds: [Int], forceRefresh: Bool = false) async -> [Int:
        Double]
    {
        // 默认使用Jita市场
        let regionID = 10_000_002 // The Forge (Jita所在星域)
        let systemID = 30_000_142 // Jita星系ID
        let stationID = 60_003_760 // Jita 4-4 空间站 ID

        // 使用通用工具类并发获取市场订单
        let marketOrders = await MarketOrdersUtil.loadRegionOrders(
            typeIds: typeIds,
            regionID: regionID,
            forceRefresh: forceRefresh
        )

        // 使用函数式编程批量计算价格
        return marketOrders.compactMapValues { orders in
            let price = MarketOrdersUtil.calculatePrice(
                from: orders,
                orderType: .sell,
                quantity: nil,
                systemId: systemID,
                stationID: stationID
            ).price
            return (price ?? 0) > 0 ? price : nil
        }
    }
}

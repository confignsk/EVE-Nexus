import SwiftUI

// MARK: - 建筑市场详情视图

struct StructureMarketDetailView: View {
    let structure: MarketStructure

    @State private var cacheStatus: StructureMarketManager.CacheStatus = .noData
    @State private var lastUpdateDate: Date? = nil
    @State private var refreshStatus: CacheRefreshStatus = .invalidRefreshable
    @State private var isLoadingOrders = false
    @State private var structureOrdersProgress: StructureOrdersProgress? = nil
    @State private var updateTimer: Timer? = nil
    @State private var buyOrdersCount: Int? = nil
    @State private var sellOrdersCount: Int? = nil
    @State private var itemTypesCount: Int? = nil
    @StateObject private var allianceIconLoader = AllianceIconLoader()
    @State private var sovereigntyData: [SovereigntyData] = []
    @State private var systemAllianceMap: [Int: Int] = [:] // 星系ID -> 联盟ID
    @State private var topSellItems: [ItemOrderInfo] = [] // 最多卖单的物品（Top 3）
    @State private var topBuyItems: [ItemOrderInfo] = [] // 最多买单的物品（Top 3）

    // 刷新冷却时间：20分钟
    private let refreshCooldownInterval: TimeInterval = 20 * 60 // 20分钟

    var body: some View {
        List {
            // Section 1: 建筑基本信息
            Section {
                // 行1: 建筑图标、名称、地点
                StructureInfoRowView(
                    structure: structure,
                    lastUpdateDate: lastUpdateDate,
                    allianceIconLoader: allianceIconLoader,
                    systemAllianceMap: systemAllianceMap,
                    isLoading: isLoadingOrders,
                    progress: structureOrdersProgress
                )

                // 订单统计信息
                if buyOrdersCount != nil || sellOrdersCount != nil || itemTypesCount != nil {
                    // 买单总数
                    if let buyCount = buyOrdersCount {
                        if buyCount > 0 {
                            NavigationLink(destination: MarketOrdersVisualizationView(
                                structureId: Int64(structure.structureId),
                                characterId: structure.characterId,
                                orderType: .buy,
                                title: NSLocalizedString("Structure_Market_Buy_Orders_Count", comment: "买单总数")
                            )) {
                                OrdersStatisticsRowView(
                                    title: NSLocalizedString("Structure_Market_Buy_Orders_Count", comment: "买单总数"),
                                    value: "\(buyCount)"
                                )
                            }
                        } else {
                            OrdersStatisticsRowView(
                                title: NSLocalizedString("Structure_Market_Buy_Orders_Count", comment: "买单总数"),
                                value: "\(buyCount)"
                            )
                        }
                    }

                    // 卖单总数
                    if let sellCount = sellOrdersCount {
                        if sellCount > 0 {
                            NavigationLink(destination: MarketOrdersVisualizationView(
                                structureId: Int64(structure.structureId),
                                characterId: structure.characterId,
                                orderType: .sell,
                                title: NSLocalizedString("Structure_Market_Sell_Orders_Count", comment: "卖单总数")
                            )) {
                                OrdersStatisticsRowView(
                                    title: NSLocalizedString("Structure_Market_Sell_Orders_Count", comment: "卖单总数"),
                                    value: "\(sellCount)"
                                )
                            }
                        } else {
                            OrdersStatisticsRowView(
                                title: NSLocalizedString("Structure_Market_Sell_Orders_Count", comment: "卖单总数"),
                                value: "\(sellCount)"
                            )
                        }
                    }

                    // 物品类别
                    if let typesCount = itemTypesCount {
                        OrdersStatisticsRowView(
                            title: NSLocalizedString("Structure_Market_Item_Types_Count", comment: "物品类别"),
                            value: "\(typesCount)"
                        )
                    }
                }
            }

            // Section 2: 最多卖单
            if !topSellItems.isEmpty {
                Section(header: Text(NSLocalizedString("Structure_Market_Top_Sell_Orders", comment: "最多卖单"))) {
                    ForEach(topSellItems) { item in
                        NavigationLink(destination: StructureItemOrdersView(
                            structureId: Int64(structure.structureId),
                            characterId: structure.characterId,
                            itemID: item.typeId,
                            itemName: item.name,
                            orderType: item.orderType,
                            databaseManager: DatabaseManager.shared
                        )) {
                            HStack(spacing: 12) {
                                // 物品图标
                                IconManager.shared.loadImage(for: item.iconFileName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)

                                // 物品名称
                                Text(item.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .contextMenu {
                                        Button {
                                            UIPasteboard.general.string = item.name
                                        } label: {
                                            Label(
                                                NSLocalizedString("Misc_Copy_Item_Name", comment: ""),
                                                systemImage: "doc.on.doc"
                                            )
                                        }
                                    }

                                Spacer()

                                // 订单数
                                Text("\(item.orderCount)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }

            // Section 3: 最多买单
            if !topBuyItems.isEmpty {
                Section(header: Text(NSLocalizedString("Structure_Market_Top_Buy_Orders", comment: "最多买单"))) {
                    ForEach(topBuyItems) { item in
                        NavigationLink(destination: StructureItemOrdersView(
                            structureId: Int64(structure.structureId),
                            characterId: structure.characterId,
                            itemID: item.typeId,
                            itemName: item.name,
                            orderType: item.orderType,
                            databaseManager: DatabaseManager.shared
                        )) {
                            HStack(spacing: 12) {
                                // 物品图标
                                IconManager.shared.loadImage(for: item.iconFileName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)

                                // 物品名称
                                Text(item.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .contextMenu {
                                        Button {
                                            UIPasteboard.general.string = item.name
                                        } label: {
                                            Label(
                                                NSLocalizedString("Misc_Copy_Item_Name", comment: ""),
                                                systemImage: "doc.on.doc"
                                            )
                                        }
                                    }

                                Spacer()

                                // 订单数
                                Text("\(item.orderCount)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Structure_Market_Orders_Overview", comment: "建筑订单总览"))
        .navigationBarTitleDisplayMode(.large)
        .conditionalRefreshable(isEnabled: refreshStatus != .validNotRefreshable) {
            // 下拉刷新，检查冷却时间
            await handlePullToRefresh()
        }
        .onAppear {
            updateCacheStatus()
            // 加载本地订单统计信息
            Task {
                await loadLocalOrdersStatistics()
                await loadTopOrderItems()
            }
            // 加载主权数据
            Task {
                await loadSovereigntyData()
            }
            // 启动定时器，每分钟更新一次状态（用于检查冷却期是否已过）
            updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                updateCacheStatus()
            }
        }
        .onDisappear {
            updateTimer?.invalidate()
            updateTimer = nil
            allianceIconLoader.cancelAllTasks()
        }
    }

    // 更新缓存状态
    private func updateCacheStatus() {
        cacheStatus = StructureMarketManager.getCacheStatus(
            structureId: Int64(structure.structureId)
        )
        lastUpdateDate = StructureMarketManager.getLocalOrdersModificationDate(
            structureId: Int64(structure.structureId)
        )
        refreshStatus = calculateRefreshStatus()
    }

    // 计算刷新状态
    private func calculateRefreshStatus() -> CacheRefreshStatus {
        switch cacheStatus {
        case .valid:
            // 缓存有效，检查是否超过冷却期
            if let updateDate = lastUpdateDate {
                let timeSinceUpdate = Date().timeIntervalSince(updateDate)
                if timeSinceUpdate >= refreshCooldownInterval {
                    // 超过20分钟，可以刷新
                    return .validRefreshable
                } else {
                    // 不足20分钟，不可刷新
                    return .validNotRefreshable
                }
            } else {
                // 没有更新时间，当作可刷新
                return .validRefreshable
            }
        case .expired, .noData:
            // 缓存无效，可以刷新
            return .invalidRefreshable
        }
    }

    // 处理下拉刷新
    private func handlePullToRefresh() async {
        // 更新缓存状态
        updateCacheStatus()

        // 检查是否在冷却期内
        switch refreshStatus {
        case .validNotRefreshable:
            // 在冷却期内，不执行刷新
            Logger.debug("刷新冷却期内，跳过刷新操作")
            return
        case .validRefreshable, .invalidRefreshable:
            // 可以刷新，执行刷新操作
            await loadStructureOrders()
        }
    }

    // 加载建筑市场订单
    private func loadStructureOrders() async {
        isLoadingOrders = true
        structureOrdersProgress = nil

        do {
            let orders = try await StructureMarketManager.shared.getStructureOrders(
                structureId: Int64(structure.structureId),
                characterId: structure.characterId,
                forceRefresh: true,
                progressCallback: { progress in
                    Task { @MainActor in
                        structureOrdersProgress = progress
                    }
                }
            )

            let statistics = await StructureMarketManager.shared.getOrdersStatistics(orders: orders)

            // 计算物品类别数（不同的 typeId 数量）
            let uniqueItemTypes = Set(orders.map { $0.typeId }).count

            // 计算最多卖单和买单的物品
            let (topSell, topBuy) = await calculateTopOrderItems(orders: orders)

            await MainActor.run {
                buyOrdersCount = statistics.buyOrders
                sellOrdersCount = statistics.sellOrders
                itemTypesCount = uniqueItemTypes
                topSellItems = topSell
                topBuyItems = topBuy

                Logger.info(
                    "建筑 \(structure.structureName) 的市场订单已加载: 买单 \(statistics.buyOrders) 个, 卖单 \(statistics.sellOrders) 个, 总交易量 \(statistics.totalVolume), 物品类别 \(uniqueItemTypes) 个"
                )
            }
        } catch {
            Logger.error("加载建筑市场订单失败: \(error)")
        }

        // 更新缓存状态
        await MainActor.run {
            updateCacheStatus()
            isLoadingOrders = false
            structureOrdersProgress = nil
        }
    }

    // 加载本地订单统计信息
    private func loadLocalOrdersStatistics() async {
        // 检查缓存状态，判断是否需要从API获取数据
        let cacheStatus = StructureMarketManager.getCacheStatus(structureId: Int64(structure.structureId))
        let needsRefresh = cacheStatus == .expired || cacheStatus == .noData

        // 如果需要刷新，设置加载状态
        if needsRefresh {
            await MainActor.run {
                isLoadingOrders = true
                structureOrdersProgress = nil
            }
        }

        // 先检查是否有本地缓存文件（无论是否过期）
        let hasLocal = await StructureMarketManager.shared.hasLocalOrders(structureId: Int64(structure.structureId))
        guard hasLocal else {
            // 如果没有本地缓存，需要从API获取，但这里不处理，让getStructureOrders处理
            // 如果needsRefresh为true，已经设置了加载状态
            await MainActor.run {
                if !needsRefresh {
                    buyOrdersCount = nil
                    sellOrdersCount = nil
                    itemTypesCount = nil
                }
            }
            // 如果没有本地缓存且需要刷新，尝试从API获取
            if needsRefresh {
                do {
                    let orders = try await StructureMarketManager.shared.getStructureOrders(
                        structureId: Int64(structure.structureId),
                        characterId: structure.characterId,
                        forceRefresh: false,
                        progressCallback: { progress in
                            Task { @MainActor in
                                structureOrdersProgress = progress
                            }
                        }
                    )
                    await processOrdersData(orders: orders, needsRefresh: needsRefresh)
                } catch {
                    await MainActor.run {
                        buyOrdersCount = nil
                        sellOrdersCount = nil
                        itemTypesCount = nil
                        topSellItems = []
                        topBuyItems = []
                        isLoadingOrders = false
                        structureOrdersProgress = nil
                    }
                }
            }
            return
        }

        do {
            // 尝试从本地缓存加载订单数据（不强制刷新，优先使用本地缓存）
            let orders = try await StructureMarketManager.shared.getStructureOrders(
                structureId: Int64(structure.structureId),
                characterId: structure.characterId,
                forceRefresh: false,
                progressCallback: needsRefresh ? { progress in
                    Task { @MainActor in
                        structureOrdersProgress = progress
                    }
                } : nil
            )

            await processOrdersData(orders: orders, needsRefresh: needsRefresh)
        } catch {
            // 如果加载失败，清空统计信息
            await MainActor.run {
                buyOrdersCount = nil
                sellOrdersCount = nil
                itemTypesCount = nil
                topSellItems = []
                topBuyItems = []

                // 清除加载状态
                if needsRefresh {
                    isLoadingOrders = false
                    structureOrdersProgress = nil
                }
            }
        }
    }

    // 处理订单数据（提取公共逻辑）
    private func processOrdersData(orders: [StructureMarketOrder], needsRefresh: Bool) async {
        // 计算统计数据
        let statistics = await StructureMarketManager.shared.getOrdersStatistics(orders: orders)
        let uniqueItemTypes = Set(orders.map { $0.typeId }).count

        // 计算最多卖单和买单的物品
        let (topSell, topBuy) = await calculateTopOrderItems(orders: orders)

        await MainActor.run {
            buyOrdersCount = statistics.buyOrders
            sellOrdersCount = statistics.sellOrders
            itemTypesCount = uniqueItemTypes
            topSellItems = topSell
            topBuyItems = topBuy

            // 如果之前显示了加载状态，现在清除
            if needsRefresh {
                isLoadingOrders = false
                structureOrdersProgress = nil
                updateCacheStatus()
            }
        }
    }

    // 加载主权数据
    private func loadSovereigntyData() async {
        do {
            let data = try await SovereigntyDataAPI.shared.fetchSovereigntyData(forceRefresh: false)
            await MainActor.run {
                sovereigntyData = data
                // 建立星系到联盟的映射（优先联盟，如果没有联盟则使用派系）
                var map: [Int: Int] = [:]
                for item in data {
                    if let allianceId = item.allianceId {
                        map[item.systemId] = allianceId
                    } else if let factionId = item.factionId, map[item.systemId] == nil {
                        // 如果没有联盟但有派系，也记录派系ID（但派系图标从数据库加载）
                        map[item.systemId] = -factionId // 使用负数表示派系
                    }
                }
                systemAllianceMap = map

                // 只加载当前建筑所在星系的联盟图标
                if let currentSystemAllianceId = map[structure.systemId], currentSystemAllianceId > 0 {
                    allianceIconLoader.loadIcon(for: currentSystemAllianceId)
                }
            }
        } catch {
            Logger.error("加载主权数据失败: \(error)")
        }
    }

    // 加载最多订单的物品
    private func loadTopOrderItems() async {
        // 先检查是否有本地缓存文件
        let hasLocal = await StructureMarketManager.shared.hasLocalOrders(structureId: Int64(structure.structureId))
        guard hasLocal else {
            await MainActor.run {
                topSellItems = []
                topBuyItems = []
            }
            return
        }

        do {
            // 从本地缓存加载订单数据
            let orders = try await StructureMarketManager.shared.getStructureOrders(
                structureId: Int64(structure.structureId),
                characterId: structure.characterId,
                forceRefresh: false
            )

            // 计算最多卖单和买单的物品
            let (topSell, topBuy) = await calculateTopOrderItems(orders: orders)

            await MainActor.run {
                topSellItems = topSell
                topBuyItems = topBuy
            }
        } catch {
            await MainActor.run {
                topSellItems = []
                topBuyItems = []
            }
        }
    }

    // 计算最多订单的物品（Top 3，相同数量时按typeId排序）
    private func calculateTopOrderItems(orders: [StructureMarketOrder]) async -> ([ItemOrderInfo], [ItemOrderInfo]) {
        // 分别统计卖单和买单
        var sellOrderCount: [Int: Int] = [:]
        var buyOrderCount: [Int: Int] = [:]

        for order in orders {
            if order.isBuyOrder {
                buyOrderCount[order.typeId, default: 0] += 1
            } else {
                sellOrderCount[order.typeId, default: 0] += 1
            }
        }

        // 先确定 Top 3 的 typeId（按订单数降序，相同数量时按typeId升序）
        let topSellTypeIds = sellOrderCount
            .sorted { first, second in
                if first.value != second.value {
                    return first.value > second.value // 按订单数降序
                } else {
                    return first.key < second.key // 相同数量时按typeId升序
                }
            }
            .prefix(3)
            .map { $0.key }

        let topBuyTypeIds = buyOrderCount
            .sorted { first, second in
                if first.value != second.value {
                    return first.value > second.value // 按订单数降序
                } else {
                    return first.key < second.key // 相同数量时按typeId升序
                }
            }
            .prefix(3)
            .map { $0.key }

        // 合并需要查询的 typeId（最多 6 个）
        let allTypeIds = Set(topSellTypeIds).union(Set(topBuyTypeIds))

        guard !allTypeIds.isEmpty else {
            return ([], [])
        }

        // 只查询 Top 3 物品的信息
        let placeholders = String(repeating: "?,", count: allTypeIds.count).dropLast()
        let query = """
            SELECT type_id, name, icon_filename
            FROM types
            WHERE type_id IN (\(placeholders))
        """

        var itemInfoMap: [Int: (name: String, iconFileName: String)] = [:]

        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: Array(allTypeIds)) {
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                      let name = row["name"] as? String,
                      let iconFileName = row["icon_filename"] as? String
                else {
                    continue
                }
                itemInfoMap[typeId] = (name: name, iconFileName: iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName)
            }
        }

        // 构建最多卖单的物品（Top 3）
        let topSellItems = topSellTypeIds.compactMap { typeId -> ItemOrderInfo? in
            guard let orderCount = sellOrderCount[typeId],
                  let itemInfo = itemInfoMap[typeId]
            else {
                return nil
            }
            return ItemOrderInfo(
                id: typeId,
                typeId: typeId,
                name: itemInfo.name,
                iconFileName: itemInfo.iconFileName,
                orderCount: orderCount,
                orderType: .sell
            )
        }

        // 构建最多买单的物品（Top 3）
        let topBuyItems = topBuyTypeIds.compactMap { typeId -> ItemOrderInfo? in
            guard let orderCount = buyOrderCount[typeId],
                  let itemInfo = itemInfoMap[typeId]
            else {
                return nil
            }
            return ItemOrderInfo(
                id: typeId,
                typeId: typeId,
                name: itemInfo.name,
                iconFileName: itemInfo.iconFileName,
                orderCount: orderCount,
                orderType: .buy
            )
        }

        return (topSellItems, topBuyItems)
    }
}

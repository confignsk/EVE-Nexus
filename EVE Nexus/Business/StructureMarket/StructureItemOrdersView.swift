import SwiftUI

// MARK: - 建筑内物品订单列表视图（单一类型）

struct StructureItemOrdersView: View {
    let structureId: Int64
    let characterId: Int
    let itemID: Int
    let itemName: String
    let orderType: MarketOrderType // 订单类型：buy 或 sell

    @ObservedObject var databaseManager: DatabaseManager
    @State private var orders: [MarketOrder] = []
    @State private var locationInfos: [Int64: LocationInfoDetail] = [:]
    @State private var isLoadingOrders = false
    @State private var isLoadingLocations = false
    @State private var itemDetails: ItemDetails?
    @State private var lastLoadedItemID: Int? = nil // 跟踪上次加载的 itemID
    @State private var lastLoadedOrderType: MarketOrderType? = nil // 跟踪上次加载的 orderType
    let locationInfoLoader: LocationInfoLoader

    init(
        structureId: Int64,
        characterId: Int,
        itemID: Int,
        itemName: String,
        orderType: MarketOrderType,
        databaseManager: DatabaseManager
    ) {
        self.structureId = structureId
        self.characterId = characterId
        self.itemID = itemID
        self.itemName = itemName
        self.orderType = orderType
        self.databaseManager = databaseManager

        // 从 UserDefaults 获取当前选择的角色ID
        let currentCharacterId = UserDefaults.standard.integer(forKey: "currentCharacterId")
        locationInfoLoader = LocationInfoLoader(
            databaseManager: databaseManager, characterId: Int64(currentCharacterId)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // 订单列表
            List {
                // 物品信息 Section
                if let details = itemDetails {
                    Section {
                        ItemInfoView(itemDetails: details)
                    }
                }

                // 订单列表 Section
                if orders.isEmpty && !isLoadingOrders {
                    Section {
                        NoDataSection()
                    }
                } else {
                    Section(header: Text(orderType == .buy
                            ? NSLocalizedString("Main_Market_Order_Buy", comment: "买单")
                            : NSLocalizedString("Main_Market_Order_Sell", comment: "卖单")))
                    {
                        ForEach(sortedOrders, id: \.orderId) { order in
                            OrderRow(
                                order: order,
                                locationInfo: locationInfos[order.locationId],
                                isLoadingLocation: isLoadingLocations
                            )
                        }
                    }
                    .listSectionSpacing(.compact)
                }
            }
            .listStyle(.insetGrouped)

            // 加载状态指示器
            if isLoadingOrders || isLoadingLocations {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(
                        isLoadingOrders
                            ? NSLocalizedString("Loading_Orders", comment: "正在加载订单...")
                            : NSLocalizedString("Loading_Location_Info", comment: "正在加载地点信息...")
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(itemName)
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
        .task {
            // 检查参数是否改变
            let needsReload = lastLoadedItemID != itemID || lastLoadedOrderType != orderType

            // 加载物品详情
            itemDetails = databaseManager.getItemDetails(for: itemID)

            // 如果参数改变或订单为空，重新加载数据
            if needsReload || orders.isEmpty {
                // 参数改变时，清空旧数据
                if needsReload {
                    await MainActor.run {
                        orders = []
                        locationInfos = [:]
                    }
                }

                await loadOrdersData()

                // 更新跟踪的参数
                await MainActor.run {
                    lastLoadedItemID = itemID
                    lastLoadedOrderType = orderType
                }
            }

            // 加载位置信息
            await loadLocationInfo()
        }
    }

    // MARK: - 计算属性

    private var sortedOrders: [MarketOrder] {
        let filteredOrders = orders.filter { order in
            orderType == .buy ? order.isBuyOrder : !order.isBuyOrder
        }

        return filteredOrders.sorted { order1, order2 -> Bool in
            if order1.isBuyOrder {
                return order1.price > order2.price // 买单按价格从高到低
            } else {
                return order1.price < order2.price // 卖单按价格从低到高
            }
        }
    }

    // MARK: - 数据加载方法

    private func loadOrdersData(forceRefresh: Bool = false) async {
        isLoadingOrders = true
        defer { isLoadingOrders = false }

        do {
            let newOrders = try await StructureMarketManager.shared.getItemOrdersInStructure(
                structureId: structureId,
                characterId: characterId,
                typeId: itemID,
                forceRefresh: forceRefresh
            )

            await MainActor.run {
                orders = newOrders
            }

            Logger.info("从建筑获取到 \(newOrders.count) 个订单")
        } catch {
            Logger.error("加载建筑市场订单失败: \(error)")
            await MainActor.run {
                orders = []
            }
        }
    }

    private func loadLocationInfo() async {
        guard !orders.isEmpty else { return }

        isLoadingLocations = true
        defer { isLoadingLocations = false }

        // 收集所有订单的位置ID
        let locationIds = Set(orders.map { $0.locationId })

        // 按类型分组位置ID
        let groupedIds = Dictionary(grouping: locationIds) { LocationType.from(id: $0) }

        // 清空之前的位置信息
        await MainActor.run {
            locationInfos = [:]
        }

        // 1. 立即处理PLEX建筑物（如果适用）
        if itemID == 44992, let structureIds = groupedIds[.structure] {
            var plexStructureInfos: [Int64: LocationInfoDetail] = [:]
            for structureId in structureIds {
                plexStructureInfos[structureId] = LocationInfoDetail(
                    stationName: NSLocalizedString("Location_Player_Structure", comment: ""),
                    solarSystemName: NSLocalizedString("Unknown_System", comment: ""),
                    security: 0.0
                )
            }

            await MainActor.run {
                locationInfos.merge(plexStructureInfos) { _, new in new }
            }
        }

        // 2. 优先加载空间站信息（通常在本地数据库中，速度快）
        if let stationIds = groupedIds[.station], !stationIds.isEmpty {
            let stationInfos = await locationInfoLoader.loadLocationInfo(
                locationIds: Set(stationIds))

            await MainActor.run {
                locationInfos.merge(stationInfos) { _, new in new }
            }
        }

        // 3. 优先加载星系信息（通常在本地数据库中，速度快）
        if let systemIds = groupedIds[.solarSystem], !systemIds.isEmpty {
            let systemInfos = await locationInfoLoader.loadLocationInfo(
                locationIds: Set(systemIds))

            await MainActor.run {
                locationInfos.merge(systemInfos) { _, new in new }
            }
        }

        // 4. 最后加载建筑物信息（需要API查询，速度慢）
        if let structureIds = groupedIds[.structure], !structureIds.isEmpty {
            // PLEX特殊处理：跳过建筑物API查询
            if itemID == 44992 {
                // PLEX的建筑物已经在步骤1中处理了
                return
            }

            // 正常物品：查询建筑物信息
            let structureInfos = await locationInfoLoader.loadLocationInfo(
                locationIds: Set(structureIds))

            await MainActor.run {
                locationInfos.merge(structureInfos) { _, new in new }
            }
        }
    }

    // MARK: - 物品信息视图

    private struct ItemInfoView: View {
        let itemDetails: ItemDetails

        var body: some View {
            HStack {
                IconManager.shared.loadImage(for: itemDetails.iconFileName)
                    .resizable()
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(itemDetails.name)
                        .font(.title3)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = itemDetails.name
                            } label: {
                                Label(
                                    NSLocalizedString("Misc_Copy_Item_Name", comment: ""),
                                    systemImage: "doc.on.doc"
                                )
                            }
                        }

                    Text("\(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
    }

    // MARK: - 订单行视图

    private struct OrderRow: View {
        let order: MarketOrder
        let locationInfo: LocationInfoDetail?
        let isLoadingLocation: Bool

        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(formatPrice(order.price))
                            .font(.headline)
                        Spacer()
                        Text("Qty: \(order.volumeRemain)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let locationInfo = locationInfo {
                        LocationInfoView(
                            stationName: locationInfo.stationName,
                            solarSystemName: locationInfo.solarSystemName,
                            security: locationInfo.security,
                            font: .caption,
                            textColor: .secondary
                        )
                    } else if isLoadingLocation {
                        // 地点信息加载中的占位视图
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("Loading_Location", comment: "加载中..."))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                    } else {
                        Text(NSLocalizedString("Assets_Unknown_Location", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }

        private func formatPrice(_ price: Double) -> String {
            let billion = 1_000_000_000.0
            let million = 1_000_000.0

            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.maximumFractionDigits = 2
            numberFormatter.minimumFractionDigits = 2

            let formattedFullPrice =
                numberFormatter.string(from: NSNumber(value: price))
                    ?? String(format: "%.2f", price)

            if price >= billion {
                let value = price / billion
                return String(format: "%.2fB (%@ ISK)", value, formattedFullPrice)
            } else if price >= million {
                let value = price / million
                return String(format: "%.2fM (%@ ISK)", value, formattedFullPrice)
            } else {
                return "\(formattedFullPrice) ISK"
            }
        }
    }
}

import SwiftUI

struct RefineryResultView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let taxRate: Double
    
    // 精炼结果数据
    let refineryOutputs: [Int: Int] // 输出材料ID -> 总数量
    let materialNameMap: [Int: String] // 材料ID -> 材料名称
    let remainingItems: [Int: Int64] // 剩余物品ID -> 剩余数量
    
    // 输出市场设置状态变量（精炼后产品的市场）
    @State private var selectedRegionID: Int = 10_000_002  // 默认 The Forge
    @State private var selectedRegionName: String = ""
    @State private var showRegionPicker = false
    @State private var saveSelection = false  // 不保存默认市场位置
    
    // 状态变量
    @State private var isLoadingPrices = false
    @State private var outputPrices: [Int: MarketPriceData] = [:]
    @State private var remainingPrices: [Int: MarketPriceData] = [:]
    @State private var outputVolumes: [Int: Double] = [:]
    @State private var remainingVolumes: [Int: Double] = [:]
    @State private var structureOrdersProgress: StructureOrdersProgress? = nil
    
    // EIV相关状态变量
    @State private var isLoadingEIV = false
    @State private var outputEIVPrices: [Int: MarketPriceData] = [:]
    
    init(
        databaseManager: DatabaseManager,
        taxRate: Double,
        refineryOutputs: [Int: Int],
        materialNameMap: [Int: String],
        remainingItems: [Int: Int64]
    ) {
        self.databaseManager = databaseManager
        self.taxRate = taxRate
        self.refineryOutputs = refineryOutputs
        self.materialNameMap = materialNameMap
        self.remainingItems = remainingItems
        
        Logger.info("=== RefineryResultView init ===")
        Logger.info("taxRate: \(taxRate)")
        Logger.info("refineryOutputs count: \(refineryOutputs.count)")
        Logger.info("materialNameMap count: \(materialNameMap.count)")
        Logger.info("remainingItems count: \(remainingItems.count)")
        
        for (materialID, quantity) in refineryOutputs {
            let materialName = materialNameMap[materialID] ?? "Unknown"
            Logger.info("Init Output: \(materialID) (\(materialName)) -> \(quantity)")
        }
        
        for (itemID, quantity) in remainingItems {
            Logger.info("Init Remaining: \(itemID) -> \(quantity)")
        }
    }
    
    var body: some View {
        List {
            // Section 1: 市场设置
            Section {
                // 输出市场选择器
                HStack {
                    Text(NSLocalizedString("Ore_Refinery_Result_Output_Market", comment: "输出市场"))
                    Spacer()
                    Button {
                        showRegionPicker = true
                    } label: {
                        HStack {
                            Text(selectedRegionName.isEmpty ? NSLocalizedString("Main_Market_Select_Location", comment: "") : selectedRegionName)
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundColor(.secondary)
                                .imageScale(.small)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }
            } header: {
                Text(NSLocalizedString("Ore_Refinery_Result_Market_Settings", comment: "市场设置"))
                    .fontWeight(.semibold)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .textCase(.none)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            
            // Section 2: 产品价值和税率
            Section {
                // 精炼后产品总价（市场价格）
                HStack {
                    Text(NSLocalizedString("Ore_Refinery_Result_Product_Market_Value", comment: "精炼后产品市场总价"))
                    Spacer()
                    if isLoadingPrices {
                        if StructureMarketManager.isStructureId(selectedRegionID),
                           let progress = structureOrdersProgress {
                            switch progress {
                            case .loading(let currentPage, let totalPages):
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("\(currentPage)/\(totalPages)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            case .completed:
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        } else {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    } else {
                        let totalValue = calculateTotalOutputValue()
                        Text("\(FormatUtil.formatISK(totalValue))")
                            .foregroundColor(.secondary)
                    }
                }
                
                // 税额（基于EIV计算）
                HStack {
                    Text(NSLocalizedString("Ore_Refinery_Result_Tax_Amount", comment: ""))
                    Spacer()
                    if isLoadingEIV {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        let taxAmount = calculateTaxAmount()
                        if taxRate == 0.0 {
                            Text(String(format: NSLocalizedString("Ore_Refinery_Result_Tax_Zero", comment: ""), taxRate))
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(FormatUtil.formatISK(taxAmount))")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                HStack {
                    Text(NSLocalizedString("Ore_Refinery_Result_Total_Volume", comment: ""))
                    Spacer()
                    if isLoadingPrices {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        let totalVolume = calculateTotalOutputVolume()
                        Text("\(FormatUtil.formatForUI(totalVolume, maxFractionDigits: 2)) m³")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                HStack {
                    Text(NSLocalizedString("Ore_Refinery_Result_Product_Value", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                    
                    Spacer()
                    
                    // 显示价格来源和加载进度
                    if isLoadingPrices {
                        if StructureMarketManager.isStructureId(selectedRegionID),
                           let progress = structureOrdersProgress {
                            switch progress {
                            case .loading(let currentPage, let totalPages):
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text("\(currentPage)/\(totalPages)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            case .completed:
                                EmptyView()
                            }
                        } else {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    } else {
                        Text(selectedRegionName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Section 2: 精炼结果清单
            if !refineryOutputs.isEmpty {
                Section {
                    ForEach(Array(refineryOutputs.keys.sorted()), id: \.self) { materialID in
                        if let quantity = refineryOutputs[materialID] {
                            refineryOutputRow(materialID: materialID, quantity: quantity)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Ore_Refinery_Result_Output_List", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                }
            } else {
                Section {
                    Text(NSLocalizedString("Ore_Refinery_Output_List_Empty", comment: ""))
                        .foregroundColor(.secondary)
                        .italic()
                } header: {
                    Text(NSLocalizedString("Ore_Refinery_Result_Output_List", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                }
            }
            
            // Section 3: 精炼剩余物品清单
            if !remainingItems.isEmpty {
                Section {
                    ForEach(Array(remainingItems.keys.sorted()), id: \.self) { itemID in
                        if let quantity = remainingItems[itemID] {
                            remainingItemRow(itemID: itemID, quantity: quantity)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Ore_Refinery_Result_Remaining_List", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                }
            } else {
                Section {
                    Text(NSLocalizedString("Ore_Refinery_Remaining_List_Empty", comment: ""))
                        .foregroundColor(.secondary)
                        .italic()
                } header: {
                    Text(NSLocalizedString("Ore_Refinery_Result_Remaining_List", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Ore_Refinery_Result_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            loadPricesAndVolumes()
        }
        .sheet(isPresented: $showRegionPicker) {
            MarketRegionPickerView(
                selectedRegionID: $selectedRegionID,
                selectedRegionName: $selectedRegionName,
                saveSelection: $saveSelection,
                databaseManager: databaseManager
            )
        }
        .onChange(of: selectedRegionID) { oldValue, newValue in
            if oldValue != newValue {
                updateRegionName()
                loadPricesAndVolumes()
            }
        }
        .onAppear {
            Logger.info("=== RefineryResultView onAppear ===")
            Logger.info("refineryOutputs count: \(refineryOutputs.count)")
            Logger.info("remainingItems count: \(remainingItems.count)")
            Logger.info("taxRate: \(taxRate)")
            
            for (materialID, quantity) in refineryOutputs {
                Logger.info("Output material: \(materialID) -> \(quantity)")
            }
            
            for (itemID, quantity) in remainingItems {
                Logger.info("Remaining item: \(itemID) -> \(quantity)")
            }
            
            // 初始化默认市场
            updateRegionName()
            loadPricesAndVolumes()
        }
    }
    
    // 精炼输出物品行
    @ViewBuilder
    private func refineryOutputRow(materialID: Int, quantity: Int) -> some View {
        HStack(spacing: 12) {
            // 物品图标
            IconManager.shared.loadImage(for: getItemIconFileName(itemID: materialID))
                .resizable()
                .frame(width: 32, height: 32)
            
            // 物品信息
            VStack(alignment: .leading, spacing: 2) {
                Text(materialNameMap[materialID] ?? "Unknown Material")
                    .lineLimit(1)
                
                // 价格信息或加载状态
                if isLoadingPrices {
                    // 显示简单的加载指示器
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text(NSLocalizedString("Main_Database_Loading", comment: "加载中..."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // 显示价格信息
                    if let priceData = outputPrices[materialID] {
                        let marketPrice = priceData.averagePrice
                        if marketPrice > 0 {
                            Text("\(NSLocalizedString("Ore_Refinery_Result_Avg_Price", comment: "")): \(FormatUtil.format(marketPrice)) ISK")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        let totalValue = marketPrice * Double(quantity)
                        Text("\(NSLocalizedString("Ore_Refinery_Result_Total_Value", comment: "")): \(FormatUtil.formatISK(totalValue))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(NSLocalizedString("Ore_Refinery_Result_No_Price", comment: ""))
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
            
            // 数量
            Text("\(quantity)")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    // 剩余物品行
    @ViewBuilder
    private func remainingItemRow(itemID: Int, quantity: Int64) -> some View {
        HStack(spacing: 12) {
            // 物品图标
            IconManager.shared.loadImage(for: getItemIconFileName(itemID: itemID))
                .resizable()
                .frame(width: 32, height: 32)
            
            // 物品信息
            VStack(alignment: .leading, spacing: 2) {
                Text(getItemName(itemID: itemID))
                    .lineLimit(1)
                
                // 价格信息或加载状态
                if isLoadingPrices {
                    // 显示简单的加载指示器
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text(NSLocalizedString("Main_Database_Loading", comment: "加载中..."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // 显示价格信息
                    if let priceData = remainingPrices[itemID] {
                        let marketPrice = priceData.averagePrice
                        if marketPrice > 0 {
                            Text("\(NSLocalizedString("Ore_Refinery_Result_Avg_Price", comment: "")): \(FormatUtil.format(marketPrice)) ISK")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        let totalValue = marketPrice * Double(quantity)
                        Text("\(NSLocalizedString("Ore_Refinery_Result_Total_Value", comment: "")): \(FormatUtil.formatISK(totalValue))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(NSLocalizedString("Ore_Refinery_Result_No_Price", comment: ""))
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
            
            // 数量
            Text("\(quantity)")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    // 加载价格和体积信息
    private func loadPricesAndVolumes() {
        Logger.info("=== loadPricesAndVolumes called ===")
        Logger.info("refineryOutputs keys: \(Array(refineryOutputs.keys))")
        Logger.info("remainingItems keys: \(Array(remainingItems.keys))")
        Logger.info("selectedRegionID: \(selectedRegionID)")
        
        isLoadingPrices = true
        isLoadingEIV = true
        
        Task {
            // 并发加载不同类型的价格数据
            async let outputMarketPricesTask: Void = {
                // 加载输出市场价格（精炼后产品）
                if await StructureMarketManager.isStructureId(selectedRegionID) {
                    await loadOutputStructureMarketPrices()
                } else {
                    await loadOutputRegionMarketPrices()
                }
            }()
            
            async let eivPricesTask: Void = loadEIVPrices()
            async let volumesTask: Void = loadVolumes()
            
            // 等待所有任务完成
            _ = await (outputMarketPricesTask, eivPricesTask, volumesTask)
            
            await MainActor.run {
                self.isLoadingPrices = false
                self.isLoadingEIV = false
                Logger.info("Finished loading prices, EIV, and volumes")
            }
        }
    }
    
    // 加载输出星域市场价格（精炼后产品）
    private func loadOutputRegionMarketPrices() async {
        // 加载精炼输出物品的价格
        let outputTypeIDs = Array(refineryOutputs.keys)
        Logger.info("Loading output region prices for output items: \(outputTypeIDs)")
        if !outputTypeIDs.isEmpty {
            let prices = await MarketPriceUtil.getMarketPrices(typeIds: outputTypeIDs)
            Logger.info("Got \(prices.count) output prices")
            await MainActor.run {
                self.outputPrices = prices
            }
        }
        
        // 加载剩余物品的价格
        let remainingTypeIDs = Array(remainingItems.keys)
        Logger.info("Loading output region prices for remaining items: \(remainingTypeIDs)")
        if !remainingTypeIDs.isEmpty {
            let prices = await MarketPriceUtil.getMarketPrices(typeIds: remainingTypeIDs)
            Logger.info("Got \(prices.count) remaining prices")
            await MainActor.run {
                self.remainingPrices = prices
            }
        }
    }
    
    // 加载输出建筑市场价格（精炼后产品）
    private func loadOutputStructureMarketPrices() async {
        guard let structureId = StructureMarketManager.getStructureId(from: selectedRegionID),
              let structure = getStructureById(structureId) else {
            Logger.error("无效的建筑ID或未找到建筑信息: \(selectedRegionID)")
            return
        }
        
        do {
            // 合并输出物品需要查询价格的物品ID
            var allTypeIds: [Int] = []
            allTypeIds.append(contentsOf: Array(refineryOutputs.keys))
            allTypeIds.append(contentsOf: Array(remainingItems.keys))
            
            Logger.info("Loading output structure market prices for \(allTypeIds.count) items from structure \(structure.structureName)")
            
            let batchOrders = try await StructureMarketManager.shared.getBatchItemOrdersInStructure(
                structureId: structureId,
                characterId: structure.characterId,
                typeIds: allTypeIds,
                forceRefresh: false,
                progressCallback: { progress in
                    Task { @MainActor in
                        structureOrdersProgress = progress
                    }
                }
            )
            
            Logger.info("Got structure orders for \(batchOrders.count) items")
            
            // 计算每个输出物品的平均价格
            var outputPricesTemp: [Int: MarketPriceData] = [:]
            var remainingPricesTemp: [Int: MarketPriceData] = [:]
            
            for (typeId, orders) in batchOrders {
                let averagePrice = calculateAveragePrice(from: orders)
                let priceData = MarketPriceData(adjustedPrice: averagePrice, averagePrice: averagePrice)
                
                if refineryOutputs.keys.contains(typeId) {
                    outputPricesTemp[typeId] = priceData
                }
                if remainingItems.keys.contains(typeId) {
                    remainingPricesTemp[typeId] = priceData
                }
            }
            
            await MainActor.run {
                self.outputPrices = outputPricesTemp
                self.remainingPrices = remainingPricesTemp
                Logger.info("Set output structure prices: output=\(outputPricesTemp.count), remaining=\(remainingPricesTemp.count)")
            }
            
        } catch {
            Logger.error("加载输出建筑市场价格失败: \(error)")
        }
    }
    
    // 计算订单的平均价格（用于输出物品）
    private func calculateAveragePrice(from orders: [MarketOrder]) -> Double {
        guard !orders.isEmpty else { return 0.0 }
        
        // 分别计算买单和卖单的最优价格
        let buyOrders = orders.filter { $0.isBuyOrder }.sorted { $0.price > $1.price }
        let sellOrders = orders.filter { !$0.isBuyOrder }.sorted { $0.price < $1.price }
        
        let bestBuyPrice = buyOrders.first?.price ?? 0.0
        let bestSellPrice = sellOrders.first?.price ?? 0.0
        
        // 如果只有一种订单类型，使用该类型的价格
        if bestBuyPrice > 0 && bestSellPrice > 0 {
            return (bestBuyPrice + bestSellPrice) / 2.0
        } else if bestSellPrice > 0 {
            return bestSellPrice
        } else if bestBuyPrice > 0 {
            return bestBuyPrice
        } else {
            return 0.0
        }
    }
    
    // 根据建筑ID获取建筑信息
    private func getStructureById(_ structureId: Int64) -> MarketStructure? {
        return MarketStructureManager.shared.structures.first { $0.structureId == Int(structureId) }
    }
    
    // 更新区域名称
    private func updateRegionName() {
        if StructureMarketManager.isStructureId(selectedRegionID) {
            // 是建筑ID，查找建筑名称
            if let structureId = StructureMarketManager.getStructureId(from: selectedRegionID),
               let structure = getStructureById(structureId) {
                selectedRegionName = structure.structureName
            } else {
                selectedRegionName = "Unknown Structure"
            }
        } else {
            // 是星域ID，查找星域名称
            let query = """
                SELECT regionName
                FROM regions
                WHERE regionID = ?
            """
            
            if case let .success(rows) = databaseManager.executeQuery(query, parameters: [selectedRegionID]) {
                if let row = rows.first, let name = row["regionName"] as? String {
                    selectedRegionName = name
                }
            }
        }
    }
    
    // MARK: - EIV价格加载和计算方法
    
    // 加载EIV价格数据（使用MarketPriceUtil）
    private func loadEIVPrices() async {
        Logger.info("=== loadEIVPrices called ===")
        
        // 合并所有需要查询EIV价格的物品ID
        var allTypeIds: [Int] = []
        allTypeIds.append(contentsOf: Array(refineryOutputs.keys))
        allTypeIds.append(contentsOf: Array(remainingItems.keys))
        
        guard !allTypeIds.isEmpty else {
            Logger.info("No items to load EIV prices for")
            return
        }
        
        Logger.info("Loading EIV prices for \(allTypeIds.count) items")
        
        // 使用MarketPriceUtil获取EIV价格
        let eivPrices = await MarketPriceUtil.getMarketPrices(typeIds: allTypeIds)
        Logger.info("Got EIV prices for \(eivPrices.count) items")
        
        await MainActor.run {
            // 只保存输出物品的EIV价格
            var outputEIVTemp: [Int: MarketPriceData] = [:]
            
            for (typeId, priceData) in eivPrices {
                if refineryOutputs.keys.contains(typeId) || remainingItems.keys.contains(typeId) {
                    outputEIVTemp[typeId] = priceData
                }
            }
            
            self.outputEIVPrices = outputEIVTemp
            
            Logger.info("Set EIV prices: output=\(outputEIVTemp.count)")
        }
    }
    
    // 加载体积信息
    private func loadVolumes() async {
        Logger.info("=== loadVolumes called ===")
        
        // 加载精炼输出物品的体积
        let outputTypeIDs = Array(refineryOutputs.keys)
        Logger.info("Loading volumes for output items: \(outputTypeIDs)")
        if !outputTypeIDs.isEmpty {
            let volumes = await loadItemVolumes(typeIDs: outputTypeIDs)
            Logger.info("Got \(volumes.count) output volumes")
            await MainActor.run {
                self.outputVolumes = volumes
            }
        }
        
        // 加载剩余物品的体积
        let remainingTypeIDs = Array(remainingItems.keys)
        Logger.info("Loading volumes for remaining items: \(remainingTypeIDs)")
        if !remainingTypeIDs.isEmpty {
            let volumes = await loadItemVolumes(typeIDs: remainingTypeIDs)
            Logger.info("Got \(volumes.count) remaining volumes")
            await MainActor.run {
                self.remainingVolumes = volumes
            }
        }
    }
    
    // 从数据库加载物品体积
    private func loadItemVolumes(typeIDs: [Int]) async -> [Int: Double] {
        guard !typeIDs.isEmpty else { return [:] }
        
        Logger.info("=== loadItemVolumes called ===")
        Logger.info("typeIDs: \(typeIDs)")
        
        let placeholders = String(repeating: "?,", count: typeIDs.count).dropLast()
        let query = "SELECT type_id, volume FROM types WHERE type_id IN (\(placeholders))"
        
        Logger.info("Query: \(query)")
        
        var volumes: [Int: Double] = [:]
        
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: typeIDs) {
            Logger.info("Query returned \(rows.count) rows")
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                   let volume = row["volume"] as? Double {
                    volumes[typeID] = volume
                    Logger.info("Found volume for \(typeID): \(volume)")
                } else {
                    Logger.warning("Failed to parse volume data: \(row)")
                }
            }
        } else {
            Logger.error("Failed to execute volume query")
        }
        
        Logger.info("Returning \(volumes.count) volumes")
        return volumes
    }
    
    // 计算产品总价值（用于显示，使用市场价格）
    private func calculateTotalOutputValue() -> Double {
        var totalValue: Double = 0
        
        Logger.info("=== calculateTotalOutputValue called ===")
        Logger.info("refineryOutputs count: \(refineryOutputs.count)")
        Logger.info("outputPrices count: \(outputPrices.count)")
        
        for (materialID, quantity) in refineryOutputs {
            Logger.info("Processing material \(materialID) with quantity \(quantity)")
            if let priceData = outputPrices[materialID] {
                let marketPrice = priceData.averagePrice
                Logger.info("Found price data for \(materialID): marketPrice = \(marketPrice)")
                if marketPrice > 0 {
                    let itemValue = marketPrice * Double(quantity)
                    totalValue += itemValue
                    Logger.info("Added \(itemValue) to total (now \(totalValue))")
                } else {
                    Logger.info("Price is 0 or negative for \(materialID)")
                }
            } else {
                Logger.info("No price data found for \(materialID)")
            }
        }
        
        Logger.info("Final total value: \(totalValue)")
        return totalValue
    }
    
    // 计算产品EIV（用于税额计算，使用adjustedPrice）
    private func calculateTotalOutputEIV() -> Double {
        var totalEIV: Double = 0
        
        Logger.info("=== calculateTotalOutputEIV called ===")
        Logger.info("refineryOutputs count: \(refineryOutputs.count)")
        Logger.info("outputEIVPrices count: \(outputEIVPrices.count)")
        
        for (materialID, quantity) in refineryOutputs {
            Logger.info("Processing EIV for material \(materialID) with quantity \(quantity)")
            if let priceData = outputEIVPrices[materialID] {
                let adjustedPrice = priceData.adjustedPrice
                Logger.info("Found EIV price data for \(materialID): adjustedPrice = \(adjustedPrice)")
                if adjustedPrice > 0 {
                    let itemEIV = adjustedPrice * Double(quantity)
                    totalEIV += itemEIV
                    Logger.info("Added \(itemEIV) to EIV total (now \(totalEIV))")
                } else {
                    Logger.info("Adjusted price is 0 or negative for \(materialID)")
                }
            } else {
                Logger.info("No EIV price data found for \(materialID)")
            }
        }
        
        Logger.info("Final total EIV: \(totalEIV)")
        return totalEIV
    }
    
    // 计算税额
    private func calculateTaxAmount() -> Double {
        Logger.info("=== calculateTaxAmount called ===")
        Logger.info("taxRate: \(taxRate)%")
        
        let totalEIV = calculateTotalOutputEIV()
        Logger.info("Total EIV: \(totalEIV)")
        
        let taxAmount = totalEIV * (taxRate / 100.0)
        Logger.info("Tax calculation: EIV \(totalEIV) × taxRate \(taxRate)% = \(taxAmount)")
        
        return taxAmount
    }
    
    // 计算精炼输出总体积
    private func calculateTotalOutputVolume() -> Double {
        var totalVolume: Double = 0
        
        Logger.info("=== calculateTotalOutputVolume called ===")
        Logger.info("refineryOutputs count: \(refineryOutputs.count)")
        Logger.info("outputVolumes count: \(outputVolumes.count)")
        
        for (materialID, quantity) in refineryOutputs {
            Logger.info("Processing volume for material \(materialID) with quantity \(quantity)")
            if let volume = outputVolumes[materialID] {
                let itemVolume = volume * Double(quantity)
                totalVolume += itemVolume
                Logger.info("Found volume for \(materialID): \(volume), item volume: \(itemVolume), total: \(totalVolume)")
            } else {
                Logger.info("No volume data found for \(materialID)")
            }
        }
        
        Logger.info("Final total volume: \(totalVolume)")
        return totalVolume
    }
    
    // 获取物品名称
    private func getItemName(itemID: Int) -> String {
        let query = "SELECT name FROM types WHERE type_id = ?"
        
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [itemID]),
           let row = rows.first,
           let name = row["name"] as? String {
            return name
        }
        
        return "Unknown Item"
    }
    
    // 获取物品图标文件名
    private func getItemIconFileName(itemID: Int) -> String {
        let query = "SELECT icon_filename FROM types WHERE type_id = ?"
        
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [itemID]),
           let row = rows.first,
           let iconName = row["icon_filename"] as? String {
            return iconName
        }
        
        return DatabaseConfig.defaultItemIcon // 使用默认图标
    }
}


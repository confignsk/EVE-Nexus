import SwiftUI

// MARK: - 搜索相关数据模型
struct LPSearchResult {
    let categoryId: Int
    let categoryName: String
    let categoryIcon: String
    let offerCount: Int
    let offers: [LPSearchOffer]
}

struct LPSearchOffer {
    let typeId: Int
    let typeName: String
    let typeIcon: String
    let offerId: Int
    let factionId: Int?
    let corporationId: Int
}

struct LPOfferSupplier {
    let factionId: Int?
    let factionName: String?
    let corporationId: Int
    let corporationName: String
    let corporationIcon: String
}

struct Faction: Identifiable {
    let id: Int
    let name: String
    let enName: String
    let zhName: String
    let iconName: String
    var corporations: [Corporation]

    init?(from row: [String: Any], corporations: [Corporation] = []) {
        guard let id = row["faction_id"] as? Int,
            let name = row["faction_name"] as? String,
            let enName = row["faction_en_name"] as? String,
            let zhName = row["faction_zh_name"] as? String,
            let iconName = row["faction_icon"] as? String
        else {
            return nil
        }
        self.id = id
        self.name = name
        self.enName = enName
        self.zhName = zhName
        self.iconName = iconName
        self.corporations = corporations
    }
}

struct Corporation: Identifiable {
    let id: Int
    let name: String
    let enName: String
    let zhName: String
    let factionId: Int
    let iconFileName: String

    init?(from row: [String: Any]) {
        guard let corporationId = row["corporation_id"] as? Int,
            let name = row["corp_name"] as? String,
            let enName = row["corp_en_name"] as? String,
            let zhName = row["corp_zh_name"] as? String,
            let factionId = row["faction_id"] as? Int
        else {
            return nil
        }

        id = corporationId
        self.name = name
        self.enName = enName
        self.zhName = zhName
        self.factionId = factionId
        self.iconFileName =
            (row["icon_filename"] as? String)?.isEmpty == true
            ? "corporations_default" : (row["icon_filename"] as? String ?? "corporations_default")
    }
}


struct FactionLPDetailView: View {
    let faction: Faction
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var lpSearchResults: [LPSearchResult] = []
    @State private var isSearchingItems = false

    private var filteredCorporations: [Corporation] {
        if debouncedSearchText.isEmpty {
            return faction.corporations
        } else {
            return faction.corporations.filter { corporation in
                corporation.name.localizedCaseInsensitiveContains(debouncedSearchText) ||
                corporation.enName.localizedCaseInsensitiveContains(debouncedSearchText) ||
                corporation.zhName.localizedCaseInsensitiveContains(debouncedSearchText)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        List {
            if !debouncedSearchText.isEmpty {
                // 显示LP物品搜索结果
                if !lpSearchResults.isEmpty {
                    Section(NSLocalizedString("Main_LP_Available_Items", comment: "可用物品")) {
                        ForEach(lpSearchResults, id: \.categoryId) { category in
                            NavigationLink(
                                destination: LPSearchCategoryView(
                                    categoryName: category.categoryName,
                                    offers: category.offers
                                )
                            ) {
                                HStack {
                                    IconManager.shared.loadImage(for: category.categoryIcon)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36)
                                        .cornerRadius(6)
                                    Text(category.categoryName)
                                        .padding(.leading, 8)
                                    
                                    Spacer()
                                    Text("\(category.offerCount)")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
                
                if filteredCorporations.isEmpty && lpSearchResults.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
            }
            
            if !filteredCorporations.isEmpty || debouncedSearchText.isEmpty {
                Section(NSLocalizedString("Main_LP_Store_Corps", comment: "")) {
                    ForEach(filteredCorporations) { corporation in
                        NavigationLink(
                            destination: CorporationLPStoreView(
                                corporationId: corporation.id, corporationName: corporation.name
                            )
                        ) {
                            HStack {
                                CorporationIconView(corporationId: corporation.id, iconFileName: corporation.iconFileName, size: 36)

                                Text(corporation.name)
                                    .padding(.leading, 8)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(faction.name)
        // 移除嵌套的搜索功能，避免与主搜索页面冲突
        // .searchable(
        //     text: $searchText,
        //     placement: .navigationBarDrawer(displayMode: .always),
        //     prompt: NSLocalizedString("Main_Search_Placeholder", comment: "")
        // )
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            
            if newValue.isEmpty {
                debouncedSearchText = ""
                lpSearchResults = []
                return
            }
            
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                if !Task.isCancelled {
                    await MainActor.run {
                        debouncedSearchText = newValue
                        if newValue.count >= 2 {
                            searchLPItems(searchText: newValue, factionId: faction.id)
                        } else {
                            lpSearchResults = []
                        }
                    }
                }
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }
    
    private func searchLPItems(searchText: String, factionId: Int) {
        isSearchingItems = true
        
        Task {
            do {
                // 1. 从CharacterDatabaseManager搜索该势力下的物品
                let itemSearchQuery = """
                    SELECT type_id, offer_id, faction_id, corporation_id 
                    FROM LPStoreItemIndex 
                    WHERE faction_id = \(factionId) 
                    AND (type_name_zh LIKE '%\(searchText)%' OR type_name_en LIKE '%\(searchText)%')
                """
                
                let itemResult = CharacterDatabaseManager.shared.executeQuery(itemSearchQuery)
                guard case let .success(itemRows) = itemResult else {
                    await MainActor.run {
                        isSearchingItems = false
                        lpSearchResults = []
                    }
                    return
                }
                
                // 收集type_ids
                var typeIds: Set<Int> = []
                var categoryIds: Set<Int> = []
                var searchOffers: [LPSearchOffer] = []
                
                for row in itemRows {
                    guard let typeId = (row["type_id"] as? Int64).map(Int.init) ?? row["type_id"] as? Int,
                          let offerId = (row["offer_id"] as? Int64).map(Int.init) ?? row["offer_id"] as? Int,
                          let corporationId = (row["corporation_id"] as? Int64).map(Int.init) ?? row["corporation_id"] as? Int else {
                        continue
                    }
                    
                    let searchFactionId = (row["faction_id"] as? Int64).map(Int.init) ?? row["faction_id"] as? Int
                    
                    typeIds.insert(typeId)
                    searchOffers.append(LPSearchOffer(
                        typeId: typeId,
                        typeName: "",
                        typeIcon: "",
                        offerId: offerId,
                        factionId: searchFactionId,
                        corporationId: corporationId
                    ))
                }
                
                if typeIds.isEmpty {
                    await MainActor.run {
                        isSearchingItems = false
                        lpSearchResults = []
                    }
                    return
                }
                
                // 2. 从DatabaseManager获取物品详细信息
                let typeQuery = """
                    SELECT type_id, name, icon_filename, categoryID 
                    FROM types 
                    WHERE type_id IN (\(typeIds.sorted().map { String($0) }.joined(separator: ","))) 
                    AND categoryID NOT IN (2118, 91)
                """
                
                let typeResult = DatabaseManager.shared.executeQuery(typeQuery)
                guard case let .success(typeRows) = typeResult else {
                    await MainActor.run {
                        isSearchingItems = false
                        lpSearchResults = []
                    }
                    return
                }
                
                var typeInfos: [Int: (name: String, icon: String, categoryId: Int)] = [:]
                
                for row in typeRows {
                    guard let typeId = row["type_id"] as? Int,
                          let name = row["name"] as? String,
                          let iconFileName = row["icon_filename"] as? String,
                          let categoryId = row["categoryID"] as? Int else {
                        continue
                    }
                    
                    typeInfos[typeId] = (name, iconFileName.isEmpty ? "not_found" : iconFileName, categoryId)
                    categoryIds.insert(categoryId)
                }
                
                // 3. 获取分类信息
                var categoryInfos: [Int: (name: String, icon: String)] = [:]
                if !categoryIds.isEmpty {
                    let categoryQuery = """
                        SELECT category_id, name, icon_filename 
                        FROM categories 
                        WHERE category_id IN (\(categoryIds.sorted().map { String($0) }.joined(separator: ",")))
                    """
                    
                    if case let .success(categoryRows) = DatabaseManager.shared.executeQuery(categoryQuery) {
                        for row in categoryRows {
                            guard let categoryId = row["category_id"] as? Int,
                                  let name = row["name"] as? String,
                                  let iconFileName = row["icon_filename"] as? String else {
                                continue
                            }
                            
                            categoryInfos[categoryId] = (name, iconFileName.isEmpty ? "not_found" : iconFileName)
                        }
                    }
                }
                
                // 4. 组织搜索结果
                var categoryOffersDict: [Int: [LPSearchOffer]] = [:]
                
                for var offer in searchOffers {
                    guard let typeInfo = typeInfos[offer.typeId] else { continue }
                    
                    // 更新offer信息
                    offer = LPSearchOffer(
                        typeId: offer.typeId,
                        typeName: typeInfo.name,
                        typeIcon: typeInfo.icon,
                        offerId: offer.offerId,
                        factionId: offer.factionId,
                        corporationId: offer.corporationId
                    )
                    
                    categoryOffersDict[typeInfo.categoryId, default: []].append(offer)
                }
                
                // 5. 转换为最终结果，按type_id去重
                let results = categoryOffersDict.compactMap { categoryId, offers -> LPSearchResult? in
                    guard let categoryInfo = categoryInfos[categoryId] else { return nil }
                    
                    // 按type_id去重，每个物品类型只保留一个offer
                    var uniqueOffers: [Int: LPSearchOffer] = [:]
                    for offer in offers {
                        if uniqueOffers[offer.typeId] == nil {
                            uniqueOffers[offer.typeId] = offer
                        }
                    }
                    
                    let deduplicatedOffers = Array(uniqueOffers.values).sorted { 
                        $0.typeName.localizedStandardCompare($1.typeName) == .orderedAscending 
                    }
                    
                    return LPSearchResult(
                        categoryId: categoryId,
                        categoryName: categoryInfo.name,
                        categoryIcon: categoryInfo.icon,
                        offerCount: deduplicatedOffers.count,
                        offers: deduplicatedOffers
                    )
                }.sorted { $0.categoryName.localizedStandardCompare($1.categoryName) == .orderedAscending }
                
                await MainActor.run {
                    isSearchingItems = false
                    lpSearchResults = results
                }
            }
        }
    }
}

// MARK: - LP搜索相关视图
struct LPSearchCategoryView: View {
    let categoryName: String
    let offers: [LPSearchOffer]
    @State private var searchText = ""
    
    private var uniqueFilteredOffers: [LPSearchOffer] {
        let filtered: [LPSearchOffer]
        if searchText.isEmpty {
            filtered = offers
        } else {
            filtered = offers.filter { offer in
                offer.typeName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // 按type_id去重，每个物品类型只保留一个
        var uniqueOffers: [Int: LPSearchOffer] = [:]
        for offer in filtered {
            if uniqueOffers[offer.typeId] == nil {
                uniqueOffers[offer.typeId] = offer
            }
        }
        
        return uniqueOffers.values.sorted { $0.typeName.localizedStandardCompare($1.typeName) == .orderedAscending }
    }
    
    var body: some View {
        List {
            Section(NSLocalizedString("Main_LP_Store_Items", comment: "物品")) {
                if !searchText.isEmpty && uniqueFilteredOffers.isEmpty {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ForEach(uniqueFilteredOffers, id: \.typeId) { offer in
                        NavigationLink(
                            destination: LPItemSuppliersView(offer: offer)
                        ) {
                            HStack {
                                IconManager.shared.loadImage(for: offer.typeIcon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36)
                                    .cornerRadius(6)
                                Text(offer.typeName)
                                    .padding(.leading, 8)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(categoryName)
        // 移除嵌套的搜索功能，避免与主搜索页面冲突
        // .searchable(
        //     text: $searchText,
        //     placement: .navigationBarDrawer(displayMode: .always),
        //     prompt: NSLocalizedString("Main_Search_Placeholder", comment: "")
        // )
    }
}

struct LPItemSuppliersView: View {
    let offer: LPSearchOffer
    @State private var suppliers: [LPOfferSupplier] = []
    @State private var isLoading = true
    @State private var error: Error?
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let error = error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error.localizedDescription)
                        .font(.headline)
                    Button(NSLocalizedString("Main_Setting_Reset", comment: "")) {
                        loadSuppliers()
                    }
                    .buttonStyle(.bordered)
                }
            } else if suppliers.isEmpty {
                Section {
                    NoDataSection()
                }
            } else {
                // 按势力分组显示供应商
                let factionGroups = Dictionary(grouping: suppliers) { $0.factionId }
                let sortedFactionIds = factionGroups.keys.sorted { factionId1, factionId2 in
                    let faction1Name = suppliers.first { $0.factionId == factionId1 }?.factionName ?? ""
                    let faction2Name = suppliers.first { $0.factionId == factionId2 }?.factionName ?? ""
                    return faction1Name.localizedStandardCompare(faction2Name) == .orderedAscending
                }
                
                ForEach(sortedFactionIds, id: \.self) { factionId in
                    let factionSuppliers = factionGroups[factionId] ?? []
                    let factionName = factionSuppliers.first?.factionName ?? NSLocalizedString("Main_LP_Unknown_Faction", comment: "未知势力")
                    
                    Section(factionName) {
                        ForEach(factionSuppliers, id: \.corporationId) { supplier in
                            NavigationLink(
                                destination: SpecificItemOfferView(
                                    corporationId: supplier.corporationId,
                                    corporationName: supplier.corporationName,
                                    targetTypeId: offer.typeId,
                                    itemInfo: LPStoreItemInfo(
                                        name: offer.typeName,
                                        enName: offer.typeName,
                                        zhName: offer.typeName,
                                        iconFileName: offer.typeIcon,
                                        categoryName: "",
                                        categoryId: 0
                                    )
                                )
                            ) {
                                HStack {
                                    CorporationIconView(
                                        corporationId: supplier.corporationId,
                                        iconFileName: supplier.corporationIcon,
                                        size: 36
                                    )
                                    Text(supplier.corporationName)
                                        .padding(.leading, 8)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .navigationTitle(offer.typeName)
        .task {
            loadSuppliers()
        }
    }
    
    private func loadSuppliers() {
        isLoading = true
        error = nil
        
        Task {
            do {
                // 查询提供此物品的所有军团
                let itemSearchQuery = """
                    SELECT DISTINCT corporation_id, faction_id 
                    FROM LPStoreItemIndex 
                    WHERE type_id = \(offer.typeId)
                """
                
                let result = CharacterDatabaseManager.shared.executeQuery(itemSearchQuery)
                guard case let .success(rows) = result else {
                    await MainActor.run {
                        error = NSError(domain: "com.eve.nexus", code: -1, userInfo: [NSLocalizedDescriptionKey: "查询失败"])
                        isLoading = false
                    }
                    return
                }
                
                var corporationIds: Set<Int> = []
                var factionIds: Set<Int> = []
                var corporationFactionMap: [Int: Int?] = [:]
                
                for row in rows {
                    guard let corporationId = (row["corporation_id"] as? Int64).map(Int.init) ?? row["corporation_id"] as? Int else {
                        continue
                    }
                    
                    let factionId = (row["faction_id"] as? Int64).map(Int.init) ?? row["faction_id"] as? Int
                    
                    corporationIds.insert(corporationId)
                    if let factionId = factionId {
                        factionIds.insert(factionId)
                    }
                    corporationFactionMap[corporationId] = factionId
                }
                
                // 查询军团和势力信息
                var corporationInfos: [Int: (name: String, icon: String)] = [:]
                var factionInfos: [Int: String] = [:]
                
                if !corporationIds.isEmpty {
                    let corpQuery = """
                        SELECT corporation_id, name, icon_filename 
                        FROM npcCorporations 
                        WHERE corporation_id IN (\(corporationIds.sorted().map { String($0) }.joined(separator: ",")))
                    """
                    
                    if case let .success(corpRows) = DatabaseManager.shared.executeQuery(corpQuery) {
                        for row in corpRows {
                            guard let corpId = row["corporation_id"] as? Int,
                                  let name = row["name"] as? String else {
                                continue
                            }
                            
                            let iconFileName = (row["icon_filename"] as? String)?.isEmpty == true 
                                ? "corporations_default" 
                                : (row["icon_filename"] as? String ?? "corporations_default")
                            
                            corporationInfos[corpId] = (name, iconFileName)
                        }
                    }
                }
                
                if !factionIds.isEmpty {
                    let factionQuery = """
                        SELECT id, name 
                        FROM factions 
                        WHERE id IN (\(factionIds.sorted().map { String($0) }.joined(separator: ",")))
                    """
                    
                    if case let .success(factionRows) = DatabaseManager.shared.executeQuery(factionQuery) {
                        for row in factionRows {
                            guard let factionId = row["id"] as? Int,
                                  let name = row["name"] as? String else {
                                continue
                            }
                            
                            factionInfos[factionId] = name
                        }
                    }
                }
                
                // 构建供应商列表
                let supplierList = corporationIds.compactMap { corpId -> LPOfferSupplier? in
                    guard let corpInfo = corporationInfos[corpId] else { return nil }
                    
                    let factionId = corporationFactionMap[corpId] ?? nil
                    let factionName = factionId.flatMap { factionInfos[$0] }
                    
                    return LPOfferSupplier(
                        factionId: factionId,
                        factionName: factionName,
                        corporationId: corpId,
                        corporationName: corpInfo.name,
                        corporationIcon: corpInfo.icon
                    )
                }.sorted { $0.corporationName.localizedStandardCompare($1.corporationName) == .orderedAscending }
                
                await MainActor.run {
                    suppliers = supplierList
                    isLoading = false
                }
                
            }
        }
    }
}

struct SpecificItemOfferView: View {
    let corporationId: Int
    let corporationName: String
    let targetTypeId: Int
    let itemInfo: LPStoreItemInfo
    
    @State private var offers: [LPStoreOffer] = []
    @State private var requiredItemInfos: [Int: LPStoreItemInfo] = [:]
    @State private var isLoading = true
    @State private var error: Error?
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let error = error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error.localizedDescription)
                        .font(.headline)
                    Button(NSLocalizedString("Main_Setting_Reset", comment: "")) {
                        Task {
                            await loadOffers()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else if offers.isEmpty {
                Section {
                    NoDataSection()
                }
            } else {
                Section(NSLocalizedString("Main_LP_Store_section", comment: "")) {
                    ForEach(offers, id: \.offerId) { offer in
                        LPStoreOfferView(
                            offer: offer,
                            itemInfo: itemInfo,
                            requiredItemInfos: requiredItemInfos
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(itemInfo.name)
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await loadOffers(forceRefresh: true)
        }
        .task {
            await loadOffers()
        }
    }
    
    private func loadOffers(forceRefresh: Bool = false) async {
        isLoading = true
        error = nil
        
        do {
            // 1. 获取军团的所有offers
            let allOffers = try await LPStoreAPI.shared.fetchCorporationLPStoreOffers(
                corporationId: corporationId,
                forceRefresh: forceRefresh
            )
            
            // 2. 筛选出目标物品的offers
            let targetOffers = allOffers.filter { $0.typeId == targetTypeId }
            
            // 3. 只查询所需物品的信息（主物品信息已经有了）
            var requiredTypeIds = Set<Int>()
            for offer in targetOffers {
                requiredTypeIds.formUnion(offer.requiredItems.map { $0.typeId })
            }
            
            var infos: [Int: LPStoreItemInfo] = [:]
            
            // 4. 如果有所需物品，查询它们的信息
            if !requiredTypeIds.isEmpty {
                let query = """
                    SELECT type_id, name, en_name, zh_name, icon_filename, bpc_icon_filename, category_name, categoryID
                    FROM types
                    WHERE type_id IN (\(requiredTypeIds.sorted().map { String($0) }.joined(separator: ",")))
                """
                
                if case let .success(rows) = DatabaseManager.shared.executeQuery(query) {
                    for row in rows {
                        if let typeId = row["type_id"] as? Int,
                            let name = row["name"] as? String,
                            let enName = row["en_name"] as? String,
                            let zhName = row["zh_name"] as? String,
                            let iconFileName = row["icon_filename"] as? String,
                            let categoryName = row["category_name"] as? String,
                            let categoryId = row["categoryID"] as? Int
                        {
                            let bpcIconFileName = row["bpc_icon_filename"] as? String
                            let finalIconFileName: String
                            
                            if let bpcIcon = bpcIconFileName, !bpcIcon.isEmpty {
                                finalIconFileName = bpcIcon
                            } else {
                                finalIconFileName = iconFileName.isEmpty ? "not_found" : iconFileName
                            }
                            
                            infos[typeId] = LPStoreItemInfo(
                                name: name,
                                enName: enName,
                                zhName: zhName,
                                iconFileName: finalIconFileName,
                                categoryName: categoryName,
                                categoryId: categoryId
                            )
                        }
                    }
                }
            }
            
            await MainActor.run {
                offers = targetOffers.sorted { offer1, offer2 in
                    // 按LP成本排序，成本低的在前
                    if offer1.lpCost != offer2.lpCost {
                        return offer1.lpCost < offer2.lpCost
                    }
                    // LP成本相同时按ISK成本排序
                    return offer1.iskCost < offer2.iskCost
                }
                requiredItemInfos = infos
                isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.error = error
                isLoading = false
            }
        }
    }
}

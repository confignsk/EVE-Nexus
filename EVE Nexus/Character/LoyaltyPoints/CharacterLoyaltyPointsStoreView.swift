import SwiftUI

struct CharacterLoyaltyPointsStoreView: View {
    @State private var factions: [Faction] = []
    @State private var isLoading = true
    @State private var error: Error?
    @State private var hasLoadedData = false
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var loadingProgress: (current: Int, total: Int)?
    @State private var isForceRefresh = false
    @State private var loadingTask: Task<Void, Never>?
    @State private var lpSearchResults: [LPSearchResult] = []
    @State private var isSearchingItems = false
    @State private var shouldExecuteSearch = false

    private var searchResults: (factions: [Faction], corporations: [Corporation]) {
        // 如果搜索文本为空，直接返回空结果，不进行任何计算
        guard !debouncedSearchText.isEmpty else {
            return ([], [])
        }

        // 如果搜索文本太短，也返回空结果
        guard debouncedSearchText.count >= 2 else {
            return ([], [])
        }

        var matchedFactions: [Faction] = []
        var matchedCorporations: [Corporation] = []

        // 搜索势力名称和军团名称
        for faction in factions {
            if faction.name.localizedCaseInsensitiveContains(debouncedSearchText)
                || faction.enName.localizedCaseInsensitiveContains(debouncedSearchText)
                || faction.zhName.localizedCaseInsensitiveContains(debouncedSearchText)
            {
                matchedFactions.append(faction)
            }

            // 检查军团名称
            for corporation in faction.corporations {
                if corporation.name.localizedCaseInsensitiveContains(debouncedSearchText)
                    || corporation.enName.localizedCaseInsensitiveContains(debouncedSearchText)
                    || corporation.zhName.localizedCaseInsensitiveContains(debouncedSearchText)
                {
                    matchedCorporations.append(corporation)
                }
            }
        }

        // 对搜索结果进行本地化排序
        matchedFactions.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        matchedCorporations.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return (matchedFactions, matchedCorporations)
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            if let progress = loadingProgress {
                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "LP_Store_Loading_Progress", comment: ""
                                        ),
                                        progress.current, progress.total
                                    )
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                ProgressView()
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                } else if let error = error {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(error.localizedDescription)
                            .font(.headline)
                        Button(NSLocalizedString("Main_Setting_Reset", comment: "")) {
                            loadFactions()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    // 正常势力列表视图
                    Section(NSLocalizedString("Main_LP_Store_Factions", comment: "")) {
                        ForEach(factions) { faction in
                            NavigationLink(destination: FactionLPDetailView(faction: faction)) {
                                HStack {
                                    IconManager.shared.loadImage(for: faction.iconName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36)
                                    Text(faction.name)
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
        .navigationTitle(NSLocalizedString("Main_LP_Store", comment: ""))
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Search_Placeholder", comment: ""))
        )
        .onSubmit(of: .search) {
            if !searchText.isEmpty && searchText.count >= 2 {
                debouncedSearchText = searchText
                searchLPItems(searchText: searchText)
                shouldExecuteSearch = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    hasLoadedData = false
                    isForceRefresh = true
                    loadFactions()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        // 移除onChange监听器，现在使用专门的搜索按钮
        .onAppear {
            if !hasLoadedData {
                loadFactions()
            }
        }
        .onDisappear {
            // 取消正在进行的任务以防止信号量泄漏
            loadingTask?.cancel()
            searchTask?.cancel()
        }
        .navigationDestination(isPresented: $shouldExecuteSearch) {
            LPSearchResultsView(
                searchText: searchText,
                searchResults: searchResults,
                lpSearchResults: lpSearchResults
            )
        }
    }

    private func loadFactions() {
        if hasLoadedData, !isForceRefresh {
            return
        }

        // 取消之前的加载任务
        loadingTask?.cancel()

        isLoading = true
        error = nil
        loadingProgress = nil

        let query = """
            WITH faction_corps AS (
                SELECT 
                    f.id as faction_id,
                    f.name as faction_name,
                    f.en_name as faction_en_name,
                    f.zh_name as faction_zh_name,
                    f.iconName as faction_icon,
                    c.corporation_id,
                    c.name as corp_name,
                    c.en_name as corp_en_name,
                    c.zh_name as corp_zh_name,
                    c.faction_id,
                    c.icon_filename
                FROM factions f
                LEFT JOIN npcCorporations c ON f.id = c.faction_id
                ORDER BY f.name, c.name
            )
            SELECT * FROM faction_corps
        """

        let result = DatabaseManager.shared.executeQuery(query)
        switch result {
        case let .success(rows):
            var factionDict:
                [Int: (
                    name: String, enName: String, zhName: String, iconName: String,
                    corporations: [Corporation]
                )] = [:]
            var corporationIds: [Int] = []

            for row in rows {
                guard let factionId = row["faction_id"] as? Int,
                      let factionName = row["faction_name"] as? String,
                      let factionEnName = row["faction_en_name"] as? String,
                      let factionZhName = row["faction_zh_name"] as? String,
                      let factionIcon = row["faction_icon"] as? String
                else {
                    continue
                }

                if factionDict[factionId] == nil {
                    factionDict[factionId] = (
                        factionName, factionEnName, factionZhName, factionIcon, []
                    )
                }

                if let corporationId = row["corporation_id"] as? Int,
                   let corpName = row["corp_name"] as? String,
                   let corpEnName = row["corp_en_name"] as? String,
                   let corpZhName = row["corp_zh_name"] as? String,
                   let corpFactionId = row["faction_id"] as? Int,
                   let iconFileName = row["icon_filename"] as? String
                {
                    let corporation = Corporation(from: [
                        "corporation_id": corporationId,
                        "corp_name": corpName,
                        "corp_en_name": corpEnName,
                        "corp_zh_name": corpZhName,
                        "faction_id": corpFactionId,
                        "icon_filename": iconFileName,
                    ])
                    if let corp = corporation {
                        factionDict[factionId]?.corporations.append(corp)
                        corporationIds.append(corporationId)
                    }
                }
            }

            // 批量获取所有军团的LP商店数据
            loadingTask = Task(priority: .userInitiated) {
                do {
                    let progressCallback: (Int) -> Void = { completedCount in
                        Task { @MainActor in
                            loadingProgress = (completedCount, corporationIds.count)
                        }
                    }

                    let offersByCorp = try await LPStoreAPI.shared
                        .fetchMultipleCorporationsLPStoreOffers(
                            corporationIds: corporationIds,
                            maxConcurrent: 50,
                            progressCallback: progressCallback,
                            forceRefresh: isForceRefresh
                        )

                    // 检查任务是否被取消
                    if Task.isCancelled {
                        Logger.info("LP商店数据加载任务被取消")
                        return
                    }

                    // 过滤掉没有offer的军团
                    for (factionId, _) in factionDict {
                        factionDict[factionId]?.corporations.removeAll { corp in
                            offersByCorp[corp.id]?.isEmpty ?? true
                        }
                    }

                    // 过滤掉没有军团的势力
                    let filteredFactions = factionDict.compactMap { id, data -> Faction? in
                        guard !data.corporations.isEmpty else { return nil }
                        return Faction(
                            from: [
                                "faction_id": id,
                                "faction_name": data.name,
                                "faction_en_name": data.enName,
                                "faction_zh_name": data.zhName,
                                "faction_icon": data.iconName,
                            ], corporations: data.corporations
                        )
                    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

                    // 更新UI
                    await MainActor.run {
                        // 再次检查任务是否被取消
                        if !Task.isCancelled {
                            self.factions = filteredFactions
                            isLoading = false
                            hasLoadedData = true
                            loadingProgress = nil
                            isForceRefresh = false
                            loadingTask = nil
                        }
                    }

                    Logger.info("成功加载所有军团的LP商店数据")
                } catch {
                    if error is CancellationError {
                        Logger.info("LP商店数据加载任务被取消")
                    } else {
                        Logger.error("加载LP商店数据失败: \(error)")
                        await MainActor.run {
                            self.error = error
                            isLoading = false
                            loadingProgress = nil
                            loadingTask = nil
                        }
                    }
                }
            }
        case let .error(errorMessage):
            error = NSError(
                domain: "com.eve.nexus",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            )
            isLoading = false
            loadingProgress = nil
        }
    }

    private func searchLPItems(searchText: String) {
        isSearchingItems = true

        Task {
            do {
                // 1. 从CharacterDatabaseManager搜索物品
                let itemSearchQuery = """
                    SELECT type_id, offer_id, faction_id, corporation_id 
                    FROM LPStoreItemIndex 
                    WHERE type_name_zh LIKE '%\(searchText)%' OR type_name_en LIKE '%\(searchText)%'
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
                    guard
                        let typeId = (row["type_id"] as? Int64).map(Int.init) ?? row["type_id"]
                        as? Int,
                        let offerId = (row["offer_id"] as? Int64).map(Int.init) ?? row["offer_id"]
                        as? Int,
                        let corporationId = (row["corporation_id"] as? Int64).map(Int.init) ?? row[
                            "corporation_id"
                        ] as? Int
                    else {
                        continue
                    }

                    let factionId =
                        (row["faction_id"] as? Int64).map(Int.init) ?? row["faction_id"] as? Int

                    typeIds.insert(typeId)
                    searchOffers.append(
                        LPSearchOffer(
                            typeId: typeId,
                            typeName: "",
                            typeIcon: "",
                            offerId: offerId,
                            factionId: factionId,
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
                          let categoryId = row["categoryID"] as? Int
                    else {
                        continue
                    }

                    typeInfos[typeId] = (
                        name, iconFileName.isEmpty ? "not_found" : iconFileName, categoryId
                    )
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

                    if case let .success(categoryRows) = DatabaseManager.shared.executeQuery(
                        categoryQuery)
                    {
                        for row in categoryRows {
                            guard let categoryId = row["category_id"] as? Int,
                                  let name = row["name"] as? String,
                                  let iconFileName = row["icon_filename"] as? String
                            else {
                                continue
                            }

                            categoryInfos[categoryId] = (
                                name, iconFileName.isEmpty ? "not_found" : iconFileName
                            )
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
                let results = categoryOffersDict.compactMap {
                    categoryId, offers -> LPSearchResult? in
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
                }.sorted {
                    $0.categoryName.localizedStandardCompare($1.categoryName) == .orderedAscending
                }

                await MainActor.run {
                    isSearchingItems = false
                    lpSearchResults = results
                }
            }
        }
    }
}

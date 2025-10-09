import SwiftUI

// MARK: - 雇佣历史联盟缓存管理器

@MainActor
class EmploymentAllianceCache: ObservableObject {
    // 军团ID -> 联盟历史
    private var corpAllianceHistories: [Int: [CorporationAllianceHistory]] = [:]
    // 联盟ID -> 名称
    @Published var allianceNames: [Int: String] = [:]
    // 联盟ID -> 图标
    @Published var allianceIcons: [Int: UIImage] = [:]
    // 军团ID -> 图标（新增军团图标缓存）
    @Published var corporationIcons: [Int: UIImage] = [:]

    /// 获取军团在指定时间的联盟信息
    /// - Parameters:
    ///   - corporationId: 军团ID
    ///   - date: 时间点（雇佣结束时间）
    /// - Returns: 联盟ID和名称（如果有）
    func getCorpAlliance(corporationId: Int, date: Date) async -> (id: Int, name: String, icon: UIImage?)? {
        // 1. 获取军团联盟历史（从缓存或API）
        let allianceHistory = await getCorpAllianceHistory(corporationId: corporationId)

        // 2. 根据时间找到对应的联盟ID
        guard let allianceId = findAllianceAtDate(allianceHistory: allianceHistory, date: date) else {
            return nil
        }

        // 3. 获取联盟名称（从缓存或API）
        let name = await getAllianceName(allianceId: allianceId)

        // 4. 获取联盟图标（从缓存或API）
        let icon = await getAllianceIcon(allianceId: allianceId)

        return (id: allianceId, name: name, icon: icon)
    }

    /// 获取军团的联盟历史（带缓存）
    private func getCorpAllianceHistory(corporationId: Int) async -> [CorporationAllianceHistory] {
        // 检查缓存
        if let cached = corpAllianceHistories[corporationId] {
            return cached
        }

        // 从API获取
        if let history = try? await CorporationAPI.shared.fetchAllianceHistory(
            corporationId: corporationId)
        {
            corpAllianceHistories[corporationId] = history
            Logger.debug("缓存军团 \(corporationId) 的联盟历史，记录数: \(history.count)")
            return history
        }

        return []
    }

    /// 根据时间找到对应的联盟ID
    private func findAllianceAtDate(allianceHistory: [CorporationAllianceHistory], date: Date) -> Int? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        // 遍历联盟历史，找到最接近且不晚于指定时间的记录
        for record in allianceHistory {
            guard let recordDate = dateFormatter.date(from: record.start_date) else { continue }

            if recordDate <= date {
                return record.alliance_id
            }
        }

        return nil
    }

    /// 获取联盟名称（带缓存）
    private func getAllianceName(allianceId: Int) async -> String {
        // 检查缓存
        if let cached = allianceNames[allianceId] {
            return cached
        }

        // 从API获取
        if let namesMap = try? await UniverseAPI.shared.getNamesWithFallback(ids: [allianceId]),
           let name = namesMap[allianceId]?.name
        {
            allianceNames[allianceId] = name
            Logger.debug("缓存联盟 \(allianceId) 的名称: \(name)")
            return name
        }

        return "Unknown"
    }

    /// 获取联盟图标（带缓存）
    private func getAllianceIcon(allianceId: Int) async -> UIImage? {
        // 检查缓存
        if let cached = allianceIcons[allianceId] {
            return cached
        }

        // 从API获取
        if let icon = try? await AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId) {
            allianceIcons[allianceId] = icon
            Logger.debug("缓存联盟 \(allianceId) 的图标")
            return icon
        }

        return nil
    }

    /// 获取军团图标（带缓存）
    func getCorporationIcon(corporationId: Int) async -> UIImage? {
        // 检查缓存
        if let cached = corporationIcons[corporationId] {
            return cached
        }

        // 从API获取
        if let icon = try? await CorporationAPI.shared.fetchCorporationLogo(corporationId: corporationId) {
            corporationIcons[corporationId] = icon
            Logger.debug("缓存军团 \(corporationId) 的图标")
            return icon
        }

        return nil
    }

    /// 批量预加载多个军团的联盟历史
    /// - Parameters:
    ///   - corporationIds: 军团ID数组（按顺序）
    ///   - batchSize: 每批并发数
    ///   - onBatchComplete: 每批完成的回调
    func preloadCorpAllianceHistories(
        corporationIds: [Int],
        batchSize: Int = 5,
        onBatchComplete: (() -> Void)? = nil
    ) async {
        Logger.info("[+] 开始预加载 \(corporationIds.count) 个军团的联盟历史")

        for batchStart in stride(from: 0, to: corporationIds.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, corporationIds.count)
            let currentBatch = Array(corporationIds[batchStart ..< batchEnd])

            Logger.info("[+] 加载批次 \(batchStart / batchSize + 1)，军团数: \(currentBatch.count)")

            // 并发加载当前批次
            await withTaskGroup(of: Void.self) { group in
                for corpId in currentBatch {
                    group.addTask {
                        _ = await self.getCorpAllianceHistory(corporationId: corpId)
                    }
                }
            }

            // 批次完成回调
            onBatchComplete?()

            Logger.info("[+] 批次 \(batchStart / batchSize + 1) 加载完成")
        }

        Logger.info("[+] 所有军团联盟历史预加载完成")
    }
}

// 移除HTML标签的扩展
private extension String {
    func removeHTMLTags() -> String {
        // 移除所有HTML标签
        let text = replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )
        // 将HTML实体转换为对应字符
        return text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CharacterDetailView: View {
    let characterId: Int
    let character: EVECharacterInfo
    @State private var portrait: UIImage?
    @State private var characterInfo: CharacterPublicInfo?
    @State private var employmentHistory: [CharacterEmploymentHistory] = []
    @State private var corporationInfo: (name: String, icon: UIImage?)?
    @State private var allianceInfo: (name: String, icon: UIImage?)?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var selectedTab = 0 // 添加选项卡状态
    // 添加声望相关的状态
    @State private var personalStandings: [Int: Double] = [:]
    @State private var corpStandings: [Int: Double] = [:]
    @State private var allianceStandings: [Int: Double] = [:]
    @State private var myCorpInfo: (name: String, icon: UIImage?)?
    @State private var myAllianceInfo: (name: String, icon: UIImage?)?
    @State private var standingsLoaded = false
    @State private var factionInfo: (name: String, iconName: String)?
    @State private var corporationNamesCache: [Int: String] = [:]
    @State private var isLoadingCorpNames: Bool = false
    // 联盟缓存管理器
    @StateObject private var allianceCache = EmploymentAllianceCache()
    @State private var idCopied: Bool = false
    // NPC 军团 ID 集合
    @State private var npcCorporationIds: Set<Int> = []

    // 导航辅助方法
    @ViewBuilder
    private func navigationDestination(for id: Int, type: String) -> some View {
        switch type {
        case "corporation":
            CorporationDetailView(corporationId: id, character: character)
        case "alliance":
            AllianceDetailView(allianceId: id, character: character)
        default:
            EmptyView()
        }
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let error = error {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text(error.localizedDescription)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                }
            } else if let characterInfo = characterInfo {
                // 基本信息和组织信息合并到一个 Section
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        // 左侧头像
                        if let portrait = portrait {
                            Image(uiImage: portrait)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.primary, lineWidth: 1)
                                        .opacity(0.3)
                                )
                        }

                        // 右侧信息
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer()
                                .frame(height: 8)

                            // 人物名称
                            Text(characterInfo.name)
                                .font(.system(size: 20, weight: .semibold))
                                .lineLimit(1)

                            // 人物头衔
                            if let title = characterInfo.title, !title.isEmpty {
                                Text(title.removeHTMLTags())
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            } else {
                                Text("[\(NSLocalizedString("Main_No_Title", comment: ""))]")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .padding(.top, 2)
                            }

                            Spacer()
                                .frame(minHeight: 8)

                            // 军团信息
                            if let corpInfo = corporationInfo {
                                HStack(spacing: 8) {
                                    if let icon = corpInfo.icon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text(corpInfo.name)
                                        .font(.system(size: 14))
                                        .lineLimit(1)
                                }
                            }

                            // 联盟信息
                            HStack(spacing: 8) {
                                if let allianceInfo = allianceInfo, let icon = allianceInfo.icon {
                                    Image(uiImage: icon)
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    Text(allianceInfo.name)
                                        .font(.system(size: 14))
                                        .lineLimit(1)
                                } else {
                                    Image(systemName: "square.dashed")
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                        .foregroundColor(.gray)
                                    Text("\(NSLocalizedString("No Alliance", comment: ""))")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.top, 4)

                            Spacer()
                                .frame(height: 8)
                        }
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = characterInfo.name
                            } label: {
                                Label(
                                    NSLocalizedString("Misc_Copy_CharID", comment: ""),
                                    systemImage: "doc.on.doc"
                                )
                            }
                            if let title = characterInfo.title, !title.isEmpty {
                                Button {
                                    UIPasteboard.general.string = title.removeHTMLTags()
                                } label: {
                                    Label(
                                        NSLocalizedString("Misc_Copy_Char_Title", comment: ""),
                                        systemImage: "doc.on.doc"
                                    )
                                }
                            }

                            Divider()

                            NavigationLink {
                                navigationDestination(
                                    for: characterInfo.corporation_id, type: "corporation"
                                )
                            } label: {
                                Label(
                                    NSLocalizedString("View Corporation", comment: ""),
                                    systemImage: "info.circle"
                                )
                            }

                            if characterInfo.alliance_id != nil {
                                NavigationLink {
                                    navigationDestination(
                                        for: characterInfo.alliance_id!, type: "alliance"
                                    )
                                } label: {
                                    Label(
                                        NSLocalizedString("View Alliance", comment: ""),
                                        systemImage: "info.circle"
                                    )
                                }
                            }
                        }
                        .frame(height: 96) // 与头像等高
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Button {
                        UIPasteboard.general.string = String(characterId)
                        idCopied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            idCopied = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Spacer()
                            Image(systemName: idCopied ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                                .frame(width: 12, height: 12)
                            Text("ID: \(characterId)")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }

                // 添加外部链接按钮
                Section {
                    // 势力信息
                    if let faction = factionInfo {
                        HStack(spacing: 8) {
                            Text("\(NSLocalizedString("Character_Faction", comment: ""))")
                            Spacer()
                            IconManager.shared.loadImage(for: faction.iconName)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(faction.name)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Button(action: {
                        if let url = URL(string: "https://evewho.com/character/\(characterId)") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Text("Eve Who")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.blue)
                        }
                    }

                    Button(action: {
                        if let url = URL(string: "https://zkillboard.com/character/\(characterId)/") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Text("zKillboard")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.blue)
                        }
                    }
                }

                // 添加Picker组件
                Section {
                    Picker(selection: $selectedTab, label: Text("")) {
                        Text(NSLocalizedString("Standings", comment: ""))
                            .tag(0)
                        Text(NSLocalizedString("Employment History", comment: ""))
                            .tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    if selectedTab == 0 {
                        StandingsView(
                            characterId: characterId,
                            character: character,
                            targetCharacter: characterInfo,
                            corporationInfo: corporationInfo,
                            allianceInfo: allianceInfo,
                            personalStandings: personalStandings,
                            corpStandings: corpStandings,
                            allianceStandings: allianceStandings,
                            myCorpInfo: myCorpInfo,
                            myAllianceInfo: myAllianceInfo
                        )
                    } else if selectedTab == 1 {
                        EmploymentHistoryView(
                            history: employmentHistory,
                            corporationNamesCache: corporationNamesCache,
                            character: character,
                            isLoadingCorpNames: isLoadingCorpNames,
                            allianceCache: allianceCache,
                            npcCorporationIds: npcCorporationIds
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCharacterDetails()
        }
    }

    private func loadCharacterDetails() async {
        Logger.info("开始加载角色详细信息 - 角色ID: \(characterId)")
        isLoading = true
        error = nil

        do {
            // 并发加载所有需要的数据
            Logger.info("开始并发加载角色信息、头像和雇佣历史")
            async let characterInfoTask = CharacterAPI.shared.fetchCharacterPublicInfo(
                characterId: characterId, forceRefresh: true
            )
            async let portraitTask = CharacterAPI.shared.fetchCharacterPortrait(
                characterId: characterId, catchImage: false
            )
            async let historyTask = CharacterAPI.shared.fetchEmploymentHistory(
                characterId: characterId)

            // 等待所有数据加载完成
            let (info, portrait, history) = try await (characterInfoTask, portraitTask, historyTask)
            Logger.info("成功加载角色基本信息")
            Logger.info("雇佣历史记录数: \(history.count)")

            // 更新状态
            characterInfo = info
            self.portrait = portrait
            employmentHistory = history

            // 加载军团信息
            if let corpInfo = try? await CorporationAPI.shared.fetchCorporationInfo(
                corporationId: info.corporation_id)
            {
                Logger.info("成功加载军团信息: \(corpInfo.name)")
                let corpIcon = try? await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: info.corporation_id)
                corporationInfo = (name: corpInfo.name, icon: corpIcon)
            }

            // 加载联盟信息
            if let allianceId = info.alliance_id {
                let allianceNames = try? await UniverseAPI.shared.getNamesWithFallback(ids: [
                    allianceId,
                ])
                if let allianceName = allianceNames?[allianceId]?.name {
                    Logger.info("成功加载联盟信息: \(allianceName)")
                    let allianceIcon = try? await AllianceAPI.shared.fetchAllianceLogo(
                        allianceID: allianceId)
                    allianceInfo = (name: allianceName, icon: allianceIcon)
                }
            }

            // 加载势力信息
            if let factionId = info.faction_id {
                let query = "SELECT name, iconName FROM factions WHERE id = ?"
                if case let .success(rows) = DatabaseManager.shared.executeQuery(
                    query, parameters: [factionId]
                ),
                    let row = rows.first,
                    let name = row["name"] as? String,
                    let iconName = row["iconName"] as? String
                {
                    Logger.info("成功加载势力信息: \(name)")
                    factionInfo = (name: name, iconName: iconName)
                }
            }

            // 步骤1: 先批量加载所有军团名称（快速展示基本信息）
            await loadEmploymentCorporationNames()

            // 步骤2: 异步加载联盟信息（不阻塞UI显示）
            Task {
                await loadEmploymentAllianceData()
            }

            // 加载声望数据
            if !standingsLoaded {
                await loadStandings()
                standingsLoaded = true
            }

        } catch {
            Logger.error("加载角色详细信息失败: \(error)")
            self.error = error
        }

        isLoading = false
        Logger.info("角色详细信息加载完成")
    }

    /// 批量加载雇佣历史中所有军团的名称
    private func loadEmploymentCorporationNames() async {
        await MainActor.run {
            isLoadingCorpNames = true
        }

        // 收集所有军团ID
        let corporationIds = Set(employmentHistory.map { $0.corporation_id })

        // 从 npcCorporations 表查询，同时获取 ID 列表和本地化名称
        if !corporationIds.isEmpty {
            let placeholders = corporationIds.map { _ in "?" }.joined(separator: ",")
            let query = "SELECT corporation_id, name FROM npcCorporations WHERE corporation_id IN (\(placeholders))"

            if case let .success(rows) = DatabaseManager.shared.executeQuery(
                query,
                parameters: Array(corporationIds)
            ) {
                var npcIds = Set<Int>()
                var npcCount = 0

                for row in rows {
                    if let corpId = row["corporation_id"] as? Int,
                       let name = row["name"] as? String
                    {
                        npcIds.insert(corpId)
                        corporationNamesCache[corpId] = name
                        npcCount += 1
                    }
                }

                await MainActor.run {
                    self.npcCorporationIds = npcIds
                }

                Logger.info("从数据库加载 NPC 军团（本地化）成功，数量: \(npcCount)")

                // 获取玩家军团ID（不在 NPC 列表中的）
                let playerCorps = corporationIds.subtracting(npcIds)

                // 从 API 获取玩家军团名称
                if !playerCorps.isEmpty {
                    if let namesMap = try? await UniverseAPI.shared.getNamesWithFallback(
                        ids: Array(playerCorps))
                    {
                        await MainActor.run {
                            for (corpId, info) in namesMap {
                                corporationNamesCache[corpId] = info.name
                            }
                        }
                        Logger.info("从 API 加载玩家军团名称成功，数量: \(namesMap.count)")
                    }
                }
            }
        }

        await MainActor.run {
            isLoadingCorpNames = false
        }
    }

    /// 渐进式加载联盟数据
    private func loadEmploymentAllianceData() async {
        // 按雇佣历史顺序收集军团ID（去重）
        var orderedCorpIds: [Int] = []
        var seenCorpIds = Set<Int>()

        for record in employmentHistory {
            if !seenCorpIds.contains(record.corporation_id) {
                orderedCorpIds.append(record.corporation_id)
                seenCorpIds.insert(record.corporation_id)
            }
        }

        Logger.info("[+] 按雇佣顺序需要加载 \(orderedCorpIds.count) 个军团的联盟历史")

        // 渐进式预加载联盟历史（每批5个并发）
        await allianceCache.preloadCorpAllianceHistories(
            corporationIds: orderedCorpIds,
            batchSize: 5
        )
    }

    private func loadStandings() async {
        // 加载我的军团信息
        if let corpId = character.corporationId {
            if let corpInfo = try? await CorporationAPI.shared.fetchCorporationInfo(
                corporationId: corpId)
            {
                let corpIcon = try? await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: corpId)
                myCorpInfo = (name: corpInfo.name, icon: corpIcon)
            }
        }

        // 加载我的联盟信息
        if let allianceId = character.allianceId {
            let allianceNames = try? await UniverseAPI.shared.getNamesWithFallback(ids: [allianceId]
            )
            if let allianceName = allianceNames?[allianceId]?.name {
                let allianceIcon = try? await AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: allianceId)
                myAllianceInfo = (name: allianceName, icon: allianceIcon)
            }
        }

        // 加载个人声望
        if let contacts = try? await GetCharContacts.shared.fetchContacts(
            characterId: character.CharacterID)
        {
            for contact in contacts {
                personalStandings[contact.contact_id] = contact.standing
            }
        }

        // 加载军团声望
        if let corpId = character.corporationId,
           let contacts = try? await GetCorpContacts.shared.fetchContacts(
               characterId: character.CharacterID, corporationId: corpId
           )
        {
            for contact in contacts {
                corpStandings[contact.contact_id] = contact.standing
            }
        }

        // 加载联盟声望
        if let allianceId = character.allianceId,
           let contacts = try? await GetAllianceContacts.shared.fetchContacts(
               characterId: character.CharacterID, allianceId: allianceId
           )
        {
            for contact in contacts {
                allianceStandings[contact.contact_id] = contact.standing
            }
        }
    }

    // 声望行视图
    struct StandingRowView: View {
        let leftPortrait: (id: Int, type: MailRecipient.RecipientType)
        let rightPortrait: (id: Int, type: MailRecipient.RecipientType)
        let leftName: String
        let rightName: String
        let standing: Double?
        @State private var leftImage: UIImage?
        @State private var rightImage: UIImage?

        var body: some View {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // 左侧头像和名称
                    HStack(spacing: 6) {
                        Text(leftName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        if let image = leftImage {
                            Image(uiImage: image)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .cornerRadius(3)
                        } else {
                            Color.gray
                                .frame(width: 24, height: 24)
                                .cornerRadius(3)
                        }
                    }
                    .frame(width: geometry.size.width * 0.4, alignment: .trailing)

                    // 中间声望值
                    if let standing = standing {
                        Text(
                            standing > 0
                                ? "+\(String(format: "%.0f", standing))"
                                : standing < 0 ? "\(String(format: "%.0f", standing))" : "0"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(getStandingColor(standing: standing))
                        .frame(width: geometry.size.width * 0.2, alignment: .center)
                    } else {
                        Text("0")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: geometry.size.width * 0.2, alignment: .center)
                    }

                    // 右侧头像和名称
                    HStack(spacing: 6) {
                        if let image = rightImage {
                            Image(uiImage: image)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .cornerRadius(3)
                        } else {
                            Color.gray
                                .frame(width: 24, height: 24)
                                .cornerRadius(3)
                        }
                        Text(rightName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    .frame(width: geometry.size.width * 0.4, alignment: .leading)
                }
            }
            .frame(height: 32) // 设置固定高度以确保一致性
            .task {
                await loadImages()
            }
        }

        private func loadImages() async {
            // 加载左侧头像
            switch leftPortrait.type {
            case .character:
                leftImage = try? await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: leftPortrait.id)
            case .corporation:
                leftImage = try? await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: leftPortrait.id)
            case .alliance:
                leftImage = try? await AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: leftPortrait.id)
            default:
                break
            }

            // 加载右侧头像
            switch rightPortrait.type {
            case .character:
                rightImage = try? await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: rightPortrait.id, catchImage: false
                )
            case .corporation:
                rightImage = try? await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: rightPortrait.id)
            case .alliance:
                rightImage = try? await AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: rightPortrait.id)
            default:
                break
            }
        }

        private func getStandingColor(standing: Double) -> Color {
            switch standing {
            case 10.0:
                return Color.blue // 深蓝
            case 5.0 ..< 10.0:
                return Color.blue // 深蓝
            case 0.1 ..< 5.0:
                return Color(red: 0.3, green: 0.7, blue: 1.0) // 浅蓝
            case 0.0:
                return Color.secondary // 次要颜色
            case -5.0 ..< 0.0:
                return Color(red: 1.0, green: 0.5, blue: 0.0) // 橙红
            case -10.0 ... -5.0:
                return Color.red // 红色
            case ..<(-10.0):
                return Color.red // 红色
            default:
                return Color.secondary
            }
        }
    }

    // 声望详情视图
    struct StandingsView: View {
        let characterId: Int
        let character: EVECharacterInfo
        let targetCharacter: CharacterPublicInfo?
        let corporationInfo: (name: String, icon: UIImage?)?
        let allianceInfo: (name: String, icon: UIImage?)?
        let personalStandings: [Int: Double]
        let corpStandings: [Int: Double]
        let allianceStandings: [Int: Double]
        let myCorpInfo: (name: String, icon: UIImage?)?
        let myAllianceInfo: (name: String, icon: UIImage?)?

        var body: some View {
            VStack {
                if let targetCharacter = targetCharacter {
                    VStack(alignment: .leading, spacing: 4) {
                        // 个人声望
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("Personal Standings", comment: ""))
                                .font(.headline)
                                .padding(.bottom, 4)

                            // 我对目标角色
                            StandingRowView(
                                leftPortrait: (id: character.CharacterID, type: .character),
                                rightPortrait: (id: characterId, type: .character),
                                leftName: character.CharacterName,
                                rightName: targetCharacter.name,
                                standing: personalStandings[characterId]
                            )

                            // 我军团对目标角色
                            if let corpId = character.corporationId {
                                StandingRowView(
                                    leftPortrait: (id: corpId, type: .corporation),
                                    rightPortrait: (id: characterId, type: .character),
                                    leftName: myCorpInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    rightName: targetCharacter.name,
                                    standing: corpStandings[characterId]
                                )
                            }

                            // 我联盟对目标角色
                            if let allianceId = character.allianceId {
                                StandingRowView(
                                    leftPortrait: (id: allianceId, type: .alliance),
                                    rightPortrait: (id: characterId, type: .character),
                                    leftName: myAllianceInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    rightName: targetCharacter.name,
                                    standing: allianceStandings[characterId]
                                )
                            }
                        }

                        Divider()

                        // 军团声望
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Corporation Standings", comment: ""))
                                .font(.headline)
                                .padding(.bottom, 4)

                            // 我对目标军团
                            StandingRowView(
                                leftPortrait: (id: character.CharacterID, type: .character),
                                rightPortrait: (
                                    id: targetCharacter.corporation_id, type: .corporation
                                ),
                                leftName: character.CharacterName,
                                rightName: corporationInfo?.name
                                    ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                standing: personalStandings[targetCharacter.corporation_id]
                            )

                            // 我军团对目标军团
                            if let corpId = character.corporationId {
                                StandingRowView(
                                    leftPortrait: (id: corpId, type: .corporation),
                                    rightPortrait: (
                                        id: targetCharacter.corporation_id, type: .corporation
                                    ),
                                    leftName: myCorpInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    rightName: corporationInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    standing: corpStandings[targetCharacter.corporation_id]
                                )
                            }

                            // 我联盟对目标军团
                            if let allianceId = character.allianceId {
                                StandingRowView(
                                    leftPortrait: (id: allianceId, type: .alliance),
                                    rightPortrait: (
                                        id: targetCharacter.corporation_id, type: .corporation
                                    ),
                                    leftName: myAllianceInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    rightName: corporationInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    standing: allianceStandings[targetCharacter.corporation_id]
                                )
                            }
                        }

                        if let targetAllianceId = targetCharacter.alliance_id {
                            Divider()

                            // 联盟声望
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Alliance Standings", comment: ""))
                                    .font(.headline)
                                    .padding(.bottom, 4)

                                // 我对目标联盟
                                StandingRowView(
                                    leftPortrait: (id: character.CharacterID, type: .character),
                                    rightPortrait: (id: targetAllianceId, type: .alliance),
                                    leftName: character.CharacterName,
                                    rightName: allianceInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    standing: personalStandings[targetAllianceId]
                                )

                                // 我军团对目标联盟
                                if let corpId = character.corporationId {
                                    StandingRowView(
                                        leftPortrait: (id: corpId, type: .corporation),
                                        rightPortrait: (id: targetAllianceId, type: .alliance),
                                        leftName: myCorpInfo?.name
                                            ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                        rightName: allianceInfo?.name
                                            ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                        standing: corpStandings[targetAllianceId]
                                    )
                                }

                                // 我联盟对目标联盟
                                if let allianceId = character.allianceId {
                                    StandingRowView(
                                        leftPortrait: (id: allianceId, type: .alliance),
                                        rightPortrait: (id: targetAllianceId, type: .alliance),
                                        leftName: myAllianceInfo?.name
                                            ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                        rightName: allianceInfo?.name
                                            ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                        standing: allianceStandings[targetAllianceId]
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 雇佣历史视图
    struct EmploymentHistoryView: View {
        let history: [CharacterEmploymentHistory]
        let corporationNamesCache: [Int: String]
        let character: EVECharacterInfo
        let isLoadingCorpNames: Bool
        @ObservedObject var allianceCache: EmploymentAllianceCache
        let npcCorporationIds: Set<Int>

        var body: some View {
            if history.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
            } else {
                ForEach(Array(history.enumerated()), id: \.element.record_id) { index, record in
                    if let startDate = parseDate(record.start_date) {
                        let endDate = index > 0 ? parseDate(history[index - 1].start_date) : nil

                        VStack(spacing: 0) {
                            EmploymentHistoryRowView(
                                corporationId: record.corporation_id,
                                startDate: startDate,
                                endDate: endDate,
                                corporationNamesCache: corporationNamesCache,
                                character: character,
                                isLoadingCorpNames: isLoadingCorpNames,
                                allianceCache: allianceCache,
                                npcCorporationIds: npcCorporationIds
                            )
                        }
                    }
                }
            }
        }

        private func parseDate(_ dateString: String) -> Date? {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            return dateFormatter.date(from: dateString)
        }
    }

    // 雇佣历史行视图
    struct EmploymentHistoryRowView: View {
        let corporationId: Int
        let startDate: Date
        let endDate: Date?
        let corporationNamesCache: [Int: String]
        let character: EVECharacterInfo
        let isLoadingCorpNames: Bool
        @ObservedObject var allianceCache: EmploymentAllianceCache
        let npcCorporationIds: Set<Int>
        @State private var corporationIcon: UIImage?
        @State private var allianceInfo: (id: Int, name: String, icon: UIImage?)?
        @State private var isLoadingAlliance: Bool = false

        var body: some View {
            HStack(spacing: 6) {
                // 军团图标
                if let icon = corporationIcon {
                    Image(uiImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(3)
                } else {
                    Color.gray
                        .frame(width: 32, height: 32)
                        .cornerRadius(3)
                }

                // 右侧信息
                VStack(alignment: .leading, spacing: 2) {
                    // 军团名称
                    if isLoadingCorpNames {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(NSLocalizedString("Misc_Loading", comment: ""))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        HStack(spacing: 4) {
                            // NPC标签
                            if npcCorporationIds.contains(corporationId) {
                                Text("NPC")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color(red: 0.7, green: 0.5, blue: 0.9))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(red: 0.7, green: 0.5, blue: 0.9).opacity(0.15))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(Color(red: 0.7, green: 0.5, blue: 0.9).opacity(0.3), lineWidth: 0.5)
                                    )
                            }

                            Text(corporationNamesCache[corporationId] ?? NSLocalizedString("Unknown", comment: ""))
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                    }

                    // 联盟信息
                    if isLoadingAlliance {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                            Text(NSLocalizedString("Misc_Loading", comment: ""))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    } else if let alliance = allianceInfo {
                        HStack(spacing: 4) {
                            if let icon = alliance.icon {
                                Image(uiImage: icon)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .cornerRadius(2)
                            }
                            Text(alliance.name)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    // 时间信息
                    HStack(spacing: 4) {
                        Text(formatDateRange(start: startDate, end: endDate))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(formatDuration(start: startDate, end: endDate))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.clear)
            .contentShape(Rectangle())
            .contextMenu {
                NavigationLink {
                    CorporationDetailView(corporationId: corporationId, character: character)
                } label: {
                    Label(
                        NSLocalizedString("View Corporation", comment: ""),
                        systemImage: "info.circle"
                    )
                }

                // 如果有联盟信息，显示跳转按钮
                if let alliance = allianceInfo {
                    NavigationLink {
                        AllianceDetailView(allianceId: alliance.id, character: character)
                    } label: {
                        Label(
                            NSLocalizedString("View Alliance", comment: ""),
                            systemImage: "info.circle"
                        )
                    }
                }
            }
            .task {
                await loadData()
            }
        }

        private func loadData() async {
            // 先检查缓存中是否有军团图标
            if let cachedIcon = allianceCache.corporationIcons[corporationId] {
                corporationIcon = cachedIcon
            } else {
                // 如果缓存中没有，加载并缓存
                let corpIcon = await allianceCache.getCorporationIcon(corporationId: corporationId)
                corporationIcon = corpIcon
            }

            // 加载联盟信息
            // 如果 endDate 为 nil（当前仍在该军团），使用当前时间
            let queryDate = endDate ?? Date()

            isLoadingAlliance = true

            if let alliance = await allianceCache.getCorpAlliance(
                corporationId: corporationId,
                date: queryDate
            ) {
                allianceInfo = alliance
            }

            isLoadingAlliance = false
        }

        private func formatDateRange(start: Date, end: Date?) -> String {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy.MM.dd"
            let startStr = dateFormatter.string(from: start)

            if let end = end {
                let endStr = dateFormatter.string(from: end)
                return "\(startStr) - \(endStr)"
            } else {
                return "\(startStr) - \(NSLocalizedString("Misc_Now", comment: "now"))"
            }
        }

        private func formatDuration(start: Date, end: Date?) -> String {
            let components = Calendar.current.dateComponents(
                [.day, .hour], from: start, to: end ?? Date()
            )
            let days = components.day ?? 0
            let hours = components.hour ?? 0

            if days == 0 {
                return
                    "(\(String(format: NSLocalizedString("Time_Hours_Long", comment: ""), hours)))"
            } else {
                return "(\(String(format: NSLocalizedString("Time_Days_Long", comment: ""), days)))"
            }
        }
    }
}
